"""Read fresh screenshot candidates through the Mac's existing iPhone pairing."""
import ctypes as c
import hashlib
import json
import re
import struct
import sys
import time
import uuid

POINTER = c.c_void_p
STRINGS = c.POINTER(c.c_char_p)
MAX_BYTES = 16 * 1024 * 1024
MAX_PREVIEW_BYTES = 512 * 1024
MISSING = 8


class MediaError(Exception):
    pass


def require(code):
    if code:
        raise MediaError(code)


def load_library():
    for prefix in ("/opt/homebrew", "/usr/local"):
        try:
            lib = c.CDLL(prefix + "/lib/libimobiledevice-1.0.dylib")
            break
        except OSError:
            continue
    else:
        raise SystemExit("libimobiledevice is required")
    signatures = {
        "idevice_new_with_options": [c.POINTER(POINTER), c.c_char_p, c.c_int],
        "idevice_free": [POINTER],
        "afc_client_start_service": [POINTER, c.POINTER(POINTER), c.c_char_p],
        "afc_client_free": [POINTER],
        "afc_read_directory": [POINTER, c.c_char_p, c.POINTER(STRINGS)],
        "afc_get_file_info": [POINTER, c.c_char_p, c.POINTER(STRINGS)],
        "afc_dictionary_free": [STRINGS],
        "afc_file_open": [POINTER, c.c_char_p, c.c_int, c.POINTER(c.c_uint64)],
        "afc_file_close": [POINTER, c.c_uint64],
        "afc_file_read": [POINTER, c.c_uint64, POINTER, c.c_uint32, c.POINTER(c.c_uint32)],
    }
    for name, args in signatures.items():
        getattr(lib, name).argtypes = args
    return lib


class MediaConnection:
    def __init__(self, lib, udid, mode):
        self.lib = lib
        self.device = POINTER()
        self.client = POINTER()
        require(lib.idevice_new_with_options(c.byref(self.device), udid, mode))
        try:
            require(lib.afc_client_start_service(self.device, c.byref(self.client), b"SnapBridge"))
        except MediaError:
            self.close()
            raise

    def close(self):
        if self.client:
            self.lib.afc_client_free(self.client)
        if self.device:
            self.lib.idevice_free(self.device)

    def strings(self, method, path):
        values = STRINGS()
        code = method(self.client, path, c.byref(values))
        if code == MISSING:
            return []
        require(code)
        try:
            result = []
            i = 0
            while values[i] is not None:
                result.append(values[i])
                i += 1
            return result
        finally:
            self.lib.afc_dictionary_free(values)

    def names(self, path):
        return self.strings(self.lib.afc_read_directory, path)

    def info(self, path):
        values = iter(self.strings(self.lib.afc_get_file_info, path))
        return dict(zip(values, values))

    def read(self, path, size):
        handle = c.c_uint64()
        require(self.lib.afc_file_open(self.client, path, 1, c.byref(handle)))
        try:
            buffer = c.create_string_buffer(min(size, 4 * 1024 * 1024))
            count = c.c_uint32()
            data = bytearray()
            while len(data) < size:
                require(self.lib.afc_file_read(
                    self.client, handle, buffer, min(size - len(data), len(buffer)), c.byref(count)
                ))
                if not count.value:
                    break
                data.extend(buffer[:count.value])
            return data if len(data) == size else None
        finally:
            self.lib.afc_file_close(self.client, handle)


def watch(lib, udid, since):
    seen = set()
    initialized = set()
    mode = 2
    connection = None
    folders = []
    active_folder = None
    refresh_at = check_usb_at = 0.0
    sweep_index = 0
    delay = 1
    while True:
        try:
            if connection is None:
                for candidate in (2, 4):
                    try:
                        connection = MediaConnection(lib, udid, candidate)
                        mode = candidate
                        break
                    except MediaError:
                        continue
                if connection is None:
                    raise MediaError("iPhone unavailable")
                refresh_at = 0
                check_usb_at = time.monotonic() + 8
            now = time.monotonic()
            if mode == 4 and now >= check_usb_at:
                check_usb_at = now + 8
                usb = POINTER()
                if lib.idevice_new_with_options(c.byref(usb), udid, 2) == 0:
                    lib.idevice_free(usb)
                    try:
                        replacement = MediaConnection(lib, udid, 2)
                    except MediaError:
                        pass
                    else:
                        connection.close()
                        connection = replacement
                        mode = 2
            active_folders = [active_folder] if active_folder in folders else folders[-1:]
            if now >= refresh_at:
                updated = sorted(name for name in connection.names(b"DCIM")
                                 if re.fullmatch(rb"[0-9]{3}APPLE", name))
                if updated and updated[-1] != (folders[-1] if folders else None):
                    active_folder = updated[-1]
                folders = updated
                active_folders = [active_folder] if active_folder in folders else folders[-1:]
                if folders:
                    other = folders[sweep_index % len(folders)]
                    if other not in active_folders:
                        active_folders.append(other)
                    sweep_index += 1
                refresh_at = now + 8
            candidates = []
            for folder in active_folders:
                directory = b"DCIM/" + folder
                paths = sorted(
                    directory + b"/" + name for name in connection.names(directory)
                    if re.fullmatch(rb"IMG_[0-9]+\.PNG", name, re.IGNORECASE)
                )
                if folder not in initialized:
                    # Skip the existing library, allowing for a burst taken during startup.
                    seen.update(paths[:-8])
                    initialized.add(folder)
                new_paths = [path for path in paths if path not in seen]
                candidates.extend(new_paths)
            fresh = []
            for path in reversed(sorted(candidates)):
                info = connection.info(path)
                if not info:
                    continue
                size = int(info.get(b"st_size", b"0"))
                modified = int(info.get(b"st_mtime", b"0"))
                if not modified or not size:
                    continue
                if modified >= since and size <= MAX_BYTES:
                    fresh.append((modified, path, size))
                else:
                    seen.add(path)
            for modified, path, size in sorted(fresh):
                key = hashlib.sha256(udid + path + str(modified).encode()).digest()[:16]
                shot_id = str(uuid.UUID(bytes=key))
                transport = "USB" if mode == 2 else "Wi-Fi"
                if mode == 4:
                    preview = screenshot_preview(connection, path, size)
                    if preview:
                        send_frame(shot_id, modified, transport, preview, preview=True)
                started = time.monotonic()
                data = connection.read(path, size)
                if data is None or not data.endswith(b"IEND\xaeB\x60\x82"):
                    continue
                seen.add(path)
                # iOS records this marker in the EXIF block. The receiver verifies it with ImageIO.
                if b"Screenshot" not in data:
                    continue
                active_folder = path.split(b"/")[1]
                send_frame(shot_id, modified, transport, data,
                           read_ms=(time.monotonic() - started) * 1000)
            heartbeat()
            delay = 1
            time.sleep(0.12 if mode == 2 else 0.25)
        except MediaError:
            if connection is not None:
                connection.close()
                connection = None
            heartbeat()
            time.sleep(delay)
            delay = min(delay * 2, 8)


def screenshot_preview(connection, path, original_size):
    # iOS may create a thumbnail after the original becomes visible. Fall through
    # to the original immediately if the thumbnail has not appeared.
    try:
        prefix = connection.read(path, min(4096, original_size))
        if not prefix or not prefix.startswith(b"\x89PNG\r\n\x1a\n"):
            return None
        offset = 8
        while offset + 12 <= len(prefix):
            length, kind = struct.unpack_from(">I4s", prefix, offset)
            end = offset + 12 + length
            if end > len(prefix):
                return None
            if kind == b"eXIf" and b"Screenshot" in prefix[offset + 8:end - 4]:
                thumbnail = b"PhotoData/Thumbnails/V2/" + path + b"/5005.JPG"
                size = int(connection.info(thumbnail).get(b"st_size", b"0"))
                if 0 < size <= MAX_PREVIEW_BYTES:
                    data = connection.read(thumbnail, size)
                    if data and data.startswith(b"\xff\xd8\xff") and data.endswith(b"\xff\xd9"):
                        return data
                return None
            offset = end
    except MediaError as error:
        if error.args != (MISSING,):
            raise
    return None


def send_frame(shot_id, modified, transport, data, *, preview=False, read_ms=0):
    header = json.dumps({
        "id": shot_id,
        "date": modified / 1_000_000_000,
        "size": len(data),
        "readMilliseconds": read_ms,
        "transport": transport,
        "preview": preview,
    }).encode("ascii")
    sys.stdout.buffer.write(struct.pack(">I", len(header)) + header)
    sys.stdout.buffer.write(data)
    sys.stdout.buffer.flush()


def heartbeat():
    sys.stdout.buffer.write(b"\0\0\0\0")
    sys.stdout.buffer.flush()


if __name__ == "__main__":
    # The parent supplies the exact paired phone and the time this Mac receiver started.
    watch(load_library(), sys.argv[1].encode(), int(sys.argv[2]))

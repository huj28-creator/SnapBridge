/* One-time trusted USB Wi-Fi-sync setup; no developer image or UI control. */
#include <stdio.h>
#include <stdint.h>
#include <string.h>
#include <libimobiledevice/libimobiledevice.h>
#include <libimobiledevice/lockdown.h>
#include <plist/plist.h>

static int enabled(lockdownd_client_t client) {
    plist_t value = NULL;
    uint8_t result = 0;
    if (lockdownd_get_value(client, "com.apple.mobile.wireless_lockdown",
                           "EnableWifiConnections", &value) == LOCKDOWN_E_SUCCESS && value) {
        plist_get_bool_val(value, &result);
        plist_free(value);
    }
    return result != 0;
}

int main(int argc, char **argv) {
    if (argc < 2 || argc > 3 || (argc == 3 && strcmp(argv[2], "--enable"))) {
        fprintf(stderr, "Usage: enable-wifi DEVICE_UDID [--enable]\n");
        return 2;
    }
    idevice_t device = NULL;
    lockdownd_client_t client = NULL;
    int code = 1;
    if (idevice_new_with_options(&device, argv[1], IDEVICE_LOOKUP_USBMUX) != IDEVICE_E_SUCCESS) goto done;
    if (lockdownd_client_new_with_handshake(device, &client, "SnapBridge WiFi Setup") != LOCKDOWN_E_SUCCESS) goto done;
    int before = enabled(client);
    if (argc == 3 && !before) {
        plist_t value = plist_new_bool(1);
        lockdownd_error_t result = lockdownd_set_value(client, "com.apple.mobile.wireless_lockdown", "EnableWifiConnections", value);
        plist_free(value);
        if (result != LOCKDOWN_E_SUCCESS) goto done;
    }
    int after = enabled(client);
    printf("{\"wifi_enabled_before\":%s,\"wifi_enabled\":%s}\n", before ? "true" : "false", after ? "true" : "false");
    code = argc == 3 && !after ? 1 : 0;
done:
    if (client) lockdownd_client_free(client);
    if (device) idevice_free(device);
    if (code) fprintf(stderr, "Trusted USB Wi-Fi setup did not complete.\n");
    return code;
}

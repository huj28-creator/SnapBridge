// Named app identity for Local Network privacy. Routine runs open no windows.
import AppKit
import Foundation
import Network

final class RenewalRunner: NSObject, NSApplicationDelegate {
    let home = Bundle.main.bundleURL.deletingLastPathComponent()
    var worker: Process?
    var browser: NWBrowser?
    var timer: DispatchSourceTimer?
    var probing = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let args = Array(CommandLine.arguments.dropFirst())
        if args.contains("--run-renewal") {
            let process = Process()
            process.executableURL = URL(fileURLWithPath:"/usr/bin/python3")
            process.arguments = [home.appendingPathComponent("renew.py").path] + args.filter { $0 != "--run-renewal" }
            process.currentDirectoryURL = home
            for (name,isError) in [("runner-output.log",false),("runner-error.log",true)] {
                let path = home.appendingPathComponent(name)
                FileManager.default.createFile(atPath:path.path,contents:Data(),attributes:[.posixPermissions:0o600])
                if let file = try? FileHandle(forWritingTo:path) {
                    if isError { process.standardError = file } else { process.standardOutput = file }
                }
            }
            process.terminationHandler = { process in DispatchQueue.main.async { exit(process.terminationStatus) } }
            worker = process
            do { try process.run() }
            catch { fputs("Cannot start renewal: \(error)\n",stderr);exit(1) }
        } else if args.isEmpty || args == ["--check-wifi"] {
            // Explicit first-time permission check, never the scheduled path.
            let browser = NWBrowser(for:.bonjour(type:"_apple-mobdev2._tcp",domain:nil),using:.tcp)
            self.browser = browser;browser.start(queue:.main)
            let timer = DispatchSource.makeTimerSource(queue:.main)
            timer.schedule(deadline:.now()+2,repeating:3)
            timer.setEventHandler { [weak self] in self?.probe() }
            self.timer = timer;timer.resume()
            DispatchQueue.main.asyncAfter(deadline:.now()+60) { [weak self] in
                self?.worker?.terminate();self?.browser?.cancel();self?.timer?.cancel();exit(1)
            }
        } else { fputs("Use --run-renewal or --check-wifi.\n",stderr);exit(2) }
    }

    func probe() {
        guard !probing else { return };probing = true
        DispatchQueue.global(qos:.utility).async { [self] in
            do {
                let config = try JSONSerialization.jsonObject(with:Data(contentsOf:home.appendingPathComponent("config.json"))) as! [String:Any]
                let process = Process();process.executableURL = URL(fileURLWithPath:"/opt/homebrew/bin/idevicepair")
                process.arguments = ["-u",config["device_udid"] as! String,"-n","validate"]
                let output = Pipe();process.standardOutput = output;process.standardError = output
                try process.run();worker = process
                DispatchQueue.global().asyncAfter(deadline:.now()+12) { if process.isRunning { process.terminate() } }
                _ = output.fileHandleForReading.readDataToEndOfFile();process.waitUntilExit()
                let success = process.terminationStatus == 0
                let report:[String:Any] = ["wireless_pairing_valid":success,"exit_code":process.terminationStatus]
                let path = home.appendingPathComponent("network-permission-check.json")
                try JSONSerialization.data(withJSONObject:report).write(to:path,options:.atomic)
                try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:path.path)
                DispatchQueue.main.async { [self] in
                    probing = false
                    if success { browser?.cancel();timer?.cancel();exit(0) }
                }
            } catch { DispatchQueue.main.async { [self] in probing = false } }
        }
    }
}
let app = NSApplication.shared
let delegate = RenewalRunner()
app.delegate = delegate
app.run()

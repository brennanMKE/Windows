// shotd — a screenshot agent that runs inside the user's Aqua session.
//
// WHY THIS EXISTS: screencapture cannot work over SSH. An SSH session has no
// window server connection, and more importantly macOS attributes the attempt
// to the SSH ancestry, which holds no Screen Recording grant and cannot be
// prompted headlessly. `sudo launchctl asuser <uid> screencapture` fails too --
// entering the session is not enough, because the grant is the blocker.
//
// So: a LaunchAgent with LimitLoadToSessionType=Aqua. launchd starts it inside
// the GUI session, it becomes its own responsible process, and Screen Recording
// is granted to THIS BINARY once, by hand, at the machine.
//
// WHY A COMPILED BINARY AND NOT A SCRIPT: a TCC grant attaches to the
// executable, which for a script is the interpreter. Granting Screen Recording
// to /usr/bin/python3 or /bin/bash would let anything on the host capture the
// screen. Homelab/docs/joe-full-disk-access.md already makes this argument for
// Full Disk Access; this is the same trade, decided the same way.
//
// PROTOCOL (deliberately files, not a port -- no listener, no auth to get
// wrong, and requests serialize naturally):
//
//   request   ~/.shotd/requests/<id>.json      {"op":"list"}
//                                              {"op":"capture","bundleID":"..."}
//   response  ~/.shotd/requests/<id>.response.json
//   images    ~/.shotd/shots/<id>.png
//
// Both sides write to a .tmp path and rename, so neither can ever read a
// half-written file.

import AppKit
import CoreGraphics
import Foundation

let home = FileManager.default.homeDirectoryForCurrentUser
let root = home.appendingPathComponent(".shotd")
let requestsDir = root.appendingPathComponent("requests")
let shotsDir = root.appendingPathComponent("shots")

// Images are evidence, not archives. Anything older than this is swept on each
// pass so a long-running agent cannot fill the boot disk.
let shotRetention: TimeInterval = 24 * 60 * 60

struct WindowInfo: Codable {
    let windowID: UInt32
    let pid: Int32
    let bundleID: String
    let appName: String
    let title: String
    let width: Int
    let height: Int
    let onScreen: Bool
}

func log(_ message: String) {
    let stamp = ISO8601DateFormatter().string(from: Date())
    FileHandle.standardError.write("\(stamp) shotd: \(message)\n".data(using: .utf8)!)
}

func listWindows() -> [WindowInfo] {
    let opts: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
    guard let raw = CGWindowListCopyWindowInfo(opts, kCGNullWindowID) as? [[String: Any]] else {
        return []
    }
    var out: [WindowInfo] = []
    for w in raw {
        guard let wid = w[kCGWindowNumber as String] as? UInt32,
              let pid = w[kCGWindowOwnerPID as String] as? Int32 else { continue }
        let bounds = w[kCGWindowBounds as String] as? [String: Any] ?? [:]
        let width = Int((bounds["Width"] as? Double) ?? 0)
        let height = Int((bounds["Height"] as? Double) ?? 0)

        // Skip the 1x1 and zero-size helper windows every app leaves lying
        // around; they are never what anyone meant to capture.
        if width < 40 || height < 40 { continue }

        let app = NSRunningApplication(processIdentifier: pid)
        out.append(WindowInfo(
            windowID: wid,
            pid: pid,
            bundleID: app?.bundleIdentifier ?? "<none>",
            appName: (w[kCGWindowOwnerName as String] as? String) ?? app?.localizedName ?? "<unknown>",
            title: (w[kCGWindowName as String] as? String) ?? "",
            width: width,
            height: height,
            onScreen: (w[kCGWindowIsOnscreen as String] as? Bool) ?? false
        ))
    }
    // Largest first: for an app with a main window and a palette, the main
    // window is almost always the intended target.
    return out.sorted { ($0.width * $0.height) > ($1.width * $1.height) }
}

func capture(windowID: UInt32, to path: URL) throws {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
    // -l <id>  that window only
    // -o       no window shadow, so the PNG is the window and nothing else
    // -x       no shutter sound
    p.arguments = ["-l", String(windowID), "-o", "-x", path.path]
    let err = Pipe()
    p.standardError = err
    try p.run()
    p.waitUntilExit()
    let stderrText = String(data: err.fileHandleForReading.readDataToEndOfFile(),
                            encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    if p.terminationStatus != 0 {
        throw Failure("screencapture exited \(p.terminationStatus): \(stderrText.isEmpty ? "no output" : stderrText)")
    }
    guard FileManager.default.fileExists(atPath: path.path) else {
        // screencapture reports success and writes nothing when the window has
        // gone away between listing and capture. Say so plainly.
        throw Failure("screencapture wrote no file; the window may have closed")
    }
}

struct Failure: Error, CustomStringConvertible {
    let description: String
    init(_ d: String) { description = d }
}

func respond(_ id: String, _ payload: [String: Any]) {
    let target = requestsDir.appendingPathComponent("\(id).response.json")
    let tmp = requestsDir.appendingPathComponent("\(id).response.json.tmp")
    do {
        let data = try JSONSerialization.data(withJSONObject: payload,
                                              options: [.prettyPrinted, .sortedKeys])
        try data.write(to: tmp)
        _ = try? FileManager.default.removeItem(at: target)
        try FileManager.default.moveItem(at: tmp, to: target)
    } catch {
        log("could not write response for \(id): \(error)")
    }
}

func encode<T: Encodable>(_ v: T) -> Any {
    guard let d = try? JSONEncoder().encode(v),
          let o = try? JSONSerialization.jsonObject(with: d) else { return [] }
    return o
}

func handle(_ requestURL: URL) {
    let id = requestURL.deletingPathExtension().lastPathComponent
    defer { try? FileManager.default.removeItem(at: requestURL) }

    guard let data = try? Data(contentsOf: requestURL),
          let req = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
        respond(id, ["ok": false, "error": "request is not valid JSON"])
        return
    }

    let op = (req["op"] as? String) ?? "capture"
    let windows = listWindows()

    if op == "list" {
        respond(id, ["ok": true, "op": "list", "windows": encode(windows)])
        log("list -> \(windows.count) windows")
        return
    }

    guard op == "capture" else {
        respond(id, ["ok": false, "error": "unknown op '\(op)'; expected list or capture"])
        return
    }

    // Resolve the target. An explicit windowID wins; otherwise bundleID, then
    // an optional title substring to disambiguate.
    var candidates = windows
    if let wid = req["windowID"] as? UInt32 ?? (req["windowID"] as? Int).map(UInt32.init) {
        candidates = windows.filter { $0.windowID == wid }
    } else if let bundle = req["bundleID"] as? String {
        candidates = windows.filter { $0.bundleID == bundle }
        if let needle = req["title"] as? String, !needle.isEmpty {
            let narrowed = candidates.filter { $0.title.localizedCaseInsensitiveContains(needle) }
            if !narrowed.isEmpty { candidates = narrowed }
        }
    } else {
        respond(id, ["ok": false, "error": "capture needs windowID or bundleID"])
        return
    }

    guard let target = candidates.first else {
        // Hand back what IS on screen. A failed match is nearly always a
        // bundle ID typo or an app that is not running, and the list is the
        // answer to both.
        respond(id, ["ok": false,
                     "error": "no matching window on screen",
                     "windows": encode(windows)])
        log("capture -> no match for \(req)")
        return
    }

    let out = shotsDir.appendingPathComponent("\(id).png")
    do {
        try capture(windowID: target.windowID, to: out)
        let attrs = try? FileManager.default.attributesOfItem(atPath: out.path)
        let bytes = (attrs?[.size] as? Int) ?? 0
        respond(id, ["ok": true, "op": "capture", "path": out.path,
                     "bytes": bytes, "window": encode(target),
                     "matched": candidates.count])
        log("capture -> \(target.bundleID) window \(target.windowID) -> \(out.lastPathComponent)")
    } catch {
        respond(id, ["ok": false, "error": "\(error)", "window": encode(target)])
        log("capture failed: \(error)")
    }
}

func sweepOldShots() {
    guard let items = try? FileManager.default.contentsOfDirectory(
        at: shotsDir, includingPropertiesForKeys: [.contentModificationDateKey]) else { return }
    let cutoff = Date().addingTimeInterval(-shotRetention)
    for item in items {
        guard let mod = try? item.resourceValues(forKeys: [.contentModificationDateKey])
                .contentModificationDate else { continue }
        if mod < cutoff { try? FileManager.default.removeItem(at: item) }
    }
}

// --- main ---

for dir in [requestsDir, shotsDir] {
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true,
                                            attributes: [.posixPermissions: 0o700])
}

if CommandLine.arguments.contains("--selftest") {
    // Proves the grant without needing a request round trip. Run this straight
    // after granting Screen Recording, from the console on this machine.
    let ws = listWindows()
    print("windows on screen: \(ws.count)")
    guard let first = ws.first else { print("no windows to capture"); exit(1) }
    let out = shotsDir.appendingPathComponent("selftest.png")
    do {
        try capture(windowID: first.windowID, to: out)
        print("captured \(first.bundleID) -> \(out.path)")
        exit(0)
    } catch {
        print("FAILED: \(error)")
        print("If this says 'could not create image', Screen Recording is not")
        print("granted to this binary. System Settings > Privacy & Security >")
        print("Screen & System Audio Recording.")
        exit(1)
    }
}

log("started; watching \(requestsDir.path)")
var sweepCounter = 0
while true {
    if let items = try? FileManager.default.contentsOfDirectory(atPath: requestsDir.path) {
        for name in items.sorted() where name.hasSuffix(".json") && !name.hasSuffix(".response.json") {
            handle(requestsDir.appendingPathComponent(name))
        }
    }
    sweepCounter += 1
    if sweepCounter >= 600 { sweepOldShots(); sweepCounter = 0 }  // ~every 5 min
    Thread.sleep(forTimeInterval: 0.5)
}

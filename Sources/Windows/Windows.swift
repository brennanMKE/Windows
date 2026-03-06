import Foundation
import CoreGraphics
import AppKit
import ArgumentParser

struct WindowInfo {
    let windowID: UInt32
    let pid: pid_t
    let bundleID: String
    let appName: String
    let title: String
}

@main
struct Windows: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "List macOS windows with their process IDs and bundle identifiers",
        version: "1.0.0"
    )

    @Flag(name: .shortAndLong, help: "Output as JSON")
    var json: Bool = false

    mutating func run() throws {
        guard let raw = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID)
                as? [[String: Any]] else {
            fputs("Error: Failed to get window list\n", stderr)
            throw ExitCode.failure
        }

        var windows: [WindowInfo] = []

        for w in raw {
            guard let windowID = w[kCGWindowNumber as String] as? UInt32,
                  let pid = w[kCGWindowOwnerPID as String] as? pid_t else {
                continue
            }

            let app = NSRunningApplication(processIdentifier: pid)
            let bundleID = app?.bundleIdentifier ?? "<none>"
            let ownerName = (w[kCGWindowOwnerName as String] as? String) ?? "<unknown>"
            let title = (w[kCGWindowName as String] as? String) ?? ""

            let window = WindowInfo(
                windowID: windowID,
                pid: pid,
                bundleID: bundleID,
                appName: ownerName,
                title: title
            )
            windows.append(window)
        }

        if json {
            outputJSON(windows)
        } else {
            outputText(windows)
        }
    }

    private func outputText(_ windows: [WindowInfo]) {
        print("WindowID\tPID\tBundleID\tAppName\tTitle")
        for window in windows {
            print("\(window.windowID)\t\(window.pid)\t\(window.bundleID)\t\(window.appName)\t\(window.title)")
        }
    }

    private func outputJSON(_ windows: [WindowInfo]) {
        let jsonArray = windows.map { window in
            [
                "windowID": window.windowID,
                "pid": window.pid,
                "bundleID": window.bundleID,
                "appName": window.appName,
                "title": window.title
            ] as [String: Any]
        }

        if let jsonData = try? JSONSerialization.data(withJSONObject: jsonArray, options: .prettyPrinted),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            print(jsonString)
        }
    }
}

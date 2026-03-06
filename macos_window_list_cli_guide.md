# Listing macOS Windows with Bundle IDs Using a Swift CLI

This guide shows how to build a **command‑line tool in Swift** that
lists the currently visible windows on macOS and prints the related
**application bundle identifier**.

The tool uses macOS native APIs:

-   **CoreGraphics (Quartz Window Services)** -- to retrieve the window
    list
-   **AppKit `NSRunningApplication`** -- to map window PIDs to bundle
    identifiers

------------------------------------------------------------------------

# Overview

macOS exposes window information through the Core Graphics API:

`CGWindowListCopyWindowInfo`

This returns metadata about all windows currently known to the window
server, including:

-   Window ID
-   Window title
-   Owning process ID (PID)
-   Application name
-   Window bounds

Once the PID is known, we can resolve it to the running application and
obtain its bundle ID.

------------------------------------------------------------------------

# Prerequisites

You need:

-   macOS
-   Xcode command line tools installed

Install CLI tools if needed:

``` bash
xcode-select --install
```

------------------------------------------------------------------------

# Swift Implementation

Create a file named:

    listwindows.swift

Paste the following code:

``` swift
import Foundation
import CoreGraphics
import AppKit

guard let raw = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID)
        as? [[String: Any]] else {
    fputs("Failed to get window list\n", stderr)
    exit(1)
}

for w in raw {
    guard let windowID = w[kCGWindowNumber as String] as? UInt32,
          let pid = w[kCGWindowOwnerPID as String] as? pid_t else {
        continue
    }

    let app = NSRunningApplication(processIdentifier: pid)
    let bundleID = app?.bundleIdentifier ?? "<none>"
    let ownerName = (w[kCGWindowOwnerName as String] as? String) ?? "<unknown>"
    let title = (w[kCGWindowName as String] as? String) ?? ""

    print("\(windowID)\t\(pid)\t\(bundleID)\t\(ownerName)\t\(title)")
}
```

------------------------------------------------------------------------

# Compile the CLI Tool

Run:

``` bash
swiftc listwindows.swift -o listwindows
```

This produces an executable named:

    listwindows

------------------------------------------------------------------------

# Run the Tool

Execute:

``` bash
./listwindows
```

Example output:

    12345   5521    com.apple.Safari   Safari   OpenAI
    12346   6123    com.apple.Terminal Terminal bash
    12347   7021    com.apple.finder   Finder   Desktop

Output columns:

  Column      Description
  ----------- --------------------------------
  Window ID   CoreGraphics window identifier
  PID         Owning process ID
  Bundle ID   Application bundle identifier
  App Name    Human-readable app name
  Title       Window title

------------------------------------------------------------------------

# Using the Window ID

The returned window ID can be used with the macOS screenshot tool:

``` bash
screencapture -l <windowid> screenshot.png
```

Example:

``` bash
screencapture -l 12345 safari.png
```

------------------------------------------------------------------------

# Notes

### Not every window has a bundle ID

Some windows belong to system components such as:

-   Dock
-   WindowServer
-   Notification Center
-   menu bar overlays

These may return `<none>`.

### Window titles may be empty

Applications sometimes hide window titles from the window server.

### Permissions

Normally this API works without special permissions. However:

-   capturing window images requires **Screen Recording permission**
-   some titles may be hidden without it

------------------------------------------------------------------------

# Optional Improvements

Possible enhancements:

-   Output JSON
-   Filter by bundle identifier
-   Filter by visible windows
-   Sort by application
-   Automatically screenshot matching windows

Example JSON output approach:

    ./listwindows | jq

------------------------------------------------------------------------

# Summary

Using only native macOS APIs you can:

1.  Query the window server
2.  Retrieve window IDs and owning PIDs
3.  Map PIDs to running applications
4.  Extract bundle identifiers
5.  Use window IDs for automation such as screenshots

This makes it easy to build CLI automation tools for macOS window
management.

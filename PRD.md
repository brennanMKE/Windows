# Product Requirements Document: macOS Window List CLI

## Overview
A command-line tool for macOS that lists all visible windows with their process ID (PID), application name, and bundle identifier.

## Objectives
- Provide a lightweight, native macOS CLI tool for querying window information
- Enable automation and scripting around macOS window management
- No external dependencies beyond standard macOS APIs

## Core Features

### Feature 1: List All Visible Windows
**Description:** Query the macOS window server and display all visible windows.

**Requirements:**
- Use CoreGraphics (`CGWindowListCopyWindowInfo`) to retrieve window list
- Display windows with the following information:
  - Window ID (CoreGraphics identifier)
  - Process ID (PID)
  - Bundle Identifier (e.g., `com.apple.Safari`)
  - Application Name (human-readable)
  - Window Title

**Output Format:**
Tab-separated columns:
```
WindowID    PID    BundleID              AppName    Title
12345       5521   com.apple.Safari      Safari     OpenAI
12346       6123   com.apple.Terminal    Terminal   bash
```

### Feature 2: Use Native macOS APIs
**Requirements:**
- CoreGraphics (Quartz Window Services) for window enumeration
- AppKit `NSRunningApplication` for PID-to-bundle-ID mapping
- No third-party dependencies

## Technical Specifications

### Implementation Language
- Swift (single file executable)
- Compiled with `swiftc`

### Required Imports
```swift
import Foundation
import CoreGraphics
import AppKit
```

### Error Handling
- Exit with error code 1 if window list retrieval fails
- Handle missing bundle IDs gracefully (display `<none>`)
- Handle missing titles gracefully (display empty string)

### Performance Considerations
- Single-pass iteration through window list
- Minimal memory footprint
- Instantaneous query time

## Success Criteria
- [ ] Executable compiles without errors
- [ ] Runs without requiring elevated privileges (normal API usage)
- [ ] Lists all visible windows with complete information
- [ ] Handles edge cases (system windows, missing data)
- [ ] Output is easily parseable (tab-separated)

## Future Enhancements (Not in Initial Release)
- JSON output format
- Filtering by bundle ID
- Filtering by visible windows only
- Sorting options (by app, by PID, etc.)
- Integration with `screencapture` for automated screenshots
- Man page/help documentation

## Constraints & Notes
- **Permissions:** Window title access may be restricted without Screen Recording permission
- **Compatibility:** macOS 10.13+ (AppKit + CoreGraphics availability)
- **Limitations:** Some system windows (Dock, WindowServer, Notification Center) may return `<none>` for bundle ID

## Deliverables
1. `listwindows.swift` - Source code
2. `listwindows` - Compiled executable
3. `README.md` - Build and usage instructions

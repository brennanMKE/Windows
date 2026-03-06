# Windows

A lightweight command-line tool for macOS that lists all visible windows with their process ID, application name, and bundle identifier.

## Features

- Query the macOS window server to list all visible windows
- Display window ID, process ID, bundle identifier, application name, and window title
- Tab-separated output (default) for easy parsing with grep and other CLI tools
- JSON output format with `--json` flag
- No external dependencies beyond standard macOS APIs
- Fast and minimal resource footprint

## Prerequisites

- macOS 10.13 or later
- Swift 5.8+ (or Xcode command line tools)

Install Xcode command line tools if needed:

```bash
xcode-select --install
```

## Installation

### Quick Install

Run the install script to build and install to `~/bin/`:

```bash
chmod +x install.sh
./install.sh
```

Ensure `~/bin/` is in your PATH. Add to `~/.zshrc` or `~/.bash_profile` if needed:

```bash
export PATH="$HOME/bin:$PATH"
```

### Manual Build

Build the project:

```bash
swift build -c release
```

Copy the executable to your bin folder:

```bash
cp .build/release/windows ~/bin/
chmod +x ~/bin/windows
```

## Usage

### List All Windows (Default)

```bash
windows
```

Output:
```
WindowID	PID	BundleID	AppName	Title
12345	5521	com.apple.Safari	Safari	OpenAI
12346	6123	com.apple.Terminal	Terminal	bash
12347	7021	com.apple.finder	Finder	Desktop
```

### Filter by Bundle ID

```bash
windows | grep com.apple.Safari
```

### JSON Output

```bash
windows --json
```

Output:
```json
[
  {
    "windowID" : 12345,
    "pid" : 5521,
    "bundleID" : "com.apple.Safari",
    "appName" : "Safari",
    "title" : "OpenAI"
  },
  ...
]
```

### Using jq with JSON Output

Filter windows by bundle ID:

```bash
windows --json | jq '.[] | select(.bundleID == "com.apple.Safari")'
```

Get window IDs for a specific application:

```bash
windows --json | jq '.[] | select(.appName == "Terminal") | .windowID'
```

Count windows by application:

```bash
windows --json | jq 'group_by(.appName) | map({app: .[0].appName, count: length})'
```

### Screenshot a Specific Window

Get the window ID and use it with `screencapture`:

```bash
# Find the window ID for Safari
WINDOW_ID=$(windows | grep com.apple.Safari | head -1 | awk '{print $1}')

# Take a screenshot of just that window
screencapture -l $WINDOW_ID safari_screenshot.png
```

Or in one command:

```bash
screencapture -l $(windows --json | jq '.[] | select(.appName == "Safari") | .windowID' | head -1) safari.png
```

### Get Help

```bash
windows --help
```

### Show Version

```bash
windows --version
```

## Output Format

The default text output is tab-separated with the following columns:

| Column   | Description                        |
| -------- | ---------------------------------- |
| WindowID | CoreGraphics window identifier     |
| PID      | Process ID of the window owner     |
| BundleID | Application bundle identifier      |
| AppName  | Human-readable application name    |
| Title    | Window title text                  |

## Notes

- Some system windows (Dock, WindowServer, Notification Center) may have `<none>` as the bundle ID
- Window titles may be empty for some applications
- Requires no elevated privileges for normal operation
- Screen Recording permission may be needed to access window titles in some cases

## Use Cases

- Automation scripts for macOS window management
- Finding window IDs for use with `screencapture -l <windowid>`
- Filtering windows by application bundle ID
- Integration with other CLI tools via piping

## Building from Source

Clone the repository and build:

```bash
swift build -c release
```

Run tests (if available):

```bash
swift test
```

## License

MIT License - see LICENSE file for details

## Technical Details

The tool uses native macOS APIs:

- **CoreGraphics** (`CGWindowListCopyWindowInfo`) - to retrieve window information from the window server
- **AppKit** (`NSRunningApplication`) - to map process IDs to bundle identifiers

This approach requires no third-party dependencies and works directly with macOS native interfaces.

# Windows

Two macOS command-line tools built from one Swift package:

- **`windows`** — lists visible windows with their window ID, process ID, application name, and bundle identifier.
- **`shotd`** — a screenshot agent that runs inside the user's GUI session, so a window can be captured from another machine over SSH. See [shotd](#shotd--remote-screenshot-agent).

## Features

- Query the macOS window server to list all visible windows
- Display window ID, process ID, bundle identifier, application name, and window title
- Filter by bundle identifier (`--bundle-id`) or app name (`--app-name`)
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

### Filter by Bundle ID or App Name

Filtering is built in — no need to pipe through `grep`:

```bash
windows --bundle-id com.apple.Safari     # or -b
windows --app-name safari                # or -a, case-insensitive
```

Both combine with `--json`:

```bash
windows -b com.apple.Safari --json
```

Piping still works if you prefer it:

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

Works **only in a GUI session that holds Screen Recording permission**. Over
SSH it fails with `could not create image from display` — see
[shotd](#shotd--remote-screenshot-agent) for why, and for the remote case.

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

## `shotd` — remote screenshot agent

`screencapture` cannot work over SSH. An SSH session has no window server
connection, and macOS attributes the attempt to the SSH ancestry, which holds no
Screen Recording grant and **cannot be prompted headlessly**. `sudo launchctl
asuser <uid> screencapture` fails identically — the grant is the blocker, not
the session.

`shotd` is a long-running agent installed as a **LaunchAgent with
`LimitLoadToSessionType = Aqua`**. launchd starts it when you log in at the
console, so it runs inside the GUI session and is its own responsible process
for TCC. Screen Recording is granted to that binary once, by hand, and remote
captures work from then on.

It is a compiled binary rather than a script on purpose: a TCC grant attaches to
the *executable*, which for a script is the interpreter — granting Screen
Recording to `/usr/bin/python3` would let anything on the host capture the
screen.

### Protocol

Files, not a port: no listener, no authentication to get wrong, and requests
serialize naturally. Both sides write a `.tmp` path and rename, so neither can
read a half-written file.

```
request   ~/.shotd/requests/<id>.json            {"op":"list"}
                                                 {"op":"capture","bundleID":"..."}
response  ~/.shotd/requests/<id>.response.json
images    ~/.shotd/shots/<id>.png                (swept after 24h)
```

`capture` accepts `windowID`, or `bundleID` optionally narrowed by `title`.
Among several matches the largest window wins. Windows under 40×40 are ignored —
a menu bar app's status-item window is never the intended target and cannot be
imaged anyway.

### Self-test

Proves the grant without a round trip:

```bash
shotd --selftest
```

### Setup

`install.sh` installs the binary but does **not** load it, because loading needs
a plist and the grant needs a human at the machine. Full instructions, the
client (`shot`), and the security analysis live in the Homelab repo:
`docs/screenshots.md`.

> **Security:** a granted `shotd` can capture *any* window on that host, and
> anything able to write to `~/.shotd/requests` as that user can ask it to.
> Read `docs/screenshots.md` before granting on a machine that runs
> chat-reachable agents.

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

`shotd` uses the same two APIs to resolve a window, then shells out to
`/usr/sbin/screencapture -l <windowID> -o -x` for the image itself.

This approach requires no third-party dependencies and works directly with macOS native interfaces.

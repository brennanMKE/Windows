#!/bin/zsh

set -e

# Build in release mode
echo "Building windows CLI..."
swift build -c release

# Check if build succeeded
if [ ! -f ".build/release/windows" ]; then
    echo "Error: Build failed or binary not found" >&2
    exit 1
fi

# Create bin directory if it doesn't exist
mkdir -p ~/bin

# Copy executable
cp ./.build/release/windows ~/bin/
chmod +x ~/bin/windows

# shotd is the screenshot agent. It is installed here but NOT loaded: it only
# works as a LaunchAgent inside an Aqua session, and it needs Screen Recording
# granted to this exact binary. See Homelab/joe/screenshots.md.
if [ -f ".build/release/shotd" ]; then
    cp ./.build/release/shotd ~/bin/
    chmod +x ~/bin/shotd
    echo "✓ Successfully installed shotd to ~/bin/shotd"
    echo "  (agent only -- see Homelab/joe/screenshots.md to load and grant it)"
fi

echo "✓ Successfully installed windows to ~/bin/windows"
echo "✓ Run 'windows --help' to get started"

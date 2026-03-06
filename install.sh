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

echo "✓ Successfully installed windows to ~/bin/windows"
echo "✓ Run 'windows --help' to get started"

#!/bin/sh
# Builds fm-code in release mode and installs it.
# Usage: ./install.sh            installs to /usr/local/bin
#        INSTALL_DIR=~/bin ./install.sh
set -eu

INSTALL_DIR="${INSTALL_DIR:-/usr/local/bin}"
cd "$(dirname "$0")"

echo "Building fm-code (release)..."
swift build -c release

mkdir -p "$INSTALL_DIR" 2>/dev/null || sudo mkdir -p "$INSTALL_DIR"
if [ -w "$INSTALL_DIR" ]; then
    install -m 755 .build/release/fm-code "$INSTALL_DIR/fm-code"
else
    echo "Installing to $INSTALL_DIR needs sudo."
    sudo install -m 755 .build/release/fm-code "$INSTALL_DIR/fm-code"
fi
echo "Installed $INSTALL_DIR/fm-code"

# From a clean git checkout, remember the installed commit so `fm-code update` knows it's current.
if commit=$(git rev-parse HEAD 2>/dev/null) && [ -z "$(git status --porcelain 2>/dev/null)" ]; then
    "$INSTALL_DIR/fm-code" update --mark-installed "$commit" 2>/dev/null || true
fi

case ":$PATH:" in
    *":$INSTALL_DIR:"*) ;;
    *) echo "Note: $INSTALL_DIR is not on your PATH — add it to use 'fm-code' directly." ;;
esac

echo
"$INSTALL_DIR/fm-code" doctor || true

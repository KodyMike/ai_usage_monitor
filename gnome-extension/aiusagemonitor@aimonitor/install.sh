#!/usr/bin/env bash

EXTENSION_UUID="aiusagemonitor@aimonitor"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="$HOME/.local/share/gnome-shell/extensions/$EXTENSION_UUID"

echo "Installing $EXTENSION_UUID..."

gnome-extensions disable "$EXTENSION_UUID" 2>/dev/null || true

rm -rf "$INSTALL_DIR"
cp -r "$SCRIPT_DIR" "$INSTALL_DIR"
glib-compile-schemas "$INSTALL_DIR/schemas/"

echo "Done. Please log out and back in to activate the extension."

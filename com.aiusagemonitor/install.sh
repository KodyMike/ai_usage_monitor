#!/bin/bash
# Install the AI Usage Monitor plasmoid into KDE Plasma.
# Run this from the com.aiusagemonitor directory or its parent.

WIDGET_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WIDGET_ID="com.aiusagemonitor"
ICON_NAME="com.aiusagemonitor"
ICON_SRC="$WIDGET_DIR/contents/images/plasmoid_mainview.png"
ICON_DEST_DIR="$HOME/.local/share/icons/hicolor/256x256/apps"
ICON_DEST="$ICON_DEST_DIR/$ICON_NAME.png"

echo "Installing $WIDGET_ID from $WIDGET_DIR..."

# Remove any previous installation
kpackagetool6 --type Plasma/Applet --remove "$WIDGET_ID" 2>/dev/null || true

# Install fresh
kpackagetool6 --type Plasma/Applet --install "$WIDGET_DIR"

if [ $? -eq 0 ]; then
    # Install custom icon so Widget Explorer shows this plasmoid image
    if [ -f "$ICON_SRC" ]; then
        mkdir -p "$ICON_DEST_DIR"
        cp -f "$ICON_SRC" "$ICON_DEST"
        # Refresh icon/services cache if tools exist
        command -v kbuildsycoca6 >/dev/null 2>&1 && kbuildsycoca6 --noincremental >/dev/null 2>&1 || true
    fi

    echo ""
    echo "Installed successfully!"
    echo ""
    echo "To add to your panel:"
    echo "  Right-click the panel → Add Widgets → search 'AI Usage Monitor'"
    echo ""
    echo "To preview in a window:"
    echo "  plasmawindowed $WIDGET_ID"
else
    echo "Installation failed. Check the output above."
    exit 1
fi

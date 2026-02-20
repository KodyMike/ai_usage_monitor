#!/bin/bash

# Upgrade AI Usage Monitor KDE Widget
# This script upgrades the widget and restarts plasmashell

echo "Upgrading AI Usage Monitor..."

# Get the directory where this script is located
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Upgrade the widget
kpackagetool6 --type Plasma/Applet --upgrade "$DIR"

if [ $? -eq 0 ]; then
    echo "✓ Widget upgraded successfully"
    echo ""
    echo "Restarting Plasma Shell to apply changes..."
    kquitapp6 plasmashell && kstart plasmashell &
    echo "✓ Plasma Shell restarted"
    echo ""
    echo "The widget should now show the updated version."
else
    echo "✗ Upgrade failed. You may need to install first:"
    echo "  ./install.sh"
fi

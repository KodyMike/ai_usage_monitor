# AI Usage Monitor

[![KDE Store](https://img.shields.io/badge/KDE_Store-Available-1D99F3?style=for-the-badge&logo=kde&logoColor=white)](https://www.pling.com/p/2348728/)

Cross-platform desktop widget/extension to monitor usage for:

- **Claude Code** - Track your 5-hour and 7-day usage limits
- **OpenAI Codex** - Monitor your Codex API quotas
- **Gemini CLI** - Keep track of Gemini model usage across all available models

Shows a compact panel indicator and a full popup with limits, usage percentages, and reset times.

## Platform Support

| Platform | Status | Version | Notes |
|----------|--------|---------|-------|
| ![KDE](https://img.shields.io/badge/KDE_Plasma-1D99F3?style=flat&logo=kde&logoColor=white) | ✅ **Working** | Plasma 6+ | Full support with KDE Frameworks 6 |
| ![GNOME](https://img.shields.io/badge/GNOME-4A86CF?style=flat&logo=gnome&logoColor=white) | ✅ **Working** | GNOME 45+ | Full support for GNOME Shell 45, 46, 47 |

---

## Installation

### KDE Plasma 6

**Easy install from KDE Store:** [Download on Pling.com](https://www.pling.com/p/2348728/)

Or see [KDE Plasma Installation](#kde-plasma-installation) below for manual installation.

### GNOME Shell

See [`gnome-extension/README.md`](gnome-extension/README.md) for detailed GNOME installation instructions.

Quick install for GNOME:
```bash
cd gnome-extension/aiusagemonitor@aimonitor
./install.sh
```

---

## Features

- **Multi-tool monitoring** - Track Claude, Codex, and Gemini in one place
- **Automatic token refresh** - Gemini tokens refresh automatically when expired (NEW!)
- **Smart retry logic** - Up to 3 retry attempts with detailed error reporting
- **Color-coded usage** - Visual indicators: 🟢 Green → 🟡 Yellow → 🟠 Orange → 🔴 Red
- **Fully configurable** - Show/hide tools, adjust refresh rates, customize display
- **Privacy-first** - No sensitive data exposed, all credentials stay local
- **Detailed metrics** - See usage percentages, reset times, and model information

---

# KDE Plasma Installation

## Install (Plasma 6)

### From KDE Store (Recommended)

1. **Install from Discover (GUI):**
   - Open System Settings → Appearance → Get New... → Download New Plasma Widgets
   - Search for "AI Usage Monitor"
   - Click Install

2. **Or visit the KDE Store:** [https://www.pling.com/p/2348728/](https://www.pling.com/p/2348728/)

### Quick install (this repo)
```bash
cd com.aiusagemonitor
./install.sh
```

### Manual install
```bash
kpackagetool6 --type Plasma/Applet --install /full/path/to/com.aiusagemonitor
```

### Upgrade after changes
```bash
kpackagetool6 --type Plasma/Applet --upgrade /full/path/to/com.aiusagemonitor
```

### Remove
```bash
kpackagetool6 --type Plasma/Applet --remove com.aiusagemonitor
```

## Add to panel
1. Right-click panel -> `Add Widgets...`
2. Search: `AI Usage Monitor`
3. Drag it to the panel

If it does not appear immediately, restart Plasma shell:
```bash
kquitapp6 plasmashell && kstart6 plasmashell
```

## Install from local `.plasmoid` file
1. In Plasma Widget Explorer: `Get New Widgets` -> `Install Widget From Local File...`
2. Select your `.plasmoid` package.

Build a `.plasmoid` package from this project:
```bash
cd com.aiusagemonitor
bsdtar --format zip -cf ../ai-usage-monitor.plasmoid .
```

Install the `.plasmoid` file from terminal:
```bash
kpackagetool6 --type Plasma/Applet --install /full/path/to/ai-usage-monitor.plasmoid
```

Notes:
- Keep `metadata.json` `Id` stable: `com.aiusagemonitor`
- Keep `"X-Plasma-API-Minimum-Version": "6.0"` for Plasma 6 visibility.

## Official references
- Plasma widget setup and packaging: https://develop.kde.org/docs/plasma/widget/setup/
- Installing plasmoids (Get New Widgets / local file): https://userbase.kde.org/Plasma/Installing_Plasmoids
- KDE Store creator/publishing FAQ: https://store.kde.org/faq-pling

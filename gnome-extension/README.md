# AI Usage Monitor — GNOME Shell Extension

Monitor Claude Code, OpenAI Codex, and Gemini CLI usage directly from your GNOME panel.

## Install

### From GNOME Extensions (recommended)

Install via [extensions.gnome.org](https://extensions.gnome.org) — no logout required.

### Manual install

```bash
cd aiusagemonitor@aimonitor
bash install.sh
```

Then log out and back in — the extension will be active automatically.

## Requirements

- GNOME Shell 45–49
- Python 3
- One or more AI tools: Claude Code, OpenAI Codex, Gemini CLI

## Configuration

Open preferences via the Extensions app or:

```bash
gnome-extensions prefs aiusagemonitor@aimonitor
```

**Settings:**
- **Refresh interval** — how often to pull usage data (20s to 30min)
- **Panel tool** — which AI tool to show in the panel bar
- **Display style** — ring + %, ring only, or % only
- **Visible tools** — show/hide each tool in the popup

## Uninstall

```bash
gnome-extensions disable aiusagemonitor@aimonitor
rm -rf ~/.local/share/gnome-shell/extensions/aiusagemonitor@aimonitor
```

## Troubleshooting

**Extension not showing:**
```bash
gnome-extensions list --enabled | grep aiusagemonitor
journalctl -f -o cat /usr/bin/gnome-shell
```

**Data not updating — test the fetch script manually:**
```bash
python3 ~/.local/share/gnome-shell/extensions/aiusagemonitor@aimonitor/scripts/fetch_all_usage.py
```

**Gemini auth errors:**
```bash
gemini auth login
```

## License

GPL-3.0-or-later

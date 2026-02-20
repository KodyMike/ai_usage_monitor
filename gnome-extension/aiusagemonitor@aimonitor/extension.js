import GLib from 'gi://GLib';
import GObject from 'gi://GObject';
import Gio from 'gi://Gio';
import St from 'gi://St';
import Clutter from 'gi://Clutter';
import Pango from 'gi://Pango';
import Cairo from 'cairo';
import * as Main from 'resource:///org/gnome/shell/ui/main.js';
import * as PanelMenu from 'resource:///org/gnome/shell/ui/panelMenu.js';
import * as PopupMenu from 'resource:///org/gnome/shell/ui/popupMenu.js';
import {Extension} from 'resource:///org/gnome/shell/extensions/extension.js';

const PANEL_RING_SIZE = 16;
const PANEL_RING_STROKE = 2.2;
const POPUP_BAR_WIDTH = 150;

function menuItemActor(item) {
    return item.actor ?? item;
}

const AIUsageIndicator = GObject.registerClass(
class AIUsageIndicator extends PanelMenu.Button {
    _init(extensionPath, settings, extension) {
        super._init(0.0, 'AI Usage Monitor', false);

        this._extensionPath = extensionPath;
        this._settings = settings;
        this._extension = extension;
        this._timeoutId = null;
        this._cancellable = null;
        this._claudeData = {};
        this._codexData = {};
        this._geminiData = {};
        this._isLoading = true;
        this._panelPct = 0;
        this._panelColor = '#22c55e';

        // Pre-load tool icons for the panel bar
        this._toolGIcons = {};
        for (let [tool, file] of [['claude', 'claude-icon-22.png'], ['codex', 'codex_icon.png'], ['gemini', 'gemini_icon.png']]) {
            try {
                this._toolGIcons[tool] = Gio.icon_new_for_string(`${extensionPath}/images/${file}`);
            } catch (_e) {}
        }

        // Panel bar widgets
        let box = new St.BoxLayout({style_class: 'panel-status-menu-box'});

        this._panelToolIcon = new St.Icon({
            icon_size: 14,
            y_align: Clutter.ActorAlign.CENTER,
            style_class: 'ai-usage-panel-tool-icon',
        });

        this._panelRing = new St.DrawingArea({
            width: PANEL_RING_SIZE,
            height: PANEL_RING_SIZE,
            y_align: Clutter.ActorAlign.CENTER,
            style_class: 'ai-usage-panel-ring',
        });
        this._panelRing.connect('repaint', this._drawPanelRing.bind(this));

        this._panelLabel = new St.Label({
            text: '...',
            y_align: Clutter.ActorAlign.CENTER,
            style_class: 'ai-usage-panel-label',
        });

        box.add_child(this._panelToolIcon);
        box.add_child(this._panelRing);
        box.add_child(this._panelLabel);
        this.add_child(box);

        this._buildMenu();

        this._settingsChangedId = this._settings.connect('changed', this._onSettingsChanged.bind(this));

        this._refresh();
        this._scheduleRefresh();
    }

    _buildMenu() {
        this.menu.removeAll();

        let headerBox = new St.BoxLayout({vertical: false, style_class: 'ai-usage-menu-header'});
        let headerLabel = new St.Label({
            text: 'AI Usage Monitor',
            style: 'font-weight: bold; font-size: 13px;',
        });
        headerBox.add_child(headerLabel);

        let refreshButton = new St.Button({
            style_class: 'button',
            child: new St.Icon({icon_name: 'view-refresh-symbolic', icon_size: 16}),
        });
        refreshButton.connect('clicked', () => this._refresh());

        let prefsButton = new St.Button({
            style_class: 'button',
            child: new St.Icon({icon_name: 'preferences-system-symbolic', icon_size: 16}),
        });
        prefsButton.connect('clicked', () => this._openPreferences());

        headerBox.add_child(new St.Label({text: ' ', x_expand: true}));
        headerBox.add_child(refreshButton);
        headerBox.add_child(prefsButton);

        this.menu.box.add_child(headerBox);
        this.menu.box.add_child(menuItemActor(new PopupMenu.PopupSeparatorMenuItem()));

        this._contentBox = new St.BoxLayout({vertical: true, style: 'padding: 5px 10px;'});
        this.menu.box.add_child(this._contentBox);
    }

    _updatePanelIcon() {
        const selectedTool = this._settings.get_string('panel-tool');
        const mode = this._getDisplayMode();
        const {tool, data} = this._resolvePanelTool(selectedTool);
        let pct = this._clampPct(this._getToolPct(tool, data));

        if (this._isLoading)
            this._panelLabel.text = '...';
        else if (data.error)
            this._panelLabel.text = '!';
        else
            this._panelLabel.text = `${Math.round(pct)}%`;

        let gicon = this._toolGIcons[tool];
        if (gicon) {
            this._panelToolIcon.gicon = gicon;
            this._panelToolIcon.visible = true;
        } else {
            this._panelToolIcon.visible = false;
        }

        let color = this._getUsageColor(pct);
        this._panelPct = pct;
        this._panelColor = color;
        this._panelRing.queue_repaint();
        this._panelLabel.style = `font-size: 11px; font-weight: bold; color: ${color};`;

        this._panelRing.visible = mode !== 2;
        this._panelLabel.visible = mode !== 1;

        let toolName = this._getToolName(tool);
        let resetTime = this._getToolReset(tool, data);
        let tooltipText = 'AI Usage Monitor';
        if (!this._isLoading && resetTime)
            tooltipText += `\n${toolName} · ${this._formatReset(resetTime)} until reset`;
        else if (!this._isLoading)
            tooltipText += `\n${toolName}`;

        this.accessible_name = tooltipText;
    }

    _openPreferences() {
        try {
            this._extension.openPreferences();
        } catch (_e) {}
    }

    _toolData(tool) {
        if (tool === 'claude') return this._claudeData || {};
        if (tool === 'codex') return this._codexData || {};
        if (tool === 'gemini') return this._geminiData || {};
        return {};
    }

    _toolUsable(tool, data) {
        if (!data?.installed || data.error)
            return false;
        if (tool === 'codex' && data.has_data === false)
            return false;
        return true;
    }

    _resolvePanelTool(selectedTool) {
        let preferred = ['claude', 'codex', 'gemini'].includes(selectedTool) ? selectedTool : 'claude';
        for (let tool of [preferred, 'claude', 'codex', 'gemini']) {
            let data = this._toolData(tool);
            if (this._toolUsable(tool, data))
                return {tool, data};
        }
        return {tool: preferred, data: this._toolData(preferred)};
    }

    _getToolPct(tool, data) {
        if (tool === 'gemini')
            return Number(data.used_pct ?? 0);
        return Number(data.five_hour_pct ?? 0);
    }

    _getToolReset(tool, data) {
        if (tool === 'gemini')
            return data.reset_time;
        return data.five_hour_reset;
    }

    _getToolName(tool) {
        if (tool === 'codex') return 'OpenAI Codex';
        if (tool === 'gemini') return 'Gemini CLI';
        return 'Claude Code';
    }

    _getDisplayMode() {
        let mode = this._settings.get_int('panel-display-mode');
        return [0, 1, 2].includes(mode) ? mode : 0;
    }

    _drawPanelRing(area) {
        let cr = area.get_context();
        try {
            let [width, height] = area.get_surface_size();
            let cx = width / 2;
            let cy = height / 2;
            let radius = Math.min(width, height) / 2 - PANEL_RING_STROKE;
            let start = -Math.PI / 2;
            let end = start + (Math.PI * 2 * (this._panelPct / 100));

            cr.setOperator(Cairo.Operator.CLEAR);
            cr.paint();
            cr.setOperator(Cairo.Operator.OVER);

            cr.setLineWidth(PANEL_RING_STROKE);
            cr.setSourceRGBA(1, 1, 1, 0.22);
            cr.arc(cx, cy, radius, 0, Math.PI * 2);
            cr.stroke();

            if (this._panelPct > 0) {
                let [r, g, b] = this._hexToRgb(this._panelColor);
                cr.setSourceRGBA(r, g, b, 1);
                cr.arc(cx, cy, radius, start, end);
                cr.stroke();
            }
        } finally {
            cr.$dispose();
        }
    }

    _updateContent() {
        this._contentBox.destroy_all_children();

        const showClaude = this._settings.get_boolean('show-claude');
        const showCodex = this._settings.get_boolean('show-codex');
        const showGemini = this._settings.get_boolean('show-gemini');

        let anyVisible = false;

        if (showClaude && this._claudeData.installed) {
            this._contentBox.add_child(this._createToolSection('Claude Code', this._claudeData, 'claude'));
            anyVisible = true;
        }

        if (showCodex && this._codexData.installed) {
            this._contentBox.add_child(this._createToolSection('OpenAI Codex', this._codexData, 'codex'));
            anyVisible = true;
        }

        if (showGemini) {
            this._contentBox.add_child(this._createToolSection('Gemini CLI', this._geminiData, 'gemini'));
            anyVisible = true;
        }

        if (!anyVisible) {
            let msg = this._isLoading ? 'Loading...' :
                (this._claudeData.installed || this._codexData.installed || this._geminiData.installed)
                    ? 'All tools hidden in settings' : 'No AI tools detected';
            this._contentBox.add_child(new St.Label({
                text: msg,
                style: 'color: gray; text-align: center; padding: 20px;',
            }));
        }

        this.menu.box.queue_relayout();
    }

    _createToolSection(name, data, type) {
        let section = new St.BoxLayout({vertical: true, style_class: 'ai-usage-tool-section'});

        let headerBox = new St.BoxLayout({vertical: false, style: 'margin-bottom: 6px;'});

        const iconFiles = {claude: 'claude-icon-22.png', codex: 'codex_icon.png', gemini: 'gemini_icon.png'};
        if (iconFiles[type]) {
            try {
                let icon = new St.Icon({
                    gicon: Gio.icon_new_for_string(`${this._extensionPath}/images/${iconFiles[type]}`),
                    icon_size: 16,
                    style: 'margin-right: 4px;',
                });
                headerBox.add_child(icon);
            } catch (_e) {}
        }

        headerBox.add_child(new St.Label({
            text: name.toUpperCase(),
            style: 'font-weight: bold; font-size: 11px;',
        }));
        section.add_child(headerBox);

        if (data.error) {
            let errorLabel = new St.Label({
                text: data.error + (data.retry_count ? ` (${data.retry_count} attempts)` : ''),
                style_class: 'ai-usage-error',
            });
            errorLabel.clutter_text.line_wrap = true;
            errorLabel.clutter_text.line_wrap_mode = Pango.WrapMode.WORD_CHAR;
            errorLabel.clutter_text.ellipsize = Pango.EllipsizeMode.NONE;
            section.add_child(errorLabel);
        }

        if (type === 'gemini') {
            if (!data.installed) {
                section.add_child(new St.Label({
                    text: 'Gemini CLI not detected',
                    style: 'color: #64748b; font-size: 10px; margin-bottom: 4px;',
                }));
            } else if (data.used_pct !== undefined && !data.error) {
                section.add_child(this._createUsageBar(data.model || 'Gemini quota', data.used_pct, data.reset_time));
            }
        } else {
            if (data.five_hour_pct !== undefined && !data.error)
                section.add_child(this._createUsageBar('5h', data.five_hour_pct, data.five_hour_reset));
            if (data.seven_day_pct !== undefined && data.seven_day_pct !== null && !data.error)
                section.add_child(this._createUsageBar('7d', data.seven_day_pct, data.seven_day_reset));
        }

        section.add_child(menuItemActor(new PopupMenu.PopupSeparatorMenuItem()));
        return section;
    }

    _createUsageBar(label, pct, resetTime) {
        pct = this._clampPct(Number(pct ?? 0));
        let color = this._getUsageColor(pct);

        let box = new St.BoxLayout({vertical: false, style_class: 'ai-usage-bar-container'});

        box.add_child(new St.Label({
            text: label,
            style: 'font-size: 10px; color: gray; min-width: 60px;',
        }));

        let barArea = new St.DrawingArea({
            width: POPUP_BAR_WIDTH,
            height: 8,
            y_align: Clutter.ActorAlign.CENTER,
        });
        barArea.connect('repaint', () => {
            let cr = barArea.get_context();
            try {
                let [w, h] = barArea.get_surface_size();
                let r = 3;
                let fill = Math.round((pct / 100) * w);

                cr.setOperator(Cairo.Operator.CLEAR);
                cr.paint();
                cr.setOperator(Cairo.Operator.OVER);

                cr.setSourceRGBA(1, 1, 1, 0.12);
                cr.newPath();
                cr.arc(r, r, r, Math.PI, Math.PI * 1.5);
                cr.arc(w - r, r, r, Math.PI * 1.5, 0);
                cr.arc(w - r, h - r, r, 0, Math.PI * 0.5);
                cr.arc(r, h - r, r, Math.PI * 0.5, Math.PI);
                cr.closePath();
                cr.fill();

                if (fill > 0) {
                    let [rr, g, b] = this._hexToRgb(color);
                    cr.setSourceRGBA(rr, g, b, 1);
                    cr.rectangle(0, 0, fill, h);
                    cr.fill();
                }
            } finally {
                cr.$dispose();
            }
        });
        box.add_child(barArea);

        box.add_child(new St.Label({
            text: ` ${Math.round(pct)}%`,
            style: `font-size: 11px; font-weight: bold; color: ${color}; min-width: 40px;`,
        }));

        if (resetTime) {
            box.add_child(new St.Label({
                text: this._formatReset(resetTime),
                style: 'font-size: 10px; color: gray; min-width: 70px;',
            }));
        }

        return box;
    }

    _clampPct(value) {
        if (!Number.isFinite(value))
            return 0;
        return Math.max(0, Math.min(100, value));
    }

    _hexToRgb(hex) {
        let match = /^#?([a-f\d]{2})([a-f\d]{2})([a-f\d]{2})$/i.exec(hex);
        if (!match)
            return [1, 1, 1];
        return [
            parseInt(match[1], 16) / 255,
            parseInt(match[2], 16) / 255,
            parseInt(match[3], 16) / 255,
        ];
    }

    _getUsageColor(pct) {
        if (pct >= 90) return '#ef4444';
        if (pct >= 70) return '#f97316';
        if (pct >= 40) return '#eab308';
        return '#22c55e';
    }

    _formatReset(isoStr) {
        if (!isoStr) return '';
        let diff = new Date(isoStr) - new Date();
        if (diff <= 0) return 'soon';
        let hrs = Math.floor(diff / 3600000);
        let mins = Math.floor((diff % 3600000) / 60000);
        if (hrs >= 24)
            return `in ${Math.floor(hrs / 24)}d ${hrs % 24}h`;
        if (hrs > 0)
            return `in ${hrs}h ${mins}m`;
        return `in ${mins}m`;
    }

    _refresh() {
        if (this._cancellable)
            this._cancellable.cancel();
        this._cancellable = new Gio.Cancellable();

        this._isLoading = true;
        this._updatePanelIcon();

        let proc;
        try {
            proc = new Gio.Subprocess({
                argv: ['python3', `${this._extensionPath}/scripts/fetch_all_usage.py`],
                flags: Gio.SubprocessFlags.STDOUT_PIPE | Gio.SubprocessFlags.STDERR_PIPE,
            });
            proc.init(this._cancellable);
        } catch (e) {
            this._isLoading = false;
            this._updatePanelIcon();
            this._updateContent();
            return;
        }

        proc.communicate_utf8_async(null, this._cancellable, (source, result) => {
            try {
                let [, stdout] = source.communicate_utf8_finish(result);
                if (stdout?.trim()) {
                    let parsed = JSON.parse(stdout.trim());
                    this._claudeData = parsed.claude || {};
                    this._codexData = parsed.codex || {};
                    this._geminiData = parsed.gemini || {};
                }
            } catch (e) {
                if (e.matches(Gio.IOErrorEnum, Gio.IOErrorEnum.CANCELLED))
                    return;
            }

            this._isLoading = false;
            this._updatePanelIcon();
            this._updateContent();
        });
    }

    _scheduleRefresh() {
        if (this._timeoutId)
            GLib.source_remove(this._timeoutId);

        let interval = this._settings.get_int('refresh-interval');
        this._timeoutId = GLib.timeout_add_seconds(GLib.PRIORITY_DEFAULT, interval, () => {
            this._refresh();
            return GLib.SOURCE_CONTINUE;
        });
    }

    _onSettingsChanged(_settings, key) {
        if (key === 'refresh-interval')
            this._scheduleRefresh();
        this._updatePanelIcon();
        this._updateContent();
    }

    destroy() {
        if (this._cancellable) {
            this._cancellable.cancel();
            this._cancellable = null;
        }

        if (this._timeoutId) {
            GLib.source_remove(this._timeoutId);
            this._timeoutId = null;
        }

        if (this._settingsChangedId) {
            this._settings.disconnect(this._settingsChangedId);
            this._settingsChangedId = null;
        }

        super.destroy();
    }
});

export default class AIUsageMonitorExtension extends Extension {
    enable() {
        this._indicator = new AIUsageIndicator(this.path, this.getSettings(), this);
        Main.panel.addToStatusArea(this.metadata.uuid, this._indicator);
    }

    disable() {
        if (this._indicator) {
            this._indicator.destroy();
            this._indicator = null;
        }
    }
}

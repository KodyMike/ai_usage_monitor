import Adw from 'gi://Adw';
import Gtk from 'gi://Gtk';
import {ExtensionPreferences} from 'resource:///org/gnome/Shell/Extensions/js/extensions/prefs.js';

const REFRESH_LABELS = [
    '20 seconds',
    '1 minute',
    '2 minutes',
    '5 minutes',
    '10 minutes',
    '30 minutes',
];

const REFRESH_VALUES = [20, 60, 120, 300, 600, 1800];
const PANEL_TOOL_LABELS = ['Claude Code', 'OpenAI Codex', 'Gemini CLI'];
const PANEL_TOOL_VALUES = ['claude', 'codex', 'gemini'];
const DISPLAY_MODE_LABELS = ['Ring and percentage', 'Ring only', 'Percentage only'];

function createDropdownRow(title, labels, selectedIndex, onChange) {
    const row = new Adw.ActionRow({title});

    const model = new Gtk.StringList();
    for (const label of labels)
        model.append(label);
    const dropdown = new Gtk.DropDown({model, valign: Gtk.Align.CENTER});
    dropdown.set_selected(selectedIndex >= 0 ? selectedIndex : 0);
    dropdown.connect('notify::selected', widget => {
        onChange(widget.get_selected());
    });

    row.add_suffix(dropdown);
    row.activatable_widget = dropdown;
    return row;
}

export default class AIUsageMonitorPreferences extends ExtensionPreferences {
    fillPreferencesWindow(window) {
        const settings = this.getSettings();

        const page = new Adw.PreferencesPage({
            title: 'General',
            icon_name: 'preferences-system-symbolic',
        });

        const refreshGroup = new Adw.PreferencesGroup({
            title: 'Refresh Interval',
            description: 'How often to update usage data',
        });

        const currentRefresh = settings.get_int('refresh-interval');
        const refreshIndex = REFRESH_VALUES.indexOf(currentRefresh);
        refreshGroup.add(createDropdownRow(
            'Refresh every',
            REFRESH_LABELS,
            refreshIndex,
            selected => settings.set_int('refresh-interval', REFRESH_VALUES[selected])
        ));

        const panelGroup = new Adw.PreferencesGroup({
            title: 'Panel Display',
            description: 'Configure what appears in the top bar',
        });

        const currentTool = settings.get_string('panel-tool');
        const toolIndex = PANEL_TOOL_VALUES.indexOf(currentTool);
        panelGroup.add(createDropdownRow(
            'Show in panel',
            PANEL_TOOL_LABELS,
            toolIndex,
            selected => settings.set_string('panel-tool', PANEL_TOOL_VALUES[selected])
        ));

        const modeIndex = settings.get_int('panel-display-mode');
        panelGroup.add(createDropdownRow(
            'Display style',
            DISPLAY_MODE_LABELS,
            modeIndex,
            selected => settings.set_int('panel-display-mode', selected)
        ));

        const visibilityGroup = new Adw.PreferencesGroup({
            title: 'Visible Tools',
            description: 'Choose which tools appear in the popup menu',
        });

        const claudeSwitch = new Adw.SwitchRow({
            title: 'Claude Code',
            subtitle: 'Show Claude Code usage in popup',
            active: settings.get_boolean('show-claude'),
        });
        claudeSwitch.connect('notify::active', widget => {
            settings.set_boolean('show-claude', widget.get_active());
        });
        visibilityGroup.add(claudeSwitch);

        const codexSwitch = new Adw.SwitchRow({
            title: 'OpenAI Codex',
            subtitle: 'Show OpenAI Codex usage in popup',
            active: settings.get_boolean('show-codex'),
        });
        codexSwitch.connect('notify::active', widget => {
            settings.set_boolean('show-codex', widget.get_active());
        });
        visibilityGroup.add(codexSwitch);

        const geminiSwitch = new Adw.SwitchRow({
            title: 'Gemini CLI',
            subtitle: 'Show Gemini CLI usage in popup',
            active: settings.get_boolean('show-gemini'),
        });
        geminiSwitch.connect('notify::active', widget => {
            settings.set_boolean('show-gemini', widget.get_active());
        });
        visibilityGroup.add(geminiSwitch);

        page.add(refreshGroup);
        page.add(panelGroup);
        page.add(visibilityGroup);
        window.add(page);
    }
}

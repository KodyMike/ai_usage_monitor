import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

Kirigami.FormLayout {
    property int cfg_refreshSecs: 60
    property string cfg_panelTool: "claude"
    property int cfg_panelDisplayMode: 0

    // Visibility settings
    property bool cfg_showClaude: true
    property bool cfg_showCodex: true
    property bool cfg_showGemini: true

    // ── Refresh ────────────────────────────────────────────────────────────
    QQC2.ComboBox {
        id: refreshCombo
        Kirigami.FormData.label: "Refresh every:"

        model: [
            { text: "20 seconds",  value: 20  },
            { text: "1 minute",    value: 60  },
            { text: "2 minutes",   value: 120 },
            { text: "5 minutes",   value: 300 },
            { text: "10 minutes",  value: 600 },
            { text: "30 minutes",  value: 1800 },
        ]

        textRole: "text"

        currentIndex: {
            var v = cfg_refreshSecs
            for (var i = 0; i < model.length; i++) {
                if (model[i].value === v) return i
            }
            return 1  // default to 1 minute
        }

        onActivated: cfg_refreshSecs = model[currentIndex].value
    }

    // ── Tool shown in panel ────────────────────────────────────────────────
    Kirigami.Separator {
        Kirigami.FormData.label: "Panel tool"
        Kirigami.FormData.isSection: true
    }

    ColumnLayout {
        Kirigami.FormData.label: "Show:"
        spacing: 4

        QQC2.RadioButton {
            text: "Claude Code"
            checked: cfg_panelTool === "claude"
            onToggled: if (checked) cfg_panelTool = "claude"
        }
        QQC2.RadioButton {
            text: "OpenAI Codex"
            checked: cfg_panelTool === "codex"
            onToggled: if (checked) cfg_panelTool = "codex"
        }
        QQC2.RadioButton {
            text: "Gemini CLI"
            checked: cfg_panelTool === "gemini"
            onToggled: if (checked) cfg_panelTool = "gemini"
        }
    }

    // ── Display style ──────────────────────────────────────────────────────
    Kirigami.Separator {
        Kirigami.FormData.label: "Display style"
        Kirigami.FormData.isSection: true
    }

    ColumnLayout {
        Kirigami.FormData.label: "Style:"
        spacing: 4

        QQC2.RadioButton {
            text: "Ring and percentage"
            checked: cfg_panelDisplayMode === 0
            onToggled: if (checked) cfg_panelDisplayMode = 0
        }
        QQC2.RadioButton {
            text: "Ring only"
            checked: cfg_panelDisplayMode === 1
            onToggled: if (checked) cfg_panelDisplayMode = 1
        }
        QQC2.RadioButton {
            text: "Percentage only"
            checked: cfg_panelDisplayMode === 2
            onToggled: if (checked) cfg_panelDisplayMode = 2
        }
    }

    // ── Visible tools ──────────────────────────────────────────────────────
    Kirigami.Separator {
        Kirigami.FormData.label: "Visible tools"
        Kirigami.FormData.isSection: true
    }

    ColumnLayout {
        Kirigami.FormData.label: "Show in popup:"
        spacing: 4

        QQC2.CheckBox {
            text: "Claude Code"
            checked: cfg_showClaude
            onToggled: cfg_showClaude = checked
        }
        QQC2.CheckBox {
            text: "OpenAI Codex"
            checked: cfg_showCodex
            onToggled: cfg_showCodex = checked
        }
        QQC2.CheckBox {
            text: "Gemini CLI"
            checked: cfg_showGemini
            onToggled: cfg_showGemini = checked
        }
    }

}

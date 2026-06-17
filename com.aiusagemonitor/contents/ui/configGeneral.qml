import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

Kirigami.FormLayout {
    property int cfg_claudeRefreshSecs: 600
    property int cfg_codexRefreshSecs: 60
    property int cfg_geminiRefreshSecs: 300
    property int cfg_opencodeRefreshSecs: 600
    property string cfg_panelTool: "claude"
    property int cfg_panelDisplayMode: 0

    // Visibility settings
    property bool cfg_showClaude: true
    property bool cfg_showCodex: true
    property bool cfg_showGemini: true
    property bool cfg_showOpencode: true

    // OpenCode Go limits ($) + subscription renewal day
    property int cfg_opencodeLimit5h: 12
    property int cfg_opencodeLimitWeek: 30
    property int cfg_opencodeLimitMonth: 60
    property int cfg_opencodeBillingDay: 1

    // ── Refresh intervals ──────────────────────────────────────────────────
    Kirigami.Separator {
        Kirigami.FormData.label: "Refresh intervals"
        Kirigami.FormData.isSection: true
    }

    QQC2.ComboBox {
        Kirigami.FormData.label: "Claude Code:"
        model: [
            { text: "1 minute",   value: 60   },
            { text: "5 minutes",  value: 300  },
            { text: "10 minutes", value: 600  },
            { text: "30 minutes", value: 1800 },
        ]
        textRole: "text"
        currentIndex: { var v = cfg_claudeRefreshSecs; for (var i = 0; i < model.length; i++) { if (model[i].value === v) return i } return 2 }
        onActivated: cfg_claudeRefreshSecs = model[currentIndex].value
    }

    QQC2.ComboBox {
        Kirigami.FormData.label: "OpenAI Codex:"
        model: [
            { text: "10 seconds", value: 10  },
            { text: "30 seconds", value: 30  },
            { text: "1 minute",   value: 60  },
            { text: "5 minutes",  value: 300 },
        ]
        textRole: "text"
        currentIndex: { var v = cfg_codexRefreshSecs; for (var i = 0; i < model.length; i++) { if (model[i].value === v) return i } return 2 }
        onActivated: cfg_codexRefreshSecs = model[currentIndex].value
    }

    QQC2.ComboBox {
        Kirigami.FormData.label: "Gemini CLI:"
        model: [
            { text: "1 minute",   value: 60   },
            { text: "5 minutes",  value: 300  },
            { text: "10 minutes", value: 600  },
            { text: "30 minutes", value: 1800 },
        ]
        textRole: "text"
        currentIndex: { var v = cfg_geminiRefreshSecs; for (var i = 0; i < model.length; i++) { if (model[i].value === v) return i } return 1 }
        onActivated: cfg_geminiRefreshSecs = model[currentIndex].value
    }

    QQC2.ComboBox {
        Kirigami.FormData.label: "OpenCode:"
        model: [
            { text: "1 minute",   value: 60   },
            { text: "5 minutes",  value: 300  },
            { text: "10 minutes", value: 600  },
            { text: "30 minutes", value: 1800 },
        ]
        textRole: "text"
        currentIndex: { var v = cfg_opencodeRefreshSecs; for (var i = 0; i < model.length; i++) { if (model[i].value === v) return i } return 2 }
        onActivated: cfg_opencodeRefreshSecs = model[currentIndex].value
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
        QQC2.RadioButton {
            text: "OpenCode"
            checked: cfg_panelTool === "opencode"
            onToggled: if (checked) cfg_panelTool = "opencode"
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
        QQC2.CheckBox {
            text: "OpenCode"
            checked: cfg_showOpencode
            onToggled: cfg_showOpencode = checked
        }
    }

    // ── OpenCode Go limits ───────────────────────────────────────────────────
    Kirigami.Separator {
        Kirigami.FormData.label: "OpenCode Go limits ($)"
        Kirigami.FormData.isSection: true
    }

    QQC2.SpinBox {
        Kirigami.FormData.label: "5-hour limit ($):"
        from: 0; to: 100000; stepSize: 1
        value: cfg_opencodeLimit5h
        onValueModified: cfg_opencodeLimit5h = value
    }

    QQC2.SpinBox {
        Kirigami.FormData.label: "Weekly limit ($):"
        from: 0; to: 100000; stepSize: 1
        value: cfg_opencodeLimitWeek
        onValueModified: cfg_opencodeLimitWeek = value
    }

    QQC2.SpinBox {
        Kirigami.FormData.label: "Monthly limit ($):"
        from: 0; to: 100000; stepSize: 1
        value: cfg_opencodeLimitMonth
        onValueModified: cfg_opencodeLimitMonth = value
    }

    QQC2.SpinBox {
        Kirigami.FormData.label: "Renewal day (monthly):"
        from: 1; to: 31
        value: cfg_opencodeBillingDay
        onValueModified: cfg_opencodeBillingDay = value
    }

}

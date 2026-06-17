import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.plasma.plasmoid
import org.kde.plasma.components as PC3
import org.kde.kirigami as Kirigami

Item {
    id: fullRoot
    implicitWidth: 360
    // Cap the popup height; the content scrolls (Flickable) when there are many
    // providers/accounts so nothing gets clipped.
    implicitHeight: Math.min(contentCol.implicitHeight + 24, 600)

    property var cd: root.claudeData
    property var od: root.codexData
    property var gd: root.geminiData
    property var ocd: root.opencodeData

    // Match GNOME extension colors exactly
    function usageColor(pct) {
        if (pct >= 90) return "#ef4444"
        if (pct >= 70) return "#f97316"
        if (pct >= 40) return "#eab308"
        return "#22c55e"
    }

    function formatReset(isoStr) {
        if (!isoStr) return ""
        var now = new Date()
        var reset = new Date(isoStr)
        var diff = reset - now
        if (diff <= 0) return "soon"
        var hrs = Math.floor(diff / 3600000)
        var mins = Math.floor((diff % 3600000) / 60000)
        if (hrs >= 24) {
            var days = Math.floor(hrs / 24)
            return "in " + days + "d " + (hrs % 24) + "h"
        }
        if (hrs > 0) return "in " + hrs + "h " + mins + "m"
        return "in " + mins + "m"
    }

    function formatTokens(n) {
        if (n === undefined || n === null) return "—"
        if (n >= 1000000) return (n / 1000000).toFixed(1) + "M"
        if (n >= 1000) return (n / 1000).toFixed(1) + "k"
        return n.toString()
    }

    function prettyGeminiModel(id) {
        var m = (id || "").toLowerCase().replace(/^models\//, "")
        if (!m) return ""
        m = m.replace(/^gemini-/, "")

        var suffix = ""
        if (m.indexOf("preview") !== -1 || m.indexOf("exp") !== -1)
            suffix = " (Preview)"

        if (m.indexOf("2.5-flash-lite") === 0) return "Gemini 2.5 Flash Lite" + suffix
        if (m.indexOf("2.5-flash") === 0) return "Gemini 2.5 Flash" + suffix
        if (m.indexOf("2.5-pro") === 0) return "Gemini 2.5 Pro" + suffix
        if (m.indexOf("2.0-flash") === 0) return "Gemini 2.0 Flash" + suffix
        if (m.indexOf("2.0-pro") === 0) return "Gemini 2.0 Pro" + suffix

        return ("Gemini " + m.replace(/-/g, " ")) + suffix
    }

    function prettyCodexModel(id) {
        var m = (id || "").toLowerCase()
        if (!m) return ""
        if (m.indexOf("codex") !== -1) {
            var major = m.match(/gpt-(\d+)(?:\.\d+)?/)
            if (major && major.length > 1)
                return "GPT-" + major[1] + " Codex"
            return "Codex"
        }
        return id
    }

    Flickable {
        anchors.fill: parent
        contentWidth: width
        contentHeight: contentCol.implicitHeight + 24
        clip: true
        QQC2.ScrollBar.vertical: QQC2.ScrollBar { policy: QQC2.ScrollBar.AsNeeded }

        ColumnLayout {
            id: contentCol
            x: 12
            y: 12
            width: parent.width - 24
            spacing: 0

        // ── Header ─────────────────────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            Layout.bottomMargin: 10

            PC3.Label {
                text: "AI Usage Monitor"
                font.bold: true
                font.pixelSize: 14
                Layout.fillWidth: true
            }

            PC3.ToolButton {
                icon.name: "view-refresh"
                enabled: !root.isLoading
                onClicked: root.refresh()
                PC3.ToolTip.text: root.lastUpdated ? "Updated " + root.lastUpdated : "Click to refresh"
                PC3.ToolTip.visible: hovered
                PC3.ToolTip.delay: 500
            }
        }

        // ── CLAUDE CODE ────────────────────────────────────────────────────
        Loader {
            Layout.fillWidth: true
            Layout.preferredHeight: active ? implicitHeight : 0
            visible: active
            active: cd.installed === true && root.showClaude

            sourceComponent: ColumnLayout {
                spacing: 6

                // Card header
                RowLayout {
                    Image {
                        source: Qt.resolvedUrl("../images/claude-icon-22.png")
                        width: 16; height: 16; fillMode: Image.PreserveAspectFit; smooth: true
                    }
                    PC3.Label { text: "CLAUDE CODE"; font.bold: true; font.pixelSize: 12 }
                    Item { Layout.fillWidth: true }
                }

                // Error message (separate row)
                PC3.Label {
                    visible: !!cd.error
                    text: cd.error || ""
                    color: Kirigami.Theme.negativeTextColor
                    font.pixelSize: 10
                    wrapMode: Text.Wrap
                    width: 320
                    Layout.preferredWidth: 320
                }

                // 5h bar
                Loader {
                    Layout.fillWidth: true
                    active: cd.five_hour_pct !== undefined && !cd.error

                    sourceComponent: UsageBar {
                        label: "5h"
                        pct: Math.min(cd.five_hour_pct || 0, 100)
                        pctText: (cd.five_hour_pct || 0) + "%"
                        resetText: fullRoot.formatReset(cd.five_hour_reset)
                        barColor: fullRoot.usageColor(cd.five_hour_pct || 0)
                    }
                }

                // 7d bar (only if data available)
                Loader {
                    Layout.fillWidth: true
                    active: cd.seven_day_pct !== null && cd.seven_day_pct !== undefined && !cd.error

                    sourceComponent: UsageBar {
                        label: "7d"
                        pct: Math.min(cd.seven_day_pct || 0, 100)
                        pctText: (cd.seven_day_pct || 0) + "%"
                        resetText: fullRoot.formatReset(cd.seven_day_reset)
                        barColor: fullRoot.usageColor(cd.seven_day_pct || 0)
                    }
                }

                PC3.Label {
                    visible: !cd.error && (cd.seven_day_pct === null || cd.seven_day_pct === undefined)
                    text: "7-day limit: not tracked on this plan"
                    font.pixelSize: 10
                    color: Kirigami.Theme.disabledTextColor
                }

                Kirigami.Separator { Layout.fillWidth: true; Layout.topMargin: 4; Layout.bottomMargin: 4 }
            }
        }

        // ── OPENAI CODEX ───────────────────────────────────────────────────
        Loader {
            Layout.fillWidth: true
            Layout.preferredHeight: active ? implicitHeight : 0
            visible: active
            active: od.installed === true && root.showCodex === true

            sourceComponent: ColumnLayout {
                spacing: 6

                RowLayout {
                    Item {
                        width: 16; height: 16
                        Image {
                            id: codexFullImg
                            source: Qt.resolvedUrl("../images/codex_icon.png")
                            width: 16; height: 16; fillMode: Image.PreserveAspectFit; smooth: true
                            visible: status === Image.Ready
                        }
                        Rectangle {
                            visible: codexFullImg.status !== Image.Ready
                            width: 14; height: 14; radius: 3; anchors.centerIn: parent
                            color: "#10A37F"
                        }
                    }
                    PC3.Label { text: "OPENAI CODEX"; font.bold: true; font.pixelSize: 12 }
                    PC3.Label {
                        visible: !!od.model
                        text: od.model ? "· " + fullRoot.prettyCodexModel(od.model) : ""
                        font.pixelSize: 10
                        color: Kirigami.Theme.disabledTextColor
                    }
                    Item { Layout.fillWidth: true }
                    PC3.Label {
                        visible: !!od.plan_type
                        text: od.plan_type || ""
                        font.pixelSize: 10
                        color: Kirigami.Theme.disabledTextColor
                    }
                }

                Loader {
                    Layout.fillWidth: true
                    active: od.five_hour_pct !== undefined && od.has_data !== false

                    sourceComponent: UsageBar {
                        label: "5h"
                        pct: Math.min(od.five_hour_pct || 0, 100)
                        pctText: Math.round(od.five_hour_pct || 0) + "%"
                        resetText: fullRoot.formatReset(od.five_hour_reset)
                        barColor: fullRoot.usageColor(od.five_hour_pct || 0)
                    }
                }

                Loader {
                    Layout.fillWidth: true
                    active: od.seven_day_pct !== undefined && od.has_data !== false

                    sourceComponent: UsageBar {
                        label: "7d"
                        pct: Math.min(od.seven_day_pct || 0, 100)
                        pctText: Math.round(od.seven_day_pct || 0) + "%"
                        resetText: fullRoot.formatReset(od.seven_day_reset)
                        barColor: fullRoot.usageColor(od.seven_day_pct || 0)
                    }
                }

                PC3.Label {
                    visible: od.has_data === false
                    text: "No session data yet"
                    font.pixelSize: 10
                    color: Kirigami.Theme.disabledTextColor
                }

                Kirigami.Separator { Layout.fillWidth: true; Layout.topMargin: 4; Layout.bottomMargin: 4 }
            }
        }

        // ── GEMINI CLI (one card per account) ──────────────────────────────
        Loader {
            Layout.fillWidth: true
            Layout.preferredHeight: active ? implicitHeight : 0
            visible: active
            active: gd.installed === true && root.showGemini === true

            sourceComponent: ColumnLayout {
                spacing: 6

                // One card per Google account (gd.accounts); falls back to the
                // single legacy object when only one account is configured.
                Repeater {
                    model: (gd.accounts && gd.accounts.length) ? gd.accounts : [gd]

                    delegate: ColumnLayout {
                        id: geminiCard
                        readonly property var acct: modelData
                        property bool expanded: false
                        readonly property bool canExpand: !!(acct.buckets && acct.buckets.length > 1 && !acct.error)
                        Layout.fillWidth: true
                        spacing: 6

                        RowLayout {
                            Image {
                                source: Qt.resolvedUrl("../images/gemini_icon.png")
                                width: 16; height: 16; fillMode: Image.PreserveAspectFit; smooth: true
                            }
                            PC3.Label { text: "GEMINI CLI"; font.bold: true; font.pixelSize: 12 }
                            PC3.Label {
                                visible: !!acct.email
                                text: acct.email ? "· " + acct.email : ""
                                font.pixelSize: 10
                                color: Kirigami.Theme.disabledTextColor
                                elide: Text.ElideRight
                                Layout.maximumWidth: 160
                            }
                            Item { Layout.fillWidth: true }
                            QQC2.Button {
                                visible: geminiCard.canExpand
                                text: geminiCard.expanded
                                    ? "Hide models"
                                    : ("Models (" + (acct.buckets ? acct.buckets.length : 0) + ")")
                                onClicked: geminiCard.expanded = !geminiCard.expanded
                            }
                        }

                        // Collapsed: single overview bar (model with lowest remaining fraction)
                        Loader {
                            Layout.fillWidth: true
                            active: acct.used_pct !== undefined && !acct.error && !geminiCard.expanded

                            sourceComponent: UsageBar {
                                label: acct.model ? fullRoot.prettyGeminiModel(acct.model) : "Gemini quota"
                                pct: Math.min(acct.used_pct || 0, 100)
                                pctText: (acct.used_pct || 0) + "%"
                                resetText: fullRoot.formatReset(acct.reset_time)
                                barColor: fullRoot.usageColor(acct.used_pct || 0)
                            }
                        }

                        // Expanded: one bar per model bucket
                        Repeater {
                            model: (geminiCard.expanded && acct.buckets) ? acct.buckets : []
                            delegate: UsageBar {
                                readonly property var bkt: modelData
                                label: fullRoot.prettyGeminiModel(bkt.model || "")
                                pct: Math.min(bkt.used_pct || 0, 100)
                                pctText: (bkt.used_pct || 0) + "%"
                                resetText: fullRoot.formatReset(bkt.reset_time)
                                barColor: fullRoot.usageColor(bkt.used_pct || 0)
                            }
                        }

                        PC3.Label {
                            visible: !!acct.error
                            text: acct.error || ""
                            font.pixelSize: 10
                            color: Kirigami.Theme.negativeTextColor
                            wrapMode: Text.Wrap
                            Layout.preferredWidth: 320
                        }
                    }
                }

                Kirigami.Separator { Layout.fillWidth: true; Layout.topMargin: 4; Layout.bottomMargin: 4 }
            }
        }

        // ── OPENCODE ───────────────────────────────────────────────────────
        // OpenCode Go has no "%/reset" quota; we show accumulated spend + tokens.
        Loader {
            Layout.fillWidth: true
            Layout.preferredHeight: active ? implicitHeight : 0
            visible: active
            active: ocd.installed === true && root.showOpencode === true

            sourceComponent: ColumnLayout {
                id: opencodeCard
                spacing: 6

                RowLayout {
                    Rectangle { width: 14; height: 14; radius: 3; color: "#8b5cf6" }
                    PC3.Label { text: "OPENCODE"; font.bold: true; font.pixelSize: 12 }
                    PC3.Label {
                        text: "Go · est. this machine"
                        font.pixelSize: 10
                        color: Kirigami.Theme.disabledTextColor
                    }
                    Item { Layout.fillWidth: true }
                    PC3.Label {
                        visible: ocd.sessions !== undefined && !ocd.error
                        text: ocd.sessions !== undefined ? (ocd.sessions + " sessions") : ""
                        font.pixelSize: 10
                        color: Kirigami.Theme.disabledTextColor
                    }
                }

                PC3.Label {
                    visible: !!ocd.error
                    text: ocd.error || ""
                    font.pixelSize: 10
                    color: Kirigami.Theme.negativeTextColor
                    wrapMode: Text.Wrap
                    Layout.preferredWidth: 320
                }

                // OpenCode Go dollar-value limit windows ($12 / $30 / $60). Spend is a
                // local estimate (tokens × model price), so it may differ from opencode's
                // console; 5h/weekly resets are approximate (rolling windows).
                Repeater {
                    model: (!ocd.error && ocd.five_hour !== undefined) ? [
                        { win: ocd.five_hour, lim: root.opencodeLimit5h,    lbl: "5h" },
                        { win: ocd.weekly,    lim: root.opencodeLimitWeek,  lbl: "7d" },
                        { win: ocd.monthly,   lim: root.opencodeLimitMonth, lbl: "mo" }
                    ] : []
                    delegate: UsageBar {
                        readonly property real p: modelData.lim > 0 ? Math.min((modelData.win.used / modelData.lim) * 100, 100) : 0
                        label: modelData.lbl
                        pct: p
                        pctText: "$" + modelData.win.used.toFixed(2) + " / $" + modelData.lim
                        resetText: fullRoot.formatReset(modelData.win.reset)
                        barColor: fullRoot.usageColor(p)
                    }
                }

                GridLayout {
                    visible: ocd.cost_total !== undefined && !ocd.error
                    columns: 2
                    rowSpacing: 2
                    columnSpacing: 12
                    Layout.fillWidth: true

                    PC3.Label { text: "Total spent"; font.pixelSize: 11; color: Kirigami.Theme.disabledTextColor }
                    PC3.Label {
                        text: ocd.cost_total !== undefined ? ("$" + ocd.cost_total.toFixed(2)) : "—"
                        font.pixelSize: 11; font.bold: true
                        Layout.fillWidth: true; horizontalAlignment: Text.AlignRight
                    }

                    PC3.Label { text: "Tokens in / out"; font.pixelSize: 11; color: Kirigami.Theme.disabledTextColor }
                    PC3.Label {
                        text: fullRoot.formatTokens(ocd.tokens_input) + " / " + fullRoot.formatTokens(ocd.tokens_output)
                        font.pixelSize: 11; font.bold: true
                        Layout.fillWidth: true; horizontalAlignment: Text.AlignRight
                    }
                }

                // OpenCode Go has no usage API: this is a local estimate of THIS machine
                // only (undercounts if you use OpenCode elsewhere). Real global total: opencode.ai.
                PC3.Label {
                    visible: ocd.cost_total !== undefined && !ocd.error
                    text: "Estimate · this machine only — real total at opencode.ai"
                    font.pixelSize: 9
                    color: Kirigami.Theme.disabledTextColor
                    wrapMode: Text.Wrap
                    Layout.fillWidth: true
                    Layout.preferredWidth: 320
                }

                Kirigami.Separator { Layout.fillWidth: true; Layout.topMargin: 4; Layout.bottomMargin: 4 }
            }
        }

        // ── No tools installed or visible ──────────────────────────────────
        Loader {
            Layout.fillWidth: true
            Layout.preferredHeight: active ? implicitHeight : 0
            visible: active
            readonly property bool claudeVisible: cd.installed === true && root.showClaude === true
            readonly property bool codexVisible: od.installed === true && root.showCodex === true
            readonly property bool geminiVisible: gd.installed === true && root.showGemini === true
            readonly property bool opencodeVisible: ocd.installed === true && root.showOpencode === true
            active: !claudeVisible && !codexVisible && !geminiVisible && !opencodeVisible

            sourceComponent: PC3.Label {
                text: {
                    if (root.isLoading) return "Loading…"
                    var allHidden = (cd.installed === true || od.installed === true || gd.installed === true || ocd.installed === true)
                    return allHidden ? "All tools hidden in settings" : "No AI tools detected"
                }
                color: Kirigami.Theme.disabledTextColor
                horizontalAlignment: Text.AlignHCenter
                Layout.fillWidth: true
            }
        }

        Item { height: 4 }
        }
    }

    // ── Reusable usage bar component ────────────────────────────────────────
    component UsageBar: RowLayout {
        property string label: ""
        property real pct: 0
        property string pctText: "0%"
        property string resetText: ""
        property color barColor: Kirigami.Theme.positiveTextColor

        spacing: 6
        Layout.fillWidth: true

        PC3.Label {
            text: label
            font.pixelSize: 10
            color: Kirigami.Theme.disabledTextColor
            Layout.minimumWidth: 18
        }

        Rectangle {
            Layout.fillWidth: true
            height: 8
            radius: 4
            color: Kirigami.Theme.backgroundColor

            Rectangle {
                width: parent.width * (pct / 100)
                height: parent.height
                radius: parent.radius
                color: barColor

                Behavior on width { NumberAnimation { duration: 400; easing.type: Easing.OutCubic } }
            }
        }

        PC3.Label {
            text: pctText
            font.pixelSize: 11
            font.bold: true
            color: barColor
            Layout.minimumWidth: 36
            horizontalAlignment: Text.AlignRight
        }

        PC3.Label {
            text: resetText
            font.pixelSize: 10
            color: Kirigami.Theme.disabledTextColor
            Layout.minimumWidth: 70
        }
    }
}

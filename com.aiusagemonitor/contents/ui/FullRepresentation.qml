import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.plasma.plasmoid
import org.kde.plasma.components as PC3
import org.kde.kirigami as Kirigami

Item {
    id: fullRoot
    implicitWidth: 360
    implicitHeight: contentCol.implicitHeight + 24

    property var cd: root.claudeData
    property var od: root.codexData
    property var gd: root.geminiData
    property bool geminiExpanded: false
    onGdChanged: {
        if (!gd || !gd.buckets || gd.buckets.length <= 1)
            geminiExpanded = false
    }

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

    ColumnLayout {
        id: contentCol
        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12 }
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
                    visible: cd.seven_day_pct === null || cd.seven_day_pct === undefined
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

        // ── GEMINI CLI ─────────────────────────────────────────────────────
        Loader {
            Layout.fillWidth: true
            Layout.preferredHeight: active ? implicitHeight : 0
            visible: active
            active: gd.installed === true && root.showGemini === true

            sourceComponent: ColumnLayout {
                id: geminiCard
                spacing: 6
                readonly property bool canExpand: !!(gd.buckets && gd.buckets.length > 1 && !gd.error)

                RowLayout {
                    id: geminiHeaderRow
                    Image {
                        source: Qt.resolvedUrl("../images/gemini_icon.png")
                        width: 16; height: 16; fillMode: Image.PreserveAspectFit; smooth: true
                    }
                    PC3.Label { text: "GEMINI CLI"; font.bold: true; font.pixelSize: 12 }
                    Item { Layout.fillWidth: true }
                    QQC2.Button {
                        visible: geminiCard.canExpand
                        text: fullRoot.geminiExpanded
                            ? "Hide models"
                            : ("Models (" + (gd.buckets ? gd.buckets.length : 0) + ")")
                        onClicked: fullRoot.geminiExpanded = !fullRoot.geminiExpanded
                    }
                }

                // Collapsed: single overview bar (model with lowest remaining fraction)
                Loader {
                    Layout.fillWidth: true
                    active: gd.used_pct !== undefined && !gd.error && !fullRoot.geminiExpanded

                    sourceComponent: UsageBar {
                        label: gd.model ? fullRoot.prettyGeminiModel(gd.model) : "Gemini quota"
                        pct: Math.min(gd.used_pct || 0, 100)
                        pctText: (gd.used_pct || 0) + "%"
                        resetText: fullRoot.formatReset(gd.reset_time)
                        barColor: fullRoot.usageColor(gd.used_pct || 0)
                    }
                }

                // Expanded: one bar per model bucket
                Repeater {
                    model: (fullRoot.geminiExpanded && gd.buckets) ? gd.buckets : []
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
                    visible: !!gd.error
                    text: gd.error || ""
                    font.pixelSize: 10
                    color: Kirigami.Theme.negativeTextColor
                    wrapMode: Text.Wrap
                    width: 320
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
            active: !claudeVisible && !codexVisible && !geminiVisible

            sourceComponent: PC3.Label {
                text: {
                    if (root.isLoading) return "Loading…"
                    var allHidden = (cd.installed === true || od.installed === true || gd.installed === true)
                    return allHidden ? "All tools hidden in settings" : "No AI tools detected"
                }
                color: Kirigami.Theme.disabledTextColor
                horizontalAlignment: Text.AlignHCenter
                Layout.fillWidth: true
            }
        }

        Item { height: 4 }
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

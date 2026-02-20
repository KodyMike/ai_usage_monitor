import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.components as PC3
import org.kde.kirigami as Kirigami

Item {
    id: compactRoot

    property var cd: root.claudeData
    property var od: root.codexData
    property var gd: root.geminiData

    property string panelTool: Plasmoid.configuration.panelTool || "claude"
    property int displayMode: Plasmoid.configuration.panelDisplayMode || 0

    property var activeData: {
        if (panelTool === "codex")  return od
        if (panelTool === "gemini") return gd
        return cd
    }

    property real activePct: {
        if (panelTool === "gemini") return Math.min((gd.used_pct || 0), 100)
        return Math.min((activeData.five_hour_pct || 0), 100)
    }

    property string activeText: {
        if (root.isLoading) return "…"
        if (panelTool === "gemini")
            return (gd.used_pct !== undefined) ? (gd.used_pct + "%") : "—"
        return activeData.five_hour_pct !== undefined ? activeData.five_hour_pct + "%" : "—"
    }

    property string iconSource: {
        if (panelTool === "codex")  return Qt.resolvedUrl("../images/codex_icon.png")
        if (panelTool === "gemini") return Qt.resolvedUrl("../images/gemini_icon.png")
        return Qt.resolvedUrl("../images/claude-icon-22.png")
    }

    function ringColor() {
        if (panelTool === "gemini")
            return gd.authenticated === true ? "#22c55e" : "#ef4444"
        var p = activePct
        if (p >= 90) return "#ef4444"
        if (p >= 70) return "#f97316"
        if (p >= 40) return "#eab308"
        return "#22c55e"
    }

    MouseArea {
        anchors.fill: parent
        onClicked: root.expanded = !root.expanded
    }

    RowLayout {
        id: row
        anchors.centerIn: parent
        spacing: 5

        // ── Tool icon ────────────────────────────────────────────────────
        Image {
            source: compactRoot.iconSource
            width: 16; height: 16
            fillMode: Image.PreserveAspectFit
            smooth: true
            visible: activeData.installed === true
        }

        // ── Ring (modes 0 and 1) ─────────────────────────────────────────
        Item {
            visible: activeData.installed === true && displayMode < 2
            width: 34; height: 34

            Canvas {
                id: progressRing
                anchors.fill: parent

                property real pct: compactRoot.activePct
                property color color: Qt.color(compactRoot.ringColor())

                onPctChanged:   requestPaint()
                onColorChanged: requestPaint()

                onPaint: {
                    var ctx = getContext("2d")
                    ctx.clearRect(0, 0, width, height)
                    var cx = width  / 2
                    var cy = height / 2
                    var r  = cx - 3
                    var lw = 3

                    ctx.beginPath()
                    ctx.arc(cx, cy, r, 0, 2 * Math.PI)
                    ctx.strokeStyle = Qt.rgba(1, 1, 1, 0.18)
                    ctx.lineWidth = lw
                    ctx.stroke()

                    if (pct > 0) {
                        ctx.beginPath()
                        ctx.arc(cx, cy, r,
                                -Math.PI / 2,
                                -Math.PI / 2 + 2 * Math.PI * (pct / 100))
                        ctx.strokeStyle = color
                        ctx.lineWidth = lw
                        ctx.stroke()
                    }
                }
            }

            // Text inside ring — mode 0 only
            Text {
                visible: displayMode === 0
                anchors.centerIn: parent
                text: compactRoot.activeText
                font.pixelSize: 9
                font.bold: true
                color: Qt.color(compactRoot.ringColor())
                horizontalAlignment: Text.AlignHCenter
            }
        }

        // ── Text only — mode 2 ───────────────────────────────────────────
        PC3.Label {
            visible: activeData.installed === true && displayMode === 2
            text: compactRoot.activeText
            font.pixelSize: 12
            font.bold: true
            color: Qt.color(compactRoot.ringColor())
        }

        // Loading fallback
        PC3.Label {
            visible: root.isLoading && activeData.installed !== true
            text: "…"
            font.pixelSize: 11
            color: Kirigami.Theme.disabledTextColor
        }
    }
}

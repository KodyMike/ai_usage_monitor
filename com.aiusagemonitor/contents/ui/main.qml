import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.plasma5support as P5Support

PlasmoidItem {
    id: root

    // Parsed data from Python script
    property var claudeData: ({})
    property var codexData: ({})
    property var geminiData: ({})
    property var opencodeData: ({})
    // isLoading derives directly from in-flight sources. A manual +1/-1 counter
    // desyncs because the executable engine collapses identical sources: if the
    // same provider is requested twice while in flight, only one newData fires,
    // so the counter would stay > 0 forever and freeze isLoading (grey button).
    readonly property bool isLoading: runner.connectedSources.length > 0
    property string lastError: ""
    property string lastUpdated: ""

    readonly property int claudeRefreshMs: (Plasmoid.configuration.claudeRefreshSecs || 600) * 1000
    readonly property int codexRefreshMs:  (Plasmoid.configuration.codexRefreshSecs  || 60)  * 1000
    readonly property int geminiRefreshMs: (Plasmoid.configuration.geminiRefreshSecs || 300) * 1000
    readonly property int opencodeRefreshMs: (Plasmoid.configuration.opencodeRefreshSecs || 600) * 1000

    // Visibility settings
    readonly property bool showClaude: Plasmoid.configuration.showClaude !== false
    readonly property bool showCodex: Plasmoid.configuration.showCodex !== false
    readonly property bool showGemini: Plasmoid.configuration.showGemini !== false
    readonly property bool showOpencode: Plasmoid.configuration.showOpencode !== false

    // OpenCode Go dollar-value limits + subscription renewal day (anchors the monthly window)
    readonly property int opencodeLimit5h:    Plasmoid.configuration.opencodeLimit5h    || 12
    readonly property int opencodeLimitWeek:  Plasmoid.configuration.opencodeLimitWeek  || 30
    readonly property int opencodeLimitMonth: Plasmoid.configuration.opencodeLimitMonth || 60
    readonly property int opencodeBillingDay: Plasmoid.configuration.opencodeBillingDay || 1

    // Path to the Python script (resolved relative to this QML file)
    readonly property string scriptPath: {
        var url = Qt.resolvedUrl("../scripts/fetch_all_usage.py").toString()
        return url.replace(/^file:\/\//, "")
    }

    // In windowed/planar mode, show the full view by default.
    // In panel mode, keep compact view.
    preferredRepresentation: Plasmoid.formFactor === PlasmaCore.Types.Planar
        ? fullRepresentation
        : compactRepresentation
    compactRepresentation: CompactRepresentation { }
    fullRepresentation: FullRepresentation { }

    // Tell the panel exactly how much space this widget needs
    Layout.fillWidth: false
    Layout.minimumWidth: 66
    Layout.preferredWidth: 66
    Layout.maximumWidth: 66

    // Executable data source — runs the Python script
    P5Support.DataSource {
        id: runner
        engine: "executable"
        connectedSources: []

        onNewData: function(sourceName, data) {
            disconnectSource(sourceName)
            var stdout = (data["stdout"] || "").trim()
            var stderr = (data["stderr"] || "").trim()
            if (stdout === "") {
                root.lastError = stderr || "No output from script"
                return
            }
            try {
                var result = JSON.parse(stdout)
                if (result.claude   !== undefined) root.claudeData   = result.claude   || {}
                if (result.codex    !== undefined) root.codexData    = result.codex    || {}
                if (result.gemini   !== undefined) root.geminiData   = result.gemini   || {}
                if (result.opencode !== undefined) root.opencodeData = result.opencode || {}
                root.lastError = ""
                var now = new Date()
                root.lastUpdated = now.getHours().toString().padStart(2, "0") + ":" +
                                   now.getMinutes().toString().padStart(2, "0") + ":" +
                                   now.getSeconds().toString().padStart(2, "0")
            } catch (e) {
                root.lastError = "Parse error: " + e.message
            }
        }
    }

    function refreshProvider(provider) {
        if (scriptPath === "") return
        var cmd = "python3 \"" + scriptPath + "\" " + provider
        if (provider === "opencode")
            cmd += " " + root.opencodeBillingDay   // pass billing-cycle reset day
        // Skip if this exact source is still in flight (the engine would dedupe it).
        if (runner.connectedSources.indexOf(cmd) !== -1) return
        runner.connectSource(cmd)
    }

    function refresh() {
        refreshProvider("claude")
        refreshProvider("codex")
        refreshProvider("gemini")
        refreshProvider("opencode")
    }

    // Per-provider timers
    Timer {
        id: claudeTimer
        interval: root.claudeRefreshMs
        running: true; repeat: true
        onTriggered: root.refreshProvider("claude")
    }
    Timer {
        id: codexTimer
        interval: root.codexRefreshMs
        running: true; repeat: true
        onTriggered: root.refreshProvider("codex")
    }
    Timer {
        id: geminiTimer
        interval: root.geminiRefreshMs
        running: true; repeat: true
        onTriggered: root.refreshProvider("gemini")
    }
    Timer {
        id: opencodeTimer
        interval: root.opencodeRefreshMs
        running: true; repeat: true
        onTriggered: root.refreshProvider("opencode")
    }

    onClaudeRefreshMsChanged:   { claudeTimer.interval   = root.claudeRefreshMs;   claudeTimer.restart()   }
    onCodexRefreshMsChanged:    { codexTimer.interval    = root.codexRefreshMs;    codexTimer.restart()    }
    onGeminiRefreshMsChanged:   { geminiTimer.interval   = root.geminiRefreshMs;   geminiTimer.restart()   }
    onOpencodeRefreshMsChanged: { opencodeTimer.interval = root.opencodeRefreshMs; opencodeTimer.restart() }
    onOpencodeBillingDayChanged: root.refreshProvider("opencode")

    // Initial load
    Component.onCompleted: root.refresh()
}

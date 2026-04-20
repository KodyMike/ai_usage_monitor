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
    property int pendingRefreshes: 0
    readonly property bool isLoading: pendingRefreshes > 0
    property string lastError: ""
    property string lastUpdated: ""

    readonly property int claudeRefreshMs: (Plasmoid.configuration.claudeRefreshSecs || 600) * 1000
    readonly property int codexRefreshMs:  (Plasmoid.configuration.codexRefreshSecs  || 60)  * 1000
    readonly property int geminiRefreshMs: (Plasmoid.configuration.geminiRefreshSecs || 300) * 1000

    // Visibility settings
    readonly property bool showClaude: Plasmoid.configuration.showClaude !== false
    readonly property bool showCodex: Plasmoid.configuration.showCodex !== false
    readonly property bool showGemini: Plasmoid.configuration.showGemini !== false

    // A provider is polled if it is shown in the popup OR selected as the panel tool.
    // Hidden providers skip all API/script calls — avoids rate limiting and wasted work.
    readonly property string panelTool: Plasmoid.configuration.panelTool || "claude"
    readonly property bool claudeEnabled: showClaude || panelTool === "claude"
    readonly property bool codexEnabled:  showCodex  || panelTool === "codex"
    readonly property bool geminiEnabled: showGemini || panelTool === "gemini"

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
            root.pendingRefreshes = Math.max(0, root.pendingRefreshes - 1)
            var stdout = (data["stdout"] || "").trim()
            var stderr = (data["stderr"] || "").trim()
            if (stdout === "") {
                root.lastError = stderr || "No output from script"
                return
            }
            try {
                var result = JSON.parse(stdout)
                if (result.claude !== undefined) root.claudeData = result.claude || {}
                if (result.codex  !== undefined) root.codexData  = result.codex  || {}
                if (result.gemini !== undefined) root.geminiData = result.gemini || {}
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
        root.pendingRefreshes += 1
        runner.connectSource("python3 \"" + scriptPath + "\" " + provider)
    }

    function refresh() {
        if (claudeEnabled) refreshProvider("claude")
        if (codexEnabled)  refreshProvider("codex")
        if (geminiEnabled) refreshProvider("gemini")
    }

    // Per-provider timers — only run while the provider is enabled.
    Timer {
        id: claudeTimer
        interval: root.claudeRefreshMs
        running: root.claudeEnabled
        repeat: true
        onTriggered: root.refreshProvider("claude")
    }
    Timer {
        id: codexTimer
        interval: root.codexRefreshMs
        running: root.codexEnabled
        repeat: true
        onTriggered: root.refreshProvider("codex")
    }
    Timer {
        id: geminiTimer
        interval: root.geminiRefreshMs
        running: root.geminiEnabled
        repeat: true
        onTriggered: root.refreshProvider("gemini")
    }

    onClaudeRefreshMsChanged: { claudeTimer.interval = root.claudeRefreshMs; claudeTimer.restart() }
    onCodexRefreshMsChanged:  { codexTimer.interval  = root.codexRefreshMs;  codexTimer.restart()  }
    onGeminiRefreshMsChanged: { geminiTimer.interval = root.geminiRefreshMs; geminiTimer.restart() }

    // Fetch immediately when a provider is (re-)enabled, so users don't wait a full interval.
    // The _ready gate prevents double-fetches during initial property binding, which would
    // otherwise race with Component.onCompleted.
    property bool _ready: false
    onClaudeEnabledChanged: if (_ready && claudeEnabled) refreshProvider("claude")
    onCodexEnabledChanged:  if (_ready && codexEnabled)  refreshProvider("codex")
    onGeminiEnabledChanged: if (_ready && geminiEnabled) refreshProvider("gemini")

    // Initial load
    Component.onCompleted: { _ready = true; root.refresh() }
}

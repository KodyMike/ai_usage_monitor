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
    // Per-provider fetch start time (epoch ms), 0 when idle.
    //
    // This was a single counter, incremented per start and decremented per
    // result. Any fetch that started but never delivered a result left it
    // permanently above zero, so isLoading stayed true forever — which
    // disabled the refresh button and kept the panel showing "…" instead of a
    // percentage. Tracking per provider makes each fetch's state recoverable
    // and lets a duplicate start be a no-op rather than an unbalanced count.
    property var fetchStarted: ({ "claude": 0, "codex": 0, "gemini": 0 })
    readonly property bool isLoading: fetchStarted.claude > 0
        || fetchStarted.codex > 0
        || fetchStarted.gemini > 0

    // Backstop: a script that never reports back must not disable the UI.
    readonly property int fetchTimeoutMs: 60000

    // Nothing may be fetched until the component is complete. Property change
    // handlers run during initial binding evaluation, when the DataSource
    // below is not ready yet, and a connectSource() made that early is
    // silently dropped — no result ever arrives for it.
    property bool started: false
    property string lastError: ""
    property string lastUpdated: ""

    readonly property int claudeRefreshMs: (Plasmoid.configuration.claudeRefreshSecs || 600) * 1000
    readonly property int codexRefreshMs:  (Plasmoid.configuration.codexRefreshSecs  || 60)  * 1000
    readonly property int geminiRefreshMs: (Plasmoid.configuration.geminiRefreshSecs || 300) * 1000

    // Visibility settings
    readonly property bool showClaude: Plasmoid.configuration.showClaude !== false
    readonly property bool showCodex: Plasmoid.configuration.showCodex !== false
    readonly property bool showGemini: Plasmoid.configuration.showGemini !== false

    // A provider is polled only if it is shown in the popup or drives the panel
    // icon. Hidden providers made API calls nobody could see, which counted
    // against the same rate limit as the visible ones.
    readonly property string panelTool: Plasmoid.configuration.panelTool || "claude"
    readonly property bool claudePolled: showClaude || panelTool === "claude"
    readonly property bool codexPolled: showCodex || panelTool === "codex"
    readonly property bool geminiPolled: showGemini || panelTool === "gemini"

    // Per-provider backoff, in ms, applied on top of the configured interval
    // after a transient failure. Without this, a rate-limited token kept being
    // polled at the normal cadence and never got a chance to recover.
    property var backoffMs: ({ "claude": 0, "codex": 0, "gemini": 0 })
    readonly property int maxBackoffMs: 30 * 60 * 1000
    readonly property var transientFailures: [
        "rate_limited", "timeout", "network_error", "server_error", "http_error"
    ]

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
            var finished = root.providerFromSource(sourceName)
            if (finished !== "") root.setFetchStarted(finished, 0)
            var stdout = (data["stdout"] || "").trim()
            var stderr = (data["stderr"] || "").trim()
            if (stdout === "") {
                root.lastError = stderr || "No output from script"
                return
            }
            try {
                var result = JSON.parse(stdout)
                if (result.claude !== undefined) {
                    root.claudeData = result.claude || {}
                    root.applyBackoff("claude", root.claudeData, root.claudeRefreshMs)
                }
                if (result.codex !== undefined) {
                    root.codexData = result.codex || {}
                    root.applyBackoff("codex", root.codexData, root.codexRefreshMs)
                }
                if (result.gemini !== undefined) {
                    root.geminiData = result.gemini || {}
                    root.applyBackoff("gemini", root.geminiData, root.geminiRefreshMs)
                }
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
        if (!started || scriptPath === "") return
        // Already running: connecting the same source again would be ignored
        // anyway, and would leave this provider marked in-flight twice.
        if (fetchStarted[provider] > 0) return
        setFetchStarted(provider, Date.now())
        runner.connectSource("python3 \"" + scriptPath + "\" " + provider)
    }

    function providerFromSource(sourceName) {
        var parts = (sourceName || "").trim().split(" ")
        var last = parts[parts.length - 1]
        return (last === "claude" || last === "codex" || last === "gemini") ? last : ""
    }

    function setFetchStarted(provider, ms) {
        if (fetchStarted[provider] === ms) return
        // Replace the object rather than mutating it, so bindings re-evaluate.
        var next = {
            "claude": fetchStarted.claude,
            "codex": fetchStarted.codex,
            "gemini": fetchStarted.gemini
        }
        next[provider] = ms
        fetchStarted = next
    }

    function refresh() {
        if (claudePolled) refreshProvider("claude")
        if (codexPolled)  refreshProvider("codex")
        if (geminiPolled) refreshProvider("gemini")
    }

    // Grow the provider's poll interval while it keeps failing transiently,
    // honouring Retry-After when the provider sent one. Serving cached data
    // does not clear it: the provider is still failing, we just have something
    // to show. Only a clean answer resets the interval.
    function applyBackoff(provider, data, baseMs) {
        var failing = !!data && !!data.fail_reason
            && transientFailures.indexOf(data.fail_reason) !== -1
        if (!failing) {
            setBackoff(provider, 0)
            return
        }
        var next
        if (data.retry_after_secs !== undefined && data.retry_after_secs !== null)
            next = data.retry_after_secs * 1000
        else
            next = backoffMs[provider] > 0 ? backoffMs[provider] * 2 : baseMs * 2
        setBackoff(provider, Math.min(next, maxBackoffMs))
    }

    function setBackoff(provider, ms) {
        if (backoffMs[provider] === ms) return
        // Replace the object rather than mutating it, so bindings re-evaluate.
        var next = {
            "claude": backoffMs.claude,
            "codex": backoffMs.codex,
            "gemini": backoffMs.gemini
        }
        next[provider] = ms
        backoffMs = next
    }

    // Per-provider timers. The interval is the configured one unless a backoff
    // is in effect, in which case we poll no more often than the backoff.
    Timer {
        id: claudeTimer
        interval: Math.max(root.claudeRefreshMs, root.backoffMs.claude)
        running: root.claudePolled; repeat: true
        onTriggered: root.refreshProvider("claude")
    }
    Timer {
        id: codexTimer
        interval: Math.max(root.codexRefreshMs, root.backoffMs.codex)
        running: root.codexPolled; repeat: true
        onTriggered: root.refreshProvider("codex")
    }
    Timer {
        id: geminiTimer
        interval: Math.max(root.geminiRefreshMs, root.backoffMs.gemini)
        running: root.geminiPolled; repeat: true
        onTriggered: root.refreshProvider("gemini")
    }

    // Clear a fetch that never reported back, so an unresponsive script cannot
    // leave the refresh button disabled and the panel stuck on "…".
    Timer {
        interval: 10000
        running: true; repeat: true
        onTriggered: {
            var now = Date.now()
            var providers = ["claude", "codex", "gemini"]
            for (var i = 0; i < providers.length; i++) {
                var p = providers[i]
                if (root.fetchStarted[p] > 0 && now - root.fetchStarted[p] > root.fetchTimeoutMs)
                    root.setFetchStarted(p, 0)
            }
        }
    }

    onClaudeRefreshMsChanged: claudeTimer.restart()
    onCodexRefreshMsChanged:  codexTimer.restart()
    onGeminiRefreshMsChanged: geminiTimer.restart()

    // Fetch immediately when a provider is switched back on, instead of
    // leaving it blank until the next tick. refreshProvider() ignores these
    // until the component is complete.
    onClaudePolledChanged: if (claudePolled) refreshProvider("claude")
    onCodexPolledChanged:  if (codexPolled)  refreshProvider("codex")
    onGeminiPolledChanged: if (geminiPolled) refreshProvider("gemini")

    // Initial load
    Component.onCompleted: {
        root.started = true
        root.refresh()
    }
}

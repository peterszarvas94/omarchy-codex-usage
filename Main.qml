import QtQuick
import Quickshell
import Quickshell.Io

// Codex-only data source. The stock Omarchy collector writes codex.json;
// this object watches that one record and refreshes it through the plugin's
// Codex wrapper.
Item {
  id: root
  visible: false

  property var settings: ({})
  property var record: null
  property string queuedRefresh: ""

  readonly property string home: Quickshell.env("HOME") || ""
  readonly property string usageDir: (Quickshell.env("XDG_STATE_HOME") || home + "/.local/state")
    + "/omarchy/agents/usage"
  readonly property string usagePath: usageDir + "/codex.json"
  readonly property string updater: home
    + "/.config/omarchy/plugins/io.github.peterszarvas94.codex-usage/bin/omarchy-agent-usage-update"
  readonly property int refreshIntervalSec: Math.max(30, Number(setting("refreshIntervalSec", 900)))
  readonly property bool hasData: !!record && ((record.limits && record.limits.length > 0) || !!record.balance)

  function setting(name, fallback) {
    var value = settings ? settings[name] : undefined
    return value === undefined || value === null ? fallback : value
  }

  function parseRecord(content) {
    try {
      var parsed = JSON.parse(String(content || ""))
      record = parsed && typeof parsed === "object" ? parsed : null
    } catch (error) {
      console.warn("codex-usage", "Ignoring invalid Codex usage record", error)
      record = null
    }
  }

  function commandFor(kind) {
    var command = [updater]
    if (kind === "force") command.push("--force")
    if (kind === "limits") command.push("--limits-only")
    command.push("codex")
    return command
  }

  function runUpdate(kind) {
    if (updateProcess.running) {
      if (kind === "force" || queuedRefresh === "") queuedRefresh = kind
      return
    }
    updateProcess.command = commandFor(kind)
    updateProcess.running = true
  }

  function refreshAll(force) { runUpdate(force === true ? "force" : "normal") }
  function refreshLimits() { runUpdate("limits") }

  FileView {
    id: usageFile
    path: root.usagePath
    watchChanges: true
    printErrors: false
    onLoaded: root.parseRecord(text())
    onFileChanged: reload()
    onLoadFailed: root.record = null
  }

  Process {
    id: updateProcess
    running: false
    onExited: {
      usageFile.reload()
      if (root.queuedRefresh !== "") {
        var kind = root.queuedRefresh
        root.queuedRefresh = ""
        root.runUpdate(kind)
      }
    }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: if (text.trim() !== "") console.warn("codex-usage", text.trim())
    }
  }

  Timer {
    interval: root.refreshIntervalSec * 1000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.runUpdate("normal")
  }
}

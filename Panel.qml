import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

Panel {
  id: root
  moduleName: "io.github.peterszarvas94.codex-usage"
  ipcTarget: "io.github.peterszarvas94.codex-usage"
  manageIpc: false

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property color surface: Color.popups.background
  readonly property color track: Style.selectedFillFor(foreground, Color.accent)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property string usagePageUrl: "https://chatgpt.com/codex/cloud/settings/analytics#usage"

  property var purchasedCredits: null
  property double nowMs: Date.now()

  readonly property var record: usage.record
  readonly property var limits: normalizedLimits(record)
  readonly property var shortLimit: findLimit(false)
  readonly property var balance: purchasedCredits || (record ? record.balance : null)
  readonly property bool alarming: {
    for (var i = 0; i < limits.length; i++)
      if (limits[i].percent >= 0.9) return true
    return false
  }

  function clamp(value, low, high) { return Math.max(low, Math.min(high, value)) }

  function normalizedLimits(source) {
    var result = []
    var entries = source && Array.isArray(source.limits) ? source.limits : []
    for (var i = 0; i < entries.length; i++) {
      var entry = entries[i] || {}
      var label = String(entry.label || entry.title || "").toLowerCase()
      var percent = Number(entry.percent)
      if (!isFinite(percent) || percent < 0) continue
      result.push({
        title: label.indexOf("week") >= 0 || label.indexOf("7-day") >= 0 ? "Weekly" : "5-hour",
        percent: percent,
        resetAt: String(entry.resetsAt || entry.resetAt || "")
      })
    }
    return result
  }

  function findLimit(longWindow) {
    for (var i = 0; i < limits.length; i++) {
      var weekly = limits[i].title === "Weekly"
      if (weekly === longWindow) return limits[i]
    }
    return null
  }

  function remainingText(limit) {
    return limit ? Math.round((1 - limit.percent) * 100) + "%" : ""
  }

  function resetText(limit) {
    if (!limit || !limit.resetAt) return ""
    var date = new Date(limit.resetAt)
    if (isNaN(date.getTime())) return ""
    return "Resets " + Qt.formatDateTime(date, limit.title === "Weekly" ? "dd.MM" : "HH:mm")
  }

  function colorChannelLuminance(value) {
    value /= 255
    return value <= 0.03928 ? value / 12.92 : Math.pow((value + 0.055) / 1.055, 2.4)
  }

  function colorLuminance(color) {
    return 0.2126 * colorChannelLuminance(color.r * 255)
      + 0.7152 * colorChannelLuminance(color.g * 255)
      + 0.0722 * colorChannelLuminance(color.b * 255)
  }

  function formatMoney(value, currency) {
    var amount = Number(value)
    if (!isFinite(amount)) return "—"
    var code = String(currency || "USD").toUpperCase()
    var prefix = code === "USD" ? "$" : code === "EUR" ? "€" : code === "GBP" ? "£" : code + " "
    return prefix + amount.toFixed(2)
  }

  function refreshNow() { usage.refreshAll(true) }

  function openUsagePage() {
    Quickshell.execDetached(["xdg-open", usagePageUrl])
    close()
  }

  visible: usage.hasData
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onOpenedChanged: if (opened) {
    nowMs = Date.now()
    panelFlick.contentY = 0
    usage.refreshLimits()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  Main {
    id: usage
    settings: root.settings
  }

  FileView {
    id: creditsFile
    path: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state")
      + "/omarchy/agents/usage/codex-credits.json"
    watchChanges: true
    printErrors: false
    onLoaded: {
      try { root.purchasedCredits = JSON.parse(String(text() || "")) }
      catch (error) { root.purchasedCredits = null }
    }
    onFileChanged: reload()
    onLoadFailed: root.purchasedCredits = null
  }

  Timer {
    interval: 30000
    running: root.opened
    repeat: true
    onTriggered: root.nowMs = Date.now()
  }

  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): string { root.refreshNow(); return "ok" }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    fixedWidth: Style.space(62)
    text: ""
    hasVisualContent: true
    active: root.alarming

    Item {
      x: Style.space(9)
      width: Style.space(13)
      height: Style.space(13)
      anchors.verticalCenter: parent.verticalCenter

      Image {
        id: barCodexMask
        anchors.fill: parent
        source: Qt.resolvedUrl("assets/codex.svg")
        fillMode: Image.PreserveAspectFit
        visible: false
        layer.enabled: true
      }

      MultiEffect {
        anchors.fill: parent
        source: barCodexMask
        colorization: 1
        colorizationColor: button.active && button.useActiveColor
          ? button.activeColor
          : button.foreground
      }
    }

    Text {
      anchors.right: parent.right
      anchors.rightMargin: Style.space(8)
      anchors.verticalCenter: parent.verticalCenter
      text: root.remainingText(root.shortLimit)
      color: button.active && button.useActiveColor ? button.activeColor : button.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      font.bold: true
    }

    onPressed: root.toggle()
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(380))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(500))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onActivateRequested: root.refreshNow()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(text) { if (text === "r" || text === "R") root.refreshNow() }

      Flickable {
        id: panelFlick
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
          id: column
          width: panelFlick.width
          spacing: Style.space(12)

          PanelHero {
            width: parent.width
            title: "Codex"
            meta: ""
            foreground: root.foreground
            fontFamily: root.fontFamily
            iconComponent: Component {
              Item {
                width: Style.font.display
                height: Style.font.display
                Image {
                  anchors.fill: parent
                  source: root.colorLuminance(root.surface) >= 0.5
                    ? Qt.resolvedUrl("assets/codex-light.svg")
                    : Qt.resolvedUrl("assets/codex.svg")
                  fillMode: Image.PreserveAspectFit
                }
              }
            }
          }

          PanelSeparator {
            visible: root.limits.length > 0 || !!root.balance
            foreground: root.foreground
          }

          Item {
            visible: !!root.balance
            width: parent.width
            implicitHeight: visible ? Math.max(creditLabel.implicitHeight, creditValue.implicitHeight) : 0
            Text {
              id: creditLabel
              text: "Prepaid credits"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
            }
            Text {
              id: creditValue
              text: root.balance ? root.formatMoney(root.balance.remaining, root.balance.currency) : ""
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
            }
          }

          Repeater {
            model: root.limits
            LimitRow {
              required property var modelData
              width: column.width
              limit: modelData
            }
          }

          Button {
            width: parent.width
            text: "Open Codex usage"
            bordered: true
            foreground: root.foreground
            fontFamily: root.fontFamily
            fontSize: Style.font.bodySmall
            verticalPadding: Style.spacing.controlPaddingY
            onClicked: root.openUsagePage()
          }
        }
      }
    }
  }

  component LimitRow: Column {
    id: limitRow
    property var limit: null
    readonly property bool alarming: limit && limit.percent >= 0.9
    spacing: Style.space(6)

    Item {
      width: parent.width
      implicitHeight: Math.max(limitLabel.implicitHeight, limitValue.implicitHeight)
      Text {
        id: limitLabel
        text: limitRow.limit ? limitRow.limit.title : ""
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
      }
      Text {
        id: limitValue
        text: root.remainingText(limitRow.limit)
        color: limitRow.alarming ? root.urgent : root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
      }
    }

    Meter {
      width: parent.width
      value: limitRow.limit ? 1 - limitRow.limit.percent : 0
      alarming: limitRow.alarming
    }

    Text {
      width: parent.width
      text: root.resetText(limitRow.limit)
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
    }
  }

  component Meter: Item {
    id: meter
    property real value: 0
    property bool alarming: false
    property real thickness: Math.max(Style.space(4), Math.round(Style.spacing.controlHeight * 0.14))
    implicitHeight: thickness

    Rectangle {
      id: meterTrack
      anchors.fill: parent
      radius: height / 2
      color: root.track
    }
    Rectangle {
      anchors.left: meterTrack.left
      anchors.verticalCenter: meterTrack.verticalCenter
      height: meterTrack.height
      radius: meterTrack.radius
      width: meterTrack.width * root.clamp(meter.value, 0, 1)
      color: meter.alarming ? root.urgent : root.foreground
      Behavior on width {
        NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
      }
    }
  }
}

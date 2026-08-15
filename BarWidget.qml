import QtQuick
import Quickshell
import Quickshell.Io
import qs.Ui

BarWidget {
  id: root
  moduleName: "io.github.gdesoutter.proxmox"

  // --- settings, read from this widget's shell.json entry -------------------
  readonly property string endpoint:        setting("endpoint", "https://proxmox.example.com:8006")
  readonly property string credentialsFile: setting("credentialsFile", "")
  readonly property string caBundle:        setting("caBundle", "")
  readonly property int    interval:        setting("interval", 15)
  readonly property string clusterLabel:    setting("label", "")
  readonly property var    watchedGuests:   setting("watchedGuests", [])

  // --- state, consumed by Panel.qml ----------------------------------------
  property var    guests: []
  property string errorText: ""
  property bool   everLoaded: false
  property bool   fetching: false

  readonly property int totalCount: guests.length
  readonly property int runningCount:
    guests.filter(function (g) { return g.status === "running" }).length
  readonly property bool healthy: errorText === ""

  readonly property var watchedDown: {
    if (!watchedGuests || watchedGuests.length === 0) return []
    return guests.filter(function (g) {
      return watchedGuests.indexOf(g.vmid) !== -1 && g.status !== "running"
    })
  }

  readonly property bool alerting:
    everLoaded && (!healthy || watchedDown.length > 0)

  readonly property string scriptPath:
    Qt.resolvedUrl("bin/pve-status.sh").toString().replace(/^file:\/\//, "")

  // --- panel plumbing (same contract as the built-in clock) -----------------
  readonly property bool opened:
    panelLoader.item ? panelLoader.item.opened === true : false
  readonly property bool popoutSwitchClosing:
    panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false

  function open()   { if (panelLoader.item) panelLoader.item.open() }
  function close()  { if (panelLoader.item) panelLoader.item.close() }
  function toggle() { if (panelLoader.item) panelLoader.item.toggle() }
  function closeForPopoutSwitch() {
    if (panelLoader.item) panelLoader.item.closeForPopoutSwitch()
  }

  function injectPanel() {
    if (!panelLoader.item) return
    panelLoader.item.bar = root.bar
    panelLoader.item.anchorItem = button
    panelLoader.item.hostWidget = root
    panelLoader.item.settings = root.settings
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight
  onBarChanged: injectPanel()

  // --- polling --------------------------------------------------------------
  function applyPayload(text) {
    root.everLoaded = true
    var payload
    try {
      payload = JSON.parse(text)
    } catch (e) {
      root.errorText = "invalid response from poller"
      return
    }
    if (payload.error) {
      root.errorText = String(payload.error)
      return
    }
    root.errorText = ""
    root.guests = []
    root.guests = payload.guests || []
  }

  function refresh() {
    if (fetcher.running) return
    fetcher.running = true
  }

  onOpenedChanged: if (root.opened) root.refresh()

  Process {
    id: fetcher
    running: false
    command: [root.scriptPath, root.endpoint, root.credentialsFile, root.caBundle]
    onRunningChanged: root.fetching = fetcher.running
    stdout: StdioCollector {
      onStreamFinished: root.applyPayload(this.text)
    }
  }

  Timer {
    interval: (root.opened ? 10 : Math.max(10, root.interval)) * 1000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    active: root.alerting
    text: {
      if (!root.everLoaded) return "󰍹 …"
      if (!root.healthy)    return "󰍹 !"
      return "󰍹 " + root.runningCount + "/" + root.totalCount
    }
    tooltipText: root.healthy
      ? (root.clusterLabel || root.endpoint) + " — " + root.runningCount + "/"
        + root.totalCount + " running"
      : "Proxmox: " + root.errorText
    onPressed: function (buttonCode) {
      if (buttonCode === Qt.LeftButton)        root.toggle()
      else if (buttonCode === Qt.MiddleButton) root.refresh()
    }
  }
}

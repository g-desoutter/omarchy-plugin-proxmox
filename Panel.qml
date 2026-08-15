import QtQuick
import Quickshell
import qs.Commons
import qs.Ui

Panel {
  id: root
  moduleName: "io.github.gdesoutter.proxmox"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null

  // Keeps the refresh icon spinning for at least 500 ms so a fast LAN fetch
  // still produces a visible acknowledgement of the click.
  property bool spinning: false

  readonly property var    guests:    hostWidget ? hostWidget.guests : []
  readonly property string errorText: hostWidget ? hostWidget.errorText : ""
  readonly property bool   fetching:  hostWidget ? hostWidget.fetching === true : false
  readonly property string title:
    hostWidget ? (hostWidget.clusterLabel || hostWidget.endpoint) : "Proxmox"
  onFetchingChanged: {
    if (root.fetching) {
      root.spinning = true
      spinFloor.restart()
    }
  }

  Timer {
    id: spinFloor
    interval: 500
    onTriggered: root.spinning = false
  }

  function open()  { root.controller.show() }
  function close() { root.controller.hide() }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.hostWidget || root, direction)
    return false
  }

  function pct(used, max) { return max > 0 ? Math.round((used / max) * 100) : 0 }
  function gib(bytes)     { return (bytes / 1073741824).toFixed(1) + " GiB" }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.hostWidget || root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(380))
    contentHeight: panel.fittedContentHeight(content.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function (direction) { root.switchPanel(direction) }

      Column {
        id: content
        width: parent.width
        spacing: Style.space(8)
        opacity: root.spinning ? 0.6 : 1.0

        Behavior on opacity {
          NumberAnimation { duration: 120 }
        }

        Row {
          width: parent.width
          spacing: Style.space(8)

          Text {
            width: parent.width - refreshBtn.width - Style.space(8)
            anchors.verticalCenter: parent.verticalCenter
            text: root.title
            color: root.barForeground
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.subtitle
            font.bold: true
            elide: Text.ElideMiddle
          }

          Text {
            id: refreshBtn
            anchors.verticalCenter: parent.verticalCenter
            text: "󰑐"
            color: root.barForeground
            opacity: refreshArea.containsMouse ? 1.0 : 0.45
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.subtitle

            Behavior on opacity { NumberAnimation { duration: 100 } }

            RotationAnimator {
              target: refreshBtn
              from: 0
              to: 360
              duration: 700
              loops: Animation.Infinite
              running: root.spinning
              onRunningChanged: if (!running) refreshBtn.rotation = 0
            }

            MouseArea {
              id: refreshArea
              anchors.fill: parent
              anchors.margins: -Style.space(4)
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: if (root.hostWidget) root.hostWidget.refresh()
            }
          }
        }

        Text {
          width: parent.width
          visible: root.errorText !== ""
          text: root.errorText
          color: root.barForeground
          opacity: 0.7
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.body
          wrapMode: Text.WordWrap
        }

        Repeater {
          model: root.guests

          Row {
            width: content.width
            spacing: Style.space(8)

            Rectangle {
              width: Style.space(8); height: width; radius: width / 2
              anchors.verticalCenter: parent.verticalCenter
              color: root.barForeground
              opacity: modelData.status === "running" ? 1.0 : 0.25
            }

            Text {
              width: content.width * 0.38
              text: modelData.name + (modelData.type === "lxc" ? "  ct" : "")
              color: root.barForeground
              opacity: modelData.status === "running" ? 1.0 : 0.5
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.body
              elide: Text.ElideRight
            }

            Text {
              width: content.width * 0.16
              horizontalAlignment: Text.AlignRight
              text: modelData.status === "running"
                ? Math.round(modelData.cpu * 100) + "%" : "—"
              color: root.barForeground
              opacity: 0.7
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.body
            }

            Text {
              width: content.width * 0.32
              horizontalAlignment: Text.AlignRight
              text: modelData.status === "running"
                ? root.pct(modelData.mem, modelData.maxmem) + "%  " + root.gib(modelData.maxmem)
                : modelData.node
              color: root.barForeground
              opacity: 0.7
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.body
            }
          }
        }
      }
    }
  }
}

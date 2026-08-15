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

  property bool spinning: false

  readonly property var    guests:    hostWidget ? hostWidget.guests : []
  readonly property string errorText: hostWidget ? hostWidget.errorText : ""
  readonly property bool   fetching:  hostWidget ? hostWidget.fetching === true : false
  readonly property string title:
    hostWidget ? (hostWidget.clusterLabel || hostWidget.endpoint) : "Proxmox"

  readonly property real colOs:   Style.space(16)
  readonly property real colName: 0.34
  readonly property real colCpu:  0.16
  readonly property real colMem:  0.34

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

  function gib(bytes)  { return (bytes / 1073741824).toFixed(1) }
  function gibU(bytes) { return (bytes / 1073741824).toFixed(1) + " GiB" }

  function osGlyph(g) {
    if (g.type === "lxc") return "󰆧"
    var o = String(g.ostype || "")
    if (o.indexOf("win") === 0 || o.indexOf("w2k") === 0) return "󰍲"
    if (o === "l26" || o === "l24") return "󰌽"
    return "󰋙"
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.hostWidget || root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(400))
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

        Row {
          width: parent.width
          spacing: Style.space(8)
          visible: root.guests.length > 0

          Item { width: Style.space(8); height: 1 }
          Item { width: root.colOs; height: 1 }

          Text {
            width: content.width * root.colName
            text: "guest"
            color: root.barForeground
            opacity: 0.85
            font.bold: true
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.body
          }

          Text {
            width: content.width * root.colCpu
            horizontalAlignment: Text.AlignRight
            text: "cpu"
            color: root.barForeground
            opacity: 0.85
            font.bold: true
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.body
          }

          Text {
            width: content.width * root.colMem
            horizontalAlignment: Text.AlignRight
            text: "memory"
            color: root.barForeground
            opacity: 0.85
            font.bold: true
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.body
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
              opacity: modelData.status === "running" ? 0.9 : 0.45
            }

            Text {
              width: root.colOs
              anchors.verticalCenter: parent.verticalCenter
              text: root.osGlyph(modelData)
              color: root.barForeground
              opacity: modelData.status === "running" ? 0.8 : 0.3
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.body
            }

            Text {
              width: content.width * root.colName
              text: modelData.name
              color: root.barForeground
              opacity: modelData.status === "running" ? 1.0 : 0.5
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.body
              elide: Text.ElideRight
            }

            Text {
              width: content.width * root.colCpu
              horizontalAlignment: Text.AlignRight
              text: modelData.status === "running"
                ? Math.round(modelData.cpu * 100) + "%" : "—"
              color: root.barForeground
              opacity: 0.7
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.body
            }

            Text {
              width: content.width * root.colMem
              horizontalAlignment: Text.AlignRight
              text: modelData.status === "running"
                ? root.gib(modelData.mem) + " / " + root.gibU(modelData.maxmem)
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

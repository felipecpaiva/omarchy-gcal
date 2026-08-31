import QtQuick
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Full-detail view for one agenda entry, opened over the month grid rather
// than in a separate window — the panel already owns the popup chrome
// (anchoring, sizing, keyboard focus), so this only ever needs to be the
// content that goes inside it. Panel.qml owns the open/close state; this
// component just renders whatever `event` it's handed and reports back
// via `closeRequested` when the user is done with it.
Item {
  id: root

  property var event: null
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family
  readonly property string joinUrl: root.event ? Model.extractJoinUrl(root.event) : ""

  signal closeRequested()

  Rectangle {
    anchors.fill: parent
    color: Color.background
  }

  Process {
    id: openLinkProcess
    command: ["xdg-open", root.joinUrl]
  }

  Flickable {
    anchors.fill: parent
    anchors.margins: Style.space(4)
    contentWidth: width
    contentHeight: detailColumn.implicitHeight
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    interactive: contentHeight > height

    Column {
      id: detailColumn
      width: parent.width
      spacing: Style.space(10)

      // ---- Back control. Same action-button language as the month
      //      nav chevrons, so it reads as part of the same panel.
      Item {
        width: parent.width
        height: backButton.implicitHeight

        PanelActionButton {
          id: backButton
          anchors.left: parent.left
          iconText: "󰅁"
          tooltipText: "Back to agenda"
          foreground: root.foreground
          fontFamily: root.fontFamily
          onClicked: root.closeRequested()
        }
      }

      Text {
        textFormat: Text.PlainText
        width: parent.width
        wrapMode: Text.WordWrap
        text: root.event ? (root.event.title || "(untitled event)") : ""
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.headerSmall !== undefined ? Style.font.headerSmall : Style.font.body
        font.bold: true
      }

      Text {
        textFormat: Text.PlainText
        width: parent.width
        wrapMode: Text.WordWrap
        visible: !!root.event
        text: root.event ? timeRangeText(root.event) : ""
        color: Qt.darker(root.foreground, 1.4)
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
      }

      Text {
        textFormat: Text.PlainText
        width: parent.width
        wrapMode: Text.WordWrap
        visible: !!(root.event && root.event.location)
        text: "Location: " + (root.event ? root.event.location : "")
        color: Qt.darker(root.foreground, 1.4)
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
      }

      // ---- Join. Only present when the event actually carries a
      //      Meet/Zoom/Teams link — never a dead button.
      PanelActionButton {
        visible: root.joinUrl !== ""
        iconText: "󰍹"
        tooltipText: "Join meeting"
        foreground: root.foreground
        fontFamily: root.fontFamily
        onClicked: openLinkProcess.running = true
      }

      Rectangle {
        width: parent.width
        height: Style.spacing.hairline
        color: root.foreground
        opacity: 0.12
        visible: !!(root.event && root.event.description)
      }

      Text {
        textFormat: Text.PlainText
        width: parent.width
        wrapMode: Text.WordWrap
        visible: !!(root.event && root.event.description)
        text: root.event ? root.event.description : ""
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
      }

      Rectangle {
        width: parent.width
        height: Style.spacing.hairline
        color: root.foreground
        opacity: 0.12
        visible: !!(root.event && root.event.attendees && root.event.attendees.length > 0)
      }

      Text {
        textFormat: Text.PlainText
        visible: !!(root.event && root.event.attendees && root.event.attendees.length > 0)
        text: "ATTENDEES"
        color: Qt.darker(root.foreground, 1.5)
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        font.letterSpacing: 1
      }

      Repeater {
        model: root.event && root.event.attendees ? root.event.attendees : []

        Text {
          required property var modelData
          textFormat: Text.PlainText
          width: detailColumn.width
          wrapMode: Text.WordWrap
          text: (modelData.name || modelData.email || "Unknown") + statusSuffix(modelData.status)
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
        }
      }
    }
  }

  function timeRangeText(event) {
    if (event.allDay) return "All day"
    var start = new Date(event.start)
    var end = new Date(event.end)
    return Qt.formatDateTime(start, "ddd, MMM d · HH:mm") + " – " + Qt.formatTime(end, "HH:mm")
  }

  function statusSuffix(status) {
    if (!status) return ""
    var normalized = String(status).toLowerCase()
    if (normalized === "accepted") return "  ✓"
    if (normalized === "declined") return "  ✗"
    if (normalized === "tentative") return "  ?"
    return ""
  }
}

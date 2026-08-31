import QtQuick
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
  // Google Calendar's own app treats ANY location as tappable, not just a
  // literal URL — a plain street address opens a Maps search. Same here:
  // a bare http(s) link opens as-is, anything else becomes a Maps query.
  readonly property string locationUrl: {
    var loc = root.event && root.event.location ? String(root.event.location).trim() : ""
    if (!loc) return ""
    if (/^https?:\/\/\S+$/i.test(loc)) return loc
    return "https://www.google.com/maps/search/?api=1&query=" + encodeURIComponent(loc)
  }

  signal closeRequested()
  // Fired right before handing off to an external app (browser, meeting
  // client) — the popup has no reason to stay open once focus is about
  // to leave it anyway.
  signal externalOpened()

  function openExternal(url) {
    Util.execArgv(["xdg-open", url])
    root.externalOpened()
  }

  Rectangle {
    anchors.fill: parent
    color: Color.background
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
        font.strikeout: !!(root.event && root.event.status === "cancelled")
      }

      Text {
        textFormat: Text.PlainText
        width: parent.width
        visible: !!(root.event && root.event.status)
        text: root.event && root.event.status === "cancelled" ? "CANCELED" : "TENTATIVE"
        color: Color.accent
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        font.letterSpacing: 1
        font.bold: true
      }

      Text {
        textFormat: Text.PlainText
        width: parent.width
        wrapMode: Text.WordWrap
        visible: !!root.event
        text: (root.event ? timeRangeText(root.event) : "") + busySuffix(root.event)
        color: Qt.darker(root.foreground, 1.4)
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
      }

      Text {
        textFormat: Text.PlainText
        width: parent.width
        wrapMode: Text.WordWrap
        visible: !!(root.event && root.event.reminderMinutes !== null && root.event.reminderMinutes !== undefined)
        text: "󰀦 " + reminderText(root.event ? root.event.reminderMinutes : null)
        color: Qt.darker(root.foreground, 1.4)
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
      }

      Text {
        textFormat: Text.PlainText
        width: parent.width
        wrapMode: Text.WordWrap
        visible: !!(root.event && root.event.recurrence)
        text: "󰑓 " + (root.event ? root.event.recurrence : "")
        color: Qt.darker(root.foreground, 1.4)
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
      }

      Row {
        width: parent.width
        spacing: Style.space(6)
        visible: !!(root.event && root.event.calendarName)

        Rectangle {
          anchors.verticalCenter: parent.verticalCenter
          width: Style.space(8)
          height: Style.space(8)
          radius: width / 2
          color: root.event && root.event.calendarColor ? root.event.calendarColor : Color.accent
        }

        Text {
          textFormat: Text.PlainText
          anchors.verticalCenter: parent.verticalCenter
          width: parent.width - Style.space(14)
          wrapMode: Text.WordWrap
          text: root.event ? root.event.calendarName : ""
          color: Qt.darker(root.foreground, 1.4)
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
        }
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

      // A Maps link in the location field gets its own tap target — same
      // safe pattern as the Join button below, not a link embedded in
      // RichText (that broke the panel's layout when tapped).
      Row {
        visible: root.locationUrl !== ""
        spacing: Style.space(6)

        PanelActionButton {
          anchors.verticalCenter: parent.verticalCenter
          iconText: "󰌖"
          tooltipText: root.locationUrl
          foreground: root.foreground
          fontFamily: root.fontFamily
          onClicked: root.openExternal(root.locationUrl)
        }

        Text {
          textFormat: Text.PlainText
          anchors.verticalCenter: parent.verticalCenter
          text: "Open in Maps"
          color: Color.accent
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          font.bold: true

          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: root.openExternal(root.locationUrl)
          }
        }
      }

      Text {
        textFormat: Text.PlainText
        width: parent.width
        wrapMode: Text.WordWrap
        visible: !!(root.event && root.event.organizer)
        text: "Organized by " + (root.event && root.event.organizer ? (root.event.organizer.name || root.event.organizer.email) : "")
        color: Qt.darker(root.foreground, 1.4)
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
      }

      // ---- Join. Only present when the event actually carries a
      //      Meet/Zoom/Teams link — never a dead button. A labeled row
      //      rather than a bare icon: an icon-only button here reads as
      //      decoration, not as the primary action it actually is.
      Row {
        visible: root.joinUrl !== ""
        spacing: Style.space(6)

        PanelActionButton {
          anchors.verticalCenter: parent.verticalCenter
          iconText: "󰍹"
          tooltipText: root.joinUrl
          foreground: root.foreground
          fontFamily: root.fontFamily
          onClicked: root.openExternal(root.joinUrl)
        }

        Text {
          textFormat: Text.PlainText
          anchors.verticalCenter: parent.verticalCenter
          text: "Join meeting"
          color: Color.accent
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          font.bold: true

          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: root.openExternal(root.joinUrl)
          }
        }
      }

      Rectangle {
        width: parent.width
        height: Style.spacing.hairline
        color: root.foreground
        opacity: 0.12
        visible: !!(root.event && root.event.description)
      }

      Text {
        // Google Calendar descriptions arrive as real HTML (<b>, <br>,
        // <ul><li>, <a href>) — RichText renders that properly instead of
        // showing the raw tags as text, and gets clickable links (a
        // Zoom/Meet URL that only exists inside an <a> tag, no dedicated
        // URL property or plain-text mention) for free via onLinkActivated.
        textFormat: Text.RichText
        width: parent.width
        wrapMode: Text.WordWrap
        visible: !!(root.event && root.event.description)
        text: root.event ? root.event.description : ""
        color: root.foreground
        linkColor: Color.accent
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        onLinkActivated: function(link) { root.openExternal(link) }
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

  // busy === null means the event carried no TRANSP property at all —
  // stay silent rather than guess, same "no signal" handling as the
  // other optional fields.
  function busySuffix(event) {
    if (!event || event.busy === null || event.busy === undefined) return ""
    return event.busy ? "  ·  Busy" : "  ·  Free"
  }

  function reminderText(minutes) {
    if (minutes === null || minutes === undefined) return ""
    if (minutes === 0) return "At time of event"
    if (minutes % 1440 === 0) return (minutes / 1440) + (minutes === 1440 ? " day before" : " days before")
    if (minutes % 60 === 0) return (minutes / 60) + (minutes === 60 ? " hour before" : " hours before")
    return minutes + " minutes before"
  }
}

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// "Which calendars show on the bar" — the same job GNOME Calendar's own
// calendar-visibility toggle list does. Reuses the shell's own
// Ui/MultiSelect (searchable checklist, dynamic optionsCommand) instead
// of building a checkbox list from scratch; this component only wires it
// to sync/eds_read.py's --list-options / --print-selected / --set-selected.
Item {
  id: root

  // Computed here directly, the same way Panel.qml/BarWidget.qml compute
  // their own cache path, rather than depending on the Loader that
  // instantiates this component to hand it over at the right moment —
  // one less cross-component timing dependency to get wrong.
  readonly property string scriptPath: Quickshell.env("HOME") + "/.local/share/omarchy-google-calendar/eds_read.py"
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family

  property bool showNextEventBadge: true

  signal closeRequested()
  signal saved()
  signal showNextEventBadgeToggled(bool value)

  Rectangle {
    anchors.fill: parent
    color: Color.background
  }

  Process {
    id: initialSelectionProcess
    command: ["/usr/bin/python3", root.scriptPath, "--print-selected"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          picker.values = JSON.parse(text)
        } catch (e) {
          picker.values = []
        }
      }
    }
  }

  Process {
    id: saveProcess
    property bool pendingRefresh: false
    onExited: function() {
      if (pendingRefresh) { pendingRefresh = false; root.saved() }
    }
  }

  function save() {
    saveProcess.pendingRefresh = true
    saveProcess.command = ["/usr/bin/python3", root.scriptPath, "--set-selected", picker.values.join(",")]
    // Force a false->true transition even if a prior run left `running`
    // stuck true — the same reset dance Ui/MultiSelect's own refresh()
    // uses for exactly this reason (a bare `= true` is a no-op if it's
    // already true, so a second click would silently do nothing).
    saveProcess.running = false
    saveProcess.running = true
  }

  Component.onCompleted: initialSelectionProcess.running = true

  Column {
    anchors.fill: parent
    anchors.margins: Style.space(4)
    spacing: Style.space(10)

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
      text: "CALENDARS ON THE BAR"
      color: Qt.darker(root.foreground, 1.5)
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      font.letterSpacing: 1
    }

    Text {
      textFormat: Text.PlainText
      width: parent.width
      wrapMode: Text.WordWrap
      text: "Most Google accounts carry far more calendars than you want on a bar clock — pick the ones that matter."
      color: Qt.darker(root.foreground, 1.4)
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
    }

    MultiSelect {
      id: picker
      width: parent.width
      label: ""
      showLabel: false
      placeholderText: "Search calendars..."
      emptyText: "No calendars found — link a Google account first"
      noSelectionText: "None selected"
      // Deliberately NOT overriding foreground/background/accent here.
      // MultiSelect's defaults (Color.popups.text on Color.popups.background)
      // are a matched, theme-correct pair for a popup surface; forcing the
      // panel's own foreground onto it made trigger text unreadable against
      // the popup's actual background under this machine's active theme.
      fontFamily: root.fontFamily
      optionsCommand: ["/usr/bin/python3", root.scriptPath, "--list-options"]
    }

    Item {
      width: parent.width
      height: saveRow.implicitHeight

      Row {
        id: saveRow
        anchors.right: parent.right
        spacing: Style.space(6)

        PanelActionButton {
          anchors.verticalCenter: parent.verticalCenter
          iconText: saveProcess.pendingRefresh ? "󰑖" : "󰄬"
          tooltipText: saveProcess.pendingRefresh ? "Saving…" : "Save and refresh"
          foreground: root.foreground
          fontFamily: root.fontFamily
          enabled: !saveProcess.pendingRefresh
          onClicked: root.save()
        }

        Text {
          textFormat: Text.PlainText
          anchors.verticalCenter: parent.verticalCenter
          text: saveProcess.pendingRefresh ? "Saving…" : "Save"
          color: Color.accent
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          font.bold: true

          MouseArea {
            anchors.fill: parent
            enabled: !saveProcess.pendingRefresh
            cursorShape: Qt.PointingHandCursor
            onClicked: root.save()
          }
        }
      }
    }

    Rectangle {
      width: parent.width
      height: Style.spacing.hairline
      color: root.foreground
      opacity: 0.12
    }

    Text {
      textFormat: Text.PlainText
      text: "BAR DISPLAY"
      color: Qt.darker(root.foreground, 1.5)
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      font.letterSpacing: 1
    }

    Item {
      width: parent.width
      height: badgeToggleRow.implicitHeight

      Row {
        id: badgeToggleRow
        anchors.left: parent.left
        spacing: Style.space(6)

        Text {
          id: badgeToggleIcon
          textFormat: Text.PlainText
          anchors.verticalCenter: parent.verticalCenter
          text: root.showNextEventBadge ? "󰱒" : "󰄱"
          color: root.showNextEventBadge ? Color.accent : Qt.darker(root.foreground, 1.4)
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
        }

        Text {
          textFormat: Text.PlainText
          anchors.verticalCenter: parent.verticalCenter
          text: "Show next meeting time on the bar"
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
        }
      }

      MouseArea {
        anchors.fill: badgeToggleRow
        cursorShape: Qt.PointingHandCursor
        onClicked: {
          root.showNextEventBadge = !root.showNextEventBadge
          root.showNextEventBadgeToggled(root.showNextEventBadge)
        }
      }
    }
  }
}

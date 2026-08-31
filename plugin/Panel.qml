import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

// The clock's calendar popup: a month grid with ISO week numbers, built to
// sit beside the weather panel — same hero-over-detail composition, same
// spacing scale, same small-caps labels.
//
// The grid is a read-out rather than a picker: today is the only marked
// day, and the only thing that moves is which month is on screen —
// chevrons, the scroll wheel, and the arrow keys all step it.
//
// BarWidget.qml owns the bar label and hands this panel the button to
// anchor against.
Panel {
  id: root
  moduleName: "google-calendar.clock"
  ipcTarget: "google-calendar.clock"
  manageIpc: false

  property var anchorItem: null
  property var selectedEvent: null
  property bool showCalendarSettings: false

  // ---- Google Calendar agenda. The cache is written by sync/eds_read.py
  //      (GNOME Online Accounts + Evolution Data Server — see the plan doc
  //      for why nothing here talks to Google directly). watchChanges means
  //      the agenda updates itself the moment a sync — automatic or forced —
  //      finishes; the panel never polls.
  //
  //      The agenda follows whichever day is selected in the month grid,
  //      not a fixed multi-day window — clicking a day is how you ask
  //      "what's on then", the same as the grid's own today highlight.
  property date selectedDay: today
  readonly property string selectedDayKey: Model.keyForDate(selectedDay)
  readonly property string eventsCachePath: Quickshell.env("HOME") + "/.cache/omarchy-google-calendar/events.json"
  property var eventsCache: ({ events: [], lastSyncUtc: null, lastError: null, error: "missing" })
  readonly property var agendaEvents: Model.eventsOnDay(eventsCache.events, root.selectedDay)
  readonly property bool agendaStale: Model.isCacheStale(eventsCache.lastSyncUtc, root.today, 5)
  // Same computation BarWidget.qml uses for the bar badge — the panel's own
  // quick-reference line at the top just needs the label text alongside it.
  readonly property var nextEvent: Model.nextUpcomingEvent(eventsCache.events, root.today)
  readonly property string nextEventBadge: Model.badgeLabel(nextEvent, root.today)
  property bool refreshingCalendar: false

  function selectDay(year, month, day) {
    root.selectedDay = new Date(year, month, day)
  }

  FileView {
    id: eventsFile
    path: root.eventsCachePath
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.eventsCache = Model.parseEventsCache(text())
    onLoadFailed: root.eventsCache = Model.parseEventsCache(null)
  }

  // The service unit does the same `--refresh` on the 5-min timer; this is
  // the same job run early on request, not a second sync engine.
  Process {
    id: refreshProcess
    command: ["systemctl", "--user", "start", "omarchy-google-calendar-sync.service"]
    onExited: function() { root.refreshingCalendar = false }
  }

  function forceRefresh() {
    if (root.refreshingCalendar) return
    root.refreshingCalendar = true
    refreshProcess.running = true
  }

  function openEvent(event) {
    root.showCalendarSettings = false
    root.selectedEvent = event
  }

  function closeEvent() {
    root.selectedEvent = null
  }

  function openCalendarSettings() {
    root.selectedEvent = null
    root.showCalendarSettings = true
  }

  function closeCalendarSettings() {
    root.showCalendarSettings = false
  }

  // The bar tracks the widget mounted in its slot — BarWidget.qml — not this
  // nested panel. Everything the bar identifies a panel by has to be that
  // widget: the popout coordinator (and with it the open-panel dot under the
  // pill) compares against `slot.activeItem`, and switchPanelFrom looks the
  // slot up the same way.
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root

  // ---- Today. SystemClock keeps this honest across midnight so the
  //      highlight rolls over without the panel being reopened.
  property date today: new Date()
  readonly property string todayKey: Model.keyForDate(today)

  // The month on screen. Stepping moves this and nothing else: the grid is
  // a read-out, not a picker, so there is no per-day cursor to keep in sync.
  property int viewYear: today.getFullYear()
  property int viewMonth: today.getMonth()

  readonly property date viewDate: new Date(viewYear, viewMonth, 1)
  readonly property bool viewingCurrentMonth: viewYear === today.getFullYear() && viewMonth === today.getMonth()

  // Pinned to today, not to the month being browsed — stepping through the
  // calendar does not change how much of the year is gone.
  readonly property real yearDone: Model.yearProgress(today.getFullYear(), today.getMonth(), today.getDate())
  readonly property int yearDonePercent: Model.yearProgressPercent(today.getFullYear(), today.getMonth(), today.getDate())

  // Memento mori, for anyone who goes looking: double-tapping the year bar
  // asks for a birth year and a life expectancy, and a second bar tracks one
  // against the other. A birth year rather than an age, so it keeps counting
  // on its own. Without one the bar stays hidden.
  readonly property int birthYear: Model.parseBirthYear(setting("birthYear", 0), today.getFullYear())
  readonly property int age: Model.ageFromBirthYear(birthYear, today.getFullYear())
  readonly property int lifeExpectancy: Model.parseLifeExpectancy(setting("lifeExpectancy", 0))
  readonly property real lifeDone: Model.lifeProgress(age, lifeExpectancy)
  readonly property int lifeDonePercent: Model.lifeProgressPercent(age, lifeExpectancy)
  property bool editingLife: false

  // Unset falls through to the locale's own first day, so a fresh install
  // starts out matching the rest of the desktop rather than a hardcoded
  // convention. Clicking the grid's "W" heading writes the choice back to
  // shell.json.
  readonly property int weekStart: Model.normalizedWeekStart(setting("weekStartDay", null), Qt.locale().firstDayOfWeek)
  // The interface is English throughout, so day names are not taken from the
  // system locale. Where the week starts still is: that is a regional
  // convention rather than a translation, and it stays overridable above.
  readonly property var labelLocale: Qt.locale("en_US")
  readonly property string nextWeekStartLabel: labelLocale.dayName(Model.toggledWeekStart(weekStart), Locale.LongFormat)
  readonly property var weekdays: Model.weekdayOrder(weekStart)
  readonly property var weeks: Model.monthGrid(viewYear, viewMonth, weekStart, todayKey)


  // Guarded so the widget renders before the bar is injected (the bar-widget
  // contract instantiates it bare).
  readonly property color contentForeground: bar ? bar.foreground : Color.foreground
  readonly property string contentFontFamily: bar ? bar.fontFamily : Style.font.family

  readonly property int cellWidth: Style.space(52)
  readonly property int cellHeight: Style.space(34)
  readonly property int cellSpacing: Style.space(2)
  readonly property int weekColumnWidth: Style.space(32)
  readonly property int gutterWidth: Style.space(14)

  function open() {
    refresh()
    root.controller.show()
    // Set after showing, not before: showing hands the popout coordinator
    // over, which closes whichever panel was open, and that close clears the
    // shared flag. Deferring means the panel taking over always wins, while
    // a handoff to a panel that does not manage the flag still leaves it
    // cleared rather than stuck on.
    Qt.callLater(function() {
      if (root.opened) setCenterHoverRevealSuppressed(true)
    })
  }

  function close() {
    setCenterHoverRevealSuppressed(false)
    // Dismissing the panel mid-edit would otherwise leave the inputs up,
    // waiting behind a closed popup for the next time it opens.
    if (root.editingLife) root.cancelEditingLife()
    root.selectedEvent = null
    root.showCalendarSettings = false
    root.controller.hide()
  }

  function toggle() {
    if (root.opened) root.close()
    else root.open()
  }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.barIdentity, direction)
    return false
  }

  // Summoning by hotkey moves no pointer, so a hover the bar was still
  // holding must not keep the center indicators revealed behind the panel.
  function setCenterHoverRevealSuppressed(value) {
    if (root.bar && "centerHoverRevealSuppressed" in root.bar)
      root.bar.centerHoverRevealSuppressed = value
  }

  function refresh() {
    root.today = new Date()
    root.goToToday()
  }

  function goToToday() {
    root.viewYear = today.getFullYear()
    root.viewMonth = today.getMonth()
    root.selectedDay = today
  }

  function moveMonth(delta) {
    var next = Model.stepMonth(viewYear, viewMonth, delta)
    root.viewYear = next.year
    root.viewMonth = next.month
  }

  function moveYear(delta) {
    moveMonth(delta * 12)
  }

  // Applied locally first so the panel redraws on the click itself; the
  // shell.json write comes back through the bar as the same value. With no
  // writable entry (the widget is not in the layout) it stays a session-only
  // preference rather than doing nothing. The host widget builds its own
  // entry when the label format is cycled, so it has to be kept in step or
  // it would write this key straight back out from a stale copy.
  function persistSettings(values) {
    var entry = { id: root.moduleName }
    for (var existing in root.settings) if (existing !== "id") entry[existing] = root.settings[existing]
    for (var key in values) entry[key] = values[key]

    root.settings = entry
    if (root.hostWidget && "settings" in root.hostWidget) root.hostWidget.settings = entry
    if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function")
      root.bar.shell.updateEntryInline(root.moduleName, entry)
  }

  function setWeekStart(day) {
    var next = Model.normalizedWeekStart(day, root.weekStart)
    if (next === root.weekStart) return
    persistSettings({ weekStartDay: Model.weekStartSettingName(next) })
  }

  function startEditingLife() {
    root.editingLife = true
    Qt.callLater(function() {
      bornField.text = root.birthYear > 0 ? String(root.birthYear) : ""
      expectancyField.text = String(root.lifeExpectancy)
      bornField.selectAll()
      bornField.forceActiveFocus()
    })
  }

  function cancelEditingLife() {
    root.editingLife = false
    Qt.callLater(function() { if (keyCatcher) keyCatcher.forceActiveFocus() })
  }

  // Shared by both fields: Tab hops to the other one, Enter commits the pair,
  // Escape drops the lot.
  function handleLifeKey(event, other) {
    if (event.key === Qt.Key_Escape) {
      root.cancelEditingLife()
      event.accepted = true
    } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
      root.commitLife()
      event.accepted = true
    } else if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
      other.selectAll()
      other.forceActiveFocus()
      event.accepted = true
    }
  }

  // Double-tapping the life bar puts it away again. The expectancy stays in
  // the config so setting a birth year again brings your own number back
  // rather than the default.
  function clearLife() {
    if (root.birthYear <= 0) return
    persistSettings({ birthYear: 0 })
  }

  function commitLife() {
    var born = Model.parseBirthYear(bornField.text, today.getFullYear())
    var span = Model.parseLifeExpectancy(expectancyField.text)
    if (born !== root.birthYear || span !== root.lifeExpectancy)
      persistSettings({ birthYear: born, lifeExpectancy: span })
    cancelEditingLife()
  }

  function toggleWeekStart() {
    setWeekStart(Model.toggledWeekStart(root.weekStart))
  }

  // English short day names, matching the rest of the interface.
  function weekdayLabel(weekday) {
    return String(labelLocale.dayName(weekday, Locale.ShortFormat)).toUpperCase()
  }

  SystemClock {
    id: clock
    precision: SystemClock.Minutes
    onDateChanged: {
      if (Model.keyForDate(clock.date) === String(root.todayKey)) return
      var followToday = root.viewingCurrentMonth
      root.today = clock.date
      if (followToday) root.goToToday()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    centerOnBar: true
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(560))
    contentHeight: panel.fittedContentHeight(calendarColumn.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: root.editingLife
      onMoveRequested: function(dx, dy) {
        if (dx !== 0) root.moveMonth(dx)
        if (dy !== 0) root.moveYear(dy)
      }
      onActivateRequested: root.goToToday()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        if (t === "[") root.moveMonth(-1)
        else if (t === "]") root.moveMonth(1)
        else if (t === "{") root.moveYear(-1)
        else if (t === "}") root.moveYear(1)
        else if (t === "t" || t === "T") root.goToToday()
        else if (t === "w" || t === "W") root.toggleWeekStart()
      }

      Flickable {
        id: calendarScroll
        anchors.fill: parent
        contentWidth: calendarColumn.width
        contentHeight: calendarColumn.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height || contentWidth > width

        Column {
          id: calendarColumn
          // Never narrower than the grid. The popup width is capped to what
          // the screen allows, and a fixed seven-column grid would otherwise
          // lose its last days off the edge instead of scrolling.
          width: Math.max(calendarScroll.width, gridColumn.width)
          spacing: Style.space(8)

          // ---- Hero: today, centered. Once the view has stepped back
          //      it is also the way home — clicking the date you are
          //      looking for beats hunting for a reset button.
          Item {
            width: parent.width
            height: heroRow.height

            Row {
              id: heroRow
              anchors.horizontalCenter: parent.horizontalCenter
              spacing: Style.space(22)

              Text {
                // Baseline-aligned, not center-aligned: "July 26" carries a
                // descender, so centering the two boxes leaves the icon
                // sitting visibly low against the digits.
                anchors.baseline: heroDate.baseline
                text: "󰃭"
                color: heroMouse.containsMouse
                  ? Style.hoverStateColor(root.contentForeground, Color.accent)
                  : root.contentForeground
                font.family: root.contentFontFamily
                // Decorative, and deliberately outside the Style.font.*
                // scale. Sized so the glyph reads at the cap height of the
                // date beside it rather than towering over it.
                font.pixelSize: 48
              }

              Text {
                id: heroDate
                textFormat: Text.PlainText
                anchors.verticalCenter: parent.verticalCenter
                text: Qt.formatDate(root.today, "MMMM d")
                color: heroMouse.containsMouse
                  ? Style.hoverStateColor(root.contentForeground, Color.accent)
                  : root.contentForeground
                font.family: root.contentFontFamily
                font.pixelSize: 52
                font.bold: true
              }
            }

            MouseArea {
              id: heroMouse
              x: heroRow.x
              y: heroRow.y
              width: heroRow.width
              height: heroRow.height
              enabled: !root.viewingCurrentMonth
              hoverEnabled: enabled
              cursorShape: Qt.PointingHandCursor
              onClicked: root.goToToday()

              PanelToolTip {
                visible: heroMouse.containsMouse
                text: "Back to today"
                fontFamily: root.contentFontFamily
              }
            }
          }

          // ---- Year progress, doubling as the rule under the hero:
          //      a plain hairline said nothing, and whole days done
          //      over days in the year says the same thing louder.
          Item {
            width: parent.width
            height: yearBlock.y + yearBlock.height

            Item {
              id: yearBlock
              y: Style.space(6)
              anchors.horizontalCenter: parent.horizontalCenter
              width: gridColumn.width
              height: Math.max(yearLabel.implicitHeight, Style.space(10))

              TapHandler {
                enabled: !root.editingLife
                onDoubleTapped: root.startEditingLife()
              }

              Row {
                visible: root.editingLife
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(10)

                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  text: "BORN"
                  color: Qt.darker(root.contentForeground, 1.5)
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.bodySmall
                  font.letterSpacing: 1
                }

                TextField {
                  id: bornField
                  width: Style.space(70)
                  anchors.verticalCenter: parent.verticalCenter
                  placeholderText: "year"
                  foreground: root.contentForeground
                  font.family: root.contentFontFamily
                  inputMethodHints: Qt.ImhDigitsOnly

                  Keys.onPressed: function(event) { root.handleLifeKey(event, expectancyField) }
                }

                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  anchors.verticalCenterOffset: 0
                  leftPadding: Style.space(6)
                  text: "LIVE TO"
                  color: Qt.darker(root.contentForeground, 1.5)
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.bodySmall
                  font.letterSpacing: 1
                }

                TextField {
                  id: expectancyField
                  width: Style.space(60)
                  anchors.verticalCenter: parent.verticalCenter
                  placeholderText: "90"
                  foreground: root.contentForeground
                  font.family: root.contentFontFamily
                  inputMethodHints: Qt.ImhDigitsOnly

                  Keys.onPressed: function(event) { root.handleLifeKey(event, bornField) }
                }
              }

              Text {
                id: yearLabel
                textFormat: Text.PlainText
                visible: !root.editingLife
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: root.today.getFullYear()
                color: Qt.darker(root.contentForeground, 1.5)
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.bodySmall
                font.letterSpacing: 1
              }

              Text {
                id: yearPercent
                textFormat: Text.PlainText
                visible: !root.editingLife
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: root.yearDonePercent + "%"
                color: root.contentForeground
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.bodySmall
              }

              Rectangle {
                id: yearTrack
                visible: !root.editingLife
                anchors.left: yearLabel.right
                anchors.right: yearPercent.left
                anchors.leftMargin: Style.space(12)
                anchors.rightMargin: Style.space(12)
                anchors.verticalCenter: parent.verticalCenter
                height: Style.space(6)
                radius: Style.cornerRadius > 0 ? height / 2 : 0
                color: Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.12)

                Rectangle {
                  width: Math.round(parent.width * root.yearDone)
                  height: parent.height
                  radius: parent.radius
                  color: Style.selectedStateColor(root.contentForeground, Color.accent)

                  Behavior on width { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                }
              }
            }
          }

          // ---- Memento mori. Only here once someone has gone looking and
          //      given an age; the same rail as the year above it, measured
          //      against a nominal lifetime.
          Item {
            visible: root.birthYear > 0
            width: parent.width
            height: visible ? lifeBlock.height : 0

            Item {
              id: lifeBlock
              anchors.horizontalCenter: parent.horizontalCenter
              width: gridColumn.width
              height: Math.max(lifeLabel.implicitHeight, Style.space(10))

              Text {
                id: lifeLabel
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: "LIFE"
                color: Qt.darker(root.contentForeground, 1.5)
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.bodySmall
                font.letterSpacing: 1
              }

              Text {
                id: lifePercent
                textFormat: Text.PlainText
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: root.lifeDonePercent + "%"
                color: root.contentForeground
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.bodySmall
              }

              Rectangle {
                anchors.left: lifeLabel.right
                anchors.right: lifePercent.left
                anchors.leftMargin: Style.space(12)
                anchors.rightMargin: Style.space(12)
                anchors.verticalCenter: parent.verticalCenter
                height: Style.space(6)
                radius: Style.cornerRadius > 0 ? height / 2 : 0
                color: Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.12)

                Rectangle {
                  width: Math.round(parent.width * root.lifeDone)
                  height: parent.height
                  radius: parent.radius
                  color: Style.selectedStateColor(root.contentForeground, Color.accent)

                  Behavior on width { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                }
              }

              TapHandler {
                onDoubleTapped: root.clearLife()
              }

              MouseArea {
                id: lifeMouse
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.NoButton

                PanelToolTip {
                  visible: lifeMouse.containsMouse
                  text: "Memento Mori"
                  fontFamily: root.contentFontFamily
                }
              }
            }
          }

          // ---- Month grid: week numbers down a gutter on the left, then
          //      the seven day columns. Always six rows, so the popup is
          //      exactly as tall in February as it is in August.
          Item {
            width: parent.width
            height: gridColumn.y + gridColumn.height

            WheelHandler {
              onWheel: function(event) {
                // Horizontal wheels and touchpad side-scrolls report y === 0;
                // without this they would every one read as "next month".
                if (event.angleDelta.y === 0) return
                root.moveMonth(event.angleDelta.y > 0 ? -1 : 1)
              }
            }

            Column {
              id: gridColumn
              // The meter above is a solid rule; the grid needs room to
              // read as its own block rather than hanging off it.
              y: Style.space(18)
              anchors.horizontalCenter: parent.horizontalCenter
              spacing: Style.space(3)

              Row {
                id: headerRow
                spacing: root.cellSpacing

                // The week-number heading doubles as the week-start toggle.
                // It is the one control in the panel whose meaning is not
                // self-evident, so it carries a tooltip naming the day the
                // click will switch to.
                Rectangle {
                  width: root.weekColumnWidth
                  height: Style.space(16)
                  radius: Style.cornerRadius
                  color: weekStartMouse.containsMouse
                    ? Style.hoverFillFor(root.contentForeground, Color.accent)
                    : "transparent"

                  Text {
                    anchors.centerIn: parent
                    text: "W"
                    color: weekStartMouse.containsMouse
                      ? Style.hoverStateColor(root.contentForeground, Color.accent)
                      : Qt.darker(root.contentForeground, 1.9)
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.caption
                    font.letterSpacing: 1
                    font.bold: true
                  }

                  MouseArea {
                    id: weekStartMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.toggleWeekStart()
                  }

                  PanelToolTip {
                    visible: weekStartMouse.containsMouse
                    text: "Start weeks on " + root.nextWeekStartLabel
                    fontFamily: root.contentFontFamily
                  }
                }

                Item {
                  width: root.gutterWidth
                  height: Style.space(16)
                }

                Repeater {
                  model: root.weekdays

                  Text {
                    textFormat: Text.PlainText
                    required property var modelData
                    width: root.cellWidth
                    height: Style.space(16)
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    text: root.weekdayLabel(modelData)
                    color: Qt.darker(root.contentForeground, 1.5)
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.caption
                    font.letterSpacing: 1
                    font.bold: true
                  }
                }
              }

              Repeater {
                model: root.weeks

                Row {
                  required property var modelData
                  spacing: root.cellSpacing

                  Text {
                    textFormat: Text.PlainText
                    width: root.weekColumnWidth
                    height: root.cellHeight
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    text: modelData.week
                    color: Qt.darker(root.contentForeground, 1.9)
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.caption
                  }

                  Item {
                    width: root.gutterWidth
                    height: root.cellHeight
                  }

                  Repeater {
                    model: modelData.days

                    Rectangle {
                      required property var modelData
                      readonly property bool isSelectedDay: modelData.key === root.selectedDayKey

                      width: root.cellWidth
                      height: root.cellHeight
                      radius: Style.cornerRadius
                      // Today is outlined, not filled: a lit-up block shouts
                      // over a grid this quiet. The day the agenda is
                      // currently showing (which starts out as today) gets
                      // a soft fill on top of that outline, so the two
                      // states read clearly even when they're the same day.
                      color: isSelectedDay
                        ? Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.08)
                        : "transparent"
                      border.width: modelData.today ? Style.spacing.hairline : 0
                      border.color: Style.normalBorderFor(root.contentForeground, Color.accent)

                      Text {
                        textFormat: Text.PlainText
                        anchors.centerIn: parent
                        text: modelData.day
                        color: modelData.inMonth
                          ? (modelData.weekend ? Qt.darker(root.contentForeground, 1.45) : root.contentForeground)
                          : Qt.darker(root.contentForeground, 2.2)
                        font.family: root.contentFontFamily
                        font.pixelSize: Style.font.body
                        font.bold: modelData.today
                      }

                      MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.selectDay(modelData.year, modelData.month, modelData.day)
                      }
                    }
                  }
                }
              }
            }

            // Hairline down the week-number gutter, drawn only beside the
            // day rows so it does not cut through the header band.
            Rectangle {
              x: gridColumn.x + root.weekColumnWidth + root.cellSpacing + Math.round((root.gutterWidth - width) / 2)
              y: gridColumn.y + headerRow.height + gridColumn.spacing
              width: Style.spacing.hairline
              height: gridColumn.height - headerRow.height - gridColumn.spacing
              color: root.contentForeground
              opacity: 0.1
            }
          }

          // ---- Month stepping, spanning the grid it drives. The chevrons
          //      sit on the grid's outer bounds, the same edges the year
          //      rail above uses, so the row reads as the panel's other
          //      full-width rail instead of a cluster floating in space.
          //      The label is centered and fixed-width, so it holds still
          //      from "MAY" to "SEPTEMBER".
          Item {
            width: parent.width
            height: monthNav.height

            Item {
              id: monthNav
              anchors.horizontalCenter: parent.horizontalCenter
              width: gridColumn.width
              height: monthLabel.implicitHeight + Style.space(10)

              Text {
                id: monthLabel
                textFormat: Text.PlainText
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.verticalCenter: parent.verticalCenter
                // Fixed width so the chevrons hold still between a
                // "MAY 2026" and a "SEPTEMBER 2026".
                width: Style.space(130)
                horizontalAlignment: Text.AlignHCenter
                text: Qt.formatDate(root.viewDate, "MMMM yyyy").toUpperCase()
                color: Qt.darker(root.contentForeground, 1.4)
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.body
                font.letterSpacing: 1
              }

              PanelActionButton {
                // Pulled out by the button's own padding so the glyph, not
                // its hit box, lines up with the "2026" on the year rail.
                anchors.left: parent.left
                anchors.leftMargin: -Style.space(8)
                anchors.verticalCenter: parent.verticalCenter
                iconText: "󰅁"
                tooltipText: "Previous month"
                foreground: root.contentForeground
                fontFamily: root.contentFontFamily
                onClicked: root.moveMonth(-1)
              }

              PanelActionButton {
                anchors.right: parent.right
                anchors.rightMargin: -Style.space(8)
                anchors.verticalCenter: parent.verticalCenter
                iconText: "󰅂"
                tooltipText: "Next month"
                foreground: root.contentForeground
                fontFamily: root.contentFontFamily
                onClicked: root.moveMonth(1)
              }
            }
          }

          // ---- Agenda: today + the next few days, one section, same rail
          //      language as YEAR/LIFE above it. The header carries the
          //      force-refresh control; everything under it is a read-out.
          Item {
            width: parent.width
            height: agendaBlock.y + agendaBlock.height

            Item {
              id: agendaBlock
              y: Style.space(18)
              anchors.horizontalCenter: parent.horizontalCenter
              width: gridColumn.width
              height: agendaColumn.implicitHeight

              Column {
                id: agendaColumn
                width: parent.width
                spacing: Style.space(6)

                Item {
                  width: parent.width
                  height: Math.max(agendaLabel.implicitHeight, Style.space(16))

                  Text {
                    id: agendaLabel
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.selectedDayKey === Model.keyForDate(root.today)
                      ? "TODAY"
                      : String(Qt.formatDate(root.selectedDay, "ddd, MMM d")).toUpperCase()
                    color: Qt.darker(root.contentForeground, 1.5)
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.bodySmall
                    font.letterSpacing: 1
                  }

                  Row {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Style.space(4)

                    PanelActionButton {
                      anchors.verticalCenter: parent.verticalCenter
                      iconText: "󰒓"
                      tooltipText: "Choose which calendars to show"
                      foreground: root.contentForeground
                      fontFamily: root.contentFontFamily
                      onClicked: root.openCalendarSettings()
                    }

                    PanelActionButton {
                      anchors.verticalCenter: parent.verticalCenter
                      iconText: root.refreshingCalendar ? "󰑖" : "󰑐"
                      tooltipText: root.refreshingCalendar ? "Refreshing…" : "Refresh all calendars"
                      foreground: root.contentForeground
                      fontFamily: root.contentFontFamily
                      enabled: !root.refreshingCalendar
                      onClicked: root.forceRefresh()
                    }
                  }
                }

                // Visible while a save-triggered or manual sync is in
                // flight (~20s) — without this, closing the settings popup
                // right after Save looks identical to a stuck Save, since
                // the settings screen's own "Saving…" state is gone by then.
                Text {
                  textFormat: Text.PlainText
                  visible: root.refreshingCalendar
                  text: "Syncing…"
                  color: Qt.darker(root.contentForeground, 1.4)
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.caption
                }

                // Errors and staleness are surfaced here rather than an
                // empty list — a blank agenda and "nothing scheduled" must
                // never look the same as "the sync is broken".
                Text {
                  textFormat: Text.PlainText
                  visible: root.eventsCache.error === "missing"
                  width: parent.width
                  wrapMode: Text.WordWrap
                  text: "No Google account linked yet — see docs/link-google-account.md"
                  color: Qt.darker(root.contentForeground, 1.4)
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.bodySmall
                }

                Text {
                  textFormat: Text.PlainText
                  visible: root.eventsCache.error !== "missing" && !!root.eventsCache.lastError
                  width: parent.width
                  wrapMode: Text.WordWrap
                  text: root.eventsCache.lastError
                  color: Color.accent
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.bodySmall
                }

                Text {
                  textFormat: Text.PlainText
                  visible: root.eventsCache.error !== "missing" && !root.eventsCache.lastError && root.agendaStale
                  width: parent.width
                  wrapMode: Text.WordWrap
                  text: "Showing last known events — sync looks stale"
                  color: Qt.darker(root.contentForeground, 1.4)
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.caption
                }

                Text {
                  textFormat: Text.PlainText
                  visible: root.eventsCache.error !== "missing" && !root.eventsCache.lastError && root.agendaEvents.length === 0
                  width: parent.width
                  text: "Nothing on the calendar this day"
                  color: Qt.darker(root.contentForeground, 1.7)
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.bodySmall
                }

                // A birthday-heavy day (a big Contacts calendar can carry
                // half a dozen) used to burn one full row each — collapsed
                // into a single expandable line instead.
                readonly property var dayBirthdays: root.eventsCache.error === "missing" ? [] : root.agendaEvents.filter(function(e) { return Model.isBirthdayEvent(e) })
                readonly property var dayOtherEvents: root.eventsCache.error === "missing" ? [] : root.agendaEvents.filter(function(e) { return !Model.isBirthdayEvent(e) })
                property bool birthdaysExpanded: false

                Connections {
                  target: root
                  function onSelectedDayChanged() { agendaColumn.birthdaysExpanded = false }
                }

                Item {
                  width: parent.width
                  visible: agendaColumn.dayBirthdays.length > 0
                  height: visible ? birthdayHeaderRow.implicitHeight : 0

                  Row {
                    id: birthdayHeaderRow
                    anchors.left: parent.left
                    spacing: Style.space(8)

                    Text {
                      textFormat: Text.PlainText
                      anchors.verticalCenter: parent.verticalCenter
                      text: " " + agendaColumn.dayBirthdays.length + (agendaColumn.dayBirthdays.length === 1 ? " birthday" : " birthdays")
                        + (agendaColumn.birthdaysExpanded ? " 󰅃" : " 󰅀")
                      color: root.contentForeground
                      font.family: root.contentFontFamily
                      font.pixelSize: Style.font.body
                    }
                  }

                  MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: agendaColumn.birthdaysExpanded = !agendaColumn.birthdaysExpanded
                  }
                }

                Repeater {
                  model: agendaColumn.birthdaysExpanded ? agendaColumn.dayBirthdays : []

                  Text {
                    required property var modelData
                    textFormat: Text.PlainText
                    x: Style.space(16)
                    width: agendaColumn.width - Style.space(16)
                    elide: Text.ElideRight
                    text: modelData.title || "(untitled event)"
                    color: Qt.darker(root.contentForeground, 1.2)
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.bodySmall

                    MouseArea {
                      anchors.fill: parent
                      cursorShape: Qt.PointingHandCursor
                      onClicked: root.openEvent(parent.modelData)
                    }
                  }
                }

                Repeater {
                  model: agendaColumn.dayOtherEvents

                  Item {
                    required property var modelData
                    width: agendaColumn.width
                    height: Math.max(eventRow.implicitHeight, Style.space(20))

                    Row {
                      id: eventRow
                      anchors.left: parent.left
                      anchors.verticalCenter: parent.verticalCenter
                      spacing: Style.space(8)

                      Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: Style.space(8)
                        height: Style.space(8)
                        radius: width / 2
                        color: modelData.calendarColor || Color.accent
                      }

                      Text {
                        textFormat: Text.PlainText
                        anchors.verticalCenter: parent.verticalCenter
                        width: Style.space(60)
                        text: modelData.allDay ? "ALL DAY" : Qt.formatTime(new Date(modelData.start), "HH:mm")
                        color: Qt.darker(root.contentForeground, 1.5)
                        font.family: root.contentFontFamily
                        font.pixelSize: Style.font.caption
                      }

                      Text {
                        textFormat: Text.PlainText
                        anchors.verticalCenter: parent.verticalCenter
                        width: agendaColumn.width - Style.space(76) - (nextBadge.visible ? nextBadge.width + Style.space(6) : 0)
                        elide: Text.ElideRight
                        text: modelData.title || "(untitled event)"
                        color: root.contentForeground
                        font.family: root.contentFontFamily
                        font.pixelSize: Style.font.body
                      }

                      // Marks whichever row is the same event BarWidget.qml's
                      // bar badge is already counting down to — same
                      // Model.nextUpcomingEvent computation, so the two never
                      // disagree about which event is "next".
                      Text {
                        id: nextBadge
                        textFormat: Text.PlainText
                        anchors.verticalCenter: parent.verticalCenter
                        // Compared by id, not object identity — a `property
                        // var` holding parsed JSON can hand back a different
                        // wrapper for the "same" element on each binding
                        // re-evaluation, so `===` between two separate reads
                        // of eventsCache.events is not reliable.
                        visible: root.nextEvent && modelData.id === root.nextEvent.id && root.nextEventBadge !== ""
                        text: root.nextEventBadge
                        color: Color.accent
                        font.family: root.contentFontFamily
                        font.pixelSize: Style.font.caption
                        font.bold: true
                      }
                    }

                    MouseArea {
                      anchors.fill: parent
                      hoverEnabled: true
                      cursorShape: Qt.PointingHandCursor
                      onClicked: root.openEvent(parent.modelData)
                    }
                  }
                }
              }
            }
          }
        }
      }
    }

    Loader {
      id: eventDetailLoader
      anchors.fill: parent
      active: root.selectedEvent !== null
      visible: active
      source: Qt.resolvedUrl("EventDetail.qml")
      onLoaded: {
        item.event = root.selectedEvent
        item.foreground = root.contentForeground
        item.fontFamily = root.contentFontFamily
        item.closeRequested.connect(root.closeEvent)
        item.externalOpened.connect(root.close)
      }
    }

    Loader {
      id: calendarSettingsLoader
      anchors.fill: parent
      active: root.showCalendarSettings
      visible: active
      source: Qt.resolvedUrl("CalendarSettings.qml")
      onLoaded: {
        item.foreground = root.contentForeground
        item.fontFamily = root.contentFontFamily
        item.closeRequested.connect(root.closeCalendarSettings)
        item.saved.connect(function() {
          root.closeCalendarSettings()
          root.forceRefresh()
        })
      }
    }
  }
}

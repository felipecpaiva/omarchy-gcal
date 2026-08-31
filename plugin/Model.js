// Pure date and format math for the clock widget and its calendar panel.
// Everything here is locale- and Qt-free so it can be unit tested under node
// (test/shell.d/clock-test.sh); the QML owns month/weekday naming through
// Qt.locale().

var MS_PER_DAY = 86400000

// Weekday indices match both JS Date.getDay() and QML's Locale.Sunday…
// Locale.Saturday, so a locale's firstDayOfWeek can be passed straight in.
var WEEKDAY_NAMES = ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"]

// ---- Bar label formats. Right-clicking the clock walks these in order and
//      writes the result back to shell.json, so the label the bar shows and
//      the format the config stores are always the same thing.
//
// The locale-shaped time presets are each followed by their 12-hour twin, so
// the walk from a 24-hour label to the same label in AM/PM is a single right
// click rather than a lap of the ring. The ISO preset is deliberately left
// without one: ISO 8601 writes time on a 24-hour clock, so an AM/PM variant
// would contradict the only thing that format is for.
var CLOCK_FORMATS = [
  "dddd HH:mm",
  "dddd h:mm AP",
  "HH:mm",
  "h:mm AP",
  "ddd d MMM HH:mm",
  "ddd d MMM h:mm AP",
  "d MMMM 'W'ww yyyy",
  "yyyy-MM-dd HH:mm"
]

// Vertical bars have room for a few stacked lines and nothing else, so the
// ring stays short. AM/PM costs a fourth line, which is why only the plain
// time carries it here.
var VERTICAL_CLOCK_FORMATS = [
  "HH\n—\nmm",
  "h\n—\nmm\nAP",
  "dd\nMMM\n'W'ww\n''yy",
  "HH\nmm"
]

function clockFormats(vertical) {
  return vertical ? VERTICAL_CLOCK_FORMATS.slice() : CLOCK_FORMATS.slice()
}

// The presets in a fixed order, plus the configured alternate and current
// format when they are something else. The order must not depend on which
// entry is current: cycling writes the result back to shell.json, and a ring
// that reshuffled itself around the current value would bounce between two
// entries instead of walking.
function clockFormatRing(configured, configuredAlt, presets) {
  var ring = []
  var candidates = (presets || []).concat([configuredAlt, configured])
  for (var i = 0; i < candidates.length; i++) {
    var format = String(candidates[i] === undefined || candidates[i] === null ? "" : candidates[i])
    if (format === "" || ring.indexOf(format) !== -1) continue
    ring.push(format)
  }
  return ring.length > 0 ? ring : ["HH:mm"]
}

// Next entry after `current`. An unknown current format (a hand-written one
// that is not in the ring) starts the walk at the top.
function nextClockFormat(ring, current) {
  if (!ring || ring.length === 0) return ""
  var index = ring.indexOf(String(current === undefined || current === null ? "" : current))
  return ring[(index + 1) % ring.length]
}

// Two-digit ISO week, substituted into a format's 'ww' token before Qt
// formats it -- Qt has no ISO week specifier of its own.
function isoWeekLiteral(year, month, day) {
  return pad2(isoWeek(year, month, day))
}

function pad2(value) {
  var n = Number(value)
  return (n < 10 ? "0" : "") + n
}

// Stable "yyyy-MM-dd" identity for a day, so a grid cell can be compared
// against today without dragging Date objects through bindings.
function dateKey(year, month, day) {
  return year + "-" + pad2(Number(month) + 1) + "-" + pad2(day)
}

function keyForDate(date) {
  return dateKey(date.getFullYear(), date.getMonth(), date.getDate())
}

function coerceWeekStart(value) {
  if (value === undefined || value === null) return null
  if (typeof value === "number")
    return isFinite(value) ? ((Math.round(value) % 7) + 7) % 7 : null

  var text = String(value).replace(/^\s+|\s+$/g, "").toLowerCase()
  if (text === "") return null

  for (var i = 0; i < WEEKDAY_NAMES.length; i++)
    if (WEEKDAY_NAMES[i] === text || WEEKDAY_NAMES[i].substr(0, 3) === text) return i

  var parsed = parseInt(text, 10)
  return isFinite(parsed) ? ((parsed % 7) + 7) % 7 : null
}

// Configured week start, falling back to the locale's own first day when
// the setting is missing or nonsense.
function normalizedWeekStart(value, fallback) {
  var configured = coerceWeekStart(value)
  if (configured !== null) return configured
  var fallbackStart = coerceWeekStart(fallback)
  return fallbackStart === null ? 1 : fallbackStart
}

function weekStartSettingName(index) {
  return WEEKDAY_NAMES[normalizedWeekStart(index, 1)]
}

// The toggle flips between the two conventions people actually switch
// between. A calendar configured to any other start (Saturday, say) is
// shown as-is and lands on Monday the first time it is toggled.
function toggledWeekStart(index) {
  return normalizedWeekStart(index, 1) === 1 ? 0 : 1
}

function weekdayOrder(weekStart) {
  var start = normalizedWeekStart(weekStart, 1)
  var out = []
  for (var i = 0; i < 7; i++) out.push((start + i) % 7)
  return out
}

// ISO-8601 week number: the week owning the Thursday of that date's
// Monday-based week. Mirrors the clock widget's 'ww' format token.
function isoWeek(year, month, day) {
  var date = new Date(Date.UTC(year, month, day))
  var weekday = date.getUTCDay() || 7
  date.setUTCDate(date.getUTCDate() + 4 - weekday)
  var yearStart = new Date(Date.UTC(date.getUTCFullYear(), 0, 1))
  return Math.ceil(((date.getTime() - yearStart.getTime()) / MS_PER_DAY + 1) / 7)
}

function dayOfYear(year, month, day) {
  return Math.round((Date.UTC(year, month, day) - Date.UTC(year, 0, 1)) / MS_PER_DAY) + 1
}

function daysInYear(year) {
  return dayOfYear(year, 11, 31)
}

// Share of the year already behind you: whole days completed over days in
// the year, so January 1 reads 0% and December 31 reads 100%.
function yearProgress(year, month, day) {
  var total = daysInYear(year)
  if (total <= 0) return 0
  return Math.max(0, Math.min(1, (dayOfYear(year, month, day) - 1) / total))
}

function yearProgressPercent(year, month, day) {
  return Math.round(yearProgress(year, month, day) * 100)
}

// Memento mori. The default span is a round number rather than anything from
// an actuarial table: the point of the bar is the reminder, not the
// arithmetic, and whoever wants a different number can say so.
var DEFAULT_LIFE_EXPECTANCY = 90

// A birth year rather than an age, so the bar keeps counting on its own
// instead of going stale the moment it is entered. 0 means "not set", which
// is also what a blank, malformed, future, or implausibly distant year means.
function parseBirthYear(value, currentYear) {
  var now = Math.round(Number(currentYear))
  if (!isFinite(now)) return 0
  var text = String(value === undefined || value === null ? "" : value).replace(/^\s+|\s+$/g, "")
  if (!/^\d{4}$/.test(text)) return 0
  var year = parseInt(text, 10)
  if (!isFinite(year) || year > now || year < now - 120) return 0
  return year
}

// Whole years, the way people say their age: born in 1979 makes you 47 for
// all of 2026, whichever side of your birthday today falls.
function ageFromBirthYear(birthYear, currentYear) {
  var born = parseBirthYear(birthYear, currentYear)
  if (born <= 0) return 0
  return Math.round(Number(currentYear)) - born
}

// 0 means "not set", which is also what a blank, negative, fractional, or
// absurd entry means — the life bar simply stays hidden.
function parseAge(value) {
  var text = String(value === undefined || value === null ? "" : value).replace(/^\s+|\s+$/g, "")
  if (!/^\d+$/.test(text)) return 0
  var years = parseInt(text, 10)
  if (!isFinite(years) || years <= 0 || years > 120) return 0
  return years
}

// Unset or nonsense falls back to the default rather than to zero, so the
// bar always has something to measure against.
function parseLifeExpectancy(value) {
  var text = String(value === undefined || value === null ? "" : value).replace(/^\s+|\s+$/g, "")
  if (!/^\d+$/.test(text)) return DEFAULT_LIFE_EXPECTANCY
  var years = parseInt(text, 10)
  if (!isFinite(years) || years <= 0 || years > 150) return DEFAULT_LIFE_EXPECTANCY
  return years
}

function lifeProgress(age, expectancy) {
  var years = parseAge(age)
  var span = parseLifeExpectancy(expectancy)
  if (years <= 0 || span <= 0) return 0
  return Math.max(0, Math.min(1, years / span))
}

function lifeProgressPercent(age, expectancy) {
  return Math.round(lifeProgress(age, expectancy) * 100)
}

// Always six rows of seven days. A fixed grid keeps the popup exactly the
// same height in every month, so stepping through the year never makes the
// panel jump under the pointer.
function monthGrid(year, month, weekStart, todayKey) {
  var start = normalizedWeekStart(weekStart, 1)
  var leading = (new Date(year, month, 1).getDay() - start + 7) % 7
  var cursor = new Date(year, month, 1 - leading)
  var today = String(todayKey || "")
  var weeks = []

  for (var w = 0; w < 6; w++) {
    var days = []
    var thursday = null
    for (var d = 0; d < 7; d++) {
      var cellYear = cursor.getFullYear()
      var cellMonth = cursor.getMonth()
      var cellDay = cursor.getDate()
      var weekday = cursor.getDay()
      var key = dateKey(cellYear, cellMonth, cellDay)
      if (weekday === 4) thursday = { year: cellYear, month: cellMonth, day: cellDay }
      days.push({
        key: key,
        year: cellYear,
        month: cellMonth,
        day: cellDay,
        weekday: weekday,
        inMonth: cellMonth === month && cellYear === year,
        weekend: weekday === 0 || weekday === 6,
        today: key === today
      })
      cursor.setDate(cursor.getDate() + 1)
    }
    // Number every row by the ISO week owning its Thursday. That is the
    // definition itself for Monday-start weeks, and the only answer that
    // stays stable for the other starts, where a row straddles two ISO
    // weeks but shares all of Monday through Thursday with one of them.
    var anchor = thursday || days[0]
    weeks.push({
      week: isoWeek(anchor.year, anchor.month, anchor.day),
      days: days
    })
  }
  return weeks
}

function stepMonth(year, month, delta) {
  var target = new Date(year, Number(month) + Number(delta), 1)
  return { year: target.getFullYear(), month: target.getMonth() }
}

// ---- Google Calendar agenda. Pure parsing/grouping over the JSON cache
//      written by sync/eds_read.py — see that file's module docstring for
//      the exact contract. Nothing here talks to EDS directly; the QML side
//      only ever reads this cache file and shells out to eds_read.py for a
//      refresh, so this module stays as easy to test as the date math above.

// A parse failure (missing file, malformed JSON) must never look like "no
// events" — the caller can tell the two apart via `error`.
function parseEventsCache(jsonText) {
  if (!jsonText) return { events: [], lastSyncUtc: null, lastError: "No Google account linked", error: "missing" }
  var data
  try {
    data = JSON.parse(jsonText)
  } catch (e) {
    return { events: [], lastSyncUtc: null, lastError: "Cache file is unreadable", error: "parse" }
  }
  var events = Array.isArray(data.events) ? data.events : []
  return {
    events: events,
    lastSyncUtc: data.last_sync_utc || null,
    lastError: data.last_error || null,
    error: null
  }
}

// Cache older than 3x the sync interval reads as stale rather than being
// hidden — a quiet agenda is not the same thing as an agenda nobody trusts.
function isCacheStale(lastSyncUtc, now, syncIntervalMinutes) {
  if (!lastSyncUtc) return true
  var last = Date.parse(lastSyncUtc)
  if (!isFinite(last)) return true
  var thresholdMs = 3 * (syncIntervalMinutes || 5) * 60000
  return (now.getTime() - last) > thresholdMs
}

// Events starting on or after `start`'s day, through `days` days later,
// sorted by start time. All-day events sort before timed ones on their day.
function eventsInRange(events, start, days) {
  var rangeStart = new Date(start.getFullYear(), start.getMonth(), start.getDate())
  var rangeEnd = new Date(rangeStart.getTime() + days * MS_PER_DAY)
  var out = []
  for (var i = 0; i < events.length; i++) {
    var e = events[i]
    var eventStart = Date.parse(e.start)
    if (!isFinite(eventStart)) continue
    if (eventStart >= rangeStart.getTime() && eventStart < rangeEnd.getTime()) out.push(e)
  }
  out.sort(function(a, b) {
    if (!!a.allDay !== !!b.allDay) return a.allDay ? -1 : 1
    return Date.parse(a.start) - Date.parse(b.start)
  })
  return out
}

// Groups an already-sorted event list into { dayKey, dayLabel, events }
// buckets in day order, for the agenda's per-day headers.
function groupEventsByDay(events) {
  var byKey = {}
  var order = []
  for (var i = 0; i < events.length; i++) {
    var e = events[i]
    var d = new Date(e.start)
    var key = keyForDate(d)
    if (!byKey[key]) {
      byKey[key] = []
      order.push(key)
    }
    byKey[key].push(e)
  }
  return order.map(function(key) { return { dayKey: key, events: byKey[key] } })
}

// The soonest event that has not ended yet, for the bar badge. Returns null
// when nothing qualifies, which the badge treats as "stay quiet".
function nextUpcomingEvent(events, now) {
  var soonest = null
  var soonestEnd = Infinity
  for (var i = 0; i < events.length; i++) {
    var e = events[i]
    var end = Date.parse(e.end)
    if (!isFinite(end) || end <= now.getTime()) continue
    if (end < soonestEnd) {
      soonest = e
      soonestEnd = end
    }
  }
  return soonest
}

function minutesUntil(event, now) {
  if (!event) return null
  var start = Date.parse(event.start)
  if (!isFinite(start)) return null
  return Math.round((start - now.getTime()) / 60000)
}

// "in 45m" while it's coming up, "now" once it has started but not ended,
// "" (badge hidden) once nothing qualifies at all.
function badgeLabel(event, now) {
  if (!event) return ""
  var minutes = minutesUntil(event, now)
  if (minutes === null) return ""
  if (minutes <= 0) return "now"
  if (minutes < 60) return "in " + minutes + "m"
  return "in " + Math.round(minutes / 60) + "h"
}

// meet.google.com / zoom.us / teams.microsoft.com links buried in a
// description when the source event carried no dedicated conference URL —
// eds_read.py does the same extraction server-side; this is the QML-side
// fallback so an older cache file still gets a Join button.
var CONFERENCE_URL_RE = /https?:\/\/[^\s<>"]*(meet\.google\.com|zoom\.us|teams\.microsoft\.com)[^\s<>"]*/i

function extractJoinUrl(event) {
  if (event.joinUrl) return event.joinUrl
  var text = String(event.description || "")
  var match = text.match(CONFERENCE_URL_RE)
  return match ? match[0] : ""
}

if (typeof module !== "undefined") {
  module.exports = {
    dateKey: dateKey,
    keyForDate: keyForDate,
    normalizedWeekStart: normalizedWeekStart,
    weekStartSettingName: weekStartSettingName,
    toggledWeekStart: toggledWeekStart,
    weekdayOrder: weekdayOrder,
    isoWeek: isoWeek,
    dayOfYear: dayOfYear,
    daysInYear: daysInYear,
    yearProgress: yearProgress,
    yearProgressPercent: yearProgressPercent,
    parseAge: parseAge,
    parseBirthYear: parseBirthYear,
    ageFromBirthYear: ageFromBirthYear,
    parseLifeExpectancy: parseLifeExpectancy,
    lifeProgress: lifeProgress,
    lifeProgressPercent: lifeProgressPercent,
    monthGrid: monthGrid,
    stepMonth: stepMonth,
    clockFormats: clockFormats,
    clockFormatRing: clockFormatRing,
    nextClockFormat: nextClockFormat,
    isoWeekLiteral: isoWeekLiteral,
    parseEventsCache: parseEventsCache,
    isCacheStale: isCacheStale,
    eventsInRange: eventsInRange,
    groupEventsByDay: groupEventsByDay,
    nextUpcomingEvent: nextUpcomingEvent,
    minutesUntil: minutesUntil,
    badgeLabel: badgeLabel,
    extractJoinUrl: extractJoinUrl
  }
}

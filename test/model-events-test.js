// Self-check for the calendar-agenda additions to Model.js. Run with:
//   node plugin/test/model-events-test.js
// The stock clock's own date-math functions already have their own test
// under omarchy's shell test suite; this only covers what was added here.
const assert = require("assert")
const Model = require("../Model.js")

// parseEventsCache: missing file vs bad JSON vs good JSON must be
// distinguishable, never all collapsing to "no events".
assert.strictEqual(Model.parseEventsCache(null).error, "missing")
assert.strictEqual(Model.parseEventsCache("not json").error, "parse")
const good = Model.parseEventsCache(JSON.stringify({ events: [{ id: "1", start: "2026-08-31T10:00:00Z", end: "2026-08-31T10:30:00Z" }], last_sync_utc: "2026-08-31T09:00:00Z", last_error: null }))
assert.strictEqual(good.error, null)
assert.strictEqual(good.events.length, 1)

// isCacheStale: fresh sync is not stale, an old one (well past 3x a 5-min
// interval) is.
const now = new Date("2026-08-31T10:00:00Z")
assert.strictEqual(Model.isCacheStale("2026-08-31T09:58:00Z", now, 5), false)
assert.strictEqual(Model.isCacheStale("2026-08-31T09:00:00Z", now, 5), true)
assert.strictEqual(Model.isCacheStale(null, now, 5), true)

// eventsInRange + groupEventsByDay: events land on the right day and stay
// sorted; an all-day event sorts before a timed one on the same day.
const events = [
  { id: "a", title: "Standup", start: "2026-08-31T09:00:00Z", end: "2026-08-31T09:15:00Z", allDay: false },
  { id: "b", title: "Company holiday", start: "2026-08-31T00:00:00Z", end: "2026-09-01T00:00:00Z", allDay: true },
  { id: "c", title: "Next week", start: "2026-09-10T09:00:00Z", end: "2026-09-10T09:15:00Z", allDay: false }
]
const inRange = Model.eventsInRange(events, now, 5)
assert.strictEqual(inRange.length, 2)
assert.strictEqual(inRange[0].id, "b") // all-day first
assert.strictEqual(inRange[1].id, "a")
const grouped = Model.groupEventsByDay(inRange)
assert.strictEqual(grouped.length, 1)
assert.strictEqual(grouped[0].events.length, 2)

// nextUpcomingEvent + badgeLabel: an event that already ended never wins,
// and the label steps from minutes to hours the way the plan describes.
const past = { id: "p", start: "2026-08-31T08:00:00Z", end: "2026-08-31T08:30:00Z" }
const soon = { id: "s", start: "2026-08-31T10:45:00Z", end: "2026-08-31T11:00:00Z" }
const later = { id: "l", start: "2026-08-31T14:00:00Z", end: "2026-08-31T15:00:00Z" }
const next = Model.nextUpcomingEvent([past, soon, later], now)
assert.strictEqual(next.id, "s")
assert.strictEqual(Model.badgeLabel(next, now), "in 45m")
assert.strictEqual(Model.badgeLabel(null, now), "")
assert.strictEqual(Model.badgeLabel({ start: "2026-08-31T14:00:00Z", end: "2026-08-31T15:00:00Z" }, now), "in 4h")

// extractJoinUrl: dedicated field wins; a Meet link in the description is
// the fallback for cache entries that predate the dedicated field.
assert.strictEqual(Model.extractJoinUrl({ joinUrl: "https://example.com/x", description: "" }), "https://example.com/x")
assert.strictEqual(Model.extractJoinUrl({ description: "Join: https://meet.google.com/abc-defg-hij" }), "https://meet.google.com/abc-defg-hij")
assert.strictEqual(Model.extractJoinUrl({ description: "no link here" }), "")

// isBirthdayEvent: the only signal is an all-day event titled "X's
// birthday" — Google's birthday calendar carries no dedicated type field.
assert.strictEqual(Model.isBirthdayEvent({ allDay: true, title: "Jane Doe's birthday" }), true)
assert.strictEqual(Model.isBirthdayEvent({ allDay: true, title: "Company holiday" }), false)
assert.strictEqual(Model.isBirthdayEvent({ allDay: false, title: "Jane Doe's birthday" }), false)
assert.strictEqual(Model.isBirthdayEvent({ allDay: true, title: "" }), false)

console.log("model-events-test: all assertions passed")

// Self-check on how Panel.qml talks to the host bar. Run with:
//   node test/panel-host-writes-test.js
//
// Why this exists: the bar hands third-party plugins a read-only view of
// centerHoverRevealSuppressed plus a setCenterHoverRevealSuppressed setter.
// Panel.qml used to assign the property directly, which throws
// "Cannot assign to read-only property". close() calls that helper on its
// first line, so the throw aborted close() before controller.hide() ever ran
// and the calendar popup could never be dismissed — with nothing but a WARN
// line in journalctl to show for it.
//
// The host decides what is writable and it has changed once already, so a
// direct assignment must never be the first thing tried, and must never
// appear outside the one helper that probes for the setter first.
const assert = require("assert")
const fs = require("fs")
const path = require("path")

const source = fs.readFileSync(path.join(__dirname, "..", "Panel.qml"), "utf8")

const helper = /function setCenterHoverRevealSuppressed\(value\)\s*\{([\s\S]*?)\n  \}/.exec(source)
assert.ok(helper, "Panel.qml must define setCenterHoverRevealSuppressed(value)")

const setterProbe = helper[1].indexOf('typeof root.bar.setCenterHoverRevealSuppressed === "function"')
const directWrite = helper[1].search(/\broot\.bar\.[A-Za-z_$][\w$]*\s*=(?!=)/)

assert.ok(
  setterProbe !== -1,
  "setCenterHoverRevealSuppressed must probe for the host's setter"
)
assert.ok(
  directWrite === -1 || setterProbe < directWrite,
  "the host setter must be tried BEFORE any direct property assignment — " +
    "assigning first throws on a read-only plugin facade and aborts the caller"
)

// Nowhere else may write a host-bar property: only the helper above is
// allowed to, and only as its fallback branch.
const outside = source.slice(0, helper.index) + source.slice(helper.index + helper[0].length)
const stray = /\broot\.bar\.[A-Za-z_$][\w$]*\s*=(?!=)/.exec(outside)
assert.ok(
  stray === null,
  `Panel.qml assigns a host bar property outside the guarded helper: "${stray && stray[0]}". ` +
    "Call the host's setter instead."
)

// close() must still reach controller.hide(); a helper that throws above it
// is what stuck the panel open, so keep the call in the function.
const closeBody = /function close\(\)\s*\{([\s\S]*?)\n  \}/.exec(source)
assert.ok(closeBody, "Panel.qml must define close()")
assert.ok(
  /root\.controller\.hide\(\)/.test(closeBody[1]),
  "close() must call root.controller.hide()"
)

console.log("panel-host-writes-test: all assertions passed")

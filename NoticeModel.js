// Reading Omarchy's notification history and shaping it the way the shell
// shapes a notification deck: one stack per groupKey, newest stack first.
//
// Nothing here writes to Omarchy's state. The history file is read-only and
// every row is treated as untrusted text: bounded, decoded, stripped to plain
// text, and rendered by QML with Text.PlainText.
.pragma library

var MAX_ENTRIES = 100
var MAX_APP = 256
var MAX_SUMMARY = 2048
var MAX_BODY = 32768
var MAX_SOURCE = 253
var MAX_GLYPH = 16
var MAX_QUERY = 128
var MAX_FILE = 8 * 1024 * 1024
var KEY = /^[A-Za-z0-9_-]{1,120}$/
var APP_ICON = /^[a-zA-Z0-9_.-]{1,256}$/

// Omarchy's Markup.BROWSERS, kept in step with the shell so a browser stack
// splits by site here exactly as it does on the desktop.
var BROWSERS = /^(google chrome|chromium|brave|brave browser|brave origin|microsoft edge|vivaldi|opera|helium|firefox|zen|librewolf)$/i

var ENTITIES = { amp: "&", lt: "<", gt: ">", quot: "\"", apos: "'", nbsp: " " }

function str(value, max) {
  return typeof value === "string" ? value.slice(0, max) : ""
}

function number(value) {
  var n = Number(value)
  return isFinite(n) ? n : 0
}

function decodeOnce(text) {
  return String(text || "")
    .replace(/&#(\d{1,7});/g, function(_, n) {
      var code = parseInt(n, 10)
      return (code > 0 && code < 0x110000) ? String.fromCodePoint(code) : _
    })
    .replace(/&#x([0-9a-f]{1,6});/gi, function(_, n) {
      var code = parseInt(n, 16)
      return (code > 0 && code < 0x110000) ? String.fromCodePoint(code) : _
    })
    .replace(/&([a-z]+);/gi, function(whole, name) {
      var hit = ENTITIES[String(name).toLowerCase()]
      return hit === undefined ? whole : hit
    })
}

// Sender bodies carry a small markup subset. Decode entities (three passes,
// because relays stack escapes), then remove tags. Text is only ever drawn as
// plain text, so this cannot re-introduce markup.
function plainText(value) {
  var text = decodeOnce(decodeOnce(decodeOnce(str(value, MAX_BODY))))
  text = text.replace(/<br\s*\/?>/gi, " ")
    .replace(/<[^>]*>/g, " ")
    .replace(/\s+/g, " ")
    .trim()
  return text
}

function safeGlyph(value) {
  var text = str(value, MAX_GLYPH)
  return /[\x00-\x1f\x7f-\x9f]/.test(text) ? "" : text
}

function isOmarchyGlyph(value) {
  var code = String(value || "").codePointAt(0)
  return isFinite(code) && code >= 0xe900 && code <= 0xe9ff
}

function isBrowser(app) {
  return BROWSERS.test(String(app || "").trim())
}

function slug(text) {
  return String(text || "").toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-|-$/g, "")
}

// Markup.canonicalHostname: a real DNS host, no control characters, no
// numeric final label (WHATWG would read it as IPv4).
function canonicalHostname(raw) {
  if (typeof raw !== "string" || raw.length > MAX_SOURCE) return ""
  var host = raw.toLowerCase().replace(/\.$/, "")
  if (!/^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?(?:\.[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?)+$/.test(host)) return ""
  if (/^(?:0x[0-9a-f]*|[0-9]+)$/i.test(host.split(".").pop())) return ""
  return host
}

// Markup.regroup, reproduced so older rows written by a previous shell build
// pick up today's grouping instead of whatever groupKey the file happens to
// carry.
function regroup(row) {
  var app = String(row && row.app || "")
  var source = String(row && row.source || "")
  if (app === "omarchy-action" || app === "notify-send") return "toast:" + String(row && row.key || "")
  if (isBrowser(app) && source && source !== app && canonicalHostname(source)) return "web:" + canonicalHostname(source)
  return "app:" + slug(app)
}

function normaliseRow(entry) {
  if (!entry || typeof entry !== "object" || Array.isArray(entry)) return null
  var key = String(entry.key || "")
  if (!KEY.test(key)) return null

  var closed = number(entry.closed_ts)
  if (closed <= 0) return null

  var app = str(entry.app, MAX_APP)
  var source = str(entry.source, MAX_SOURCE)
  var summary = plainText(entry.summary)
  var body = plainText(entry.body)
  // Summary first, body second, the way a card reads. When there is no
  // summary the body becomes the line that identifies the notification.
  var title = summary || body
  var preview = summary ? body : ""

  var row = {
    key: key,
    app: app,
    appIcon: APP_ICON.test(str(entry.appIcon, 256)) ? str(entry.appIcon, 256) : "",
    source: source,
    glyph: safeGlyph(entry.glyph),
    title: title,
    preview: preview,
    urgency: Math.max(0, Math.min(2, Math.round(number(entry.urgency)))),
    ts: number(entry.ts) || closed,
    closed_ts: closed,
    closed_reason: /^[a-z]{1,32}$/.test(String(entry.closed_reason || "")) ? String(entry.closed_reason) : ""
  }
  row.groupKey = regroup(row)
  row.search = (app + " " + source + " " + title + " " + preview + " " + row.closed_reason).toLowerCase()
  return row
}

// history.json is newest first, up to 100 rows and 24 hours. A row that does
// not carry a usable key or close time is not something the shell wrote, so
// it is skipped rather than guessed at.
function parse(text) {
  var raw = String(text || "")
  if (!raw.trim() || raw.length > MAX_FILE) return []

  var value
  try { value = JSON.parse(raw) } catch (e) { return [] }
  if (!Array.isArray(value)) return []

  var out = []
  var seen = Object.create(null)
  for (var i = 0; i < value.length && out.length < MAX_ENTRIES; i++) {
    var row = normaliseRow(value[i])
    if (!row || seen[row.key]) continue
    seen[row.key] = true
    out.push(row)
  }
  out.sort(function(a, b) { return b.closed_ts - a.closed_ts })
  return out
}

function unreadRows(rows, lastSeenTs) {
  var cutoff = number(lastSeenTs)
  var out = []
  for (var i = 0; i < (rows ? rows.length : 0); i++)
    if (rows[i].closed_ts > cutoff) out.push(rows[i])
  return out
}

function unreadCount(rows, lastSeenTs) {
  return unreadRows(rows, lastSeenTs).length
}

function latestTs(rows) {
  var best = 0
  for (var i = 0; i < (rows ? rows.length : 0); i++)
    if (rows[i].closed_ts > best) best = rows[i].closed_ts
  return best
}

// Every word must appear somewhere in the row's plain text. That makes
// "kde photo" find the photo notification from KDE Connect and keeps search
// stable while the user is still typing.
function filterRows(rows, query) {
  var needle = str(query, MAX_QUERY).toLowerCase().replace(/\s+/g, " ").trim()
  if (!needle) return rows || []

  var tokens = needle.split(" ")
  var out = []
  for (var i = 0; i < (rows ? rows.length : 0); i++) {
    var haystack = String(rows[i].search || "")
    var matched = true
    for (var t = 0; t < tokens.length; t++) {
      if (haystack.indexOf(tokens[t]) === -1) { matched = false; break }
    }
    if (matched) out.push(rows[i])
  }
  return out
}

function groupKind(key) {
  var value = String(key || "")
  if (value.indexOf("web:") === 0) return "web"
  if (value.indexOf("toast:") === 0) return "toast"
  return "app"
}

// rows: newest-first rows from parse().
// Returns stacks in newest-activity order. Each stack carries the rows it
// contains, so opening it needs no second lookup.
function buildGroups(rows, lastSeenTs, options) {
  var onlyUnread = !!(options && options.onlyUnread)
  var cutoff = number(lastSeenTs)
  var byKey = Object.create(null)
  var order = []

  for (var i = 0; i < (rows ? rows.length : 0); i++) {
    var row = rows[i]
    if (onlyUnread && row.closed_ts <= cutoff) continue
    var key = String(row.groupKey || "")
    var group = byKey[key]
    if (!group) {
      group = { key: key, rows: [] }
      byKey[key] = group
      order.push(group)
    }
    group.rows.push(row)
  }

  var out = []
  for (var g = 0; g < order.length; g++) {
    var item = order[g]
    item.rows.sort(function(a, b) { return b.closed_ts - a.closed_ts })
    var latest = item.rows[0]
    var kind = groupKind(item.key)
    var unread = 0
    var silenced = 0
    var critical = false
    for (var r = 0; r < item.rows.length; r++) {
      var row2 = item.rows[r]
      if (row2.closed_ts > cutoff) unread++
      if (row2.closed_reason === "silenced") silenced++
      if (row2.urgency === 2) critical = true
    }

    out.push({
      key: item.key,
      kind: kind,
      app: latest.app,
      appIcon: latest.appIcon,
      source: latest.source,
      label: kind === "web" ? (latest.source || latest.app) : (latest.app || latest.source),
      summary: latest.title,
      body: latest.preview,
      glyph: latest.glyph,
      urgency: latest.urgency,
      count: item.rows.length,
      unreadCount: unread,
      silencedCount: silenced,
      critical: critical,
      latestTs: latest.ts,
      latestClosedTs: latest.closed_ts,
      rows: item.rows
    })
  }

  out.sort(function(a, b) { return b.latestClosedTs - a.latestClosedTs })
  return out
}

if (typeof module !== "undefined") {
  module.exports = {
    parse: parse,
    plainText: plainText,
    regroup: regroup,
    buildGroups: buildGroups,
    filterRows: filterRows,
    unreadRows: unreadRows,
    unreadCount: unreadCount,
    latestTs: latestTs,
    isOmarchyGlyph: isOmarchyGlyph
  }
}

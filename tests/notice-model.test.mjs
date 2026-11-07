import test from "node:test"
import assert from "node:assert"
import { readFileSync } from "node:fs"
import vm from "node:vm"

// NoticeModel.js is a QML library: `.pragma library` is a QML directive, not
// JavaScript. Strip the directive and run the rest in a sandbox so the same
// file the shell loads is the file under test.
const source = readFileSync(new URL("../NoticeModel.js", import.meta.url), "utf8")
  .replace(/^\.pragma.*$/m, "")

const sandbox = { module: { exports: {} }, exports: {} }
sandbox.exports = sandbox.module.exports
vm.runInNewContext(source, sandbox, { filename: "NoticeModel.js" })
const Model = sandbox.module.exports

const fixture = JSON.parse(
  readFileSync(new URL("./fixtures/history.json", import.meta.url), "utf8"))

const rows = Model.parse(JSON.stringify(fixture))
const groupList = Model.buildGroups(rows, 0)
const byKey = Object.fromEntries(groupList.map(function(group) { return [group.key, group] }))

test("parse reads the history newest first and skips unusable rows", function() {
  assert.equal(rows.length, 8)
  assert.equal(rows[0].key, "fixture-0008")
  assert.equal(rows[rows.length - 1].key, "fixture-0001")
  assert.ok(rows.every(function(row) { return row.closed_ts > 0 }))
})

test("parse refuses duplicate keys, non-arrays, and oversized input", function() {
  const duplicate = JSON.stringify([
    { key: "a", app: "Signal", closed_ts: 20 },
    { key: "a", app: "Signal", closed_ts: 10 }
  ])
  assert.equal(Model.parse(duplicate).length, 1)
  assert.deepEqual(Model.parse("{}"), [])
  assert.deepEqual(Model.parse("not json"), [])
  assert.deepEqual(Model.parse("x".repeat(9 * 1024 * 1024)), [])
})

test("plainText decodes stacked entities and strips markup", function() {
  assert.equal(Model.plainText("Tom &amp; Jerry"), "Tom & Jerry")
  assert.equal(Model.plainText("<b>bold</b> <i>x</i>"), "bold x")
  assert.equal(Model.plainText("&amp;lt;b&amp;gt;hi&amp;lt;/b&amp;gt;"), "hi")
  assert.equal(Model.plainText("baris satu<br/>baris dua"), "baris satu baris dua")
})

test("regroup follows Omarchy: app, browser site, standalone toast", function() {
  assert.equal(Model.regroup({ app: "Signal", source: "Signal", key: "k" }), "app:signal")
  assert.equal(Model.regroup({ app: "Telegram Desktop", source: "Telegram Desktop" }), "app:telegram-desktop")
  assert.equal(Model.regroup({ app: "Firefox", source: "github.com", key: "k" }), "web:github.com")
  assert.equal(Model.regroup({ app: "Firefox", source: "Firefox", key: "k" }), "app:firefox")
  assert.equal(Model.regroup({ app: "omarchy-action", key: "abc" }), "toast:abc")
  assert.equal(Model.regroup({ app: "notify-send", key: "def" }), "toast:def")
})

test("buildGroups splits browsers by site and keeps every row", function() {
  assert.equal(groupList.length, 6)
  assert.equal(byKey["web:github.com"].count, 2)
  assert.equal(byKey["web:news.ycombinator.com"].count, 1)
  assert.equal(byKey["app:signal"].count, 2)
  assert.equal(byKey["toast:fixture-0008"].kind, "toast")
  assert.equal(byKey["web:github.com"].kind, "web")
  assert.equal(byKey["app:signal"].kind, "app")
})

test("browser URLs never become their own stack", function() {
  const urlRows = Model.parse(JSON.stringify([
    { key: "u1", app: "Firefox", source: "github.com", summary: "one", closed_ts: 3 },
    { key: "u2", app: "Firefox", source: "github.com", summary: "two", closed_ts: 2 },
    { key: "u3", app: "Firefox", source: "example.org", summary: "three", closed_ts: 1 }
  ]))
  const keys = Model.buildGroups(urlRows, 0).map(function(group) { return group.key })
  assert.deepEqual(keys, ["web:github.com", "web:example.org"])
})

test("groups order by newest activity and carry the latest summary", function() {
  assert.equal(groupList[0].key, "toast:fixture-0008")
  assert.equal(groupList[0].summary, "Backup selesai")
  assert.equal(byKey["app:signal"].summary, "Ada")
  const times = groupList.map(function(group) { return group.latestClosedTs })
  assert.deepEqual(times, times.slice().sort(function(a, b) { return b - a }))
})

test("unread counts use the last acknowledged close time", function() {
  assert.equal(Model.unreadCount(rows, 0), 8)
  assert.equal(Model.unreadCount(rows, 1793916120), 4)
  assert.equal(Model.unreadRows(rows, 1793916120).length, 4)

  const unreadGroups = Model.buildGroups(rows, 1793916120, { onlyUnread: true })
  assert.equal(unreadGroups.length, 3)
  const github = unreadGroups.filter(function(group) { return group.key === "web:github.com" })[0]
  assert.equal(github.unreadCount, 2)
  assert.equal(Model.latestTs(rows), 1793955660.9)
})

test("critical and silenced markers survive grouping", function() {
  assert.equal(byKey["toast:fixture-0008"].critical, true)
  assert.equal(byKey["app:signal"].critical, false)
  assert.equal(byKey["app:telegram-desktop"].silencedCount, 1)
  assert.equal(byKey["app:telegram-desktop"].unreadCount, 1)
})

test("search requires every word and ignores case", function() {
  assert.equal(Model.filterRows(rows, "firefox merged").length, 1)
  assert.equal(Model.filterRows(rows, "firefox merged")[0].key, "fixture-0006")
  assert.equal(Model.filterRows(rows, "SIGNAL ada").length, 1)
  assert.equal(Model.filterRows(rows, "   ").length, rows.length)
  assert.equal(Model.filterRows(rows, "tidak-ada-yang-cocok").length, 0)
})

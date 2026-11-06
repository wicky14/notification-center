import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "NoticeModel.js" as Model

// Notification Center's bar presence: a bell, an unread dot, and the host for
// the history panel. Omarchy's notification service remains the only daemon;
// this widget reads its history file and never writes to it.
BarWidget {
  id: root
  moduleName: "wicky14.notification-center"

  readonly property string historyPath: String(setting(
    "historyPath",
    Quickshell.env("HOME") + "/.local/state/omarchy/notifications/history.json"))
  readonly property string quietPath: String(setting(
    "quietPath",
    Quickshell.env("HOME") + "/.local/state/omarchy/notifications/quiet.json"))

  property var rows: []
  property bool historyLoaded: false
  property bool dnd: false
  property bool dndBusy: false

  readonly property var groups: Model.buildGroups(root.rows, noticeState.lastSeenTs)
  readonly property int unreadCount: Model.unreadCount(root.rows, noticeState.lastSeenTs)
  readonly property int totalCount: root.rows.length
  readonly property real lastSeenTs: noticeState.lastSeenTs

  // Unread state is carried by the bell's accent color; the count lives in
  // the tooltip and inside the panel, never beside the glyph.
  readonly property string tooltipText: {
    if (root.dnd) return strings.t("bar.dnd", "Notifications · Do not disturb")
    if (root.unreadCount > 0)
      return strings.t("bar.unread", "Notifications · %1 new").arg(I18n.formatNumber(root.unreadCount))
    return strings.t("bar.idle", "Notifications")
  }

  function applyHistory(text) {
    root.rows = Model.parse(text)
    root.historyLoaded = true
    root.syncSeen()
  }

  function applyQuiet(text) {
    var parsed = null
    try { parsed = JSON.parse(String(text || "")) } catch (e) { parsed = null }
    if (root.dndBusy) return
    root.dnd = !!(parsed && typeof parsed === "object" && parsed.dnd === true)
  }

  // A fresh install acknowledges the history that is already there. It does
  // not turn yesterday's messages into a hundred unread notifications.
  function syncSeen() {
    if (!root.historyLoaded || !noticeState.loaded) return
    if (!noticeState.initialized) noticeState.initialize(Model.latestTs(root.rows))
  }

  function markSeen(ts) {
    noticeState.setLastSeen(ts)
  }

  function markAllRead() {
    if (root.rows.length === 0) return
    noticeState.setLastSeen(root.rows[0].closed_ts)
  }

  function toggleDnd() {
    if (root.dndBusy) return
    var next = !root.dnd
    root.dnd = next
    root.dndBusy = true
    dndProcess.command = ["omarchy-shell", "notifications", "setDnd", next ? "true" : "false"]
    dndProcess.running = true
  }

  // Clicking a stack focuses the app the way Omarchy does on a card click.
  // Stored execArgv is deliberately never run by this read-only viewer.
  function focusApp(app) {
    var value = String(app || "").trim()
    if (!value || value === "omarchy-action" || value === "notify-send") return
    Util.execArgv(["omarchy-hyprland-focus-app", value])
  }

  function reloadData() {
    historyFile.reload()
    quietFile.reload()
  }

  // ---- Panel lifecycle -----------------------------------------------------
  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false
  readonly property bool popoutSwitchClosing:
    panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false

  function open() {
    if (panelLoader.item) panelLoader.item.open()
  }

  function close() {
    if (panelLoader.item) panelLoader.item.close()
  }

  function togglePanel() {
    if (panelLoader.item) panelLoader.item.toggle()
  }

  function closeForPopoutSwitch() {
    if (panelLoader.item) panelLoader.item.closeForPopoutSwitch()
  }

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()

  Translations {
    id: strings
    directory: Qt.resolvedUrl("i18n")
  }

  NoticeState {
    id: noticeState
    onLoadedChanged: root.syncSeen()
  }

  FileView {
    id: historyFile
    path: root.historyPath
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.applyHistory(text())
    onLoadFailed: root.applyHistory("")
  }

  FileView {
    id: quietFile
    path: root.quietPath
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.applyQuiet(text())
    onLoadFailed: root.applyQuiet("")
  }

  // The first read can race shell startup. One delayed reload self-corrects,
  // and is a no-op when the initial read already landed.
  Timer {
    interval: 1200
    running: true
    onTriggered: root.reloadData()
  }

  Process {
    id: dndProcess
    onExited: function(code) {
      root.dndBusy = false
      quietReloadTimer.restart()
    }
  }

  Timer {
    id: quietReloadTimer
    interval: 350
    onTriggered: quietFile.reload()
  }

  ShellIpc {
    target: "wicky14.notification-center"

    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.togglePanel() }
    function refresh(): void { root.reloadData() }
    function markAllRead(): void { root.markAllRead() }
  }

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.dnd ? "\uf1f6" : "\uf0f3"
    active: root.unreadCount > 0
    activeColor: Color.accent
    dimmed: root.dnd
    tooltipText: root.tooltipText

    onPressed: function(buttonCode) {
      if (buttonCode === Qt.RightButton) root.toggleDnd()
      else root.togglePanel()
    }
  }
}

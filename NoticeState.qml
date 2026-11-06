import QtQuick
import Quickshell
import Quickshell.Io

// The plugin's only piece of local state: the close time of the newest
// notification the user has acknowledged. It lives beside Omarchy's own state
// so uninstalling is easy, but it never writes to Omarchy's files.
QtObject {
  id: root

  // Omarchy reads its own state from $HOME/.local/state/omarchy regardless of
  // XDG_STATE_HOME, so the plugin's state sits beside it.
  readonly property string directoryPath:
    Quickshell.env("HOME") + "/.local/state/omarchy/wicky14.notification-center"
  readonly property string filePath: root.directoryPath + "/state.json"

  property bool ready: false
  property bool loaded: false
  property bool initialized: false
  property real lastSeenTs: 0
  property bool savePending: false

  function apply(text) {
    var parsed = null
    try { parsed = JSON.parse(String(text || "")) } catch (e) { parsed = null }

    var ts = parsed && typeof parsed === "object" ? Number(parsed.lastSeenTs) : NaN
    root.lastSeenTs = isFinite(ts) && ts > 0 ? ts : 0
    root.initialized = !!(parsed && parsed.initialized === true)
    root.loaded = true
    if (root.savePending) Qt.callLater(root.save)
  }

  // Writes only when the directory exists. The prepare process makes it, so a
  // first-run mark-read waits briefly instead of silently disappearing.
  function save() {
    if (!root.ready) {
      root.savePending = true
      return
    }
    root.savePending = false
    root.file.setText(JSON.stringify({
      lastSeenTs: root.lastSeenTs,
      initialized: root.initialized
    }) + "\n")
  }

  function setLastSeen(ts) {
    var value = Number(ts)
    if (isFinite(value) && value > root.lastSeenTs) root.lastSeenTs = value
    root.initialized = true
    root.save()
  }

  // First install: the history that is already there is old news, not a badge
  // with a hundred unread notifications.
  function initialize(ts) {
    var value = Number(ts)
    root.lastSeenTs = isFinite(value) && value > 0 ? value : 0
    root.initialized = true
    root.save()
  }

  property FileView file: FileView {
    path: root.ready ? root.filePath : ""
    watchChanges: true
    printErrors: false
    atomicWrites: true
    onFileChanged: reload()
    onLoaded: root.apply(text())
    onLoadFailed: root.apply("")
  }

  property Process prepare: Process {
    command: [
      "bash", "-c",
      "umask 077; mkdir -p -- \"$1\" && chmod 700 -- \"$1\"",
      "notification-center-state", root.directoryPath
    ]
    onExited: function(code) {
      if (code !== 0) return
      root.ready = true
      if (root.savePending) Qt.callLater(root.save)
    }
  }

  Component.onCompleted: root.prepare.running = true
}

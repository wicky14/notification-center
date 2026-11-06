import QtQuick
import Quickshell
import qs.Commons
import qs.Ui
import qs.Commons as Commons
import "NoticeModel.js" as Model

Panel {
  id: root
  moduleName: "wicky14.notification-center"
  manageIpc: false

  // The panel reads right-to-left languages (Arabic, Hebrew, Urdu) the same
  // way Omarchy's own toast deck does.
  LayoutMirroring.enabled: I18n.rightToLeft
  LayoutMirroring.childrenInherit: true

  property var anchorItem: null
  property var hostWidget: null

  // Panel-local view state. The history itself stays in BarWidget so the bar
  // badge and this list always agree.
  property string searchText: ""
  property bool searchActive: false
  property string filterMode: "all"
  property int cursorIndex: 0
  property bool cursorActive: false
  property var expandedKeys: ({})

  readonly property var sourceRows: root.hostWidget ? root.hostWidget.rows : []
  readonly property real lastSeenTs: root.hostWidget ? root.hostWidget.lastSeenTs : 0
  readonly property bool dnd: root.hostWidget ? root.hostWidget.dnd === true : false
  readonly property int unreadTotal: root.hostWidget ? root.hostWidget.unreadCount : 0
  readonly property int totalCount: root.hostWidget ? root.hostWidget.totalCount : 0

  readonly property color dimColor: Qt.darker(root.barForeground, 1.4)
  readonly property color accentColor: Commons.Color.accent
  readonly property color urgentColor: Commons.Color.urgent

  readonly property var filteredRows: {
    var rows = Model.filterRows(root.sourceRows, root.searchText)
    if (root.filterMode === "unread") rows = Model.unreadRows(rows, root.lastSeenTs)
    return rows
  }

  // Rebuilt from the same groupKey Omarchy uses. A browser splits by site; a
  // one-off Omarchy action stays its own stack.
  readonly property var groups: Model.buildGroups(root.filteredRows, root.lastSeenTs)

  readonly property var filterOptions: [
    { value: "all", label: strings.t("filter.all", "All") },
    { value: "unread", label: strings.t("filter.unread", "Unread") }
  ]

  readonly property string heroMeta: {
    if (root.dnd) return strings.t("panel.dndMeta", "Do not disturb · new notifications stay silent")
    if (root.totalCount === 0) return strings.t("panel.emptyMeta", "Reads Omarchy's notification history")
    return strings.t("panel.keptMeta", "Kept for 24 hours · 100 most recent")
  }

  readonly property string heroDetail: root.unreadTotal > 0
    ? strings.t("panel.new", "%1 new").arg(I18n.formatNumber(root.unreadTotal))
    : ""

  readonly property string emptyTitle: {
    if (root.searchText.trim() !== "") return strings.t("empty.noMatchTitle", "No notifications match")
    if (root.filterMode === "unread") return strings.t("empty.noUnreadTitle", "Nothing unread")
    return strings.t("empty.title", "No notifications yet")
  }

  readonly property string emptyBody: {
    if (root.searchText.trim() !== "") return strings.t("empty.noMatchBody", "Try a different app, title, or message.")
    if (root.filterMode === "unread") return strings.t("empty.noUnreadBody", "Everything in the last 24 hours has been read.")
    if (root.dnd) return strings.t("empty.dndBody", "Do not disturb is on. New notifications are collected here silently.")
    return strings.t("empty.body", "Notifications you receive will appear here. Omarchy keeps the last 24 hours.")
  }

  Translations {
    id: strings
    directory: Qt.resolvedUrl("i18n")
  }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.hostWidget || root, direction)
    return false
  }

  // ---- labels -------------------------------------------------------------
  function appLabel(group) {
    if (!group) return ""
    if (group.kind === "web") return group.label || group.source || group.app
    if (group.app === "omarchy-action") return strings.t("app.omarchy", "Omarchy")
    if (group.app === "notify-send") return strings.t("app.notifySend", "notify-send")
    return group.app || group.label || strings.t("notice.unknownApp", "Notification")
  }

  function captionText(group) {
    if (!group) return ""
    var text = root.appLabel(group)
    if (group.count > 1) text += "  ×" + I18n.formatNumber(group.count)
    if (group.silencedCount > 0) text += "  ·  " + strings.t("notice.silenced", "silenced")
    return text
  }

  function timeLabel(timestamp) {
    var value = Number(timestamp)
    if (!isFinite(value) || value <= 0) return ""
    var date = new Date(value * 1000)
    var now = new Date()
    var yesterday = new Date(now.getFullYear(), now.getMonth(), now.getDate() - 1)
    var locale = Qt.locale(I18n.formatLocale)

    if (date.toDateString() === now.toDateString())
      return date.toLocaleString(locale, "HH:mm")
    if (date.toDateString() === yesterday.toDateString())
      return strings.t("time.yesterday", "Yesterday")
    if (date.getFullYear() === now.getFullYear())
      return date.toLocaleString(locale, "d MMM")
    return date.toLocaleString(locale, "d MMM yyyy")
  }

  // ---- cursor and expansion ----------------------------------------------
  function isExpanded(key) {
    return root.expandedKeys[String(key)] === true
  }

  function toggleExpanded(key) {
    var next = {}
    for (var k in root.expandedKeys) next[k] = root.expandedKeys[k]
    var value = String(key)
    if (next[value]) delete next[value]
    else next[value] = true
    root.expandedKeys = next
    Qt.callLater(root.revealCursor)
  }

  function revealCursor() {
    if (!root.cursorActive || root.groups.length === 0) return
    if (root.cursorIndex >= 0 && root.cursorIndex < groupList.count)
      groupList.positionViewAtIndex(root.cursorIndex, ListView.Contain)
  }

  function moveCursor(dy) {
    if (root.groups.length === 0) return
    if (!root.cursorActive) {
      root.cursorActive = true
      root.revealCursor()
      return
    }
    var next = root.cursorIndex + (dy < 0 ? -1 : 1)
    root.cursorIndex = Math.max(0, Math.min(root.groups.length - 1, next))
    root.revealCursor()
  }

  function jumpTo(index) {
    if (root.groups.length === 0) return
    root.cursorActive = true
    root.cursorIndex = Math.max(0, Math.min(root.groups.length - 1, index))
    root.revealCursor()
  }

  function selectedGroup() {
    if (!root.cursorActive || root.groups.length === 0) return null
    return root.groups[Math.max(0, Math.min(root.cursorIndex, root.groups.length - 1))]
  }

  function expandSelected() {
    var group = root.selectedGroup()
    if (group && group.count > 1 && !root.isExpanded(group.key)) root.toggleExpanded(group.key)
  }

  function collapseSelected() {
    var group = root.selectedGroup()
    if (group && root.isExpanded(group.key)) root.toggleExpanded(group.key)
  }

  function activateGroup(group) {
    if (!group) return
    if (group.count > 1) root.toggleExpanded(group.key)
    else root.openRow(group.rows[0])
  }

  function activateCursor() {
    if (!root.cursorActive) {
      root.cursorActive = true
      root.revealCursor()
      return
    }
    root.activateGroup(root.selectedGroup())
  }

  function openCursorApp() {
    var group = root.selectedGroup()
    if (group) root.openRow(group.rows[0])
  }

  function openRow(row) {
    if (!row) return
    if (root.hostWidget) {
      root.hostWidget.markSeen(row.closed_ts)
      root.hostWidget.focusApp(row.app)
    }
    root.close()
  }

  // ---- search -------------------------------------------------------------
  function beginSearch() {
    root.searchActive = true
    Qt.callLater(function() {
      searchInput.forceActiveFocus()
      searchInput.cursorPosition = searchInput.length
    })
  }

  function endSearch() {
    root.searchActive = false
    Qt.callLater(function() {
      keyCatcher.forceActiveFocus()
    })
  }

  onOpenedChanged: {
    if (!opened) return
    root.searchActive = false
    root.searchText = ""
    searchInput.text = ""
    root.filterMode = "all"
    root.cursorIndex = 0
    root.cursorActive = false
    root.expandedKeys = ({})
    Qt.callLater(function() {
      keyCatcher.forceActiveFocus()
      groupList.positionViewAtBeginning()
    })
  }

  onSearchTextChanged: {
    root.cursorIndex = 0
    root.cursorActive = false
    Qt.callLater(function() {
      groupList.positionViewAtBeginning()
    })
  }

  onFilterModeChanged: {
    root.cursorIndex = 0
    root.cursorActive = false
    Qt.callLater(function() {
      groupList.positionViewAtBeginning()
    })
  }

  onGroupsChanged: {
    if (root.groups.length === 0) {
      root.cursorIndex = 0
      return
    }
    if (root.cursorIndex >= root.groups.length)
      root.cursorIndex = root.groups.length - 1
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.hostWidget || root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(420))
    contentHeight: panel.fittedContentHeight(panelContent.implicitHeight, Style.space(620))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      implicitHeight: panelContent.implicitHeight
      blocked: root.searchActive

      onMoveRequested: function(dx, dy) {
        if (dy !== 0) root.moveCursor(dy)
        else if (dx > 0) root.expandSelected()
        else if (dx < 0) root.collapseSelected()
      }
      onActivateRequested: root.activateCursor()
      onCloseRequested: root.close()
      onDeleteRequested: root.collapseSelected()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t, modifiers) {
        if ((modifiers & Qt.ControlModifier) && (t === "f" || t === "F")) {
          root.beginSearch()
          return
        }
        if (t === "/") { root.beginSearch(); return }
        if (t === "d" || t === "D") {
          if (root.hostWidget) root.hostWidget.toggleDnd()
          return
        }
        if (t === "o" || t === "O") { root.openCursorApp(); return }
        if (t === "g") { root.jumpTo(0); return }
        if (t === "G") { root.jumpTo(root.groups.length - 1); return }
      }

      Column {
        id: panelContent
        width: parent.width
        spacing: Style.space(10)

        PanelHero {
          iconComponent: Component {
            Text {
              textFormat: Text.PlainText
              text: root.dnd ? "\uf1f6" : "\uf0f3"
              color: root.barForeground
              font.family: Style.font.family
              font.pixelSize: Style.font.display
            }
          }
          title: strings.t("panel.title", "Notification Center")
          meta: root.heroMeta
          detail: root.heroDetail
          foreground: root.barForeground
          fontFamily: Style.font.family

          trailingControl: Component {
            Column {
              spacing: Style.space(2)

              Text {
                id: dndLabel
                width: dndSwitch.implicitWidth
                horizontalAlignment: Text.AlignHCenter
                textFormat: Text.PlainText
                text: strings.t("panel.dndShort", "DND")
                color: root.dimColor
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
                font.bold: true
                font.letterSpacing: 1.0
              }

              ToggleSwitch {
                id: dndSwitch
                checked: root.dnd
                foreground: root.barForeground
                accent: Commons.Color.accent
                onToggled: if (root.hostWidget) root.hostWidget.toggleDnd()
              }
            }
          }
        }

        // ---- Search -------------------------------------------------------
        BorderSurface {
          width: parent.width
          implicitHeight: Style.spacing.controlHeight + Style.space(4)
          height: implicitHeight
          radius: Style.cornerRadius
          color: Style.normalFillFor(root.barForeground, Commons.Color.accent)
          borderSpec: Border.controlSpec(searchInput.activeFocus ? "focus" : "normal",
                                         root.barForeground, Commons.Color.accent)

          Item {
            anchors.fill: parent
            anchors.leftMargin: Style.space(10)
            anchors.rightMargin: Style.space(10)

            Text {
              id: searchIcon
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              textFormat: Text.PlainText
              text: "\uf002"
              color: root.dimColor
              font.family: Style.font.family
              font.pixelSize: Style.font.body
            }

            FilterInput {
              id: searchInput
              anchors.left: searchIcon.right
              anchors.leftMargin: Style.space(8)
              anchors.right: searchHint.left
              anchors.rightMargin: Style.space(8)
              anchors.verticalCenter: parent.verticalCenter
              focus: false
              selectByMouse: true
              keyHandler: keyCatcher
              color: root.barForeground
              font.family: Style.font.family
              font.pixelSize: Style.font.body
              onTextChanged: if (text !== root.searchText) root.searchText = text
              onActiveFocusChanged: root.searchActive = activeFocus
              onAccepted: root.endSearch()

              Keys.onEscapePressed: {
                if (text !== "") text = ""
                else root.endSearch()
              }
            }

            Text {
              anchors.left: searchInput.left
              anchors.right: searchInput.right
              anchors.verticalCenter: searchInput.verticalCenter
              visible: searchInput.text === "" && !searchInput.preeditText
              textFormat: Text.PlainText
              text: strings.t("panel.search", "Search notifications…")
              color: root.barForeground
              opacity: 0.55
              font.family: Style.font.family
              font.pixelSize: Style.font.body
              elide: Text.ElideRight
            }

            Text {
              id: searchHint
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              textFormat: Text.PlainText
              text: root.searchActive ? strings.t("keys.esc", "Esc") : "/"
              color: root.dimColor
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
            }
          }
        }

        // ---- Filters ------------------------------------------------------
        Item {
          width: parent.width
          implicitHeight: Math.max(filterGroup.implicitHeight, markRead.implicitHeight)
          height: implicitHeight

          ButtonGroup {
            id: filterGroup
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            options: root.filterOptions
            value: root.filterMode
            focusable: false
            fontFamily: Style.font.family
            fontSize: Style.font.bodySmall
            foreground: root.barForeground
            accent: Commons.Color.accent
            onChanged: function(value) { root.filterMode = value }
          }

          Button {
            id: markRead
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            visible: root.unreadTotal > 0
            text: strings.t("panel.markAllRead", "Mark all read")
            fontFamily: Style.font.family
            fontSize: Style.font.bodySmall
            foreground: root.barForeground
            accent: Commons.Color.accent
            onClicked: if (root.hostWidget) root.hostWidget.markAllRead()
          }
        }

        PanelSeparator {
          foreground: root.barForeground
          strength: 0.12
        }

        // ---- History ------------------------------------------------------
        Item {
          id: listArea
          width: parent.width
          implicitHeight: root.groups.length === 0
            ? Style.space(190)
            : Math.min(Style.space(340), Math.max(Style.space(80), groupList.contentHeight))
          height: implicitHeight
          clip: true

          ListView {
            id: groupList
            anchors.fill: parent
            visible: root.groups.length > 0
            model: root.groups
            spacing: Style.space(2)
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            cacheBuffer: Style.space(320)
            delegate: groupDelegate
          }

          Column {
            anchors.centerIn: parent
            width: parent.width - Style.space(40)
            spacing: Style.space(8)
            visible: root.groups.length === 0

            Text {
              width: parent.width
              horizontalAlignment: Text.AlignHCenter
              textFormat: Text.PlainText
              text: root.dnd ? "\uf1f6" : "\uf0f3"
              color: root.barForeground
              opacity: 0.32
              font.family: Style.font.family
              font.pixelSize: Style.font.displayLarge
            }

            Text {
              width: parent.width
              horizontalAlignment: Text.AlignHCenter
              textFormat: Text.PlainText
              text: root.emptyTitle
              color: root.barForeground
              font.family: Style.font.family
              font.pixelSize: Style.font.body
              font.weight: Font.DemiBold
              wrapMode: Text.WordWrap
            }

            Text {
              width: parent.width
              horizontalAlignment: Text.AlignHCenter
              textFormat: Text.PlainText
              text: root.emptyBody
              color: root.dimColor
              font.family: Style.font.family
              font.pixelSize: Style.font.bodySmall
              wrapMode: Text.WordWrap
            }
          }
        }

        PanelSeparator {
          visible: root.groups.length > 0
          foreground: root.barForeground
          strength: 0.12
        }

        Text {
          width: parent.width
          visible: root.groups.length > 0
          textFormat: Text.PlainText
          text: strings.t("panel.footer", "Enter open · → expand · / search · D DND · Esc close")
          color: root.dimColor
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
      }
    }
  }

  // ---- One stack -----------------------------------------------------------
  Component {
    id: groupDelegate

    Item {
      id: groupItem
      required property var modelData
      required property int index

      readonly property bool expanded: root.expandedKeys[String(groupItem.modelData.key)] === true
      width: groupList.width
      implicitHeight: headerRow.implicitHeight + (groupItem.expanded ? childColumn.implicitHeight : 0)
      height: implicitHeight

      CursorSurface {
        id: headerRow
        width: parent.width
        implicitHeight: headerBody.implicitHeight + Style.space(16)
        height: implicitHeight
        hasCursor: root.cursorActive && root.cursorIndex === groupItem.index
        foreground: root.barForeground
        accent: Commons.Color.accent

        Rectangle {
          visible: groupItem.modelData.unreadCount > 0
          width: Math.max(2, Style.space(2))
          height: Math.max(0, parent.height - Style.space(18))
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          color: groupItem.modelData.critical ? root.urgentColor : root.accentColor
        }

        Item {
          id: headerBody
          anchors.left: parent.left
          anchors.leftMargin: Style.space(12)
          anchors.right: parent.right
          anchors.rightMargin: Style.space(10)
          anchors.top: parent.top
          anchors.topMargin: Style.space(8)
          implicitHeight: Math.max(iconSlot.height, textColumn.implicitHeight, metaColumn.implicitHeight)

          NoticeIcon {
            id: iconSlot
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            glyph: groupItem.modelData.glyph
            iconName: groupItem.modelData.appIcon
            label: root.appLabel(groupItem.modelData)
            foreground: root.barForeground
            accent: Commons.Color.accent
          }

          Column {
            id: textColumn
            anchors.left: iconSlot.right
            anchors.leftMargin: Style.space(10)
            anchors.right: metaColumn.left
            anchors.rightMargin: Style.space(8)
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(2)

            Text {
              width: parent.width
              textFormat: Text.PlainText
              text: groupItem.modelData.summary !== ""
                ? groupItem.modelData.summary
                : strings.t("notice.untitled", "Notification")
              color: root.barForeground
              font.family: Style.font.family
              font.pixelSize: Style.font.body
              font.weight: Font.DemiBold
              elide: Text.ElideRight
              maximumLineCount: 1
            }

            Text {
              width: parent.width
              visible: text !== ""
              textFormat: Text.PlainText
              text: groupItem.modelData.body
              color: root.dimColor
              font.family: Style.font.family
              font.pixelSize: Style.font.bodySmall
              elide: Text.ElideRight
              maximumLineCount: 1
            }

            Text {
              width: parent.width
              textFormat: Text.PlainText
              text: root.captionText(groupItem.modelData)
              color: root.dimColor
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
              elide: Text.ElideRight
              maximumLineCount: 1
            }
          }

          Column {
            id: metaColumn
            anchors.right: parent.right
            anchors.top: parent.top
            spacing: Style.space(2)
            width: Math.max(Style.space(38), timeText.implicitWidth, badgeRow.implicitWidth)

            Text {
              id: timeText
              width: parent.width
              horizontalAlignment: Text.AlignRight
              textFormat: Text.PlainText
              text: root.timeLabel(groupItem.modelData.latestTs || groupItem.modelData.latestClosedTs)
              color: root.dimColor
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
              elide: Text.ElideRight
            }

            Item {
              width: parent.width
              height: badgeRow.implicitHeight

              Row {
                id: badgeRow
                anchors.right: parent.right
                spacing: Style.space(4)

                Text {
                  visible: groupItem.modelData.critical
                  textFormat: Text.PlainText
                  text: "\uf071"
                  color: root.urgentColor
                  font.family: Style.font.family
                  font.pixelSize: Style.font.caption
                }

                Text {
                  visible: groupItem.modelData.count > 1
                  textFormat: Text.PlainText
                  text: "\uf105"
                  color: root.dimColor
                  font.family: Style.font.family
                  font.pixelSize: Style.font.caption
                  rotation: groupItem.expanded ? 90 : 0
                  transformOrigin: Item.Center
                  Behavior on rotation {
                    NumberAnimation {
                      duration: Style.duration(140)
                      easing.type: Easing.Bezier
                      easing.bezierCurve: Style.easeOut
                    }
                  }
                }
              }
            }
          }
        }

        MouseArea {
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onEntered: {
            root.cursorActive = true
            root.cursorIndex = groupItem.index
          }
          onClicked: root.activateGroup(groupItem.modelData)
        }
      }

      Column {
        id: childColumn
        width: parent.width
        visible: groupItem.expanded
        spacing: 0

        Repeater {
          model: groupItem.expanded ? groupItem.modelData.rows.slice(1) : []

          delegate: Item {
            id: childDelegate
            required property var modelData
            width: childColumn.width
            implicitHeight: childSurface.height

            CursorSurface {
              id: childSurface
              width: parent.width
              implicitHeight: childBody.implicitHeight + Style.space(12)
              height: implicitHeight
              property bool hot: false
              hasCursor: childSurface.hot
              foreground: root.barForeground
              accent: Commons.Color.accent

              Item {
                id: childBody
                anchors.left: parent.left
                anchors.leftMargin: Style.space(42)
                anchors.right: parent.right
                anchors.rightMargin: Style.space(10)
                anchors.verticalCenter: parent.verticalCenter
                implicitHeight: Math.max(childText.implicitHeight, childTime.implicitHeight)

                Rectangle {
                  visible: childDelegate.modelData.closed_ts > root.lastSeenTs
                  width: Math.max(3, Style.space(4))
                  height: width
                  radius: width / 2
                  color: root.accentColor
                  anchors.left: parent.left
                  anchors.verticalCenter: parent.verticalCenter
                }

                Column {
                  id: childText
                  anchors.left: parent.left
                  anchors.leftMargin: Style.space(12)
                  anchors.right: childTime.left
                  anchors.rightMargin: Style.space(8)
                  anchors.verticalCenter: parent.verticalCenter
                  spacing: Style.space(1)

                  Text {
                    width: parent.width
                    textFormat: Text.PlainText
                    text: childDelegate.modelData.title !== ""
                      ? childDelegate.modelData.title
                      : strings.t("notice.untitled", "Notification")
                    color: root.barForeground
                    font.family: Style.font.family
                    font.pixelSize: Style.font.bodySmall
                    elide: Text.ElideRight
                    maximumLineCount: 1
                  }

                  Text {
                    width: parent.width
                    visible: text !== ""
                    textFormat: Text.PlainText
                    text: childDelegate.modelData.preview
                    color: root.dimColor
                    font.family: Style.font.family
                    font.pixelSize: Style.font.caption
                    elide: Text.ElideRight
                    maximumLineCount: 1
                  }
                }

                Text {
                  id: childTime
                  anchors.right: parent.right
                  anchors.top: parent.top
                  textFormat: Text.PlainText
                  text: root.timeLabel(childDelegate.modelData.ts || childDelegate.modelData.closed_ts)
                  color: root.dimColor
                  font.family: Style.font.family
                  font.pixelSize: Style.font.caption
                }
              }

              MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onContainsMouseChanged: childSurface.hot = containsMouse
                onClicked: root.openRow(childDelegate.modelData)
              }
            }
          }
        }
      }
    }
  }
}

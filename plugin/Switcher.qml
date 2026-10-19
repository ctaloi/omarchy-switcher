import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// The SUPER+TAB app strip. Purely a view: ~/.config/hypr/switcher.lua owns the
// app order, the selection and the key handling, and pushes state here with
//   omarchy-shell switcher show '{"seq":1,"selected":0,"items":[{"class":..,"title":..,"count":..}]}'
//   omarchy-shell switcher close <seq>
// The surface never takes keyboard focus, so the SUPER release still reaches
// Hyprland.
Item {
  id: root

  property bool opened: false
  property var items: []
  property int selected: 0
  property real closedSeq: 0

  readonly property string home: Quickshell.env("HOME")
  readonly property int pad: Style.space(14)
  readonly property int tile: Style.space(112)
  readonly property int iconSize: Style.space(64)

  // class -> { name, icon } for apps Hyprland names differently from their
  // desktop entry. Omarchy web apps run as chromium windows classed
  // chrome-<host>_<path with / as _>-Default.
  property var classIndex: ({})

  function rebuildIndex() {
    var next = ({})
    var entries = DesktopEntries.applications.values || []
    for (var i = 0; i < entries.length; i++) {
      var e = entries[i]
      var info = { name: e.name || "", icon: e.icon || "" }
      if (e.startupClass) next[String(e.startupClass).toLowerCase()] = info
      if (e.id) next[String(e.id).toLowerCase()] = info
      var m = String(e.execString || "").match(/omarchy-launch-webapp\s+"?(https?:\/\/[^\s"]+)/)
      if (m) {
        var url = m[1].replace(/^https?:\/\//, "")
        var slash = url.indexOf("/")
        var host = slash < 0 ? url : url.slice(0, slash)
        var path = slash < 0 ? "/" : url.slice(slash)
        next[("chrome-" + host + "_" + path.replace(/\//g, "_") + "-Default").toLowerCase()] = info
      }
    }
    root.classIndex = next
  }

  function infoFor(cls) {
    var key = String(cls || "").toLowerCase()
    var hit = root.classIndex[key]
    if (!hit) {
      var parts = key.split(".")
      hit = root.classIndex[parts[parts.length - 1]]
    }
    return hit || { name: "", icon: key }
  }

  // Ordered guesses for an icon name. The themed lookup's cache never rescans,
  // so icons installed after the shell started are tried as plain files too.
  function iconSources(icon) {
    var value = String(icon || "")
    if (value === "") return []
    if (value.charAt(0) === "/") return ["file://" + value]
    var out = []
    var themed = Quickshell.iconPath(value, true)
    if (themed) out.push(themed)
    var dirs = [root.home + "/.local/share/icons/hicolor", "/usr/share/icons/hicolor"]
    for (var i = 0; i < dirs.length; i++) {
      out.push("file://" + dirs[i] + "/256x256/apps/" + value + ".png")
      out.push("file://" + dirs[i] + "/scalable/apps/" + value + ".svg")
    }
    out.push("file:///usr/share/pixmaps/" + value + ".png")
    return out
  }

  function prettyClass(cls) {
    var value = String(cls || "")
    var parts = value.split(".")
    value = parts[parts.length - 1]
    return value.charAt(0).toUpperCase() + value.slice(1)
  }

  function show(payloadJson) {
    try {
      var p = JSON.parse(payloadJson || "{}")
      if ((p.seq || 0) <= root.closedSeq) return
      root.items = p.items || []
      root.selected = p.selected || 0
      root.opened = root.items.length > 0
    } catch (e) {}
  }

  Component.onCompleted: rebuildIndex()

  Connections {
    target: DesktopEntries.applications
    function onValuesChanged() { root.rebuildIndex() }
  }

  IpcHandler {
    target: "switcher"
    function show(payloadJson: string): string { root.show(payloadJson); return "ok" }
    function close(seq: string): string {
      root.closedSeq = Math.max(root.closedSeq, Number(seq) || 0)
      root.opened = false
      return "ok"
    }
    function ping(): string { return "ok" }
  }

  PanelWindow {
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "chris-switcher"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore
    mask: Region {}

    BorderSurface {
      id: card
      anchors.centerIn: parent
      width: Math.min(parent.width - Style.space(48), card.borderLeft + root.pad + strip.implicitWidth + root.pad + card.borderRight)
      height: card.borderTop + root.pad + root.tile + root.pad + card.borderBottom
      color: Commons.Color.popups.background
      borderSpec: Border.surfaceSpec("popups", "border", Commons.Color.popups.border, Math.max(1, Style.space(2)))
      radius: Style.cornerRadius

      ListView {
        id: strip
        anchors.fill: parent
        anchors.topMargin: card.borderTop + root.pad
        anchors.bottomMargin: card.borderBottom + root.pad
        anchors.leftMargin: card.borderLeft + root.pad
        anchors.rightMargin: card.borderRight + root.pad
        orientation: ListView.Horizontal
        spacing: Style.space(6)
        interactive: false
        clip: true
        implicitWidth: root.items.length * root.tile + Math.max(0, root.items.length - 1) * spacing
        model: root.items
        currentIndex: root.selected
        highlightMoveDuration: 0
        preferredHighlightBegin: width / 2 - root.tile / 2
        preferredHighlightEnd: width / 2 + root.tile / 2
        highlightRangeMode: implicitWidth > width ? ListView.StrictlyEnforceRange : ListView.NoHighlightRange

        delegate: Item {
          id: cell
          required property var modelData
          required property int index
          readonly property bool current: index === root.selected
          readonly property var info: root.infoFor(modelData.class)
          readonly property var sources: root.iconSources(info.icon)
          property int sourceIndex: 0
          width: root.tile
          height: root.tile

          Rectangle {
            anchors.fill: parent
            radius: Math.max(Style.cornerRadius, Style.space(6))
            color: cell.current ? Util.alpha(Commons.Color.accent, 0.22) : "transparent"
            border.width: cell.current ? Math.max(1, Style.space(2)) : 0
            border.color: Commons.Color.accent
          }

          Image {
            id: icon
            anchors.horizontalCenter: parent.horizontalCenter
            y: Style.space(10)
            width: root.iconSize
            height: root.iconSize
            sourceSize: Qt.size(root.iconSize * 2, root.iconSize * 2)
            fillMode: Image.PreserveAspectFit
            smooth: true
            asynchronous: false
            source: cell.sourceIndex < cell.sources.length ? cell.sources[cell.sourceIndex] : ""
            onStatusChanged: if (status === Image.Error) cell.sourceIndex++
            visible: status === Image.Ready
          }

          // No icon found: a letter tile.
          Rectangle {
            anchors.fill: icon
            visible: icon.status !== Image.Ready
            radius: Style.space(12)
            color: Util.alpha(Commons.Color.popups.text, 0.12)
            Text {
              anchors.centerIn: parent
              text: (cell.info.name || root.prettyClass(cell.modelData.class)).charAt(0).toUpperCase()
              font.family: Style.font.family
              font.bold: true
              font.pixelSize: root.iconSize / 2
              color: Commons.Color.popups.text
            }
          }

          // Window count, macOS-dock style dots under the icon.
          Row {
            visible: cell.modelData.count > 1
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: icon.bottom
            anchors.topMargin: Style.space(3)
            spacing: Style.space(3)
            Repeater {
              model: Math.min(cell.modelData.count, 4)
              Rectangle {
                width: Style.space(4); height: width; radius: width / 2
                color: Commons.Color.popups.text
                opacity: 0.7
              }
            }
          }

          Text {
            anchors.bottom: parent.bottom
            anchors.bottomMargin: Style.space(6)
            anchors.horizontalCenter: parent.horizontalCenter
            width: parent.width - Style.space(10)
            horizontalAlignment: Text.AlignHCenter
            textFormat: Text.PlainText
            text: cell.info.name || root.prettyClass(cell.modelData.class)
            font.family: Style.font.family
            font.bold: cell.current
            font.pixelSize: Style.font.body
            color: Commons.Color.popups.text
            opacity: cell.current ? 1 : 0.75
            elide: Text.ElideRight
            maximumLineCount: 1
          }
        }
      }
    }
  }
}

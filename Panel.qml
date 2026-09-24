import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Ui

// Standalone panel plugin: browses the local theme catalog scraped from
// omarchythemes.com (see scripts/scrape-catalog.sh) and installs the
// selected theme via `omarchy theme install` / `omarchy theme set`.
//
// Summon with: omarchy-shell shell summon lory.theme-gallery '{}'
Item {
  id: root

  readonly property string pluginDir: Quickshell.env("HOME") + "/.config/omarchy/plugins/lory.theme-gallery"

  property var shell: null
  property var manifest: null

  property bool opened: false
  property var themes: []
  property string filterText: ""
  property string installingSlug: ""
  property string statusText: ""
  property bool statusError: false
  property bool refreshing: false
  property string refreshProgress: ""
  property int refreshCurrent: 0
  property int refreshTotal: 0

  readonly property int gridColumns: 4
  readonly property int gridCellWidth: Style.space(200)
  readonly property int gridCellHeight: Style.space(210)

  readonly property var filteredThemes: {
    var q = filterText.trim().toLowerCase()
    if (q === "") return themes
    return themes.filter(function(t) {
      return t.name.toLowerCase().indexOf(q) !== -1
        || (t.author || "").toLowerCase().indexOf(q) !== -1
    })
  }

  function open(payloadJson) {
    root.opened = true
    Qt.callLater(function() {
      if (root.opened) searchField.forceActiveFocus()
    })
  }

  function close() {
    root.opened = false
  }

  function dismiss() {
    if (root.shell && typeof root.shell.hide === "function")
      root.shell.hide((root.manifest && root.manifest.id) || "lory.theme-gallery")
    else close()
  }

  function loadCatalog(text) {
    try {
      var parsed = JSON.parse(text || "{}")
      root.themes = parsed.themes || []
    } catch (e) {
      root.themes = []
      root.statusText = "Could not read the theme catalog"
      root.statusError = true
    }
  }

  function themeBySlug(slug) {
    for (var i = 0; i < root.themes.length; i++)
      if (root.themes[i].slug === slug) return root.themes[i]
    return null
  }

  function installTheme(theme) {
    if (root.installingSlug !== "") return
    root.installingSlug = theme.slug
    root.statusError = false
    root.statusText = "Installing " + theme.name + "…"
    installProc.errorText = ""
    installProc.command = theme.repo
      ? ["omarchy", "theme", "install", theme.repo]
      : ["omarchy", "theme", "set", theme.slug]
    installProc.running = true
  }

  function startRefresh() {
    if (root.refreshing) return
    root.refreshing = true
    root.refreshProgress = ""
    root.refreshCurrent = 0
    root.refreshTotal = 0
    root.statusError = false
    root.statusText = ""
    refreshProc.command = [root.pluginDir + "/scripts/refresh.sh"]
    refreshProc.running = true
  }

  FileView {
    id: catalogFile
    path: root.pluginDir + "/cache/catalog.json"
    watchChanges: true
    printErrors: false
    onLoaded: root.loadCatalog(text())
    onLoadFailed: {
      root.themes = []
      root.statusText = "No catalog yet — run scripts/scrape-catalog.sh"
      root.statusError = true
    }
  }

  Process {
    id: installProc
    property string errorText: ""
    stdout: StdioCollector { waitForEnd: true }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: installProc.errorText = String(text || "").trim()
    }
    onExited: function(exitCode) {
      var theme = root.themeBySlug(root.installingSlug)
      var label = theme ? theme.name : "Theme"
      if (exitCode === 0) {
        root.statusError = false
        root.statusText = label + " installed and applied"
      } else {
        root.statusError = true
        root.statusText = "Install failed: " + (installProc.errorText || "unknown error")
      }
      root.installingSlug = ""
    }
  }

  Process {
    id: refreshProc
    property string errorText: ""
    stdout: StdioCollector { waitForEnd: true }
    stderr: SplitParser {
      onRead: function(line) {
        var m = line.match(/^\[(\d+)\/(\d+)\]/)
        if (m) {
          root.refreshCurrent = parseInt(m[1], 10)
          root.refreshTotal = parseInt(m[2], 10)
          root.refreshProgress = m[1] + "/" + m[2]
        }
        refreshProc.errorText = line
      }
    }
    onExited: function(exitCode) {
      root.refreshing = false
      root.refreshProgress = ""
      root.refreshCurrent = 0
      root.refreshTotal = 0
      if (exitCode === 0) {
        root.statusError = false
        root.statusText = "Catalog refreshed"
        catalogFile.reload()
      } else {
        root.statusError = true
        root.statusText = "Refresh failed: " + (refreshProc.errorText || "unknown error")
      }
    }
  }

  PanelWindow {
    id: win
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "lory-theme-gallery"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: root.opened ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    Rectangle {
      anchors.fill: parent
      color: Qt.rgba(0, 0, 0, 0.6)
      MouseArea { anchors.fill: parent; onClicked: root.dismiss() }
    }

    Item {
      anchors.fill: parent
      focus: true
      Keys.onEscapePressed: root.dismiss()

      Rectangle {
        id: card
        anchors.centerIn: parent
        width: Math.min(parent.width - Style.space(80), root.gridColumns * root.gridCellWidth + Style.spacing.panelPadding * 2)
        height: Math.min(parent.height - Style.space(80), Style.space(680))
        radius: Style.cornerRadius
        color: Color.background
        border.color: Style.normalBorderColor
        border.width: Style.normalBorderWidth

        MouseArea { anchors.fill: parent; onClicked: {} }

        ColumnLayout {
          anchors.fill: parent
          anchors.margins: Style.spacing.panelPadding
          spacing: Style.spacing.panelGap

          RowLayout {
            Layout.fillWidth: true
            spacing: Style.spacing.controlGap

            TextField {
              id: searchField
              Layout.preferredWidth: Style.space(220)
              placeholderText: "Filter by name or author…"
              text: root.filterText
              onTextChanged: root.filterText = text
            }

            Button {
              text: root.refreshing ? "Refreshing" + (root.refreshProgress !== "" ? " " + root.refreshProgress : "…") : "Refresh"
              iconText: root.refreshing ? "⟳" : ""
              iconSpinning: root.refreshing
              bordered: true
              onClicked: root.startRefresh()
            }

            Button {
              text: "Close"
              bordered: true
              onClicked: root.dismiss()
            }

            Item { Layout.fillWidth: true }

            Text {
              textFormat: Text.PlainText
              text: "Theme Gallery"
              color: Color.foreground
              font.family: Style.font.family
              font.pixelSize: Style.font.title
              font.bold: true
            }
          }

          Text {
            textFormat: Text.PlainText
            visible: root.statusText !== ""
            text: root.statusText
            color: root.statusError ? Color.urgent : Color.accent
            font.family: Style.font.family
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.Wrap
            Layout.fillWidth: true
          }

          Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            ColumnLayout {
              anchors.centerIn: parent
              width: Math.min(parent.width - Style.space(80), Style.space(360))
              visible: root.filteredThemes.length === 0 && !root.refreshing
              spacing: Style.spacing.md

              Text {
                textFormat: Text.PlainText
                text: root.themes.length === 0
                  ? "No themes cached yet."
                  : "No themes match “" + root.filterText + "”."
                color: Color.foreground
                opacity: 0.8
                font.family: Style.font.family
                font.pixelSize: Style.font.body
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                Layout.fillWidth: true
              }

              Text {
                textFormat: Text.PlainText
                visible: root.themes.length === 0
                text: "Click Refresh above to fetch the catalog from omarchythemes.com (takes a few minutes on first run)."
                color: Color.foreground
                opacity: 0.55
                font.family: Style.font.family
                font.pixelSize: Style.font.bodySmall
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                Layout.fillWidth: true
              }
            }

            ColumnLayout {
              anchors.centerIn: parent
              width: Math.min(parent.width - Style.space(80), Style.space(360))
              visible: root.refreshing && root.themes.length === 0
              spacing: Style.spacing.md

              Text {
                textFormat: Text.PlainText
                text: "Fetching theme catalog…"
                color: Color.foreground
                opacity: 0.8
                font.family: Style.font.family
                font.pixelSize: Style.font.body
                horizontalAlignment: Text.AlignHCenter
                Layout.fillWidth: true
              }

              Text {
                textFormat: Text.PlainText
                text: root.refreshTotal > 0
                  ? root.refreshCurrent + " / " + root.refreshTotal
                  : "Starting…"
                color: Color.foreground
                opacity: 0.55
                font.family: Style.font.family
                font.pixelSize: Style.font.bodySmall
                horizontalAlignment: Text.AlignHCenter
                Layout.fillWidth: true
              }

              Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: Style.space(6)
                radius: height / 2
                color: Style.normalFill
                border.color: Style.normalBorderColor
                border.width: Style.normalBorderWidth

                Rectangle {
                  height: parent.height
                  radius: parent.radius
                  color: Color.accent
                  width: root.refreshTotal > 0
                    ? Math.max(height, parent.width * Math.min(1, root.refreshCurrent / root.refreshTotal))
                    : 0

                  Behavior on width { NumberAnimation { duration: 150 } }
                }
              }
            }

            GridView {
              id: grid
              anchors.fill: parent
              visible: root.filteredThemes.length > 0
              clip: true
              cellWidth: root.gridCellWidth
              cellHeight: root.gridCellHeight
              model: root.filteredThemes

              delegate: Item {
              id: delegateRoot
              required property var modelData
              width: grid.cellWidth
              height: grid.cellHeight

              Rectangle {
                anchors.fill: parent
                anchors.margins: Style.spacing.sm
                radius: Style.cornerRadius
                color: Style.normalFill
                border.color: Style.normalBorderColor
                border.width: Style.normalBorderWidth

                ColumnLayout {
                  anchors.fill: parent
                  anchors.margins: Style.spacing.sm
                  spacing: Style.spacing.xs

                  Image {
                    id: thumb
                    Layout.fillWidth: true
                    Layout.preferredHeight: Style.space(110)
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    source: "file://" + root.pluginDir + "/cache/thumbs/" + delegateRoot.modelData.slug + ".jpg"
                    onStatusChanged: {
                      if (status === Image.Error && delegateRoot.modelData.thumb)
                        source = delegateRoot.modelData.thumb
                    }
                  }

                  Text {
                    textFormat: Text.PlainText
                    text: delegateRoot.modelData.name
                    color: Color.foreground
                    font.family: Style.font.family
                    font.pixelSize: Style.font.body
                    font.bold: true
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                  }

                  Text {
                    textFormat: Text.PlainText
                    text: (delegateRoot.modelData.author ? "by " + delegateRoot.modelData.author : "")
                      + (delegateRoot.modelData.kind === "official" ? "  ·  official" : "")
                    color: Color.foreground
                    opacity: 0.6
                    font.family: Style.font.family
                    font.pixelSize: Style.font.caption
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                  }

                  Item { Layout.fillHeight: true }

                  Button {
                    Layout.fillWidth: true
                    bordered: true
                    text: root.installingSlug === delegateRoot.modelData.slug ? "Installing…"
                      : delegateRoot.modelData.repo ? "Install"
                      : "Apply"
                    iconText: root.installingSlug === delegateRoot.modelData.slug ? "⟳" : ""
                    iconSpinning: root.installingSlug === delegateRoot.modelData.slug
                    onClicked: root.installTheme(delegateRoot.modelData)
                  }
                }
              }
            }
          }
        }

          Text {
            textFormat: Text.PlainText
            Layout.alignment: Qt.AlignRight
            text: root.themes.length > 0 ? root.themes.length + " themes" : ""
            color: Color.foreground
            opacity: 0.5
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
          }
      }
    }
  }
}
}



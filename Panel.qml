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
  property var installedSlugs: []
  property var detailTheme: null
  property string currentThemeSlug: ""
  property string sortMode: "name-asc"

  readonly property var sortOptions: [
    { value: "name-asc", label: "Name (A-Z)" },
    { value: "name-desc", label: "Name (Z-A)" }
  ]

  readonly property int gridColumns: 4
  readonly property int gridCellWidth: Style.space(200)
  readonly property int gridCellHeight: Style.space(210)

  readonly property string userThemesDir: Quickshell.env("HOME") + "/.config/omarchy/themes"
  readonly property string stockThemesDir: Quickshell.env("OMARCHY_PATH") + "/themes"
  readonly property string currentThemeStatePath: Quickshell.env("HOME") + "/.local/state/omarchy/current/theme.name"

  readonly property var filteredThemes: {
    var q = filterText.trim().toLowerCase()
    var list = q === "" ? themes.slice() : themes.filter(function(t) {
      return t.name.toLowerCase().indexOf(q) !== -1
        || (t.author || "").toLowerCase().indexOf(q) !== -1
    })
    var dir = root.sortMode === "name-desc" ? -1 : 1
    list.sort(function(a, b) {
      return dir * a.name.toLowerCase().localeCompare(b.name.toLowerCase())
    })
    return list
  }

  function open(payloadJson) {
    root.opened = true
    root.refreshInstalledSlugs()
    Qt.callLater(function() {
      if (root.opened) searchField.forceActiveFocus()
    })
  }

  function close() {
    root.opened = false
    root.detailTheme = null
  }

  function openDetail(theme) {
    root.detailTheme = theme
  }

  function closeDetail() {
    root.detailTheme = null
  }

  function isInstalled(theme) {
    return theme && root.installedSlugs.indexOf(String(theme.slug).toLowerCase()) !== -1
  }

  function isCurrent(theme) {
    return theme && root.currentThemeSlug !== "" && String(theme.slug).toLowerCase() === root.currentThemeSlug
  }

  function refreshInstalledSlugs() {
    installedListProc.running = false
    installedListProc.running = true
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
    var alreadyInstalled = root.isInstalled(theme)
    root.installingSlug = theme.slug
    root.statusError = false
    root.statusText = (alreadyInstalled ? "Applying " : "Installing ") + theme.name + "…"
    installProc.errorText = ""
    installProc.command = (theme.repo && !alreadyInstalled)
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

  // Tracks the live active theme so a card can show "Current" instead of
  // Install/Apply. watchChanges means switching themes any other way (the
  // built-in switcher, `omarchy theme set` in a terminal) updates this too.
  FileView {
    id: currentThemeFile
    path: root.currentThemeStatePath
    watchChanges: true
    printErrors: false
    onLoaded: root.currentThemeSlug = text().trim().toLowerCase()
    onLoadFailed: root.currentThemeSlug = ""
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
        root.statusText = label + " applied"
        root.refreshInstalledSlugs()
      } else {
        root.statusError = true
        root.statusText = "Install failed: " + (installProc.errorText || "unknown error")
      }
      root.installingSlug = ""
    }
  }

  Process {
    id: installedListProc
    command: ["bash", "-c", 'ls -1 "$1" 2>/dev/null; ls -1 "$2" 2>/dev/null',
      "bash", root.userThemesDir, root.stockThemesDir]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.installedSlugs = String(text || "").split("\n")
          .map(function(s) { return s.trim().toLowerCase() })
          .filter(function(s) { return s.length > 0 })
      }
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
      Keys.onEscapePressed: root.detailTheme !== null ? root.closeDetail() : root.dismiss()

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

            Dropdown {
              Layout.preferredWidth: Style.space(160)
              showLabel: false
              options: root.sortOptions
              value: root.sortMode
              onChanged: function(v) { root.sortMode = v }
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
                border.color: root.isCurrent(delegateRoot.modelData) ? Color.accent : Style.normalBorderColor
                border.width: root.isCurrent(delegateRoot.modelData) ? Math.max(2, Style.normalBorderWidth) : Style.normalBorderWidth

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

                    MouseArea {
                      anchors.fill: parent
                      cursorShape: Qt.PointingHandCursor
                      onClicked: root.openDetail(delegateRoot.modelData)
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
                    selected: root.isCurrent(delegateRoot.modelData)
                    text: root.installingSlug === delegateRoot.modelData.slug
                      ? (root.isInstalled(delegateRoot.modelData) ? "Applying…" : "Installing…")
                      : root.isCurrent(delegateRoot.modelData) ? "Current"
                      : root.isInstalled(delegateRoot.modelData) ? "Apply"
                      : delegateRoot.modelData.repo ? "Install"
                      : "Apply"
                    iconText: root.installingSlug === delegateRoot.modelData.slug ? "⟳" : ""
                    iconSpinning: root.installingSlug === delegateRoot.modelData.slug
                    onClicked: {
                      if (root.isCurrent(delegateRoot.modelData)) return
                      root.installTheme(delegateRoot.modelData)
                    }
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

      Rectangle {
        id: detailOverlay
        anchors.fill: parent
        visible: root.detailTheme !== null
        color: Qt.rgba(0, 0, 0, 0.75)
        z: 10

        MouseArea { anchors.fill: parent; onClicked: root.closeDetail() }

        Rectangle {
          id: detailCard
          anchors.centerIn: parent
          width: Math.min(parent.width - Style.space(80), Style.space(760))
          height: Math.min(parent.height - Style.space(80), detailContent.implicitHeight + Style.spacing.panelPadding * 2)
          radius: Style.cornerRadius
          color: Color.background
          border.color: root.isCurrent(root.detailTheme) ? Color.accent : Style.normalBorderColor
          border.width: root.isCurrent(root.detailTheme) ? Math.max(2, Style.normalBorderWidth) : Style.normalBorderWidth

          MouseArea { anchors.fill: parent; onClicked: {} }

          ColumnLayout {
            id: detailContent
            anchors.fill: parent
            anchors.margins: Style.spacing.panelPadding
            spacing: Style.spacing.md

            Image {
              Layout.fillWidth: true
              Layout.preferredHeight: Style.space(380)
              fillMode: Image.PreserveAspectFit
              asynchronous: true
              source: root.detailTheme ? ("file://" + root.pluginDir + "/cache/thumbs/" + root.detailTheme.slug + ".jpg") : ""
              onStatusChanged: {
                if (status === Image.Error && root.detailTheme && root.detailTheme.thumb)
                  source = root.detailTheme.thumb
              }
            }

            RowLayout {
              Layout.fillWidth: true
              spacing: Style.spacing.controlGap

              Text {
                textFormat: Text.PlainText
                text: root.detailTheme ? root.detailTheme.name : ""
                color: Color.foreground
                font.family: Style.font.family
                font.pixelSize: Style.font.heading
                font.bold: true
                elide: Text.ElideRight
                Layout.fillWidth: true
              }

              Button {
                text: "Close"
                bordered: true
                onClicked: root.closeDetail()
              }
            }

            Text {
              textFormat: Text.PlainText
              text: (root.detailTheme && root.detailTheme.author ? "by " + root.detailTheme.author : "")
                + (root.detailTheme && root.detailTheme.kind === "official" ? "  ·  official" : "")
              color: Color.foreground
              opacity: 0.65
              font.family: Style.font.family
              font.pixelSize: Style.font.bodySmall
              Layout.fillWidth: true
            }

            Text {
              textFormat: Text.PlainText
              visible: root.detailTheme && root.detailTheme.apps && root.detailTheme.apps.length > 0
              text: root.detailTheme && root.detailTheme.apps ? "Themed apps: " + root.detailTheme.apps.join(", ") : ""
              color: Color.foreground
              opacity: 0.55
              font.family: Style.font.family
              font.pixelSize: Style.font.bodySmall
              wrapMode: Text.Wrap
              Layout.fillWidth: true
            }

            Text {
              textFormat: Text.PlainText
              visible: root.detailTheme && root.detailTheme.repo
              text: root.detailTheme ? root.detailTheme.repo : ""
              color: Color.accent
              font.family: Style.font.family
              font.pixelSize: Style.font.bodySmall
              font.underline: true
              elide: Text.ElideMiddle
              Layout.fillWidth: true

              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: Quickshell.execDetached(["omarchy-launch-browser", root.detailTheme.repo])
              }
            }

            Text {
              textFormat: Text.PlainText
              visible: root.detailTheme && !root.detailTheme.repo
              text: "Built into Omarchy — no external repo."
              color: Color.foreground
              opacity: 0.5
              font.family: Style.font.family
              font.pixelSize: Style.font.bodySmall
              Layout.fillWidth: true
            }

            Button {
              Layout.fillWidth: true
              bordered: true
              visible: root.detailTheme !== null
              selected: root.isCurrent(root.detailTheme)
              text: root.detailTheme && root.installingSlug === root.detailTheme.slug
                ? (root.isInstalled(root.detailTheme) ? "Applying…" : "Installing…")
                : root.isCurrent(root.detailTheme) ? "Current"
                : root.detailTheme && root.isInstalled(root.detailTheme) ? "Apply"
                : root.detailTheme && root.detailTheme.repo ? "Install"
                : "Apply"
              iconText: root.detailTheme && root.installingSlug === root.detailTheme.slug ? "⟳" : ""
              iconSpinning: root.detailTheme && root.installingSlug === root.detailTheme.slug
              onClicked: {
                if (root.isCurrent(root.detailTheme)) return
                root.installTheme(root.detailTheme)
              }
            }
          }
        }
      }
  }
}
}



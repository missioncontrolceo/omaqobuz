import QtQuick
import Quickshell
import Quickshell.Services.Mpris
import qs.Ui
import qs.Commons

// Now-playing widget bound to the Qobuz desktop app (QBZ), which publishes a
// standard MPRIS interface on org.mpris.MediaPlayer2.com.blitzfc.qbz.
// Unlike omarchy.media this never follows another player: when QBZ is closed
// the widget collapses to nothing rather than showing whatever else is playing.
BarWidget {
  id: root
  moduleName: "missioncontrolceo.omaqobuz"

  readonly property var players: Mpris.players ? Mpris.players.values : []
  readonly property var player: root.findQobuz()

  readonly property bool hasTrack: player !== null && (player.trackTitle || player.trackArtist)
  readonly property bool playing: player ? !!player.isPlaying : false
  readonly property string title: player ? (player.trackTitle || "") : ""
  readonly property string artist: player ? (player.trackArtist || "") : ""
  readonly property string album: player && player.trackAlbum ? player.trackAlbum : ""
  readonly property string artUrl: player && player.trackArtUrl ? player.trackArtUrl : ""

  // Settings live inline on the shell.json bar entry and are written back
  // through the plugin registry when a preference toggle is flipped.
  readonly property bool showArt: setting("showArt", true) !== false
  readonly property bool showLabel: setting("showLabel", true) !== false
  readonly property bool scrollLabel: setting("scrollLabel", true) !== false
  readonly property bool showSkipButtons: setting("showSkipButtons", false) === true
  readonly property real maxLabelWidth: setting("maxLabelWidth", 180)

  readonly property real trackLength: player && player.lengthSupported ? player.length : 0
  readonly property real trackPosition: player && player.positionSupported ? player.position : 0
  readonly property real progress: trackLength > 0 ? Math.max(0, Math.min(1, trackPosition / trackLength)) : 0

  property bool popupOpen: false
  property bool prefsOpen: false

  // QBZ identifies itself as "QBZ" / com.blitzfc.qbz. Match loosely so a
  // rename or a flatpak-style bus name still resolves.
  function isQobuz(candidate) {
    if (!candidate) return false
    var fields = [candidate.desktopEntry, candidate.identity, candidate.dbusName]
    for (var i = 0; i < fields.length; i++) {
      var field = fields[i]
      if (typeof field === "string" && /qbz|qobuz/i.test(field)) return true
    }
    return false
  }

  function findQobuz() {
    for (var i = 0; i < players.length; i++) {
      if (isQobuz(players[i])) return players[i]
    }
    return null
  }

  function playPause() {
    if (!player) return
    if (player.isPlaying && player.canPause) player.pause()
    else if (!player.isPlaying && player.canPlay) player.play()
    else if (player.canTogglePlaying) player.togglePlaying()
  }

  function next() {
    if (player && player.canGoNext) player.next()
  }

  function previous() {
    if (player && player.canGoPrevious) player.previous()
  }

  function showNowPlaying(open) {
    if (open) prefsOpen = false
    popupOpen = open
  }

  function showPrefs(open) {
    if (open) popupOpen = false
    prefsOpen = open
  }

  // PopupCard calls close() on its owner when a click lands outside it.
  function close() { popupOpen = false }

  // Optimistically update the in-memory settings, then write the value back to
  // this widget's entry in shell.json so it survives a shell restart.
  function persist(key, value) {
    var next = {}
    for (var k in settings) next[k] = settings[k]
    next[key] = value
    settings = next

    if (!bar || !bar.shell) return
    var registry = bar.shell.pluginRegistry
    if (!registry || typeof registry.setBarWidget !== "function") return
    var error = registry.setBarWidget(moduleName, key, value, {})
    if (error) console.warn(root.moduleName + ": could not persist " + key + ": " + error)
  }

  function formatTime(seconds) {
    if (!(seconds > 0)) return "0:00"
    var total = Math.floor(seconds)
    var mins = Math.floor(total / 60)
    var secs = total % 60
    if (mins >= 60) {
      var hours = Math.floor(mins / 60)
      mins = mins % 60
      return hours + ":" + (mins < 10 ? "0" : "") + mins + ":" + (secs < 10 ? "0" : "") + secs
    }
    return mins + ":" + (secs < 10 ? "0" : "") + secs
  }

  visible: hasTrack
  implicitWidth: hasTrack ? row.implicitWidth + Style.space(12) : 0
  implicitHeight: barSize

  onHasTrackChanged: if (!hasTrack) {
    popupOpen = false
    prefsOpen = false
  }

  // MPRIS position is pulled on demand, so nudge the player to re-read it
  // while the popup is showing a progress bar that has to move.
  Timer {
    running: root.popupOpen && root.playing && root.player !== null && root.player.positionSupported
    interval: 1000
    repeat: true
    onTriggered: if (root.player) root.player.positionChanged()
  }

  // Second popup's owner, so outside-click dismissal and the bar's popout
  // coordinator can tell the preferences card apart from the now-playing one.
  QtObject {
    id: prefsOwner
    function close() { root.prefsOpen = false }
  }

  Row {
    id: row
    anchors.centerIn: parent
    spacing: Style.space(6)

    BarIconButton {
      bar: root.bar
      visible: root.showSkipButtons
      text: "󰒮"
      tooltipText: "Previous track"
      dimmed: !(root.player && root.player.canGoPrevious)
      anchors.verticalCenter: parent.verticalCenter
      onPressed: function(button) {
        if (button === Qt.RightButton) root.showPrefs(!root.prefsOpen)
        else root.previous()
      }
    }

    Item {
      id: info
      width: infoRow.implicitWidth
      height: root.barSize
      anchors.verticalCenter: parent.verticalCenter

      // Declared before the content so the glyphs and artwork sit on top of
      // it; none of them accept clicks, so every press still lands here.
      MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton

        onClicked: function(mouse) {
          if (mouse.button === Qt.MiddleButton) root.next()
          else if (mouse.button === Qt.RightButton) root.showPrefs(!root.prefsOpen)
          else root.showNowPlaying(!root.popupOpen)
        }
        onWheel: function(wheel) {
          if (wheel.angleDelta.y > 0) root.previous()
          else if (wheel.angleDelta.y < 0) root.next()
        }
        onEntered: if (root.bar) root.bar.showTooltip(root, root.title + (root.artist ? " — " + root.artist : ""))
        onExited: if (root.bar) root.bar.hideTooltip(root)
      }

      Row {
        id: infoRow
        anchors.centerIn: parent
        spacing: Style.space(6)

        Item {
          id: artThumb
          readonly property real size: Math.max(Style.space(12), root.barSize - Style.space(10))
          width: visible ? size : 0
          height: size
          anchors.verticalCenter: parent.verticalCenter
          visible: root.showArt && root.artUrl !== ""
          clip: true

          Image {
            anchors.fill: parent
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            cache: true
            source: root.artUrl
            sourceSize.width: artThumb.size * 2
            sourceSize.height: artThumb.size * 2
          }
        }

        Text {
          id: glyph
          textFormat: Text.PlainText
          anchors.verticalCenter: parent.verticalCenter
          // Play/pause glyph doubles as the fallback icon when art is unavailable.
          text: root.playing ? "󰏤" : "󰐊"
          color: root.playing ? root.bar.barForeground : Qt.darker(root.bar.barForeground, 1.5)
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.body
          Behavior on color {
            enabled: !root.bar || root.bar.foregroundAnimationEnabled
            ColorAnimation { duration: 160 }
          }
        }

        Item {
          id: labelClip
          width: Math.min(root.maxLabelWidth, labelText.implicitWidth)
          height: glyph.height
          clip: true
          anchors.verticalCenter: parent.verticalCenter
          visible: root.showLabel && !root.bar.vertical && root.title !== ""

          Text {
            id: labelText
            textFormat: Text.PlainText
            text: root.title + (root.artist ? "  ·  " + root.artist : "")
            color: root.bar.barForeground
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.body
            anchors.verticalCenter: parent.verticalCenter
            // Scrolling drives x by animation; static mode elides inside the clip.
            width: root.scrollLabel ? implicitWidth : labelClip.width
            elide: root.scrollLabel ? Text.ElideNone : Text.ElideRight

            readonly property bool shouldScroll: root.scrollLabel
              && !root.bar.vertical
              && !root.popupOpen
              && !root.prefsOpen
              && implicitWidth > labelClip.width

            NumberAnimation on x {
              id: marquee
              running: labelText.shouldScroll
              loops: Animation.Infinite
              duration: Math.max(6000, labelText.implicitWidth * 25)
              from: labelClip.width
              to: -labelText.implicitWidth
              easing.type: Easing.Linear
              // Park the text back at the left edge whenever the marquee stops,
              // otherwise a static label keeps whatever offset the animation left.
              onRunningChanged: if (!running) labelText.x = 0
            }
          }
        }
      }
    }

    BarIconButton {
      bar: root.bar
      visible: root.showSkipButtons
      text: "󰒭"
      tooltipText: "Next track"
      dimmed: !(root.player && root.player.canGoNext)
      anchors.verticalCenter: parent.verticalCenter
      onPressed: function(button) {
        if (button === Qt.RightButton) root.showPrefs(!root.prefsOpen)
        else root.next()
      }
    }
  }

  PopupCard {
    id: popup
    anchorItem: root
    bar: root.bar
    owner: root
    open: root.popupOpen
    contentWidth: popup.fittedContentWidth(Style.space(260))
    contentHeight: popup.fittedContentHeight(column.implicitHeight)

    Column {
      id: column
      anchors.fill: parent
      spacing: Style.space(10)

      BorderSurface {
        id: artCard
        // Full width, but capped so a theme with a large base font size can't
        // grow the cover into a screen-filling card.
        anchors.horizontalCenter: parent.horizontalCenter
        width: Math.min(column.width, Style.space(280))
        height: width
        radius: Style.spacing.labelGap
        color: Style.normalFillFor(root.bar.foreground, Color.accent)
        borderSpec: Border.controlSpec("normal", root.bar.foreground, Color.accent)

        Image {
          anchors.fill: parent
          anchors.margins: Style.space(2)
          fillMode: Image.PreserveAspectCrop
          asynchronous: true
          cache: true
          source: root.artUrl
          sourceSize.width: artCard.width * 2
          sourceSize.height: artCard.width * 2
          visible: root.artUrl !== ""
        }

        Text {
          anchors.centerIn: parent
          visible: root.artUrl === ""
          text: "󰝚"
          color: root.bar.foreground
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.displayLarge
        }
      }

      Column {
        width: parent.width
        spacing: Style.space(4)

        Text {
          textFormat: Text.PlainText
          text: root.title || "Nothing playing"
          color: root.bar.foreground
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.subtitle
          font.bold: true
          elide: Text.ElideRight
          width: parent.width
        }

        Text {
          textFormat: Text.PlainText
          text: root.artist
          color: Qt.darker(root.bar.foreground, 1.3)
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.bodySmall
          elide: Text.ElideRight
          width: parent.width
          visible: text !== ""
        }

        Text {
          textFormat: Text.PlainText
          text: root.album
          color: Qt.darker(root.bar.foreground, 1.6)
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
          width: parent.width
          visible: text !== ""
        }
      }

      Column {
        width: parent.width
        spacing: Style.space(4)
        visible: root.trackLength > 0

        Rectangle {
          width: parent.width
          height: Math.max(2, Style.space(3))
          radius: height / 2
          color: Style.normalFillFor(root.bar.foreground, Color.accent)

          Rectangle {
            width: parent.width * root.progress
            height: parent.height
            radius: parent.radius
            color: Color.accent
          }
        }

        Item {
          width: parent.width
          height: elapsed.implicitHeight

          Text {
            id: elapsed
            textFormat: Text.PlainText
            anchors.left: parent.left
            text: root.formatTime(root.trackPosition)
            color: Qt.darker(root.bar.foreground, 1.6)
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.caption
          }

          Text {
            textFormat: Text.PlainText
            anchors.right: parent.right
            text: root.formatTime(root.trackLength)
            color: Qt.darker(root.bar.foreground, 1.6)
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.caption
          }
        }
      }

      Row {
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: Style.space(6)

        Button {
          iconText: "󰒮"
          foreground: root.bar.foreground
          horizontalPadding: Style.spacing.controlPaddingX
          verticalPadding: Style.spacing.controlPaddingY
          enabled: root.player && root.player.canGoPrevious
          opacity: enabled ? 1.0 : 0.4
          onClicked: root.previous()
        }

        Button {
          iconText: root.playing ? "󰏤" : "󰐊"
          foreground: root.bar.foreground
          horizontalPadding: Style.spacing.panelGap
          verticalPadding: Style.spacing.controlPaddingY
          iconSize: Style.font.iconLarge
          enabled: root.player && (root.player.canTogglePlaying || root.player.canPlay || root.player.canPause)
          opacity: enabled ? 1.0 : 0.4
          onClicked: root.playPause()
        }

        Button {
          iconText: "󰒭"
          foreground: root.bar.foreground
          horizontalPadding: Style.spacing.controlPaddingX
          verticalPadding: Style.spacing.controlPaddingY
          enabled: root.player && root.player.canGoNext
          opacity: enabled ? 1.0 : 0.4
          onClicked: root.next()
        }
      }

      PanelSeparator { foreground: root.bar.foreground }

      Button {
        anchors.horizontalCenter: parent.horizontalCenter
        text: "Preferences"
        iconText: "󰒓"
        foreground: root.bar.foreground
        horizontalPadding: Style.spacing.controlPaddingX
        verticalPadding: Style.spacing.controlPaddingY
        onClicked: root.showPrefs(true)
      }
    }
  }

  PopupCard {
    id: prefs
    anchorItem: root
    bar: root.bar
    owner: prefsOwner
    open: root.prefsOpen
    contentWidth: prefs.fittedContentWidth(Style.space(280))
    contentHeight: prefs.fittedContentHeight(prefsColumn.implicitHeight)

    Column {
      id: prefsColumn
      anchors.fill: parent
      spacing: Style.space(8)

      PanelSectionHeader {
        text: "Omaqobuz preferences"
        foreground: root.bar.foreground
        fontFamily: root.bar.fontFamily
      }

      Toggle {
        width: parent.width
        label: "Scroll track info"
        description: "Off keeps the title still and trims it to fit"
        checked: root.scrollLabel
        foreground: root.bar.foreground
        fontFamily: root.bar.fontFamily
        onClicked: root.persist("scrollLabel", !root.scrollLabel)
      }

      Toggle {
        width: parent.width
        label: "Skip buttons in the bar"
        description: "Previous and next either side of the track"
        checked: root.showSkipButtons
        foreground: root.bar.foreground
        fontFamily: root.bar.fontFamily
        onClicked: root.persist("showSkipButtons", !root.showSkipButtons)
      }

      Toggle {
        width: parent.width
        label: "Album art in the bar"
        description: "Cover thumbnail next to the track"
        checked: root.showArt
        foreground: root.bar.foreground
        fontFamily: root.bar.fontFamily
        onClicked: root.persist("showArt", !root.showArt)
      }

      Toggle {
        width: parent.width
        label: "Track info in the bar"
        description: "Off leaves just the icon and controls"
        checked: root.showLabel
        foreground: root.bar.foreground
        fontFamily: root.bar.fontFamily
        onClicked: root.persist("showLabel", !root.showLabel)
      }

      PanelSeparator { foreground: root.bar.foreground }

      Button {
        anchors.horizontalCenter: parent.horizontalCenter
        text: "Now playing"
        iconText: "󰝚"
        foreground: root.bar.foreground
        horizontalPadding: Style.spacing.controlPaddingX
        verticalPadding: Style.spacing.controlPaddingY
        onClicked: root.showNowPlaying(true)
      }
    }
  }
}

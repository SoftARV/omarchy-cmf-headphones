import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// Bar widget + popup for a CMF Headphone Pro.
//
// The device speaks Nothing's RFCOMM protocol on channel 28; everything here
// goes through the `cmfctl` CLI, which owns that protocol. See
// ~/Projects/cmfctl/FINDINGS.md.
Panel {
  id: root
  moduleName: "nec.cmf-headphones"
  ipcTarget: "nec.cmf-headphones"
  manageIpc: true

  // The brand's dot-matrix face, installed at
  // ~/.local/share/fonts/nothing-font/ (SIL OFL).
  readonly property string brandFont: "Nothing Font"

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property color barTint: cmf.connected ? barForeground : Qt.darker(barForeground, 1.6)

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  readonly property var ancOptions: [
    { label: "ANC", value: "anc" },
    { label: "Transparency", value: "transparency" },
    { label: "Off", value: "off" }
  ]

  // cmfctl reports the ANC level (high/mid/low/adaptive), while this group
  // offers a single "ANC" button. Fold the levels onto it so the right button
  // stays lit; the exact level is shown in the header line instead.
  readonly property var ancLevels: ["high", "mid", "low", "adaptive"]

  // Shown only while ANC is active, mirroring the phone app: the four levels
  // are meaningless in transparency or off.
  // Ordered low -> high then adaptive, as the phone app presents them.
  readonly property var levelOptions: [
    { label: "Low", value: "low" },
    { label: "Mid", value: "mid" },
    { label: "High", value: "high" },
    { label: "Adaptive", value: "adaptive" }
  ]
  readonly property bool ancActive: ancLevels.indexOf(cmf.displayAnc) >= 0

  function ancGroupValue(v) {
    return ancLevels.indexOf(v) >= 0 ? "anc" : v
  }

  function ancLabel(v) {
    if (ancLevels.indexOf(v) >= 0) return "ANC"
    for (var i = 0; i < ancOptions.length; i++)
      if (ancOptions[i].value === v) return ancOptions[i].label
    return v
  }

  CmfService {
    id: cmf
    settings: root.settings
    panelOpen: root.opened
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    iconComponent: Component {
      Item {
        NothingHeadphoneIcon {
          anchors.centerIn: parent
          iconSize: Style.space(15)
          color: root.barTint
        }
      }
    }
    onPressed: function (buttonCode) {
      if (buttonCode === Qt.RightButton) cmf.refresh()
      else root.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(360))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(400))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function (direction) { root.switchPanel(direction) }
      onTextKey: function (t) {
        var k = String(t).toLowerCase()
        if (k === "r") cmf.refresh()
        else if (k === "a") cmf.setAnc("anc")
        else if (k === "t") cmf.setAnc("transparency")
        else if (k === "o") cmf.setAnc("off")
        else if (k === "l") cmf.setLdac(!cmf.displayLdac)
      }

      Column {
        id: column
        width: parent.width
        spacing: Style.space(12)

        // Device name in the brand face, with the live readout beneath it in
        // the bar's own font -- the dot-matrix is a wordmark, not a face to
        // read numbers in.
        Column {
          width: parent.width
          spacing: Style.space(4)

          Text {
            text: "CMF Headphone Pro"
            font.family: root.brandFont
            font.pixelSize: Style.font.title
            color: (cmf.connected || cmf.restarting) ? root.foreground : root.dim
          }

          Text {
            width: parent.width
            text: {
              if (cmf.restarting) return "Restarting…"
              if (!cmf.connected) return "Not connected"
              var bits = []
              if (cmf.battery >= 0) bits.push(cmf.battery + "%")
              if (cmf.displayAnc !== "") bits.push(root.ancLabel(cmf.displayAnc))
              // The negotiated codec, not the LDAC flag -- the flag only says
              // the headphones will offer it.
              if (cmf.codec !== "") bits.push(cmf.codec.toUpperCase())
              else if (cmf.ldac) bits.push("LDAC")
              return bits.join("   ·   ")
            }
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            color: root.dim
          }
        }

        PanelSeparator { width: parent.width }

        PanelSectionHeader {
          width: parent.width
          text: "Noise control"
          foreground: root.dim
          fontFamily: root.fontFamily
        }

        ButtonGroup {
          width: parent.width
          enabled: cmf.connected
          opacity: cmf.connected ? 1.0 : 0.45
          options: root.ancOptions
          value: root.ancGroupValue(cmf.displayAnc)
          foreground: root.foreground
          fontFamily: root.fontFamily
          onChanged: function (value) { cmf.setAnc(value) }
        }

        ButtonGroup {
          width: parent.width
          visible: root.ancActive && cmf.connected
          enabled: cmf.connected
          options: root.levelOptions
          value: cmf.displayAnc
          foreground: root.foreground
          fontFamily: root.fontFamily
          fontSize: Style.font.bodySmall
          onChanged: function (value) { cmf.setAnc(value) }
        }

        PanelSeparator { width: parent.width }

        PanelSectionHeader {
          width: parent.width
          text: "Audio"
          foreground: root.dim
          fontFamily: root.fontFamily
        }

        RowLayout {
          width: parent.width
          spacing: Style.space(8)

          Column {
            Layout.fillWidth: true
            spacing: Style.space(2)

            Text {
              text: "Hi-res audio (LDAC)"
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              color: root.foreground
            }

            Text {
              text: cmf.restarting ? "Headphones restarting to apply…"
                                   : "Switching restarts the headphones"
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              color: root.dim
            }
          }

          ToggleSwitch {
            checked: cmf.displayLdac
            // busy also blocks the click, so the restart cannot be interrupted
            // by a second toggle mid-flight.
            busy: cmf.restarting || cmf.busy
            interactive: cmf.connected && !cmf.restarting
            foreground: root.foreground
            onToggled: cmf.setLdac(!cmf.displayLdac)
          }
        }

        Text {
          width: parent.width
          visible: cmf.actionStatus !== ""
          text: cmf.actionStatus
          wrapMode: Text.WordWrap
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          color: root.dim
        }
      }
    }
  }
}

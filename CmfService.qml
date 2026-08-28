import QtQuick
import Quickshell
import Quickshell.Io

// State for a CMF Headphone Pro, read through the `cmfctl` CLI.
//
// Every cmfctl invocation opens a fresh RFCOMM link and the connect dominates
// the cost, so state is gathered with a single `status --json` call rather than
// one call per value. Back-to-back connects can also hit EBUSY, which is a
// second reason not to fan out.
Item {
  id: root

  property var settings: ({})
  property bool panelOpen: false

  property bool connected: false
  property int battery: -1
  property string anc: ""            // "anc" | "off" | "transparency"
  property bool ldac: false          // the device flag: will it *offer* LDAC
  property string codec: ""          // what host and device actually negotiated
  property string lastError: ""
  property string actionStatus: ""

  // Whether the CLI this widget renders is installed at all. Kept separate
  // from `connected`, because "the tool is missing" and "the headphones are
  // off" want opposite advice and only one of them is the user's Bluetooth.
  property bool cmfctlMissing: false

  // Set while a write is in flight so the UI shows the intended mode
  // immediately instead of waiting a poll cycle for the device to confirm.
  property string pendingAnc: ""
  property int pendingLdac: -1       // -1 follow the device, else the value we asked for

  // Writing the LDAC flag power-cycles the headphones: they announce power-off,
  // restart and re-pair, which shows here as a ~6-9s disconnect. That gap is
  // expected, not a fault, so it is tracked separately from "headphones are
  // off" -- otherwise the panel would claim they are gone mid-restart.
  property bool restarting: false

  readonly property bool busy: statusProc.running || actionProc.running
  readonly property string displayAnc: pendingAnc !== "" ? pendingAnc : anc
  readonly property bool displayLdac: pendingLdac === -1 ? ldac : pendingLdac === 1

  // Mirrors of the stdio collectors: StdioCollector and onExited have no
  // guaranteed ordering, so reading collector.text alone can see an empty
  // string on a perfectly good run.
  property string _statusText: ""
  property string _statusErrText: ""

  function setting(name, fallback) {
    var v = settings ? settings[name] : undefined
    return v === undefined || v === null ? fallback : v
  }

  function intSetting(name, fallback, min, max) {
    var n = parseInt(String(setting(name, fallback)), 10)
    if (!isFinite(n)) n = fallback
    return Math.max(min, Math.min(max, n))
  }

  readonly property int idlePollSec: intSetting("idlePollSec", 120, 15, 900)
  readonly property int activePollSec: intSetting("activePollSec", 5, 2, 60)

  function refresh() {
    if (statusProc.running) return
    statusProc.running = true
  }

  function applyStatus(raw) {
    var parsed
    try {
      parsed = JSON.parse(String(raw || ""))
    } catch (e) {
      lastError = "Could not parse cmfctl output"
      return
    }
    connected = true
    battery = parsed.battery === null || parsed.battery === undefined ? -1 : Number(parsed.battery)
    anc = String(parsed.anc || "")
    ldac = parsed.ldac === true
    codec = String(parsed.codec || "")
    lastError = ""
    // Requesting "anc" is an alias for "high", but the device may answer with
    // whichever level it restored, so any level clears a pending "anc".
    var levels = ["high", "mid", "low", "adaptive"]
    if (pendingAnc !== ""
        && (anc === pendingAnc
            || (pendingAnc === "anc" && levels.indexOf(anc) >= 0)))
      pendingAnc = ""
    if (pendingLdac !== -1 && ldac === (pendingLdac === 1)) {
      pendingLdac = -1
      restarting = false
      restartGuard.stop()
    }
  }

  function setLdac(on) {
    // No dedicated cmfctl subcommand: the wrapper was shelved, so drive the
    // command id directly. SET_LHDC_COMMANDS takes a single byte.
    if (!connected || actionProc.running || restarting) return
    pendingLdac = on ? 1 : 0
    restarting = true
    restartGuard.restart()
    actionProc.command = ["cmfctl", "set", "SET_LHDC_COMMANDS", on ? "01" : "00"]
    actionProc.running = true
  }

  function setAnc(mode) {
    if (!connected || actionProc.running) return
    pendingAnc = mode
    actionProc.command = ["cmfctl", "anc", mode]
    actionProc.running = true
  }

  Component.onCompleted: {
    probe.running = true
    refresh()
  }

  // Presence is probed rather than inferred. Quickshell surfaces no dependable
  // exit code for a binary that fails to *start*, so a missing cmfctl and a
  // failing one are indistinguishable at statusProc -- which is exactly how a
  // user without the CLI came to be told their headphones were disconnected.
  // `sh` is always present, so the probe itself cannot fail to start.
  Process {
    id: probe
    running: false
    command: ["sh", "-c", "command -v cmfctl >/dev/null 2>&1"]
    onExited: function (exitCode) { root.cmfctlMissing = exitCode !== 0 }
  }

  Timer {
    id: poll
    interval: (root.panelOpen ? root.activePollSec : root.idlePollSec) * 1000
    repeat: true
    running: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  // Poll shortly after a write so the panel reflects reality quickly without
  // shortening the whole cycle.
  Timer {
    id: settle
    interval: 900
    repeat: false
    onTriggered: root.refresh()
  }

  // BlueZ announces connect/disconnect and A2DP transport changes on D-Bus.
  // Watching them means the widget reacts the moment the headphones come back
  // instead of waiting out the poll interval. A blocked read also keeps the CPU
  // in deeper idle states than a fast timer would.
  Process {
    id: btMonitor
    running: true
    command: ["gdbus", "monitor", "--system", "--dest", "org.bluez"]
    stdout: SplitParser {
      onRead: function (line) {
        var l = String(line)
        if (l.indexOf("'Connected'") >= 0 || l.indexOf("MediaTransport1") >= 0
            || l.indexOf("InterfacesAdded") >= 0 || l.indexOf("InterfacesRemoved") >= 0)
          debounce.restart()
      }
    }
  }

  // A connect emits a burst of signals; coalesce them, and give the transport a
  // moment to finish negotiating before asking what codec it settled on.
  Timer {
    id: debounce
    interval: 1500
    repeat: false
    onTriggered: root.refresh()
  }

  // If the headphones never come back, stop claiming they are restarting.
  Timer {
    id: restartGuard
    interval: 45000
    repeat: false
    onTriggered: {
      root.restarting = false
      root.pendingLdac = -1
    }
  }

  Timer {
    id: clearAction
    interval: 2500
    repeat: false
    onTriggered: root.actionStatus = ""
  }

  Process {
    id: statusProc
    running: false
    command: ["cmfctl", "status", "--json"]
    stdout: StdioCollector {
      id: statusOut
      waitForEnd: true
      onStreamFinished: root._statusText = String(text || "")
    }
    stderr: StdioCollector {
      id: statusErr
      waitForEnd: true
      onStreamFinished: root._statusErrText = String(text || "")
    }
    onExited: function (exitCode) {
      var out = String(statusOut.text || root._statusText || "")
      if (exitCode === 0 && out.trim() !== "") {
        root.applyStatus(out)
      } else if (exitCode !== 0) {
        // cmfctl exits non-zero when no CMF device is connected. That is the
        // normal "headphones are off" case, not an error worth shouting about.
        root.connected = false
        root.battery = -1
        root.anc = ""
        root.codec = ""
        root.pendingAnc = ""
        // pendingLdac and restarting deliberately survive: this disconnect is
        // the restart we asked for, and they clear when the device returns.
        root.lastError = String(statusErr.text || root._statusErrText || "").trim()
        // A failed status is the only hint that the CLI may have gone away, so
        // re-check rather than trusting the answer from startup.
        if (!probe.running) probe.running = true
      }
      root._statusText = ""
      root._statusErrText = ""
    }
  }

  Process {
    id: actionProc
    running: false
    command: []
    stdout: StdioCollector { id: actionOut; waitForEnd: true }
    stderr: StdioCollector { id: actionErr; waitForEnd: true }
    onExited: function (exitCode) {
      if (exitCode !== 0) {
        root.pendingAnc = ""
        root.pendingLdac = -1
        root.restarting = false
        restartGuard.stop()
        root.actionStatus = String(actionErr.text || "Command failed").trim()
        clearAction.restart()
      }
      settle.restart()
    }
  }
}

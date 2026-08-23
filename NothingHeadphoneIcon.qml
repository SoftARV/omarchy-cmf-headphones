import QtQuick

// Nothing's dot-matrix headphone mark, transcribed from the SVG they use on
// their product pages.
//
// Drawn as real QML circles rather than an embedded SVG so it takes the bar's
// foreground colour directly (the source uses fill="currentColor") and stays
// crisp at any size without a recolour pass.
//
// Source viewBox is 16x16 with the dot grid spanning x 1..15 and y 1.281..13.281
// at r=1, so the artwork is 16 wide by 14 tall; it is nudged down by 0.719
// units to sit centred in a square box.
Item {
  id: root

  property real iconSize: 16
  property color color: "white"

  implicitWidth: iconSize
  implicitHeight: iconSize

  readonly property real unit: iconSize / 16
  readonly property real dot: unit * 2

  // [cx, cy] in source units.
  readonly property var dots: [
    [5, 1.281], [7, 1.281], [9, 1.281], [11, 1.281],
    [3, 3.281], [13, 3.281],
    [3, 5.281], [13, 5.281],
    [3, 7.281], [13, 7.281],
    [1, 9.281], [5, 9.281], [11, 9.281], [15, 9.281],
    [1, 11.281], [5, 11.281], [11, 11.281], [15, 11.281],
    [1, 13.281], [3, 13.281], [5, 13.281],
    [11, 13.281], [13, 13.281], [15, 13.281]
  ]

  Repeater {
    model: root.dots
    delegate: Rectangle {
      required property var modelData
      width: root.dot
      height: root.dot
      radius: root.dot / 2
      color: root.color
      antialiasing: true
      x: (modelData[0] - 1) * root.unit
      y: (modelData[1] - 0.281) * root.unit
    }
  }
}

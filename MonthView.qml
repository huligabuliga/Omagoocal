import QtQuick
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Month view: six fixed rows, so paging never resizes the panel.
//
// Cells are open — ruled by hairlines rather than boxed in — and the only
// colour is the events themselves. Today is an accent numeral with a rule
// under it; days outside the month fade rather than disappear, because the
// last week of the previous month is usually why you are looking.
Item {
  id: root
  property var panel: null

  readonly property var weeks: Model.monthGrid(panel.anchor.getFullYear(),
                                               panel.anchor.getMonth(),
                                               panel.weekStart)
  readonly property real weekColumn: Style.space(28)
  readonly property real cellWidth: (width - weekColumn) / 7
  readonly property real headHeight: Style.space(22)
  readonly property real rowHeight: (height - headHeight) / 6
  readonly property int chipCapacity: Math.max(1, Math.floor((rowHeight - Style.space(26)) / Style.space(18)))

  // A press begins as the existing "open this day" click. Once it travels
  // far enough it becomes an all-day range selection instead. The MouseArea
  // that accepted the press keeps receiving positions outside its own cell,
  // so one gesture can cross week rows.
  property var dragStart: null
  property var dragEnd: null
  property bool draggingRange: false
  property real pressX: 0
  property real pressY: 0

  function dateAt(x, y) {
    var column = Math.max(0, Math.min(6, Math.floor((x - weekColumn) / cellWidth)))
    var week = Math.max(0, Math.min(5, Math.floor((y - headHeight) / rowHeight)))
    return weeks[week][column]
  }

  function beginRange(day, area, mouse) {
    var point = area.mapToItem(root, mouse.x, mouse.y)
    dragStart = day
    dragEnd = day
    draggingRange = false
    pressX = point.x
    pressY = point.y
  }

  function moveRange(area, mouse) {
    if (!dragStart) return false
    var point = area.mapToItem(root, mouse.x, mouse.y)
    var dx = point.x - pressX, dy = point.y - pressY
    if (!draggingRange && Math.sqrt(dx * dx + dy * dy) < Style.space(6)) return false
    draggingRange = true
    dragEnd = dateAt(point.x, point.y)
    return true
  }

  function finishRange() {
    if (draggingRange && dragStart && dragEnd)
      panel.compose(dragStart, true, dragEnd)
    cancelRange()
  }

  function cancelRange() {
    dragStart = null
    dragEnd = null
    draggingRange = false
  }

  function selected(day) {
    return draggingRange && Model.dayInRange(day, dragStart, dragEnd)
  }

  Column {
    anchors.fill: parent
    spacing: 0

    // ------------------------------------------------------- weekday heads
    Row {
      width: parent.width
      height: root.headHeight

      Item { width: root.weekColumn; height: parent.height }

      Repeater {
        model: Model.weekdayLabels(root.panel.weekStart)

        Item {
          required property var modelData
          width: root.cellWidth
          height: parent.height

          Text {
            anchors.left: parent.left
            anchors.leftMargin: Style.space(6)
            anchors.verticalCenter: parent.verticalCenter
            text: modelData
            color: root.panel.faint
            font.family: root.panel.mono
            font.pixelSize: Style.font.caption
            font.letterSpacing: 1.8
          }
        }
      }
    }

    // ------------------------------------------------------------- the grid
    Repeater {
      model: root.weeks

      Item {
        id: weekRow
        required property var modelData
        required property int index

        width: root.width
        height: root.rowHeight

        Rectangle {
          width: parent.width
          height: 1
          color: root.panel.hair
        }

        // ISO week number, set in the gutter. Small enough to ignore, there
        // when a colleague says "week 37".
        Text {
          x: Style.space(4)
          y: Style.space(6)
          width: root.weekColumn - Style.space(8)
          horizontalAlignment: Text.AlignRight
          text: Model.isoWeek(weekRow.modelData[0])
          color: Util.alpha(root.panel.ink, 0.18)
          font.family: root.panel.mono
          font.pixelSize: Style.font.caption
        }

        Row {
          x: root.weekColumn
          width: parent.width - root.weekColumn
          height: parent.height

          Repeater {
            model: weekRow.modelData

            Item {
              id: cell
              required property var modelData
              required property int index

              readonly property bool isToday: Model.sameDay(modelData, root.panel.now)
              readonly property bool inMonth: modelData.getMonth() === root.panel.anchor.getMonth()
              readonly property var dayEvents: Model.onDay(root.panel.events, modelData)
              readonly property int overflow: dayEvents.length - root.chipCapacity

              width: root.cellWidth
              height: parent.height

              Rectangle {
                anchors.fill: parent
                color: cellMouse.containsMouse ? Util.alpha(root.panel.ink, 0.035) : "transparent"
                Behavior on color { ColorAnimation { duration: 120 } }
              }

              Rectangle {
                anchors.left: parent.left
                width: 1
                height: parent.height
                visible: cell.index > 0
                color: root.panel.hair
              }

              MouseArea {
                id: cellMouse
                anchors.fill: parent
                hoverEnabled: true
                property bool dragged: false
                onPressed: function(mouse) {
                  dragged = false
                  root.beginRange(cell.modelData, cellMouse, mouse)
                }
                onPositionChanged: function(mouse) {
                  if (pressed && root.moveRange(cellMouse, mouse)) dragged = true
                }
                onReleased: {
                  if (dragged) root.finishRange()
                  else root.cancelRange()
                }
                onCanceled: {
                  dragged = false
                  root.cancelRange()
                }
                onClicked: {
                  if (!dragged) {
                    root.panel.anchor = cell.modelData
                    root.panel.setView("day")
                  }
                }
              }

              // ---- Date numeral.
              Text {
                id: numeral
                x: Style.space(6)
                y: Style.space(4)
                text: cell.modelData.getDate()
                color: cell.isToday ? Color.accent
                     : (cell.inMonth ? root.panel.ink : Util.alpha(root.panel.ink, 0.28))
                font.family: root.panel.mono
                font.pixelSize: Style.font.subtitle
                font.bold: cell.isToday
              }

              Rectangle {
                x: numeral.x
                y: numeral.y + numeral.implicitHeight + 1
                width: numeral.implicitWidth
                height: Style.space(2)
                visible: cell.isToday
                color: Color.accent
              }

              // The month's first day earns its name, so a cell at the edge
              // of the grid still says which month it belongs to.
              Text {
                anchors.left: numeral.right
                anchors.leftMargin: Style.space(4)
                anchors.baseline: numeral.baseline
                visible: cell.modelData.getDate() === 1
                text: Qt.formatDate(cell.modelData, "MMM").toUpperCase()
                color: Util.alpha(root.panel.ink, 0.4)
                font.family: root.panel.mono
                font.pixelSize: Style.font.caption
                font.letterSpacing: 1.2
              }

              PanelActionButton {
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: Style.space(2)
                visible: cellMouse.containsMouse
                iconText: "󰐕"
                fontSize: Style.font.caption
                foreground: root.panel.faint
                hoverColor: Color.accent
                tooltipText: "New event"
                onClicked: root.panel.compose(
                  new Date(cell.modelData.getFullYear(), cell.modelData.getMonth(),
                           cell.modelData.getDate(), 9, 0), false)
              }

              // ---- Events.
              Column {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.topMargin: Style.space(24)
                anchors.leftMargin: Style.space(3)
                anchors.rightMargin: Style.space(3)
                spacing: Style.space(2)

                Repeater {
                  model: Math.min(cell.dayEvents.length, root.chipCapacity)

                  EventChip {
                    required property int modelData
                    width: parent.width
                    height: Style.space(16)
                    compact: true
                    panel: root.panel
                    event: cell.dayEvents[modelData]
                    opacity: 0
                    Component.onCompleted: opacity = cell.inMonth ? 1 : 0.5
                    Behavior on opacity { NumberAnimation { duration: 180 } }
                  }
                }

                Text {
                  visible: cell.overflow > 0
                  text: "+" + cell.overflow + " more"
                  color: root.panel.faint
                  font.family: root.panel.mono
                  font.pixelSize: Style.font.caption
                }
              }

              RangePreview {
                readonly property var selectedRange: root.dragStart && root.dragEnd
                  ? Model.dayRange(root.dragStart, root.dragEnd) : null
                x: Style.space(3)
                y: Style.space(24)
                width: parent.width - Style.space(6)
                height: Style.space(16)
                visible: root.selected(cell.modelData)
                panel: root.panel
                showLabel: selectedRange !== null
                  && Model.sameDay(cell.modelData, selectedRange.start)
                z: 5
              }
            }
          }
        }
      }
    }
  }
}

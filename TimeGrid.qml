import QtQuick
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Week and day view: an hour rail on the left, one column per day, events
// positioned by time rather than listed.
//
// Day view is the same grid with one column — there is no second layout to
// keep in step, and the transition between them is just a column count.
//
// The one loud element is the now-line: a hairline in the theme accent with
// the live time set into the rail. Everything else is grey until an event
// gives it colour.
Item {
  id: root
  property var panel: null

  readonly property var days: panel.viewDays
  readonly property real railWidth: Style.space(54)
  readonly property real hourHeight: Style.space(46)
  readonly property real gridHeight: hourHeight * 24
  readonly property real columnWidth: days.length > 0
    ? (width - railWidth) / days.length
    : width

  // How many events a column may show side by side before the rest collapse
  // into a "+N". Derived from the column width, so week view stays terse and
  // day view — one column, seven times wider — opens right up.
  // Lanes are budgeted against a *readable* chip, not a minimum one, so a
  // wider panel buys wider chips rather than more slivers. In practice that
  // pins week view to three lanes and lets day view — one column, seven times
  // wider — open all the way up.
  //
  // Never below three: at two, the last lane is the marker, so a single real
  // event per overlap would survive and the week would read as empty.
  readonly property int maxLanes: Math.min(8, Math.max(3,
    Math.floor(columnWidth / Style.space(150))))

  // All-day events get a banner above the grid rather than a 24-hour block
  // inside it. Keep one empty row available even when there are no events:
  // it is the target for clicking or dragging out a new all-day event.
  readonly property var allDayRows: {
    var rows = []
    for (var i = 0; i < days.length; i++)
      rows.push(Model.splitAllDay(Model.onDay(panel.events, days[i])).allDay)
    return rows
  }
  readonly property real headHeight: Style.space(46)
  readonly property real bandHeight: Math.max(Style.space(28),
    allDayDepth * Style.space(20) + Style.space(8)
      + (allDayRows.some(function(r) { return r.length > allDayCap }) ? Style.space(14) : 0))

  // `days` and `allDayRows` do not change in the same frame, so a delegate
  // built for a 7-column week can outlive the switch to a 1-column day by an
  // instant and index past the end.
  function allDayFor(index) {
    return allDayRows[index] || []
  }

  // Three banners is as deep as the band goes before it starts eating the
  // grid. Anything past that is counted, not dropped.
  readonly property int allDayCap: 3
  readonly property int allDayDepth: {
    var max = 0
    for (var i = 0; i < allDayRows.length; i++) max = Math.max(max, allDayRows[i].length)
    return Math.min(max, allDayCap)
  }
  function allDayHidden(index) {
    return Math.max(0, allDayFor(index).length - allDayCap)
  }

  property var bandDragStart: null
  property var bandDragEnd: null
  property bool bandDragging: false
  property real bandPressX: 0
  property real bandPressY: 0

  function allDayAt(x) {
    var column = Math.max(0, Math.min(days.length - 1,
      Math.floor((x - railWidth) / columnWidth)))
    return days[column]
  }

  function beginAllDayRange(day, area, mouse) {
    var point = area.mapToItem(root, mouse.x, mouse.y)
    bandDragStart = day
    bandDragEnd = day
    bandDragging = false
    bandPressX = point.x
    bandPressY = point.y
  }

  function moveAllDayRange(area, mouse) {
    if (!bandDragStart) return false
    var point = area.mapToItem(root, mouse.x, mouse.y)
    var dx = point.x - bandPressX, dy = point.y - bandPressY
    if (!bandDragging && Math.sqrt(dx * dx + dy * dy) < Style.space(6)) return false
    bandDragging = true
    bandDragEnd = allDayAt(point.x)
    return true
  }

  function finishAllDayRange() {
    if (bandDragging && bandDragStart && bandDragEnd)
      panel.compose(bandDragStart, true, bandDragEnd)
    cancelAllDayRange()
  }

  function cancelAllDayRange() {
    bandDragStart = null
    bandDragEnd = null
    bandDragging = false
  }

  function allDaySelected(day) {
    return bandDragging && Model.dayInRange(day, bandDragStart, bandDragEnd)
  }

  Column {
    anchors.fill: parent
    spacing: 0

    // ------------------------------------------------------------- day heads
    Item {
      width: parent.width
      height: root.headHeight

      Row {
        anchors.fill: parent

        Item { width: root.railWidth; height: parent.height }

        Repeater {
          model: root.days

          Item {
            id: head
            required property var modelData
            required property int index
            readonly property bool isToday: Model.sameDay(modelData, root.panel.now)

            width: root.columnWidth
            height: parent.height

            Column {
              anchors.centerIn: parent
              spacing: Style.space(1)

              Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: Model.weekdayLabel(head.modelData)
                color: head.isToday ? Color.accent : root.panel.faint
                font.family: root.panel.mono
                font.pixelSize: Style.font.caption
                font.letterSpacing: 1.8
              }

              // Today is marked by weight and colour, not by a filled disc.
              // A circle behind a numeral in a monospace grid always ends up
              // fighting the column it sits in.
              Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: head.modelData.getDate()
                color: head.isToday ? Color.accent : root.panel.ink
                font.family: root.panel.mono
                font.pixelSize: Style.font.heading
                font.bold: head.isToday
              }
            }

            Rectangle {
              anchors.bottom: parent.bottom
              anchors.horizontalCenter: parent.horizontalCenter
              width: Style.space(20)
              height: Style.space(2)
              visible: head.isToday
              color: Color.accent
            }

            Rectangle {
              anchors.left: parent.left
              width: 1
              height: parent.height
              visible: index > 0
              color: root.panel.hair
            }
          }
        }
      }
    }

    Rectangle { width: parent.width; height: 1; color: root.panel.hair }

    // ---------------------------------------------------------- all-day band
    Item {
      width: parent.width
      height: root.bandHeight
      visible: height > 0

      Text {
        anchors.left: parent.left
        anchors.leftMargin: Style.space(6)
        anchors.top: parent.top
        anchors.topMargin: Style.space(5)
        text: "ALL DAY"
        color: root.panel.faint
        font.family: root.panel.mono
        font.pixelSize: Style.font.caption - 1
        font.letterSpacing: 1.2
      }

      Row {
        anchors.fill: parent
        anchors.topMargin: Style.space(4)

        Item { width: root.railWidth; height: parent.height }

        Repeater {
          model: root.days

          Item {
            id: dayCell
            required property int index
            width: root.columnWidth
            height: parent.height

            Rectangle {
              anchors.fill: parent
              visible: root.allDaySelected(root.days[dayCell.index])
              color: Util.alpha(Color.accent, root.panel.lightSurface ? 0.20 : 0.14)
              border.width: 1
              border.color: Util.alpha(Color.accent, 0.72)
            }

            MouseArea {
              id: allDayMouse
              anchors.fill: parent
              hoverEnabled: true
              property bool dragged: false
              onPressed: function(mouse) {
                dragged = false
                root.beginAllDayRange(root.days[dayCell.index], allDayMouse, mouse)
              }
              onPositionChanged: function(mouse) {
                if (pressed && root.moveAllDayRange(allDayMouse, mouse)) dragged = true
              }
              onReleased: {
                if (dragged) root.finishAllDayRange()
                else root.cancelAllDayRange()
              }
              onCanceled: {
                dragged = false
                root.cancelAllDayRange()
              }
              onClicked: {
                if (!dragged)
                  root.panel.compose(root.days[dayCell.index], true, root.days[dayCell.index])
              }
            }

            Column {
              anchors.fill: parent
              anchors.leftMargin: Style.space(2)
              anchors.rightMargin: Style.space(2)
              spacing: Style.space(2)

              Repeater {
                model: Math.min(root.allDayFor(dayCell.index).length, root.allDayDepth)

                EventChip {
                  required property int modelData
                  width: parent.width
                  height: Style.space(18)
                  compact: true
                  panel: root.panel
                  event: root.allDayFor(dayCell.index)[modelData]
                }
              }

              Text {
                visible: root.allDayHidden(dayCell.index) > 0
                width: parent.width
                text: "+" + root.allDayHidden(dayCell.index) + " more"
                color: bandMore.containsMouse ? Color.accent : root.panel.faint
                font.family: root.panel.mono
                font.pixelSize: Style.font.caption

                MouseArea {
                  id: bandMore
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: {
                    root.panel.anchor = root.days[dayCell.index]
                    root.panel.setView("day")
                  }
                }
              }
            }
          }
        }
      }

      Rectangle {
        anchors.bottom: parent.bottom
        width: parent.width
        height: 1
        color: root.panel.hair
      }
    }

    // --------------------------------------------------------------- the grid
    Flickable {
      id: scroller
      width: parent.width
      height: parent.height - root.headHeight - 1 - root.bandHeight
      contentHeight: root.gridHeight
      clip: true
      boundsBehavior: Flickable.StopAtBounds
      flickDeceleration: 4000

      // Opening on 00:00 wastes half the view on hours nobody has meetings
      // in. Land on the configured start of day, or far enough back to keep
      // the now-line in sight — whichever is later.
      //
      // This has to wait for a real height: at Component.onCompleted the
      // Flickable has none yet, and the viewport term silently drops out,
      // parking the grid an hour past where it belongs.
      property bool positioned: false

      function scrollToStart() {
        if (height <= 0 || positioned) return
        positioned = true
        var target = Math.max(root.panel.dayStartHour * root.hourHeight,
                              root.nowFraction * root.gridHeight - height * 0.35)
        contentY = Math.max(0, Math.min(target, root.gridHeight - height))
      }

      onHeightChanged: scrollToStart()
      Component.onCompleted: Qt.callLater(scrollToStart)

      Item {
        width: scroller.width
        height: root.gridHeight

        // ---- Hour rules and rail. Half-hour rules are drawn fainter so the
        //      eye can still land on an hour boundary.
        Repeater {
          model: 24

          Item {
            required property int index
            y: index * root.hourHeight
            width: scroller.width
            height: root.hourHeight

            Rectangle {
              width: parent.width
              height: 1
              color: root.panel.hair
            }

            Rectangle {
              y: root.hourHeight / 2
              x: root.railWidth
              width: parent.width - root.railWidth
              height: 1
              color: Util.alpha(root.panel.ink, 0.04)
            }

            Text {
              x: root.railWidth - width - Style.space(8)
              y: -implicitHeight / 2
              visible: index > 0
              text: Model.hourLabel(index, root.panel.hours12)
              color: root.panel.faint
              font.family: root.panel.mono
              font.pixelSize: Style.font.caption
            }
          }
        }

        // ---- Column rules, drawn over the hour rules so the grid reads as
        //      columns first and rows second.
        Repeater {
          model: root.days.length

          Rectangle {
            required property int index
            x: root.railWidth + index * root.columnWidth
            width: 1
            height: root.gridHeight
            visible: index > 0
            color: root.panel.hair
          }
        }

        // ---- Events.
        Repeater {
          model: root.days.length

          Item {
            id: column
            required property int index
            readonly property var laid: root.days[index]
              ? Model.layout(Model.splitAllDay(
                  Model.onDay(root.panel.events, root.days[index])).timed, root.maxLanes)
              : []

            x: root.railWidth + index * root.columnWidth
            width: root.columnWidth
            height: root.gridHeight

            Repeater {
              model: column.laid

              EventChip {
                required property var modelData
                readonly property var bounds: Model.dayBounds(modelData, root.days[column.index])
                readonly property real lane: root.columnWidth / modelData.lanes

                panel: root.panel
                event: modelData
                overflow: modelData.overflow === true
                onOverflowClicked: {
                  root.panel.anchor = root.days[column.index]
                  root.panel.setView("day")
                }
                // Overlapping events sit side by side but overlap by a
                // hair, so a stack of three still shows three spines.
                x: modelData.lane * lane + Style.space(2)
                width: lane - Style.space(3) + (modelData.lanes > 1 ? Style.space(4) : 0)
                y: bounds.top * root.gridHeight
                height: bounds.height * root.gridHeight - Style.space(1)
                z: modelData.lane

                opacity: 0
                Component.onCompleted: opacity = 1
                Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
              }
            }
          }
        }

        // ---- Now. The only element allowed to be this loud.
        Item {
          y: root.nowFraction * root.gridHeight
          width: scroller.width
          height: 1
          visible: root.showsToday
          z: 30

          Rectangle {
            x: root.railWidth
            width: parent.width - root.railWidth
            height: 1
            color: Color.accent
          }

          Rectangle {
            x: root.railWidth - width - Style.space(6)
            y: -height / 2 + 0.5
            width: nowText.implicitWidth + Style.space(10)
            height: nowText.implicitHeight + Style.space(4)
            radius: Style.cornerRadius > 0 ? height / 2 : 0
            color: Color.accent

            Text {
              id: nowText
              anchors.centerIn: parent
              text: Model.clockLabel(root.panel.now, root.panel.hours12)
              color: Model.readableOn(String(Color.accent))
              font.family: root.panel.mono
              font.pixelSize: Style.font.caption
              font.bold: true
            }
          }
        }
      }

      // Click empty grid to create an event at that time, rounded to the
      // half hour — the fastest path from "I need a slot here" to a saved
      // event.
      MouseArea {
        anchors.fill: parent
        z: -1
        acceptedButtons: Qt.LeftButton
        onClicked: function(mouse) {
          if (mouse.x < root.railWidth) return
          var col = Math.floor((mouse.x - root.railWidth) / root.columnWidth)
          if (col < 0 || col >= root.days.length) return
          var minutes = ((scroller.contentY + mouse.y) / root.gridHeight) * 1440
          minutes = Math.floor(minutes / 30) * 30
          var day = root.days[col]
          root.panel.compose(new Date(day.getFullYear(), day.getMonth(), day.getDate(),
                                      Math.floor(minutes / 60), minutes % 60), false)
        }
      }
    }
  }

  // ---- Now-line placement. Hoisted here so the Flickable can read it
  //      before the item that draws it exists.
  readonly property bool showsToday: {
    for (var i = 0; i < days.length; i++) if (Model.sameDay(days[i], panel.now)) return true
    return false
  }
  readonly property real nowFraction: {
    var n = panel.now
    return (n.getHours() * 60 + n.getMinutes()) / 1440
  }
}

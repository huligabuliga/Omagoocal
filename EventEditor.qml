import QtQuick
import QtQuick.Controls
import Quickshell
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Create, edit and delete, in a card over the calendar rather than a second
// window — the event stays in the context you opened it from.
//
// Times are typed, not spun. "9", "930", "9:30" and "9pm" all land, and the
// Save button stays dead until both ends parse, so a typo can never reach
// Google as a silently wrong timestamp.
Item {
  id: root
  property var panel: null

  readonly property var draft: panel.editing
  readonly property bool isNew: !draft || !draft.id

  // Text lives in the fields themselves. Binding a field's `text` to a
  // property the field also writes back to is the classic QML two-way trap;
  // reading the ids instead keeps one copy of every string.
  property bool allDay: draft ? draft.allDay === true : false
  property string colorId: draft ? String(draft.colorId || "") : ""
  property string calendarKey: draft ? draft.account + "\t" + draft.calendarId : ""

  readonly property var writableCalendars: panel.calendars.filter(function(c) {
    return c.writable && c.enabled
  })

  // The one way into this event's call. An invitation's boilerplate carries
  // half a dozen links on hosts worth recognising; the join link is the one
  // worth a box.
  readonly property var meeting: draft ? Model.primaryMeeting(draft) : null

  // The notes open closed. A card that opens at the height of somebody's
  // invitation boilerplate is a card you scroll past to reach Save.
  property bool notesExpanded: false

  function expandNotes() {
    notesExpanded = true
    notesArea.forceActiveFocus()
    // At the top, which is where the note starts and where the collapsed
    // line left off.
    notesArea.cursorPosition = 0
  }

  // The same rule the chips follow: only a web link is ever handed out.
  function openLink(url) {
    if (Model.isWebLink(url)) Quickshell.execDetached(["/usr/bin/xdg-open", url])
  }

  readonly property var parsedStart: {
    var day = Model.parseDayInput(startDayField.text)
    if (!day) return null
    if (allDay) return day
    var time = Model.parseTimeInput(startTimeField.text)
    return time ? Model.combine(day, time) : null
  }

  readonly property var parsedEnd: {
    var day = Model.parseDayInput(endDayField.text)
    if (!day) return null
    if (allDay) return day
    var time = Model.parseTimeInput(endTimeField.text)
    return time ? Model.combine(day, time) : null
  }

  readonly property string problem: {
    if (!Model.parseDayInput(startDayField.text)) return "Start date must look like 2026-09-10."
    if (!allDay && !Model.parseTimeInput(startTimeField.text)) return "Start time must look like 9:30, 930 or 9pm."
    if (!Model.parseDayInput(endDayField.text)) return "End date must look like 2026-09-10."
    if (!allDay && !Model.parseTimeInput(endTimeField.text)) return "End time must look like 9:30, 930 or 9pm."
    if (parsedEnd < parsedStart) return "The event ends before it starts."
    if (!calendarKey) return "Pick a calendar."
    return ""
  }

  function commit() {
    if (problem !== "") return
    var parts = calendarKey.split("\t")
    var out = {
      id: draft.id,
      account: parts[0],
      calendarId: parts[1],
      title: titleField.text.trim(),
      allDay: allDay,
      startAt: parsedStart,
      endAt: parsedEnd
    }
    // Send only what changed. An untouched description must reach Google
    // byte for byte — the editor round-trips one now, but a note it never
    // loaded, or one Google stores rich text for, is still not ours to
    // rewrite by sending it back.
    if (locationField.text.trim() !== String(draft.location || "")) out.location = locationField.text.trim()
    if (notesArea.text !== String(draft.description || "")) out.description = notesArea.text
    if (colorId !== String(draft.colorId || "")) out.colorId = colorId
    panel.saveEvent(out)
  }

  // Nudging the end along with the start is what everyone means: moving a
  // meeting an hour later does not make it an hour longer.
  function shiftEnd(previousStart) {
    if (!previousStart || !parsedStart || !parsedEnd) return
    if (previousStart.getTime() === parsedStart.getTime()) return
    var span = parsedEnd.getTime() - previousStart.getTime()
    if (span <= 0) return
    setEnd(new Date(parsedStart.getTime() + span))
  }

  function setDuration(minutes) {
    if (!parsedStart) return
    setEnd(new Date(parsedStart.getTime() + minutes * 60000))
  }

  function setEnd(moment) {
    endDayField.text = Model.dayKey(moment)
    endTimeField.text = Model.clockLabel(moment, false)
  }

  // ---- Scrim. Clicking outside is a cancel; the card swallows its own
  //      clicks so a stray press inside never dismisses a half-typed event.
  Rectangle {
    anchors.fill: parent
    color: Util.alpha(Color.popups.background, 0.82)

    MouseArea {
      anchors.fill: parent
      onClicked: root.panel.editing = null
    }
  }

  Rectangle {
    id: card
    anchors.centerIn: parent
    width: Math.min(parent.width - Style.space(80), Style.space(460))
    height: Math.min(parent.height - Style.space(40), form.implicitHeight + Style.space(44))
    color: Color.popups.background
    radius: Style.cornerRadius
    border.width: 1
    border.color: Util.alpha(root.panel.ink, 0.22)

    // The card arrives from slightly below and slightly small. Anything more
    // theatrical gets tiring by the tenth event of the week.
    scale: 0.97
    opacity: 0
    Component.onCompleted: { scale = 1; opacity = 1 }
    Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
    Behavior on opacity { NumberAnimation { duration: 160 } }

    MouseArea { anchors.fill: parent }

    // The chosen colour bleeds along the top edge of the card, so the swatch
    // you picked is visible while you keep typing.
    Rectangle {
      width: parent.width
      height: Style.space(3)
      radius: parent.radius
      color: {
        for (var i = 0; i < Model.EVENT_COLORS.length; i++)
          if (Model.EVENT_COLORS[i].id === root.colorId && Model.EVENT_COLORS[i].hex)
            return Model.EVENT_COLORS[i].hex
        return root.draft ? root.draft.color : Color.accent
      }
      Behavior on color { ColorAnimation { duration: 180 } }
    }

    Flickable {
      anchors.fill: parent
      anchors.margins: Style.space(22)
      contentHeight: form.implicitHeight
      clip: true
      boundsBehavior: Flickable.StopAtBounds
      interactive: contentHeight > height

      Column {
        id: form
        width: parent.width
        spacing: Style.space(12)

        Text {
          text: root.isNew ? "NEW EVENT" : "EDIT EVENT"
          color: root.panel.faint
          font.family: root.panel.mono
          font.pixelSize: Style.font.caption
          font.letterSpacing: 2.0
        }

        TextField {
          id: titleField
          width: parent.width
          text: root.draft ? root.draft.title : ""
          placeholderText: "Title"
          foreground: root.panel.ink
          font.pixelSize: Style.font.title
          Component.onCompleted: { forceActiveFocus(); selectAll() }
          Keys.onEscapePressed: root.panel.editing = null
        }

        Toggle {
          width: parent.width
          label: "All day"
          checked: root.allDay
          foreground: root.panel.ink
          fontFamily: root.panel.mono
          onClicked: root.allDay = !root.allDay
        }

        // ---- When.
        Grid {
          width: parent.width
          columns: 2
          columnSpacing: Style.space(8)
          rowSpacing: Style.space(6)

          Column {
            width: (form.width - Style.space(8)) / 2
            spacing: Style.space(3)

            Text {
              text: "STARTS"
              color: root.panel.faint
              font.family: root.panel.mono
              font.pixelSize: Style.font.caption
              font.letterSpacing: 1.4
            }

            Row {
              spacing: Style.space(5)

              TextField {
                id: startDayField
                width: root.allDay ? (form.width - Style.space(8)) / 2 : Style.space(112)
                text: root.draft ? Model.dayKey(root.draft.startAt) : ""
                foreground: root.panel.ink
                // Snapshot on focus, not as a binding: a binding tracks the
                // value being edited, so it would always agree with the new
                // start and the end would never follow it.
                property var previous: null
                onActiveFocusChanged: if (activeFocus) previous = root.parsedStart
                onEditingFinished: { root.shiftEnd(previous); previous = null }
              }

              TextField {
                id: startTimeField
                visible: !root.allDay
                width: Style.space(62)
                text: root.draft ? Model.clockLabel(root.draft.startAt, false) : ""
                foreground: root.panel.ink
                property var previous: null
                onActiveFocusChanged: if (activeFocus) previous = root.parsedStart
                onEditingFinished: { root.shiftEnd(previous); previous = null }
              }
            }
          }

          Column {
            width: (form.width - Style.space(8)) / 2
            spacing: Style.space(3)

            Text {
              text: "ENDS"
              color: root.panel.faint
              font.family: root.panel.mono
              font.pixelSize: Style.font.caption
              font.letterSpacing: 1.4
            }

            Row {
              spacing: Style.space(5)

              TextField {
                id: endDayField
                width: root.allDay ? (form.width - Style.space(8)) / 2 : Style.space(112)
                // Inclusive: what Google calls the 17th, a person calls the
                // 16th. Saving converts back.
                text: root.draft ? Model.dayKey(Model.inclusiveEndDay(root.draft)) : ""
                foreground: root.panel.ink
              }

              TextField {
                id: endTimeField
                visible: !root.allDay
                width: Style.space(62)
                text: root.draft ? Model.clockLabel(root.draft.endAt, false) : ""
                foreground: root.panel.ink
              }
            }
          }
        }

        // Most events are one of four lengths. Typing an end time is the
        // exception, so the exception is what gets the keyboard.
        Row {
          visible: !root.allDay
          spacing: Style.space(4)

          Repeater {
            model: [{ label: "15m", m: 15 }, { label: "30m", m: 30 },
                    { label: "1h", m: 60 }, { label: "2h", m: 120 }]

            Button {
              required property var modelData
              text: modelData.label
              foreground: root.panel.dim
              accent: Color.accent
              fontFamily: root.panel.mono
              fontSize: Style.font.caption
              bordered: true
              onClicked: root.setDuration(modelData.m)
            }
          }
        }

        // ---- The call, when there is one.
        //
        //      Read-only: the link is Google's, or somebody's paste into the
        //      description, and neither is this card's to rewrite. What it
        //      is here for is the one click that gets you into the meeting —
        //      which used to mean opening the event on the web to find it.
        Column {
          id: callBox
          width: parent.width
          visible: root.meeting !== null
          spacing: Style.space(6)

          PanelSeparator { width: parent.width; foreground: root.panel.ink }

          Text {
            text: "CALL"
            color: root.panel.faint
            font.family: root.panel.mono
            font.pixelSize: Style.font.caption
            font.letterSpacing: 1.4
          }

          Rectangle {
            width: parent.width
            height: Math.max(Style.space(40), rowText.implicitHeight + Style.space(14))
            radius: Style.cornerRadius > 0 ? Style.space(3) : 0
            color: Util.alpha(root.panel.ink, 0.06)
            border.width: 1
            border.color: Util.alpha(root.panel.ink, 0.14)

            Text {
              id: rowGlyph
              anchors.left: parent.left
              anchors.leftMargin: Style.space(9)
              anchors.verticalCenter: parent.verticalCenter
              text: !root.meeting ? ""
                  : root.meeting.kind === "phone" ? "󰏲"
                  : root.meeting.kind === "video" ? "󰕧" : "󰌷"
              color: Color.accent
              font.family: root.panel.mono
              font.pixelSize: Style.font.icon
            }

            Column {
              id: rowText
              anchors.left: rowGlyph.right
              anchors.leftMargin: Style.space(8)
              anchors.right: rowAction.left
              anchors.rightMargin: Style.space(8)
              anchors.verticalCenter: parent.verticalCenter
              spacing: 0

              Text {
                width: parent.width
                text: Model.meetingName(root.meeting)
                textFormat: Text.PlainText
                color: root.panel.ink
                font.family: root.panel.mono
                font.pixelSize: Style.font.bodySmall
                elide: Text.ElideRight
              }

              // Somebody else's URL, drawn as text and never as markup.
              Text {
                width: parent.width
                text: Model.meetingDetail(root.meeting)
                textFormat: Text.PlainText
                color: root.panel.dim
                font.family: root.panel.mono
                font.pixelSize: Style.font.caption
                elide: Text.ElideRight
              }
            }

            // A number cannot be joined, so it is offered as something to
            // paste into whatever you dial with instead.
            Button {
              id: rowAction
              property bool copied: false
              readonly property bool joinable: root.meeting !== null && root.meeting.openable

              anchors.right: parent.right
              anchors.rightMargin: Style.space(6)
              anchors.verticalCenter: parent.verticalCenter
              text: joinable ? "JOIN" : (copied ? "COPIED" : "COPY")
              tooltipText: root.meeting ? root.meeting.uri : ""
              foreground: joinable ? Color.accent : root.panel.dim
              accent: Color.accent
              fontFamily: root.panel.mono
              fontSize: Style.font.caption
              bordered: true
              onClicked: {
                if (!root.meeting) return
                if (joinable) root.openLink(root.meeting.uri)
                else {
                  Quickshell.clipboardText = Model.meetingCopyText(root.meeting)
                  copied = true
                  revert.restart()
                }
              }

              Timer {
                id: revert
                interval: 1400
                onTriggered: rowAction.copied = false
              }
            }
          }
        }

        PanelSeparator { width: parent.width; foreground: root.panel.ink }

        // ---- Which calendar. Multi-account lives here: the list is every
        //      writable calendar across every connected account, labelled by
        //      account when there is more than one.
        Column {
          width: parent.width
          spacing: Style.space(3)

          Text {
            text: "CALENDAR"
            color: root.panel.faint
            font.family: root.panel.mono
            font.pixelSize: Style.font.caption
            font.letterSpacing: 1.4
          }

          Dropdown {
            width: parent.width
            showLabel: false
            fontFamily: root.panel.mono
            value: root.calendarKey
            options: root.writableCalendars.map(function(c) {
              return {
                value: c.account + "\t" + c.id,
                label: c.name + (root.panel.accounts.length > 1 ? "  ·  " + c.account : "")
              }
            })
            onChanged: function(v) { root.calendarKey = v }
          }
        }

        // ---- Colour, straight from Google's own event palette.
        Column {
          width: parent.width
          spacing: Style.space(5)

          Text {
            text: "COLOUR"
            color: root.panel.faint
            font.family: root.panel.mono
            font.pixelSize: Style.font.caption
            font.letterSpacing: 1.4
          }

          Flow {
            width: parent.width
            spacing: Style.space(6)

            Repeater {
              model: Model.EVENT_COLORS

              Rectangle {
                required property var modelData
                readonly property bool picked: root.colorId === modelData.id

                width: Style.space(20)
                height: Style.space(20)
                radius: Style.cornerRadius > 0 ? width / 2 : 0
                color: modelData.hex !== "" ? modelData.hex : "transparent"
                border.width: modelData.hex === "" ? 1 : 0
                border.color: Util.alpha(root.panel.ink, 0.4)
                scale: picked ? 1.0 : (swatch.containsMouse ? 1.08 : 0.82)

                Behavior on scale { NumberAnimation { duration: 130; easing.type: Easing.OutBack } }

                // The selected swatch is the full-size one; a ring around it
                // as well would be two marks saying the same thing.
                Text {
                  anchors.centerIn: parent
                  visible: modelData.hex === ""
                  text: "󰃉"
                  color: Util.alpha(root.panel.ink, 0.55)
                  font.family: root.panel.mono
                  font.pixelSize: Style.font.caption
                }

                MouseArea {
                  id: swatch
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.colorId = modelData.id

                  PanelToolTip {
                    visible: swatch.containsMouse
                    text: modelData.name
                  }
                }
              }
            }
          }
        }

        TextField {
          id: locationField
          width: parent.width
          text: root.draft ? root.draft.location : ""
          placeholderText: "Location"
          foreground: root.panel.ink
        }

        // ---- Notes. One line until you ask for the rest.
        //
        //      A description is a block of text and this was a single-line
        //      input. A single-line input scrolls to its cursor, so what it
        //      showed of a long note was the *end* of it — the last words of
        //      an invitation's footer, never the first words of what the
        //      meeting is. Collapsed it is now a label that starts where the
        //      note starts; expanded it is the whole thing, still editable.
        Column {
          width: parent.width
          spacing: Style.space(3)

          Item {
            width: parent.width
            height: notesLabel.implicitHeight

            Text {
              id: notesLabel
              anchors.left: parent.left
              text: "NOTES"
              color: root.panel.faint
              font.family: root.panel.mono
              font.pixelSize: Style.font.caption
              font.letterSpacing: 1.4
            }

            // Says how much is being kept back, not just that something is.
            Text {
              anchors.right: parent.right
              anchors.verticalCenter: notesLabel.verticalCenter
              readonly property int lines: Model.notesLineCount(notesArea.text)
              text: root.notesExpanded
                ? "COLLAPSE 󰅃"
                : (lines > 1 ? lines + " LINES 󰅀" : "EXPAND 󰅀")
              color: notesToggle.containsMouse ? Color.accent : root.panel.faint
              font.family: root.panel.mono
              font.pixelSize: Style.font.caption
              font.letterSpacing: 1.0

              MouseArea {
                id: notesToggle
                anchors.fill: parent
                anchors.margins: -Style.space(4)
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                  if (root.notesExpanded) root.notesExpanded = false
                  else root.expandNotes()
                }
              }
            }
          }

          // Collapsed: the first words, cut at the right edge rather than
          // scrolled past.
          BorderSurface {
            visible: !root.notesExpanded
            width: parent.width
            height: Style.space(30)
            radius: Style.cornerRadius
            color: Style.controlFill(false, notesPreview.containsMouse, root.panel.ink, Color.accent)
            borderSpec: Border.controlSpec(notesPreview.containsMouse ? "hover-cursor" : "normal",
                                           root.panel.ink, Color.accent)

            Text {
              anchors.fill: parent
              anchors.leftMargin: Style.spacing.controlPaddingX
              anchors.rightMargin: Style.spacing.controlPaddingX
              verticalAlignment: Text.AlignVCenter
              text: Model.notesPreview(notesArea.text) || "Notes"
              textFormat: Text.PlainText
              color: notesArea.text === "" ? Qt.darker(root.panel.ink, 1.6) : root.panel.ink
              font.family: Style.font.family
              font.pixelSize: Style.font.body
              elide: Text.ElideRight
            }

            MouseArea {
              id: notesPreview
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.IBeamCursor
              onClicked: root.expandNotes()
            }
          }

          // Expanded: the whole note. It stays loaded while collapsed, so a
          // paragraph typed and then folded away is still there to save.
          BorderSurface {
            visible: root.notesExpanded
            width: parent.width
            height: Style.space(150)
            radius: Style.cornerRadius
            color: Style.controlFill(notesArea.activeFocus, notesArea.hovered,
                                     root.panel.ink, Color.accent)
            borderSpec: Border.controlSpec(notesArea.activeFocus ? "focus"
                                             : (notesArea.hovered ? "hover-cursor" : "normal"),
                                           root.panel.ink, Color.accent)

            Flickable {
              anchors.fill: parent
              anchors.margins: Style.space(2)
              clip: true
              boundsBehavior: Flickable.StopAtBounds

              TextArea.flickable: TextArea {
                id: notesArea
                text: root.draft ? root.draft.description : ""
                placeholderText: "Notes"
                wrapMode: TextEdit.Wrap
                // Somebody else's text in an editable field is still
                // somebody else's text: never parsed as markup.
                textFormat: TextEdit.PlainText
                color: root.panel.ink
                placeholderTextColor: Qt.darker(root.panel.ink, 1.6)
                selectionColor: Style.selectionFillFor(root.panel.ink, Color.accent)
                selectedTextColor: root.panel.ink
                font.family: Style.font.family
                font.pixelSize: Style.font.body
                leftPadding: Style.spacing.controlPaddingX
                rightPadding: Style.spacing.controlPaddingX
                topPadding: Style.spacing.inputPaddingY
                bottomPadding: Style.spacing.inputPaddingY
                background: null
                Keys.onEscapePressed: root.panel.editing = null
              }

              ScrollBar.vertical: ScrollBar { }
            }
          }
        }

        Text {
          width: parent.width
          visible: root.problem !== "" && titleField.text !== ""
          text: root.problem
          color: Color.urgent
          wrapMode: Text.Wrap
          font.family: root.panel.mono
          font.pixelSize: Style.font.caption
        }

        PanelSeparator { width: parent.width; foreground: root.panel.ink }

        Item {
          width: parent.width
          height: actions.implicitHeight

          Button {
            anchors.left: parent.left
            visible: !root.isNew
            text: "DELETE"
            foreground: Color.urgent
            accent: Color.urgent
            fontFamily: root.panel.mono
            fontSize: Style.font.caption
            bordered: true
            onClicked: confirmDelete.opened = true
          }

          Row {
            id: actions
            anchors.right: parent.right
            spacing: Style.space(6)

            Button {
              text: "CANCEL"
              foreground: root.panel.dim
              fontFamily: root.panel.mono
              fontSize: Style.font.caption
              onClicked: root.panel.editing = null
            }

            Button {
              text: root.isNew ? "CREATE" : "SAVE"
              enabled: root.problem === ""
              opacity: enabled ? 1 : 0.4
              foreground: Color.accent
              accent: Color.accent
              fontFamily: root.panel.mono
              fontSize: Style.font.caption
              bordered: true
              onClicked: root.commit()
            }
          }
        }

        Item { width: 1; height: Style.space(2) }
      }
    }
  }

  ConfirmDialog {
    id: confirmDelete
    anchors.fill: parent
    z: 10
    message: root.draft && String(root.draft.title).trim() !== ""
      ? "Delete \"" + root.draft.title + "\"?"
      : "Delete this event?"
    confirmText: "Delete"
    cancelText: "Keep"
    fontFamily: root.panel.mono
    foreground: root.panel.ink
    onConfirmed: {
      confirmDelete.opened = false
      root.panel.deleteEvent(root.draft)
    }
    onCanceled: confirmDelete.opened = false
  }

  // Esc anywhere in the card cancels; Ctrl+Enter saves from any field.
  Keys.onEscapePressed: {
    if (confirmDelete.opened) confirmDelete.opened = false
    else root.panel.editing = null
  }
  focus: true

  Shortcut {
    sequences: ["Ctrl+Return", "Ctrl+Enter"]
    onActivated: root.commit()
  }
}

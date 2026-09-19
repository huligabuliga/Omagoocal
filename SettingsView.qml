import QtQuick
import Quickshell
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Settings, and the front door.
//
// Until an account is connected this is the whole plugin, so it opens with
// the one thing that matters — a button that starts the Google sign-in — and
// keeps the credential setup underneath it, folded away once it is done.
//
// Google has no client id to give a desktop app on someone else's machine,
// so the OAuth client is the user's own. That is the honest version of this
// screen: four steps, a link that opens the right console page, and two
// fields.
Flickable {
  id: root
  property var panel: null

  contentHeight: column.implicitHeight
  clip: true
  boundsBehavior: Flickable.StopAtBounds
  interactive: contentHeight > height

  readonly property var byAccount: {
    var map = {}
    for (var i = 0; i < panel.calendars.length; i++) {
      var cal = panel.calendars[i]
      if (cal.error) continue
      if (!map[cal.account]) map[cal.account] = []
      map[cal.account].push(cal)
    }
    return map
  }

  Column {
    id: column
    width: root.width - Style.space(4)
    spacing: Style.space(18)

    // ---------------------------------------------------------- front door
    //
    // Three states, one place: packages missing, ready to sign in, or
    // already connected. Until an account exists this is the entire panel,
    // so it is built as a centred hero rather than a form.
    Item {
      width: parent.width
      height: root.panel.connected ? addRow.implicitHeight : hero.implicitHeight + Style.space(40)
      visible: !root.panel.depsChecking

      // ---- Connected: one quiet line, because the account list is next.
      Button {
        id: addRow
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        visible: root.panel.connected
        iconText: "󰐕"
        text: "ADD ANOTHER GOOGLE ACCOUNT"
        foreground: root.panel.dim
        accent: Color.accent
        fontFamily: root.panel.mono
        fontSize: Style.font.caption
        horizontalPadding: 0
        onClicked: root.panel.login()
      }

      // ---- Not connected: the hero.
      Column {
        id: hero
        anchors.centerIn: parent
        visible: !root.panel.connected
        width: Math.min(parent.width, Style.space(440))
        spacing: Style.space(14)

        readonly property bool needsPackages: !root.panel.depsInstalled

        // The mark: a calendar glyph wearing a small Google badge, so the
        // screen says what this is before a word is read.
        Item {
          anchors.horizontalCenter: parent.horizontalCenter
          width: Style.space(72)
          height: Style.space(64)

          Text {
            id: heroGlyph
            anchors.centerIn: parent
            text: "󰃭"
            color: root.panel.ink
            font.family: root.panel.mono
            font.pixelSize: Style.font.display + Style.space(14)
            opacity: 0.9
          }

          Text {
            anchors.right: heroGlyph.right
            anchors.bottom: heroGlyph.bottom
            anchors.rightMargin: -Style.space(4)
            anchors.bottomMargin: -Style.space(2)
            text: hero.needsPackages ? "󰏔" : "󰊭"
            color: Color.accent
            font.family: root.panel.mono
            font.pixelSize: Style.font.title
            font.bold: true
          }
        }

        Text {
          width: parent.width
          text: hero.needsPackages ? "Two packages first" : "Sign in with Google"
          color: root.panel.ink
          horizontalAlignment: Text.AlignHCenter
          font.family: root.panel.mono
          font.pixelSize: Style.font.heading
          font.bold: true
          font.letterSpacing: -0.4
        }

        Text {
          width: parent.width
          text: hero.needsPackages
            ? "GNOME Online Accounts brokers the Google sign-in. Omarchy installs it in a terminal window — that is also where it asks for your password."
            : "Google's own sign-in window opens. Nothing to create in Google Cloud, no API keys, no client ID."
          color: root.panel.dim
          horizontalAlignment: Text.AlignHCenter
          wrapMode: Text.WordWrap
          font.family: root.panel.mono
          font.pixelSize: Style.font.bodySmall
        }

        // What is about to be installed, named. A button that installs
        // unnamed things is a button people do not press.
        Column {
          anchors.horizontalCenter: parent.horizontalCenter
          visible: hero.needsPackages
          spacing: Style.space(2)

          Repeater {
            model: root.panel.requiredPackages

            Text {
              required property var modelData
              text: "󰏖  " + modelData
              color: root.panel.faint
              font.family: root.panel.mono
              font.pixelSize: Style.font.caption
            }
          }
        }

        // ---- The button the whole plugin hangs off.
        Button {
          anchors.horizontalCenter: parent.horizontalCenter
          enabled: !root.panel.installing
          opacity: enabled ? 1 : 0.6
          iconText: root.panel.installing ? "󰑐" : (hero.needsPackages ? "󰏔" : "󰊭")
          iconSpinning: root.panel.installing
          iconSize: Style.font.iconLarge
          text: root.panel.installing ? "INSTALLING…"
              : (hero.needsPackages ? "INSTALL DEPENDENCIES" : "SIGN IN WITH GOOGLE")
          bordered: true
          background: Util.alpha(Color.accent, 0.14)
          foreground: root.panel.ink
          accent: Color.accent
          fontFamily: root.panel.mono
          fontSize: Style.font.bodySmall
          horizontalPadding: Style.space(22)
          verticalPadding: Style.space(12)
          onClicked: hero.needsPackages ? root.panel.installDeps() : root.panel.login()
        }

        Text {
          width: parent.width
          visible: root.panel.installError !== ""
          text: root.panel.installError
          color: Color.urgent
          horizontalAlignment: Text.AlignHCenter
          wrapMode: Text.WordWrap
          font.family: root.panel.mono
          font.pixelSize: Style.font.caption
        }

        Text {
          width: parent.width
          visible: !hero.needsPackages
          text: "Handled by GNOME Online Accounts — the same stack GNOME Calendar uses."
          color: root.panel.faint
          horizontalAlignment: Text.AlignHCenter
          wrapMode: Text.WordWrap
          font.family: root.panel.mono
          font.pixelSize: Style.font.caption
        }
      }
    }

    // ----------------------------------------------------------- accounts
    Column {
      width: parent.width
      spacing: Style.space(8)
      visible: root.panel.accounts.length > 0

      Text {
        text: "ACCOUNTS"
        color: root.panel.faint
        font.family: root.panel.mono
        font.pixelSize: Style.font.caption
        font.letterSpacing: 2.0
      }

      Repeater {
        model: root.panel.accounts

        Item {
          required property var modelData
          width: column.width
          height: Style.space(30)

          Row {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(8)

            Text {
              anchors.verticalCenter: parent.verticalCenter
              text: "󰊭"
              color: Color.accent
              font.family: root.panel.mono
              font.pixelSize: Style.font.body
            }

            Text {
              anchors.verticalCenter: parent.verticalCenter
              text: modelData
              textFormat: Text.PlainText
              color: root.panel.ink
              font.family: root.panel.mono
              font.pixelSize: Style.font.bodySmall
            }

            Text {
              anchors.verticalCenter: parent.verticalCenter
              text: (root.byAccount[modelData] || []).length + " calendars"
              color: root.panel.faint
              font.family: root.panel.mono
              font.pixelSize: Style.font.caption
            }
          }

          // Not a sign-out button: the credential belongs to GNOME Online
          // Accounts, so this opens the window that owns it. The ellipsis
          // says so, and the tooltip says it plainly.
          Button {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: "MANAGE…"
            tooltipText: "Opens GNOME Online Accounts, where this account is stored"
            foreground: root.panel.dim
            accent: Color.accent
            fontFamily: root.panel.mono
            fontSize: Style.font.caption
            onClicked: root.panel.login()
          }

          Rectangle {
            anchors.bottom: parent.bottom
            width: parent.width
            height: 1
            color: root.panel.hair
          }
        }
      }
    }

    // ---------------------------------------------------------- calendars
    Column {
      width: parent.width
      spacing: Style.space(8)
      visible: root.panel.calendars.length > 0

      Text {
        text: "CALENDARS"
        color: root.panel.faint
        font.family: root.panel.mono
        font.pixelSize: Style.font.caption
        font.letterSpacing: 2.0
      }

      // Grouped by account. With a dozen calendars across two accounts, the
      // account belongs in a heading once, not repeated down the right edge
      // of every single row.
      Repeater {
        model: root.panel.accounts

        Column {
          required property var modelData
          width: column.width
          spacing: Style.space(2)

          Text {
            visible: root.panel.accounts.length > 1
            topPadding: Style.space(8)
            text: modelData
            textFormat: Text.PlainText
            color: root.panel.faint
            font.family: root.panel.mono
            font.pixelSize: Style.font.caption
          }

          Repeater {
            model: root.byAccount[modelData] || []

            Item {
              id: calRow
              required property var modelData
              readonly property bool on: root.panel.calendarEnabled(modelData)

              width: column.width
              // A comfortable row, and the whole of it is the hit target —
              // hunting for a 20px switch is not a thing anyone should do.
              height: Style.space(32)

              Rectangle {
                anchors.fill: parent
                anchors.leftMargin: -Style.space(6)
                anchors.rightMargin: -Style.space(6)
                radius: Style.cornerRadius
                color: rowMouse.containsMouse ? Util.alpha(root.panel.ink, 0.05) : "transparent"
                Behavior on color { ColorAnimation { duration: 120 } }
              }

              MouseArea {
                id: rowMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.panel.toggleCalendar(calRow.modelData)
              }

              Rectangle {
                id: swatch
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                width: Style.space(10)
                height: Style.space(10)
                radius: Style.cornerRadius > 0 ? width / 2 : 0
                color: calRow.modelData.color
                // Disabled sits at 0.4, not 0.3: below that a colour swatch
                // stops reading as a colour at all.
                opacity: calRow.on ? 1 : 0.4
                Behavior on opacity { NumberAnimation { duration: 140 } }
              }

              Text {
                anchors.left: swatch.right
                anchors.leftMargin: Style.space(10)
                anchors.right: calQualifier.left
                anchors.rightMargin: Style.space(10)
                anchors.verticalCenter: parent.verticalCenter
                text: calRow.modelData.name
                textFormat: Text.PlainText
                color: calRow.on ? root.panel.ink : root.panel.faint
                elide: Text.ElideRight
                font.family: root.panel.mono
                font.pixelSize: Style.font.bodySmall
                Behavior on color { ColorAnimation { duration: 140 } }
              }

              Text {
                id: calQualifier
                anchors.right: calSwitch.left
                anchors.rightMargin: Style.space(12)
                anchors.verticalCenter: parent.verticalCenter
                text: calRow.modelData.writable ? "" : "read-only"
                color: root.panel.faint
                font.family: root.panel.mono
                font.pixelSize: Style.font.caption
              }

              ToggleSwitch {
                id: calSwitch
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                checked: calRow.on
                hasCursor: rowMouse.containsMouse
                foreground: root.panel.ink
                accent: Color.accent
                onToggled: root.panel.toggleCalendar(calRow.modelData)
              }
            }
          }
        }
      }
    }

    // -------------------------------------------------------- preferences
    Column {
      width: parent.width
      spacing: Style.space(10)

      Text {
        text: "PREFERENCES"
        color: root.panel.faint
        font.family: root.panel.mono
        font.pixelSize: Style.font.caption
        font.letterSpacing: 2.0
      }

      Grid {
        width: parent.width
        columns: 2
        columnSpacing: Style.space(16)
        rowSpacing: Style.space(10)

        Repeater {
          model: [
            { key: "notifyMinutes", label: "Notify before events",
              options: [{ value: 0, label: "Off" }, { value: 5, label: "5 minutes" },
                        { value: 10, label: "10 minutes" }, { value: 15, label: "15 minutes" },
                        { value: 30, label: "30 minutes" }, { value: 60, label: "1 hour" }] },
            { key: "defaultView", label: "Open on",
              options: [{ value: "day", label: "Day" }, { value: "week", label: "Week" },
                        { value: "month", label: "Month" }] },
            { key: "weekStart", label: "Week starts",
              options: [{ value: 1, label: "Monday" }, { value: 0, label: "Sunday" },
                        { value: 6, label: "Saturday" }] },
            { key: "hours12", label: "Clock",
              options: [{ value: false, label: "24 hour" }, { value: true, label: "12 hour" }] },
            { key: "eventTimes", label: "Event times",
              options: [{ value: "auto", label: "When they fit" },
                        { value: "always", label: "Always" }] },
            { key: "dayStartHour", label: "Grid opens at",
              options: [{ value: 0, label: "Midnight" }, { value: 6, label: "06:00" },
                        { value: 7, label: "07:00" }, { value: 8, label: "08:00" },
                        { value: 9, label: "09:00" }] },
            { key: "refreshMinutes", label: "Refresh every",
              options: [{ value: 1, label: "1 minute" }, { value: 5, label: "5 minutes" },
                        { value: 15, label: "15 minutes" }, { value: 30, label: "30 minutes" }] },
            { key: "snapshot", label: "Keep last sync on disk (instant open)",
              options: [{ value: true, label: "Yes" }, { value: false, label: "No — fetch every time" }] }
          ]

          Column {
            required property var modelData
            width: (column.width - Style.space(16)) / 2
            spacing: Style.space(3)

            Text {
              text: modelData.label
              color: root.panel.dim
              font.family: root.panel.mono
              font.pixelSize: Style.font.caption
            }

            Dropdown {
              width: parent.width
              showLabel: false
              fontFamily: root.panel.mono
              // Dropdown speaks strings; the config keeps real numbers and
              // booleans, so the conversion happens at this seam only.
              value: String(root.panel.cfg[modelData.key])
              options: modelData.options.map(function(o) {
                return { value: String(o.value), label: o.label }
              })
              onChanged: function(v) {
                for (var i = 0; i < modelData.options.length; i++)
                  if (String(modelData.options[i].value) === v)
                    root.panel.setConfig(modelData.key, modelData.options[i].value)
              }
            }
          }
        }
      }
    }

    Item { width: 1; height: Style.space(6) }
  }
}

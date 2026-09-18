import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

Item {
  id: root

  property var backend: null
  property color foreground: Color.foreground
  property color background: Color.background
  property color accent: Color.accent
  property color urgent: Color.urgent
  property color dim: Qt.darker(foreground, 1.55)
  property string fontFamily: Style.font.family

  // Selected provider: null shows the provider list
  property var selectedProvider: null

  // Form inputs
  property string remoteName: ""
  property string mountPath: ""
  property bool mountImmediate: true
  property bool showPassword: false
  property bool showAdvancedOAuth: false
  property string s3Preset: "AWS"

  signal accountAdded(string remoteName)
  signal cancelled()

  implicitWidth: parent ? parent.width : Style.space(380)
  implicitHeight: mainCol.implicitHeight

  function selectProvider(provId) {
    if (!provId || provId === "") {
      root.selectedProvider = null
      return
    }
    var p = Model.getProvider(provId)
    root.selectedProvider = p
    root.suggestName(p)
    if (root.backend) {
      root.backend.authError = ""
      root.backend.authSuccess = false
    }
  }

  function suggestName(provider) {
    if (!provider) return
    var base = provider.defaultName || provider.name.replace(/[^a-zA-Z0-9]/g, "")
    var name = base
    var counter = 2
    if (root.backend && root.backend.drives) {
      var existing = {}
      for (var i = 0; i < root.backend.drives.length; i++) {
        existing[root.backend.drives[i].name] = true
      }
      while (existing[name]) {
        name = base + "_" + counter
        counter++
      }
    }
    root.remoteName = name
    root.mountPath = (root.backend ? root.backend.mountRoot : "~/Cloud") + "/" + name
  }

  Connections {
    target: root.backend
    function onAccountCreated(name) {
      successTimer.restart()
    }
  }

  Timer {
    id: successTimer
    interval: 1200
    repeat: false
    onTriggered: {
      root.accountAdded(root.remoteName)
      root.selectedProvider = null
    }
  }

  ColumnLayout {
    id: mainCol
    width: parent.width
    spacing: Style.space(10)

    // ========================================================================
    // HEADER BAR
    // ========================================================================
    RowLayout {
      Layout.fillWidth: true
      spacing: Style.space(8)

      Button {
        iconText: "󰁝"
        text: root.selectedProvider ? "Providers" : "Close"
        fontFamily: root.fontFamily
        fontSize: Style.font.caption
        foreground: root.foreground
        bordered: true
        onClicked: {
          if (root.backend && root.backend.authWaiting) {
            root.backend.cancelAuth()
          }
          if (root.selectedProvider) {
            root.selectedProvider = null
          } else {
            root.cancelled()
          }
        }
      }

      Text {
        Layout.fillWidth: true
        text: root.selectedProvider ? (root.selectedProvider.name + " Setup") : "Connect Cloud Drive"
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        font.bold: true
        color: root.foreground
        elide: Text.ElideRight
      }

      if (root.selectedProvider) {
        Text {
          text: root.selectedProvider.glyph || "󰅟"
          color: root.selectedProvider.color || Color.accent
          font.family: root.fontFamily
          font.pixelSize: Style.font.heading
        }
      }
    }

    // Success Banner
    BorderSurface {
      visible: root.backend && root.backend.authSuccess
      Layout.fillWidth: true
      implicitHeight: successRow.implicitHeight + Style.space(16)
      radius: Style.cornerRadius
      color: Qt.rgba(0.1, 0.6, 0.2, 0.15)
      borderSpec: Border.controlSpec("normal", Color.accent, Color.accent)

      RowLayout {
        id: successRow
        anchors {
          fill: parent
          margins: Style.space(8)
        }
        spacing: Style.space(8)

        Text {
          text: "󰄬"
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          color: Color.accent
        }

        Text {
          Layout.fillWidth: true
          text: root.backend ? root.backend.authSuccessMessage : "Drive connected successfully!"
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          font.bold: true
          color: root.foreground
        }
      }
    }

    // Error Banner
    BorderSurface {
      visible: root.backend && root.backend.authError !== ""
      Layout.fillWidth: true
      implicitHeight: errorRow.implicitHeight + Style.space(16)
      radius: Style.cornerRadius
      color: Qt.rgba(0.8, 0.1, 0.1, 0.15)
      borderSpec: Border.controlSpec("normal", root.urgent, root.urgent)

      RowLayout {
        id: errorRow
        anchors {
          fill: parent
          margins: Style.space(8)
        }
        spacing: Style.space(8)

        Text {
          text: "󰅚"
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          color: root.urgent
        }

        Text {
          Layout.fillWidth: true
          text: root.backend ? root.backend.authError : ""
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption - Style.space(1)
          color: root.foreground
          wrapMode: Text.WordWrap
        }

        PanelActionButton {
          iconText: "󰅖"
          tooltipText: "Dismiss"
          foreground: root.foreground
          hoverColor: root.urgent
          onClicked: {
            if (root.backend) root.backend.authError = ""
          }
        }
      }
    }

    // ========================================================================
    // VIEW 1: PROVIDER SELECTION LIST
    // ========================================================================
    ColumnLayout {
      visible: root.selectedProvider === null
      Layout.fillWidth: true
      spacing: Style.space(4)

      Text {
        text: "Select a Cloud Service:"
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        color: root.dim
      }

      Repeater {
        model: Model.ALL_PROVIDERS

        CursorSurface {
          id: provRow
          property var prov: modelData
          Layout.fillWidth: true
          implicitHeight: Style.space(46)
          radius: Style.cornerRadius
          hasCursor: provMouse.containsMouse

          MouseArea {
            id: provMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.selectProvider(prov.id)
          }

          RowLayout {
            anchors {
              fill: parent
              leftMargin: Style.space(8)
              rightMargin: Style.space(8)
            }
            spacing: Style.space(10)

            // Provider Icon
            Rectangle {
              implicitWidth: Style.space(30)
              implicitHeight: Style.space(30)
              radius: Style.cornerRadius
              color: prov.color ? Qt.alpha(prov.color, 0.15) : Qt.rgba(1, 1, 1, 0.08)

              Text {
                anchors.centerIn: parent
                text: prov.glyph || "󰅟"
                color: prov.color || root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.icon
              }
            }

            // Name & Category
            Column {
              Layout.fillWidth: true
              spacing: 0

              Text {
                text: prov.name
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                font.bold: true
                color: root.foreground
                elide: Text.ElideRight
                width: parent.width
              }

              Text {
                text: prov.authTag + " • " + prov.category
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption - Style.space(2)
                color: root.dim
              }
            }

            Text {
              text: "󰅂"
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              color: provMouse.containsMouse ? Color.accent : root.dim
            }
          }
        }
      }
    }

    // ========================================================================
    // VIEW 2: PROVIDER CONFIGURATION FORM
    // ========================================================================
    ColumnLayout {
      visible: root.selectedProvider !== null
      Layout.fillWidth: true
      spacing: Style.space(10)

      // Section 1: Name & Mount Location
      BorderSurface {
        Layout.fillWidth: true
        implicitHeight: idCol.implicitHeight + Style.space(16)
        radius: Style.cornerRadius
        color: Qt.rgba(1, 1, 1, 0.03)
        borderSpec: Border.controlSpec("normal", root.foreground, Color.accent)

        ColumnLayout {
          id: idCol
          anchors {
            fill: parent
            margins: Style.space(10)
          }
          spacing: Style.space(8)

          // Remote Name
          ColumnLayout {
            Layout.fillWidth: true
            spacing: Style.space(2)

            Text {
              text: "Drive Name:"
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
              color: root.foreground
            }

            TextField {
              id: nameInputField
              Layout.fillWidth: true
              text: root.remoteName
              placeholderText: "e.g. MyDrive"
              onTextChanged: {
                root.remoteName = text
                if (!mountPathInputField.activeFocus) {
                  root.mountPath = (root.backend ? root.backend.mountRoot : "~/Cloud") + "/" + text
                }
              }
            }
          }

          // Custom Mount Location
          ColumnLayout {
            Layout.fillWidth: true
            spacing: Style.space(2)

            Text {
              text: "Mount Directory:"
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
              color: root.foreground
            }

            TextField {
              id: mountPathInputField
              Layout.fillWidth: true
              text: root.mountPath
              placeholderText: "~/Cloud/" + root.remoteName
              onTextChanged: { root.mountPath = text }
            }

            Text {
              text: "Folder path on your computer where files will be attached"
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption - Style.space(2)
              color: root.dim
            }
          }

          // Auto-mount switch
          RowLayout {
            Layout.fillWidth: true
            spacing: Style.space(8)

            Text {
              Layout.fillWidth: true
              text: "Mount immediately upon connection"
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              color: root.foreground
            }

            ToggleSwitch {
              checked: root.mountImmediate
              foreground: root.foreground
              onToggled: { root.mountImmediate = !root.mountImmediate }
            }
          }
        }
      }

      // Section 2: Authentication

      // A. OAuth Provider
      ColumnLayout {
        visible: root.selectedProvider && root.selectedProvider.authType === "oauth"
        Layout.fillWidth: true
        spacing: Style.space(8)

        // Waiting Card
        BorderSurface {
          visible: root.backend && root.backend.authWaiting
          Layout.fillWidth: true
          implicitHeight: waitCol.implicitHeight + Style.space(20)
          radius: Style.cornerRadius
          color: Qt.alpha(Color.accent, 0.1)
          borderSpec: Border.controlSpec("focus", root.foreground, Color.accent)

          ColumnLayout {
            id: waitCol
            anchors {
              fill: parent
              margins: Style.space(10)
            }
            spacing: Style.space(8)

            RowLayout {
              Layout.fillWidth: true
              spacing: Style.space(10)

              Text {
                text: "󰑐"
                font.family: root.fontFamily
                font.pixelSize: Style.font.heading
                color: Color.accent
                RotationAnimator on rotation {
                  running: root.backend && root.backend.authWaiting
                  from: 0
                  to: 360
                  loops: Animation.Infinite
                  duration: 1800
                }
              }

              Column {
                Layout.fillWidth: true
                spacing: Style.space(1)

                Text {
                  text: "Waiting for Browser Sign-in…"
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  font.bold: true
                  color: root.foreground
                }

                Text {
                  text: "Complete login in your web browser. ODrive will detect completion automatically."
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption - Style.space(1)
                  color: root.foreground
                  wrapMode: Text.WordWrap
                  width: parent.width
                }
              }
            }

            Button {
              Layout.alignment: Qt.AlignRight
              text: "Cancel Authorization"
              fontFamily: root.fontFamily
              fontSize: Style.font.caption
              foreground: root.urgent
              bordered: true
              onClicked: {
                if (root.backend) root.backend.cancelAuth()
              }
            }
          }
        }

        // Ready to authorize
        ColumnLayout {
          visible: !(root.backend && root.backend.authWaiting)
          Layout.fillWidth: true
          spacing: Style.space(8)

          Text {
            Layout.fillWidth: true
            text: "Clicking Authorize opens your web browser to securely sign in with " + (root.selectedProvider ? root.selectedProvider.name : "") + ". No passwords are stored locally."
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            color: root.dim
            wrapMode: Text.WordWrap
          }

          Button {
            Layout.fillWidth: true
            implicitHeight: Style.space(38)
            text: "Authorize in Browser"
            iconText: root.selectedProvider ? root.selectedProvider.glyph : "󰊭"
            fontFamily: root.fontFamily
            fontBold: true
            foreground: root.foreground
            bordered: true
            onClicked: {
              if (root.backend) {
                root.backend.addOAuth(
                  root.remoteName.trim(),
                  root.selectedProvider.id,
                  "",
                  "",
                  root.mountPath.trim(),
                  root.mountImmediate
                )
              }
            }
          }
        }
      }

      // B. Nextcloud / ownCloud
      ColumnLayout {
        visible: root.selectedProvider && root.selectedProvider.id === "nextcloud"
        Layout.fillWidth: true
        spacing: Style.space(8)

        ColumnLayout {
          Layout.fillWidth: true
          spacing: Style.space(2)

          Text {
            text: "Server Address:"
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
            color: root.foreground
          }

          TextField {
            id: ncUrlField
            Layout.fillWidth: true
            placeholderText: "https://cloud.example.com"
          }
        }

        ColumnLayout {
          Layout.fillWidth: true
          spacing: Style.space(2)

          Text {
            text: "Username:"
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
            color: root.foreground
          }

          TextField {
            id: ncUserField
            Layout.fillWidth: true
            placeholderText: "username"
          }
        }

        ColumnLayout {
          Layout.fillWidth: true
          spacing: Style.space(2)

          RowLayout {
            Layout.fillWidth: true
            Text {
              text: "App Password:"
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
              color: root.foreground
            }
            Item { Layout.fillWidth: true }
            Button {
              text: root.showPassword ? "Hide" : "Show"
              fontFamily: root.fontFamily
              fontSize: Style.font.caption - Style.space(2)
              foreground: root.dim
              bordered: false
              onClicked: { root.showPassword = !root.showPassword }
            }
          }

          TextField {
            id: ncPassField
            Layout.fillWidth: true
            placeholderText: "Password or App Token"
            password: !root.showPassword
          }
        }

        Button {
          Layout.fillWidth: true
          implicitHeight: Style.space(38)
          text: (root.backend && root.backend.authBusy) ? "Connecting…" : "Connect & Mount Nextcloud"
          iconText: "󰒋"
          fontFamily: root.fontFamily
          fontBold: true
          foreground: root.foreground
          bordered: true
          onClicked: {
            if (root.backend) {
              root.backend.addCredentials(
                root.remoteName.trim(),
                "nextcloud",
                {
                  url: ncUrlField.text.trim(),
                  user: ncUserField.text.trim(),
                  pass: ncPassField.text.trim()
                },
                root.mountPath.trim(),
                root.mountImmediate
              )
            }
          }
        }
      }

      // C. Generic WebDAV
      ColumnLayout {
        visible: root.selectedProvider && root.selectedProvider.id === "webdav"
        Layout.fillWidth: true
        spacing: Style.space(8)

        ColumnLayout {
          Layout.fillWidth: true
          spacing: Style.space(2)
          Text { text: "WebDAV URL:"; font.family: root.fontFamily; font.pixelSize: Style.font.caption; font.bold: true; color: root.foreground }
          TextField { id: wdUrlField; Layout.fillWidth: true; placeholderText: "https://dav.example.com/remote.php/webdav" }
        }

        ColumnLayout {
          Layout.fillWidth: true
          spacing: Style.space(2)
          Text { text: "Username:"; font.family: root.fontFamily; font.pixelSize: Style.font.caption; font.bold: true; color: root.foreground }
          TextField { id: wdUserField; Layout.fillWidth: true; placeholderText: "username" }
        }

        ColumnLayout {
          Layout.fillWidth: true
          spacing: Style.space(2)
          Text { text: "Password:"; font.family: root.fontFamily; font.pixelSize: Style.font.caption; font.bold: true; color: root.foreground }
          TextField { id: wdPassField; Layout.fillWidth: true; placeholderText: "Password"; password: !root.showPassword }
        }

        Button {
          Layout.fillWidth: true
          implicitHeight: Style.space(38)
          text: (root.backend && root.backend.authBusy) ? "Connecting…" : "Connect & Mount WebDAV"
          iconText: "󰒋"
          fontFamily: root.fontFamily
          fontBold: true
          foreground: root.foreground
          bordered: true
          onClicked: {
            if (root.backend) {
              root.backend.addCredentials(
                root.remoteName.trim(),
                "webdav",
                {
                  url: wdUrlField.text.trim(),
                  user: wdUserField.text.trim(),
                  pass: wdPassField.text.trim(),
                  vendor: "other"
                },
                root.mountPath.trim(),
                root.mountImmediate
              )
            }
          }
        }
      }

      // D. Amazon S3 / MinIO
      ColumnLayout {
        visible: root.selectedProvider && root.selectedProvider.id === "s3"
        Layout.fillWidth: true
        spacing: Style.space(8)

        RowLayout {
          Layout.fillWidth: true
          spacing: Style.space(4)
          Repeater {
            model: ["AWS", "Minio", "Cloudflare", "Other"]
            Button {
              text: modelData === "Minio" ? "MinIO" : (modelData === "Cloudflare" ? "R2" : modelData)
              fontFamily: root.fontFamily
              fontSize: Style.font.caption
              selected: root.s3Preset === modelData
              foreground: root.foreground
              bordered: true
              onClicked: {
                root.s3Preset = modelData
                if (modelData === "Minio" && s3EndpointField.text === "") s3EndpointField.text = "http://127.0.0.1:9000"
                else if (modelData === "Cloudflare" && s3EndpointField.text === "") s3EndpointField.text = "https://<accountid>.r2.cloudflarestorage.com"
              }
            }
          }
        }

        ColumnLayout {
          Layout.fillWidth: true
          spacing: Style.space(2)
          Text { text: "Endpoint URL (optional):"; font.family: root.fontFamily; font.pixelSize: Style.font.caption; color: root.foreground }
          TextField { id: s3EndpointField; Layout.fillWidth: true; placeholderText: root.s3Preset === "AWS" ? "Default AWS" : "https://minio.lan:9000" }
        }

        ColumnLayout {
          Layout.fillWidth: true
          spacing: Style.space(2)
          Text { text: "Access Key ID:"; font.family: root.fontFamily; font.pixelSize: Style.font.caption; font.bold: true; color: root.foreground }
          TextField { id: s3AccessKeyField; Layout.fillWidth: true; placeholderText: "Access Key" }
        }

        ColumnLayout {
          Layout.fillWidth: true
          spacing: Style.space(2)
          Text { text: "Secret Access Key:"; font.family: root.fontFamily; font.pixelSize: Style.font.caption; font.bold: true; color: root.foreground }
          TextField { id: s3SecretKeyField; Layout.fillWidth: true; placeholderText: "Secret Key"; password: !root.showPassword }
        }

        Button {
          Layout.fillWidth: true
          implicitHeight: Style.space(38)
          text: (root.backend && root.backend.authBusy) ? "Connecting…" : "Connect & Mount S3 Storage"
          iconText: "󰋊"
          fontFamily: root.fontFamily
          fontBold: true
          foreground: root.foreground
          bordered: true
          onClicked: {
            if (root.backend) {
              root.backend.addCredentials(
                root.remoteName.trim(),
                "s3",
                {
                  provider: root.s3Preset,
                  endpoint: s3EndpointField.text.trim(),
                  access_key_id: s3AccessKeyField.text.trim(),
                  secret_access_key: s3SecretKeyField.text.trim()
                },
                root.mountPath.trim(),
                root.mountImmediate
              )
            }
          }
        }
      }

      // E. Proton Drive
      ColumnLayout {
        visible: root.selectedProvider && root.selectedProvider.id === "protondrive"
        Layout.fillWidth: true
        spacing: Style.space(8)

        ColumnLayout {
          Layout.fillWidth: true
          spacing: Style.space(2)
          Text { text: "Proton Email:"; font.family: root.fontFamily; font.pixelSize: Style.font.caption; font.bold: true; color: root.foreground }
          TextField { id: protonUserField; Layout.fillWidth: true; placeholderText: "user@proton.me" }
        }

        ColumnLayout {
          Layout.fillWidth: true
          spacing: Style.space(2)
          Text { text: "Password:"; font.family: root.fontFamily; font.pixelSize: Style.font.caption; font.bold: true; color: root.foreground }
          TextField { id: protonPassField; Layout.fillWidth: true; placeholderText: "Account Password"; password: !root.showPassword }
        }

        Button {
          Layout.fillWidth: true
          implicitHeight: Style.space(38)
          text: (root.backend && root.backend.authBusy) ? "Connecting…" : "Connect & Mount Proton Drive"
          iconText: "󰅟"
          fontFamily: root.fontFamily
          fontBold: true
          foreground: root.foreground
          bordered: true
          onClicked: {
            if (root.backend) {
              root.backend.addCredentials(
                root.remoteName.trim(),
                "protondrive",
                {
                  username: protonUserField.text.trim(),
                  password: protonPassField.text.trim()
                },
                root.mountPath.trim(),
                root.mountImmediate
              )
            }
          }
        }
      }
    }
  }
}

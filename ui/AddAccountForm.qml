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

  // Selected provider: null shows the gallery of cloud providers
  property var selectedProvider: null

  // Form state
  property string remoteName: ""
  property bool mountImmediate: true
  property bool showPassword: false
  property bool showAdvancedOAuth: false
  property string s3Preset: "AWS"

  signal accountAdded(string remoteName)

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
  }

  Connections {
    target: root.backend
    function onAccountCreated(name) {
      successTimer.restart()
    }
  }

  Timer {
    id: successTimer
    interval: 1400
    repeat: false
    onTriggered: {
      root.accountAdded(root.remoteName)
      root.selectedProvider = null
    }
  }

  // ==========================================================================
  // VIEW 1: PROVIDER GALLERY
  // ==========================================================================
  Flickable {
    id: galleryFlick
    visible: root.selectedProvider === null
    anchors.fill: parent
    contentWidth: width
    contentHeight: galleryCol.implicitHeight + Style.space(40)
    clip: true
    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

    ColumnLayout {
      id: galleryCol
      anchors {
        left: parent.left
        right: parent.right
        top: parent.top
        margins: Style.space(20)
      }
      spacing: Style.space(16)

      Column {
        spacing: Style.space(4)

        Text {
          text: "Connect New Cloud Account"
          font.family: root.fontFamily
          font.pixelSize: Style.font.heading
          font.bold: true
          color: root.foreground
        }

        Text {
          text: "Choose a cloud storage provider to add. ODrive configures everything in the background without needing a terminal."
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          color: root.dim
        }
      }

      Flow {
        Layout.fillWidth: true
        spacing: Style.space(12)

        Repeater {
          model: Model.ALL_PROVIDERS

          BorderSurface {
            id: pCard
            property var prov: modelData
            implicitWidth: Style.space(235)
            implicitHeight: Style.space(145)
            radius: Style.cornerRadius
            color: pCardMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.06) : Qt.rgba(1, 1, 1, 0.03)
            borderSpec: Border.controlSpec(pCardMouse.containsMouse ? "hover-cursor" : "normal", root.foreground, Color.accent)

            ColumnLayout {
              anchors {
                fill: parent
                margins: Style.space(14)
              }
              spacing: Style.space(8)

              RowLayout {
                Layout.fillWidth: true
                spacing: Style.space(10)

                Rectangle {
                  implicitWidth: Style.space(34)
                  implicitHeight: Style.space(34)
                  radius: Style.cornerRadius
                  color: prov.color ? Qt.alpha(prov.color, 0.15) : Qt.rgba(1, 1, 1, 0.08)

                  Text {
                    anchors.centerIn: parent
                    text: prov.glyph || "󰅟"
                    color: prov.color || root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.heading
                  }
                }

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
                    text: prov.category
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption - Style.space(2)
                    color: root.dim
                  }
                }
              }

              Text {
                Layout.fillWidth: true
                text: prov.description
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption - Style.space(1)
                color: root.dim
                wrapMode: Text.WordWrap
                maximumLineCount: 2
                elide: Text.ElideRight
              }

              Item { Layout.fillHeight: true }

              RowLayout {
                Layout.fillWidth: true

                // Pill tag
                Rectangle {
                  implicitHeight: Style.space(18)
                  implicitWidth: tagText.implicitWidth + Style.space(10)
                  radius: Style.cornerRadius
                  color: Qt.rgba(1, 1, 1, 0.05)

                  Text {
                    id: tagText
                    anchors.centerIn: parent
                    text: prov.authTag || "Setup"
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption - Style.space(3)
                    color: root.dim
                  }
                }

                Item { Layout.fillWidth: true }

                Text {
                  text: "Configure →"
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  font.bold: true
                  color: pCardMouse.containsMouse ? Color.accent : root.dim
                }
              }
            }

            MouseArea {
              id: pCardMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.selectProvider(prov.id)
            }
          }
        }
      }
    }
  }

  // ==========================================================================
  // VIEW 2: PROVIDER CONFIGURATION FORM
  // ==========================================================================
  Flickable {
    id: formFlick
    visible: root.selectedProvider !== null
    anchors.fill: parent
    contentWidth: width
    contentHeight: formCol.implicitHeight + Style.space(40)
    clip: true
    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

    ColumnLayout {
      id: formCol
      anchors {
        left: parent.left
        right: parent.right
        top: parent.top
        margins: Style.space(20)
      }
      spacing: Style.space(16)

      // Header Navigation
      RowLayout {
        Layout.fillWidth: true
        spacing: Style.space(12)

        Button {
          iconText: "󰁝"
          text: "All Providers"
          fontFamily: root.fontFamily
          foreground: root.foreground
          bordered: true
          onClicked: {
            if (root.backend && root.backend.authWaiting) {
              root.backend.cancelAuth()
            }
            root.selectedProvider = null
          }
        }

        Item { Layout.fillWidth: true }

        if (root.selectedProvider) {
          RowLayout {
            spacing: Style.space(8)

            Text {
              text: root.selectedProvider.glyph || "󰅟"
              color: root.selectedProvider.color || root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.heading
            }

            Text {
              text: root.selectedProvider.name + " Configuration"
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              font.bold: true
              color: root.foreground
            }
          }
        }
      }

      // Success Banner
      BorderSurface {
        visible: root.backend && root.backend.authSuccess
        Layout.fillWidth: true
        implicitHeight: successRow.implicitHeight + Style.space(20)
        radius: Style.cornerRadius
        color: Qt.rgba(0.1, 0.6, 0.2, 0.15)
        borderSpec: Border.controlSpec("normal", Color.accent, Color.accent)

        RowLayout {
          id: successRow
          anchors {
            fill: parent
            margins: Style.space(12)
          }
          spacing: Style.space(10)

          Text {
            text: "󰄬"
            font.family: root.fontFamily
            font.pixelSize: Style.font.heading
            color: Color.accent
          }

          Text {
            Layout.fillWidth: true
            text: root.backend ? root.backend.authSuccessMessage : "Drive configured successfully!"
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            font.bold: true
            color: root.foreground
          }
        }
      }

      // Error Banner
      BorderSurface {
        visible: root.backend && root.backend.authError !== ""
        Layout.fillWidth: true
        implicitHeight: errorRow.implicitHeight + Style.space(20)
        radius: Style.cornerRadius
        color: Qt.rgba(0.8, 0.1, 0.1, 0.15)
        borderSpec: Border.controlSpec("normal", root.urgent, root.urgent)

        RowLayout {
          id: errorRow
          anchors {
            fill: parent
            margins: Style.space(12)
          }
          spacing: Style.space(10)

          Text {
            text: "󰅚"
            font.family: root.fontFamily
            font.pixelSize: Style.font.heading
            color: root.urgent
          }

          Text {
            Layout.fillWidth: true
            text: root.backend ? root.backend.authError : ""
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
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

      // ----------------------------------------------------------------------
      // SECTION 1: REMOTE NAME & MOUNT PREFERENCES
      // ----------------------------------------------------------------------
      BorderSurface {
        Layout.fillWidth: true
        implicitHeight: generalSecCol.implicitHeight + Style.space(24)
        radius: Style.cornerRadius
        color: Qt.rgba(1, 1, 1, 0.03)
        borderSpec: Border.controlSpec("normal", root.foreground, Color.accent)

        ColumnLayout {
          id: generalSecCol
          anchors {
            fill: parent
            margins: Style.space(14)
          }
          spacing: Style.space(12)

          Text {
            text: "Drive Identification"
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            font.bold: true
            color: root.foreground
          }

          RowLayout {
            Layout.fillWidth: true
            spacing: Style.space(12)

            Column {
              Layout.preferredWidth: Style.space(160)
              spacing: 0

              Text {
                text: "Remote Name:"
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                color: root.foreground
              }

              Text {
                text: "Folder in ~/Cloud"
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption - Style.space(2)
                color: root.dim
              }
            }

            TextField {
              id: remoteNameField
              Layout.fillWidth: true
              text: root.remoteName
              placeholderText: "e.g. MyCloudDrive"
              onTextChanged: { root.remoteName = text }
            }
          }

          RowLayout {
            Layout.fillWidth: true
            spacing: Style.space(12)

            Column {
              Layout.fillWidth: true
              spacing: 0

              Text {
                text: "Mount immediately upon connection"
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                color: root.foreground
              }

              Text {
                text: "Attaches drive to ~/Cloud/" + (root.remoteName || "drive") + " as soon as setup finishes"
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption - Style.space(2)
                color: root.dim
              }
            }

            ToggleSwitch {
              checked: root.mountImmediate
              foreground: root.foreground
              onToggled: root.mountImmediate = !root.mountImmediate
            }
          }
        }
      }

      // ----------------------------------------------------------------------
      // SECTION 2: AUTHENTICATION (DYNAMIC PER PROVIDER)
      // ----------------------------------------------------------------------

      // ----------------------------------------------------------------------
      // A. OAuth Providers (Google Drive, OneDrive, Dropbox, Box, pCloud)
      // ----------------------------------------------------------------------
      BorderSurface {
        visible: root.selectedProvider && root.selectedProvider.authType === "oauth"
        Layout.fillWidth: true
        implicitHeight: oauthSecCol.implicitHeight + Style.space(24)
        radius: Style.cornerRadius
        color: Qt.rgba(1, 1, 1, 0.03)
        borderSpec: Border.controlSpec("normal", root.foreground, Color.accent)

        ColumnLayout {
          id: oauthSecCol
          anchors {
            fill: parent
            margins: Style.space(14)
          }
          spacing: Style.space(14)

          Text {
            text: "Browser Authentication (OAuth 2.0)"
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            font.bold: true
            color: root.foreground
          }

          // Active Waiting Card
          BorderSurface {
            visible: root.backend && root.backend.authWaiting
            Layout.fillWidth: true
            implicitHeight: waitCol.implicitHeight + Style.space(24)
            radius: Style.cornerRadius
            color: Qt.alpha(Color.accent, 0.1)
            borderSpec: Border.controlSpec("focus", root.foreground, Color.accent)

            ColumnLayout {
              id: waitCol
              anchors {
                fill: parent
                margins: Style.space(14)
              }
              spacing: Style.space(10)

              RowLayout {
                Layout.fillWidth: true
                spacing: Style.space(10)

                Text {
                  text: "󰑐"
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.display
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
                  spacing: Style.space(2)

                  Text {
                    text: "Waiting for Browser Authorization…"
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                    font.bold: true
                    color: root.foreground
                  }

                  Text {
                    text: "1. Please switch to your web browser window.\n2. Log in and grant ODrive permission to access your storage.\n3. ODrive will automatically detect authorization and attach your drive."
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    color: root.foreground
                    wrapMode: Text.WordWrap
                    width: parent.width
                  }
                }
              }

              Button {
                Layout.alignment: Qt.AlignRight
                iconText: "󰅚"
                text: "Cancel Authorization"
                fontFamily: root.fontFamily
                foreground: root.urgent
                bordered: true
                onClicked: {
                  if (root.backend) root.backend.cancelAuth()
                }
              }
            }
          }

          // Ready to authorize info
          ColumnLayout {
            visible: !(root.backend && root.backend.authWaiting)
            Layout.fillWidth: true
            spacing: Style.space(12)

            Text {
              Layout.fillWidth: true
              text: "Clicking Authorize below will open your default web browser where you can log in directly on the official " + (root.selectedProvider ? root.selectedProvider.name : "") + " authentication page. Your credentials are never handled by ODrive."
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              color: root.dim
              wrapMode: Text.WordWrap
            }

            // Advanced Options Toggle
            RowLayout {
              Layout.fillWidth: true

              Button {
                text: root.showAdvancedOAuth ? "Hide Advanced OAuth Settings" : "Custom Client ID & Secret (Optional)"
                iconText: root.showAdvancedOAuth ? "󰅃" : "󰅀"
                fontFamily: root.fontFamily
                fontSize: Style.font.caption
                foreground: root.dim
                bordered: false
                onClicked: { root.showAdvancedOAuth = !root.showAdvancedOAuth }
              }

              Item { Layout.fillWidth: true }
            }

            // Advanced Fields
            ColumnLayout {
              visible: root.showAdvancedOAuth
              Layout.fillWidth: true
              spacing: Style.space(8)

              RowLayout {
                Layout.fillWidth: true
                spacing: Style.space(12)

                Text {
                  text: "Client ID:"
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  color: root.dim
                  Layout.preferredWidth: Style.space(120)
                }

                TextField {
                  id: oauthClientIdField
                  Layout.fillWidth: true
                  placeholderText: "Leave blank to use default rclone app"
                }
              }

              RowLayout {
                Layout.fillWidth: true
                spacing: Style.space(12)

                Text {
                  text: "Client Secret:"
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  color: root.dim
                  Layout.preferredWidth: Style.space(120)
                }

                TextField {
                  id: oauthClientSecretField
                  Layout.fillWidth: true
                  placeholderText: "Leave blank to use default rclone app"
                  password: true
                }
              }
            }

            // Action Button
            Button {
              Layout.fillWidth: true
              implicitHeight: Style.space(42)
              text: "Authorize with " + (root.selectedProvider ? root.selectedProvider.name : "") + " in Browser"
              iconText: root.selectedProvider ? root.selectedProvider.glyph : "󰊭"
              fontFamily: root.fontFamily
              fontBold: true
              foreground: root.foreground
              bordered: true
              onClicked: {
                if (!root.remoteName || root.remoteName.trim() === "") {
                  root.suggestName(root.selectedProvider)
                }
                if (root.backend) {
                  root.backend.addOAuth(
                    root.remoteName.trim(),
                    root.selectedProvider.id,
                    oauthClientIdField.text.trim(),
                    oauthClientSecretField.text.trim(),
                    root.mountImmediate
                  )
                }
              }
            }
          }
        }
      }

      // ----------------------------------------------------------------------
      // B. Nextcloud / ownCloud
      // ----------------------------------------------------------------------
      BorderSurface {
        visible: root.selectedProvider && root.selectedProvider.id === "nextcloud"
        Layout.fillWidth: true
        implicitHeight: nextcloudSecCol.implicitHeight + Style.space(24)
        radius: Style.cornerRadius
        color: Qt.rgba(1, 1, 1, 0.03)
        borderSpec: Border.controlSpec("normal", root.foreground, Color.accent)

        ColumnLayout {
          id: nextcloudSecCol
          anchors {
            fill: parent
            margins: Style.space(14)
          }
          spacing: Style.space(12)

          Text {
            text: "Nextcloud Server Credentials"
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            font.bold: true
            color: root.foreground
          }

          RowLayout {
            Layout.fillWidth: true
            spacing: Style.space(12)

            Text {
              text: "Server URL:"
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              color: root.foreground
              Layout.preferredWidth: Style.space(140)
            }

            TextField {
              id: ncUrlField
              Layout.fillWidth: true
              placeholderText: "https://cloud.example.com"
            }
          }

          RowLayout {
            Layout.fillWidth: true
            spacing: Style.space(12)

            Text {
              text: "Username:"
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              color: root.foreground
              Layout.preferredWidth: Style.space(140)
            }

            TextField {
              id: ncUserField
              Layout.fillWidth: true
              placeholderText: "username"
            }
          }

          RowLayout {
            Layout.fillWidth: true
            spacing: Style.space(12)

            Text {
              text: "App Password:"
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              color: root.foreground
              Layout.preferredWidth: Style.space(140)
            }

            TextField {
              id: ncPassField
              Layout.fillWidth: true
              placeholderText: "Password or App Token"
              password: !root.showPassword
            }

            PanelActionButton {
              iconText: root.showPassword ? "󰈈" : "󰈉"
              tooltipText: root.showPassword ? "Hide password" : "Show password"
              foreground: root.foreground
              onClicked: { root.showPassword = !root.showPassword }
            }
          }

          Text {
            Layout.fillWidth: true
            text: "Tip: For accounts with 2-Factor Authentication, create an App Password in Nextcloud under Personal Settings → Security."
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption - Style.space(2)
            color: root.dim
            wrapMode: Text.WordWrap
          }

          Button {
            Layout.fillWidth: true
            implicitHeight: Style.space(42)
            text: (root.backend && root.backend.authBusy) ? "Verifying & Connecting…" : "Connect & Mount Nextcloud"
            iconText: "󰒋"
            fontFamily: root.fontFamily
            fontBold: true
            foreground: root.foreground
            bordered: true
            onClicked: {
              if (!root.remoteName || root.remoteName.trim() === "") root.suggestName(root.selectedProvider)
              if (root.backend) {
                root.backend.addCredentials(
                  root.remoteName.trim(),
                  "nextcloud",
                  {
                    url: ncUrlField.text.trim(),
                    user: ncUserField.text.trim(),
                    pass: ncPassField.text.trim()
                  },
                  root.mountImmediate
                )
              }
            }
          }
        }
      }

      // ----------------------------------------------------------------------
      // C. Generic WebDAV
      // ----------------------------------------------------------------------
      BorderSurface {
        visible: root.selectedProvider && root.selectedProvider.id === "webdav"
        Layout.fillWidth: true
        implicitHeight: webdavSecCol.implicitHeight + Style.space(24)
        radius: Style.cornerRadius
        color: Qt.rgba(1, 1, 1, 0.03)
        borderSpec: Border.controlSpec("normal", root.foreground, Color.accent)

        ColumnLayout {
          id: webdavSecCol
          anchors {
            fill: parent
            margins: Style.space(14)
          }
          spacing: Style.space(12)

          Text {
            text: "WebDAV Server Configuration"
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            font.bold: true
            color: root.foreground
          }

          RowLayout {
            Layout.fillWidth: true
            spacing: Style.space(12)

            Text {
              text: "WebDAV URL:"
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              color: root.foreground
              Layout.preferredWidth: Style.space(140)
            }

            TextField {
              id: wdUrlField
              Layout.fillWidth: true
              placeholderText: "https://dav.example.com/remote.php/webdav"
            }
          }

          RowLayout {
            Layout.fillWidth: true
            spacing: Style.space(12)

            Text {
              text: "Username:"
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              color: root.foreground
              Layout.preferredWidth: Style.space(140)
            }

            TextField {
              id: wdUserField
              Layout.fillWidth: true
              placeholderText: "Username"
            }
          }

          RowLayout {
            Layout.fillWidth: true
            spacing: Style.space(12)

            Text {
              text: "Password:"
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              color: root.foreground
              Layout.preferredWidth: Style.space(140)
            }

            TextField {
              id: wdPassField
              Layout.fillWidth: true
              placeholderText: "Password"
              password: !root.showPassword
            }

            PanelActionButton {
              iconText: root.showPassword ? "󰈈" : "󰈉"
              tooltipText: root.showPassword ? "Hide password" : "Show password"
              foreground: root.foreground
              onClicked: { root.showPassword = !root.showPassword }
            }
          }

          Button {
            Layout.fillWidth: true
            implicitHeight: Style.space(42)
            text: (root.backend && root.backend.authBusy) ? "Verifying & Connecting…" : "Connect & Mount WebDAV"
            iconText: "󰒋"
            fontFamily: root.fontFamily
            fontBold: true
            foreground: root.foreground
            bordered: true
            onClicked: {
              if (!root.remoteName || root.remoteName.trim() === "") root.suggestName(root.selectedProvider)
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
                  root.mountImmediate
                )
              }
            }
          }
        }
      }

      // ----------------------------------------------------------------------
      // D. Amazon S3 / MinIO / R2
      // ----------------------------------------------------------------------
      BorderSurface {
        visible: root.selectedProvider && root.selectedProvider.id === "s3"
        Layout.fillWidth: true
        implicitHeight: s3SecCol.implicitHeight + Style.space(24)
        radius: Style.cornerRadius
        color: Qt.rgba(1, 1, 1, 0.03)
        borderSpec: Border.controlSpec("normal", root.foreground, Color.accent)

        ColumnLayout {
          id: s3SecCol
          anchors {
            fill: parent
            margins: Style.space(14)
          }
          spacing: Style.space(12)

          Text {
            text: "S3 Compatible Object Storage"
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            font.bold: true
            color: root.foreground
          }

          // Provider Preset Buttons
          RowLayout {
            Layout.fillWidth: true
            spacing: Style.space(6)

            Repeater {
              model: ["AWS", "Minio", "Cloudflare", "Wasabi", "Other"]

              Button {
                text: modelData === "Cloudflare" ? "Cloudflare R2" : (modelData === "Minio" ? "MinIO" : modelData)
                fontFamily: root.fontFamily
                fontSize: Style.font.caption
                selected: root.s3Preset === modelData
                foreground: root.foreground
                bordered: true
                onClicked: {
                  root.s3Preset = modelData
                  if (modelData === "Minio" && s3EndpointField.text === "") {
                    s3EndpointField.text = "http://127.0.0.1:9000"
                  } else if (modelData === "Cloudflare" && s3EndpointField.text === "") {
                    s3EndpointField.text = "https://<accountid>.r2.cloudflarestorage.com"
                  }
                }
              }
            }
          }

          RowLayout {
            Layout.fillWidth: true
            spacing: Style.space(12)

            Text {
              text: "Endpoint URL:"
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              color: root.foreground
              Layout.preferredWidth: Style.space(140)
            }

            TextField {
              id: s3EndpointField
              Layout.fillWidth: true
              placeholderText: root.s3Preset === "AWS" ? "Default (AWS endpoints)" : "https://endpoint.example.com"
            }
          }

          RowLayout {
            Layout.fillWidth: true
            spacing: Style.space(12)

            Text {
              text: "Access Key ID:"
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              color: root.foreground
              Layout.preferredWidth: Style.space(140)
            }

            TextField {
              id: s3AccessKeyField
              Layout.fillWidth: true
              placeholderText: "AKIA..."
            }
          }

          RowLayout {
            Layout.fillWidth: true
            spacing: Style.space(12)

            Text {
              text: "Secret Access Key:"
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              color: root.foreground
              Layout.preferredWidth: Style.space(140)
            }

            TextField {
              id: s3SecretKeyField
              Layout.fillWidth: true
              placeholderText: "Secret Key"
              password: !root.showPassword
            }

            PanelActionButton {
              iconText: root.showPassword ? "󰈈" : "󰈉"
              tooltipText: root.showPassword ? "Hide secret" : "Show secret"
              foreground: root.foreground
              onClicked: { root.showPassword = !root.showPassword }
            }
          }

          RowLayout {
            Layout.fillWidth: true
            spacing: Style.space(12)

            Text {
              text: "Region:"
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              color: root.foreground
              Layout.preferredWidth: Style.space(140)
            }

            TextField {
              id: s3RegionField
              Layout.fillWidth: true
              placeholderText: "auto, us-east-1, eu-central-1"
            }
          }

          Button {
            Layout.fillWidth: true
            implicitHeight: Style.space(42)
            text: (root.backend && root.backend.authBusy) ? "Verifying & Connecting…" : "Connect & Mount S3 Storage"
            iconText: "󰋊"
            fontFamily: root.fontFamily
            fontBold: true
            foreground: root.foreground
            bordered: true
            onClicked: {
              if (!root.remoteName || root.remoteName.trim() === "") root.suggestName(root.selectedProvider)
              if (root.backend) {
                root.backend.addCredentials(
                  root.remoteName.trim(),
                  "s3",
                  {
                    provider: root.s3Preset,
                    endpoint: s3EndpointField.text.trim(),
                    access_key_id: s3AccessKeyField.text.trim(),
                    secret_access_key: s3SecretKeyField.text.trim(),
                    region: s3RegionField.text.trim()
                  },
                  root.mountImmediate
                )
              }
            }
          }
        }
      }

      // ----------------------------------------------------------------------
      // E. Proton Drive
      // ----------------------------------------------------------------------
      BorderSurface {
        visible: root.selectedProvider && root.selectedProvider.id === "protondrive"
        Layout.fillWidth: true
        implicitHeight: protonSecCol.implicitHeight + Style.space(24)
        radius: Style.cornerRadius
        color: Qt.rgba(1, 1, 1, 0.03)
        borderSpec: Border.controlSpec("normal", root.foreground, Color.accent)

        ColumnLayout {
          id: protonSecCol
          anchors {
            fill: parent
            margins: Style.space(14)
          }
          spacing: Style.space(12)

          Text {
            text: "Proton Drive Account Login"
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            font.bold: true
            color: root.foreground
          }

          RowLayout {
            Layout.fillWidth: true
            spacing: Style.space(12)

            Text {
              text: "Proton Email:"
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              color: root.foreground
              Layout.preferredWidth: Style.space(140)
            }

            TextField {
              id: protonUserField
              Layout.fillWidth: true
              placeholderText: "user@proton.me"
            }
          }

          RowLayout {
            Layout.fillWidth: true
            spacing: Style.space(12)

            Text {
              text: "Password:"
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              color: root.foreground
              Layout.preferredWidth: Style.space(140)
            }

            TextField {
              id: protonPassField
              Layout.fillWidth: true
              placeholderText: "Proton Account Password"
              password: !root.showPassword
            }

            PanelActionButton {
              iconText: root.showPassword ? "󰈈" : "󰈉"
              tooltipText: root.showPassword ? "Hide password" : "Show password"
              foreground: root.foreground
              onClicked: { root.showPassword = !root.showPassword }
            }
          }

          RowLayout {
            Layout.fillWidth: true
            spacing: Style.space(12)

            Text {
              text: "2FA Code (optional):"
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              color: root.foreground
              Layout.preferredWidth: Style.space(140)
            }

            TextField {
              id: proton2faField
              Layout.fillWidth: true
              placeholderText: "6-digit Authenticator code"
            }
          }

          Button {
            Layout.fillWidth: true
            implicitHeight: Style.space(42)
            text: (root.backend && root.backend.authBusy) ? "Verifying & Connecting…" : "Connect & Mount Proton Drive"
            iconText: "󰅟"
            fontFamily: root.fontFamily
            fontBold: true
            foreground: root.foreground
            bordered: true
            onClicked: {
              if (!root.remoteName || root.remoteName.trim() === "") root.suggestName(root.selectedProvider)
              if (root.backend) {
                root.backend.addCredentials(
                  root.remoteName.trim(),
                  "protondrive",
                  {
                    username: protonUserField.text.trim(),
                    password: protonPassField.text.trim(),
                    "2fa": proton2faField.text.trim()
                  },
                  root.mountImmediate
                )
              }
            }
          }
        }
      }
    }
  }
}

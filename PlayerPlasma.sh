#!/usr/bin/env bash

set -e

PLASMOID_ID="org.kde.roflo.mediaplayer"
PLASMOID_DIR="$HOME/.local/share/plasma/plasmoids/$PLASMOID_ID"

# ---------------------------------------------------------------
# 1. Проверка, что мы в KDE Plasma
# ---------------------------------------------------------------

is_kde() {
    if [[ "${XDG_CURRENT_DESKTOP:-}" == *"KDE"* ]]; then
        return 0
    fi

    if pgrep -x plasmashell &>/dev/null; then
        return 0
    fi

    if [[ -f "$HOME/.config/kdeglobals" ]] && command -v plasmashell &>/dev/null; then
        return 0
    fi

    return 1
}

if ! is_kde; then
    echo ""
    echo "ERROR: It's not a KDE session."
    echo ""
    echo "This plasmoid only works on KDE Plasma."
    echo "Detected: ${XDG_CURRENT_DESKTOP:-unknown}"
    echo ""
    exit 1
fi

# ---------------------------------------------------------------
# 2. Проверка playerctl и установка через пакетный менеджер
# ---------------------------------------------------------------

detect_distro() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        echo "${ID:-unknown}"
    else
        echo "unknown"
    fi
}

install_playerctl() {
    local distro
    distro="$(detect_distro)"

    echo ""
    echo "playerctl not found."
    echo "Detected distribution: $distro"
    echo ""

    case "$distro" in
        arch|manjaro|endeavouros|garuda|cachyos|artix)
            echo "Installing via pacman..."
            sudo pacman -S --needed --noconfirm playerctl
            ;;

        debian|ubuntu|linuxmint|pop|kali|elementary|zorin|neon)
            echo "Installing via apt..."
            sudo apt update && sudo apt install -y playerctl
            ;;

        fedora|rhel|centos|rocky|almalinux)
            echo "Installing via dnf..."
            sudo dnf install -y playerctl
            ;;

        opensuse*|sles|sled)
            echo "Installing via zypper..."
            sudo zypper install -y playerctl
            ;;

        void)
            echo "Installing via xbps..."
            sudo xbps-install -Sy playerctl
            ;;

        alpine)
            echo "Installing via apk..."
            sudo apk add playerctl
            ;;

        gentoo)
            echo "Installing via emerge..."
            sudo emerge --ask media-sound/playerctl
            ;;

        nixos)
            echo "NixOS detected. Add to configuration.nix:"
            echo "  environment.systemPackages = [ pkgs.playerctl ];"
            echo "Then run: sudo nixos-rebuild switch"
            return 1
            ;;

        *)
            if command -v pacman &>/dev/null; then
                sudo pacman -S --needed --noconfirm playerctl
            elif command -v apt &>/dev/null; then
                sudo apt update && sudo apt install -y playerctl
            elif command -v dnf &>/dev/null; then
                sudo dnf install -y playerctl
            elif command -v zypper &>/dev/null; then
                sudo zypper install -y playerctl
            elif command -v xbps-install &>/dev/null; then
                sudo xbps-install -Sy playerctl
            elif command -v apk &>/dev/null; then
                sudo apk add playerctl
            elif command -v emerge &>/dev/null; then
                sudo emerge --ask media-sound/playerctl
            else
                echo ""
                echo "Could not detect a package manager."
                echo "Install playerctl manually:"
                echo "  https://github.com/altdesktop/playerctl"
                return 1
            fi
            ;;
    esac

    return 0
}

if ! command -v playerctl &>/dev/null; then
    echo ""
    read -r -p "Install playerctl now? [Y/n] " ans
    ans="${ans:-Y}"

    if [[ "$ans" =~ ^[Yy]$ ]]; then
        install_playerctl || {
            echo ""
            echo "Failed to install playerctl."
            echo "The widget will still be installed, but won't control the player."
        }
    else
        echo ""
        echo "Skipping. The widget will be installed without player control."
    fi
fi

# ---------------------------------------------------------------
# 3. Установка плазмоида
# ---------------------------------------------------------------

mkdir -p "$PLASMOID_DIR/contents/ui"
mkdir -p "$PLASMOID_DIR/contents/config"

cat << 'EOF' > "$PLASMOID_DIR/metadata.json"
{
    "KPlugin": {
        "Id": "org.kde.roflo.mediaplayer",
        "Name": "Media Player",
        "Description": "Управление плеером через playerctl",
        "Icon": "multimedia-player",
        "Authors": [{ "Name": "Danya" }],
        "Category": "Multimedia",
        "Version": "2.0"
    },
    "KPackageStructure": "Plasma/Applet",
    "X-Plasma-API-Minimum-Version": "6.0"
}
EOF

cat << 'QML_EOF' > "$PLASMOID_DIR/contents/ui/main.qml"
import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.components as PlasmaComponents
import org.kde.plasma.plasma5support as Plasma5Support
import org.kde.kirigami as Kirigami

PlasmoidItem {
    id: root
    preferredRepresentation: fullRepresentation

    Plasmoid.backgroundHints: PlasmaCore.Types.DefaultBackground

    property string trackTitle: "Nothing playing"
    property string trackArtist: ""
    property string artUrl: ""
    property string status: "Stopped"
    property string positionStr: "0:00"
    property string lengthStr: "0:00"
    property real progress: 0.0
    property real totalSec: 0.0
    property real currentSec: 0.0

    readonly property string getMediaCmd: `bash -c '
        P=$(playerctl -l 2>/dev/null | head -n 1)
        if [ -z "$P" ]; then
            echo "Stopped|Nothing playing||||0|0"
            exit 0
        fi
        STATUS=$(playerctl -p "$P" status 2>/dev/null || echo "Stopped")
        ART=$(playerctl -p "$P" metadata mpris:artUrl 2>/dev/null || echo "")
        TITLE=$(playerctl -p "$P" metadata xesam:title 2>/dev/null || echo "Nothing playing")
        ARTIST=$(playerctl -p "$P" metadata xesam:artist 2>/dev/null || echo "")
        POS=$(playerctl -p "$P" position 2>/dev/null || echo "0")
        LEN=$(playerctl -p "$P" metadata mpris:length 2>/dev/null || echo "0")
        echo "$STATUS|$TITLE|$ARTIST|$ART|$POS|$LEN"
    '`

    Plasma5Support.DataSource {
        id: executableSource
        engine: "executable"
        connectedSources: []

        onNewData: (sourceName, data) => {
            var stdout = data["stdout"]
            if (stdout) {
                var parts = stdout.trim().split("|")
                if (parts.length >= 6) {
                    root.status = parts[0].trim()
                    root.trackTitle = parts[1].trim() || "Untitled"
                    root.trackArtist = parts[2].trim()
                    root.artUrl = parts[3].trim()

                    var posSec = Math.floor(parseFloat(parts[4]) || 0)
                    var lenSec = Math.floor((parseFloat(parts[5]) || 0) / 1000000)

                    root.totalSec = lenSec
                    root.currentSec = posSec
                    root.positionStr = formatTime(posSec)
                    root.lengthStr = formatTime(lenSec)
                    root.updateProgress()
                }
            }
            disconnectSource(sourceName)
        }

        function fetchMedia() {
            disconnectSource(root.getMediaCmd)
            connectSource(root.getMediaCmd)
        }

        function runControl(cmd) {
            if (cmd === "play-pause") {
                root.status = (root.status === "Playing" ? "Paused" : "Playing")
                connectSource("bash -c 'P=$(playerctl -l 2>/dev/null | head -n 1); playerctl -p \"$P\" play-pause'")
            } else if (cmd === "force-previous") {
                connectSource("bash -c 'P=$(playerctl -l 2>/dev/null | head -n 1); playerctl -p \"$P\" previous'")
            } else {
                connectSource("bash -c 'P=$(playerctl -l 2>/dev/null | head -n 1); playerctl -p \"$P\" " + cmd + "'")
            }
            delayedFetch.restart()
        }

        function seekTo(targetSec) {
            root.currentSec = targetSec
            root.updateProgress()
            connectSource("bash -c 'P=$(playerctl -l 2>/dev/null | head -n 1); playerctl -p \"$P\" position " + targetSec + "'")
            delayedFetch.restart()
        }
    }

    Timer {
        id: delayedFetch
        interval: 300
        repeat: false
        onTriggered: executableSource.fetchMedia()
    }

    function formatTime(sec) {
        var m = Math.floor(sec / 60)
        var s = Math.floor(sec % 60)
        return m + ":" + (s < 10 ? "0" : "") + s
    }

    function updateProgress() {
        if (totalSec > 0) {
            progress = Math.min(1.0, Math.max(0.0, currentSec / totalSec))
        } else {
            progress = 0
        }
        positionStr = formatTime(currentSec)
    }

    Timer {
        interval: 3000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: executableSource.fetchMedia()
    }

    Timer {
        interval: 1000
        running: root.status === "Playing"
        repeat: true
        onTriggered: {
            if (root.currentSec < root.totalSec) {
                root.currentSec += 1
                root.updateProgress()
            }
        }
    }

    fullRepresentation: Item {
        implicitWidth: 300
        implicitHeight: 420

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Kirigami.Units.gridUnit
            spacing: Kirigami.Units.smallSpacing

            // ================= ОБЛОЖКА =================
            Kirigami.ShadowedRectangle {
                Layout.alignment: Qt.AlignHCenter
                Layout.preferredWidth: 200
                Layout.preferredHeight: 200
                radius: Kirigami.Units.largeSpacing
                color: Kirigami.Theme.alternateBackgroundColor
                border.color: Kirigami.Theme.textColor
                border.width: 1
                shadow.size: 8
                shadow.color: Qt.rgba(0, 0, 0, 0.3)

                Image {
                    id: coverImage
                    anchors.fill: parent
                    anchors.margins: 1
                    source: root.artUrl
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    visible: root.artUrl !== "" && status === Image.Ready
                    layer.enabled: true
                    layer.effect: null
                }

                Kirigami.Icon {
                    anchors.centerIn: parent
                    source: "media-optical-audio"
                    width: Kirigami.Units.iconSizes.huge
                    height: Kirigami.Units.iconSizes.huge
                    visible: root.artUrl === "" || coverImage.status !== Image.Ready
                }
            }

            // ================= ИНФО =================
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2

                PlasmaComponents.Label {
                    text: root.trackTitle
                    font.bold: true
                    font.pixelSize: Kirigami.Theme.defaultFont.pixelSize
                    color: Kirigami.Theme.textColor
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }

                PlasmaComponents.Label {
                    text: root.trackArtist
                    font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                    color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.7)
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                    visible: text.length > 0
                    Layout.fillWidth: true
                }
            }

            // ================= ПРОГРЕСС =================
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2

                PlasmaComponents.Slider {
                    id: seekSlider
                    Layout.fillWidth: true
                    from: 0
                    to: root.totalSec > 0 ? root.totalSec : 1
                    value: root.currentSec
                    enabled: root.totalSec > 0

                    onMoved: {
                        executableSource.seekTo(Math.floor(value))
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    PlasmaComponents.Label {
                        text: root.positionStr
                        font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                        color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.6)
                    }
                    Item { Layout.fillWidth: true }
                    PlasmaComponents.Label {
                        text: root.lengthStr
                        font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                        color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.6)
                    }
                }
            }

            // ================= КНОПКИ =================
            RowLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignHCenter
                spacing: Kirigami.Units.largeSpacing

                Item { Layout.fillWidth: true }

                PlasmaComponents.ToolButton {
                    icon.name: "media-skip-backward"
                    icon.width: Kirigami.Units.iconSizes.smallMedium
                    icon.height: Kirigami.Units.iconSizes.smallMedium
                    onClicked: executableSource.runControl("force-previous")
                }

                PlasmaComponents.ToolButton {
                    icon.name: root.status === "Playing" ? "media-playback-pause" : "media-playback-start"
                    icon.width: Kirigami.Units.iconSizes.medium
                    icon.height: Kirigami.Units.iconSizes.medium
                    onClicked: executableSource.runControl("play-pause")
                }

                PlasmaComponents.ToolButton {
                    icon.name: "media-skip-forward"
                    icon.width: Kirigami.Units.iconSizes.smallMedium
                    icon.height: Kirigami.Units.iconSizes.smallMedium
                    onClicked: executableSource.runControl("next")
                }

                Item { Layout.fillWidth: true }
            }
        }
    }
}
QML_EOF

cat << 'EOF' > "$PLASMOID_DIR/contents/config/main.xml"
<?xml version="1.0" encoding="UTF-8"?>
<kcfg xmlns="http://www.kde.org/standards/kcfg/1.0"
      xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
      xsi:schemaLocation="http://www.kde.org/standards/kcfg/1.0 http://www.kde.org/standards/kcfg/1.0/kcfg.xsd">
  <kcfgfile name=""/>
  <group name="General">
    <entry name="backgroundHints" type="Enum">
      <default>0</default>
    </entry>
  </group>
</kcfg>
EOF

kbuildsycoca6 --noincremental &>/dev/null || true

echo ""
read -r -p "Restart plasmashell now? [y/N] " ans
if [[ "$ans" =~ ^[Yy]$ ]]; then
    nohup plasmashell --replace >/dev/null 2>&1 &
    sleep 1
fi

echo "Done"

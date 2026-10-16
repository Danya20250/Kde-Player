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
    exit 1
fi

# ---------------------------------------------------------------
# 2. Проверка playerctl
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
    case "$distro" in
        arch|manjaro|endeavouros|garuda|cachyos|artix)
            sudo pacman -S --needed --noconfirm playerctl ;;
        debian|ubuntu|linuxmint|pop|kali|elementary|zorin|neon)
            sudo apt update && sudo apt install -y playerctl ;;
        fedora|rhel|centos|rocky|almalinux)
            sudo dnf install -y playerctl ;;
        opensuse*|sles|sled)
            sudo zypper install -y playerctl ;;
        void)
            sudo xbps-install -Sy playerctl ;;
        alpine)
            sudo apk add playerctl ;;
        gentoo)
            sudo emerge --ask media-sound/playerctl ;;
        *)
            if command -v pacman &>/dev/null; then
                sudo pacman -S --needed --noconfirm playerctl
            elif command -v apt &>/dev/null; then
                sudo apt update && sudo apt install -y playerctl
            elif command -v dnf &>/dev/null; then
                sudo dnf install -y playerctl
            else
                return 1
            fi
            ;;
    esac
    return 0
}

if ! command -v playerctl &>/dev/null; then
    read -r -p "Install playerctl now? [Y/n] " ans
    ans="${ans:-Y}"
    if [[ "$ans" =~ ^[Yy]$ ]]; then
        install_playerctl || echo "Failed. Widget installed without player control."
    fi
fi

# ---------------------------------------------------------------
# 3. Установка
# ---------------------------------------------------------------

mkdir -p "$PLASMOID_DIR/contents/ui"
mkdir -p "$PLASMOID_DIR/contents/config"

cat << 'EOF' > "$PLASMOID_DIR/metadata.json"
{
    "KPlugin": {
        "Id": "org.kde.roflo.mediaplayer",
        "Name": "Media Player",
        "Description": "Плеер с эффектами в стиле KDE",
        "Icon": "multimedia-player",
        "Authors": [{ "Name": "Danya" }],
        "Category": "Multimedia",
        "Version": "3.0"
    },
    "KPackageStructure": "Plasma/Applet",
    "X-Plasma-API-Minimum-Version": "6.0"
}
EOF

cat << 'QML_EOF' > "$PLASMOID_DIR/contents/ui/main.qml"
import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import org.kde.plasma.plasmoid
import org.kde.plasma.components as PlasmaComponents
import org.kde.plasma.plasma5support as Plasma5Support
import org.kde.kirigami as Kirigami

PlasmoidItem {
    id: root
    preferredRepresentation: fullRepresentation

    Plasmoid.backgroundHints: Plasmoid.NoBackground

    property string trackTitle: "Nothing playing"
    property string trackArtist: ""
    property string artUrl: ""
    property string status: "Stopped"
    property string positionStr: "0:00"
    property string lengthStr: "0:00"
    property real progress: 0.0
    property real totalSec: 0.0
    property real currentSec: 0.0
    property real waveOffset: 0.0
    property string selectedPlayer: ""
    property var availablePlayers: []
    property bool playerMenuOpen: false

    // Перевод меню по системной локали пользователя.
    readonly property string menuLocale: (Qt.locale().name || "en").toLowerCase()
    readonly property string menuLanguage: menuLocale.split("_")[0].split("-")[0]
    readonly property string menuAutomaticLabel: menuText("automatic")

    function menuText(key) {
        var translations = {
            ru: { title: "Медиаплеер", automatic: "Автоматически", refresh: "Обновить" },
            en: { title: "Media player", automatic: "Automatic", refresh: "Refresh" },
            zh: { title: "媒体播放器", automatic: "自动选择", refresh: "刷新" },
            "zh-tw": { title: "媒體播放器", automatic: "自動選擇", refresh: "重新整理" },
            ja: { title: "メディアプレーヤー", automatic: "自動", refresh: "更新" },
            ko: { title: "미디어 플레이어", automatic: "자동", refresh: "새로 고침" },
            de: { title: "Medienplayer", automatic: "Automatisch", refresh: "Aktualisieren" },
            fr: { title: "Lecteur multimédia", automatic: "Automatique", refresh: "Actualiser" },
            es: { title: "Reproductor multimedia", automatic: "Automático", refresh: "Actualizar" },
            it: { title: "Lettore multimediale", automatic: "Automatico", refresh: "Aggiorna" },
            pt: { title: "Reprodutor de mídia", automatic: "Automático", refresh: "Atualizar" },
            pl: { title: "Odtwarzacz multimedialny", automatic: "Automatycznie", refresh: "Odśwież" },
            uk: { title: "Медіапрогравач", automatic: "Автоматично", refresh: "Оновити" },
            tr: { title: "Medya oynatıcı", automatic: "Otomatik", refresh: "Yenile" },
            nl: { title: "Mediaspeler", automatic: "Automatisch", refresh: "Vernieuwen" },
            sv: { title: "Mediaspelare", automatic: "Automatiskt", refresh: "Uppdatera" },
            cs: { title: "Přehrávač médií", automatic: "Automaticky", refresh: "Obnovit" },
            da: { title: "Medieafspiller", automatic: "Automatisk", refresh: "Opdater" },
            fi: { title: "Mediasoitin", automatic: "Automaattinen", refresh: "Päivitä" },
            no: { title: "Mediespiller", automatic: "Automatisk", refresh: "Oppdater" }
        }
        var lang = menuLanguage
        if (lang === "zh" && (menuLocale.indexOf("zh_tw") === 0 || menuLocale.indexOf("zh-hant") === 0 || menuLocale.indexOf("zh_hk") === 0))
            lang = "zh-tw"
        var pack = translations[lang] || translations.en
        return pack[key] || translations.en[key] || key
    }

    property color auraColor1: Kirigami.Theme.highlightColor
    property color auraColor2: Kirigami.Theme.positiveTextColor
    // Автоматически определяем светлую или тёмную тему Plasma.
    readonly property bool isLightTheme: {
        var c = Kirigami.Theme.backgroundColor
        return (0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b) > 0.5
    }

    readonly property string getMediaCmd: `bash -c '
        P="${root.selectedPlayer}"; if [ -z "$P" ]; then P=$(playerctl -l 2>/dev/null | grep -i "Cassette" | head -n 1); [ -n "$P" ] || P=$(playerctl -l 2>/dev/null | while IFS= read -r p; do if [ "$(playerctl -p "$p" status 2>/dev/null)" = "Playing" ]; then printf "%s\n" "$p"; break; fi; done); [ -n "$P" ] || P=$(playerctl -l 2>/dev/null | head -n 1); fi
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
                connectSource(`bash -c 'P="${root.selectedPlayer}"; if [ -z "$P" ]; then P=$(playerctl -l 2>/dev/null | grep -i Cassette | head -n 1); [ -n "$P" ] || P=$(playerctl -l 2>/dev/null | head -n 1); fi; playerctl -p "$P" play-pause'`)
            } else if (cmd === "force-previous") {
                connectSource(`bash -c 'P="${root.selectedPlayer}"; if [ -z "$P" ]; then P=$(playerctl -l 2>/dev/null | grep -i Cassette | head -n 1); [ -n "$P" ] || P=$(playerctl -l 2>/dev/null | head -n 1); fi; playerctl -p "$P" previous'`)
            } else {
                connectSource(`bash -c 'P="${root.selectedPlayer}"; if [ -z "$P" ]; then P=$(playerctl -l 2>/dev/null | grep -i Cassette | head -n 1); [ -n "$P" ] || P=$(playerctl -l 2>/dev/null | head -n 1); fi; playerctl -p "$P" ${cmd}'`)
            }
            delayedFetch.restart()
        }

        function seekTo(targetSec) {
            root.currentSec = targetSec
            root.updateProgress()
            connectSource(`bash -c 'P="${root.selectedPlayer}"; if [ -z "$P" ]; then P=$(playerctl -l 2>/dev/null | grep -i Cassette | head -n 1); [ -n "$P" ] || P=$(playerctl -l 2>/dev/null | head -n 1); fi; playerctl -p "$P" position ${targetSec}'`)
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

    NumberAnimation on waveOffset {
        running: root.status === "Playing"
        from: 0
        to: Math.PI * 2
        duration: 1500
        loops: Animation.Infinite
    }

    fullRepresentation: Item {
        implicitWidth: 300
        implicitHeight: 420

        Rectangle {
            id: mainBg
            anchors.fill: parent
            color: root.isLightTheme ? Kirigami.Theme.backgroundColor : Qt.rgba(0.1, 0.1, 0.12, 0.9)
            radius: 20
            clip: true

            // ================= АУРА =================
            Item {
                id: auraContainer
                anchors.fill: parent
                opacity: root.isLightTheme ? 0.18 : 0.7

                Rectangle {
                    width: parent.width * 1.6
                    height: width
                    radius: width / 2
                    anchors.horizontalCenter: parent.left
                    anchors.verticalCenter: parent.top
                    color: root.auraColor1

                    Behavior on color { ColorAnimation { duration: 800 } }

                    SequentialAnimation on anchors.horizontalCenterOffset {
                        loops: Animation.Infinite
                        running: true
                        PropertyAnimation { to: 40; duration: 8000; easing.type: Easing.InOutSine }
                        PropertyAnimation { to: -30; duration: 9000; easing.type: Easing.InOutSine }
                    }
                    SequentialAnimation on anchors.verticalCenterOffset {
                        loops: Animation.Infinite
                        running: true
                        PropertyAnimation { to: 50; duration: 10000; easing.type: Easing.InOutSine }
                        PropertyAnimation { to: -20; duration: 7000; easing.type: Easing.InOutSine }
                    }
                }

                Rectangle {
                    width: parent.width * 1.6
                    height: width
                    radius: width / 2
                    anchors.horizontalCenter: parent.right
                    anchors.verticalCenter: parent.bottom
                    color: root.auraColor2

                    Behavior on color { ColorAnimation { duration: 800 } }

                    SequentialAnimation on anchors.horizontalCenterOffset {
                        loops: Animation.Infinite
                        running: true
                        PropertyAnimation { to: -50; duration: 9000; easing.type: Easing.InOutSine }
                        PropertyAnimation { to: 20; duration: 8000; easing.type: Easing.InOutSine }
                    }
                    SequentialAnimation on anchors.verticalCenterOffset {
                        loops: Animation.Infinite
                        running: true
                        PropertyAnimation { to: -40; duration: 7500; easing.type: Easing.InOutSine }
                        PropertyAnimation { to: 30; duration: 9500; easing.type: Easing.InOutSine }
                    }
                }

                Rectangle {
                    width: parent.width * 1.4
                    height: width
                    radius: width / 2
                    anchors.horizontalCenter: parent.right
                    anchors.verticalCenter: parent.top
                    color: root.auraColor1

                    Behavior on color { ColorAnimation { duration: 800 } }

                    SequentialAnimation on anchors.horizontalCenterOffset {
                        loops: Animation.Infinite
                        running: true
                        PropertyAnimation { to: -30; duration: 8500; easing.type: Easing.InOutSine }
                        PropertyAnimation { to: 40; duration: 10500; easing.type: Easing.InOutSine }
                    }
                    SequentialAnimation on anchors.verticalCenterOffset {
                        loops: Animation.Infinite
                        running: true
                        PropertyAnimation { to: 60; duration: 9000; easing.type: Easing.InOutSine }
                        PropertyAnimation { to: -30; duration: 8000; easing.type: Easing.InOutSine }
                    }
                }
            }

            MultiEffect {
                anchors.fill: auraContainer
                source: auraContainer
                blurEnabled: true
                blur: 1.0
                blurMax: 96
            }

            // ================= ИЗВЛЕЧЕНИЕ ЦВЕТА ИЗ ОБЛОЖКИ =================
            Canvas {
                id: colorExtractor
                width: 30
                height: 30
                visible: false

                property string currentArt: root.artUrl

                onCurrentArtChanged: {
                    if (currentArt !== "") loadImage(currentArt)
                }

                function ensureBrightness(r, g, b) {
                    var lightness = (Math.max(r, g, b) + Math.min(r, g, b)) / (2 * 255)
                    var c = Qt.rgba(r / 255, g / 255, b / 255, 1.0)
                    if (lightness < 0.35) {
                        var factor = 0.45 / Math.max(lightness, 0.05)
                        return Qt.rgba(Math.min(1.0, c.r * factor), Math.min(1.0, c.g * factor), Math.min(1.0, c.b * factor), 1.0)
                    }
                    return c
                }

                onImageLoaded: {
                    var ctx = getContext("2d")
                    ctx.drawImage(currentArt, 0, 0, width, height)
                    var p1 = ctx.getImageData(5, 5, 1, 1).data
                    var p2 = ctx.getImageData(25, 25, 1, 1).data
                    root.auraColor1 = ensureBrightness(p1[0], p1[1], p1[2])
                    root.auraColor2 = ensureBrightness(p2[0], p2[1], p2[2])
                }
            }

            // ================= МЕНЮ ПЛЕЕРА =================
            Item {
                id: playerMenuButton
                width: 28
                height: 28
                anchors.top: parent.top
                anchors.right: parent.right
                anchors.topMargin: 10
                anchors.rightMargin: 10
                z: 100

                Rectangle {
                    anchors.fill: parent
                    radius: width / 2
                    color: menuButtonMouse.containsMouse || root.playerMenuOpen ? "#34363a" : "#202124"
                    border.width: 1
                    border.color: "#45474b"
                    Behavior on color { ColorAnimation { duration: 140 } }
                }
                Kirigami.Icon {
                    anchors.centerIn: parent
                    width: 18
                    height: 18
                    source: "overflow-menu"
                    color: "#f3f3f3"
                    opacity: menuButtonMouse.containsMouse || root.playerMenuOpen ? 1.0 : 0.9
                }
                MouseArea {
                    id: menuButtonMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        root.playerMenuOpen = !root.playerMenuOpen
                        if (root.playerMenuOpen) playerListSource.refreshPlayers()
                    }
                }

                Rectangle {
                    id: playerMenu
                    anchors.top: parent.bottom
                    anchors.right: parent.right
                    anchors.topMargin: 6
                    width: 205
                    height: Math.min(260, playerMenuColumn.implicitHeight + 16)
                    visible: root.playerMenuOpen
                    radius: 12
                    // Всегда тёмная непрозрачная подложка — в том числе в светлой теме Plasma.
                    color: "#202124"
                    border.width: 1
                    border.color: "#45474b"
                    z: 101

                    ColumnLayout {
                        id: playerMenuColumn
                        anchors.fill: parent
                        anchors.margins: 8
                        spacing: 4

                        PlasmaComponents.Label {
                            text: root.menuText("title")
                            font.bold: true
                            color: "#ffffff"
                            Layout.fillWidth: true
                            Layout.leftMargin: 6
                            Layout.bottomMargin: 3
                        }

                        Repeater {
                            model: [root.menuAutomaticLabel].concat(root.availablePlayers)
                            delegate: Rectangle {
                                required property string modelData
                                Layout.fillWidth: true
                                height: 30
                                radius: 7
                                color: playerOptionMouse.containsMouse ? "#34363a" : "transparent"
                                PlasmaComponents.Label {
                                    anchors.fill: parent
                                    anchors.leftMargin: 8
                                    anchors.rightMargin: 8
                                    verticalAlignment: Text.AlignVCenter
                                    elide: Text.ElideRight
                                    text: modelData
                                    font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                                    color: (modelData === root.menuAutomaticLabel && root.selectedPlayer === "") || modelData === root.selectedPlayer ? "#8ab4f8" : "#f1f3f4"
                                }
                                MouseArea {
                                    id: playerOptionMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        root.selectedPlayer = modelData === root.menuAutomaticLabel ? "" : modelData
                                        root.playerMenuOpen = false
                                        executableSource.fetchMedia()
                                    }
                                }
                            }
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            height: 1
                            color: "#45474b"
                            Layout.topMargin: 2
                            Layout.bottomMargin: 2
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            height: 32
                            radius: 7
                            color: refreshMenuMouse.containsMouse ? "#34363a" : "transparent"
                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 8
                                spacing: 8
                                Kirigami.Icon { source: "view-refresh"; width: 16; height: 16; color: "#f1f3f4" }
                                PlasmaComponents.Label { text: root.menuText("refresh"); Layout.fillWidth: true; color: "#f1f3f4" }
                            }
                            MouseArea {
                                id: refreshMenuMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    root.playerMenuOpen = false
                                    playerListSource.refreshPlayers()
                                    executableSource.fetchMedia()
                                }
                            }
                        }
                    }
                }
            }

            Plasma5Support.DataSource {
                id: playerListSource
                engine: "executable"
                connectedSources: []
                function refreshPlayers() {
                    disconnectSource("bash -c 'playerctl -l 2>/dev/null'")
                    connectSource("bash -c 'playerctl -l 2>/dev/null'")
                }
                onNewData: (sourceName, data) => {
                    var output = data["stdout"] || ""
                    var lines = output.trim().split("\n").filter(p => p.length > 0)
                    root.availablePlayers = lines
                    disconnectSource(sourceName)
                }
            }

            // ================= КОНТЕНТ =================
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
                    border.color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.15)
                    border.width: 1
                    shadow.size: 8
                    shadow.color: Qt.rgba(0, 0, 0, 0.4)

                    Image {
                        id: coverImage
                        anchors.fill: parent
                        anchors.margins: 1
                        source: root.artUrl
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        visible: root.artUrl !== "" && status === Image.Ready
                    }

                    Kirigami.Icon {
                        anchors.centerIn: parent
                        source: "media-optical-audio"
                        width: Kirigami.Units.iconSizes.huge
                        height: Kirigami.Units.iconSizes.huge
                        visible: root.artUrl === "" || coverImage.status !== Image.Ready
                        opacity: 0.6
                    }
                }

                // ================= ИНФО О ТРЕКЕ =================
                Rectangle {
                    Layout.fillWidth: true
                    color: root.isLightTheme ? Qt.rgba(0, 0, 0, 0.045) : Qt.rgba(0, 0, 0, 0.4)
                    border.color: root.isLightTheme ? Qt.rgba(0, 0, 0, 0.12) : Qt.rgba(1, 1, 1, 0.12)
                    border.width: 1
                    radius: Kirigami.Units.smallSpacing
                    implicitHeight: infoColumn.implicitHeight + 10

                    ColumnLayout {
                        id: infoColumn
                        anchors.fill: parent
                        anchors.margins: 5
                        spacing: 1

                        PlasmaComponents.Label {
                            text: root.trackTitle
                            font.pixelSize: Kirigami.Theme.defaultFont.pixelSize
                            font.bold: true
                            color: Kirigami.Theme.textColor
                            horizontalAlignment: Text.AlignHCenter
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }

                        PlasmaComponents.Label {
                            text: root.trackArtist
                            font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                            color: root.isLightTheme ? Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.7) : Qt.rgba(1, 1, 1, 0.7)
                            horizontalAlignment: Text.AlignHCenter
                            elide: Text.ElideRight
                            visible: text.length > 0
                            Layout.fillWidth: true
                        }
                    }
                }

                // ================= ВОЛНИСТЫЙ ПРОГРЕСС (оригинальный) =================
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2

                    Item {
                        id: seekContainer
                        Layout.fillWidth: true
                        height: 28

                        Rectangle {
                            id: seekPill
                            anchors.fill: parent
                            radius: height / 2
                            color: Qt.rgba(1, 1, 1, 0.055)
                            border.color: Qt.rgba(1, 1, 1, 0.08)
                            border.width: 1
                        }

                        Rectangle {
                            id: leftSeparator
                            width: 2
                            height: 12
                            radius: 1
                            anchors.left: parent.left
                            anchors.leftMargin: 8
                            anchors.verticalCenter: parent.verticalCenter
                            color: Qt.rgba(1, 1, 1, 0.28)
                        }

                        Rectangle {
                            id: rightSeparator
                            width: 2
                            height: 12
                            radius: 1
                            anchors.right: parent.right
                            anchors.rightMargin: 8
                            anchors.verticalCenter: parent.verticalCenter
                            color: Qt.rgba(1, 1, 1, 0.28)
                        }

                        Item {
                            id: seekTrackArea
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.leftMargin: 20
                            anchors.rightMargin: 20
                            anchors.verticalCenter: parent.verticalCenter
                            height: 18

                            Rectangle {
                                id: seekBackground
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                height: 6
                                radius: 3
                                color: Qt.rgba(1, 1, 1, 0.13)
                            }

                            Item {
                                id: seekActiveContainer
                                anchors.left: seekBackground.left
                                anchors.verticalCenter: seekBackground.verticalCenter
                                width: seekBackground.width * root.progress
                                height: 18
                                clip: true

                                Behavior on width {
                                    NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
                                }

                                Canvas {
                                    id: waveCanvas
                                    anchors.fill: parent

                                    property real amplitude: 3.5
                                    property real wavelength: 22
                                    property real phase: root.waveOffset

                                    onPhaseChanged: requestPaint()
                                    onWidthChanged: requestPaint()
                                    onHeightChanged: requestPaint()

                                    onPaint: {
                                        var ctx = getContext("2d")
                                        ctx.reset()
                                        var w = width
                                        var h = height
                                        var cy = h / 2
                                        if (w <= 0) return

                                        var grad = ctx.createLinearGradient(0, 0, w, 0)
                                        grad.addColorStop(0.0, root.auraColor1)
                                        grad.addColorStop(0.55, Qt.lighter(root.auraColor1, 1.15))
                                        grad.addColorStop(1.0, root.auraColor2)

                                        ctx.fillStyle = grad
                                        ctx.strokeStyle = grad
                                        ctx.lineCap = "round"
                                        ctx.lineJoin = "round"

                                        ctx.beginPath()
                                        var steps = Math.max(2, Math.ceil(w / 2))
                                        for (var i = 0; i <= steps; i++) {
                                            var x = (i / steps) * w
                                            var y = cy - root.waveAmplitudeAt(x, phase, wavelength, amplitude)
                                            if (i === 0) ctx.moveTo(x, y)
                                            else ctx.lineTo(x, y)
                                        }
                                        for (var j = steps; j >= 0; j--) {
                                            var x2 = (j / steps) * w
                                            var y2 = cy + root.waveAmplitudeAt(x2, phase, wavelength, amplitude)
                                            ctx.lineTo(x2, y2)
                                        }
                                        ctx.closePath()
                                        ctx.fill()
                                    }
                                }

                                MultiEffect {
                                    anchors.fill: waveCanvas
                                    source: waveCanvas
                                    blurEnabled: true
                                    blur: 0.6
                                    blurMax: 18
                                    opacity: 0.6
                                }
                            }

                            // Деления
                            Rectangle {
                                width: 1; height: 5; radius: 1
                                x: seekBackground.width * 0.25
                                anchors.verticalCenter: seekBackground.verticalCenter
                                color: Qt.rgba(1, 1, 1, 0.16)
                            }
                            Rectangle {
                                width: 1; height: 5; radius: 1
                                x: seekBackground.width * 0.50
                                anchors.verticalCenter: seekBackground.verticalCenter
                                color: Qt.rgba(1, 1, 1, 0.16)
                            }
                            Rectangle {
                                width: 1; height: 5; radius: 1
                                x: seekBackground.width * 0.75
                                anchors.verticalCenter: seekBackground.verticalCenter
                                color: Qt.rgba(1, 1, 1, 0.16)
                            }

                            // Светящийся ползунок
                            Rectangle {
                                id: seekThumbGlow
                                width: 14
                                height: 22
                                radius: 7
                                x: Math.max(-7, Math.min(seekBackground.width - 7, seekBackground.width * root.progress - 7))
                                anchors.verticalCenter: seekBackground.verticalCenter
                                color: root.auraColor2
                                opacity: seekMouse.containsMouse || seekMouse.pressed ? 0.32 : 0.18
                                scale: seekMouse.containsMouse ? 1.15 : 1.0

                                Behavior on opacity { NumberAnimation { duration: 150 } }
                                Behavior on scale { SpringAnimation { spring: 4.5; damping: 0.35 } }
                            }

                            MultiEffect {
                                anchors.fill: seekThumbGlow
                                source: seekThumbGlow
                                blurEnabled: true
                                blur: 1.0
                                blurMax: 20
                                opacity: 0.8
                            }

                            Rectangle {
                                id: seekThumb
                                width: 8
                                height: 18
                                radius: 4
                                x: Math.max(-4, Math.min(seekBackground.width - 4, seekBackground.width * root.progress - 4))
                                anchors.verticalCenter: seekBackground.verticalCenter
                                color: "#ffffff"
                                border.color: Qt.rgba(1, 1, 1, 0.45)
                                border.width: 1
                                scale: seekMouse.containsMouse || seekMouse.pressed ? 1.18 : 1.0

                                Behavior on x { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                                Behavior on scale { SpringAnimation { spring: 5; damping: 0.35 } }
                            }
                        }

                        MouseArea {
                            id: seekMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor

                            onClicked: (mouse) => handleSeek(mouse.x)
                            onPositionChanged: (mouse) => { if (pressed) handleSeek(mouse.x) }

                            function handleSeek(mouseX) {
                                if (root.totalSec > 0) {
                                    var trackStart = seekTrackArea.x
                                    var trackWidth = seekTrackArea.width
                                    var pct = (mouseX - trackStart) / trackWidth
                                    pct = Math.max(0, Math.min(1, pct))
                                    executableSource.seekTo(Math.floor(pct * root.totalSec))
                                }
                            }
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        PlasmaComponents.Label {
                            text: root.positionStr
                            font.pixelSize: 10
                            color: "#808080"
                        }
                        Item { Layout.fillWidth: true }
                        PlasmaComponents.Label {
                            text: root.lengthStr
                            font.pixelSize: 10
                            color: "#808080"
                        }
                    }
                }

                // ================= КНОПКИ С ФОНОМ (оригинальные) =================
                RowLayout {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 56
                    Layout.alignment: Qt.AlignHCenter
                    spacing: 16

                    Item { Layout.fillWidth: true }

                    // КНОПКА "НАЗАД"
                    Item {
                        Layout.preferredWidth: 46
                        Layout.preferredHeight: 46

                        Rectangle {
                            id: prevBtnBg
                            anchors.fill: parent
                            radius: 23
                            scale: prevBtnMouse.pressed ? 0.90 : (prevBtnMouse.containsMouse ? 1.08 : 1.0)
                            color: prevBtnMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.25) : Qt.rgba(1, 1, 1, 0.12)
                            border.color: Qt.rgba(1, 1, 1, 0.25)
                            border.width: 1

                            Behavior on scale { SpringAnimation { spring: 4.5; damping: 0.3 } }
                            Behavior on color { ColorAnimation { duration: 150 } }
                        }

                        MultiEffect {
                            anchors.fill: prevBtnBg
                            source: auraContainer
                            blurEnabled: true
                            blur: 1.0
                            blurMax: 32
                            maskEnabled: true
                            maskSource: prevBtnBg
                        }

                        Kirigami.Icon {
                            anchors.centerIn: parent
                            source: "media-skip-backward"
                            width: 20
                            height: 20
                            color: "#ffffff"
                        }

                        MouseArea {
                            id: prevBtnMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: executableSource.runControl("force-previous")
                        }
                    }

                    // КНОПКА "PLAY/PAUSE"
                    Item {
                        Layout.preferredWidth: 54
                        Layout.preferredHeight: 54

                        Rectangle {
                            id: playBtnBg
                            anchors.fill: parent
                            radius: root.status === "Playing" ? 27 : 16
                            scale: playBtnMouse.pressed ? 0.90 : (playBtnMouse.containsMouse ? 1.08 : 1.0)
                            color: {
                                if (root.status === "Playing") {
                                    return playBtnMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.35) : Qt.rgba(1, 1, 1, 0.20)
                                } else {
                                    return playBtnMouse.containsMouse ? "#ffffff" : "#e0e0e0"
                                }
                            }
                            border.color: root.status === "Playing" ? Qt.rgba(1, 1, 1, 0.3) : "transparent"
                            border.width: 1

                            Behavior on radius { SpringAnimation { spring: 3.5; damping: 0.3 } }
                            Behavior on scale { SpringAnimation { spring: 4.5; damping: 0.3 } }
                            Behavior on color { ColorAnimation { duration: 150 } }
                        }

                        MultiEffect {
                            anchors.fill: playBtnBg
                            source: auraContainer
                            blurEnabled: root.status === "Playing"
                            blur: 1.0
                            blurMax: 32
                            maskEnabled: true
                            maskSource: playBtnBg
                        }

                        Kirigami.Icon {
                            anchors.centerIn: parent
                            source: root.status === "Playing" ? "media-playback-pause" : "media-playback-start"
                            width: 24
                            height: 24
                            color: root.status === "Playing" ? "#ffffff" : "#000000"
                        }

                        MouseArea {
                            id: playBtnMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: executableSource.runControl("play-pause")
                        }
                    }

                    // КНОПКА "ВПЕРЁД"
                    Item {
                        Layout.preferredWidth: 46
                        Layout.preferredHeight: 46

                        Rectangle {
                            id: nextBtnBg
                            anchors.fill: parent
                            radius: 23
                            scale: nextBtnMouse.pressed ? 0.90 : (nextBtnMouse.containsMouse ? 1.08 : 1.0)
                            color: nextBtnMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.25) : Qt.rgba(1, 1, 1, 0.12)
                            border.color: Qt.rgba(1, 1, 1, 0.25)
                            border.width: 1

                            Behavior on scale { SpringAnimation { spring: 4.5; damping: 0.3 } }
                            Behavior on color { ColorAnimation { duration: 150 } }
                        }

                        MultiEffect {
                            anchors.fill: nextBtnBg
                            source: auraContainer
                            blurEnabled: true
                            blur: 1.0
                            blurMax: 32
                            maskEnabled: true
                            maskSource: nextBtnBg
                        }

                        Kirigami.Icon {
                            anchors.centerIn: parent
                            source: "media-skip-forward"
                            width: 20
                            height: 20
                            color: "#ffffff"
                        }

                        MouseArea {
                            id: nextBtnMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: executableSource.runControl("next")
                        }
                    }

                    Item { Layout.fillWidth: true }
                }
            }
        }
    }

    function waveAmplitudeAt(x, phase, wavelength, amplitude) {
        return Math.sin((x / wavelength) * Math.PI * 2 + phase) * amplitude
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

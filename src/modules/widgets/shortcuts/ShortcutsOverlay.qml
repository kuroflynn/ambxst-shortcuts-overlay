import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland
import qs.config
import qs.modules.components
import qs.modules.globals
import qs.modules.services
import qs.modules.theme
import "ShortcutData.js" as ShortcutData

PanelWindow {
    id: root

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }

    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    visible: shortcutsOpen

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "ambxst:shortcuts"
    WlrLayershell.keyboardFocus: shortcutsOpen ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    readonly property var screenVisibilities: screen ? Visibilities.getForScreen(screen.name) : null
    readonly property bool shortcutsOpen: screenVisibilities ? screenVisibilities.shortcuts : false
    readonly property int columnCount: panel.width >= 1040 ? 3 : (panel.width >= 680 ? 2 : 1)

    property var sections: []
    property int shortcutCount: 0
    property string dataError: ""

    function close() {
        Visibilities.setActiveModule("");
    }

    function refreshData() {
        const loader = Config.keybindsLoader;
        if (!loader || !loader.loaded) {
            sections = [];
            shortcutCount = 0;
            dataError = "La configuración de atajos aún no está disponible.";
            return;
        }

        let rawText;
        try {
            rawText = loader.text();
        } catch (error) {
            sections = [];
            shortcutCount = 0;
            dataError = "No se pudo leer la configuración de atajos.";
            return;
        }

        const parsed = ShortcutData.parseJson(rawText);
        if (!parsed.ok) {
            sections = [];
            shortcutCount = 0;
            dataError = parsed.error;
            return;
        }

        const adapter = loader.adapter;
        if (!adapter || !adapter.ambxst) {
            sections = [];
            shortcutCount = 0;
            dataError = "La configuración activa de atajos aún no está disponible.";
            return;
        }

        const activeBinds = {
            ambxst: adapter.ambxst,
            custom: adapter.custom || []
        };
        const result = ShortcutData.build(activeBinds, GlobalStates.compositorLayout);
        sections = result.sections;
        shortcutCount = result.total;
        dataError = result.error;
        shortcutsFlickable.contentY = 0;
    }

    function scrollBy(amount) {
        const maximum = Math.max(0, shortcutsFlickable.contentHeight - shortcutsFlickable.height);
        shortcutsFlickable.contentY = Math.max(0, Math.min(maximum, shortcutsFlickable.contentY + amount));
    }

    function sectionIcon(sectionId) {
        switch (sectionId) {
        case "ambxst": return Icons.terminal;
        case "windows": return Icons.apps;
        case "workspaces": return Icons.overview;
        case "layout": return Icons.layout;
        case "system": return Icons.gear;
        case "media": return Icons.player;
        default: return Icons.keyboard;
        }
    }

    mask: Region {
        item: root.shortcutsOpen ? fullMask : emptyMask
    }

    Item {
        id: fullMask
        anchors.fill: parent
    }

    Item {
        id: emptyMask
        width: 0
        height: 0
    }

    FocusGrab {
        windows: [root]
        active: root.shortcutsOpen

        onCleared: {
            Qt.callLater(() => {
                if (root.shortcutsOpen)
                    root.close();
            });
        }
    }

    Rectangle {
        anchors.fill: parent
        color: Colors.scrim
        opacity: root.shortcutsOpen ? 0.55 : 0

        Behavior on opacity {
            enabled: Config.animDuration > 0
            NumberAnimation {
                duration: Config.animDuration
                easing.type: Easing.OutQuart
            }
        }

        MouseArea {
            anchors.fill: parent
            onClicked: root.close()
        }
    }

    FocusScope {
        id: focusScope
        anchors.fill: parent
        focus: root.shortcutsOpen

        Keys.priority: Keys.BeforeItem
        Keys.onEscapePressed: event => {
            event.accepted = true;
            root.close();
        }
        Keys.onPressed: event => {
            if (event.key === Qt.Key_PageDown) {
                root.scrollBy(shortcutsFlickable.height * 0.8);
                event.accepted = true;
            } else if (event.key === Qt.Key_PageUp) {
                root.scrollBy(-shortcutsFlickable.height * 0.8);
                event.accepted = true;
            } else if (event.key === Qt.Key_Down) {
                root.scrollBy(64);
                event.accepted = true;
            } else if (event.key === Qt.Key_Up) {
                root.scrollBy(-64);
                event.accepted = true;
            } else if (event.key === Qt.Key_Home) {
                shortcutsFlickable.contentY = 0;
                event.accepted = true;
            } else if (event.key === Qt.Key_End) {
                shortcutsFlickable.contentY = Math.max(0, shortcutsFlickable.contentHeight - shortcutsFlickable.height);
                event.accepted = true;
            }
        }

        StyledRect {
            id: panel
            anchors.centerIn: parent
            width: Math.min(1260, Math.max(320, parent.width - 48))
            height: Math.min(820, Math.max(320, parent.height - 64))
            variant: "bg"
            radius: Styling.radius(20)

            opacity: root.shortcutsOpen ? 1 : 0
            scale: root.shortcutsOpen ? 1 : 0.94

            layer.enabled: true
            layer.effect: Shadow {}

            Behavior on opacity {
                enabled: Config.animDuration > 0
                NumberAnimation {
                    duration: Config.animDuration
                    easing.type: Easing.OutQuart
                }
            }

            Behavior on scale {
                enabled: Config.animDuration > 0
                NumberAnimation {
                    duration: Config.animDuration
                    easing.type: Easing.OutBack
                    easing.overshoot: 1.1
                }
            }

            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.AllButtons
            }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: root.columnCount === 1 ? 18 : 24
                spacing: 14

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 12

                    Text {
                        text: Icons.keyboard
                        font.family: Icons.font
                        font.pixelSize: Styling.fontSize(5)
                        color: Styling.srItem("overprimary")
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 1

                        Text {
                            text: "Atajos de teclado"
                            font.family: Config.theme.font
                            font.pixelSize: Styling.fontSize(4)
                            font.weight: Font.Bold
                            color: Colors.overSurface
                        }

                        Text {
                            text: root.shortcutCount > 0 ? `${root.shortcutCount} acciones activas` : "Referencia de solo lectura"
                            font.family: Config.theme.font
                            font.pixelSize: Styling.fontSize(-2)
                            color: Colors.overSurfaceVariant
                        }
                    }

                    Text {
                        text: "Esc para cerrar"
                        font.family: Config.theme.font
                        font.pixelSize: Styling.fontSize(-2)
                        color: Colors.outline
                        Layout.alignment: Qt.AlignTop
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 1
                    color: Colors.outline
                    opacity: 0.28
                }

                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    Flickable {
                        id: shortcutsFlickable
                        anchors.fill: parent
                        visible: root.dataError === "" && root.shortcutCount > 0
                        clip: true
                        interactive: true
                        boundsBehavior: Flickable.StopAtBounds
                        contentWidth: width
                        contentHeight: sectionsGrid.implicitHeight

                        ScrollBar.vertical: ScrollBar {
                            policy: shortcutsFlickable.contentHeight > shortcutsFlickable.height ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff
                        }

                        GridLayout {
                            id: sectionsGrid
                            width: shortcutsFlickable.width - (shortcutsFlickable.contentHeight > shortcutsFlickable.height ? 12 : 0)
                            columns: root.columnCount
                            columnSpacing: 12
                            rowSpacing: 12

                            Repeater {
                                model: root.sections

                                delegate: StyledRect {
                                    id: sectionCard
                                    required property var modelData

                                    Layout.fillWidth: true
                                    Layout.alignment: Qt.AlignTop
                                    implicitHeight: sectionContent.implicitHeight + 28
                                    variant: "internalbg"
                                    radius: Styling.radius(4)

                                    ColumnLayout {
                                        id: sectionContent
                                        anchors.left: parent.left
                                        anchors.right: parent.right
                                        anchors.top: parent.top
                                        anchors.margins: 14
                                        spacing: 9

                                        RowLayout {
                                            Layout.fillWidth: true
                                            spacing: 8

                                            Text {
                                                text: root.sectionIcon(sectionCard.modelData.id)
                                                font.family: Icons.font
                                                font.pixelSize: Styling.fontSize(1)
                                                color: Styling.srItem("overprimary")
                                            }

                                            Text {
                                                Layout.fillWidth: true
                                                text: sectionCard.modelData.title
                                                font.family: Config.theme.font
                                                font.pixelSize: Styling.fontSize(0)
                                                font.weight: Font.DemiBold
                                                color: Colors.overSurface
                                                wrapMode: Text.WordWrap
                                            }
                                        }

                                        Rectangle {
                                            Layout.fillWidth: true
                                            Layout.preferredHeight: 1
                                            color: Colors.outline
                                            opacity: 0.18
                                        }

                                        Repeater {
                                            model: sectionCard.modelData.rows

                                            delegate: Item {
                                                id: shortcutRow
                                                required property var modelData
                                                required property int index

                                                Layout.fillWidth: true
                                                implicitHeight: Math.max(keyColumn.implicitHeight, actionLabel.implicitHeight) + 8

                                                ColumnLayout {
                                                    id: keyColumn
                                                    anchors.left: parent.left
                                                    anchors.top: parent.top
                                                    width: Math.min(shortcutRow.width * 0.62, root.columnCount === 1 ? 360 : 230)
                                                    spacing: 4

                                                    Repeater {
                                                        model: shortcutRow.modelData.combos

                                                        delegate: StyledRect {
                                                            id: keyPill
                                                            required property var modelData

                                                            Layout.maximumWidth: keyColumn.width
                                                            Layout.preferredWidth: Math.min(keyColumn.width, keyText.implicitWidth + 18)
                                                            Layout.preferredHeight: Math.max(27, keyText.implicitHeight + 10)
                                                            variant: "common"
                                                            radius: Styling.radius(-4)

                                                            Text {
                                                                id: keyText
                                                                anchors.left: parent.left
                                                                anchors.right: parent.right
                                                                anchors.verticalCenter: parent.verticalCenter
                                                                anchors.leftMargin: 9
                                                                anchors.rightMargin: 9
                                                                text: keyPill.modelData.text
                                                                font.family: Config.theme.font
                                                                font.pixelSize: Styling.fontSize(-3)
                                                                font.weight: Font.DemiBold
                                                                color: keyPill.item
                                                                wrapMode: Text.Wrap
                                                                horizontalAlignment: Text.AlignHCenter
                                                            }
                                                        }
                                                    }
                                                }

                                                Text {
                                                    id: actionLabel
                                                    anchors.left: keyColumn.right
                                                    anchors.leftMargin: 10
                                                    anchors.right: parent.right
                                                    anchors.top: parent.top
                                                    anchors.topMargin: 5
                                                    text: shortcutRow.modelData.label
                                                    font.family: Config.theme.font
                                                    font.pixelSize: Styling.fontSize(-2)
                                                    color: Colors.overSurfaceVariant
                                                    wrapMode: Text.WordWrap
                                                }

                                                Rectangle {
                                                    anchors.left: parent.left
                                                    anchors.right: parent.right
                                                    anchors.bottom: parent.bottom
                                                    height: 1
                                                    visible: shortcutRow.index < sectionCard.modelData.rows.length - 1
                                                    color: Colors.outline
                                                    opacity: 0.1
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    ColumnLayout {
                        anchors.centerIn: parent
                        width: Math.min(parent.width - 32, 460)
                        visible: root.dataError !== "" || root.shortcutCount === 0
                        spacing: 12

                        Text {
                            Layout.alignment: Qt.AlignHCenter
                            text: root.dataError !== "" ? Icons.alert : Icons.keyboard
                            font.family: Icons.font
                            font.pixelSize: Styling.fontSize(8)
                            color: root.dataError !== "" ? Colors.error : Styling.srItem("overprimary")
                        }

                        Text {
                            Layout.fillWidth: true
                            text: root.dataError !== "" ? root.dataError : "No hay atajos activos para mostrar."
                            font.family: Config.theme.font
                            font.pixelSize: Styling.fontSize(0)
                            color: Colors.overSurfaceVariant
                            wrapMode: Text.WordWrap
                            horizontalAlignment: Text.AlignHCenter
                        }
                    }
                }
            }
        }
    }

    Shortcut {
        enabled: root.shortcutsOpen
        sequence: "Escape"
        context: Qt.ApplicationShortcut
        onActivated: root.close()
    }

    Connections {
        target: Config.keybindsLoader
        enabled: root.shortcutsOpen

        function onLoaded() {
            Qt.callLater(root.refreshData);
        }

        function onFileChanged() {
            Qt.callLater(root.refreshData);
        }

        function onAdapterUpdated() {
            Qt.callLater(root.refreshData);
        }
    }

    Connections {
        target: GlobalStates
        enabled: root.shortcutsOpen

        function onCompositorLayoutChanged() {
            root.refreshData();
        }
    }

    onShortcutsOpenChanged: {
        if (shortcutsOpen) {
            refreshData();
            Qt.callLater(() => focusScope.forceActiveFocus());
        }
    }

    Component.onCompleted: {
        if (shortcutsOpen) {
            refreshData();
            Qt.callLater(() => focusScope.forceActiveFocus());
        }
    }
}

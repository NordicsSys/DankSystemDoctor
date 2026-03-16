import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Widgets

Column {
    id: root

    // Slightly tighter vertical rhythm for better density
    spacing: Theme.spacingXS

    // --- Status pill: Healthy / Warning / Critical with reason ---
    component StatusPill: Rectangle {
        id: pill
        property string status: "Healthy"   // Healthy | Warning | Critical
        property string reason: ""
        implicitHeight: reason ? reasonRow.implicitHeight + Theme.spacingS * 2 : 36
        radius: Theme.cornerRadius
        color: {
            if (pill.status === "Critical") return Qt.rgba(0.96, 0.26, 0.21, 0.15);
            if (pill.status === "Warning") return Qt.rgba(1, 0.6, 0, 0.15);
            return Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.15);
        }
        Row {
            id: mainRow
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: Theme.spacingS
            height: 32
            spacing: Theme.spacingS
            DankIcon {
                name: pill.status === "Critical" ? "dangerous" : (pill.status === "Warning" ? "warning" : "monitor_heart")
                color: pill.status === "Critical" ? "#F44336" : (pill.status === "Warning" ? "#FF9800" : Theme.primary)
                size: 18
                anchors.verticalCenter: parent.verticalCenter
            }
            StyledText {
                text: pill.status + (pill.reason ? " — " + pill.reason : "")
                font.pixelSize: Theme.fontSizeSmall
                font.weight: Font.DemiBold
                color: pill.status === "Critical" ? "#F44336" : (pill.status === "Warning" ? "#FF9800" : Theme.primary)
                elide: Text.ElideRight
                width: parent.width - 26 - Theme.spacingS
                anchors.verticalCenter: parent.verticalCenter
            }
        }
            StyledText {
            id: reasonRow
            visible: pill.reason.length > 0
            anchors.top: mainRow.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.margins: Theme.spacingXS
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.surfaceVariantText
            text: pill.reason
            wrapMode: Text.WordWrap
            width: parent.width - Theme.spacingS * 2
        }
    }

    // --- Inline metric card component (fixed min height so grid rows don't overlap) ---
    component MetricCard: Rectangle {
        id: card

        property string label: ""
        property string icon: ""
        property real value: 0
        property int threshold: 85
        property string unit: "%"
        property string subtitle: ""

        readonly property color cardColor: {
            if (value >= threshold + 10) return "#F44336";
            if (value >= threshold - 10) return "#FF9800";
            return Theme.primary;
        }

        Layout.fillWidth: true
        Layout.fillHeight: true
        Layout.minimumHeight: 100
        Layout.preferredHeight: 100
        implicitHeight: 100
        radius: Theme.cornerRadius
        color: Theme.surfaceContainerHigh
        clip: true

        Column {
            anchors.fill: parent
            anchors.margins: Theme.spacingS
            spacing: Theme.spacingXS

            Row {
                width: parent.width
                height: 20
                spacing: Theme.spacingXS
                clip: true

                DankIcon {
                    name: card.icon
                    color: card.cardColor
                    size: 14
                    anchors.verticalCenter: parent.verticalCenter
                }
                StyledText {
                    text: card.label
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.surfaceVariantText
                    elide: Text.ElideRight
                    width: parent.width - 14 - Theme.spacingXS
                    anchors.verticalCenter: parent.verticalCenter
                }
            }

            StyledText {
                text: card.value.toFixed(0) + card.unit
                font.pixelSize: 18
                font.weight: Font.Bold
                color: card.cardColor
                width: parent.width
                elide: Text.ElideRight
            }

            Rectangle {
                width: parent.width
                height: 4
                radius: 2
                color: Theme.surfaceVariant

                Rectangle {
                    width: Math.min(parent.width, parent.width * (card.value / 100))
                    height: parent.height
                    radius: parent.radius
                    color: card.cardColor

                    Behavior on width {
                        NumberAnimation { duration: 400; easing.type: Easing.OutCubic }
                    }
                }
            }

            StyledText {
                text: card.subtitle
                visible: card.subtitle.length > 0
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.surfaceVariantText
                elide: Text.ElideRight
                width: parent.width
                maximumLineCount: 1
            }
        }
    }

    // --- Tab bar ---
    DankTabBar {
        id: tabBar
        width: parent.width - Theme.spacingS * 2
        anchors.horizontalCenter: parent.horizontalCenter
        currentIndex: 0
        model: [
            { text: "Overview",  icon: "monitor_heart" },
            { text: "Processes", icon: "memory"         },
            { text: "Logs",      icon: "article"        },
            { text: "Update & Care", icon: "system_update" },
            { text: "AI Doctor", icon: "smart_toy"      }
        ]
        onTabClicked: index => { tabBar.currentIndex = index; }
    }

    // ─────────────────────────────────────────────
    // TAB 0 — Overview (compact quick-glance + expandable detail)
    // ─────────────────────────────────────────────
    Item {
        visible: tabBar.currentIndex === 0
        width: parent.width
        height: parent.height - tabBar.height - Theme.spacingS * 2

        ColumnLayout {
            id: overviewColumn
            anchors.fill: parent
            anchors.margins: Theme.spacingS
            spacing: Theme.spacingS
            property bool overviewExpanded: true

            // Compact view toggle
            Row {
                Layout.fillWidth: true
                spacing: Theme.spacingS
                StyledText {
                    text: "Quick view"
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.surfaceVariantText
                    anchors.verticalCenter: parent.verticalCenter
                }
                Item { width: 4; height: 1 }
                Rectangle {
                    width: 36
                    height: 20
                    radius: 10
                    color: overviewColumn.overviewExpanded ? Theme.primary : Theme.surfaceVariant
                    anchors.verticalCenter: parent.verticalCenter
                    Rectangle {
                        width: 16
                        height: 16
                        radius: 8
                        anchors.verticalCenter: parent.verticalCenter
                        x: overviewColumn.overviewExpanded ? parent.width - width - 2 : 2
                        color: "white"
                        Behavior on x { NumberAnimation { duration: 150 } }
                    }
                    TapHandler {
                        onTapped: overviewColumn.overviewExpanded = !overviewColumn.overviewExpanded
                    }
                }
                StyledText {
                    text: "Detail"
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.surfaceVariantText
                    anchors.verticalCenter: parent.verticalCenter
                }
            }

            // Status pill (Healthy/Warning/Critical with reason; "Many log errors" hidden per request)
            StatusPill {
                Layout.fillWidth: true
                status: SystemDoctorService.healthLabel
                reason: {
                    var r = SystemDoctorService.healthReason.replace(/,\s*Many log errors|Many log errors\s*,?|Many log errors/g, "").replace(/^[\s,]+|[\s,]+$/g, "");
                    return r;
                }
            }

            // Compact gauges row (always visible)
            Row {
                Layout.fillWidth: true
                spacing: Theme.spacingS
                Repeater {
                    model: [
                        { label: "CPU", value: SystemDoctorService.cpuPct, icon: "memory" },
                        { label: "RAM", value: SystemDoctorService.ramPct, icon: "storage" },
                        { label: "Disk", value: SystemDoctorService.diskPct, icon: "hard_drive" }
                    ]
                    Rectangle {
                        width: (parent.width - Theme.spacingS * 2) / 3 - Theme.spacingS
                        height: 48
                        radius: Theme.cornerRadius
                        color: Theme.surfaceContainerHigh
                        Column {
                            anchors.centerIn: parent
                            spacing: 4
                            DankIcon {
                                name: modelData.icon
                                size: 24
                                color: modelData.value > 85 ? "#F44336" : (modelData.value > 70 ? "#FF9800" : Theme.primary)
                                anchors.horizontalCenter: parent.horizontalCenter
                            }
                            StyledText {
                                text: modelData.value.toFixed(0) + "%"
                                font.pixelSize: Theme.fontSizeSmall
                                font.weight: Font.DemiBold
                                color: Theme.surfaceText
                                anchors.horizontalCenter: parent.horizontalCenter
                            }
                        }
                    }
                }
            }

            // Expanded detail: metric cards fill remaining space (no empty gap)
            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.minimumHeight: 0
                visible: overviewColumn.overviewExpanded

                GridLayout {
                    anchors.fill: parent
                    columns: 2
                    columnSpacing: Theme.spacingS
                    rowSpacing: Theme.spacingS

                    MetricCard {
                        label: "CPU Usage"
                        icon: "memory"
                        value: SystemDoctorService.cpuPct
                        threshold: SystemDoctorService.cpuThreshold
                        subtitle: "Threshold: " + SystemDoctorService.cpuThreshold + "%"
                    }

                    MetricCard {
                        label: "RAM Usage"
                        icon: "storage"
                        value: SystemDoctorService.ramPct
                        threshold: SystemDoctorService.ramThreshold
                        subtitle: SystemDoctorService.formatMb(SystemDoctorService.ramUsedMb)
                                  + " / " + SystemDoctorService.formatMb(SystemDoctorService.ramTotalMb)
                    }

                    MetricCard {
                        label: "Disk ( / )"
                        icon: "hard_drive"
                        value: SystemDoctorService.diskPct
                        threshold: SystemDoctorService.diskThreshold
                        subtitle: "Threshold: " + SystemDoctorService.diskThreshold + "%"
                    }

                    MetricCard {
                        label: "Temperature"
                        icon: "thermostat"
                        value: SystemDoctorService.tempC > 0 ? SystemDoctorService.tempC : 0
                        threshold: 80
                        unit: "°C"
                        subtitle: SystemDoctorService.tempC < 0 ? "No sensor data" : ""
                    }

                    MetricCard {
                        visible: SystemDoctorService.gpuAvailable
                        Layout.columnSpan: 2
                        label: "GPU"
                        icon: "videocam"
                        value: SystemDoctorService.gpuPct
                        threshold: 90
                        subtitle: "VRAM " + SystemDoctorService.gpuVramUsedMb + " / " + SystemDoctorService.gpuVramTotalMb + " MiB"
                              + (SystemDoctorService.gpuTempC > 0 ? "  ·  " + SystemDoctorService.gpuTempC + "°C" : "")
                    }
                }
            }
        }
    }

    // ─────────────────────────────────────────────
    // TAB 1 — Processes
    // ─────────────────────────────────────────────
    Item {
        visible: tabBar.currentIndex === 1
        width: parent.width
        height: parent.height - tabBar.height - Theme.spacingS * 2

        Column {
            anchors.fill: parent
            anchors.margins: Theme.spacingS
            spacing: Theme.spacingS

            // Header row
            Row {
                width: parent.width
                height: 24
                spacing: 0

                StyledText {
                    width: parent.width * 0.38
                    text: "Command"
                    font.pixelSize: Theme.fontSizeSmall
                    font.weight: Font.DemiBold
                    color: Theme.surfaceVariantText
                }
                StyledText {
                    width: parent.width * 0.15
                    text: "PID"
                    font.pixelSize: Theme.fontSizeSmall
                    font.weight: Font.DemiBold
                    color: Theme.surfaceVariantText
                }
                StyledText {
                    width: parent.width * 0.22
                    text: "CPU %"
                    font.pixelSize: Theme.fontSizeSmall
                    font.weight: Font.DemiBold
                    color: Theme.surfaceVariantText
                }
                StyledText {
                    width: parent.width * 0.15
                    text: "RAM %"
                    font.pixelSize: Theme.fontSizeSmall
                    font.weight: Font.DemiBold
                    color: Theme.surfaceVariantText
                }
                StyledText {
                    width: parent.width * 0.10
                    text: "User"
                    font.pixelSize: Theme.fontSizeSmall
                    font.weight: Font.DemiBold
                    color: Theme.surfaceVariantText
                }
            }

            Rectangle {
                width: parent.width
                height: 1
                color: Theme.surfaceVariant
            }

            Flickable {
                width: parent.width
                height: parent.height - 25 - Theme.spacingS - 1
                contentHeight: procColumn.implicitHeight
                clip: true

                Column {
                    id: procColumn
                    width: parent.width
                    spacing: 1

                    Repeater {
                        model: SystemDoctorService.topProcs

                        Rectangle {
                            id: procRow
                            required property var modelData
                            required property int index

                            width: procColumn.width
                            height: 30
                            radius: 4
                            color: index % 2 === 0 ? "transparent" : Qt.rgba(Theme.surfaceVariant.r, Theme.surfaceVariant.g, Theme.surfaceVariant.b, 0.3)

                            Row {
                                anchors.fill: parent
                                anchors.leftMargin: 4
                                anchors.rightMargin: 4
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 0

                                StyledText {
                                    width: parent.width * 0.38
                                    text: procRow.modelData.cmd
                                    font.pixelSize: Theme.fontSizeSmall
                                    color: Theme.surfaceText
                                    elide: Text.ElideRight
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                                StyledText {
                                    width: parent.width * 0.15
                                    text: procRow.modelData.pid
                                    font.pixelSize: Theme.fontSizeSmall
                                    color: Theme.surfaceVariantText
                                    anchors.verticalCenter: parent.verticalCenter
                                }

                                // CPU bar + value
                                Item {
                                    width: parent.width * 0.22
                                    height: parent.height
                                    anchors.verticalCenter: parent.verticalCenter

                                    Row {
                                        anchors.verticalCenter: parent.verticalCenter
                                        spacing: Theme.spacingXS

                                        Rectangle {
                                            width: 60
                                            height: 6
                                            radius: 3
                                            color: Theme.surfaceVariant
                                            anchors.verticalCenter: parent.verticalCenter

                                            Rectangle {
                                                width: Math.min(parent.width, parent.width * (procRow.modelData.cpu / 100))
                                                height: parent.height
                                                radius: parent.radius
                                                color: procRow.modelData.cpu > 50 ? "#F44336" : procRow.modelData.cpu > 25 ? "#FF9800" : Theme.primary
                                            }
                                        }

                                        StyledText {
                                            text: procRow.modelData.cpu.toFixed(1)
                                            font.pixelSize: Theme.fontSizeSmall
                                            color: Theme.surfaceText
                                            anchors.verticalCenter: parent.verticalCenter
                                        }
                                    }
                                }

                                StyledText {
                                    width: parent.width * 0.15
                                    text: procRow.modelData.mem.toFixed(1)
                                    font.pixelSize: Theme.fontSizeSmall
                                    color: Theme.surfaceVariantText
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                                StyledText {
                                    width: parent.width * 0.10
                                    text: procRow.modelData.user
                                    font.pixelSize: Theme.fontSizeSmall
                                    color: Theme.surfaceVariantText
                                    elide: Text.ElideRight
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // ─────────────────────────────────────────────
    // TAB 2 — Logs
    // ─────────────────────────────────────────────
    Item {
        visible: tabBar.currentIndex === 2
        width: parent.width
        height: parent.height - tabBar.height - Theme.spacingS * 2

        Column {
            anchors.fill: parent
            anchors.margins: Theme.spacingS
            spacing: Theme.spacingS

            Row {
                width: parent.width
                spacing: Theme.spacingS

                DankIcon {
                    name: "article"
                    color: SystemDoctorService.logErrors.length > 0 ? "#FF9800" : Theme.primary
                    size: 18
                    anchors.verticalCenter: parent.verticalCenter
                }

                StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    text: SystemDoctorService.logErrors.length > 0
                          ? SystemDoctorService.logErrors.length + " error entries (journalctl -p err)"
                          : "No errors found in recent journal"
                    font.pixelSize: Theme.fontSizeMedium
                    font.weight: Font.DemiBold
                    color: SystemDoctorService.logErrors.length > 0 ? "#FF9800" : Theme.primary
                }
            }

            Rectangle {
                width: parent.width
                height: 1
                color: Theme.surfaceVariant
            }

            Flickable {
                width: parent.width
                height: parent.height - 20 - Theme.spacingS * 2 - 1
                contentHeight: logColumn.implicitHeight
                clip: true

                Column {
                    id: logColumn
                    width: parent.width
                    spacing: 1

                    Repeater {
                        model: SystemDoctorService.logErrors

                        Rectangle {
                            id: logEntry
                            required property string modelData
                            required property int index

                            width: logColumn.width
                            height: logText.implicitHeight + Theme.spacingXS * 2
                            radius: 4
                            color: index % 2 === 0 ? "transparent"
                                                   : Qt.rgba(Theme.surfaceVariant.r, Theme.surfaceVariant.g, Theme.surfaceVariant.b, 0.3)

                            StyledText {
                                id: logText
                                text: logEntry.modelData
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.top: parent.top
                                anchors.margins: Theme.spacingXS
                                font.pixelSize: 11
                                font.family: "monospace"
                                color: Theme.surfaceText
                                wrapMode: Text.WrapAnywhere
                            }
                        }
                    }

                    Rectangle {
                        width: parent.width
                        height: SystemDoctorService.logErrors.length === 0 ? 60 : 0
                        visible: SystemDoctorService.logErrors.length === 0
                        color: "transparent"

                        StyledText {
                            anchors.centerIn: parent
                            text: "No recent errors"
                            color: Theme.surfaceVariantText
                            font.pixelSize: Theme.fontSizeSmall
                        }
                    }
                }
            }
        }
    }

    // ─────────────────────────────────────────────
    // TAB 3 — Update & Care (action drawer: Update, Clean, Diagnose)
    // ─────────────────────────────────────────────
    Item {
        visible: tabBar.currentIndex === 3
        width: parent.width
        height: parent.height - tabBar.height - Theme.spacingS * 2

        Flickable {
            anchors.fill: parent
            anchors.margins: Theme.spacingS
            contentHeight: updateCareColumn.implicitHeight
            clip: true

            Column {
                id: updateCareColumn
                width: parent.width - Theme.spacingS * 2
                spacing: Theme.spacingM

                // — Update now —
                Rectangle {
                    width: parent.width
                    radius: Theme.cornerRadius
                    color: Theme.surfaceContainerHigh
                    height: updateSectionColumn.implicitHeight + Theme.spacingM * 2

                    Column {
                        id: updateSectionColumn
                        anchors.fill: parent
                        anchors.margins: Theme.spacingM
                        spacing: Theme.spacingS

                        Row {
                            width: parent.width - Theme.spacingM * 2
                            spacing: Theme.spacingS
                            DankIcon { name: "system_update"; color: Theme.primary; size: 20; anchors.verticalCenter: parent.verticalCenter }
                            StyledText {
                                text: "Updates"
                                font.pixelSize: Theme.fontSizeMedium
                                font.weight: Font.DemiBold
                                color: Theme.surfaceText
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }
                        StyledText {
                            visible: SystemDoctorService.updateCount === 0 && !SystemDoctorService.updateInProgress
                            text: "No pending updates (" + (SystemDoctorService.updateManager || "none") + ")."
                            font.pixelSize: Theme.fontSizeSmall
                            color: Theme.surfaceVariantText
                            width: parent.width - Theme.spacingM * 2
                        }
                        StyledText {
                            visible: SystemDoctorService.updateCount > 0
                            text: SystemDoctorService.updateCount + " pending (" + (SystemDoctorService.updateManager || "")
                                  + (SystemDoctorService.updateSecurity > 0 ? ", " + SystemDoctorService.updateSecurity + " security" : "")
                                  + ") · ETA " + SystemDoctorService.updateEtaLabel
                            font.pixelSize: Theme.fontSizeSmall
                            color: Theme.surfaceVariantText
                            width: parent.width - Theme.spacingM * 2
                        }
                        Row {
                            visible: SystemDoctorService.updateInProgress
                            width: parent.width - Theme.spacingM * 2
                            spacing: Theme.spacingS
                            Rectangle {
                                width: 120
                                height: 6
                                radius: 3
                                color: Theme.surfaceVariant
                                anchors.verticalCenter: parent.verticalCenter
                                Rectangle {
                                    width: parent.width * (SystemDoctorService.updateProgressPct / 100)
                                    height: parent.height
                                    radius: parent.radius
                                    color: Theme.primary
                                }
                            }
                            StyledText {
                                text: SystemDoctorService.updateProgressLabel
                                font.pixelSize: Theme.fontSizeSmall
                                color: Theme.surfaceText
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }
                        Row {
                            visible: SystemDoctorService.updateCount > 0 && !SystemDoctorService.updateInProgress
                            spacing: Theme.spacingS
                            DankButton {
                                text: "Create snapshot first"
                                iconName: "save"
                                height: 32
                                onClicked: SystemDoctorService.runUpdateNow(true)
                            }
                            DankButton {
                                text: "Update now"
                                iconName: "system_update"
                                height: 32
                                onClicked: SystemDoctorService.runUpdateNow(false)
                            }
                        }
                        StyledText {
                            visible: SystemDoctorService.updateCount > 0
                            text: "Rollback: if needed, use " + (SystemDoctorService.snapshotProvider === "timeshift" ? "Timeshift" : SystemDoctorService.snapshotProvider) + " to restore a snapshot."
                            font.pixelSize: 11
                            color: Theme.surfaceVariantText
                            width: parent.width - Theme.spacingM * 2
                            wrapMode: Text.WordWrap
                        }
                    }
                }

                // — Safe mode prechecks —
                Rectangle {
                    width: parent.width
                    height: precheckRow.implicitHeight + Theme.spacingS * 2
                    radius: Theme.cornerRadius
                    color: Theme.surfaceContainerHigh

                    Row {
                        id: precheckRow
                        anchors.centerIn: parent
                        spacing: Theme.spacingL
                        StyledText { text: "Free: " + SystemDoctorService.freeSpaceGb.toFixed(1) + " GB"; font.pixelSize: Theme.fontSizeSmall; color: Theme.surfaceVariantText }
                        StyledText { text: SystemDoctorService.onBattery ? "On battery" : "AC"; font.pixelSize: Theme.fontSizeSmall; color: Theme.surfaceVariantText }
                        StyledText {
                            text: SystemDoctorService.snapshotAvailable ? "Snapshot OK" : "No snapshot"
                            font.pixelSize: Theme.fontSizeSmall
                            color: SystemDoctorService.snapshotAvailable ? Theme.primary : "#FF9800"
                        }
                    }
                }

                // — Action drawer: Clean / Repair (grouped with risk badges) —
                StyledText {
                    text: "Maintenance"
                    font.pixelSize: Theme.fontSizeMedium
                    font.weight: Font.DemiBold
                    color: Theme.surfaceText
                }
                Repeater {
                    model: SystemDoctorService.maintenanceActions
                    delegate: Rectangle {
                        id: actionRow
                        required property var modelData
                        width: updateCareColumn.width
                        height: 36
                        radius: 6
                        color: Theme.surfaceContainerHigh
                        Row {
                            anchors.fill: parent
                            anchors.margins: Theme.spacingS
                            spacing: Theme.spacingS
                            StyledText {
                                text: actionRow.modelData.group + ":"
                                font.pixelSize: Theme.fontSizeSmall
                                color: Theme.surfaceVariantText
                                width: 52
                                anchors.verticalCenter: parent.verticalCenter
                            }
                            StyledText {
                                text: actionRow.modelData.label
                                font.pixelSize: Theme.fontSizeSmall
                                color: Theme.surfaceText
                                elide: Text.ElideRight
                                width: parent.width - 52 - 50 - 70 - Theme.spacingS * 4
                                anchors.verticalCenter: parent.verticalCenter
                            }
                            StyledText {
                                text: actionRow.modelData.risk === "requires_network" ? "Network" : "Safe"
                                font.pixelSize: 10
                                color: actionRow.modelData.risk === "requires_network" ? "#FF9800" : Theme.primary
                                width: 50
                                anchors.verticalCenter: parent.verticalCenter
                            }
                            DankButton {
                                text: "Run"
                                iconName: "play_arrow"
                                height: 28
                                anchors.verticalCenter: parent.verticalCenter
                                onClicked: SystemDoctorService.runMaintenanceAction(actionRow.modelData.id, false)
                            }
                        }
                    }
                }
            }
        }
    }

    // ─────────────────────────────────────────────
    // TAB 4 — AI Doctor
    // ─────────────────────────────────────────────
    AiPanel {
        visible: tabBar.currentIndex === 4
        width: parent.width
        height: parent.height - tabBar.height - Theme.spacingS * 2
    }

    Connections {
        target: SystemDoctorService
        function onUpdateFinished(success, message) {
            if (typeof ToastService !== "undefined") {
                if (success) ToastService.showInfo("Updates", message);
                else ToastService.showError("Updates", message);
            }
        }
        function onMaintenanceFinished(actionId, success, message) {
            if (typeof ToastService !== "undefined") {
                if (success) ToastService.showInfo("Maintenance", actionId + ": done.");
                else ToastService.showError("Maintenance", message);
            }
        }
    }
}

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.plasmoid
import org.kde.plasma.plasma5support as P5Support

PlasmoidItem {
    id: root

    preferredRepresentation: compactRepresentation
    fullRepresentation: fullRep
    compactRepresentation: compactRep

    property var stacksList: []
    property bool isLoading: false
    property string lastError: ""
    property string activeLogStack: ""
    property string logContent: ""
    property bool isLoadingLogs: false

    // Action Loading State per Stack (contoh: {"simpeg": "start", "predika": "stop"})
    property var actionLoadingMap: ({})

    // Filter & Search State
    property string searchQuery: ""
    property string statusFilter: "active" // Default: hanya yang aktif ("active", "all", "exited")

    function getFilteredStacks() {
        if (!root.stacksList || root.stacksList.length === 0) return []
        var q = root.searchQuery.trim().toLowerCase()
        return root.stacksList.filter(function(stk) {
            // Status filter logic
            if (root.statusFilter === "active") {
                if (stk.running_containers === 0) return false
            } else if (root.statusFilter === "exited") {
                if (stk.running_containers > 0) return false
            }

            // Search query logic
            if (q.length > 0) {
                var nameMatch = stk.name && stk.name.toLowerCase().indexOf(q) !== -1
                return nameMatch
            }
            return true
        })
    }

    // Native Command Executor via Plasma DataSource
    P5Support.DataSource {
        id: cmdRunner
        engine: "executable"
        connectedSources: []

        onNewData: function(source, data) {
            var exitCode = data["exit code"]
            var stdout = data["stdout"] || ""
            var stderr = data["stderr"] || ""

            if (source.indexOf("docker compose ls --all --format json") !== -1) {
                root.isLoading = false
                if (exitCode === 0) {
                    try {
                        var raw = JSON.parse(stdout.trim())
                        var parsed = []
                        for (var i = 0; i < raw.length; i++) {
                            var item = raw[i]
                            var name = item.Name || "unknown"
                            var rawStatus = item.Status || ""

                            var running = 0
                            var exited = 0
                            var runMatch = rawStatus.match(/running\((\d+)\)/)
                            if (runMatch) running = parseInt(runMatch[1], 10)
                            var exitMatch = rawStatus.match(/exited\((\d+)\)/)
                            if (exitMatch) exited = parseInt(exitMatch[1], 10)

                            var total = running + exited
                            var st = "exited"
                            if (running === total && total > 0) st = "running"
                            else if (running > 0) st = "partial"

                            parsed.push({
                                name: name,
                                status: st,
                                total_containers: total,
                                running_containers: running,
                                raw_status: rawStatus,
                                config_files: item.ConfigFiles || ""
                            })
                        }
                        root.stacksList = parsed
                    } catch (e) {
                        root.lastError = "Invalid output format"
                    }
                } else {
                    root.lastError = stderr.trim() || "Failed to execute docker compose"
                }
            } else if (source.indexOf("logs --tail") !== -1) {
                root.isLoadingLogs = false
                root.logContent = stdout || stderr || "No logs available."
            } else {
                // Command start / stop / restart finished
                var match = source.match(/docker compose -p\s+([^\s]+)\s+([^\s]+)/)
                if (match) {
                    var sName = match[1]
                    var updated = Object.assign({}, root.actionLoadingMap)
                    delete updated[sName]
                    root.actionLoadingMap = updated
                }
                // Refresh stacks list
                root.fetchStacks()
            }

            disconnectSource(source)
        }
    }

    function runExec(cmd) {
        cmdRunner.connectSource(cmd)
    }

    function fetchStacks() {
        isLoading = true
        lastError = ""
        runExec("docker compose ls --all --format json")
    }

    function triggerStackAction(stackName, action) {
        // action: start | stop | restart
        var updated = Object.assign({}, root.actionLoadingMap)
        updated[stackName] = action
        root.actionLoadingMap = updated

        var cmd = "docker compose -p " + stackName + " " + action
        runExec(cmd)
    }

    function viewStackLogs(stackName) {
        root.activeLogStack = stackName
        root.isLoadingLogs = true
        root.logContent = "Fetching logs for stack " + stackName + "..."
        var cmd = "docker compose -p " + stackName + " logs --tail 200"
        runExec(cmd)
    }

    Timer {
        interval: 15000 // Polling otomatis tiap 15 detik
        running: true
        repeat: true
        onTriggered: root.fetchStacks()
    }

    Component.onCompleted: {
        root.fetchStacks()
    }

    // --- Compact Representation (Tampilan di Taskbar/Panel: Icon Only) ---
    Component {
        id: compactRep
        MouseArea {
            id: compactItem
            implicitWidth: 28
            implicitHeight: 28
            Layout.preferredWidth: 28
            Layout.fillHeight: true
            cursorShape: Qt.PointingHandCursor
            hoverEnabled: true

            onClicked: {
                root.expanded = !root.expanded
                if (root.expanded) {
                    root.activeLogStack = ""
                    root.fetchStacks()
                }
            }

            Image {
                anchors.centerIn: parent
                source: "../icons/docker.webp"
                width: 22
                height: 22
                fillMode: Image.PreserveAspectFit
                opacity: root.isLoading ? 0.6 : 1.0
            }
        }
    }

    // --- Full Representation (Popup / Flyout: Card per Stack) ---
    Component {
        id: fullRep
        Item {
            id: flyoutRoot
            implicitWidth: 460
            implicitHeight: 540

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 12
                spacing: 10

                // Header Top Bar
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    Image {
                        source: "../icons/docker.webp"
                        Layout.preferredWidth: 22
                        Layout.preferredHeight: 22
                        fillMode: Image.PreserveAspectFit
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 1

                        Text {
                            text: root.activeLogStack ? ("Logs: " + root.activeLogStack) : "Docker Stacks Controller"
                            font.bold: true
                            font.pixelSize: 13
                            color: Kirigami.Theme.textColor
                        }

                        Text {
                            text: root.activeLogStack ? "Press Back button to view all stacks" : (root.isLoading ? "Refreshing status..." : (root.lastError ? root.lastError : (root.stacksList.length + " Compose Stacks Detected")))
                            font.pixelSize: 10
                            color: root.lastError ? Kirigami.Theme.negativeTextColor : Kirigami.Theme.disabledTextColor
                        }
                    }

                    // Back button from Logs view
                    QQC2.Button {
                        visible: !!root.activeLogStack
                        text: "Back"
                        onClicked: root.activeLogStack = ""
                    }

                    QQC2.Button {
                        text: "🔄"
                        flat: true
                        Layout.preferredWidth: 28
                        Layout.preferredHeight: 28
                        onClicked: {
                            if (root.activeLogStack) {
                                root.viewStackLogs(root.activeLogStack)
                            } else {
                                root.fetchStacks()
                            }
                        }
                    }
                }

                // VIEW 1: Log Viewer (Jika sedang klik tombol Log di stack)
                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    visible: !!root.activeLogStack

                    Rectangle {
                        anchors.fill: parent
                        radius: 6
                        color: Qt.rgba(0.02, 0.04, 0.08, 0.95)
                        border.color: Qt.rgba(0.2, 0.25, 0.35, 0.4)

                        Flickable {
                            id: logFlickable
                            anchors.fill: parent
                            anchors.margins: 8
                            clip: true
                            contentWidth: width
                            contentHeight: logText.implicitHeight
                            boundsBehavior: Flickable.StopAtBounds

                            TextEdit {
                                id: logText
                                width: logFlickable.width
                                text: root.logContent
                                readOnly: true
                                selectByMouse: true
                                color: "#e2e8f0"
                                font.family: "monospace"
                                font.pixelSize: 10
                                wrapMode: TextEdit.Wrap

                                onTextChanged: {
                                    Qt.callLater(function() {
                                        logFlickable.contentY = Math.max(0, logFlickable.contentHeight - logFlickable.height)
                                        cursorPosition = length
                                    })
                                }
                            }

                            QQC2.ScrollBar.vertical: QQC2.ScrollBar {
                                active: true
                            }
                        }
                    }
                }

                // VIEW 2: Stack Cards List
                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    visible: !root.activeLogStack

                    ColumnLayout {
                        anchors.fill: parent
                        spacing: 8

                        // Search Input & Filter Tabs
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 6

                            // Search Field
                            Rectangle {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 30
                                radius: 4
                                color: Qt.rgba(0.04, 0.06, 0.12, 0.9)
                                border.color: searchInput.activeFocus ? Kirigami.Theme.highlightColor : Qt.rgba(0.2, 0.25, 0.35, 0.5)
                                border.width: 1

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 8
                                    anchors.rightMargin: 8
                                    spacing: 4

                                    Text {
                                        text: "🔍"
                                        font.pixelSize: 11
                                        opacity: 0.7
                                    }

                                    QQC2.TextField {
                                        id: searchInput
                                        Layout.fillWidth: true
                                        placeholderText: "Search stack name..."
                                        color: Kirigami.Theme.textColor
                                        font.pixelSize: 11
                                        background: null
                                        padding: 0
                                        onTextChanged: root.searchQuery = text
                                    }

                                    Text {
                                        text: "✕"
                                        font.pixelSize: 10
                                        color: Kirigami.Theme.disabledTextColor
                                        visible: searchInput.text.length > 0
                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                searchInput.text = ""
                                                root.searchQuery = ""
                                            }
                                        }
                                    }
                                }
                            }

                            // Filter Tabs: Active (Default) / All / Stopped
                            RowLayout {
                                spacing: 4

                                Rectangle {
                                    height: 28
                                    width: activeTabText.implicitWidth + 14
                                    radius: 4
                                    color: root.statusFilter === "active" ? Kirigami.Theme.highlightColor : Qt.rgba(0.1, 0.15, 0.25, 0.4)
                                    border.color: root.statusFilter === "active" ? "transparent" : Qt.rgba(0.2, 0.25, 0.35, 0.4)
                                    border.width: 1

                                    Text {
                                        id: activeTabText
                                        anchors.centerIn: parent
                                        text: "Active"
                                        font.pixelSize: 11
                                        font.bold: root.statusFilter === "active"
                                        color: root.statusFilter === "active" ? Kirigami.Theme.highlightedTextColor : Kirigami.Theme.textColor
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.statusFilter = "active"
                                    }
                                }

                                Rectangle {
                                    height: 28
                                    width: allTabText.implicitWidth + 14
                                    radius: 4
                                    color: root.statusFilter === "all" ? Kirigami.Theme.highlightColor : Qt.rgba(0.1, 0.15, 0.25, 0.4)
                                    border.color: root.statusFilter === "all" ? "transparent" : Qt.rgba(0.2, 0.25, 0.35, 0.4)
                                    border.width: 1

                                    Text {
                                        id: allTabText
                                        anchors.centerIn: parent
                                        text: "All"
                                        font.pixelSize: 11
                                        font.bold: root.statusFilter === "all"
                                        color: root.statusFilter === "all" ? Kirigami.Theme.highlightedTextColor : Kirigami.Theme.textColor
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.statusFilter = "all"
                                    }
                                }

                                Rectangle {
                                    height: 28
                                    width: exitedTabText.implicitWidth + 14
                                    radius: 4
                                    color: root.statusFilter === "exited" ? Kirigami.Theme.highlightColor : Qt.rgba(0.1, 0.15, 0.25, 0.4)
                                    border.color: root.statusFilter === "exited" ? "transparent" : Qt.rgba(0.2, 0.25, 0.35, 0.4)
                                    border.width: 1

                                    Text {
                                        id: exitedTabText
                                        anchors.centerIn: parent
                                        text: "Stopped"
                                        font.pixelSize: 11
                                        font.bold: root.statusFilter === "exited"
                                        color: root.statusFilter === "exited" ? Kirigami.Theme.highlightedTextColor : Kirigami.Theme.textColor
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.statusFilter = "exited"
                                    }
                                }
                            }
                        }

                        // Cards View
                        Item {
                            Layout.fillWidth: true
                            Layout.fillHeight: true

                            QQC2.ScrollView {
                                id: scrollView
                                anchors.fill: parent
                                clip: true

                                ListView {
                                    id: cardsList
                                    width: scrollView.availableWidth
                                    spacing: 8
                                    model: root.getFilteredStacks()

                                    delegate: Rectangle {
                                        width: cardsList.width
                                        implicitHeight: cardCol.implicitHeight + 16
                                        radius: 8
                                        color: Qt.rgba(0.06, 0.09, 0.16, 0.95)
                                        border.color: Qt.rgba(0.2, 0.25, 0.35, 0.5)
                                        border.width: 1

                                        ColumnLayout {
                                            id: cardCol
                                            anchors.fill: parent
                                            anchors.margins: 10
                                            spacing: 8

                                            // Stack Header: Name & Status Badge
                                            RowLayout {
                                                Layout.fillWidth: true
                                                spacing: 6

                                                Text {
                                                    text: modelData.name
                                                    font.pixelSize: 12
                                                    font.bold: true
                                                    color: Kirigami.Theme.textColor
                                                    Layout.fillWidth: true
                                                    elide: Text.ElideRight
                                                }

                                                Rectangle {
                                                    height: 18
                                                    width: statusText.implicitWidth + 10
                                                    radius: 4
                                                    color: {
                                                        if (modelData.status === "running") return Qt.rgba(0.06, 0.72, 0.51, 0.15)
                                                        if (modelData.status === "partial") return Qt.rgba(0.96, 0.62, 0.04, 0.15)
                                                        return Qt.rgba(0.95, 0.25, 0.37, 0.15)
                                                    }

                                                    Text {
                                                        id: statusText
                                                        anchors.centerIn: parent
                                                        text: modelData.running_containers + "/" + modelData.total_containers + " " + modelData.status.toUpperCase()
                                                        font.pixelSize: 9
                                                        font.bold: true
                                                        color: {
                                                            if (modelData.status === "running") return "#10b981"
                                                            if (modelData.status === "partial") return "#f59e0b"
                                                            return "#f43f5e"
                                                        }
                                                    }
                                                }
                                            }

                                            // Action Buttons: Start, Stop, Restart, Log (Icon Only, Fit Width, Justify End)
                                            RowLayout {
                                                Layout.fillWidth: true
                                                spacing: 6

                                                Item {
                                                    Layout.fillWidth: true // Spacer untuk push semua tombol ke kanan (justify-end)
                                                }

                                                // Loading Indicator / Status Text saat aksi berlangsung
                                                RowLayout {
                                                    visible: !!root.actionLoadingMap[modelData.name]
                                                    spacing: 4

                                                    QQC2.BusyIndicator {
                                                        Layout.preferredWidth: 18
                                                        Layout.preferredHeight: 18
                                                        running: !!root.actionLoadingMap[modelData.name]
                                                    }

                                                    Text {
                                                        text: {
                                                            var act = root.actionLoadingMap[modelData.name]
                                                            if (act === "start") return "Starting..."
                                                            if (act === "stop") return "Stopping..."
                                                            if (act === "restart") return "Restarting..."
                                                            return "Loading..."
                                                        }
                                                        font.pixelSize: 10
                                                        color: Kirigami.Theme.disabledTextColor
                                                    }
                                                }

                                                // Start Button
                                                Rectangle {
                                                    Layout.preferredWidth: 28
                                                    Layout.preferredHeight: 28
                                                    radius: 4
                                                    color: (modelData.status === "running" || !!root.actionLoadingMap[modelData.name]) ? Qt.rgba(0.1, 0.15, 0.25, 0.3) : Qt.rgba(0.06, 0.72, 0.51, 0.2)
                                                    border.color: (modelData.status === "running" || !!root.actionLoadingMap[modelData.name]) ? "transparent" : "#10b981"
                                                    border.width: 1

                                                    Text {
                                                        anchors.centerIn: parent
                                                        text: "▶"
                                                        font.pixelSize: 11
                                                        color: (modelData.status === "running" || !!root.actionLoadingMap[modelData.name]) ? Kirigami.Theme.disabledTextColor : "#10b981"
                                                    }

                                                    MouseArea {
                                                        anchors.fill: parent
                                                        cursorShape: Qt.PointingHandCursor
                                                        enabled: modelData.status !== "running" && !root.actionLoadingMap[modelData.name]
                                                        onClicked: root.triggerStackAction(modelData.name, "start")
                                                    }
                                                }

                                                // Stop Button
                                                Rectangle {
                                                    Layout.preferredWidth: 28
                                                    Layout.preferredHeight: 28
                                                    radius: 4
                                                    color: (modelData.running_containers === 0 || !!root.actionLoadingMap[modelData.name]) ? Qt.rgba(0.1, 0.15, 0.25, 0.3) : Qt.rgba(0.95, 0.25, 0.37, 0.2)
                                                    border.color: (modelData.running_containers === 0 || !!root.actionLoadingMap[modelData.name]) ? "transparent" : "#f43f5e"
                                                    border.width: 1

                                                    Text {
                                                        anchors.centerIn: parent
                                                        text: "■"
                                                        font.pixelSize: 11
                                                        color: (modelData.running_containers === 0 || !!root.actionLoadingMap[modelData.name]) ? Kirigami.Theme.disabledTextColor : "#f43f5e"
                                                    }

                                                    MouseArea {
                                                        anchors.fill: parent
                                                        cursorShape: Qt.PointingHandCursor
                                                        enabled: modelData.running_containers > 0 && !root.actionLoadingMap[modelData.name]
                                                        onClicked: root.triggerStackAction(modelData.name, "stop")
                                                    }
                                                }

                                                // Restart Button
                                                Rectangle {
                                                    Layout.preferredWidth: 28
                                                    Layout.preferredHeight: 28
                                                    radius: 4
                                                    color: !!root.actionLoadingMap[modelData.name] ? Qt.rgba(0.1, 0.15, 0.25, 0.3) : Qt.rgba(0.96, 0.62, 0.04, 0.2)
                                                    border.color: !!root.actionLoadingMap[modelData.name] ? "transparent" : "#f59e0b"
                                                    border.width: 1

                                                    Text {
                                                        anchors.centerIn: parent
                                                        text: "⟳"
                                                        font.pixelSize: 13
                                                        font.bold: true
                                                        color: !!root.actionLoadingMap[modelData.name] ? Kirigami.Theme.disabledTextColor : "#f59e0b"
                                                    }

                                                    MouseArea {
                                                        anchors.fill: parent
                                                        cursorShape: Qt.PointingHandCursor
                                                        enabled: !root.actionLoadingMap[modelData.name]
                                                        onClicked: root.triggerStackAction(modelData.name, "restart")
                                                    }
                                                }

                                                // Log Button
                                                Rectangle {
                                                    Layout.preferredWidth: 28
                                                    Layout.preferredHeight: 28
                                                    radius: 4
                                                    color: Qt.rgba(0.2, 0.25, 0.35, 0.3)
                                                    border.color: Qt.rgba(0.4, 0.45, 0.55, 0.4)
                                                    border.width: 1

                                                    Text {
                                                        anchors.centerIn: parent
                                                        text: "📄"
                                                        font.pixelSize: 11
                                                        color: Kirigami.Theme.textColor
                                                    }

                                                    MouseArea {
                                                        anchors.fill: parent
                                                        cursorShape: Qt.PointingHandCursor
                                                        onClicked: root.viewStackLogs(modelData.name)
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }

                            // Empty / No Results State
                            Text {
                                anchors.centerIn: parent
                                visible: root.getFilteredStacks().length === 0 && !root.isLoading
                                text: root.searchQuery ? "No stacks matching your search" : "No active stacks currently running"
                                color: Kirigami.Theme.disabledTextColor
                                font.pixelSize: 12
                            }
                        }
                    }
                }
            }
        }
    }
}

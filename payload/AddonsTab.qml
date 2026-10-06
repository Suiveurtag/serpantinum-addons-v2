import QtQuick
import QtQuick.Layouts
import Quickshell
import "../"
import "../reusables"
import "../reusables/guide"

Item {
    id: root
    required property var rootObj
    required property int tabIndex
    anchors.fill: parent
    visible: rootObj.currentTab === tabIndex
    opacity: visible ? 1 : 0
    property real slideY: visible ? 0 : rootObj.s(10)
    Behavior on slideY { NumberAnimation { duration: 250; easing.type: Easing.OutQuart } }
    transform: Translate { y: root.slideY }
    Behavior on opacity { NumberAnimation { duration: 250 } }
    Flickable {
        anchors.fill: parent; anchors.margins: rootObj.s(24); contentWidth: width; contentHeight: settings.implicitHeight; clip: true
        ColumnLayout {
            id: settings; width: parent.width; spacing: rootObj.s(14)
            SettingsRow {
                rootObj: root.rootObj; settingId: "addons_legacy_clock"; searchTab: "addons"; searchKeywords: "calendar clock legacy horloge calendrier"
                title: "Legacy clock design"; description: "Restore the v1 calendar and clock panel."; icon: "󰥔"
                Toggle {
                    checked: Config.getSetting("addonsV2LegacyClock", false)
                    accentColor: ThemeBackend.mauve
                    onToggled: { Config.setSetting("addonsV2LegacyClock", checked); }
                }
            }
            SettingsRow {
                rootObj: root.rootObj; settingId: "addons_mullvad_dns"; searchTab: "addons"; searchKeywords: "dns mullvad network privacy"
                title: "Mullvad DNS"; icon: "󰖟"
                description: dns.errorMessage || (dns.connectionName ? "DNS over TLS · " + dns.connectionName : "Connect to a network to change its DNS.")
                wrapText: true
                DnsControl { id: dns; Layout.preferredWidth: root.rootObj.s(170); pollEnabled: root.visible }
            }
        }
    }
}

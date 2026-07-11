import 'package:flutter/material.dart';

// Localizations
import 'package:chameleonultragui/generated/i18n/app_localizations.dart';

// Hub page for the "Bluetooth app" — single-entry menu under Ethical Hacking
// that surfaces every BLE tool (audit / radio & identity / stress & broadcast)
// in one place. Each tab reuses the existing dedicated page so the per-tool
// state machines and timers keep working unchanged.
//
// Operator-authorised use only (cybersecurity fork, CLAUDE.md fork-specific
// exemption). While a stress / broadcast run is in progress the device shows
// a solid blue outside->centre LED animation; pressing button A or B on the
// device cancels the run and re-runs the BLE app so the host can reconnect.
class BleAppPage extends StatefulWidget {
  final Widget auditTab;
  final Widget radioIdentityTab;
  final Widget stressBroadcastTab;

  const BleAppPage({
    super.key,
    required this.auditTab,
    required this.radioIdentityTab,
    required this.stressBroadcastTab,
  });

  @override
  State<BleAppPage> createState() => _BleAppPageState();
}

class _BleAppPageState extends State<BleAppPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(
        title: Text(localizations.bluetooth_app),
        bottom: TabBar(
          controller: _tab,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: [
            Tab(
                icon: const Icon(Icons.bluetooth_searching),
                text: localizations.ble_tab_audit),
            Tab(
                icon: const Icon(Icons.bluetooth),
                text: localizations.ble_tab_radio_id),
            Tab(
                icon: const Icon(Icons.bolt),
                text: localizations.ble_tab_stress),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tab,
        children: [
          widget.auditTab,
          widget.radioIdentityTab,
          widget.stressBroadcastTab,
        ],
      ),
    );
  }
}

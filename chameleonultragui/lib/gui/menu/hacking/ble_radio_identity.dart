import 'package:chameleonultragui/bridge/chameleon_ble.dart';
import 'package:chameleonultragui/connector/serial_abstract.dart';
import 'package:chameleonultragui/generated/i18n/app_localizations.dart';
import 'package:chameleonultragui/helpers/ble/ble_address.dart';
import 'package:chameleonultragui/gui/menu/hacking/ble_capability_gate.dart';
import 'package:chameleonultragui/helpers/definitions.dart';
import 'package:chameleonultragui/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

// BLE own-radio identity & power toggle.
//
// Identity + radio power always mutate OUR radio (they can't be scoped
// further — they're settings on us). The environment-wide broadcast tools
// live on the BLE stress & broadcast page; this one is just for identity /
// stealth toggling.
class BleRadioIdentityPage extends StatefulWidget {
  final bool embedded;

  const BleRadioIdentityPage({super.key, this.embedded = false});

  @override
  BleRadioIdentityPageState createState() => BleRadioIdentityPageState();
}

class BleRadioIdentityPageState extends State<BleRadioIdentityPage> {
  // --- radio state ---
  Map<String, bool>? _radio;
  bool _radioBusy = false;
  String? _radioError;

  // --- identity state ---
  Map<String, dynamic>? _addr;
  bool _addrBusy = false;
  String? _addrError;
  bool _wasConnected = false;
  int _addrMode = 2; // 0 restore, 1 static, 2 RPA, 3 NRPA
  final _staticAddr = TextEditingController(
      text: 'C0:11:22:33:44:55'); // example static-random placeholder
  ChameleonGUIState get _app => context.read<ChameleonGUIState>();
  ChameleonCommunicator get _dev => _app.communicator!;
  bool get _usingBleTransport =>
      _app.connector?.connectionType == ConnectionType.ble;

  String _addressTypeName(AppLocalizations localizations, int type) =>
      switch (type) {
        0 => localizations.ble_address_type_public,
        1 => localizations.ble_address_static_random,
        2 => localizations.ble_address_rpa,
        3 => localizations.ble_address_nrpa,
        _ => localizations.ble_unknown_address_type(type),
      };

  @override
  void dispose() {
    _staticAddr.dispose();
    super.dispose();
  }

  Future<void> _refreshRadio() async {
    final localizations = AppLocalizations.of(context)!;
    try {
      final r = await _dev.bleRadioGet();
      if (!mounted) return;
      setState(() {
        _radio = r;
        _radioError = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() =>
          _radioError = localizations.ble_radio_refresh_failed(e.toString()));
    }
  }

  Future<void> _refreshAddr() async {
    final localizations = AppLocalizations.of(context)!;
    try {
      final a = await _dev.bleGetAddr();
      if (!mounted) return;
      setState(() {
        _addr = a;
        _addrError = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() =>
          _addrError = localizations.ble_identity_refresh_failed(e.toString()));
    }
  }

  Future<void> _toggleRadio(bool target) async {
    final localizations = AppLocalizations.of(context)!;
    setState(() => _radioBusy = true);
    try {
      await _dev.bleRadioSet(target);
      if (mounted) setState(() => _radioError = null);
      await _refreshRadio();
    } catch (e) {
      if (mounted) {
        setState(() =>
            _radioError = localizations.ble_radio_update_failed(e.toString()));
      }
    } finally {
      if (mounted) setState(() => _radioBusy = false);
    }
  }

  Future<void> _applyAddr() async {
    if (_usingBleTransport) return;
    final localizations = AppLocalizations.of(context)!;
    setState(() => _addrBusy = true);
    try {
      Uint8List? staticBytes;
      if (_addrMode == 1) {
        staticBytes = bleAddressToLittleEndian(_staticAddr.text,
            requireStaticRandom: true);
      }
      await _dev.bleSetAddr(_addrMode, addr: staticBytes);
      if (mounted) setState(() => _addrError = null);
      await _refreshAddr();
    } catch (e) {
      if (mounted) {
        setState(() => _addrError =
            localizations.ble_identity_update_failed(e.toString()));
      }
    } finally {
      if (mounted) setState(() => _addrBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context)!;
    final app = context.watch<ChameleonGUIState>();
    final connected =
        app.communicator != null && (app.connector?.connected ?? false);
    if (connected != _wasConnected) {
      _wasConnected = connected;
      if (connected) {
        WidgetsBinding.instance.addPostFrameCallback((_) async {
          if (!mounted ||
              _app.communicator == null ||
              !(_app.connector?.connected ?? false)) {
            return;
          }
          await _refreshRadio();
          await _refreshAddr();
        });
      }
    }
    final body = !connected
        ? Center(child: Text(localizations.ble_no_device_connected))
        : SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                BleCapabilityGate(
                  feature: localizations.ble_radio_power,
                  requiredCommands: const [
                    ChameleonCommand.bleRadioSet,
                    ChameleonCommand.bleRadioGet,
                  ],
                  child: _radioCard(),
                ),
                const SizedBox(height: 16),
                BleCapabilityGate(
                  feature: localizations.ble_identity_title,
                  requiredCommands: const [
                    ChameleonCommand.bleSetAddr,
                    ChameleonCommand.bleGetAddr,
                  ],
                  child: _identityCard(),
                ),
              ],
            ),
          );
    if (widget.embedded) return body;
    return Scaffold(
      appBar: AppBar(title: Text(localizations.ble_radio_identity_title)),
      body: body,
    );
  }

  Widget _radioCard() {
    final localizations = AppLocalizations.of(context)!;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(localizations.ble_radio_power,
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(localizations.ble_radio_power_description),
            if (_usingBleTransport) ...[
              const SizedBox(height: 8),
              Text(localizations.ble_radio_off_usb_only,
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
            const SizedBox(height: 12),
            if (_radioError != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(_radioError!,
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error)),
              ),
            if (_radio != null) ...[
              _kv(
                  localizations.ble_radio,
                  _radio!['on']!
                      ? localizations.ble_state_on
                      : localizations.ble_state_off),
              _kv(
                  localizations.ble_advertising,
                  _radio!['advertising']!
                      ? localizations.ble_state_on
                      : localizations.ble_state_off),
              _kv(
                  localizations.ble_passive_scan,
                  _radio!['scanning']!
                      ? localizations.ble_state_on
                      : localizations.ble_state_off),
              _kv(
                  localizations.ble_central_link,
                  _radio!['centralLink']!
                      ? localizations.ble_state_up
                      : localizations.ble_state_down),
            ],
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                FilledButton.icon(
                  icon: const Icon(Icons.power_settings_new),
                  label: Text(localizations.ble_turn_on),
                  onPressed: (_radioBusy || (_radio?['on'] ?? false))
                      ? null
                      : () => _toggleRadio(true),
                ),
                FilledButton.tonalIcon(
                  icon: const Icon(Icons.do_not_disturb_on),
                  label: Text(localizations.ble_silent_off),
                  onPressed: (_radioBusy ||
                          _usingBleTransport ||
                          !(_radio?['on'] ?? true))
                      ? null
                      : () => _toggleRadio(false),
                ),
                IconButton(
                  icon: const Icon(Icons.refresh),
                  tooltip: localizations.ble_refresh,
                  onPressed: _radioBusy ? null : _refreshRadio,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _identityCard() {
    final localizations = AppLocalizations.of(context)!;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(localizations.ble_identity_title,
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(localizations.ble_identity_description),
            const SizedBox(height: 12),
            if (_addrError != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(_addrError!,
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error)),
              ),
            if (_addr != null) ...[
              _kv(localizations.ble_active_type,
                  _addressTypeName(localizations, _addr!['addrType'] as int)),
              _kv(localizations.ble_active_address,
                  bleAddressFromLittleEndian(_addr!['addr'] as Uint8List)),
            ],
            const SizedBox(height: 12),
            DropdownButtonFormField<int>(
              initialValue: _addrMode,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: localizations.ble_mode,
                border: const OutlineInputBorder(),
              ),
              items: [
                DropdownMenuItem(
                    value: 0,
                    child: Text(localizations.ble_address_restore,
                        overflow: TextOverflow.ellipsis)),
                DropdownMenuItem(
                    value: 1,
                    child: Text(localizations.ble_address_static_random,
                        overflow: TextOverflow.ellipsis)),
                DropdownMenuItem(
                    value: 2,
                    child: Text(localizations.ble_address_rpa,
                        overflow: TextOverflow.ellipsis)),
                DropdownMenuItem(
                    value: 3,
                    child: Text(localizations.ble_address_nrpa,
                        overflow: TextOverflow.ellipsis)),
              ],
              onChanged:
                  _addrBusy ? null : (v) => setState(() => _addrMode = v ?? 0),
            ),
            if (_addrMode == 1) ...[
              const SizedBox(height: 12),
              TextField(
                controller: _staticAddr,
                enabled: !_addrBusy,
                decoration: InputDecoration(
                  labelText: localizations.ble_static_random_address,
                  hintText: 'C0:11:22:33:44:55',
                  border: const OutlineInputBorder(),
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9a-fA-F:\- ]')),
                ],
              ),
            ],
            if (_usingBleTransport) ...[
              const SizedBox(height: 12),
              Text(
                localizations.ble_address_change_usb_only,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                FilledButton.icon(
                  icon: const Icon(Icons.swap_horiz),
                  label: Text(localizations.ble_apply),
                  onPressed:
                      (_addrBusy || _usingBleTransport) ? null : _applyAddr,
                ),
                IconButton(
                  icon: const Icon(Icons.refresh),
                  tooltip: localizations.ble_refresh,
                  onPressed: _addrBusy ? null : _refreshAddr,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _kv(String k, String v) => BleResponsiveKeyValueRow(
        label: k,
        value: v,
      );
}

class BleResponsiveKeyValueRow extends StatelessWidget {
  final String label;
  final String value;

  const BleResponsiveKeyValueRow({
    super.key,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final textScaler = MediaQuery.textScalerOf(context);
        final stack = constraints.maxWidth < 360 || textScaler.scale(14) >= 21;
        final labelWidget = Text(
          label,
          style: Theme.of(context).textTheme.bodySmall,
        );

        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: stack
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    labelWidget,
                    const SizedBox(height: 2),
                    Text(value),
                  ],
                )
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(width: 110, child: labelWidget),
                    Expanded(child: Text(value)),
                  ],
                ),
        );
      },
    );
  }
}

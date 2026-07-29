import 'package:chameleonultragui/bridge/chameleon_ble.dart';
import 'package:chameleonultragui/connector/serial_abstract.dart';
import 'package:chameleonultragui/generated/i18n/app_localizations.dart';
import 'package:chameleonultragui/gui/menu/hacking/ble_capability_gate.dart';
import 'package:chameleonultragui/helpers/ble/ble_advertising.dart';
import 'package:chameleonultragui/helpers/definitions.dart';
import 'package:chameleonultragui/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

enum _AdvertisingLabTemplate { custom, connectableAccessory, sensorBeacon }

enum _PairingPromptFamily { apple, android }

class BleAdvertisingLabPage extends StatefulWidget {
  final bool embedded;

  const BleAdvertisingLabPage({super.key, this.embedded = false});

  @override
  State<BleAdvertisingLabPage> createState() => _BleAdvertisingLabPageState();
}

class _BleAdvertisingLabPageState extends State<BleAdvertisingLabPage> {
  bool _raw = false;
  bool _pairingProfile = false;
  bool _busy = false;
  ChameleonCommunicator? _lastCommunicator;
  String? _error;
  BleAdvertisingLabStatus? _status;
  BleAdvertisingMode _mode = BleAdvertisingMode.scannable;
  _AdvertisingLabTemplate _template = _AdvertisingLabTemplate.custom;
  _PairingPromptFamily _pairingFamily = _PairingPromptFamily.apple;
  int _appleModelCode = 0x0e20;
  int _androidModelId = 0x2d7a23;
  BleAdvertisingNameTarget _nameTarget = BleAdvertisingNameTarget.advertisement;

  final _flags = TextEditingController(text: '0x06');
  final _serviceUuid = TextEditingController();
  final _serviceDataUuid = TextEditingController();
  final _serviceData = TextEditingController();
  final _companyId = TextEditingController();
  final _manufacturer = TextEditingController();
  final _names = TextEditingController(text: 'Chameleon Lab');
  final _rawAdv = TextEditingController(text: '02 01 06');
  final _rawScan = TextEditingController();
  final _interval = TextEditingController(text: '250');
  final _rotation = TextEditingController(text: '1000');
  final _duration = TextEditingController(text: '0');
  final _maxEvents = TextEditingController(text: '0');

  ChameleonGUIState get _app => context.read<ChameleonGUIState>();
  ChameleonCommunicator get _device => _app.communicator!;
  bool get _usingBle => _app.connector?.connectionType == ConnectionType.ble;

  @override
  void dispose() {
    for (final controller in [
      _flags,
      _serviceUuid,
      _serviceDataUuid,
      _serviceData,
      _companyId,
      _manufacturer,
      _names,
      _rawAdv,
      _rawScan,
      _interval,
      _rotation,
      _duration,
      _maxEvents,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  int _integer(String value, String field) {
    final text = value.trim();
    if (text.isEmpty) throw FormatException('$field is required');
    final parsed = text.toLowerCase().startsWith('0x')
        ? int.tryParse(text.substring(2), radix: 16)
        : int.tryParse(text);
    if (parsed == null) throw FormatException('$field is not a number');
    return parsed;
  }

  int? _optionalInteger(String value, String field) =>
      value.trim().isEmpty ? null : _integer(value, field);

  List<String> _nameList() => (_raw || _pairingProfile)
      ? const []
      : _names.text
          .split('\n')
          .map((name) => name.trim())
          .where((name) => name.isNotEmpty)
          .toList(growable: false);

  void _applyTemplate(_AdvertisingLabTemplate template) {
    setState(() {
      _template = template;
      if (template == _AdvertisingLabTemplate.custom) return;
      _flags.text = '0x06';
      _companyId.clear();
      _manufacturer.clear();
      _nameTarget = BleAdvertisingNameTarget.advertisement;
      if (template == _AdvertisingLabTemplate.connectableAccessory) {
        _mode = BleAdvertisingMode.connectable;
        _serviceUuid.clear();
        _serviceDataUuid.clear();
        _serviceData.clear();
        _names.text = 'Lab Accessory';
        _interval.text = '100';
      } else {
        _mode = BleAdvertisingMode.scannable;
        _serviceUuid.text = '0x181A';
        _serviceDataUuid.text = '0x181A';
        _serviceData.text = '00 00';
        _names.text = 'Lab Sensor';
        _interval.text = '500';
      }
    });
  }

  BleAdvertisingLabConfig _config() {
    final names = _nameList();
    late Uint8List advertising;
    late Uint8List scanResponse;
    late BleAdvertisingProfile profile;
    var mode = _mode;
    if (_pairingProfile) {
      final built = _pairingFamily == _PairingPromptFamily.apple
          ? bleBuildAppleProximityProfile(modelCode: _appleModelCode)
          : bleBuildFastPairProfile(modelId: _androidModelId);
      advertising = built.advertising;
      scanResponse = built.scanResponse;
      profile = BleAdvertisingProfile.raw;
      mode = _pairingFamily == _PairingPromptFamily.apple
          ? BleAdvertisingMode.nonScannable
          : BleAdvertisingMode.connectable;
    } else if (_raw) {
      advertising = bleParseAdvertisingHex(_rawAdv.text);
      scanResponse = bleParseAdvertisingHex(_rawScan.text);
      profile = BleAdvertisingProfile.raw;
    } else {
      final built = bleBuildAdvertisingProfile(
        flags: _integer(_flags.text, 'Flags'),
        serviceUuid: _optionalInteger(_serviceUuid.text, 'Service UUID'),
        serviceDataUuid:
            _optionalInteger(_serviceDataUuid.text, 'Service Data UUID'),
        serviceData: bleParseAdvertisingHex(_serviceData.text),
        companyId: _optionalInteger(_companyId.text, 'Company ID'),
        manufacturerData: bleParseAdvertisingHex(_manufacturer.text),
      );
      advertising = built.advertising;
      scanResponse = built.scanResponse;
      profile = names.length > 1
          ? BleAdvertisingProfile.rotating
          : BleAdvertisingProfile.custom;
    }
    return BleAdvertisingLabConfig(
      profile: profile,
      mode: mode,
      advertisingData: advertising,
      scanResponseData: scanResponse,
      names: names,
      nameTarget: names.isEmpty ? BleAdvertisingNameTarget.none : _nameTarget,
      intervalMs: _integer(_interval.text, 'Advertising interval'),
      rotationMs:
          names.length > 1 ? _integer(_rotation.text, 'Name rotation') : 0,
      durationMs: _integer(_duration.text, 'Duration'),
      maxAdvertisingEvents: _integer(_maxEvents.text, 'Maximum events'),
    );
  }

  Future<void> _refresh() async {
    final localizations = AppLocalizations.of(context)!;
    final device = _device;
    try {
      final status = await device.bleAdvLabStatus();
      if (mounted && identical(_app.communicator, device)) {
        setState(() {
          _status = status;
          _error = null;
        });
      }
    } catch (error) {
      if (mounted && identical(_app.communicator, device)) {
        setState(() => _error =
            localizations.ble_advertising_operation_failed(error.toString()));
      }
    }
  }

  Future<void> _start() async {
    if (_usingBle) return;
    final localizations = AppLocalizations.of(context)!;
    final device = _device;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final status = await device.bleAdvLabStart(_config());
      if (mounted && identical(_app.communicator, device)) {
        setState(() => _status = status);
      }
    } catch (error) {
      if (mounted && identical(_app.communicator, device)) {
        setState(() => _error =
            localizations.ble_advertising_operation_failed(error.toString()));
      }
    } finally {
      if (mounted && identical(_app.communicator, device)) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _stop() async {
    final localizations = AppLocalizations.of(context)!;
    final device = _device;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final status = await device.bleAdvLabStop();
      if (mounted && identical(_app.communicator, device)) {
        setState(() => _status = status);
      }
    } catch (error) {
      if (mounted && identical(_app.communicator, device)) {
        setState(() => _error =
            localizations.ble_advertising_operation_failed(error.toString()));
      }
    } finally {
      if (mounted && identical(_app.communicator, device)) {
        setState(() => _busy = false);
      }
    }
  }

  String _stateLabel(AppLocalizations localizations) =>
      switch (_status?.state) {
        2 => localizations.ble_advertising_running,
        3 => localizations.ble_advertising_connected,
        4 => localizations.ble_advertising_error,
        _ => localizations.ble_advertising_idle,
      };

  String _reasonLabel(AppLocalizations localizations) =>
      switch (_status?.reason) {
        1 => localizations.ble_advertising_reason_host_stop,
        2 => localizations.ble_advertising_reason_duration,
        3 => localizations.ble_advertising_reason_event_limit,
        4 => localizations.ble_advertising_reason_connected,
        7 => localizations.ble_advertising_reason_error,
        _ => localizations.ble_advertising_reason_none,
      };

  Widget _numberField(TextEditingController controller, String label,
          {double width = 220}) =>
      SizedBox(
        width: width,
        child: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[0-9a-fA-FxX]'))
          ],
          decoration: InputDecoration(
              labelText: label, border: const OutlineInputBorder()),
          onChanged: (_) => setState(() {
            if (!_raw) _template = _AdvertisingLabTemplate.custom;
          }),
        ),
      );

  Widget _editor(AppLocalizations localizations) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(localizations.ble_advertising_lab_title,
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(localizations.ble_advertising_lab_description),
            const SizedBox(height: 16),
            SegmentedButton<int>(
              segments: [
                ButtonSegment(
                    value: 0,
                    label: Text(localizations.ble_advertising_lab_profile)),
                ButtonSegment(
                    value: 1,
                    label:
                        Text(localizations.ble_advertising_pairing_profiles)),
                ButtonSegment(
                    value: 2,
                    label: Text(localizations.ble_advertising_lab_raw)),
              ],
              selected: {
                _pairingProfile ? 1 : (_raw ? 2 : 0),
              },
              onSelectionChanged: _busy
                  ? null
                  : (selection) => setState(() {
                        _pairingProfile = selection.first == 1;
                        _raw = selection.first == 2;
                        if (_pairingProfile) _interval.text = '100';
                      }),
            ),
            const SizedBox(height: 16),
            if (!_raw && !_pairingProfile) ...[
              DropdownButtonFormField<_AdvertisingLabTemplate>(
                initialValue: _template,
                isExpanded: true,
                decoration: InputDecoration(
                    labelText: localizations.ble_advertising_template),
                items: [
                  DropdownMenuItem(
                      value: _AdvertisingLabTemplate.custom,
                      child:
                          Text(localizations.ble_advertising_template_custom)),
                  DropdownMenuItem(
                      value: _AdvertisingLabTemplate.connectableAccessory,
                      child: Text(
                          localizations.ble_advertising_template_connectable)),
                  DropdownMenuItem(
                      value: _AdvertisingLabTemplate.sensorBeacon,
                      child:
                          Text(localizations.ble_advertising_template_sensor)),
                ],
                onChanged: _busy ? null : (value) => _applyTemplate(value!),
              ),
              const SizedBox(height: 16),
            ],
            if (!_pairingProfile)
              DropdownButtonFormField<BleAdvertisingMode>(
                initialValue: _mode,
                isExpanded: true,
                decoration: InputDecoration(labelText: localizations.ble_mode),
                items: [
                  DropdownMenuItem(
                      value: BleAdvertisingMode.connectable,
                      child:
                          Text(localizations.ble_advertising_mode_connectable)),
                  DropdownMenuItem(
                      value: BleAdvertisingMode.scannable,
                      child:
                          Text(localizations.ble_advertising_mode_scannable)),
                  DropdownMenuItem(
                      value: BleAdvertisingMode.nonScannable,
                      child: Text(
                          localizations.ble_advertising_mode_non_scannable)),
                ],
                onChanged: _busy
                    ? null
                    : (value) => setState(() {
                          _mode = value!;
                          if (!_raw) {
                            _template = _AdvertisingLabTemplate.custom;
                          }
                        }),
              )
            else
              Text(localizations.ble_advertising_pairing_mode_fixed),
            const SizedBox(height: 16),
            if (_pairingProfile) ...[
              DropdownButtonFormField<_PairingPromptFamily>(
                initialValue: _pairingFamily,
                isExpanded: true,
                decoration: InputDecoration(
                    labelText: localizations.ble_advertising_pairing_family),
                items: [
                  DropdownMenuItem(
                      value: _PairingPromptFamily.apple,
                      child: Text(localizations.ble_advertising_pairing_apple)),
                  DropdownMenuItem(
                      value: _PairingPromptFamily.android,
                      child:
                          Text(localizations.ble_advertising_pairing_android)),
                ],
                onChanged: _busy
                    ? null
                    : (value) => setState(() => _pairingFamily = value!),
              ),
              const SizedBox(height: 12),
              if (_pairingFamily == _PairingPromptFamily.apple)
                DropdownButtonFormField<int>(
                  initialValue: _appleModelCode,
                  isExpanded: true,
                  decoration: InputDecoration(
                      labelText: localizations.ble_advertising_accessory_model),
                  items: const [
                    DropdownMenuItem(value: 0x0220, child: Text('AirPods')),
                    DropdownMenuItem(value: 0x0e20, child: Text('AirPods Pro')),
                    DropdownMenuItem(
                        value: 0x1420, child: Text('AirPods Pro (2nd gen)')),
                    DropdownMenuItem(value: 0x0a20, child: Text('AirPods Max')),
                  ],
                  onChanged: _busy
                      ? null
                      : (value) => setState(() => _appleModelCode = value!),
                )
              else
                DropdownButtonFormField<int>(
                  initialValue: _androidModelId,
                  isExpanded: true,
                  decoration: InputDecoration(
                      labelText: localizations.ble_advertising_accessory_model),
                  items: const [
                    DropdownMenuItem(
                        value: 0x2d7a23, child: Text('Sony WF-1000XM4')),
                    DropdownMenuItem(
                        value: 0x9adb11, child: Text('Pixel Buds Pro')),
                    DropdownMenuItem(
                        value: 0x821f66, child: Text('JBL Flip 6')),
                    DropdownMenuItem(
                        value: 0xcd8256, child: Text('Bose NC 700')),
                  ],
                  onChanged: _busy
                      ? null
                      : (value) => setState(() => _androidModelId = value!),
                ),
              const SizedBox(height: 12),
              Text(localizations.ble_advertising_pairing_disclaimer),
            ] else if (_raw) ...[
              TextField(
                controller: _rawAdv,
                minLines: 2,
                maxLines: 4,
                decoration: InputDecoration(
                    labelText: localizations.ble_advertising_raw_adv,
                    border: const OutlineInputBorder()),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _rawScan,
                minLines: 2,
                maxLines: 4,
                decoration: InputDecoration(
                    labelText: localizations.ble_advertising_raw_scan,
                    border: const OutlineInputBorder()),
                onChanged: (_) => setState(() {}),
              ),
            ] else ...[
              Wrap(spacing: 12, runSpacing: 12, children: [
                _numberField(_flags, localizations.ble_advertising_flags),
                _numberField(
                    _serviceUuid, localizations.ble_advertising_service_uuid),
                _numberField(_serviceDataUuid,
                    localizations.ble_advertising_service_data_uuid),
                _numberField(
                    _companyId, localizations.ble_advertising_company_id),
              ]),
              const SizedBox(height: 12),
              TextField(
                controller: _serviceData,
                decoration: InputDecoration(
                    labelText: localizations.ble_advertising_service_data,
                    border: const OutlineInputBorder()),
                onChanged: (_) =>
                    setState(() => _template = _AdvertisingLabTemplate.custom),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _manufacturer,
                decoration: InputDecoration(
                    labelText: localizations.ble_advertising_manufacturer_data,
                    border: const OutlineInputBorder()),
                onChanged: (_) =>
                    setState(() => _template = _AdvertisingLabTemplate.custom),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _names,
                minLines: 2,
                maxLines: 6,
                decoration: InputDecoration(
                    labelText: localizations.ble_advertising_names,
                    border: const OutlineInputBorder()),
                onChanged: (_) =>
                    setState(() => _template = _AdvertisingLabTemplate.custom),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<BleAdvertisingNameTarget>(
                initialValue: _nameTarget,
                isExpanded: true,
                decoration: InputDecoration(
                    labelText: localizations.ble_advertising_name_target),
                items: [
                  DropdownMenuItem(
                      value: BleAdvertisingNameTarget.advertisement,
                      child: Text(localizations.ble_advertising_packet)),
                  DropdownMenuItem(
                      value: BleAdvertisingNameTarget.scanResponse,
                      child: Text(localizations.ble_scan_response_packet)),
                ],
                onChanged: _busy
                    ? null
                    : (value) => setState(() {
                          _nameTarget = value!;
                          _template = _AdvertisingLabTemplate.custom;
                        }),
              ),
            ],
            const SizedBox(height: 16),
            Wrap(spacing: 12, runSpacing: 12, children: [
              _numberField(
                  _interval, localizations.ble_advertising_interval_ms),
              if (!_raw && !_pairingProfile && _nameList().length > 1)
                _numberField(
                    _rotation, localizations.ble_advertising_rotation_ms),
              _numberField(
                  _duration, localizations.ble_advertising_duration_ms),
              _numberField(
                  _maxEvents, localizations.ble_advertising_max_events),
            ]),
            const SizedBox(height: 16),
            _preview(localizations),
            if (_usingBle) ...[
              const SizedBox(height: 12),
              Text(localizations.ble_advertising_lab_usb_only,
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
            const SizedBox(height: 16),
            Wrap(spacing: 12, runSpacing: 8, children: [
              FilledButton.icon(
                onPressed: _busy || _usingBle ? null : _start,
                icon: const Icon(Icons.cell_tower),
                label: Text(localizations.ble_advertising_start),
              ),
              OutlinedButton.icon(
                onPressed: _busy ? null : _refresh,
                icon: const Icon(Icons.refresh),
                label: Text(localizations.ble_refresh),
              ),
              OutlinedButton.icon(
                onPressed: _busy ? null : _stop,
                icon: const Icon(Icons.stop),
                label: Text(localizations.ble_advertising_stop),
              ),
            ]),
          ],
        ),
      ),
    );
  }

  Widget _preview(AppLocalizations localizations) {
    try {
      final config = _config();
      final packets = config.previewPackets();
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(localizations.ble_advertising_preview,
            style: Theme.of(context).textTheme.titleMedium),
        SelectableText('${localizations.ble_advertising_packet} '
            '(${packets.advertising.length}/31): '
            '${bleFormatAdvertisingHex(packets.advertising)}'),
        SelectableText('${localizations.ble_scan_response_packet} '
            '(${packets.scanResponse.length}/31): '
            '${bleFormatAdvertisingHex(packets.scanResponse)}'),
      ]);
    } catch (error) {
      return Text(error.toString(),
          style: TextStyle(color: Theme.of(context).colorScheme.error));
    }
  }

  Widget _statusCard(AppLocalizations localizations) {
    final status = _status;
    return Card(
      child: ListTile(
        leading: Icon(
            status?.running == true ? Icons.cell_tower : Icons.info_outline),
        title: Text(localizations.ble_advertising_status),
        subtitle: Text(localizations.ble_advertising_status_line(
          _stateLabel(localizations),
          status?.advertisingLength ?? 0,
          status?.scanResponseLength ?? 0,
          status?.rotationCount ?? 0,
          _reasonLabel(localizations),
        )),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context)!;
    final app = context.watch<ChameleonGUIState>();
    final connected =
        app.communicator != null && (app.connector?.connected ?? false);
    if (!identical(app.communicator, _lastCommunicator)) {
      _lastCommunicator = app.communicator;
      _status = null;
      _error = null;
      _busy = false;
      if (connected) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _app.communicator != null) _refresh();
        });
      }
    }
    final body = !connected
        ? Center(child: Text(localizations.ble_no_device_connected))
        : BleCapabilityGate(
            feature: localizations.ble_advertising_lab_title,
            requiredCommands: const [
              ChameleonCommand.bleAdvLabStart,
              ChameleonCommand.bleAdvLabStatus,
              ChameleonCommand.bleAdvLabStop,
            ],
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(children: [
                _editor(localizations),
                const SizedBox(height: 12),
                _statusCard(localizations),
              ]),
            ),
          );
    if (widget.embedded) return body;
    return Scaffold(
      appBar: AppBar(title: Text(localizations.ble_advertising_lab_title)),
      body: body,
    );
  }
}

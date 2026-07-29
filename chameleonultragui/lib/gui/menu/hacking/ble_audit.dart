import 'dart:async';

import 'package:chameleonultragui/bridge/chameleon_ble.dart';
import 'package:chameleonultragui/generated/i18n/app_localizations.dart';
import 'package:chameleonultragui/helpers/ble/ble_address.dart';
import 'package:chameleonultragui/helpers/ble/ble_presentation.dart';
import 'package:chameleonultragui/helpers/definitions.dart';
import 'package:chameleonultragui/gui/menu/hacking/ble_audit_status.dart';
import 'package:chameleonultragui/gui/menu/hacking/ble_capability_gate.dart';
import 'package:chameleonultragui/gui/menu/hacking/ble_characteristic_tile.dart';
import 'package:chameleonultragui/gui/menu/hacking/ble_responsive.dart';
import 'package:chameleonultragui/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

// BLE audit tool.
//
// SCOPE: this is receive-only + point-to-point, matching the firmware.
//  - "Passive scan" listens for advertisements only; the device transmits
//    nothing. Used to inventory / detect nearby BLE devices.
//  - "Directed fuzz" connects to ONE target you specify by address, enumerates
//    its GATT characteristics and writes mutated payloads to a chosen
//    characteristic to exercise its input parsing. It never broadcasts, floods
//    or jams — everything is scoped to the single connected target, and
//    Disconnect frees it to reconnect to its normal source.
class BleAuditPage extends StatefulWidget {
  final bool embedded;

  const BleAuditPage({super.key, this.embedded = false});

  @override
  BleAuditPageState createState() => BleAuditPageState();
}

class BleAuditPageState extends State<BleAuditPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;

  // --- passive scan state ---
  final _scanDuration = TextEditingController(text: '5');
  bool _scanning = false;
  bool _activeScan = false;
  List<BleScanResult> _scanResults = [];
  final _nameFilter = TextEditingController();
  final _minRssi = TextEditingController();

  // --- directed fuzz state ---
  final _addr = TextEditingController();
  int _addrType = 0;
  final _handle = TextEditingController();
  final _count = TextEditingController(text: '200');
  final _interval = TextEditingController(text: '50');
  BleCentralState? _state;
  int _mtu = 23;
  List<BleCharacteristic> _chars = [];
  List<Map<String, int>> _services = [];
  final Map<int, String> _readValues = {}; // value handle -> last read result
  List<BleFuzzLogEntry> _log = [];
  bool _notifying = false;
  int? _notifCccd; // CCCD handle currently subscribed
  int? _notifValueHandle; // value handle shown by the characteristic row
  List<Map<String, dynamic>> _notifs = [];
  bool _busy = false;
  bool _fuzzing = false;
  String? _error;
  bool _disposing = false;
  int _scanGeneration = 0;
  int _fuzzGeneration = 0;
  int _notificationGeneration = 0;

  late ChameleonGUIState _app;
  bool get _connected => _app.connector?.connected ?? false;
  bool _supportsCommands(List<ChameleonCommand> commands) {
    final communicator = _app.communicator;
    return communicator == null ||
        commands.every(
            (command) => communicator.supportsCommandSync(command) != false);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _app = context.read<ChameleonGUIState>();
  }

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_connected) return;
      _refreshState().catchError((Object error) {
        if (mounted) {
          setState(() => _error = AppLocalizations.of(context)!
              .ble_state_refresh_failed(error.toString()));
        }
      });
    });
  }

  @override
  void dispose() {
    _disposing = true;
    _scanGeneration++;
    _fuzzGeneration++;
    _notificationGeneration++;
    final communicator = _app.communicator;
    final cccd = _notifCccd;
    _scanning = false;
    _fuzzing = false;
    _notifying = false;
    _notifCccd = null;
    _notifValueHandle = null;
    _notifs = [];
    if (communicator != null) {
      unawaited(_cleanupDisposedRoute(communicator, cccd));
    }
    _tab.dispose();
    _scanDuration.dispose();
    _nameFilter.dispose();
    _minRssi.dispose();
    _addr.dispose();
    _handle.dispose();
    _count.dispose();
    _interval.dispose();
    super.dispose();
  }

  Future<void> _cleanupDisposedRoute(
      ChameleonCommunicator communicator, int? cccd) async {
    await _bestEffortStopDeviceActivity(communicator,
        stopScan: true, stopFuzz: true, cccd: cccd);
    try {
      await communicator.bleDisconnect();
    } catch (_) {}
  }

  // ---- helpers ----------------------------------------------------------
  Future<void> _bestEffortStopDeviceActivity(ChameleonCommunicator communicator,
      {required bool stopScan,
      required bool stopFuzz,
      required int? cccd}) async {
    if (cccd != null) {
      try {
        await communicator.bleSubscribe(cccd, 0);
      } catch (_) {}
    }
    if (stopFuzz) {
      try {
        await communicator.bleFuzzStop();
      } catch (_) {}
    }
    if (stopScan) {
      try {
        await communicator.blePassiveScanStop();
      } catch (_) {}
    }
  }

  void _clearLocalActivity({bool clearCentralState = false}) {
    _scanGeneration++;
    _fuzzGeneration++;
    _notificationGeneration++;
    _scanning = false;
    _fuzzing = false;
    _notifying = false;
    _notifCccd = null;
    _notifValueHandle = null;
    _notifs = [];
    if (clearCentralState) {
      _state = null;
      _chars = [];
      _services = [];
    }
  }

  // ---- passive scan -----------------------------------------------------
  Future<void> _runScan() async {
    final localizations = AppLocalizations.of(context)!;
    final generation = ++_scanGeneration;
    setState(() {
      _scanning = true;
      _scanResults = [];
      _error = null;
    });
    try {
      final secs = double.tryParse(_scanDuration.text.trim()) ?? 5.0;
      await _app.communicator!.blePassiveScanStart(active: _activeScan);
      await Future.delayed(
          Duration(milliseconds: (secs.clamp(1, 60) * 1000).round()));
      if (_disposing || generation != _scanGeneration) return;
      await _app.communicator!.blePassiveScanStop();
      final results = await _app.communicator!.blePassiveScanResults();
      if (!mounted || generation != _scanGeneration) return;
      setState(() => _scanResults = results);
    } catch (e) {
      if (mounted) {
        setState(() => _error = localizations.ble_scan_failed(e.toString()));
      }
    } finally {
      if (mounted && generation == _scanGeneration) {
        setState(() => _scanning = false);
      }
    }
  }

  List<BleScanResult> _visibleResults() {
    final name = _nameFilter.text.trim().toLowerCase();
    final minRssi = int.tryParse(_minRssi.text.trim());
    return _scanResults.where((r) {
      if (minRssi != null && r.rssi < minRssi) return false;
      if (name.isNotEmpty &&
          !(bleAdvertisingName(r.adv)?.toLowerCase() ?? '').contains(name)) {
        return false;
      }
      return true;
    }).toList();
  }

  void _useAsTarget(BleScanResult r) {
    setState(() {
      _addr.text = bleAddressFromLittleEndian(r.addr);
      // The scanner can report addr types 0-3 (and rarely 0x7F anonymous);
      // clamp to a value the dropdown actually has an item for, else the
      // DropdownButton throws on the next build.
      _addrType = (r.addrType >= 0 && r.addrType <= 3) ? r.addrType : 1;
    });
    _tab.animateTo(1);
  }

  String _localizedAdvertisingDetail(
      AppLocalizations localizations, String detail) {
    const prefixes = [
      'flags: ',
      'services16: ',
      'services128: ',
      'name: ',
      'tx_power: ',
      'appearance: ',
      'mfr: ',
      'svc_data ',
    ];
    String? prefix;
    for (final candidate in prefixes) {
      if (detail.startsWith(candidate)) {
        prefix = candidate;
        break;
      }
    }
    if (prefix == null) return detail;
    final value = detail.substring(prefix.length);
    return switch (prefix) {
      'flags: ' => localizations.ble_advertising_field_flags(value),
      'services16: ' => localizations.ble_advertising_field_services_16(value),
      'services128: ' =>
        localizations.ble_advertising_field_services_128(value),
      'name: ' => localizations.ble_advertising_field_name(value),
      'tx_power: ' => localizations.ble_advertising_field_tx_power(value),
      'appearance: ' => localizations.ble_advertising_field_appearance(value),
      'mfr: ' => localizations.ble_advertising_field_manufacturer(value),
      _ => localizations.ble_advertising_field_service_data(value),
    };
  }

  void _showDeviceDetails(BleScanResult r) {
    final localizations = AppLocalizations.of(context)!;
    final details = bleAdvertisingDetails(r.adv)
        .map((detail) => _localizedAdvertisingDetail(localizations, detail))
        .toList();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(bleAddressFromLittleEndian(r.addr),
            style: const TextStyle(fontFamily: 'RobotoMono')),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(localizations.ble_device_details_metadata(
                  r.addrType, r.rssi)),
              const SizedBox(height: 8),
              if (details.isEmpty) Text(localizations.ble_no_advertising_data),
              for (final d in details)
                Text(d,
                    style: const TextStyle(
                        fontFamily: 'RobotoMono', fontSize: 12)),
              const SizedBox(height: 8),
              Text(localizations.ble_raw_data,
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              SelectableText(bleFormatHexBytes(r.adv),
                  style:
                      const TextStyle(fontFamily: 'RobotoMono', fontSize: 11)),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _useAsTarget(r);
            },
            child: Text(localizations.ble_fuzz_this),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(localizations.close),
          ),
        ],
      ),
    );
  }

  // ---- directed fuzz ----------------------------------------------------
  Future<void> _refreshState() async {
    final st = await _app.communicator!.bleCentralState();
    int mtu = 23;
    if (st.connState == 2) {
      try {
        mtu = await _app.communicator!.bleGetMtu();
      } catch (_) {}
    }
    if (mounted) {
      setState(() {
        _state = st;
        _mtu = mtu;
        _fuzzing = st.fuzzState == 1;
        if (st.connState != 2) {
          _notificationGeneration++;
          _notifying = false;
          _notifCccd = null;
          _notifValueHandle = null;
          _notifs = [];
        }
      });
    }
  }

  // Toggle the device's OWN advertising (discoverable) — controls only this
  // Chameleon, does not touch other devices.
  Future<void> _toggleAdvertising() async {
    final localizations = AppLocalizations.of(context)!;
    try {
      final cur = await _app.communicator!.bleAdvertisingGet();
      final now = await _app.communicator!.bleAdvertisingSet(!cur);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(now
              ? localizations.ble_local_advertising_on
              : localizations.ble_local_advertising_off)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content:
              Text(localizations.ble_advertising_toggle_failed(e.toString()))));
    }
  }

  Future<void> _probeLink({bool globalMode = false}) async {
    final localizations = AppLocalizations.of(context)!;
    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final targetCount =
          globalMode ? await _app.communicator!.blePassiveScanCount() : 1;
      if (globalMode && targetCount == 0) {
        setState(() => _error = localizations.ble_scan_buffer_empty);
        return;
      }
      await _app.communicator!.bleLinkProbe(globalMode: globalMode);
      if (!mounted) return;

      final maxPolls = globalMode ? targetCount * 60 + 20 : 80;
      for (int i = 0; i < maxPolls && mounted; i++) {
        await Future.delayed(const Duration(milliseconds: 100));
        final st = await _app.communicator!.bleCentralState();
        if (!mounted) return;
        setState(() => _state = st);
        if (st.probeState == 2) {
          final message = globalMode
              ? localizations.ble_scan_buffer_probe_completed(
                  st.probeIndex, st.probeTotal)
              : localizations.ble_target_probe_succeeded;
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(message)));
          return;
        }
        if (st.probeState == 3) {
          setState(() {
            _error = localizations
                .ble_ping_failed('0x${st.probeResult.toRadixString(16)}');
          });
          return;
        }
      }

      if (mounted) {
        setState(() => _error = globalMode
            ? localizations.ble_scan_buffer_probe_timeout
            : localizations.ble_target_probe_timeout);
      }
    } catch (e) {
      if (mounted) {
        setState(
            () => _error = localizations.ble_link_probe_failed(e.toString()));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _connect() async {
    final localizations = AppLocalizations.of(context)!;
    setState(() {
      _busy = true;
      _error = null;
      _chars = [];
      _log = [];
    });
    try {
      final le = bleAddressToLittleEndian(_addr.text);
      await _app.communicator!.bleConnect(le, addrType: _addrType);
      for (int i = 0; i < 50 && mounted; i++) {
        await Future.delayed(const Duration(milliseconds: 100));
        final st = await _app.communicator!.bleCentralState();
        if (!mounted) return;
        setState(() => _state = st);
        if (st.connState == 2) {
          await _refreshState(); // pick up the negotiated MTU
          break;
        }
        if (st.connState == 0 || st.connState == 3) {
          setState(() => _error = localizations.ble_connection_failed);
          break;
        }
      }
    } on FormatException catch (e) {
      setState(() => _error = localizations.ble_connect_error(e.message));
    } catch (e) {
      setState(() => _error = localizations.ble_connect_error(e.toString()));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _discover() async {
    final localizations = AppLocalizations.of(context)!;
    setState(() {
      _busy = true;
      _error = null;
      _chars = [];
      _services = [];
    });
    try {
      await _app.communicator!.bleGattDiscover();
      BleCentralState? terminalState;
      for (int i = 0; i < 50 && mounted; i++) {
        await Future.delayed(const Duration(milliseconds: 100));
        final st = await _app.communicator!.bleCentralState();
        if (!mounted) return;
        setState(() => _state = st);
        if (st.discState == 2 || st.discState == 3) {
          terminalState = st;
          break;
        }
      }
      if (terminalState == null) {
        throw TimeoutException(localizations.ble_discovery_timeout);
      }
      if (terminalState.discState == 3) {
        throw StateError(localizations.ble_discovery_failed);
      }
      final chars = await _app.communicator!.bleGattChars();
      // Also discover primary services so characteristics can be grouped.
      final services = _supportsCommands(const [
        ChameleonCommand.bleSvcDiscover,
        ChameleonCommand.bleSvcGet,
      ])
          ? await _app.communicator!.bleServices()
          : <Map<String, int>>[];
      if (mounted) {
        setState(() {
          _chars = chars;
          _services = services;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error =
            localizations.ble_discovery_operation_failed(e.toString()));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _readChar(int handle) async {
    final localizations = AppLocalizations.of(context)!;
    late final int status;
    late final Uint8List value;
    try {
      (status, value) = await _app.communicator!.bleGattRead(handle);
    } catch (e) {
      if (mounted) {
        setState(() => _error = localizations.ble_read_failed(e.toString()));
      }
      return;
    }
    if (!mounted) return;
    String text;
    if (status == 0) {
      text = value.isEmpty
          ? localizations.ble_empty_value
          : bleFormatHexBytes(value);
    } else if (status < 0) {
      text = localizations.ble_operation_timeout;
    } else {
      text = localizations.ble_att_error(bleAttStatusDescription(status));
    }
    setState(() => _readValues[handle] = text);
  }

  // Prompt for a hex value and write it to a characteristic (point-to-point).
  Future<void> _writeChar(BleCharacteristic c) async {
    final localizations = AppLocalizations.of(context)!;
    final controller = TextEditingController();
    final input = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(localizations.ble_write_handle_title(
            '0x${c.handle.toRadixString(16).padLeft(4, '0')}')),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(
              labelText: localizations.ble_value_hex, hintText: '0100'),
          style: const TextStyle(fontFamily: 'RobotoMono'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(localizations.cancel)),
          TextButton(
              onPressed: () => Navigator.pop(ctx, controller.text),
              child: Text(localizations.write)),
        ],
      ),
    );
    if (input == null || input.trim().isEmpty) return;
    Uint8List data;
    try {
      data = bleParseHexBytes(input.replaceAll(' ', ''));
    } catch (_) {
      if (mounted) setState(() => _error = localizations.invalid_hex_input);
      return;
    }
    final maxWriteLength = _mtu > 3 ? _mtu - 3 : 0;
    if (data.length > maxWriteLength) {
      if (mounted) {
        setState(() => _error =
            localizations.ble_write_too_long(data.length, maxWriteLength));
      }
      return;
    }
    int status;
    try {
      status = await _app.communicator!.bleGattWrite(c.handle, data);
    } catch (e) {
      if (mounted) {
        setState(() => _error = localizations.ble_write_failed(e.toString()));
      }
      return;
    }
    if (!mounted) return;
    final String msg = status == 0
        ? localizations.ble_write_success(
            '0x${c.handle.toRadixString(16).padLeft(4, '0')}')
        : status < 0
            ? localizations.ble_write_timeout
            : localizations.ble_write_rejected(bleAttStatusDescription(status));
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  // List all GATT descriptors of the connected target in a dialog.
  Future<void> _showDescriptors() async {
    final localizations = AppLocalizations.of(context)!;
    late final List<Map<String, int>> descs;
    try {
      descs = await _app.communicator!.bleDescriptors();
    } catch (e) {
      if (mounted) {
        setState(() => _error =
            localizations.ble_descriptor_discovery_failed(e.toString()));
      }
      return;
    }
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(localizations.ble_descriptors),
        content: SingleChildScrollView(
          child: descs.isEmpty
              ? Text(localizations.ble_no_descriptors)
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final d in descs)
                      Text(
                          bleUuidName(d['uuid'] ?? 0).isEmpty
                              ? localizations.ble_descriptor_row(
                                  '0x${(d['handle'] ?? 0).toRadixString(16).padLeft(4, '0')}',
                                  '0x${(d['uuid'] ?? 0).toRadixString(16).padLeft(4, '0')}')
                              : localizations.ble_descriptor_named_row(
                                  '0x${(d['handle'] ?? 0).toRadixString(16).padLeft(4, '0')}',
                                  '0x${(d['uuid'] ?? 0).toRadixString(16).padLeft(4, '0')}',
                                  bleUuidName(d['uuid'] ?? 0)),
                          style: const TextStyle(
                              fontFamily: 'RobotoMono', fontSize: 12)),
                  ],
                ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(localizations.close)),
        ],
      ),
    );
  }

  // Read the connected target's standard device information (GAP name/appearance,
  // Device Information Service, battery level) in a dialog. Point-to-point,
  // read-only; run after Discover (handles come from the characteristic table).
  String _localizedDeviceInfoValue(
      AppLocalizations localizations, int uuid, int status, Uint8List data) {
    if (status != 0) {
      return localizations
          .ble_device_info_read_failed(bleAttStatusDescription(status));
    }
    final value = bleDeviceInfoValue(uuid, status, data);
    return value == '(empty)' ? localizations.ble_empty_value : value;
  }

  Future<void> _showDeviceInfo() async {
    final localizations = AppLocalizations.of(context)!;
    late final List<Map<String, dynamic>> fields;
    try {
      fields = await _app.communicator!.bleDeviceInfo();
    } catch (e) {
      if (mounted) {
        setState(
            () => _error = localizations.ble_device_info_failed(e.toString()));
      }
      return;
    }
    if (!mounted) return;
    // Keep only characteristics the target actually exposes (status != 0xFF).
    final present = fields.where((f) => (f['status'] as int) != 0xFF).toList();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(localizations.ble_device_info),
        content: SingleChildScrollView(
          child: present.isEmpty
              ? Text(localizations.ble_no_device_info)
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final f in present)
                      Text(
                          '${bleDeviceInfoLabel(f['uuid'] as int)}: '
                          '${_localizedDeviceInfoValue(localizations, f['uuid'] as int, f['status'] as int, f['data'] as Uint8List)}',
                          style: const TextStyle(
                              fontFamily: 'RobotoMono', fontSize: 12)),
                  ],
                ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(localizations.close)),
        ],
      ),
    );
  }

  // Subscribe/unsubscribe to notifications on a characteristic. Uses the common
  // CCCD-at-(value handle + 1) layout. Receive-only: streams the target's own
  // notifications, sends nothing but the one CCCD write.
  Future<void> _toggleNotify(BleCharacteristic c) async {
    final localizations = AppLocalizations.of(context)!;
    if (_notifying) {
      final cccd = _notifCccd;
      _notificationGeneration++;
      _notifying = false;
      if (mounted) {
        setState(() {
          _notifCccd = null;
          _notifValueHandle = null;
          _notifs = [];
        });
      }
      if (cccd != null) {
        try {
          await _app.communicator!.bleSubscribe(cccd, 0);
        } catch (e) {
          if (mounted) {
            setState(() =>
                _error = localizations.ble_unsubscribe_failed(e.toString()));
          }
        }
      }
      return;
    }
    final generation = ++_notificationGeneration;
    int? subscribedCccd;
    try {
      final cccd = await _app.communicator!.bleFindCccd(c.handle);
      subscribedCccd = cccd;
      if (!mounted || generation != _notificationGeneration) return;
      final mode = (c.props & 0x10 != 0) ? 1 : 2; // notify else indicate
      await _app.communicator!.bleSubscribe(cccd, mode);
      if (!mounted || generation != _notificationGeneration) {
        try {
          await _app.communicator!.bleSubscribe(cccd, 0);
        } catch (_) {}
        return;
      }
      setState(() {
        _notifying = true;
        _notifCccd = cccd;
        _notifValueHandle = c.handle;
        _notifs = [];
      });
      int seen = 0;
      while (_notifying &&
          !_disposing &&
          mounted &&
          generation == _notificationGeneration) {
        await Future.delayed(const Duration(milliseconds: 300));
        if (!_notifying ||
            _disposing ||
            !mounted ||
            generation != _notificationGeneration) {
          break;
        }
        final list = await _app.communicator!.bleGetNotifications();
        if (!mounted || generation != _notificationGeneration) return;
        if (list.length > seen) {
          seen = list.length;
          setState(() => _notifs = list);
        }
      }
    } catch (e) {
      if (subscribedCccd != null) {
        try {
          await _app.communicator!.bleSubscribe(subscribedCccd, 0);
        } catch (_) {}
      }
      if (mounted && generation == _notificationGeneration) {
        setState(() {
          _notifying = false;
          _notifCccd = null;
          _notifValueHandle = null;
          _error =
              localizations.ble_notification_subscription_failed(e.toString());
        });
      }
    }
  }

  Future<void> _startFuzz() async {
    final localizations = AppLocalizations.of(context)!;
    final handle =
        int.tryParse(_handle.text.trim().replaceFirst('0x', ''), radix: 16) ??
            0;
    if (handle == 0) {
      setState(() => _error = localizations.ble_valid_handle_required);
      return;
    }
    final count = int.tryParse(_count.text.trim()) ?? 200;
    final interval = int.tryParse(_interval.text.trim()) ?? 50;
    if (handle < 1 || handle > 0xFFFF) {
      setState(() => _error = localizations.ble_handle_range_error);
      return;
    }
    if (count < 0 || count > 0xFFFF) {
      setState(() => _error = localizations.ble_count_range_error);
      return;
    }
    if (interval < 10 || interval > 0xFFFF) {
      setState(() => _error = localizations.ble_interval_range_error);
      return;
    }
    setState(() {
      _error = null;
      _log = [];
    });
    try {
      final current = await _app.communicator!.bleCentralState();
      if (current.hasOperationState && current.floodState == 1) {
        if (mounted) {
          setState(() => _error = localizations.ble_flood_active_error);
        }
        return;
      }
      await _app.communicator!
          .bleFuzzStart(handle, maxIterations: count, intervalMs: interval);
    } catch (e) {
      if (mounted) {
        setState(
            () => _error = localizations.ble_fuzz_start_failed(e.toString()));
      }
      return;
    }
    final generation = ++_fuzzGeneration;
    setState(() => _fuzzing = true);
    // Poll state until the run finishes, the target drops, or we stop.
    var releaseTarget = true;
    while (
        _fuzzing && !_disposing && mounted && generation == _fuzzGeneration) {
      await Future.delayed(const Duration(milliseconds: 300));
      if (!_fuzzing ||
          _disposing ||
          !mounted ||
          generation != _fuzzGeneration) {
        break;
      }
      BleCentralState st;
      try {
        st = await _app.communicator!.bleCentralState();
      } catch (e) {
        if (mounted && generation == _fuzzGeneration) {
          setState(() => _error =
              localizations.ble_fuzz_state_refresh_failed(e.toString()));
        }
        break;
      }
      if (!mounted) return;
      setState(() => _state = st);
      if (!st.targetAlive && st.connState == 3) {
        setState(() => _error = localizations.ble_target_dropped);
        break;
      }
      if (st.fuzzState != 1) {
        if (st.hasOperationState && st.floodState == 1) {
          releaseTarget = false;
          setState(() => _error = localizations.ble_fuzz_stopped_by_operation);
        }
        break;
      }
    }
    if (!_disposing && generation == _fuzzGeneration) {
      await _finishFuzz(stopDevice: true, disconnect: releaseTarget);
    }
  }

  Future<void> _finishFuzz(
      {required bool stopDevice, bool disconnect = true}) async {
    if (mounted) setState(() => _fuzzing = false);
    if (stopDevice) {
      try {
        await _app.communicator!.bleFuzzStop();
      } catch (_) {}
    }
    try {
      final log = await _app.communicator!.bleFuzzLog();
      if (mounted) setState(() => _log = log);
    } catch (_) {}
    // Batch finished (or cancelled): release the target so it can reconnect to
    // its normal source.
    if (disconnect) {
      await _disconnect(stopFuzz: false);
    }
  }

  Future<void> _stopFuzz() async {
    _fuzzGeneration++;
    _fuzzing = false;
    await _finishFuzz(stopDevice: true);
  }

  Future<void> _disconnect({bool stopFuzz = true}) async {
    final localizations = AppLocalizations.of(context)!;
    final communicator = _app.communicator!;
    final stopScan = _scanning;
    final wasFuzzing = stopFuzz && _fuzzing;
    final cccd = _notifCccd;
    if (mounted) {
      setState(() {
        _busy = true;
        _clearLocalActivity();
      });
    } else {
      _clearLocalActivity();
    }
    try {
      await _bestEffortStopDeviceActivity(communicator,
          stopScan: stopScan, stopFuzz: wasFuzzing, cccd: cccd);
      await communicator.bleDisconnect();
      for (var attempt = 0; attempt < 30 && mounted; attempt++) {
        final state = await communicator.bleCentralState();
        setState(() => _state = state);
        if (state.connState == 0 || state.connState == 3) break;
        await Future.delayed(const Duration(milliseconds: 100));
      }
      if (mounted) {
        setState(() {
          _chars = [];
          _services = [];
        });
      }
    } catch (e) {
      if (mounted) {
        setState(
            () => _error = localizations.ble_disconnect_failed(e.toString()));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ---- UI ---------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context)!;
    final app = context.watch<ChameleonGUIState>();
    final transportConnected =
        app.communicator != null && (app.connector?.connected ?? false);
    if (!transportConnected &&
        (_state != null ||
            _scanning ||
            _fuzzing ||
            _notifying ||
            _notifs.isNotEmpty)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || (_app.connector?.connected ?? false)) return;
        setState(() => _clearLocalActivity(clearCentralState: true));
      });
    }
    final tabBar = TabBar(
      controller: _tab,
      isScrollable: true,
      tabAlignment: TabAlignment.start,
      tabs: [
        Tab(
            text: localizations.ble_passive_scan,
            icon: const Icon(Icons.radar)),
        Tab(
            text: localizations.ble_directed_fuzz,
            icon: const Icon(Icons.bug_report)),
      ],
    );
    final body = !transportConnected
        ? Center(child: Text(localizations.ble_no_device_connected))
        : TabBarView(
            controller: _tab,
            children: [
              BleCapabilityGate(
                feature: localizations.ble_passive_scan,
                requiredCommands: const [
                  ChameleonCommand.bleScanStart,
                  ChameleonCommand.bleScanStop,
                  ChameleonCommand.bleScanGetCount,
                  ChameleonCommand.bleScanGetResults,
                ],
                child: _scanTab(context),
              ),
              BleCapabilityGate(
                feature: localizations.ble_directed_fuzz,
                requiredCommands: const [
                  ChameleonCommand.bleConnect,
                  ChameleonCommand.bleDisconnect,
                  ChameleonCommand.bleCentralState,
                  ChameleonCommand.bleGattDiscover,
                  ChameleonCommand.bleGattGetChars,
                  ChameleonCommand.bleFuzzStart,
                  ChameleonCommand.bleFuzzStop,
                  ChameleonCommand.bleFuzzGetLog,
                ],
                child: _fuzzTab(context),
              ),
            ],
          );
    final advertisingSupported = app.communicator == null ||
        (app.communicator!
                    .supportsCommandSync(ChameleonCommand.bleAdvertisingSet) !=
                false &&
            app.communicator!
                    .supportsCommandSync(ChameleonCommand.bleAdvertisingGet) !=
                false);
    final advertisingButton = IconButton(
      icon: const Icon(Icons.bluetooth_audio),
      tooltip: localizations.ble_toggle_local_advertising,
      onPressed: _connected && advertisingSupported ? _toggleAdvertising : null,
    );
    if (widget.embedded) {
      return Column(
        children: [
          Row(children: [Expanded(child: tabBar), advertisingButton]),
          Expanded(child: body),
        ],
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(localizations.ble_audit_title),
        actions: [advertisingButton],
        bottom: tabBar,
      ),
      body: body,
    );
  }

  Widget _scanTab(BuildContext context) {
    final localizations = AppLocalizations.of(context)!;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
              _activeScan
                  ? localizations.ble_active_scan_description
                  : localizations.ble_passive_scan_description,
              style: const TextStyle(fontStyle: FontStyle.italic)),
          const SizedBox(height: 12),
          LayoutBuilder(builder: (context, constraints) {
            final stacked = constraints.maxWidth < 360;
            return Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                SizedBox(
                  width: stacked ? constraints.maxWidth : 120,
                  child: TextField(
                    controller: _scanDuration,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                        labelText: localizations.ble_duration_seconds,
                        border: const OutlineInputBorder()),
                  ),
                ),
                SizedBox(
                  width: stacked ? constraints.maxWidth : null,
                  child: ElevatedButton.icon(
                    onPressed: _scanning ? null : _runScan,
                    icon: _scanning
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.search),
                    label: Text(_scanning
                        ? localizations.ble_scanning
                        : localizations.ble_scan),
                  ),
                ),
              ],
            );
          }),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: _activeScan,
            onChanged: _scanning
                ? null
                : (v) => setState(() => _activeScan = v ?? false),
            title: Text(localizations.ble_active_scan_option),
          ),
          const SizedBox(height: 8),
          if (_scanResults.isNotEmpty)
            BleResponsiveFieldGroup(
              breakpoint: 440,
              children: [
                TextField(
                  controller: _nameFilter,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                      labelText: localizations.ble_filter_by_name,
                      isDense: true,
                      border: const OutlineInputBorder()),
                ),
                TextField(
                  controller: _minRssi,
                  keyboardType: TextInputType.number,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                      labelText: localizations.ble_min_rssi,
                      isDense: true,
                      border: const OutlineInputBorder()),
                ),
              ],
            ),
          const SizedBox(height: 8),
          if (_error != null && _tab.index == 0)
            Text(_error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error)),
          if (_scanResults.isEmpty && !_scanning)
            Padding(
              padding: const EdgeInsets.only(top: 24),
              child: Text(localizations.ble_no_scan_results),
            ),
          for (final r in _visibleResults())
            Card(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ListTile(
                    onTap: () => _showDeviceDetails(r),
                    title: Text(
                        bleAdvertisingName(r.adv) ??
                            bleAddressFromLittleEndian(r.addr),
                        style: const TextStyle(fontFamily: 'RobotoMono')),
                    subtitle: Text([
                      if (bleAdvertisingName(r.adv) != null)
                        bleAddressFromLittleEndian(r.addr),
                      localizations.ble_scan_result_metadata(
                          r.addrType, r.rssi),
                      if (bleAdvertisingSummary(r.adv,
                              serviceAbbreviation:
                                  localizations.ble_service_abbreviation)
                          .isNotEmpty)
                        bleAdvertisingSummary(r.adv,
                            serviceAbbreviation:
                                localizations.ble_service_abbreviation),
                    ].join('  ·  ')),
                  ),
                  Padding(
                    padding:
                        const EdgeInsets.only(left: 16, right: 16, bottom: 4),
                    child: Wrap(
                      children: [
                        TextButton(
                          onPressed: () => _useAsTarget(r),
                          child: Text(localizations.ble_fuzz_this),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _fuzzTab(BuildContext context) {
    final localizations = AppLocalizations.of(context)!;
    final connected = _state?.connState == 2;
    final linkProbeSupported =
        _supportsCommands(const [ChameleonCommand.bleLinkProbe]);
    final readSupported = _supportsCommands(const [
      ChameleonCommand.bleGattRead,
      ChameleonCommand.bleGattGetRead,
    ]);
    final writeSupported = _supportsCommands(const [
      ChameleonCommand.bleGattWrite,
      ChameleonCommand.bleGetWrite,
    ]);
    final notifySupported = _supportsCommands(const [
      ChameleonCommand.bleSubscribe,
      ChameleonCommand.bleGetNotifications,
      ChameleonCommand.bleFindCccd,
      ChameleonCommand.bleGetCccd,
    ]);
    final descriptorSupported = _supportsCommands(const [
      ChameleonCommand.bleDescDiscover,
      ChameleonCommand.bleDescGet,
    ]);
    final deviceInfoSupported = _supportsCommands(const [
      ChameleonCommand.bleDeviceInfo,
      ChameleonCommand.bleGetDeviceInfo,
    ]);
    String fuzzLogEntry(BleFuzzLogEntry entry) {
      final status = entry.status == 0
          ? localizations.ble_status_ok
          : localizations
              .ble_status_error_code('0x${entry.status.toRadixString(16)}');
      return localizations.ble_fuzz_log_entry(
          entry.index, entry.length, status, bleFormatHexBytes(entry.data));
    }

    String notificationEntry(Map<String, dynamic> notification) {
      final handle =
          '0x${(notification['handle'] as int).toRadixString(16).padLeft(4, '0')}';
      return localizations.ble_notification_log_entry(
          handle, bleFormatHexBytes(notification['data'] as Uint8List));
    }

    Widget characteristicTile(BleCharacteristic characteristic) =>
        BleCharacteristicTile(
          characteristic: characteristic,
          readValue: _readValues[characteristic.handle],
          notifying: _notifying && _notifValueHandle == characteristic.handle,
          readSupported: readSupported,
          writeSupported: writeSupported,
          notifySupported: notifySupported,
          onRead: () => _readChar(characteristic.handle),
          onWrite: () => _writeChar(characteristic),
          onSelectFuzz: () => setState(() => _handle.text =
              '0x${characteristic.handle.toRadixString(16).padLeft(4, '0')}'),
          onToggleNotify: () => _toggleNotify(characteristic),
        );
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(localizations.ble_directed_fuzz_description,
              style: const TextStyle(fontStyle: FontStyle.italic)),
          const SizedBox(height: 12),
          BleResponsiveFieldGroup(
            breakpoint: 520,
            children: [
              TextField(
                controller: _addr,
                decoration: InputDecoration(
                    labelText: localizations.ble_target_address,
                    border: const OutlineInputBorder()),
                style: const TextStyle(fontFamily: 'RobotoMono'),
              ),
              DropdownButton<int>(
                // Defensive: the value passed to the dropdown is always clamped to
                // a range that has a matching item, so no stale/unexpected
                // _addrType can ever trip the "exactly one item" assertion.
                value: (_addrType >= 0 && _addrType <= 3) ? _addrType : 0,
                isExpanded: true,
                items: [
                  DropdownMenuItem(
                      value: 0,
                      child: Text(localizations.ble_address_type_public,
                          overflow: TextOverflow.ellipsis)),
                  DropdownMenuItem(
                      value: 1,
                      child: Text(localizations.ble_address_type_random,
                          overflow: TextOverflow.ellipsis)),
                  DropdownMenuItem(
                      value: 2,
                      child: Text(localizations.ble_address_type_random_rpa,
                          overflow: TextOverflow.ellipsis)),
                  DropdownMenuItem(
                      value: 3,
                      child: Text(localizations.ble_address_type_random_nrpa,
                          overflow: TextOverflow.ellipsis)),
                ],
                onChanged: (v) => setState(() => _addrType = v ?? 0),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: [
            ElevatedButton.icon(
              onPressed: _busy ? null : _connect,
              icon: const Icon(Icons.link),
              label: Text(localizations.connect),
            ),
            OutlinedButton.icon(
              onPressed: (_busy || !connected || !linkProbeSupported)
                  ? null
                  : () => _probeLink(),
              icon: const Icon(Icons.wifi_tethering),
              label: Text(localizations.ble_ping),
            ),
            OutlinedButton.icon(
              onPressed: (_busy || connected || !linkProbeSupported)
                  ? null
                  : () => _probeLink(globalMode: true),
              icon: const Icon(Icons.cell_tower),
              label: Text(localizations.ble_probe_scan_buffer),
            ),
            OutlinedButton.icon(
              onPressed: (_busy || !connected) ? null : _discover,
              icon: const Icon(Icons.travel_explore),
              label: Text(localizations.ble_discover),
            ),
            OutlinedButton.icon(
              onPressed: _busy ? null : _disconnect,
              icon: const Icon(Icons.link_off),
              label: Text(localizations.ble_disconnect),
            ),
            IconButton(
              onPressed: _busy
                  ? null
                  : () => _refreshState().catchError((Object error) {
                        if (mounted) {
                          setState(() => _error = localizations
                              .ble_state_refresh_failed(error.toString()));
                        }
                      }),
              icon: const Icon(Icons.refresh),
              tooltip: localizations.ble_refresh_central_state,
            ),
          ]),
          const SizedBox(height: 12),
          if (_state != null) BleAuditStatus(state: _state!, mtu: _mtu),
          if (_error != null && _tab.index == 1) ...[
            const SizedBox(height: 8),
            Text(_error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
          if (_chars.isNotEmpty) ...[
            const SizedBox(height: 16),
            Row(children: [
              Expanded(
                child: Text(localizations.ble_characteristics,
                    style: const TextStyle(fontWeight: FontWeight.bold)),
              ),
              IconButton(
                tooltip: localizations.ble_list_descriptors,
                icon: const Icon(Icons.list_alt, size: 18),
                onPressed: descriptorSupported ? _showDescriptors : null,
              ),
              IconButton(
                tooltip: localizations.ble_device_info_tooltip,
                icon: const Icon(Icons.info_outline, size: 18),
                onPressed: deviceInfoSupported ? _showDeviceInfo : null,
              ),
              IconButton(
                tooltip: localizations.ble_copy_characteristics,
                icon: const Icon(Icons.copy, size: 18),
                onPressed: () {
                  Clipboard.setData(ClipboardData(
                      text: _chars.map((c) {
                    final nm = bleUuidName(c.uuid);
                    return 'handle 0x${c.handle.toRadixString(16).padLeft(4, '0')}\t'
                        'UUID 0x${c.uuid.toRadixString(16).padLeft(4, '0')}'
                        '${nm.isNotEmpty ? ' ($nm)' : ''}\t[${bleCharacteristicPropertiesString(c.props)}]';
                  }).join('\n')));
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text(localizations
                          .ble_copied_characteristics(_chars.length))));
                },
              ),
            ]),
            // Grouped under primary services when known, else a flat list.
            if (_services.isNotEmpty) ...[
              for (final s in _services) ...[
                Padding(
                  padding: const EdgeInsets.only(top: 8, bottom: 2),
                  child: Text(
                      bleUuidName(s['uuid'] ?? 0).isEmpty
                          ? localizations.ble_service_row(
                              '0x${(s['uuid'] ?? 0).toRadixString(16).padLeft(4, '0')}',
                              '0x${(s['start'] ?? 0).toRadixString(16).padLeft(4, '0')}',
                              '0x${(s['end'] ?? 0).toRadixString(16).padLeft(4, '0')}')
                          : localizations.ble_named_service_row(
                              '0x${(s['uuid'] ?? 0).toRadixString(16).padLeft(4, '0')}',
                              bleUuidName(s['uuid'] ?? 0),
                              '0x${(s['start'] ?? 0).toRadixString(16).padLeft(4, '0')}',
                              '0x${(s['end'] ?? 0).toRadixString(16).padLeft(4, '0')}'),
                      style: TextStyle(
                          fontFamily: 'RobotoMono',
                          fontWeight: FontWeight.w600,
                          color: Theme.of(context).colorScheme.primary)),
                ),
                for (final c in _chars)
                  if (c.handle >= (s['start'] ?? 0) &&
                      c.handle <= (s['end'] ?? 0))
                    characteristicTile(c),
              ],
              // Characteristics that fell outside any discovered service.
              for (final c in _chars)
                if (!_services.any((s) =>
                    c.handle >= (s['start'] ?? 0) &&
                    c.handle <= (s['end'] ?? 0)))
                  characteristicTile(c),
            ] else
              for (final c in _chars) characteristicTile(c),
          ],
          const SizedBox(height: 16),
          Text(localizations.ble_fuzz,
              style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          BleResponsiveFieldGroup(
            children: [
              TextField(
                controller: _handle,
                decoration: InputDecoration(
                    labelText: localizations.ble_handle_hex,
                    border: const OutlineInputBorder()),
                style: const TextStyle(fontFamily: 'RobotoMono'),
              ),
              TextField(
                controller: _count,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                    labelText: localizations.ble_count,
                    border: const OutlineInputBorder()),
              ),
              TextField(
                controller: _interval,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                    labelText: localizations.ble_interval_ms,
                    border: const OutlineInputBorder()),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: [
            ElevatedButton.icon(
              onPressed: (!connected || _fuzzing) ? null : _startFuzz,
              icon: _fuzzing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.play_arrow),
              label: Text(_fuzzing
                  ? localizations.ble_fuzzing
                  : localizations.ble_start_fuzz),
            ),
            OutlinedButton.icon(
              onPressed: _fuzzing ? _stopFuzz : null,
              icon: const Icon(Icons.cancel_outlined),
              label: Text(localizations.cancel),
            ),
          ]),
          const SizedBox(height: 6),
          Row(children: [
            Icon(Icons.info_outline,
                size: 14, color: Theme.of(context).colorScheme.outline),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                _fuzzing
                    ? localizations.ble_fuzz_running_description
                    : localizations.ble_fuzz_idle_description,
                style: TextStyle(
                    fontSize: 12, color: Theme.of(context).colorScheme.outline),
              ),
            ),
          ]),
          if (_log.isNotEmpty) ...[
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: Text(localizations.ble_log_summary(_log.length),
                    style: const TextStyle(fontWeight: FontWeight.bold)),
              ),
              IconButton(
                tooltip: localizations.ble_copy_full_log,
                icon: const Icon(Icons.copy, size: 18),
                onPressed: () {
                  Clipboard.setData(
                      ClipboardData(text: _log.map(fuzzLogEntry).join('\n')));
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text(
                          localizations.ble_copied_log_entries(_log.length))));
                },
              ),
            ]),
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(top: 6),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: SelectableText(
                _log.reversed
                    .take(15)
                    .toList()
                    .reversed
                    .map(fuzzLogEntry)
                    .join('\n'),
                style: const TextStyle(fontFamily: 'RobotoMono', fontSize: 12),
              ),
            ),
          ],
          if (_notifs.isNotEmpty) ...[
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: Text(
                    localizations.ble_notifications_summary(_notifs.length),
                    style: const TextStyle(fontWeight: FontWeight.bold)),
              ),
              IconButton(
                tooltip: localizations.ble_copy_all_notifications,
                icon: const Icon(Icons.copy, size: 18),
                onPressed: () {
                  Clipboard.setData(ClipboardData(
                      text: _notifs.map(notificationEntry).join('\n')));
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text(localizations
                          .ble_copied_notifications(_notifs.length))));
                },
              ),
            ]),
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(top: 6),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: SelectableText(
                _notifs.reversed
                    .take(15)
                    .toList()
                    .reversed
                    .map(notificationEntry)
                    .join('\n'),
                style: const TextStyle(fontFamily: 'RobotoMono', fontSize: 12),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

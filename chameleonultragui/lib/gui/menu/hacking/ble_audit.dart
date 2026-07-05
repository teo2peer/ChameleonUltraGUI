import 'package:chameleonultragui/helpers/definitions.dart';
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
  const BleAuditPage({super.key});

  @override
  BleAuditPageState createState() => BleAuditPageState();
}

class BleAuditPageState extends State<BleAuditPage>
    with SingleTickerProviderStateMixin {
  static const int _statusSuccess = 0x68; // firmware STATUS_SUCCESS

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
  List<Map<String, dynamic>> _notifs = [];
  bool _busy = false;
  bool _fuzzing = false;
  String? _error;

  ChameleonGUIState get _app => context.read<ChameleonGUIState>();
  bool get _connected => _app.connector?.connected ?? false;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _fuzzing = false; // stop any polling loop
    _notifying = false;
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

  // ---- helpers ----------------------------------------------------------
  static Uint8List _macToLe(String mac) {
    final parts = mac.trim().replaceAll('-', ':').split(':');
    if (parts.length != 6) {
      throw const FormatException('address must be 6 hex octets');
    }
    final b = parts.map((p) => int.parse(p, radix: 16)).toList();
    return Uint8List.fromList(b.reversed.toList()); // display MSB-first -> LE
  }

  static String _leToMac(Uint8List le) {
    final msb = le.reversed
        .map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase());
    return msb.join(':');
  }

  static String? _advName(Uint8List adv) {
    int i = 0;
    String? name;
    while (i < adv.length) {
      final ln = adv[i];
      if (ln == 0) break;
      final type = (i + 1 < adv.length) ? adv[i + 1] : 0;
      final end = (i + 1 + ln <= adv.length) ? i + 1 + ln : adv.length;
      final value = adv.sublist((i + 2 <= end) ? i + 2 : end, end);
      if (type == 0x08 || type == 0x09) {
        name = String.fromCharCodes(value);
      }
      i += ln + 1;
    }
    return name;
  }

  static const Map<int, String> _companyIds = {
    0x0006: 'Microsoft',
    0x0059: 'Nordic',
    0x004C: 'Apple',
    0x0075: 'Samsung',
    0x0087: 'Garmin',
    0x00E0: 'Google',
    0x0157: 'Huawei',
    0x0171: 'Amazon',
    0x02E5: 'Espressif',
    0x038F: 'Xiaomi',
    0x0499: 'Ruuvi',
    0x0A12: 'Sony',
  };

  // A compact decode of the advertising data for the scan list (flags, service
  // count, manufacturer, TX power).
  static String _advSummary(Uint8List adv) {
    final parts = <String>[];
    int i = 0;
    while (i + 1 < adv.length) {
      final ln = adv[i];
      if (ln == 0) break;
      final type = adv[i + 1];
      final end = (i + 1 + ln <= adv.length) ? i + 1 + ln : adv.length;
      final value = adv.sublist((i + 2 <= end) ? i + 2 : end, end);
      if (type == 0x01 && value.isNotEmpty) {
        final f = <String>[];
        if (value[0] & 0x02 != 0) f.add('LE-gen');
        if (value[0] & 0x04 != 0) f.add('no-BR/EDR');
        if (f.isNotEmpty) parts.add(f.join('|'));
      } else if ((type == 0x02 || type == 0x03) && value.length >= 2) {
        parts.add('${value.length ~/ 2} svc');
      } else if (type == 0x0A && value.isNotEmpty) {
        parts.add('${value[0] > 127 ? value[0] - 256 : value[0]}dBm');
      } else if (type == 0xFF && value.length >= 2) {
        final company = value[0] | (value[1] << 8);
        parts.add(_companyIds[company] ??
            '0x${company.toRadixString(16).padLeft(4, '0')}');
      }
      i += ln + 1;
    }
    return parts.join(' · ');
  }

  // Full advertising-data breakdown (one string per AD structure) for the
  // per-device details dialog.
  static List<String> _advDetails(Uint8List adv) {
    final fields = <String>[];
    int i = 0;
    while (i + 1 < adv.length) {
      final ln = adv[i];
      if (ln == 0) break;
      final type = adv[i + 1];
      final end = (i + 1 + ln <= adv.length) ? i + 1 + ln : adv.length;
      final value = adv.sublist((i + 2 <= end) ? i + 2 : end, end);
      if (type == 0x01 && value.isNotEmpty) {
        final f = <String>[];
        if (value[0] & 0x01 != 0) f.add('LE-limited');
        if (value[0] & 0x02 != 0) f.add('LE-general');
        if (value[0] & 0x04 != 0) f.add('no-BR/EDR');
        fields.add('flags: ${f.isEmpty ? '0x${value[0].toRadixString(16)}' : f.join('|')}');
      } else if (type == 0x02 || type == 0x03) {
        final us = <String>[];
        for (int j = 0; j + 1 < value.length; j += 2) {
          final u = value[j] | (value[j + 1] << 8);
          final nm = _uuidName(u);
          us.add('0x${u.toRadixString(16).padLeft(4, '0')}${nm.isNotEmpty ? '($nm)' : ''}');
        }
        if (us.isNotEmpty) fields.add('services16: ${us.join(', ')}');
      } else if (type == 0x06 || type == 0x07) {
        fields.add('services128: ${value.length ~/ 16}');
      } else if (type == 0x08 || type == 0x09) {
        fields.add('name: ${String.fromCharCodes(value)}');
      } else if (type == 0x0A && value.isNotEmpty) {
        fields.add('tx_power: ${value[0] > 127 ? value[0] - 256 : value[0]} dBm');
      } else if (type == 0x19 && value.length >= 2) {
        final appv = value[0] | (value[1] << 8);
        final appn = _appearanceName(appv);
        fields.add('appearance: 0x${appv.toRadixString(16).padLeft(4, '0')}'
            '${appn.isNotEmpty ? ' ($appn)' : ''}');
      } else if (type == 0xFF && value.length >= 2) {
        final c = value[0] | (value[1] << 8);
        final cn = _companyIds[c] ?? '0x${c.toRadixString(16).padLeft(4, '0')}';
        fields.add('mfr: $cn [${_hex(value.sublist(2))}]');
      } else if (type == 0x16 && value.length >= 2) {
        final s = value[0] | (value[1] << 8);
        fields.add('svc_data 0x${s.toRadixString(16).padLeft(4, '0')}: ${_hex(value.sublist(2))}');
      }
      i += ln + 1;
    }
    return fields;
  }

  static String _propsStr(int p) {
    final names = <String>[];
    if (p & 0x02 != 0) names.add('read');
    if (p & 0x04 != 0) names.add('write-nr');
    if (p & 0x08 != 0) names.add('write');
    if (p & 0x10 != 0) names.add('notify');
    if (p & 0x20 != 0) names.add('indicate');
    return names.isEmpty ? '-' : names.join(',');
  }

  // Common Bluetooth SIG 16-bit UUIDs (services 0x18xx, characteristics 0x2Axx).
  static const Map<int, String> _uuidNames = {
    0x1800: 'Generic Access', 0x1801: 'Generic Attribute', 0x1802: 'Immediate Alert',
    0x1803: 'Link Loss', 0x1804: 'Tx Power', 0x1805: 'Current Time',
    0x1808: 'Glucose', 0x1809: 'Health Thermometer', 0x180A: 'Device Information',
    0x180D: 'Heart Rate', 0x180F: 'Battery', 0x1810: 'Blood Pressure',
    0x1812: 'HID', 0x1816: 'Cycling Speed', 0x1818: 'Cycling Power',
    0x1819: 'Location and Navigation', 0x181A: 'Environmental Sensing',
    0x181C: 'User Data', 0x1826: 'Fitness Machine',
    0xFE59: 'Nordic DFU', 0xFD6F: 'Exposure Notification',
    0x2A00: 'Device Name', 0x2A01: 'Appearance', 0x2A04: 'Preferred Conn Params',
    0x2A05: 'Service Changed', 0x2A06: 'Alert Level', 0x2A19: 'Battery Level',
    0x2A23: 'System ID', 0x2A24: 'Model Number', 0x2A25: 'Serial Number',
    0x2A26: 'Firmware Rev', 0x2A27: 'Hardware Rev', 0x2A28: 'Software Rev',
    0x2A29: 'Manufacturer', 0x2A2B: 'Current Time', 0x2A37: 'Heart Rate Meas',
    0x2A38: 'Body Sensor Loc', 0x2A50: 'PnP ID', 0x2A6E: 'Temperature',
    0x2A6F: 'Humidity',
    // descriptors
    0x2900: 'Char Ext Props', 0x2901: 'Char User Desc', 0x2902: 'CCCD',
    0x2903: 'Server Char Config', 0x2904: 'Char Presentation Fmt',
    0x2905: 'Char Aggregate Fmt', 0x2908: 'Report Reference',
  };

  static String _uuidName(int uuid) => _uuidNames[uuid] ?? '';

  // BLE appearance categories (top 10 bits) + a few specific subtypes.
  static const Map<int, String> _appearanceCat = {
    0x0040: 'Phone', 0x0080: 'Computer', 0x00C0: 'Watch', 0x0100: 'Clock',
    0x0140: 'Display', 0x0180: 'Remote Control', 0x01C0: 'Eye-glasses',
    0x0200: 'Tag', 0x0240: 'Keyring', 0x0280: 'Media Player',
    0x02C0: 'Barcode Scanner', 0x0300: 'Thermometer', 0x0340: 'Heart Rate Sensor',
    0x0380: 'Blood Pressure', 0x03C0: 'HID', 0x0400: 'Glucose Meter',
    0x0440: 'Running/Walking Sensor', 0x0480: 'Cycling',
  };
  static const Map<int, String> _appearanceSpecific = {
    0x03C1: 'Keyboard', 0x03C2: 'Mouse', 0x03C3: 'Joystick', 0x03C4: 'Gamepad',
    0x0341: 'Heart Rate Belt',
  };

  static String _appearanceName(int v) =>
      _appearanceSpecific[v] ?? _appearanceCat[v & 0xFFC0] ?? '';

  bool _isWritable(int p) => (p & 0x0C) != 0; // write or write-without-response

  // ---- passive scan -----------------------------------------------------
  Future<void> _runScan() async {
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
      await _app.communicator!.blePassiveScanStop();
      final results = await _app.communicator!.blePassiveScanResults();
      if (!mounted) return;
      setState(() => _scanResults = results);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  List<BleScanResult> _visibleResults() {
    final name = _nameFilter.text.trim().toLowerCase();
    final minRssi = int.tryParse(_minRssi.text.trim());
    return _scanResults.where((r) {
      if (minRssi != null && r.rssi < minRssi) return false;
      if (name.isNotEmpty && !(_advName(r.adv)?.toLowerCase() ?? '').contains(name)) {
        return false;
      }
      return true;
    }).toList();
  }

  void _useAsTarget(BleScanResult r) {
    setState(() {
      _addr.text = _leToMac(r.addr);
      // The scanner can report addr types 0-3 (and rarely 0x7F anonymous);
      // clamp to a value the dropdown actually has an item for, else the
      // DropdownButton throws on the next build.
      _addrType = (r.addrType >= 0 && r.addrType <= 3) ? r.addrType : 1;
    });
    _tab.animateTo(1);
  }

  void _showDeviceDetails(BleScanResult r) {
    final details = _advDetails(r.adv);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(_leToMac(r.addr),
            style: const TextStyle(fontFamily: 'RobotoMono')),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('type: ${r.addrType}    RSSI: ${r.rssi} dBm'),
              const SizedBox(height: 8),
              if (details.isEmpty) const Text('(no advertising data)'),
              for (final d in details)
                Text(d,
                    style:
                        const TextStyle(fontFamily: 'RobotoMono', fontSize: 12)),
              const SizedBox(height: 8),
              const Text('raw:', style: TextStyle(fontWeight: FontWeight.bold)),
              SelectableText(_hex(r.adv),
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
            child: const Text('Fuzz this'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  // ---- directed fuzz ----------------------------------------------------
  Future<void> _refreshState() async {
    final st = await _app.communicator!.bleCentralState();
    int mtu = _mtu;
    if (st.connState == 2) {
      try {
        mtu = await _app.communicator!.bleGetMtu();
      } catch (_) {}
    }
    if (mounted) {
      setState(() {
        _state = st;
        _mtu = mtu;
      });
    }
  }

  // Toggle the device's OWN advertising (discoverable) — controls only this
  // Chameleon, does not touch other devices.
  Future<void> _toggleAdvertising() async {
    try {
      final cur = await _app.communicator!.bleAdvertisingGet();
      final now = await _app.communicator!.bleAdvertisingSet(!cur);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Local advertising ${now ? 'on' : 'off'}')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Advertising toggle failed: $e')));
    }
  }

  Future<void> _probeLink() async {
    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      // Single-target liveness ping of the one connected target — never the
      // batch/global mode.
      final status = await _app.communicator!.bleLinkProbe(globalMode: false);
      if (!mounted) return;
      if (status != _statusSuccess) {
        setState(() {
          _error = 'Ping rejected (0x${status.toRadixString(16)}) — connect to a target first';
        });
        return;
      }

      for (int i = 0; i < 80 && mounted; i++) {
        await Future.delayed(const Duration(milliseconds: 100));
        final st = await _app.communicator!.bleCentralState();
        if (!mounted) return;
        setState(() => _state = st);
        if (st.probeState == 2) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('Target responded to the link probe')));
          return;
        }
        if (st.probeState == 3) {
          setState(() {
            _error = 'Ping failed (0x${st.probeResult.toRadixString(16)})';
          });
          return;
        }
      }

      if (mounted) {
        setState(() => _error = 'Ping timed out');
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _connect() async {
    setState(() {
      _busy = true;
      _error = null;
      _chars = [];
      _log = [];
    });
    try {
      final le = _macToLe(_addr.text);
      final status = await _app.communicator!.bleConnect(le, addrType: _addrType);
      if (status != _statusSuccess) {
        setState(() => _error = 'Connect rejected by device (0x${status.toRadixString(16)})');
        return;
      }
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
          setState(() => _error = 'Connection failed / timed out');
          break;
        }
      }
    } on FormatException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _discover() async {
    setState(() {
      _busy = true;
      _error = null;
      _chars = [];
      _services = [];
    });
    try {
      final status = await _app.communicator!.bleGattDiscover();
      if (status != _statusSuccess) {
        setState(() => _error = 'Not connected to a target');
        return;
      }
      for (int i = 0; i < 50 && mounted; i++) {
        await Future.delayed(const Duration(milliseconds: 100));
        final st = await _app.communicator!.bleCentralState();
        if (!mounted) return;
        setState(() => _state = st);
        if (st.discState == 2 || st.discState == 3) break;
      }
      final chars = await _app.communicator!.bleGattChars();
      // Also discover primary services so characteristics can be grouped.
      final services = await _app.communicator!.bleServices();
      if (mounted) {
        setState(() {
          _chars = chars;
          _services = services;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _readChar(int handle) async {
    final (status, value) = await _app.communicator!.bleGattRead(handle);
    if (!mounted) return;
    String text;
    if (status == 0) {
      text = value.isEmpty ? '(empty)' : _hex(value);
    } else if (status < 0) {
      text = 'timeout';
    } else {
      text = 'ATT err 0x${status.toRadixString(16)}';
    }
    setState(() => _readValues[handle] = text);
  }

  static Uint8List _hexToBytes(String s) {
    if (s.isEmpty || s.length % 2 != 0) {
      throw const FormatException('need an even number of hex digits');
    }
    return Uint8List.fromList([
      for (int i = 0; i < s.length; i += 2)
        int.parse(s.substring(i, i + 2), radix: 16)
    ]);
  }

  // Prompt for a hex value and write it to a characteristic (point-to-point).
  Future<void> _writeChar(BleCharacteristic c) async {
    final controller = TextEditingController();
    final input = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Write 0x${c.handle.toRadixString(16).padLeft(4, '0')}'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
              labelText: 'Value (hex)', hintText: '0100'),
          style: const TextStyle(fontFamily: 'RobotoMono'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, controller.text),
              child: const Text('Write')),
        ],
      ),
    );
    if (input == null || input.trim().isEmpty) return;
    Uint8List data;
    try {
      data = _hexToBytes(input.replaceAll(' ', ''));
    } catch (_) {
      if (mounted) setState(() => _error = 'Invalid hex value');
      return;
    }
    final status = await _app.communicator!.bleGattWrite(c.handle, data);
    if (!mounted) return;
    final String msg = status == 0
        ? 'Write to 0x${c.handle.toRadixString(16).padLeft(4, '0')} OK'
        : status < 0
            ? 'Write timed out'
            : 'Write rejected (ATT 0x${status.toRadixString(16)})';
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  // List all GATT descriptors of the connected target in a dialog.
  Future<void> _showDescriptors() async {
    final descs = await _app.communicator!.bleDescriptors();
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Descriptors'),
        content: SingleChildScrollView(
          child: descs.isEmpty
              ? const Text('No descriptors found.')
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final d in descs)
                      Text(
                          'handle 0x${(d['handle'] ?? 0).toRadixString(16).padLeft(4, '0')}  '
                          'UUID 0x${(d['uuid'] ?? 0).toRadixString(16).padLeft(4, '0')}'
                          '${_uuidName(d['uuid'] ?? 0).isNotEmpty ? " (${_uuidName(d['uuid'] ?? 0)})" : ""}',
                          style: const TextStyle(
                              fontFamily: 'RobotoMono', fontSize: 12)),
                  ],
                ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
        ],
      ),
    );
  }

  // One characteristic row (Read / Write / Select / Notify actions).
  Widget _charTile(BleCharacteristic c) {
    return ListTile(
      dense: true,
      isThreeLine: _readValues.containsKey(c.handle),
      title: Text(
          'handle 0x${c.handle.toRadixString(16).padLeft(4, '0')}  '
          'UUID 0x${c.uuid.toRadixString(16).padLeft(4, '0')}'
          '${_uuidName(c.uuid).isNotEmpty ? ' (${_uuidName(c.uuid)})' : ''}',
          style: const TextStyle(fontFamily: 'RobotoMono')),
      subtitle: Text(
          _propsStr(c.props) +
              (_readValues.containsKey(c.handle)
                  ? '\n= ${_readValues[c.handle]}'
                  : ''),
          style: const TextStyle(fontFamily: 'RobotoMono')),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (c.props & 0x02 != 0)
            TextButton(
                onPressed: () => _readChar(c.handle), child: const Text('Read')),
          if (_isWritable(c.props))
            TextButton(
                onPressed: () => _writeChar(c), child: const Text('Write')),
          if (_isWritable(c.props))
            TextButton(
                onPressed: () => setState(() => _handle.text =
                    '0x${c.handle.toRadixString(16).padLeft(4, '0')}'),
                child: const Text('Select')),
          if (c.props & 0x30 != 0)
            TextButton(
                onPressed: () => _toggleNotify(c),
                child: Text(_notifying && _notifCccd == c.handle + 1
                    ? 'Stop'
                    : 'Notify')),
        ],
      ),
    );
  }

  // Subscribe/unsubscribe to notifications on a characteristic. Uses the common
  // CCCD-at-(value handle + 1) layout. Receive-only: streams the target's own
  // notifications, sends nothing but the one CCCD write.
  Future<void> _toggleNotify(BleCharacteristic c) async {
    if (_notifying) {
      _notifying = false;
      if (_notifCccd != null) {
        await _app.communicator!.bleSubscribe(_notifCccd!, 0);
      }
      if (mounted) setState(() => _notifCccd = null);
      return;
    }
    final cccd = await _app.communicator!.bleFindCccd(c.handle);
    if (!mounted) return;
    final mode = (c.props & 0x10 != 0) ? 1 : 2; // notify else indicate
    final status = await _app.communicator!.bleSubscribe(cccd, mode);
    if (!mounted) return;
    if (status != _statusSuccess) {
      setState(() => _error = 'Subscribe failed (0x${status.toRadixString(16)})');
      return;
    }
    setState(() {
      _notifying = true;
      _notifCccd = cccd;
      _notifs = [];
    });
    int seen = 0;
    while (_notifying && mounted) {
      await Future.delayed(const Duration(milliseconds: 300));
      if (!_notifying || !mounted) break;
      final list = await _app.communicator!.bleGetNotifications();
      if (!mounted) return;
      if (list.length > seen) {
        seen = list.length;
        setState(() => _notifs = list);
      }
    }
  }

  Future<void> _startFuzz() async {
    final handle = int.tryParse(_handle.text.trim().replaceFirst('0x', ''),
            radix: 16) ??
        0;
    if (handle == 0) {
      setState(() => _error = 'Enter a valid characteristic handle (hex)');
      return;
    }
    final count = int.tryParse(_count.text.trim()) ?? 200;
    final interval = int.tryParse(_interval.text.trim()) ?? 50;
    setState(() {
      _error = null;
      _log = [];
    });
    final status = await _app.communicator!
        .bleFuzzStart(handle, maxIterations: count & 0xFFFF, intervalMs: interval & 0xFFFF);
    if (status != _statusSuccess) {
      setState(() => _error = 'Could not start fuzzing (is a target connected?)');
      return;
    }
    setState(() => _fuzzing = true);
    // Poll state until the run finishes, the target drops, or we stop.
    while (_fuzzing && mounted) {
      await Future.delayed(const Duration(milliseconds: 300));
      if (!_fuzzing || !mounted) break;
      final st = await _app.communicator!.bleCentralState();
      if (!mounted) return;
      setState(() => _state = st);
      if (!st.targetAlive && st.connState == 3) {
        setState(() => _error =
            'Target dropped the connection — possible crash / defensive disconnect');
        break;
      }
      if (st.fuzzState != 1) break; // finished on the device side
    }
    await _finishFuzz();
  }

  Future<void> _finishFuzz() async {
    if (_fuzzing) {
      await _app.communicator!.bleFuzzStop();
    }
    try {
      final log = await _app.communicator!.bleFuzzLog();
      if (mounted) setState(() => _log = log);
    } catch (_) {}
    // Batch finished (or cancelled): release the target so it can reconnect to
    // its normal source.
    await _app.communicator!.bleDisconnect();
    await _refreshState();
    if (mounted) {
      setState(() {
        _fuzzing = false;
        _chars = [];
      });
    }
  }

  Future<void> _stopFuzz() async {
    _fuzzing = false;
    await _app.communicator!.bleFuzzStop();
    await _refreshState();
    await _finishFuzz();
  }

  Future<void> _disconnect() async {
    _fuzzing = false;
    await _app.communicator!.bleFuzzStop();
    await _app.communicator!.bleDisconnect();
    await _refreshState();
    if (mounted) setState(() => _chars = []);
  }

  // ---- UI ---------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('BLE audit'),
        actions: [
          IconButton(
            icon: const Icon(Icons.bluetooth_audio),
            tooltip: 'Toggle local advertising (discoverable)',
            onPressed: _connected ? _toggleAdvertising : null,
          ),
        ],
        bottom: TabBar(
          controller: _tab,
          tabs: const [
            Tab(text: 'Passive scan', icon: Icon(Icons.radar)),
            Tab(text: 'Directed fuzz', icon: Icon(Icons.bug_report)),
          ],
        ),
      ),
      body: !_connected
          ? const Center(child: Text('No device connected'))
          : TabBarView(
              controller: _tab,
              children: [_scanTab(context), _fuzzTab(context)],
            ),
    );
  }

  Widget _scanTab(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
              'Listen-only: the Chameleon receives advertisements but transmits '
              'nothing.',
              style: TextStyle(fontStyle: FontStyle.italic)),
          const SizedBox(height: 12),
          Row(children: [
            SizedBox(
              width: 120,
              child: TextField(
                controller: _scanDuration,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                    labelText: 'Duration (s)', border: OutlineInputBorder()),
              ),
            ),
            const SizedBox(width: 12),
            ElevatedButton.icon(
              onPressed: _scanning ? null : _runScan,
              icon: _scanning
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.search),
              label: Text(_scanning ? 'Scanning...' : 'Scan'),
            ),
          ]),
          Row(children: [
            Checkbox(
              value: _activeScan,
              onChanged: _scanning
                  ? null
                  : (v) => setState(() => _activeScan = v ?? false),
            ),
            const Flexible(
              child: Text('Active scan (sends scan requests to get full names)'),
            ),
          ]),
          const SizedBox(height: 8),
          if (_scanResults.isNotEmpty)
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _nameFilter,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                      labelText: 'Filter by name', isDense: true,
                      border: OutlineInputBorder()),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 110,
                child: TextField(
                  controller: _minRssi,
                  keyboardType: TextInputType.number,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                      labelText: 'Min RSSI', isDense: true,
                      border: OutlineInputBorder()),
                ),
              ),
            ]),
          const SizedBox(height: 8),
          if (_error != null && _tab.index == 0)
            Text(_error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error)),
          if (_scanResults.isEmpty && !_scanning)
            const Padding(
              padding: EdgeInsets.only(top: 24),
              child: Text('No devices yet — run a scan.'),
            ),
          for (final r in _visibleResults())
            Card(
              child: ListTile(
                onTap: () => _showDeviceDetails(r),
                title: Text(_advName(r.adv) ?? _leToMac(r.addr),
                    style: const TextStyle(fontFamily: 'RobotoMono')),
                subtitle: Text([
                  if (_advName(r.adv) != null) _leToMac(r.addr),
                  'type ${r.addrType}',
                  'RSSI ${r.rssi} dBm',
                  if (_advSummary(r.adv).isNotEmpty) _advSummary(r.adv),
                ].join('  ·  ')),
                trailing: TextButton(
                  onPressed: () => _useAsTarget(r),
                  child: const Text('Fuzz this'),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _fuzzTab(BuildContext context) {
    final connected = _state?.connState == 2;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
              'Point-to-point against ONE target you specify. The device '
              'connects only to this address and writes only to it — it never '
              'broadcasts to other devices.',
              style: TextStyle(fontStyle: FontStyle.italic)),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: TextField(
                controller: _addr,
                decoration: const InputDecoration(
                    labelText: 'Target address (AA:BB:CC:DD:EE:FF)',
                    border: OutlineInputBorder()),
                style: const TextStyle(fontFamily: 'RobotoMono'),
              ),
            ),
            const SizedBox(width: 12),
            DropdownButton<int>(
              // Defensive: the value passed to the dropdown is always clamped to
              // a range that has a matching item, so no stale/unexpected
              // _addrType can ever trip the "exactly one item" assertion.
              value: (_addrType >= 0 && _addrType <= 3) ? _addrType : 0,
              items: const [
                DropdownMenuItem(value: 0, child: Text('public')),
                DropdownMenuItem(value: 1, child: Text('random')),
                DropdownMenuItem(value: 2, child: Text('random-RPA')),
                DropdownMenuItem(value: 3, child: Text('random-NRPA')),
              ],
              onChanged: (v) => setState(() => _addrType = v ?? 0),
            ),
          ]),
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: [
            ElevatedButton.icon(
              onPressed: _busy ? null : _connect,
              icon: const Icon(Icons.link),
              label: const Text('Connect'),
            ),
            OutlinedButton.icon(
              onPressed: (_busy || !connected) ? null : _probeLink,
              icon: const Icon(Icons.wifi_tethering),
              label: const Text('Ping'),
            ),
            OutlinedButton.icon(
              onPressed: (_busy || !connected) ? null : _discover,
              icon: const Icon(Icons.travel_explore),
              label: const Text('Discover'),
            ),
            OutlinedButton.icon(
              onPressed: _busy ? null : _disconnect,
              icon: const Icon(Icons.link_off),
              label: const Text('Disconnect'),
            ),
          ]),
          const SizedBox(height: 12),
          _statusBox(context),
          if (_error != null && _tab.index == 1) ...[
            const SizedBox(height: 8),
            Text(_error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
          if (_chars.isNotEmpty) ...[
            const SizedBox(height: 16),
            Row(children: [
              const Expanded(
                child: Text('Characteristics',
                    style: TextStyle(fontWeight: FontWeight.bold)),
              ),
              IconButton(
                tooltip: 'List all descriptors',
                icon: const Icon(Icons.list_alt, size: 18),
                onPressed: _showDescriptors,
              ),
              IconButton(
                tooltip: 'Copy characteristics',
                icon: const Icon(Icons.copy, size: 18),
                onPressed: () {
                  Clipboard.setData(ClipboardData(
                      text: _chars.map((c) {
                    final nm = _uuidName(c.uuid);
                    return 'handle 0x${c.handle.toRadixString(16).padLeft(4, '0')}\t'
                        'UUID 0x${c.uuid.toRadixString(16).padLeft(4, '0')}'
                        '${nm.isNotEmpty ? ' ($nm)' : ''}\t[${_propsStr(c.props)}]';
                  }).join('\n')));
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text('Copied ${_chars.length} characteristics')));
                },
              ),
            ]),
            // Grouped under primary services when known, else a flat list.
            if (_services.isNotEmpty) ...[
              for (final s in _services) ...[
                Padding(
                  padding: const EdgeInsets.only(top: 8, bottom: 2),
                  child: Text(
                      'Service 0x${(s['uuid'] ?? 0).toRadixString(16).padLeft(4, '0')}'
                      '${_uuidName(s['uuid'] ?? 0).isNotEmpty ? " (${_uuidName(s['uuid'] ?? 0)})" : ""}'
                      '  [0x${(s['start'] ?? 0).toRadixString(16).padLeft(4, '0')}-'
                      '0x${(s['end'] ?? 0).toRadixString(16).padLeft(4, '0')}]',
                      style: TextStyle(
                          fontFamily: 'RobotoMono',
                          fontWeight: FontWeight.w600,
                          color: Theme.of(context).colorScheme.primary)),
                ),
                for (final c in _chars)
                  if (c.handle >= (s['start'] ?? 0) &&
                      c.handle <= (s['end'] ?? 0))
                    _charTile(c),
              ],
              // Characteristics that fell outside any discovered service.
              for (final c in _chars)
                if (!_services.any((s) =>
                    c.handle >= (s['start'] ?? 0) && c.handle <= (s['end'] ?? 0)))
                  _charTile(c),
            ] else
              for (final c in _chars) _charTile(c),
          ],
          const SizedBox(height: 16),
          const Text('Fuzz', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: TextField(
                controller: _handle,
                decoration: const InputDecoration(
                    labelText: 'Handle (hex)', border: OutlineInputBorder()),
                style: const TextStyle(fontFamily: 'RobotoMono'),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 90,
              child: TextField(
                controller: _count,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                    labelText: 'Count', border: OutlineInputBorder()),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 100,
              child: TextField(
                controller: _interval,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                    labelText: 'Interval ms', border: OutlineInputBorder()),
              ),
            ),
          ]),
          const SizedBox(height: 12),
          Wrap(spacing: 8, children: [
            ElevatedButton.icon(
              onPressed: (!connected || _fuzzing) ? null : _startFuzz,
              icon: _fuzzing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.play_arrow),
              label: Text(_fuzzing ? 'Fuzzing...' : 'Start fuzz'),
            ),
            OutlinedButton.icon(
              onPressed: _fuzzing ? _stopFuzz : null,
              icon: const Icon(Icons.cancel_outlined),
              label: const Text('Cancel'),
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
                    ? 'The target is connected only during the test. It will reconnect to '
                        'its normal source when the batch finishes or you press Cancel.'
                    : 'While testing, the target stays connected to this device only; it '
                        'reconnects to its normal source once the batch finishes or you cancel.',
                style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.outline),
              ),
            ),
          ]),
          if (_log.isNotEmpty) ...[
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: Text('Log (${_log.length} entries, last 15):',
                    style: const TextStyle(fontWeight: FontWeight.bold)),
              ),
              IconButton(
                tooltip: 'Copy full log',
                icon: const Icon(Icons.copy, size: 18),
                onPressed: () {
                  Clipboard.setData(ClipboardData(
                      text: _log
                          .map((e) =>
                              '#${e.index}\tlen=${e.length}\t${e.status == 0 ? 'ok' : 'err0x${e.status.toRadixString(16)}'}\t${_hex(e.data)}')
                          .join('\n')));
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text('Copied ${_log.length} log entries')));
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
                    .map((e) =>
                        '#${e.index}  len=${e.length}  '
                        '${e.status == 0 ? 'ok' : 'err0x${e.status.toRadixString(16)}'}  '
                        '${_hex(e.data)}')
                    .join('\n'),
                style: const TextStyle(fontFamily: 'RobotoMono', fontSize: 12),
              ),
            ),
          ],
          if (_notifs.isNotEmpty) ...[
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: Text('Notifications (${_notifs.length}, last 15):',
                    style: const TextStyle(fontWeight: FontWeight.bold)),
              ),
              IconButton(
                tooltip: 'Copy all notifications',
                icon: const Icon(Icons.copy, size: 18),
                onPressed: () {
                  Clipboard.setData(ClipboardData(
                      text: _notifs.map((n) {
                    final d = n['data'] as Uint8List;
                    return 'h0x${(n['handle'] as int).toRadixString(16).padLeft(4, '0')}\t${_hex(d)}';
                  }).join('\n')));
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text('Copied ${_notifs.length} notifications')));
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
                _notifs.reversed.take(15).toList().reversed.map((n) {
                  final d = n['data'] as Uint8List;
                  return 'h0x${(n['handle'] as int).toRadixString(16).padLeft(4, '0')}  ${_hex(d)}';
                }).join('\n'),
                style: const TextStyle(fontFamily: 'RobotoMono', fontSize: 12),
              ),
            ),
          ],
        ],
      ),
    );
  }

  static String _hex(Uint8List b) =>
      b.map((x) => x.toRadixString(16).padLeft(2, '0')).join().toUpperCase();

  Widget _statusBox(BuildContext context) {
    final st = _state;
    if (st == null) return const SizedBox.shrink();
    const conn = ['idle', 'connecting', 'connected', 'disconnected'];
    const disc = ['idle', 'discovering', 'done', 'error'];
    const fuzz = ['idle', 'running', 'stopped'];
    String at(List<String> l, int i) => (i >= 0 && i < l.length) ? l[i] : '$i';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('connection : ${at(conn, st.connState)}'),
          Text('discovery  : ${at(disc, st.discState)} (${st.charCount} chars)'),
          Text('fuzz       : ${at(fuzz, st.fuzzState)} (${st.fuzzSent} writes)'),
          Text('target up  : ${st.targetAlive}'),
          if (st.connState == 2) Text('ATT MTU    : $_mtu'),
          Text('link probe : '
              '${at(<String>["idle", "probing", "done", "error"], st.probeState)}'
              '${st.probeState == 3 ? " (0x${st.probeResult.toRadixString(16)})" : ""}'),
          if (st.lastReason != 0)
            Text('last disconnect reason : '
                '0x${st.lastReason.toRadixString(16).padLeft(2, '0')}'),
        ],
      ),
    );
  }
}

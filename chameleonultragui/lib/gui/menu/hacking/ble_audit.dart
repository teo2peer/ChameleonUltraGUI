import 'dart:typed_data';

import 'package:chameleonultragui/helpers/definitions.dart';
import 'package:chameleonultragui/main.dart';
import 'package:flutter/material.dart';
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
  List<BleScanResult> _scanResults = [];

  // --- directed fuzz state ---
  final _addr = TextEditingController();
  int _addrType = 0;
  final _handle = TextEditingController();
  final _count = TextEditingController(text: '200');
  final _interval = TextEditingController(text: '50');
  BleCentralState? _state;
  List<BleCharacteristic> _chars = [];
  final Map<int, String> _readValues = {}; // value handle -> last read result
  List<BleFuzzLogEntry> _log = [];
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
    _tab.dispose();
    _scanDuration.dispose();
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

  static String _propsStr(int p) {
    final names = <String>[];
    if (p & 0x02 != 0) names.add('read');
    if (p & 0x04 != 0) names.add('write-nr');
    if (p & 0x08 != 0) names.add('write');
    if (p & 0x10 != 0) names.add('notify');
    if (p & 0x20 != 0) names.add('indicate');
    return names.isEmpty ? '-' : names.join(',');
  }

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
      await _app.communicator!.blePassiveScanStart();
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

  void _useAsTarget(BleScanResult r) {
    setState(() {
      _addr.text = _leToMac(r.addr);
      _addrType = r.addrType;
    });
    _tab.animateTo(1);
  }

  // ---- directed fuzz ----------------------------------------------------
  Future<void> _refreshState() async {
    final st = await _app.communicator!.bleCentralState();
    if (mounted) setState(() => _state = st);
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
        if (st.connState == 2) break; // connected
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
      if (mounted) setState(() => _chars = chars);
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
    if (mounted) setState(() => _fuzzing = false);
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
          const SizedBox(height: 16),
          if (_error != null && _tab.index == 0)
            Text(_error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error)),
          if (_scanResults.isEmpty && !_scanning)
            const Padding(
              padding: EdgeInsets.only(top: 24),
              child: Text('No devices yet — run a scan.'),
            ),
          for (final r in _scanResults)
            Card(
              child: ListTile(
                title: Text(_leToMac(r.addr),
                    style: const TextStyle(fontFamily: 'RobotoMono')),
                subtitle: Text([
                  if (_advName(r.adv) != null) _advName(r.adv)!,
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
              value: _addrType,
              items: const [
                DropdownMenuItem(value: 0, child: Text('public')),
                DropdownMenuItem(value: 1, child: Text('random')),
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
            const Text('Characteristics',
                style: TextStyle(fontWeight: FontWeight.bold)),
            for (final c in _chars)
              ListTile(
                dense: true,
                isThreeLine: _readValues.containsKey(c.handle),
                title: Text(
                    'handle 0x${c.handle.toRadixString(16).padLeft(4, '0')}  '
                    'UUID 0x${c.uuid.toRadixString(16).padLeft(4, '0')}',
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
                        onPressed: () => _readChar(c.handle),
                        child: const Text('Read'),
                      ),
                    if (_isWritable(c.props))
                      TextButton(
                        onPressed: () => setState(() => _handle.text =
                            '0x${c.handle.toRadixString(16).padLeft(4, '0')}'),
                        child: const Text('Select'),
                      ),
                  ],
                ),
              ),
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
              icon: const Icon(Icons.stop),
              label: const Text('Stop'),
            ),
          ]),
          if (_log.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text('Log (${_log.length} entries, last 15):',
                style: const TextStyle(fontWeight: FontWeight.bold)),
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
          if (st.lastReason != 0)
            Text('last disconnect reason : '
                '0x${st.lastReason.toRadixString(16).padLeft(2, '0')}'),
        ],
      ),
    );
  }
}

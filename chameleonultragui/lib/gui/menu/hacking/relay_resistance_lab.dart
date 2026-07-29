import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:chameleonultragui/bridge/relay_lab_platform.dart';
import 'package:chameleonultragui/gui/component/apdu_cheatsheet.dart';
import 'package:chameleonultragui/helpers/general.dart';
import 'package:chameleonultragui/helpers/relay_lab.dart';
import 'package:chameleonultragui/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

class RelayResistanceLabPage extends StatefulWidget {
  const RelayResistanceLabPage({super.key});

  @override
  State<RelayResistanceLabPage> createState() => _RelayResistanceLabPageState();
}

class _RelayResistanceLabPageState extends State<RelayResistanceLabPage> {
  final _platform = RelayLabPlatform();
  final _deadline = TextEditingController(text: '750');
  final _inducedDelay = TextEditingController(text: '0');
  StreamSubscription<Map<String, Object?>>? _events;
  bool _available = false;
  bool _armed = false;
  bool _busy = false;
  String? _error;
  final List<RelayLabExchange> _exchanges = [];
  final List<RelayLabExchange> _baseline = [];

  ChameleonGUIState get _app => context.read<ChameleonGUIState>();
  bool get _connected => _app.connector?.connected ?? false;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    final available = await _platform.isAvailable();
    if (!mounted) return;
    setState(() => _available = available);
    if (available) {
      _events = _platform.apduEvents.listen(_handleApdu,
          onError: (Object error) =>
              mounted ? setState(() => _error = error.toString()) : null);
    }
  }

  @override
  void dispose() {
    _platform.setEnabled(false);
    _events?.cancel();
    _deadline.dispose();
    _inducedDelay.dispose();
    super.dispose();
  }

  Future<void> _setArmed(bool value) async {
    if (value && !_connected) {
      setState(() => _error = 'Connect the backend Chameleon first');
      return;
    }
    if (value) {
      final deadline = int.tryParse(_deadline.text);
      if (deadline == null || deadline < 50 || deadline > 5000) {
        setState(() => _error = 'Deadline must be 50..5000 ms');
        return;
      }
      final inducedDelay = int.tryParse(_inducedDelay.text);
      if (inducedDelay == null || inducedDelay < 0 || inducedDelay > 3000) {
        setState(() => _error = 'Induced delay must be 0..3000 ms');
        return;
      }
      setState(() {
        _busy = true;
        _error = null;
      });
      try {
        if (!await _app.communicator!.isReaderDeviceMode()) {
          await _app.communicator!.setReaderDeviceMode(true);
        }
      } catch (error) {
        if (mounted) setState(() => _error = error.toString());
        return;
      } finally {
        if (mounted) setState(() => _busy = false);
      }
    }
    final enabled = await _platform.setEnabled(value);
    if (mounted) setState(() => _armed = enabled);
  }

  Future<void> _handleApdu(Map<String, Object?> event) async {
    final id = event['id'];
    final commandHex = event['apduHex'];
    if (!_armed || id is! num || commandHex is! String) return;
    final stopwatch = Stopwatch()..start();
    var response = Uint8List.fromList([0x64, 0x00]);
    var reason = 'Backend exchange failed';
    var allowed = false;
    bool? nonceBound;
    try {
      final command = hexToBytes(commandHex);
      final policy = evaluateRelayLabApdu(command);
      allowed = policy.allowed;
      reason = policy.reason;
      if (policy.allowed) {
        final backend = await _app.communicator!.hf14a4ReaderApdu(command);
        if (backend.length < 2 || backend.length > relayLabMaxResponseLength) {
          throw const FormatException('Backend response must be 2..260 bytes');
        }
        response = backend;
        nonceBound = relayLabNonceBound(command, backend);
        if (nonceBound == false) {
          reason = '$reason; challenge response is not bound to the nonce';
        }
      } else {
        response = policy.errorResponse;
      }
      final delayMs = int.tryParse(_inducedDelay.text) ?? 0;
      if (delayMs > 0) {
        await Future<void>.delayed(Duration(milliseconds: delayMs));
        reason = '$reason; induced delay ${delayMs}ms';
      }
    } catch (error) {
      reason = '$reason: $error';
    }
    stopwatch.stop();
    final deadlineMs = int.tryParse(_deadline.text) ?? 750;
    final withinDeadline = stopwatch.elapsedMicroseconds <= deadlineMs * 1000;
    if (!withinDeadline) {
      response = Uint8List.fromList([0x64, 0x01]);
      reason = '$reason; total deadline exceeded';
    }
    final responseHex = bytesToHex(response).toUpperCase();
    final delivered = await _platform.respond(id.toInt(), responseHex);
    if (!mounted) return;
    setState(() {
      _exchanges.insert(
        0,
        RelayLabExchange(
          commandHex: commandHex.toUpperCase(),
          responseHex: responseHex,
          elapsedUs: stopwatch.elapsedMicroseconds,
          allowed: allowed,
          reason: delivered ? reason : '$reason; HCE response was stale',
          withinDeadline: withinDeadline && delivered,
          nonceBound: nonceBound,
        ),
      );
      if (_exchanges.length > 100) _exchanges.removeLast();
    });
  }

  Future<void> _runBaseline() async {
    if (!_connected) {
      setState(() => _error = 'Connect the backend Chameleon first');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _baseline.clear();
    });
    try {
      if (!await _app.communicator!.isReaderDeviceMode()) {
        await _app.communicator!.setReaderDeviceMode(true);
      }
      final select = hexToBytes('00A4040007F001020304050600');
      final selectResponse = await _app.communicator!.hf14a4ReaderApdu(select);
      if (selectResponse.length < 2 ||
          selectResponse[selectResponse.length - 2] != 0x90 ||
          selectResponse.last != 0x00) {
        throw const FormatException(
            'Backend did not accept the private relay-lab AID');
      }

      final samples = <RelayLabExchange>[];
      for (var index = 0; index < 5; index++) {
        final command = hexToBytes('F030000000');
        final stopwatch = Stopwatch()..start();
        final response = await _app.communicator!.hf14a4ReaderApdu(command);
        stopwatch.stop();
        samples.add(_baselineExchange(
            command, response, stopwatch.elapsedMicroseconds));
        await Future<void>.delayed(const Duration(milliseconds: 80));
      }

      final random = Random.secure();
      final nonce = List<int>.generate(8, (_) => random.nextInt(256));
      final challenge =
          Uint8List.fromList([0xF0, 0x10, 0x00, 0x00, 0x08, ...nonce]);
      final stopwatch = Stopwatch()..start();
      final challengeResponse =
          await _app.communicator!.hf14a4ReaderApdu(challenge);
      stopwatch.stop();
      samples.add(_baselineExchange(
          challenge, challengeResponse, stopwatch.elapsedMicroseconds));

      if (!mounted) return;
      setState(() => _baseline.addAll(samples));
    } catch (error) {
      if (mounted) setState(() => _error = 'Baseline failed: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  RelayLabExchange _baselineExchange(
      Uint8List command, Uint8List response, int elapsedUs) {
    if (response.length < 2 || response.length > relayLabMaxResponseLength) {
      throw const FormatException('Backend response must be 2..260 bytes');
    }
    final deadlineMs = int.tryParse(_deadline.text) ?? 750;
    final nonceBound = relayLabNonceBound(command, response);
    return RelayLabExchange(
      commandHex: bytesToHex(command).toUpperCase(),
      responseHex: bytesToHex(response).toUpperCase(),
      elapsedUs: elapsedUs,
      allowed: true,
      reason: nonceBound == false
          ? 'Direct backend response is not bound to the challenge nonce'
          : 'Direct backend baseline',
      withinDeadline: elapsedUs <= deadlineMs * 1000,
      nonceBound: nonceBound,
    );
  }

  void _clearDemo() {
    setState(() {
      _baseline.clear();
      _exchanges.clear();
      _error = null;
    });
  }

  Future<void> _copyReport() async {
    final comparison = compareRelayLabRuns(_baseline, _exchanges);
    final report = const JsonEncoder.withIndent('  ').convert({
      'protocol': 'chameleon-synthetic-relay-lab',
      'privateAid': relayLabAidHex,
      'paymentTrafficForwarded': false,
      'deadlineMs': int.tryParse(_deadline.text),
      'inducedDelayMs': int.tryParse(_inducedDelay.text),
      'baseline': _baseline.map((exchange) => exchange.toJson()).toList(),
      'exchanges': _exchanges.map((exchange) => exchange.toJson()).toList(),
      'comparison': comparison.toJson(),
    });
    await Clipboard.setData(ClipboardData(text: report));
  }

  @override
  Widget build(BuildContext context) {
    final comparison = compareRelayLabRuns(_baseline, _exchanges);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Synthetic relay-resistance lab'),
        actions: [
          IconButton(
            tooltip: 'Copy timing report',
            onPressed: _exchanges.isEmpty ? null : _copyReport,
            icon: const Icon(Icons.data_object),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              color: Theme.of(context).colorScheme.secondaryContainer,
              child: const Padding(
                padding: EdgeInsets.all(14),
                child: Text(
                  'Android HCE exposes only private AID F0010203040506. PPSE, '
                  'payment AIDs and all non-private command classes are rejected '
                  'before Bluetooth/USB forwarding. After successful selection, '
                  'every APDU using private CLA F0 is forwarded. The backend must '
                  'touch a synthetic lab card or phone implementing the same AID.',
                ),
              ),
            ),
            if (!_available)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(14),
                  child: Text(
                    'Terminal-facing HCE is available on supported Android devices. '
                    'iOS does not expose generic HCE without restricted Apple '
                    'entitlements; use iOS for backend reader and report analysis.',
                  ),
                ),
              ),
            const ApduCheatSheet(showEmv: false),
            const SizedBox(height: 10),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('GUIDED REALISTIC DEMO',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, letterSpacing: 0.5)),
                    const SizedBox(height: 8),
                    const Text(
                        '1. Arm a second Chameleon with the Synthetic relay lab preset.'),
                    const Text('2. Place it on this reader-side Chameleon.'),
                    const Text('3. Run the direct backend baseline below.'),
                    const Text(
                        '4. Arm Android HCE and present it to the private-AID lab terminal.'),
                    const Text(
                        '5. Send SELECT, status, challenge and arbitrary F0 test APDUs.'),
                    const Text(
                        '6. Compare median, p95, deadline and nonce results.'),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        FilledButton.icon(
                          onPressed: _busy || _armed ? null : _runBaseline,
                          icon: const Icon(Icons.speed),
                          label: const Text('Run backend baseline'),
                        ),
                        OutlinedButton.icon(
                          onPressed: _busy ? null : _clearDemo,
                          icon: const Icon(Icons.clear_all),
                          label: const Text('Clear demo'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _deadline,
                    enabled: !_armed,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Total deadline',
                      suffixText: 'ms',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _inducedDelay,
                    enabled: !_armed,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Induced delay',
                      suffixText: 'ms',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _armed,
              onChanged: !_available || _busy ? null : _setArmed,
              title: const Text('Arm private-AID Android HCE'),
              subtitle: Text(_connected
                  ? 'Backend Chameleon connected'
                  : 'Backend Chameleon not connected'),
            ),
            if (_error != null)
              Text(_error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
            if (_baseline.isNotEmpty || _exchanges.isNotEmpty) ...[
              const SizedBox(height: 8),
              Card(
                color: Theme.of(context).colorScheme.tertiaryContainer,
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('DEMO COMPARISON',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                      Text(
                          'Baseline: n=${comparison.baseline.count}, median=${_formatUs(comparison.baseline.medianUs)}, p95=${_formatUs(comparison.baseline.p95Us)}'),
                      Text(
                          'Relayed: n=${comparison.relayed.count}, median=${_formatUs(comparison.relayed.medianUs)}, p95=${_formatUs(comparison.relayed.p95Us)}'),
                      Text(
                          'Median overhead: ${comparison.medianOverheadUs == null ? 'pending' : _formatUs(comparison.medianOverheadUs!)}'),
                      Text(
                          'Deadline failures: ${comparison.relayed.deadlineFailures} | Nonce failures: ${comparison.relayed.nonceFailures}'),
                      const SizedBox(height: 4),
                      Text(comparison.conclusion,
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              ),
            ],
            const Divider(),
            Text('Baseline samples (${_baseline.length})',
                style: const TextStyle(fontWeight: FontWeight.bold)),
            for (final exchange in _baseline)
              _exchangeTile(exchange, direct: true),
            const Divider(),
            Text('Exchanges (${_exchanges.length})',
                style: const TextStyle(fontWeight: FontWeight.bold)),
            for (final exchange in _exchanges) _exchangeTile(exchange),
          ],
        ),
      ),
    );
  }

  Widget _exchangeTile(RelayLabExchange exchange, {bool direct = false}) {
    return ListTile(
      dense: true,
      leading: Icon(
        exchange.passed ? Icons.check_circle : Icons.cancel,
        color: exchange.passed ? Colors.green : Colors.red,
      ),
      title: Text(
        '${direct ? 'DIRECT' : 'RELAY'} | ${_formatUs(exchange.elapsedUs)} | ${exchange.reason}',
      ),
      subtitle: SelectableText(
        '${exchange.commandHex} -> ${exchange.responseHex}',
        style: const TextStyle(fontFamily: 'RobotoMono', fontSize: 11),
      ),
    );
  }

  String _formatUs(int value) => '${(value / 1000).toStringAsFixed(2)} ms';
}

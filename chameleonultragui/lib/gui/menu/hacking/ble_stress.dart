import 'dart:async';

import 'package:chameleonultragui/bridge/chameleon_ble.dart';
import 'package:chameleonultragui/generated/i18n/app_localizations.dart';
import 'package:chameleonultragui/gui/menu/hacking/ble_capability_gate.dart';
import 'package:chameleonultragui/gui/menu/hacking/ble_responsive.dart';
import 'package:chameleonultragui/helpers/ble/ble_presentation.dart';
import 'package:chameleonultragui/helpers/definitions.dart';
import 'package:chameleonultragui/main.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

enum _BroadcastErrorTarget { floodCard, broadcastCard }

// BLE stress / broadcast page (cybersecurity fork, operator-authorised).
//
// Per-call scope selectable (CLAUDE.md fork-specific exemption — operator has
// explicit authorisation):
//   single target      = already-connected central link
//   scan-buffer-wide   = every address cached by the passive scanner
//   environment-wide   = full broadcast on the 2.4 GHz BLE spectrum
//                        (non-connectable adv spam, max payload,
//                        regulatory-minimum interval — every scanner / peer
//                        in range sees it)
class BleStressPage extends StatefulWidget {
  final bool embedded;

  const BleStressPage({super.key, this.embedded = false});

  @override
  BleStressPageState createState() => BleStressPageState();
}

class BleStressPageState extends State<BleStressPage> {
  static const int _statusDeviceModeError = 0x66;
  static const int _bleFloodPayloadMax = 20;
  static const int _bufferFloodDefaultCount = 200;

  // --- flood ---
  int _floodScope = 0; // 0 single, 1 buffer, 2 broadcast
  final _floodHandle = TextEditingController(text: '0x0012');
  final _floodSize = TextEditingController(text: '16');
  final _floodCount = TextEditingController(text: '0'); // 0 = until stop
  final _floodInterval = TextEditingController(text: '5');
  int _floodSent = 0;
  bool _flooding = false;
  bool _startingFlood = false;
  bool _pollInFlight = false;
  int? _finiteFloodTarget;
  Timer? _pollTimer;
  String? _floodError;

  // --- kick ---
  int _kickScope = 0; // 0 single, 1 buffer
  final _kickCycles = TextEditingController(text: '1');
  String? _kickError;

  // --- environment-wide broadcast ---
  final _advFill = TextEditingController(text: '0x00');
  final _advIntervalUnits = TextEditingController(text: '1'); // 100ms multiples
  bool _broadcasting = false;
  String? _broadcastError;

  late ChameleonGUIState _app;
  ChameleonCommunicator get _dev => _app.communicator!;
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
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted ||
          _app.communicator == null ||
          !(_app.connector?.connected ?? false)) {
        return;
      }
      try {
        final state = await _dev.bleCentralState();
        if (!mounted || !state.hasOperationState || state.floodState != 1) {
          return;
        }
        setState(() {
          _flooding = true;
          _floodSent = state.floodSent;
        });
        _pollTimer = Timer.periodic(const Duration(milliseconds: 250), (_) {
          unawaited(_refreshFloodCount());
        });
      } catch (_) {}
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    final communicator = _app.communicator;
    if (communicator != null) {
      unawaited(communicator.bleFloodStop().catchError((_) {}));
    }
    _floodHandle.dispose();
    _floodSize.dispose();
    _floodCount.dispose();
    _floodInterval.dispose();
    _kickCycles.dispose();
    _advFill.dispose();
    _advIntervalUnits.dispose();
    super.dispose();
  }

  void _clearLocalActivity() {
    _pollTimer?.cancel();
    _pollTimer = null;
    _pollInFlight = false;
    _startingFlood = false;
    _flooding = false;
    _broadcasting = false;
    _finiteFloodTarget = null;
  }

  Future<void> _startFlood() async {
    if (_startingFlood || _flooding) return;
    setState(() => _startingFlood = true);
    try {
      await _startFloodUnchecked();
    } finally {
      if (mounted) setState(() => _startingFlood = false);
    }
  }

  Future<void> _startFloodUnchecked() async {
    final localizations = AppLocalizations.of(context)!;
    setState(() => _floodError = null);

    if (_floodScope == 2) {
      try {
        final fill = _floodSize.text.trim().isEmpty
            ? 0x00
            : bleParseHexOrDecimal(_floodSize.text);
        final units = _floodCount.text.trim().isEmpty
            ? 1
            : int.parse(_floodCount.text.trim());
        if (fill < 0 || fill > 0xFF) {
          setState(() => _floodError = localizations.ble_fill_byte_range_error);
          return;
        }
        if (units < 1 || units > 102) {
          setState(
              () => _floodError = localizations.ble_interval_units_range_error);
          return;
        }
        await _startBroadcastValues(fill, units,
            errorTarget: _BroadcastErrorTarget.floodCard);
      } on FormatException catch (e) {
        setState(() =>
            _floodError = localizations.ble_invalid_broadcast_field(e.message));
      } catch (e) {
        setState(() =>
            _floodError = localizations.ble_broadcast_failed(e.toString()));
      }
      return;
    }

    int handle = 0;
    int size;
    int count;
    int interval;
    try {
      // Apply defaults when fields are empty so the operator can hit Start
      // without filling every box first.
      size = _floodSize.text.trim().isEmpty
          ? 16
          : int.parse(_floodSize.text.trim());
      count = _floodCount.text.trim().isEmpty
          ? 0
          : int.parse(_floodCount.text.trim());
      interval = _floodInterval.text.trim().isEmpty
          ? 5
          : int.parse(_floodInterval.text.trim());
      handle = _floodHandle.text.trim().isEmpty
          ? 0x0012
          : bleParseHexOrDecimal(_floodHandle.text);
    } on FormatException catch (e) {
      setState(() =>
          _floodError = localizations.ble_invalid_numeric_field(e.message));
      return;
    } catch (_) {
      setState(
          () => _floodError = localizations.ble_invalid_numeric_field_plain);
      return;
    }
    if (size < 1 || size > _bleFloodPayloadMax) {
      setState(() => _floodError =
          localizations.ble_payload_size_range_error(_bleFloodPayloadMax));
      return;
    }
    if (handle < 1 || handle > 0xFFFF) {
      setState(() => _floodError = localizations.ble_flood_handle_range_error);
      return;
    }
    if (count < 0 || count > 0xFFFF) {
      setState(() => _floodError = localizations.ble_flood_count_range_error);
      return;
    }
    if (interval < 1 || interval > 0xFFFF) {
      setState(
          () => _floodError = localizations.ble_flood_interval_range_error);
      return;
    }
    try {
      final operationState = await _dev.bleCentralState();
      if (operationState.fuzzState == 1) {
        setState(
            () => _floodError = localizations.ble_fuzz_active_before_flood);
        return;
      }
      if (_floodScope == 0) {
        if (operationState.connState != 2) {
          setState(() =>
              _floodError = localizations.ble_single_target_not_connected);
          return;
        }
      } else {
        final scanCount = await _dev.blePassiveScanCount();
        if (scanCount == 0) {
          setState(() => _floodError = localizations.ble_buffer_scope_empty);
          return;
        }
        await _dev.blePassiveScanStop();
        if (count == 0) {
          count = _bufferFloodDefaultCount;
        }
      }

      await _dev.bleFloodStart(_floodScope, handle, size,
          maxIterations: count, intervalMs: interval);
      if (!mounted) return;
      setState(() {
        _flooding = true;
        _floodSent = 0;
        _finiteFloodTarget = count > 0 ? count : null;
      });
      _pollTimer?.cancel();
      _pollTimer = Timer.periodic(const Duration(milliseconds: 250), (_) {
        unawaited(_refreshFloodCount());
      });
    } on ChameleonCommandException catch (e) {
      if (mounted) setState(() => _floodError = _floodStartError(e.status));
    } catch (e) {
      if (mounted) {
        setState(
            () => _floodError = localizations.ble_flood_failed(e.toString()));
      }
    }
  }

  Future<void> _refreshFloodCount() async {
    final localizations = AppLocalizations.of(context)!;
    if (_pollInFlight) return;
    _pollInFlight = true;
    try {
      final count = await _dev.bleFloodCount();
      final state = await _dev.bleCentralState();
      if (!mounted) return;
      final completed = (state.hasOperationState && state.floodState != 1) ||
          (_floodScope == 0 &&
              _finiteFloodTarget != null &&
              count >= _finiteFloodTarget!);
      if (completed) {
        _pollTimer?.cancel();
        _pollTimer = null;
      }
      setState(() {
        _floodSent = count;
        if (completed) {
          _flooding = false;
          _finiteFloodTarget = null;
        }
      });
    } catch (e) {
      if (mounted) {
        setState(() =>
            _floodError = localizations.ble_count_refresh_failed(e.toString()));
      }
    } finally {
      _pollInFlight = false;
    }
  }

  String _floodStartError(int status) {
    final localizations = AppLocalizations.of(context)!;
    final hex = '0x${status.toRadixString(16)}';
    if (status == _statusDeviceModeError) {
      return _floodScope == 0
          ? localizations.ble_flood_start_single_failed(hex)
          : localizations.ble_flood_start_buffer_disconnect(hex);
    }
    return _floodScope == 1
        ? localizations.ble_flood_start_buffer_failed(hex)
        : localizations.ble_flood_start_failed(hex);
  }

  Future<void> _startBroadcast() async {
    if (_startingFlood || _flooding) return;
    setState(() => _startingFlood = true);
    try {
      await _startBroadcastUnchecked();
    } finally {
      if (mounted) setState(() => _startingFlood = false);
    }
  }

  Future<void> _startBroadcastUnchecked() async {
    final localizations = AppLocalizations.of(context)!;
    setState(() => _broadcastError = null);
    try {
      final fill = _advFill.text.trim().isEmpty
          ? 0x00
          : bleParseHexOrDecimal(_advFill.text);
      final units = _advIntervalUnits.text.trim().isEmpty
          ? 1
          : int.parse(_advIntervalUnits.text.trim());
      if (fill < 0 || fill > 0xFF) {
        setState(
            () => _broadcastError = localizations.ble_fill_byte_range_error);
        return;
      }
      if (units < 1 || units > 102) {
        setState(() =>
            _broadcastError = localizations.ble_interval_units_range_error);
        return;
      }
      await _startBroadcastValues(fill, units,
          errorTarget: _BroadcastErrorTarget.broadcastCard);
    } on FormatException catch (e) {
      if (mounted) {
        setState(() => _broadcastError =
            localizations.ble_invalid_broadcast_field(e.message));
      }
    } catch (e) {
      if (mounted) {
        setState(() =>
            _broadcastError = localizations.ble_broadcast_failed(e.toString()));
      }
    }
  }

  Future<void> _startBroadcastValues(int fill, int units,
      {required _BroadcastErrorTarget errorTarget}) async {
    await _dev.bleAdvFloodStart(fill, intervalUnits: units);
    if (!mounted) return;
    setState(() {
      _flooding = true;
      _floodSent = 0;
      _finiteFloodTarget = null;
      _broadcasting = true;
      _broadcastError = null;
      if (errorTarget == _BroadcastErrorTarget.floodCard) {
        _floodError = null;
      }
    });
  }

  Future<void> _stopFlood() async {
    final localizations = AppLocalizations.of(context)!;
    _pollTimer?.cancel();
    _pollTimer = null;
    _finiteFloodTarget = null;
    final wasBroadcasting = _broadcasting;
    try {
      await _dev.bleFloodStop(); // stops both WRITE_CMD and adv floods
      final n = await _dev.bleFloodCount();
      if (!mounted) return;
      setState(() {
        _flooding = false;
        _broadcasting = false;
        _floodSent = n;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          if (wasBroadcasting) {
            _broadcastError = localizations.ble_broadcast_failed(e.toString());
          } else {
            _floodError = localizations.ble_flood_failed(e.toString());
          }
        });
      }
    }
  }

  Future<void> _kick() async {
    final localizations = AppLocalizations.of(context)!;
    setState(() => _kickError = null);
    int cycles;
    try {
      cycles = int.parse(_kickCycles.text);
    } catch (_) {
      setState(() => _kickError = localizations.ble_cycles_range_error);
      return;
    }
    if (cycles < 1 || cycles > 10) {
      setState(() => _kickError = localizations.ble_cycles_range_error);
      return;
    }
    if (_kickScope == 0 && cycles != 1) {
      setState(() => _kickError = localizations.ble_single_kick_cycles_error);
      return;
    }
    try {
      if (_kickScope == 0) {
        final state = await _dev.bleCentralState();
        if (state.connState != 2) {
          setState(
              () => _kickError = localizations.ble_single_target_not_connected);
          return;
        }
      } else {
        final scanCount = await _dev.blePassiveScanCount();
        if (scanCount == 0) {
          setState(() => _kickError = localizations.ble_buffer_scope_empty);
          return;
        }
        await _dev.blePassiveScanStop();
      }
      await _dev.bleKick(cycles, scope: _kickScope);
    } catch (e) {
      if (mounted) {
        setState(
            () => _kickError = localizations.ble_kick_failed(e.toString()));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context)!;
    final app = context.watch<ChameleonGUIState>();
    final connected =
        app.communicator != null && (app.connector?.connected ?? false);
    if (!connected &&
        (_flooding || _startingFlood || _broadcasting || _pollTimer != null)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted ||
            (_app.communicator != null &&
                (_app.connector?.connected ?? false))) {
          return;
        }
        setState(_clearLocalActivity);
      });
    }
    final body = !connected
        ? Center(child: Text(localizations.ble_no_device_connected))
        : SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                BleCapabilityGate(
                  feature: localizations.ble_write_cmd_flood,
                  requiredCommands: const [
                    ChameleonCommand.bleCentralState,
                    ChameleonCommand.bleFloodStart,
                    ChameleonCommand.bleFloodStop,
                    ChameleonCommand.bleFloodCount,
                  ],
                  child: _floodCard(),
                ),
                const SizedBox(height: 16),
                BleCapabilityGate(
                  feature: localizations.ble_kick_title,
                  requiredCommands: const [
                    ChameleonCommand.bleCentralState,
                    ChameleonCommand.bleKick,
                  ],
                  child: _kickCard(),
                ),
                const SizedBox(height: 16),
                BleCapabilityGate(
                  feature: localizations.ble_environment_broadcast_title,
                  requiredCommands: const [
                    ChameleonCommand.bleAdvFloodStart,
                    ChameleonCommand.bleFloodStop,
                    ChameleonCommand.bleFloodCount,
                  ],
                  child: _broadcastCard(),
                ),
              ],
            ),
          );
    if (widget.embedded) return body;
    return Scaffold(
      appBar: AppBar(title: Text(localizations.ble_stress_title)),
      body: body,
    );
  }

  Widget _floodCard() {
    final localizations = AppLocalizations.of(context)!;
    final bufferScopeSupported = _supportsCommands(const [
      ChameleonCommand.bleScanGetCount,
      ChameleonCommand.bleScanStop,
    ]);
    final environmentScopeSupported =
        _supportsCommands(const [ChameleonCommand.bleAdvFloodStart]);
    final selectedScopeSupported = switch (_floodScope) {
      1 => bufferScopeSupported,
      2 => environmentScopeSupported,
      _ => true,
    };
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(localizations.ble_write_cmd_flood,
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(localizations.ble_write_cmd_flood_description),
            const SizedBox(height: 12),
            DropdownButtonFormField<int>(
              initialValue: _floodScope,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: localizations.ble_scope,
                border: const OutlineInputBorder(),
              ),
              items: [
                DropdownMenuItem(
                    value: 0,
                    child: Text(localizations.ble_scope_single_central,
                        overflow: TextOverflow.ellipsis)),
                DropdownMenuItem(
                    value: 1,
                    enabled: bufferScopeSupported,
                    child: Text(localizations.ble_scope_scan_buffer_all,
                        overflow: TextOverflow.ellipsis)),
                DropdownMenuItem(
                    value: 2,
                    enabled: environmentScopeSupported,
                    child: Text(localizations.ble_scope_environment,
                        overflow: TextOverflow.ellipsis)),
              ],
              onChanged: (_flooding || _startingFlood)
                  ? null
                  : (v) => setState(() {
                        final next = v ?? 0;
                        if (_floodScope != 2 &&
                            next == 2 &&
                            _floodSize.text == '16') {
                          _floodSize.text = '0x00';
                        } else if (_floodScope == 2 &&
                            next != 2 &&
                            _floodSize.text.trim().toLowerCase() == '0x00') {
                          _floodSize.text = '16';
                        }
                        if (_floodScope != 2 &&
                            next == 2 &&
                            _floodCount.text == '0') {
                          _floodCount.text = '1';
                        } else if (_floodScope == 2 &&
                            next != 2 &&
                            _floodCount.text == '1') {
                          _floodCount.text = '0';
                        }
                        _floodScope = next;
                      }),
            ),
            if (_floodScope != 2) ...[
              const SizedBox(height: 8),
              TextField(
                controller: _floodHandle,
                enabled: !_flooding && !_startingFlood,
                decoration: InputDecoration(
                  labelText: localizations.ble_value_handle,
                  hintText: '0x0012',
                  border: const OutlineInputBorder(),
                ),
              ),
            ],
            const SizedBox(height: 8),
            BleResponsiveFieldGroup(
              children: [
                TextField(
                  controller: _floodSize,
                  enabled: !_flooding && !_startingFlood,
                  keyboardType: _floodScope == 2
                      ? TextInputType.text
                      : TextInputType.number,
                  decoration: InputDecoration(
                    labelText: _floodScope == 2
                        ? localizations.ble_fill_byte_with_range
                        : localizations
                            .ble_payload_size_with_range(_bleFloodPayloadMax),
                    border: const OutlineInputBorder(),
                  ),
                ),
                TextField(
                  controller: _floodCount,
                  enabled: !_flooding && !_startingFlood,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: _floodScope == 2
                        ? localizations.ble_interval_units_with_range
                        : localizations.ble_max_iterations,
                    border: const OutlineInputBorder(),
                  ),
                ),
                if (_floodScope != 2)
                  TextField(
                    controller: _floodInterval,
                    enabled: !_flooding && !_startingFlood,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: localizations.ble_interval_parenthesized_ms,
                      border: const OutlineInputBorder(),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                FilledButton.icon(
                  icon: const Icon(Icons.play_arrow),
                  label: Text(localizations.ble_start),
                  onPressed:
                      (_flooding || _startingFlood || !selectedScopeSupported)
                          ? null
                          : _startFlood,
                ),
                FilledButton.tonalIcon(
                  icon: const Icon(Icons.stop),
                  label: Text(localizations.ble_stop),
                  onPressed: (_flooding && !_startingFlood) ? _stopFlood : null,
                ),
                if (_floodScope != 2) ...[
                  IconButton(
                    icon: const Icon(Icons.refresh),
                    tooltip: localizations.ble_refresh_sent_count,
                    onPressed: _pollInFlight ? null : _refreshFloodCount,
                  ),
                ],
                if (_floodScope != 2)
                  Text(localizations.ble_sent_count(_floodSent),
                      style: Theme.of(context).textTheme.titleMedium)
                else
                  Text(
                      _broadcasting
                          ? localizations.ble_broadcasting
                          : localizations.ble_status_idle_title,
                      style: Theme.of(context).textTheme.titleMedium),
              ],
            ),
            if (_floodError != null) ...[
              const SizedBox(height: 8),
              Text(_floodError!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _kickCard() {
    final localizations = AppLocalizations.of(context)!;
    final bufferScopeSupported = _supportsCommands(const [
      ChameleonCommand.bleScanGetCount,
      ChameleonCommand.bleScanStop,
    ]);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(localizations.ble_kick_title,
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(localizations.ble_kick_description),
            const SizedBox(height: 12),
            DropdownButtonFormField<int>(
              initialValue: _kickScope,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: localizations.ble_scope,
                border: const OutlineInputBorder(),
              ),
              items: [
                DropdownMenuItem(
                    value: 0,
                    child: Text(localizations.ble_scope_single,
                        overflow: TextOverflow.ellipsis)),
                DropdownMenuItem(
                    value: 1,
                    enabled: bufferScopeSupported,
                    child: Text(localizations.ble_scope_scan_buffer,
                        overflow: TextOverflow.ellipsis)),
              ],
              onChanged: (v) => setState(() {
                final next = v ?? 0;
                if (next == 0) {
                  _kickCycles.text = '1';
                } else if (_kickCycles.text == '1') {
                  _kickCycles.text = '3';
                }
                _kickScope = next;
              }),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _kickCycles,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: _kickScope == 0
                    ? localizations.ble_cycles_single
                    : localizations.ble_cycles_per_peer,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  icon: const Icon(Icons.bolt),
                  label: Text(localizations.ble_kick),
                  onPressed:
                      _kickScope == 1 && !bufferScopeSupported ? null : _kick,
                ),
              ],
            ),
            if (_kickError != null) ...[
              const SizedBox(height: 8),
              Text(_kickError!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _broadcastCard() {
    final localizations = AppLocalizations.of(context)!;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(localizations.ble_environment_broadcast_title,
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(localizations.ble_environment_broadcast_description),
            const SizedBox(height: 12),
            BleResponsiveFieldGroup(
              children: [
                TextField(
                  controller: _advFill,
                  enabled: !_flooding && !_startingFlood,
                  decoration: InputDecoration(
                    labelText: localizations.ble_fill_byte,
                    hintText: '0x00',
                    border: const OutlineInputBorder(),
                  ),
                ),
                TextField(
                  controller: _advIntervalUnits,
                  enabled: !_flooding && !_startingFlood,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: localizations.ble_interval_units_with_range,
                    border: const OutlineInputBorder(),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  icon: const Icon(Icons.podcasts),
                  label: Text(localizations.ble_start_broadcast),
                  onPressed:
                      (_flooding || _startingFlood) ? null : _startBroadcast,
                ),
                FilledButton.tonalIcon(
                  icon: const Icon(Icons.stop),
                  label: Text(localizations.ble_stop),
                  onPressed: _broadcasting ? _stopFlood : null,
                ),
              ],
            ),
            if (_broadcastError != null) ...[
              const SizedBox(height: 8),
              Text(_broadcastError!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
          ],
        ),
      ),
    );
  }
}

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui';

import 'package:chameleonultragui/bridge/chameleon.dart';
import 'package:chameleonultragui/helpers/definitions.dart';
import 'package:chameleonultragui/helpers/general.dart';
import 'package:chameleonultragui/helpers/hf_capture.dart';
import 'package:chameleonultragui/helpers/hf_capture_controller.dart';
import 'package:chameleonultragui/helpers/hf_sniff.dart';
import 'package:chameleonultragui/helpers/mifare_classic/autopwn_v2.dart';
import 'package:chameleonultragui/helpers/mifare_classic/emulation_key_recovery.dart';
import 'package:chameleonultragui/helpers/mifare_classic/general.dart';
import 'package:chameleonultragui/helpers/mifare_ultralight/general.dart';
import 'package:chameleonultragui/gui/undercover/undercover_grid.dart';
import 'package:chameleonultragui/main.dart';
import 'package:chameleonultragui/sharedprefsprovider.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

const _green = Color(0xFF30D158);
const _red = Color(0xFFFF453A);
const _blue = Color(0xFF0A84FF);
const _orange = Color(0xFFFF9F0A);

final _deviceOperations = _DashboardDeviceCoordinator();

class _DashboardDeviceCoordinator extends ChangeNotifier {
  Object? _token;
  String? _owner;
  int? activeSlot;

  String? get owner => _owner;

  _DeviceOperationLease? acquire(String owner) {
    if (_token != null) return null;
    final token = Object();
    _token = token;
    _owner = owner;
    notifyListeners();
    return _DeviceOperationLease(() {
      if (!identical(_token, token)) return;
      _token = null;
      _owner = null;
      notifyListeners();
    });
  }

  void selectedSlot(int index) {
    if (activeSlot == index) return;
    activeSlot = index;
    notifyListeners();
  }
}

class _DeviceOperationLease {
  _DeviceOperationLease(this._onRelease);

  final VoidCallback _onRelease;
  bool _released = false;

  void release() {
    if (_released) return;
    _released = true;
    _onRelease();
  }
}

class _SlotSnapshot {
  const _SlotSnapshot({
    required this.index,
    required this.name,
    required this.type,
    required this.enabled,
  });

  final int index;
  final String name;
  final TagType type;
  final bool enabled;
}

Future<List<_SlotSnapshot>> _readHfSlots(
  ChameleonCommunicator communicator,
) async {
  final names = await communicator.getSlotTagNames();
  final types = await communicator.getSlotTagTypes();
  final enabled = await communicator.getEnabledSlots();
  return List.generate(8, (index) {
    final name = names[index].hf.trim();
    return _SlotSnapshot(
      index: index,
      name: name.isEmpty ? 'Slot ${index + 1}' : name,
      type: types[index].hf,
      enabled: enabled[index].hf,
    );
  });
}

String _tagLabel(TagType type) =>
    type == TagType.unknown ? 'Empty HF slot' : 'HF card configured';

void _showNotice(BuildContext context, String message, {bool error = false}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        backgroundColor: error
            ? const Color(0xE6B42318)
            : const Color(0xE62C2C2E),
        content: Text(message),
      ),
    );
}

_DeviceOperationLease? _beginDeviceOperation(
  BuildContext context,
  String owner, {
  bool allowDuringCapture = false,
  bool quiet = false,
}) {
  final appState = context.read<ChameleonGUIState>();
  final capture = appState.hfCaptureController;
  if (!allowDuringCapture &&
      (capture.isRunning ||
          capture.isBusy ||
          capture.needsDrain ||
          capture.needsFinalize)) {
    if (!quiet) {
      _showNotice(context, 'A journal update is already in progress.');
    }
    return null;
  }
  final lease = _deviceOperations.acquire(owner);
  if (lease == null && !quiet) {
    _showNotice(context, 'Another update is already in progress.');
  }
  return lease;
}

Future<T?> _showUndercoverSheet<T>(
  BuildContext context, {
  required String title,
  required Widget child,
  double heightFactor = 0.72,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black54,
    builder: (context) => FractionallySizedBox(
      heightFactor: heightFactor,
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: const Color(0xF21C1C1E),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(30),
              ),
              border: Border.all(color: Colors.white24),
            ),
            child: Column(
              children: [
                const SizedBox(height: 9),
                Container(
                  width: 38,
                  height: 5,
                  decoration: BoxDecoration(
                    color: Colors.white38,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 14, 10, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      IconButton(
                        key: const Key('undercover-sheet-close'),
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(
                          Icons.cancel_rounded,
                          color: Colors.white54,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(child: child),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class _GlassCard extends StatelessWidget {
  const _GlassCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xD92A2D43),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x29000000),
            blurRadius: 12,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Padding(padding: const EdgeInsets.all(14), child: child),
    );
  }
}

class _SelectedCardWeatherWidget extends StatelessWidget {
  const _SelectedCardWeatherWidget({
    super.key,
    required this.cardName,
    required this.description,
    required this.busy,
  });

  final String cardName;
  final String description;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    const shape = ContinuousRectangleBorder(
      borderRadius: BorderRadius.all(Radius.circular(42)),
      side: BorderSide(color: Color(0x47FFFFFF), width: 0.8),
    );
    return Semantics(
      label: 'Weather, Madrid, selected card, $cardName, $description',
      child: DecoratedBox(
        decoration: const ShapeDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF72C7FF), Color(0xFF2479E8), Color(0xFF173F9C)],
            stops: [0, 0.52, 1],
          ),
          shape: shape,
          shadows: [
            BoxShadow(
              color: Color(0x30000000),
              blurRadius: 18,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: ClipPath(
          clipper: const ShapeBorderClipper(shape: shape),
          child: Stack(
            fit: StackFit.expand,
            children: [
              const Positioned(
                top: -32,
                right: -20,
                child: Icon(
                  Icons.wb_sunny_rounded,
                  color: Color(0x5CFFF1A6),
                  size: 142,
                ),
              ),
              const Positioned(
                top: 1,
                left: 58,
                right: 58,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.transparent,
                        Color(0xA6FFFFFF),
                        Colors.transparent,
                      ],
                    ),
                  ),
                  child: SizedBox(height: 1),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
                child: Row(
                  children: [
                    Expanded(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'WEATHER',
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 1.1,
                              ),
                            ),
                            const SizedBox(height: 4),
                            const Text(
                              'Madrid',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 28,
                                height: 1,
                                fontWeight: FontWeight.w600,
                                letterSpacing: -0.8,
                                shadows: [
                                  Shadow(color: Colors.black26, blurRadius: 6),
                                ],
                              ),
                            ),
                            const SizedBox(height: 12),
                            const Text(
                              'Selected card',
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              cardName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                                height: 1.1,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              description,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 10,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 70,
                      child: Center(
                        child: busy
                            ? const SizedBox.square(
                                dimension: 28,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2.5,
                                ),
                              )
                            : const Icon(
                                Icons.cloud_rounded,
                                color: Colors.white,
                                size: 56,
                                shadows: [
                                  Shadow(
                                    color: Color(0x33000000),
                                    blurRadius: 8,
                                    offset: Offset(0, 3),
                                  ),
                                ],
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class UndercoverSlotsDashboard extends StatefulWidget {
  const UndercoverSlotsDashboard({super.key});

  @override
  State<UndercoverSlotsDashboard> createState() =>
      _UndercoverSlotsDashboardState();
}

class _UndercoverSlotsDashboardState extends State<UndercoverSlotsDashboard>
    with AutomaticKeepAliveClientMixin {
  ChameleonCommunicator? _communicator;
  List<_SlotSnapshot> _slots = const [];
  int _activeSlot = 0;
  bool? _readerMode;
  bool _busy = false;
  String? _error;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _deviceOperations.addListener(_syncSharedSlot);
  }

  void _syncSharedSlot() {
    final slot = _deviceOperations.activeSlot;
    if (mounted && slot != null && slot != _activeSlot) {
      setState(() => _activeSlot = slot);
    }
    if (mounted &&
        _deviceOperations.owner == null &&
        _communicator != null &&
        _slots.isEmpty &&
        !_busy) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_refresh());
      });
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final communicator = context.watch<ChameleonGUIState>().communicator;
    if (identical(communicator, _communicator)) return;
    _communicator = communicator;
    _slots = const [];
    _readerMode = null;
    _error = null;
    _busy = false;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_refresh());
    });
  }

  Future<void> _refresh() async {
    final communicator = _communicator;
    if (communicator == null || _busy) return;
    final lease = _beginDeviceOperation(context, 'Home sync', quiet: true);
    if (lease == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final active = await communicator.getActiveSlot();
      final slots = await _readHfSlots(communicator);
      final readerMode = await communicator.isReaderDeviceMode();
      if (!mounted || !identical(communicator, _communicator)) return;
      setState(() {
        _activeSlot = active;
        _slots = slots;
        _readerMode = readerMode;
      });
      _deviceOperations.selectedSlot(active);
    } catch (error) {
      if (mounted && identical(communicator, _communicator)) {
        setState(() => _error = 'Lists could not be updated.');
      }
    } finally {
      lease.release();
      if (mounted && identical(communicator, _communicator)) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _selectSlot(int index) async {
    final appState = context.read<ChameleonGUIState>();
    final communicator = appState.communicator;
    if (communicator == null || _busy) return;
    final lease = _beginDeviceOperation(context, 'Slot selection');
    if (lease == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await appState.runSlotOperation(() => communicator.activateSlot(index));
      appState.changesMade();
      _deviceOperations.selectedSlot(index);
      if (mounted) setState(() => _activeSlot = index);
    } catch (error) {
      if (mounted) {
        setState(() => _error = 'The selected list could not be opened.');
        _showNotice(
          context,
          'The selected list could not be opened.',
          error: true,
        );
      }
    } finally {
      lease.release();
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _deviceOperations.removeListener(_syncSharedSlot);
    super.dispose();
  }

  void _move(int delta) {
    if (_slots.isEmpty) return;
    for (var offset = 1; offset <= _slots.length; offset++) {
      final index =
          (_activeSlot + delta * offset + _slots.length) % _slots.length;
      final slot = _slots[index];
      if (slot.enabled && slot.type != TagType.unknown) {
        unawaited(_selectSlot(index));
        return;
      }
    }
  }

  Future<void> _toggleDeviceMode() async {
    final appState = context.read<ChameleonGUIState>();
    final communicator = appState.communicator;
    final readerMode = _readerMode;
    if (communicator == null || readerMode == null || _busy) return;
    final lease = _beginDeviceOperation(context, 'Device mode');
    if (lease == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final nextReaderMode = !readerMode;
      await communicator.setReaderDeviceMode(nextReaderMode);
      if (!mounted || !identical(communicator, _communicator)) return;
      setState(() => _readerMode = nextReaderMode);
      appState.changesMade();
    } catch (error) {
      if (mounted && identical(communicator, _communicator)) {
        setState(() => _error = 'Device mode could not be changed.');
        _showNotice(context, 'Device mode could not be changed.', error: true);
      }
    } finally {
      lease.release();
      if (mounted && identical(communicator, _communicator)) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final slot = _slots.isEmpty ? null : _slots[_activeSlot.clamp(0, 7)];
    final connected = _communicator != null;
    final hasSelectableCards = _slots.any(
      (entry) => entry.enabled && entry.type != TagType.unknown,
    );
    return UndercoverSpringGrid(
      key: const Key('undercover-grid-home'),
      placements: [
        UndercoverGridPlacement(
          row: 0,
          column: 0,
          rowSpan: 2,
          columnSpan: 4,
          child: _SelectedCardWeatherWidget(
            key: const Key('undercover-card-weather'),
            cardName: slot?.name ?? 'No card selected',
            description:
                _error ??
                (connected
                    ? 'Slot ${_activeSlot + 1}'
                    : 'Connect a device to load cards'),
            busy: _busy,
          ),
        ),
        UndercoverGridPlacement(
          row: 5,
          column: 0,
          rowSpan: 1,
          columnSpan: 1,
          child: UndercoverGridTile(
            key: const Key('undercover-slot-previous'),
            label: 'Previous',
            icon: Icons.chevron_left_rounded,
            color: const Color(0xFF5E5CE6),
            enabled: !_busy && hasSelectableCards,
            onPressed: () => _move(-1),
          ),
        ),
        UndercoverGridPlacement(
          row: 5,
          column: 1,
          rowSpan: 1,
          columnSpan: 1,
          child: UndercoverGridTile(
            key: const Key('undercover-device-connected'),
            label: connected ? 'Connected' : 'Disconnected',
            icon: connected ? Icons.check_rounded : Icons.close_rounded,
            color: connected ? _green : _red,
            selected: connected,
          ),
        ),
        UndercoverGridPlacement(
          row: 5,
          column: 2,
          rowSpan: 1,
          columnSpan: 1,
          child: UndercoverGridTile(
            key: const Key('undercover-device-mode'),
            label: switch (_readerMode) {
              true => 'Reader Mode',
              false => 'Emulation',
              null => 'Device Mode',
            },
            icon: _readerMode == false
                ? Icons.contactless_rounded
                : Icons.barcode_reader,
            color: _readerMode == false ? const Color(0xFFBF5AF2) : _blue,
            enabled: connected && _readerMode != null && !_busy,
            busy: _busy,
            onPressed: () => unawaited(_toggleDeviceMode()),
          ),
        ),
        UndercoverGridPlacement(
          row: 5,
          column: 3,
          rowSpan: 1,
          columnSpan: 1,
          child: UndercoverGridTile(
            key: const Key('undercover-slot-next'),
            label: 'Next',
            icon: Icons.chevron_right_rounded,
            color: const Color(0xFF5E5CE6),
            enabled: !_busy && hasSelectableCards,
            onPressed: () => _move(1),
          ),
        ),
      ],
    );
  }
}

class _SlotGlyph extends StatelessWidget {
  const _SlotGlyph({required this.type});

  final TagType type;

  @override
  Widget build(BuildContext context) {
    return Icon(
      type == TagType.unknown ? Icons.add_rounded : Icons.checklist_rounded,
      color: Colors.white,
      size: 28,
    );
  }
}

@visibleForTesting
List<double> buildRecoverySectorChartValues({
  required int seed,
  required List<int> keysPerSector,
  List<int> identity = const [],
}) {
  var combinedSeed = seed ^ (keysPerSector.length * 1049);
  for (final byte in identity) {
    combinedSeed = ((combinedSeed * 31) ^ byte) & 0x7FFFFFFF;
  }
  return List.generate(keysPerSector.length, (sector) {
    final keyCount = keysPerSector[sector];
    final random = math.Random(
      combinedSeed ^ (sector * 7919) ^ (keyCount * 65537),
    );
    return switch (keyCount) {
      0 => -25 + random.nextDouble() * 22,
      1 => 3 + random.nextDouble() * 21,
      _ => 27 + random.nextDouble() * 23,
    };
  });
}

class _KeyRecoveryStockWidget extends StatelessWidget {
  const _KeyRecoveryStockWidget({
    super.key,
    required this.card,
    required this.verified,
    required this.total,
    required this.status,
    required this.series,
    required this.error,
  });

  final CardData? card;
  final int verified;
  final int total;
  final String status;
  final List<double> series;
  final bool error;

  @override
  Widget build(BuildContext context) {
    const shape = ContinuousRectangleBorder(
      borderRadius: BorderRadius.all(Radius.circular(42)),
      side: BorderSide(color: Color(0x38FFFFFF), width: 0.8),
    );
    final card = this.card;
    final statusColor = error
        ? _red
        : status == 'COMPLETE'
        ? _green
        : status == 'AUTOPWN'
        ? _orange
        : const Color(0xFF64D2FF);
    final metrics = [
      ('UUID', card == null ? '--' : bytesToHex(card.uid).toUpperCase()),
      ('ATK', card == null ? '--' : bytesToHex(card.atqa).toUpperCase()),
      (
        'SAK',
        card == null
            ? '--'
            : card.sak.toRadixString(16).padLeft(2, '0').toUpperCase(),
      ),
      ('KEYS', '$verified/$total'),
    ];
    return Semantics(
      container: true,
      label:
          'MIFARE recovery stocks, status $status, $verified of $total keys recovered. '
          'Sector chart from 0 to ${series.length - 1}: below zero means no key, '
          'above zero means one key, and above 25 means both keys.',
      child: DecoratedBox(
        decoration: const ShapeDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF182439), Color(0xFF101B2A), Color(0xFF102A25)],
          ),
          shape: shape,
          shadows: [
            BoxShadow(
              color: Color(0x30000000),
              blurRadius: 18,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: ClipPath(
          clipper: const ShapeBorderClipper(shape: shape),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxHeight < 150;
              final metricsWidth = (constraints.maxWidth * 0.36).clamp(
                100.0,
                132.0,
              );
              return Stack(
                fit: StackFit.expand,
                children: [
                  const Positioned(
                    top: 1,
                    left: 58,
                    right: 58,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Colors.transparent,
                            Color(0x8AFFFFFF),
                            Colors.transparent,
                          ],
                        ),
                      ),
                      child: SizedBox(height: 1),
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.all(compact ? 10 : 14),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Expanded(
                                    child: Text(
                                      'MFC KEY INDEX',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: Colors.white70,
                                        fontSize: 9,
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: 0.9,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 5),
                                  DecoratedBox(
                                    decoration: BoxDecoration(
                                      color: statusColor.withValues(
                                        alpha: 0.16,
                                      ),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                        color: statusColor.withValues(
                                          alpha: 0.44,
                                        ),
                                      ),
                                    ),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 5,
                                        vertical: 2,
                                      ),
                                      child: Text(
                                        status,
                                        style: TextStyle(
                                          color: statusColor,
                                          fontSize: 7,
                                          height: 1,
                                          fontWeight: FontWeight.w800,
                                          letterSpacing: 0.5,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 5),
                              Expanded(
                                child: CustomPaint(
                                  key: const Key(
                                    'undercover-recovery-stock-chart',
                                  ),
                                  painter: _RecoveryStockChartPainter(
                                    points: series,
                                    color: statusColor,
                                  ),
                                  child: const SizedBox.expand(),
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                '$verified of $total keys recovered',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white60,
                                  fontSize: 8.5,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                        SizedBox(width: compact ? 8 : 12),
                        Container(
                          width: 1,
                          color: Colors.white.withValues(alpha: 0.1),
                        ),
                        SizedBox(width: compact ? 8 : 12),
                        SizedBox(
                          width: metricsWidth,
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              for (final metric in metrics)
                                _StockMetricRow(
                                  label: metric.$1,
                                  value: metric.$2,
                                  active: card != null || metric.$1 == 'KEYS',
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _StockMetricRow extends StatelessWidget {
  const _StockMetricRow({
    required this.label,
    required this.value,
    required this.active,
  });

  final String label;
  final String value;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 34,
          child: Text(
            label,
            style: TextStyle(
              color: active ? const Color(0xFF64D2FF) : Colors.white30,
              fontSize: 8,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.5,
            ),
          ),
        ),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.end,
            style: TextStyle(
              color: active ? Colors.white : Colors.white30,
              fontSize: 8,
              height: 1,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

class _RecoveryStockChartPainter extends CustomPainter {
  const _RecoveryStockChartPainter({required this.points, required this.color});

  final List<double> points;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2 || size.isEmpty) return;
    const minimum = -30.0;
    const maximum = 55.0;
    final chart = Rect.fromLTRB(15, 2, size.width - 2, size.height - 10);
    if (chart.width <= 0 || chart.height <= 0) return;

    double yFor(double value) =>
        chart.bottom -
        ((value.clamp(minimum, maximum) - minimum) / (maximum - minimum)) *
            chart.height;

    final zeroY = yFor(0);
    final twoKeysY = yFor(25);
    canvas.drawLine(
      Offset(chart.left, zeroY),
      Offset(chart.right, zeroY),
      Paint()
        ..color = Colors.white.withValues(alpha: 0.24)
        ..strokeWidth = 0.8,
    );
    canvas.drawLine(
      Offset(chart.left, twoKeysY),
      Offset(chart.right, twoKeysY),
      Paint()
        ..color = _green.withValues(alpha: 0.3)
        ..strokeWidth = 0.8,
    );
    _paintChartLabel(canvas, '0', Offset(0, zeroY - 4));
    _paintChartLabel(canvas, '25', Offset(0, twoKeysY - 4));

    final maxSector = points.length - 1;
    final sectorStep = math.max(1, (maxSector / 4).ceil());
    final sectors = <int>{
      0,
      maxSector,
      for (var sector = sectorStep; sector < maxSector; sector += sectorStep)
        sector,
    }.toList()..sort();
    for (final sector in sectors) {
      final x = chart.left + chart.width * sector / maxSector;
      canvas.drawLine(
        Offset(x, chart.bottom),
        Offset(x, chart.bottom + 2),
        Paint()
          ..color = Colors.white.withValues(alpha: 0.2)
          ..strokeWidth = 0.6,
      );
      _paintChartLabel(
        canvas,
        '$sector',
        Offset(x, chart.bottom + 2),
        centered: true,
      );
    }

    final path = Path();
    for (var index = 0; index < points.length; index++) {
      final point = Offset(
        chart.left + chart.width * index / maxSector,
        yFor(points[index]),
      );
      if (index == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }

    final fillPath = Path.from(path)
      ..lineTo(chart.right, zeroY)
      ..lineTo(chart.left, zeroY)
      ..close();
    canvas.drawPath(
      fillPath,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            color.withValues(alpha: 0.28),
            color.withValues(alpha: 0.01),
          ],
        ).createShader(Offset.zero & size),
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    final pointRadius = points.length > 24 ? 1.5 : 2.1;
    for (var sector = 0; sector < points.length; sector++) {
      final value = points[sector];
      final pointColor = value < 0
          ? _red
          : value > 25
          ? _green
          : _orange;
      canvas.drawCircle(
        Offset(chart.left + chart.width * sector / maxSector, yFor(value)),
        pointRadius,
        Paint()..color = pointColor,
      );
    }
  }

  void _paintChartLabel(
    Canvas canvas,
    String text,
    Offset offset, {
    bool centered = false,
  }) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: const TextStyle(
          color: Colors.white38,
          fontSize: 6,
          height: 1,
          fontWeight: FontWeight.w600,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(
      canvas,
      centered ? offset.translate(-painter.width / 2, 0) : offset,
    );
  }

  @override
  bool shouldRepaint(covariant _RecoveryStockChartPainter oldDelegate) =>
      !identical(points, oldDelegate.points) || color != oldDelegate.color;
}

class UndercoverRecoveryDashboard extends StatefulWidget {
  const UndercoverRecoveryDashboard({super.key});

  @override
  State<UndercoverRecoveryDashboard> createState() =>
      _UndercoverRecoveryDashboardState();
}

class _UndercoverRecoveryDashboardState
    extends State<UndercoverRecoveryDashboard>
    with AutomaticKeepAliveClientMixin {
  static const _runner = AutopwnV2Runner();

  late final int _stockSeed;
  late List<double> _stockSeries;
  final Set<String> _selectedDictionaryIds = {};
  List<Dictionary> _dictionaries = const [];
  CardData? _hfCard;
  TagType _hfTagType = TagType.unknown;
  AutopwnV2Progress? _progress;
  AutopwnV2Result? _result;
  MifareClassicAutopwnV2Port? _port;
  _DeviceOperationLease? _recoveryLease;
  bool _readingHf = false;
  bool _running = false;
  String? _error;
  bool _loadedDictionaries = false;
  ChameleonCommunicator? _communicator;
  int _operationGeneration = 0;

  @override
  void initState() {
    super.initState();
    _stockSeed = DateTime.now().microsecondsSinceEpoch & 0x7FFFFFFF;
    _stockSeries = _stockSeriesFor();
  }

  @override
  bool get wantKeepAlive => true;

  List<double> _stockSeriesFor({
    CardData? card,
    int total = 32,
    Iterable<AutopwnV2VerifiedKey> verifiedKeys = const [],
  }) {
    final sectorCount = math.max(1, (total + 1) ~/ 2);
    final keysPerSector = List<int>.filled(sectorCount, 0);
    for (final key in verifiedKeys) {
      if (key.sector >= 0 && key.sector < sectorCount) {
        keysPerSector[key.sector] = math.min(2, keysPerSector[key.sector] + 1);
      }
    }
    return buildRecoverySectorChartValues(
      seed: _stockSeed,
      keysPerSector: keysPerSector,
      identity: card?.uid ?? const [],
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final appState = context.watch<ChameleonGUIState>();
    final communicator = appState.communicator;
    if (!identical(communicator, _communicator)) {
      _operationGeneration++;
      _port?.cancel();
      _communicator = communicator;
      _readingHf = false;
      _running = false;
    }
    if (!_loadedDictionaries) {
      _dictionaries = appState.sharedPreferencesProvider.getDictionaries(
        keyLength: 12,
      );
      _selectedDictionaryIds.addAll(_dictionaries.map((entry) => entry.id));
      _loadedDictionaries = true;
    }
  }

  List<Dictionary> get _selectedDictionaries => _dictionaries
      .where((entry) => _selectedDictionaryIds.contains(entry.id))
      .toList();

  @override
  void dispose() {
    _operationGeneration++;
    _port?.cancel();
    super.dispose();
  }

  bool _isCurrent(int generation, ChameleonCommunicator communicator) =>
      mounted &&
      generation == _operationGeneration &&
      identical(communicator, _communicator);

  Future<void> _readHf() async {
    final communicator = _communicator;
    if (communicator == null || _readingHf || _running) return;
    final lease = _beginDeviceOperation(context, 'HF card scan');
    if (lease == null) return;
    final generation = ++_operationGeneration;
    setState(() {
      _readingHf = true;
      _hfCard = null;
      _hfTagType = TagType.unknown;
      _stockSeries = _stockSeriesFor();
      _error = null;
    });
    try {
      final readerMode = await communicator.isReaderDeviceMode();
      if (!_isCurrent(generation, communicator)) return;
      if (!readerMode) {
        await communicator.setReaderDeviceMode(true);
        if (!_isCurrent(generation, communicator)) return;
      }
      final card = await communicator.scan14443aTag();
      if (!_isCurrent(generation, communicator)) return;
      var tagType = TagType.unknown;
      if (card != null) {
        try {
          if (await communicator.detectMf1Support()) {
            if (!_isCurrent(generation, communicator)) return;
            tagType = mfClassicGetChameleonTagType(
              await mfClassicGetType(communicator),
            );
            if (!_isCurrent(generation, communicator)) return;
          } else if (card.sak == 0x20) {
            tagType = TagType.hf14a4;
          }
        } catch (_) {
          tagType = TagType.unknown;
        }
      }
      if (!_isCurrent(generation, communicator)) return;
      setState(() {
        _hfCard = card;
        _hfTagType = tagType;
        _stockSeries = _stockSeriesFor(card: card);
      });
      if (card == null && mounted) {
        _showNotice(context, 'No ISO 14443-A card was found.');
      }
    } catch (error) {
      if (!mounted) return;
      if (_isCurrent(generation, communicator)) {
        setState(() {
          _hfCard = null;
          _hfTagType = TagType.unknown;
          _stockSeries = _stockSeriesFor();
          _error = 'The HF card scan failed.';
        });
        _showNotice(context, 'The HF card scan failed.', error: true);
      }
    } finally {
      lease.release();
      if (_isCurrent(generation, communicator)) {
        setState(() => _readingHf = false);
      }
    }
  }

  Future<void> _saveUuid() async {
    final card = _hfCard;
    if (card == null) return;
    if (_hfTagType == TagType.unknown) {
      _showNotice(context, 'The scanned card type cannot be saved.');
      return;
    }
    final appState = context.read<ChameleonGUIState>();
    final cards = appState.sharedPreferencesProvider.getCards();
    final uid = bytesToHexSpace(card.uid).toUpperCase();
    cards.add(
      CardSave(
        uid: uid,
        sak: card.sak,
        atqa: Uint8List.fromList(card.atqa),
        ats: Uint8List.fromList(card.ats),
        name:
            'Recovered card ${DateTime.now().toIso8601String().substring(0, 16)}',
        tag: _hfTagType,
      ),
    );
    await appState.sharedPreferencesProvider.setCards(cards);
    if (mounted) _showNotice(context, 'Scanned card saved.');
  }

  Future<bool> _sameCard(
    ChameleonCommunicator communicator,
    String uid,
    String atqa,
    String sak,
  ) async {
    final card = await communicator.scan14443aTag();
    return card != null &&
        bytesToHexSpace(card.uid) == uid &&
        bytesToHexSpace(card.atqa) == atqa &&
        card.sak.toRadixString(16).padLeft(2, '0').toUpperCase() == sak;
  }

  Future<void> _runAutopwn() async {
    if (_running) return;
    final appState = context.read<ChameleonGUIState>();
    final communicator = appState.communicator;
    if (communicator == null) return;
    final lease = _beginDeviceOperation(context, 'MIFARE Autopwn');
    if (lease == null) return;
    final generation = ++_operationGeneration;
    _recoveryLease = lease;
    setState(() {
      _running = true;
      _result = null;
      _progress = null;
      _stockSeries = _stockSeriesFor(card: _hfCard);
      _error = null;
    });
    try {
      final (card, mfc, _) = await readHFInfo(context, () {
        if (_isCurrent(generation, communicator)) setState(() {});
      });
      if (!_isCurrent(generation, communicator)) return;
      if (!card.cardExist || mfc.recovery == null) {
        throw StateError('No compatible MIFARE Classic asset found');
      }
      final scannedCard = mfc.recovery!.cardIdentity;
      if (scannedCard != null) {
        setState(() {
          _hfCard = scannedCard;
          _hfTagType = card.type;
          _stockSeries = _stockSeriesFor(card: scannedCard);
        });
      }
      final port = MifareClassicAutopwnV2Port(
        mfc.recovery!,
        hintedNtLevel: mfc.ntLevel,
        hintedBackdoor: mfc.hasBackdoor,
      );
      setState(() => _port = port);
      final result = await _runner.run(
        recovery: port,
        options: AutopwnV2Options(
          dictionaries: _selectedDictionaries,
          exhaustiveEvidence: true,
          createPartialDump: true,
        ),
        onProgress: (progress) {
          if (_isCurrent(generation, communicator)) {
            setState(() {
              _progress = progress;
              _stockSeries = _stockSeriesFor(
                card: _hfCard,
                total: progress.totalSlots,
                verifiedKeys: port.verifiedKeys,
              );
            });
          }
        },
        cardGuard: () {
          if (!_isCurrent(generation, communicator) ||
              !identical(appState.communicator, communicator)) {
            return Future<bool>.value(false);
          }
          return _sameCard(communicator, card.uid, card.atqa, card.sak);
        },
      );
      if (_isCurrent(generation, communicator)) {
        setState(() {
          _result = result;
          _stockSeries = _stockSeriesFor(
            card: _hfCard,
            total: result.totalKeySlots,
            verifiedKeys: result.verifiedKeys,
          );
        });
      }
    } catch (error) {
      if (!mounted) return;
      if (_isCurrent(generation, communicator)) {
        setState(() => _error = 'Autopwn could not recover the card keys.');
        _showNotice(
          context,
          'Autopwn could not recover the card keys.',
          error: true,
        );
      }
    } finally {
      lease.release();
      if (identical(_recoveryLease, lease)) _recoveryLease = null;
      if (_isCurrent(generation, communicator)) {
        setState(() {
          _running = false;
          _port = null;
        });
      }
    }
  }

  void _cancelAutopwn() {
    _port?.cancel();
    if (mounted) setState(() {});
  }

  Future<void> _chooseDictionaries() async {
    await _showUndercoverSheet<void>(
      context,
      title: 'Key dictionaries',
      child: StatefulBuilder(
        builder: (sheetContext, setSheetState) => ListView(
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 24),
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(8, 0, 8, 12),
              child: Text(
                'Select the dictionaries Autopwn should use. Built-in default keys are always included.',
                style: TextStyle(color: Colors.white60),
              ),
            ),
            if (_dictionaries.isEmpty)
              const _GlassCard(
                child: Text(
                  'No additional key dictionaries are available.',
                  style: TextStyle(color: Colors.white70),
                ),
              ),
            for (final dictionary in _dictionaries)
              CheckboxListTile(
                value: _selectedDictionaryIds.contains(dictionary.id),
                activeColor: _blue,
                checkColor: Colors.white,
                title: Text(
                  'Dictionary ${_dictionaries.indexOf(dictionary) + 1}',
                  style: const TextStyle(color: Colors.white),
                ),
                subtitle: Text(
                  '${dictionary.keys.length} keys',
                  style: const TextStyle(color: Colors.white54),
                ),
                secondary: CircleAvatar(backgroundColor: dictionary.color),
                onChanged: _running
                    ? null
                    : (selected) {
                        setState(() {
                          if (selected == true) {
                            _selectedDictionaryIds.add(dictionary.id);
                          } else {
                            _selectedDictionaryIds.remove(dictionary.id);
                          }
                        });
                        setSheetState(() {});
                      },
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _copyKeys() async {
    final result = _result;
    if (result == null) return;
    final payload = const JsonEncoder.withIndent('  ').convert({
      'verifiedKeys': result.verifiedKeys.map((key) => key.toJson()).toList(),
      'complete': result.complete,
    });
    await Clipboard.setData(ClipboardData(text: payload));
    if (mounted) _showNotice(context, 'Recovered keys copied.');
  }

  Future<void> _copyDump() async {
    final result = _result;
    if (result == null) return;
    final payload = const JsonEncoder.withIndent('  ').convert({
      'blocks': result.blocks.map((block) => block.toJson()).toList(),
      'complete': result.complete,
    });
    await Clipboard.setData(ClipboardData(text: payload));
    if (mounted) _showNotice(context, 'Recovered dump copied.');
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final card = _hfCard;
    final progress = _progress;
    final result = _result;
    final verified = result?.verifiedKeySlots ?? progress?.verifiedSlots ?? 0;
    final total = result?.totalKeySlots ?? progress?.totalSlots ?? 32;
    final stockStatus = _error != null
        ? 'ERROR'
        : _running
        ? 'AUTOPWN'
        : result?.complete == true
        ? 'COMPLETE'
        : result != null
        ? 'PARTIAL'
        : card != null
        ? 'CARD READY'
        : 'READY';
    return UndercoverSpringGrid(
      key: const Key('undercover-grid-progress'),
      placements: [
        UndercoverGridPlacement(
          row: 0,
          column: 0,
          rowSpan: 2,
          columnSpan: 4,
          child: _KeyRecoveryStockWidget(
            key: const Key('undercover-recovery-stocks'),
            card: card,
            verified: verified,
            total: total,
            status: stockStatus,
            series: _stockSeries,
            error: _error != null,
          ),
        ),
        UndercoverGridPlacement(
          row: 2,
          column: 0,
          rowSpan: 1,
          columnSpan: 1,
          child: UndercoverGridTile(
            key: const Key('undercover-recovery-hf'),
            label: 'Scan HF Card',
            value: card == null ? null : 'Found',
            icon: Icons.fact_check_rounded,
            color: _blue,
            enabled: !_readingHf && !_running && _communicator != null,
            busy: _readingHf,
            onPressed: () => unawaited(_readHf()),
          ),
        ),
        UndercoverGridPlacement(
          row: 2,
          column: 1,
          rowSpan: 1,
          columnSpan: 1,
          child: UndercoverGridTile(
            key: const Key('undercover-autopwn-weather'),
            label: _running ? 'Cancel Autopwn' : 'Run Autopwn',
            icon: _running ? Icons.stop_circle_rounded : Icons.task_alt_rounded,
            color: _running ? _red : const Color(0xFFBF5AF2),
            enabled: _running || _communicator != null,
            busy: _running,
            onPressed: _running
                ? _cancelAutopwn
                : () => unawaited(_runAutopwn()),
          ),
        ),
        UndercoverGridPlacement(
          row: 2,
          column: 2,
          rowSpan: 1,
          columnSpan: 1,
          child: UndercoverGridTile(
            label: 'Dictionaries',
            value: '${_selectedDictionaryIds.length}',
            icon: Icons.library_books_rounded,
            color: const Color(0xFF5E5CE6),
            enabled: !_running,
            onPressed: () => unawaited(_chooseDictionaries()),
          ),
        ),
        UndercoverGridPlacement(
          row: 2,
          column: 3,
          rowSpan: 1,
          columnSpan: 1,
          child: UndercoverGridTile(
            label: 'Save Card',
            icon: Icons.bookmark_add_rounded,
            color: _blue,
            enabled: card != null && _hfTagType != TagType.unknown && !_running,
            onPressed: () => unawaited(_saveUuid()),
          ),
        ),
        UndercoverGridPlacement(
          row: 3,
          column: 0,
          rowSpan: 1,
          columnSpan: 1,
          child: UndercoverGridTile(
            label: 'Copy Keys',
            icon: Icons.content_copy_rounded,
            color: const Color(0xFF64D2FF),
            enabled: result?.verifiedKeys.isNotEmpty == true,
            onPressed: () => unawaited(_copyKeys()),
          ),
        ),
        UndercoverGridPlacement(
          row: 3,
          column: 1,
          rowSpan: 1,
          columnSpan: 1,
          child: UndercoverGridTile(
            label: 'Copy Dump',
            icon: Icons.note_alt_rounded,
            color: const Color(0xFF5E5CE6),
            enabled: result?.blocks.isNotEmpty == true,
            onPressed: () => unawaited(_copyDump()),
          ),
        ),
      ],
    );
  }
}

class _HfCaptureStatusWidget extends StatelessWidget {
  const _HfCaptureStatusWidget({
    super.key,
    required this.mode,
    required this.slotName,
    required this.observed,
    required this.stored,
    required this.dropped,
    required this.bufferRatio,
    required this.running,
    required this.busy,
    required this.error,
  });

  final HfCaptureMode mode;
  final String slotName;
  final int observed;
  final int stored;
  final int dropped;
  final double bufferRatio;
  final bool running;
  final bool busy;
  final bool error;

  @override
  Widget build(BuildContext context) {
    const shape = ContinuousRectangleBorder(
      borderRadius: BorderRadius.all(Radius.circular(42)),
      side: BorderSide(color: Color(0x3DFFFFFF), width: 0.8),
    );
    final status = error
        ? 'ERROR'
        : busy
        ? 'SYNCING'
        : running
        ? 'LIVE'
        : 'READY';
    final statusColor = error
        ? _red
        : running
        ? _green
        : const Color(0xFF64D2FF);
    final modeLabel = switch (mode) {
      HfCaptureMode.emulation => 'Emulation capture',
      HfCaptureMode.passive => 'Passive sniffing',
      HfCaptureMode.reader => 'Reader capture',
    };
    final safeBufferRatio = bufferRatio.clamp(0.0, 1.0).toDouble();
    return Semantics(
      container: true,
      label:
          'HF Capture, status $status, mode $modeLabel, slot $slotName, '
          '$observed observed, $stored stored, $dropped dropped',
      child: DecoratedBox(
        decoration: const ShapeDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF19264A), Color(0xFF17213B), Color(0xFF24204B)],
          ),
          shape: shape,
          shadows: [
            BoxShadow(
              color: Color(0x30000000),
              blurRadius: 18,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: ClipPath(
          clipper: const ShapeBorderClipper(shape: shape),
          child: Stack(
            fit: StackFit.expand,
            children: [
              const Positioned(
                top: 1,
                left: 58,
                right: 58,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.transparent,
                        Color(0x8AFFFFFF),
                        Colors.transparent,
                      ],
                    ),
                  ),
                  child: SizedBox(height: 1),
                ),
              ),
              LayoutBuilder(
                builder: (context, constraints) {
                  final compact = constraints.maxHeight < 150;
                  return Padding(
                    padding: EdgeInsets.all(compact ? 10 : 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Expanded(
                              child: Text(
                                'HF CAPTURE',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  height: 1,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.8,
                                ),
                              ),
                            ),
                            DecoratedBox(
                              decoration: BoxDecoration(
                                color: statusColor.withValues(alpha: 0.16),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: statusColor.withValues(alpha: 0.44),
                                ),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                child: Text(
                                  status,
                                  style: TextStyle(
                                    color: statusColor,
                                    fontSize: 7,
                                    height: 1,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                '$modeLabel · $slotName',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 9,
                                  height: 1,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'BUFFER ${(safeBufferRatio * 100).round()}%',
                              style: const TextStyle(
                                color: Colors.white54,
                                fontSize: 7,
                                height: 1,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 3),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(3),
                          child: LinearProgressIndicator(
                            value: safeBufferRatio,
                            minHeight: 2.5,
                            backgroundColor: Colors.white10,
                            valueColor: AlwaysStoppedAnimation(statusColor),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Expanded(
                          child: CustomPaint(
                            key: const Key('undercover-capture-signal'),
                            painter: _HfCaptureSignalPainter(
                              observed: observed,
                              dropped: dropped,
                              running: running,
                              color: statusColor,
                            ),
                            child: const SizedBox.expand(),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            _CaptureMetric(label: 'Observed', value: observed),
                            _CaptureMetric(label: 'Stored', value: stored),
                            _CaptureMetric(
                              label: 'Dropped',
                              value: dropped,
                              warning: dropped > 0,
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CaptureMetric extends StatelessWidget {
  const _CaptureMetric({
    required this.label,
    required this.value,
    this.warning = false,
  });

  final String label;
  final int value;
  final bool warning;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$value',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: warning ? _red : Colors.white,
              fontSize: 14,
              height: 1,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white54,
              fontSize: 7.5,
              height: 1,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _HfCaptureSignalPainter extends CustomPainter {
  const _HfCaptureSignalPainter({
    required this.observed,
    required this.dropped,
    required this.running,
    required this.color,
  });

  final int observed;
  final int dropped;
  final bool running;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final centerY = size.height / 2;
    canvas.drawLine(
      Offset(0, centerY),
      Offset(size.width, centerY),
      Paint()
        ..color = Colors.white.withValues(alpha: 0.08)
        ..strokeWidth = 0.6,
    );
    final path = Path();
    final amplitude = size.height * (running ? 0.34 : 0.12);
    final phase = (observed % 17) * 0.23;
    const pointCount = 36;
    for (var index = 0; index < pointCount; index++) {
      final progress = index / (pointCount - 1);
      final wave =
          math.sin(progress * math.pi * 6 + phase) * 0.65 +
          math.sin(progress * math.pi * 14 + phase * 0.5) * 0.35;
      final point = Offset(size.width * progress, centerY - wave * amplitude);
      if (index == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color.withValues(alpha: 0.2)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = dropped > 0 ? _orange : color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(covariant _HfCaptureSignalPainter oldDelegate) =>
      observed != oldDelegate.observed ||
      dropped != oldDelegate.dropped ||
      running != oldDelegate.running ||
      color != oldDelegate.color;
}

class UndercoverCaptureDashboard extends StatefulWidget {
  const UndercoverCaptureDashboard({super.key});

  @override
  State<UndercoverCaptureDashboard> createState() =>
      _UndercoverCaptureDashboardState();
}

class _UndercoverCaptureDashboardState extends State<UndercoverCaptureDashboard>
    with AutomaticKeepAliveClientMixin {
  HfCaptureMode _mode = HfCaptureMode.emulation;
  ChameleonCommunicator? _communicator;
  List<_SlotSnapshot> _slots = const [];
  int? _selectedSlot;
  bool _slotsLoading = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _deviceOperations.addListener(_retrySlotLoad);
  }

  void _retrySlotLoad() {
    if (mounted &&
        _deviceOperations.owner == null &&
        _communicator != null &&
        _slots.isEmpty &&
        !_slotsLoading) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_loadSlots());
      });
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final communicator = context.watch<ChameleonGUIState>().communicator;
    if (identical(communicator, _communicator)) return;
    _communicator = communicator;
    _slots = const [];
    _selectedSlot = null;
    _slotsLoading = false;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && communicator != null) unawaited(_loadSlots());
    });
  }

  Future<void> _loadSlots() async {
    final communicator = _communicator;
    if (communicator == null || _slotsLoading) return;
    final lease = _beginDeviceOperation(context, 'Recorder setup', quiet: true);
    if (lease == null) return;
    setState(() => _slotsLoading = true);
    try {
      final active = await communicator.getActiveSlot();
      final slots = await _readHfSlots(communicator);
      if (!mounted || !identical(communicator, _communicator)) return;
      setState(() {
        _slots = slots;
        final activeSlot = slots[active];
        _selectedSlot = activeSlot.enabled && activeSlot.type != TagType.unknown
            ? active
            : null;
      });
      _deviceOperations.selectedSlot(active);
    } catch (error) {
      if (mounted && identical(communicator, _communicator)) {
        _showNotice(context, 'HF slots could not be loaded.', error: true);
      }
    } finally {
      lease.release();
      if (mounted && identical(communicator, _communicator)) {
        setState(() => _slotsLoading = false);
      }
    }
  }

  _SlotSnapshot? get _selectedEntry {
    final index = _selectedSlot;
    if (index == null || index >= _slots.length) return null;
    return _slots[index];
  }

  Future<void> _chooseSlot() async {
    if (_slots.isEmpty) await _loadSlots();
    if (!mounted) return;
    await _showUndercoverSheet<void>(
      context,
      title: 'Select capture slot',
      heightFactor: 0.64,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(14, 0, 14, 24),
        children: [
          for (final slot in _slots)
            ListTile(
              enabled: slot.enabled && slot.type != TagType.unknown,
              leading: CircleAvatar(
                backgroundColor: slot.index == _selectedSlot
                    ? _blue
                    : Colors.white12,
                child: _SlotGlyph(type: slot.type),
              ),
              title: Text(
                slot.name,
                style: const TextStyle(color: Colors.white),
              ),
              subtitle: Text(
                _tagLabel(slot.type),
                style: const TextStyle(color: Colors.white54),
              ),
              trailing: slot.index == _selectedSlot
                  ? const Icon(Icons.check_circle_rounded, color: _green)
                  : null,
              onTap: slot.enabled && slot.type != TagType.unknown
                  ? () {
                      setState(() => _selectedSlot = slot.index);
                      Navigator.pop(context);
                    }
                  : null,
            ),
        ],
      ),
    );
  }

  Future<void> _start(HfCaptureController controller) async {
    final appState = context.read<ChameleonGUIState>();
    final communicator = appState.communicator;
    if (communicator == null) return;
    final lease = _beginDeviceOperation(context, 'HF Recorder');
    if (lease == null) return;
    try {
      if (_mode == HfCaptureMode.emulation) {
        final slot = _selectedEntry;
        if (slot == null) {
          throw StateError('Select an active HF slot first');
        }
        await appState.runSlotOperation(
          () => communicator.activateSlot(slot.index),
        );
        appState.changesMade();
        _deviceOperations.selectedSlot(slot.index);
      }
      await controller.start(_mode);
    } catch (error) {
      if (mounted) {
        _showNotice(context, 'HF capture could not be started.', error: true);
      }
    } finally {
      lease.release();
    }
  }

  Future<void> _stop(HfCaptureController controller) async {
    final lease = _beginDeviceOperation(
      context,
      'Recorder stop',
      allowDuringCapture: true,
    );
    if (lease == null) return;
    try {
      await controller.stop();
    } catch (error) {
      if (mounted) {
        _showNotice(context, 'HF capture could not be stopped.', error: true);
      }
    } finally {
      lease.release();
    }
  }

  Future<void> _retryDrain(HfCaptureController controller) async {
    final lease = _beginDeviceOperation(
      context,
      'Recorder recovery',
      allowDuringCapture: true,
    );
    if (lease == null) return;
    try {
      await controller.retryDrain();
    } catch (error) {
      if (mounted) {
        _showNotice(
          context,
          'The previous HF capture session could not be recovered.',
          error: true,
        );
      }
    } finally {
      lease.release();
    }
  }

  Future<void> _probeReader(HfCaptureController controller) async {
    final lease = _beginDeviceOperation(
      context,
      'Reader probe',
      allowDuringCapture: true,
    );
    if (lease == null) return;
    try {
      await controller.probeReader();
    } catch (error) {
      if (mounted) {
        _showNotice(
          context,
          'The reader probe could not be captured.',
          error: true,
        );
      }
    } finally {
      lease.release();
    }
  }

  @override
  void dispose() {
    _deviceOperations.removeListener(_retrySlotLoad);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final controller = context.read<ChameleonGUIState>().hfCaptureController;
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final metadata = controller.metadata;
        final running = controller.isRunning;
        final effectiveMode = running ? metadata?.mode ?? _mode : _mode;
        final capacityBytes = metadata?.capacityBytes ?? 0;
        final bufferRatio = capacityBytes == 0
            ? 0.0
            : (metadata!.usedBytes / capacityBytes).clamp(0.0, 1.0).toDouble();
        return UndercoverSpringGrid(
          key: const Key('undercover-grid-journal'),
          placements: [
            UndercoverGridPlacement(
              row: 0,
              column: 0,
              rowSpan: 2,
              columnSpan: 4,
              child: _HfCaptureStatusWidget(
                key: const Key('undercover-capture-status'),
                mode: effectiveMode,
                slotName: _selectedEntry?.name ?? 'No slot selected',
                observed: metadata?.observedRecords ?? 0,
                stored: metadata?.storedRecords ?? 0,
                dropped: metadata?.droppedRecords ?? 0,
                bufferRatio: bufferRatio,
                running: running,
                busy: controller.isBusy,
                error: controller.error != null,
              ),
            ),
            for (var index = 0; index < HfCaptureMode.values.length; index++)
              UndercoverGridPlacement(
                row: 2,
                column: index,
                rowSpan: 1,
                columnSpan: 1,
                child: UndercoverGridTile(
                  key: Key(
                    'undercover-capture-mode-${HfCaptureMode.values[index].name}',
                  ),
                  label: switch (HfCaptureMode.values[index]) {
                    HfCaptureMode.emulation => 'Emulation',
                    HfCaptureMode.passive => 'Passive Sniff',
                    HfCaptureMode.reader => 'Reader Mode',
                  },
                  icon: switch (HfCaptureMode.values[index]) {
                    HfCaptureMode.emulation => Icons.repeat_rounded,
                    HfCaptureMode.passive => Icons.notifications_off_rounded,
                    HfCaptureMode.reader => Icons.touch_app_rounded,
                  },
                  color: _blue,
                  selected: effectiveMode == HfCaptureMode.values[index],
                  enabled: !running && !controller.isBusy,
                  onPressed: () =>
                      setState(() => _mode = HfCaptureMode.values[index]),
                ),
              ),
            UndercoverGridPlacement(
              row: 2,
              column: 3,
              rowSpan: 1,
              columnSpan: 1,
              child: UndercoverGridTile(
                key: const Key('undercover-capture-toggle'),
                label: running ? 'Stop Capture' : 'Start Capture',
                icon: running ? Icons.stop_rounded : Icons.play_arrow_rounded,
                color: running ? _red : _green,
                selected: running,
                enabled:
                    !controller.isBusy &&
                    controller.isConnected &&
                    controller.isSupported != false &&
                    (running || controller.canStart),
                onPressed: () => running
                    ? unawaited(_stop(controller))
                    : unawaited(_start(controller)),
              ),
            ),
            UndercoverGridPlacement(
              row: 5,
              column: 0,
              rowSpan: 1,
              columnSpan: 1,
              child: UndercoverGridTile(
                label: 'Select Slot',
                icon: Icons.swap_horiz_rounded,
                color: _blue,
                enabled: !running && !_slotsLoading,
                busy: _slotsLoading,
                onPressed: () => unawaited(_chooseSlot()),
              ),
            ),
            UndercoverGridPlacement(
              row: 5,
              column: 1,
              rowSpan: 1,
              columnSpan: 1,
              child: UndercoverGridTile(
                label: 'Probe Reader',
                icon: Icons.add_task_rounded,
                color: _green,
                enabled:
                    running &&
                    effectiveMode == HfCaptureMode.reader &&
                    !controller.isBusy,
                onPressed: () => unawaited(_probeReader(controller)),
              ),
            ),
            UndercoverGridPlacement(
              row: 5,
              column: 2,
              rowSpan: 1,
              columnSpan: 1,
              child: UndercoverGridTile(
                label: 'Recover Session',
                icon: Icons.restore_rounded,
                color: _orange,
                enabled:
                    !running &&
                    !controller.canStart &&
                    (controller.needsDrain || controller.needsFinalize) &&
                    controller.isConnected &&
                    !controller.isBusy,
                onPressed: () => unawaited(_retryDrain(controller)),
              ),
            ),
            UndercoverGridPlacement(
              row: 5,
              column: 3,
              rowSpan: 1,
              columnSpan: 1,
              child: UndercoverGridTile(
                label: 'Reload Slots',
                icon: Icons.sync_rounded,
                color: const Color(0xFF64D2FF),
                enabled: !running && !_slotsLoading && _communicator != null,
                onPressed: () => unawaited(_loadSlots()),
              ),
            ),
          ],
        );
      },
    );
  }
}

Uint8List? parseUndercoverEmulationUid(String value) {
  final normalized = value.replaceAll(RegExp(r'[\s:-]'), '');
  if (!const [8, 14, 20].contains(normalized.length) ||
      !RegExp(r'^[0-9a-fA-F]+$').hasMatch(normalized)) {
    return null;
  }
  return hexToBytes(normalized);
}

Uint8List generateUndercoverEmulationUid({int length = 4, int? seed}) {
  if (!const [4, 7, 10].contains(length)) {
    throw ArgumentError.value(length, 'length', 'must be 4, 7, or 10');
  }
  final random = math.Random(seed);
  final uid = Uint8List.fromList(
    List.generate(length, (_) => random.nextInt(256)),
  );
  if (uid[0] == 0x88) uid[0] = 0x08;
  if (uid.every((byte) => byte == 0)) uid[uid.length - 1] = 1;
  return uid;
}

enum _EmulationUidSource { slot, random, custom }

class _EmulationIdentityBackup {
  const _EmulationIdentityBackup({
    required this.communicator,
    required this.slot,
    required this.card,
    required this.randomUidMode,
    required this.useFirstBlockUid,
  });

  final ChameleonCommunicator communicator;
  final int slot;
  final CardData card;
  final bool? randomUidMode;
  final bool? useFirstBlockUid;
}

class _HfEmulationActivityWidget extends StatelessWidget {
  const _HfEmulationActivityWidget({
    super.key,
    required this.slot,
    required this.uidSource,
    required this.uid,
    required this.connected,
    required this.emulating,
    required this.busy,
    required this.recovering,
    required this.capturedNonces,
    required this.recoveredKeys,
    required this.recoveredSectors,
    required this.sectorCount,
    required this.error,
  });

  final _SlotSnapshot? slot;
  final _EmulationUidSource uidSource;
  final Uint8List? uid;
  final bool connected;
  final bool emulating;
  final bool busy;
  final bool recovering;
  final int capturedNonces;
  final int recoveredKeys;
  final int recoveredSectors;
  final int sectorCount;
  final String? error;

  @override
  Widget build(BuildContext context) {
    const shape = ContinuousRectangleBorder(
      borderRadius: BorderRadius.all(Radius.circular(42)),
      side: BorderSide(color: Color(0x3DFFFFFF), width: 0.8),
    );
    final slotReady = slot?.enabled == true && slot?.type != TagType.unknown;
    final uidSourceLabel = switch (uidSource) {
      _EmulationUidSource.slot => 'SLOT UID',
      _EmulationUidSource.random => 'RANDOM UID',
      _EmulationUidSource.custom => 'CUSTOM UID',
    };
    final uidValue = uid == null ? 'Stored identity' : bytesToHexSpace(uid!);
    final status = error != null
        ? 'ERROR'
        : busy
        ? 'SYNCING'
        : recovering
        ? 'RECOVERING'
        : emulating
        ? 'CAPTURING'
        : slotReady
        ? 'READY'
        : 'NO CARD';
    final statusColor = error != null
        ? _red
        : emulating
        ? const Color(0xFFFF375F)
        : slotReady
        ? _green
        : Colors.white54;

    return Semantics(
      container: true,
      label:
          'HF emulation, $status, ${slot?.name ?? 'no slot'}, $uidSourceLabel, $uidValue, $capturedNonces nonces, $recoveredKeys keys, $recoveredSectors of $sectorCount sectors',
      child: DecoratedBox(
        decoration: const ShapeDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF121216), Color(0xFF09090C), Color(0xFF18131C)],
          ),
          shape: shape,
          shadows: [
            BoxShadow(
              color: Color(0x36000000),
              blurRadius: 18,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: ClipPath(
          clipper: const ShapeBorderClipper(shape: shape),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxHeight < 150;
              final ringSize = compact ? 78.0 : 94.0;
              Widget legend(Color color, String label, String value) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: color.withValues(alpha: 0.42),
                            blurRadius: 5,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white54,
                              fontSize: 7,
                              height: 1,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.5,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            value,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 9,
                              height: 1,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );

              return Stack(
                fit: StackFit.expand,
                children: [
                  const Positioned(
                    top: 1,
                    left: 58,
                    right: 58,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Colors.transparent,
                            Color(0x7AFFFFFF),
                            Colors.transparent,
                          ],
                        ),
                      ),
                      child: SizedBox(height: 1),
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.all(compact ? 10 : 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Expanded(
                              child: Text(
                                'HF EMULATION',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  height: 1,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.8,
                                ),
                              ),
                            ),
                            DecoratedBox(
                              decoration: BoxDecoration(
                                color: statusColor.withValues(alpha: 0.16),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: statusColor.withValues(alpha: 0.5),
                                ),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                child: Text(
                                  status,
                                  style: TextStyle(
                                    color: statusColor,
                                    fontSize: 7,
                                    height: 1,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 5),
                        Expanded(
                          child: Row(
                            children: [
                              SizedBox.square(
                                dimension: ringSize,
                                child: CustomPaint(
                                  key: const Key(
                                    'undercover-emulation-activity-rings',
                                  ),
                                  painter: _HfEmulationActivityPainter(
                                    deviceProgress: connected ? 0.96 : 0.08,
                                    cardProgress: sectorCount == 0
                                        ? (slotReady ? 0.82 : 0.08)
                                        : (recoveredKeys / (sectorCount * 2))
                                              .clamp(0.04, 1.0),
                                    emulationProgress: sectorCount == 0
                                        ? (emulating ? 1 : 0.18)
                                        : (recoveredSectors / sectorCount)
                                              .clamp(0.04, 1.0),
                                  ),
                                ),
                              ),
                              SizedBox(width: compact ? 9 : 14),
                              Expanded(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    legend(
                                      const Color(0xFFFF375F),
                                      uidSourceLabel,
                                      uidValue,
                                    ),
                                    legend(
                                      const Color(0xFF30D158),
                                      'NONCES',
                                      '$capturedNonces captured',
                                    ),
                                    legend(
                                      const Color(0xFF64D2FF),
                                      'KEYS',
                                      '$recoveredKeys · $recoveredSectors/$sectorCount sectors',
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _HfEmulationActivityPainter extends CustomPainter {
  const _HfEmulationActivityPainter({
    required this.deviceProgress,
    required this.cardProgress,
    required this.emulationProgress,
  });

  final double deviceProgress;
  final double cardProgress;
  final double emulationProgress;

  @override
  void paint(Canvas canvas, Size size) {
    final shortest = size.shortestSide;
    final strokeWidth = shortest * 0.115;
    final spacing = strokeWidth * 0.42;
    final center = size.center(Offset.zero);
    final progress = [deviceProgress, cardProgress, emulationProgress];
    const colors = [Color(0xFFFF375F), Color(0xFF30D158), Color(0xFF64D2FF)];

    for (var index = 0; index < progress.length; index++) {
      final radius =
          shortest / 2 - strokeWidth / 2 - index * (strokeWidth + spacing);
      final rect = Rect.fromCircle(center: center, radius: radius);
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..color = colors[index].withValues(alpha: 0.15)
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeWidth,
      );
      final sweep = math.pi * 2 * progress[index].clamp(0.0, 1.0);
      canvas.drawArc(
        rect,
        -math.pi / 2,
        sweep,
        false,
        Paint()
          ..color = colors[index]
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeWidth
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _HfEmulationActivityPainter oldDelegate) =>
      deviceProgress != oldDelegate.deviceProgress ||
      cardProgress != oldDelegate.cardProgress ||
      emulationProgress != oldDelegate.emulationProgress;
}

class _HfEmulationSlotSelector extends StatelessWidget {
  const _HfEmulationSlotSelector({
    super.key,
    required this.slot,
    required this.onPrevious,
    required this.onNext,
  });

  final _SlotSnapshot? slot;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    const shape = ContinuousRectangleBorder(
      borderRadius: BorderRadius.all(Radius.circular(30)),
      side: BorderSide(color: Color(0x2EFFFFFF), width: 0.8),
    );
    Widget arrow({
      required Key key,
      required IconData icon,
      required String tooltip,
      required VoidCallback? onPressed,
    }) => IconButton(
      key: key,
      tooltip: tooltip,
      onPressed: onPressed,
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints.tightFor(width: 40, height: 40),
      style: IconButton.styleFrom(
        backgroundColor: Colors.white.withValues(alpha: 0.08),
        disabledBackgroundColor: Colors.white.withValues(alpha: 0.03),
      ),
      icon: Icon(
        icon,
        color: onPressed == null ? Colors.white24 : Colors.white,
        size: 22,
      ),
    );

    return Semantics(
      container: true,
      label: slot == null
          ? 'No HF slot selected'
          : '${slot!.name}, slot ${slot!.index + 1} of 8',
      child: DecoratedBox(
        decoration: const ShapeDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xE62A2D43), Color(0xE61A1C2C)],
          ),
          shape: shape,
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          child: Row(
            children: [
              arrow(
                key: const Key('undercover-emulation-slot-previous'),
                icon: Icons.chevron_left_rounded,
                tooltip: 'Previous HF slot',
                onPressed: onPrevious,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      slot?.name ?? 'No HF card selected',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        height: 1,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      slot == null
                          ? 'Connect and reload slots'
                          : 'Slot ${slot!.index + 1} of 8 · ${_tagLabel(slot!.type)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 8,
                        height: 1,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              arrow(
                key: const Key('undercover-emulation-slot-next'),
                icon: Icons.chevron_right_rounded,
                tooltip: 'Next HF slot',
                onPressed: onNext,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class UndercoverEmulationDashboard extends StatefulWidget {
  const UndercoverEmulationDashboard({super.key});

  @override
  State<UndercoverEmulationDashboard> createState() =>
      _UndercoverEmulationDashboardState();
}

class _UndercoverEmulationDashboardState
    extends State<UndercoverEmulationDashboard>
    with AutomaticKeepAliveClientMixin {
  ChameleonGUIState? _appState;
  ChameleonCommunicator? _communicator;
  List<_SlotSnapshot> _slots = const [];
  int _selectedSlot = 0;
  bool _busy = false;
  bool _emulating = false;
  String? _error;
  _DeviceOperationLease? _emulationLease;
  _EmulationUidSource _uidSource = _EmulationUidSource.slot;
  Uint8List? _uidOverride;
  _EmulationIdentityBackup? _identityBackup;
  Mf1EmulationKeyRecoveryController? _keyRecovery;
  int _operationGeneration = 0;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _deviceOperations.addListener(_syncSharedSlot);
  }

  void _syncSharedSlot() {
    final slot = _deviceOperations.activeSlot;
    if (mounted && slot != null && slot != _selectedSlot) {
      setState(() {
        _selectedSlot = slot;
        if (_uidSource == _EmulationUidSource.random &&
            slot < _slots.length &&
            _supportsUidOverride(_slots[slot].type)) {
          _uidOverride = generateUndercoverEmulationUid(
            length: isMifareUltralight(_slots[slot].type) ? 7 : 4,
          );
        }
      });
    }
    if (mounted &&
        _deviceOperations.owner == null &&
        _communicator != null &&
        _slots.isEmpty &&
        !_busy) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_refresh());
      });
    }
  }

  bool _isCurrent(int generation, ChameleonCommunicator communicator) =>
      mounted &&
      generation == _operationGeneration &&
      identical(communicator, _communicator);

  void _recoveryChanged() {
    if (mounted) setState(() {});
  }

  bool _supportsUidOverride(TagType type) =>
      isMifareClassic(type) || isMifareUltralight(type);

  bool _isUidCompatible(TagType type, Uint8List? uid) =>
      uid != null &&
      _supportsUidOverride(type) &&
      (!isMifareUltralight(type) || uid.length == 7);

  Future<void> _applyUidOverride(
    ChameleonCommunicator communicator,
    _SlotSnapshot slot,
  ) async {
    final uid = _uidOverride;
    final overrideUid = _uidSource != _EmulationUidSource.slot && uid != null;
    final classic = isMifareClassic(slot.type);
    if (!overrideUid && !classic) return;
    if (overrideUid && !_isUidCompatible(slot.type, uid)) {
      throw StateError('This HF card type does not support temporary UIDs');
    }

    final original = await communicator.mf1GetAntiCollData();
    bool? randomUidMode;
    bool? useFirstBlockUid;
    if (classic) {
      final randomUidSupported =
          communicator.supportsCommandSync(
                ChameleonCommand.mf1GetRandomUidMode,
              ) ==
              true &&
          communicator.supportsCommandSync(
                ChameleonCommand.mf1SetRandomUidMode,
              ) ==
              true;
      if (randomUidSupported) {
        randomUidMode = await communicator.getMf1RandomUidMode();
      }
      final firstBlockUidSupported =
          communicator.supportsCommandSync(
                ChameleonCommand.mf1GetFirstBlockColl,
              ) !=
              false &&
          communicator.supportsCommandSync(
                ChameleonCommand.mf1SetFirstBlockColl,
              ) !=
              false;
      if (overrideUid && firstBlockUidSupported) {
        useFirstBlockUid = await communicator.isMf1UseFirstBlockColl();
      }
    }
    if (!overrideUid && randomUidMode != true) return;
    _identityBackup = _EmulationIdentityBackup(
      communicator: communicator,
      slot: slot.index,
      card: CardData(
        uid: Uint8List.fromList(original.uid),
        sak: original.sak,
        atqa: Uint8List.fromList(original.atqa),
        ats: Uint8List.fromList(original.ats),
      ),
      randomUidMode: randomUidMode,
      useFirstBlockUid: useFirstBlockUid,
    );

    if (randomUidMode == true) {
      await communicator.setMf1RandomUidMode(false);
    }
    if (overrideUid && useFirstBlockUid == true) {
      await communicator.setMf1UseFirstBlockColl(false);
    }
    if (overrideUid) {
      await communicator.setMf1AntiCollision(
        CardData(
          uid: Uint8List.fromList(uid),
          sak: original.sak,
          atqa: Uint8List.fromList(original.atqa),
          ats: Uint8List.fromList(original.ats),
        ),
      );
    }
  }

  Future<bool> _restoreUidOverride(
    ChameleonCommunicator communicator, {
    _EmulationIdentityBackup? backupOverride,
    ChameleonGUIState? operationState,
    int attempts = 1,
  }) async {
    final backup = backupOverride ?? _identityBackup;
    if (backup == null) return true;
    if (!identical(backup.communicator, communicator)) return false;
    if (attempts < 1) throw ArgumentError.value(attempts, 'attempts');
    Future<void> restore() async {
      await communicator.activateSlot(backup.slot);
      await communicator.setMf1AntiCollision(backup.card);
      if (backup.useFirstBlockUid != null) {
        await communicator.setMf1UseFirstBlockColl(backup.useFirstBlockUid!);
      }
      if (backup.randomUidMode != null) {
        await communicator.setMf1RandomUidMode(backup.randomUidMode!);
      }
    }

    for (var attempt = 0; attempt < attempts; attempt++) {
      try {
        if (operationState != null) {
          if (!identical(operationState.communicator, communicator)) {
            return false;
          }
          await operationState.runSlotOperation(restore);
        } else {
          await restore();
        }
        if (identical(_identityBackup, backup)) _identityBackup = null;
        return true;
      } catch (_) {
        if (attempt + 1 < attempts) {
          await Future<void>.delayed(const Duration(milliseconds: 80));
        }
      }
    }
    return false;
  }

  Future<bool> _restoreEmulationState(
    ChameleonCommunicator communicator,
    _DeviceOperationLease? lease, {
    _EmulationIdentityBackup? identityBackup,
    ChameleonGUIState? operationState,
    Mf1EmulationKeyRecoveryController? keyRecoveryOverride,
    int restoreAttempts = 1,
  }) async {
    final identityMatches =
        identityBackup == null ||
        identical(identityBackup.communicator, communicator);
    var restored = identityMatches;
    try {
      await communicator.setReaderDeviceMode(true);
    } catch (_) {
      restored = false;
    } finally {
      final keyRecovery = keyRecoveryOverride ?? _keyRecovery;
      if (keyRecovery?.owns(communicator) == true) {
        try {
          await keyRecovery!.stop(communicator: communicator);
        } catch (_) {
          restored = false;
        }
      }
      if (identityMatches) {
        if (!await _restoreUidOverride(
          communicator,
          backupOverride: identityBackup,
          operationState: operationState,
          attempts: restoreAttempts,
        )) {
          restored = false;
        }
      }
      lease?.release();
    }
    return restored;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final appState = context.watch<ChameleonGUIState>();
    _appState = appState;
    _keyRecovery ??= Mf1EmulationKeyRecoveryController(
      appState.sharedPreferencesProvider,
      onKeysSaved: () => _appState?.changesMade(),
    )..addListener(_recoveryChanged);
    final communicator = appState.communicator;
    if (identical(communicator, _communicator)) return;
    _operationGeneration++;
    final previous = _communicator;
    final previousLease = _emulationLease;
    final previousIdentityBackup = _identityBackup;
    final wasEmulating = _emulating;
    final previousRecoveryActive =
        previous != null && _keyRecovery?.owns(previous) == true;
    if (previous != null &&
        (_emulating ||
            previousIdentityBackup != null ||
            previousRecoveryActive)) {
      unawaited(
        _restoreEmulationState(
          previous,
          previousLease,
          identityBackup: previousIdentityBackup,
          restoreAttempts: 3,
        ).then((restored) {
          if (!mounted) return;
          if (_identityBackup != null &&
              !identical(_identityBackup, previousIdentityBackup)) {
            return;
          }
          final restorationStillVisible =
              _error == 'Restoring the original slot UID.' ||
              _error == 'Stopping the previous HF emulation session.' ||
              _error == 'The original slot UID is waiting to be restored.';
          if (!restored && _keyRecovery?.owns(previous) == true) {
            _keyRecovery!.abandon(previous);
          }
          setState(() {
            if (identical(_identityBackup, previousIdentityBackup)) {
              _identityBackup = null;
            }
            if (!restorationStillVisible) return;
            if (restored) {
              _error = null;
            } else {
              _error = previousIdentityBackup == null
                  ? 'The previous HF emulation session could not be stopped.'
                  : 'The original device disconnected before its UID could be restored.';
            }
          });
        }),
      );
    } else if (!_busy) {
      previousLease?.release();
    }
    _emulationLease = null;
    _communicator = communicator;
    _slots = const [];
    _emulating = false;
    _busy = false;
    _uidSource = _EmulationUidSource.slot;
    _uidOverride = null;
    _error = previousIdentityBackup != null
        ? 'Restoring the original slot UID.'
        : wasEmulating
        ? 'Stopping the previous HF emulation session.'
        : null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_refresh());
    });
  }

  Future<void> _refresh() async {
    final communicator = _communicator;
    if (communicator == null || _busy) return;
    final lease = _beginDeviceOperation(
      context,
      'HF emulation refresh',
      quiet: true,
    );
    if (lease == null) return;
    final generation = ++_operationGeneration;
    setState(() {
      _busy = true;
      _error = _identityBackup == null
          ? null
          : 'The original slot UID is waiting to be restored.';
    });
    try {
      final active = await communicator.getActiveSlot();
      if (!_isCurrent(generation, communicator)) return;
      final slots = await _readHfSlots(communicator);
      if (!_isCurrent(generation, communicator)) return;
      final readerMode = await communicator.isReaderDeviceMode();
      if (!_isCurrent(generation, communicator)) return;
      setState(() {
        _slots = slots;
        _selectedSlot = active;
        _emulating = !readerMode;
      });
      _deviceOperations.selectedSlot(active);
      if (!readerMode) _emulationLease = lease;
    } catch (error) {
      if (!mounted) return;
      if (_isCurrent(generation, communicator)) {
        setState(() => _error = 'HF emulation slots could not be loaded.');
      }
    } finally {
      if (!identical(_emulationLease, lease)) lease.release();
      if (_isCurrent(generation, communicator)) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _start() async {
    final appState = context.read<ChameleonGUIState>();
    final communicator = appState.communicator;
    if (communicator == null || _busy || _slots.isEmpty) return;
    if (_identityBackup != null) {
      _showNotice(
        context,
        'The original slot UID must be restored before starting again.',
        error: true,
      );
      return;
    }
    final slot = _slots[_selectedSlot];
    if (!slot.enabled || slot.type == TagType.unknown) {
      _showNotice(
        context,
        'Select an available HF card slot first.',
        error: true,
      );
      return;
    }
    if (_uidSource != _EmulationUidSource.slot &&
        !_isUidCompatible(slot.type, _uidOverride)) {
      _showNotice(
        context,
        'Select a compatible MIFARE slot and a valid temporary UID.',
        error: true,
      );
      return;
    }
    final lease = _beginDeviceOperation(context, 'HF card emulation');
    if (lease == null) return;
    final generation = ++_operationGeneration;
    _emulationLease = lease;
    setState(() {
      _busy = true;
      _error = null;
    });
    var keepLease = false;
    var modeMayBeEmulating = false;
    var recoveryMayBeActive = false;
    try {
      await appState.runSlotOperation(() async {
        await communicator.activateSlot(slot.index);
        await _applyUidOverride(communicator, slot);
      });
      if (!_isCurrent(generation, communicator)) return;
      if (isMifareClassic(slot.type)) {
        await _keyRecovery!.start(
          communicator: communicator,
          slot: slot.index,
          tagType: slot.type,
          runSlotOperation: (operation) => appState.runSlotOperation(operation),
        );
        recoveryMayBeActive = true;
      } else {
        _keyRecovery!.reset();
      }
      if (!_isCurrent(generation, communicator)) return;
      modeMayBeEmulating = true;
      await communicator.setReaderDeviceMode(false);
      if (!_isCurrent(generation, communicator)) return;
      keepLease = true;
      appState.changesMade();
      _deviceOperations.selectedSlot(slot.index);
      setState(() => _emulating = true);
    } catch (error) {
      if (!mounted) return;
      if (_isCurrent(generation, communicator)) {
        setState(() => _error = 'HF card emulation could not be started.');
        _showNotice(
          context,
          'HF card emulation could not be started.',
          error: true,
        );
      }
    } finally {
      if (!keepLease) {
        if (modeMayBeEmulating ||
            recoveryMayBeActive ||
            _identityBackup != null) {
          await _restoreEmulationState(
            communicator,
            lease,
            operationState: _isCurrent(generation, communicator)
                ? _appState
                : null,
          );
        } else {
          lease.release();
        }
        if (identical(_emulationLease, lease)) _emulationLease = null;
      }
      if (_isCurrent(generation, communicator)) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _stop() async {
    final communicator = _communicator;
    if (communicator == null || _busy) return;
    final generation = ++_operationGeneration;
    final lease = _emulationLease;
    setState(() => _busy = true);
    var stopped = false;
    try {
      await communicator.setReaderDeviceMode(true);
      stopped = true;
      var recoveryRestored = true;
      if (_keyRecovery?.owns(communicator) == true) {
        try {
          await _keyRecovery!.stop(communicator: communicator);
        } catch (_) {
          recoveryRestored = false;
        }
      }
      final identityRestored = await _restoreUidOverride(
        communicator,
        operationState: _appState,
      );
      final restored = recoveryRestored && identityRestored;
      if (!mounted) return;
      if (_isCurrent(generation, communicator)) {
        setState(() {
          _emulating = false;
          _error = restored
              ? null
              : 'Emulation stopped, but its temporary recovery state could not be fully restored.';
        });
        if (!restored) {
          _showNotice(
            context,
            'Emulation stopped, but its temporary recovery state could not be fully restored.',
            error: true,
          );
        }
      }
    } catch (error) {
      if (!mounted) return;
      if (_isCurrent(generation, communicator)) {
        setState(() => _error = 'HF card emulation could not be stopped.');
        _showNotice(
          context,
          'HF card emulation could not be stopped.',
          error: true,
        );
      }
    } finally {
      if (stopped) {
        lease?.release();
        if (identical(_emulationLease, lease)) _emulationLease = null;
      } else if (!_isCurrent(generation, communicator) && lease != null) {
        await _restoreEmulationState(communicator, lease);
      }
      if (_isCurrent(generation, communicator)) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _retryEmulationRestore() async {
    final communicator = _communicator;
    final backup = _identityBackup;
    final keyRecovery = _keyRecovery;
    final canRetryRecovery =
        communicator != null &&
        keyRecovery?.cleanupPending == true &&
        keyRecovery?.owns(communicator) == true;
    final canRetryIdentity =
        communicator != null &&
        backup != null &&
        identical(backup.communicator, communicator);
    if (communicator == null ||
        _busy ||
        (!canRetryRecovery && !canRetryIdentity)) {
      return;
    }
    final lease = _beginDeviceOperation(context, 'HF emulation restore');
    if (lease == null) return;
    final generation = ++_operationGeneration;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await communicator.setReaderDeviceMode(true);
      var restored = true;
      if (canRetryRecovery) {
        try {
          await keyRecovery!.stop(communicator: communicator);
        } catch (_) {
          restored = false;
        }
      }
      if (canRetryIdentity &&
          !await _restoreUidOverride(communicator, operationState: _appState)) {
        restored = false;
      }
      if (!restored) throw StateError('Emulation restoration failed');
      if (_isCurrent(generation, communicator)) {
        setState(() {
          _emulating = false;
          _error = null;
        });
      }
    } catch (_) {
      if (!mounted) return;
      if (_isCurrent(generation, communicator)) {
        setState(
          () => _error = 'The temporary emulation state could not be restored.',
        );
        _showNotice(
          context,
          'The temporary emulation state could not be restored.',
          error: true,
        );
      }
    } finally {
      lease.release();
      if (_isCurrent(generation, communicator)) {
        setState(() => _busy = false);
      }
    }
  }

  void _useSlotUid() {
    setState(() {
      _uidSource = _EmulationUidSource.slot;
      _uidOverride = null;
    });
  }

  void _useRandomUid() {
    final slot = _slots.isEmpty ? null : _slots[_selectedSlot.clamp(0, 7)];
    if (slot == null || !_supportsUidOverride(slot.type)) return;
    setState(() {
      _uidSource = _EmulationUidSource.random;
      _uidOverride = generateUndercoverEmulationUid(
        length: isMifareUltralight(slot.type) ? 7 : 4,
      );
    });
  }

  Future<void> _chooseCustomUid() async {
    final slot = _slots.isEmpty ? null : _slots[_selectedSlot.clamp(0, 7)];
    final requiresSevenBytes = slot != null && isMifareUltralight(slot.type);
    var input = _uidSource == _EmulationUidSource.custom && _uidOverride != null
        ? bytesToHexSpace(_uidOverride!)
        : '';
    var invalid = false;
    Uint8List? parseInput() {
      final parsed = parseUndercoverEmulationUid(input);
      if (parsed == null || (requiresSevenBytes && parsed.length != 7)) {
        return null;
      }
      return parsed;
    }

    final uid = await _showUndercoverSheet<Uint8List>(
      context,
      title: 'Custom HF UID',
      heightFactor: 0.48,
      child: StatefulBuilder(
        builder: (sheetContext, setSheetState) => ListView(
          padding: EdgeInsets.fromLTRB(
            20,
            4,
            20,
            20 + MediaQuery.viewInsetsOf(sheetContext).bottom,
          ),
          children: [
            const Text(
              'Enter a 4, 7, or 10-byte UID. Spaces, colons, and hyphens are optional. The original slot UID is restored when emulation stops.',
              style: TextStyle(color: Colors.white60, height: 1.35),
            ),
            const SizedBox(height: 16),
            TextFormField(
              key: const Key('undercover-emulation-custom-uid-field'),
              initialValue: input,
              autofocus: true,
              textCapitalization: TextCapitalization.characters,
              keyboardType: TextInputType.text,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9a-fA-F\s:-]')),
                LengthLimitingTextInputFormatter(29),
              ],
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.1,
              ),
              decoration: InputDecoration(
                labelText: 'UID',
                hintText: '04 A1 B2 C3',
                errorText: invalid
                    ? requiresSevenBytes
                          ? 'This Ultralight/NTAG slot requires a 7-byte UID.'
                          : 'Use exactly 8, 14, or 20 hexadecimal characters.'
                    : null,
                filled: true,
                fillColor: Colors.white.withValues(alpha: 0.08),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              onChanged: (value) {
                input = value;
                if (invalid) setSheetState(() => invalid = false);
              },
              onFieldSubmitted: (_) {
                final parsed = parseInput();
                if (parsed == null) {
                  setSheetState(() => invalid = true);
                } else {
                  Navigator.pop(sheetContext, parsed);
                }
              },
            ),
            const SizedBox(height: 14),
            FilledButton.icon(
              key: const Key('undercover-emulation-custom-uid-apply'),
              onPressed: () {
                final parsed = parseInput();
                if (parsed == null) {
                  setSheetState(() => invalid = true);
                } else {
                  Navigator.pop(sheetContext, parsed);
                }
              },
              icon: const Icon(Icons.check_rounded),
              label: const Text('Use Temporary UID'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || uid == null) return;
    setState(() {
      _uidSource = _EmulationUidSource.custom;
      _uidOverride = uid;
    });
  }

  Future<void> _showRecoveredKeys() async {
    final results = _keyRecovery?.recoveredResults ?? const [];
    if (results.isEmpty) {
      _showNotice(context, 'No MIFARE Classic keys have been recovered yet.');
      return;
    }
    await _showUndercoverSheet<void>(
      context,
      title: 'Recovered Classic Keys',
      heightFactor: 0.72,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(14, 0, 14, 24),
        itemCount: results.length,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final result = results[index];
          final key = bytesToHex(result.key!).toUpperCase();
          final uid = result.target.uid
              .toRadixString(16)
              .padLeft(8, '0')
              .toUpperCase();
          return ListTile(
            leading: CircleAvatar(
              backgroundColor: result.verifiedByReader
                  ? _green.withValues(alpha: 0.18)
                  : _orange.withValues(alpha: 0.18),
              child: Icon(
                result.verifiedByReader
                    ? Icons.verified_rounded
                    : Icons.vpn_key_rounded,
                color: result.verifiedByReader ? _green : _orange,
              ),
            ),
            title: Text(
              key,
              style: const TextStyle(
                color: Colors.white,
                fontFamily: 'RobotoMono',
                fontWeight: FontWeight.w700,
              ),
            ),
            subtitle: Text(
              'UID $uid · Sector ${result.target.sector} · Key ${result.target.keyType} · ${result.verifiedByReader ? 'verified' : 'recovered'}',
              style: const TextStyle(color: Colors.white60),
            ),
            onTap: () async {
              await Clipboard.setData(ClipboardData(text: key));
              if (context.mounted) {
                _showNotice(context, 'Recovered key copied.');
              }
            },
          );
        },
      ),
    );
  }

  @override
  void dispose() {
    _operationGeneration++;
    _deviceOperations.removeListener(_syncSharedSlot);
    final communicator = _communicator;
    final lease = _emulationLease;
    final identityBackup = _identityBackup;
    final keyRecovery = _keyRecovery;
    _identityBackup = null;
    _keyRecovery = null;
    keyRecovery?.removeListener(_recoveryChanged);
    final backupBelongsToCurrent =
        identityBackup == null ||
        identical(identityBackup.communicator, communicator);
    if (communicator != null &&
        backupBelongsToCurrent &&
        (_emulating ||
            identityBackup != null ||
            keyRecovery?.owns(communicator) == true)) {
      unawaited(() async {
        try {
          await _restoreEmulationState(
            communicator,
            lease,
            identityBackup: identityBackup,
            operationState: _appState,
            keyRecoveryOverride: keyRecovery,
            restoreAttempts: 3,
          );
        } finally {
          keyRecovery?.dispose();
        }
      }());
    } else {
      if (!_busy) lease?.release();
      keyRecovery?.dispose();
    }
    _emulationLease = null;
    super.dispose();
  }

  void _moveSelectedSlot(int delta) {
    if (_slots.isEmpty) return;
    for (var offset = 1; offset <= _slots.length; offset++) {
      final index =
          (_selectedSlot + delta * offset + _slots.length) % _slots.length;
      final candidate = _slots[index];
      if (candidate.enabled && candidate.type != TagType.unknown) {
        setState(() {
          _selectedSlot = index;
          if (_uidSource == _EmulationUidSource.random &&
              _supportsUidOverride(candidate.type)) {
            _uidOverride = generateUndercoverEmulationUid(
              length: isMifareUltralight(candidate.type) ? 7 : 4,
            );
          }
        });
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final slot = _slots.isEmpty ? null : _slots[_selectedSlot.clamp(0, 7)];
    final keyRecovery = _keyRecovery!;
    final hasAvailableSlots = _slots.any(
      (entry) => entry.enabled && entry.type != TagType.unknown,
    );
    final slotReady = slot?.enabled == true && slot?.type != TagType.unknown;
    final classicRecovery = slot != null && isMifareClassic(slot.type);
    final recoveryOwnedByCurrent =
        _communicator != null && keyRecovery.owns(_communicator!);
    final canRetryRecovery =
        keyRecovery.cleanupPending && recoveryOwnedByCurrent;
    final recoverySessionPending =
        keyRecovery.isStopping ||
        keyRecovery.cleanupPending ||
        (keyRecovery.active && !recoveryOwnedByCurrent);
    final slotSupportsUidOverride =
        slot != null && _supportsUidOverride(slot.type);
    final identityPending = _identityBackup != null;
    final canRetryIdentity =
        identityPending &&
        identical(_identityBackup!.communicator, _communicator);
    final identityReady =
        !identityPending &&
        (_uidSource == _EmulationUidSource.slot ||
            (slot != null && _isUidCompatible(slot.type, _uidOverride)));
    return UndercoverSpringGrid(
      key: const Key('undercover-grid-routines'),
      placements: [
        UndercoverGridPlacement(
          row: 0,
          column: 0,
          rowSpan: 2,
          columnSpan: 4,
          child: _HfEmulationActivityWidget(
            key: const Key('undercover-emulation-activity'),
            slot: slot,
            uidSource: _uidSource,
            uid: _uidOverride,
            connected: _communicator != null,
            emulating: _emulating,
            busy: _busy,
            recovering: keyRecovery.isRecovering,
            capturedNonces: keyRecovery.capturedNonceCount,
            recoveredKeys: keyRecovery.recoveredKeyCount,
            recoveredSectors: keyRecovery.recoveredSectorCount,
            sectorCount: keyRecovery.sectorCount,
            error: _error ?? keyRecovery.error,
          ),
        ),
        UndercoverGridPlacement(
          row: 2,
          column: 0,
          rowSpan: 1,
          columnSpan: 4,
          child: _HfEmulationSlotSelector(
            key: const Key('undercover-emulation-slot-selector'),
            slot: slot,
            onPrevious:
                !_busy &&
                    !_emulating &&
                    !identityPending &&
                    !recoverySessionPending &&
                    hasAvailableSlots
                ? () => _moveSelectedSlot(-1)
                : null,
            onNext:
                !_busy &&
                    !_emulating &&
                    !identityPending &&
                    !recoverySessionPending &&
                    hasAvailableSlots
                ? () => _moveSelectedSlot(1)
                : null,
          ),
        ),
        UndercoverGridPlacement(
          row: 3,
          column: 0,
          rowSpan: 1,
          columnSpan: 1,
          child: UndercoverGridTile(
            key: const Key('undercover-emulation-slot-uid'),
            label: 'Slot UID',
            icon: Icons.credit_card_rounded,
            color: const Color(0xFF5E5CE6),
            selected: _uidSource == _EmulationUidSource.slot,
            enabled:
                !_busy &&
                !_emulating &&
                !identityPending &&
                !recoverySessionPending &&
                slotReady,
            onPressed: _useSlotUid,
          ),
        ),
        UndercoverGridPlacement(
          row: 3,
          column: 1,
          rowSpan: 1,
          columnSpan: 1,
          child: UndercoverGridTile(
            key: const Key('undercover-emulation-random-uid'),
            label: 'Random UID',
            value: _uidSource == _EmulationUidSource.random
                ? '${_uidOverride?.length ?? 0}B'
                : null,
            icon: Icons.casino_rounded,
            color: const Color(0xFFFF375F),
            selected: _uidSource == _EmulationUidSource.random,
            enabled:
                !_busy &&
                !_emulating &&
                !identityPending &&
                !recoverySessionPending &&
                slotSupportsUidOverride,
            onPressed: _useRandomUid,
          ),
        ),
        UndercoverGridPlacement(
          row: 3,
          column: 2,
          rowSpan: 1,
          columnSpan: 1,
          child: UndercoverGridTile(
            key: const Key('undercover-emulation-custom-uid'),
            label: 'Custom UID',
            value: _uidSource == _EmulationUidSource.custom
                ? '${_uidOverride?.length ?? 0}B'
                : null,
            icon: Icons.edit_rounded,
            color: _green,
            selected: _uidSource == _EmulationUidSource.custom,
            enabled:
                !_busy &&
                !_emulating &&
                !identityPending &&
                !recoverySessionPending &&
                slotSupportsUidOverride,
            onPressed: () => unawaited(_chooseCustomUid()),
          ),
        ),
        UndercoverGridPlacement(
          row: 3,
          column: 3,
          rowSpan: 1,
          columnSpan: 1,
          child: UndercoverGridTile(
            key: const Key('undercover-routine-toggle'),
            label: _emulating
                ? classicRecovery
                      ? 'Stop Recovery'
                      : 'Stop Emulation'
                : classicRecovery
                ? 'Start Recovery'
                : 'Start Emulation',
            icon: _emulating ? Icons.stop_rounded : Icons.play_arrow_rounded,
            color: _emulating ? _red : _green,
            selected: _emulating,
            enabled:
                !_busy &&
                !recoverySessionPending &&
                (_emulating || (slotReady && identityReady)),
            onPressed: () =>
                _emulating ? unawaited(_stop()) : unawaited(_start()),
          ),
        ),
        UndercoverGridPlacement(
          row: 4,
          column: 0,
          rowSpan: 1,
          columnSpan: 1,
          child: UndercoverGridTile(
            key: const Key('undercover-emulation-nonces'),
            label: 'Captured Nonces',
            value: '${keyRecovery.capturedNonceCount}',
            icon: Icons.data_object_rounded,
            color: _orange,
            selected: keyRecovery.active,
            enabled: classicRecovery,
          ),
        ),
        UndercoverGridPlacement(
          row: 4,
          column: 1,
          rowSpan: 1,
          columnSpan: 1,
          child: UndercoverGridTile(
            key: const Key('undercover-emulation-recovered-keys'),
            label: 'Recovered Keys',
            value: '${keyRecovery.recoveredKeyCount}',
            icon: Icons.vpn_key_rounded,
            color: _green,
            selected: keyRecovery.recoveredKeyCount > 0,
            enabled: keyRecovery.recoveredKeyCount > 0,
            onPressed: () => unawaited(_showRecoveredKeys()),
          ),
        ),
        UndercoverGridPlacement(
          row: 4,
          column: 2,
          rowSpan: 1,
          columnSpan: 1,
          child: UndercoverGridTile(
            key: const Key('undercover-emulation-recovered-sectors'),
            label: 'Recovered Sectors',
            value:
                '${keyRecovery.recoveredSectorCount}/${keyRecovery.sectorCount}',
            icon: Icons.grid_view_rounded,
            color: const Color(0xFF64D2FF),
            selected: keyRecovery.recoveredSectorCount > 0,
            enabled: classicRecovery,
          ),
        ),
        UndercoverGridPlacement(
          row: 4,
          column: 3,
          rowSpan: 1,
          columnSpan: 1,
          child: UndercoverGridTile(
            key: const Key('undercover-emulation-reload-or-restore'),
            label: canRetryIdentity
                ? 'Restore UID'
                : canRetryRecovery
                ? 'Restore Session'
                : identityPending
                ? 'Restoring UID'
                : keyRecovery.cleanupPending
                ? 'Restoring Session'
                : 'Reload Slots',
            icon: identityPending || keyRecovery.cleanupPending
                ? Icons.settings_backup_restore_rounded
                : Icons.refresh_rounded,
            color: identityPending || keyRecovery.cleanupPending
                ? _orange
                : _blue,
            enabled:
                !_busy &&
                !_emulating &&
                _communicator != null &&
                (identityPending || keyRecovery.cleanupPending
                    ? canRetryIdentity || canRetryRecovery
                    : !recoverySessionPending),
            busy: _busy,
            onPressed: () => identityPending || keyRecovery.cleanupPending
                ? unawaited(_retryEmulationRestore())
                : unawaited(_refresh()),
          ),
        ),
      ],
    );
  }
}

class _ActivityReviewWidget extends StatelessWidget {
  const _ActivityReviewWidget({
    super.key,
    required this.capture,
    required this.connected,
    required this.reviewing,
    required this.durationSeconds,
    required this.error,
  });

  final HfSniffCapture? capture;
  final bool connected;
  final bool reviewing;
  final int durationSeconds;
  final String? error;

  @override
  Widget build(BuildContext context) {
    const shape = ContinuousRectangleBorder(
      borderRadius: BorderRadius.all(Radius.circular(42)),
      side: BorderSide(color: Color(0x2EFFFFFF), width: 0.8),
    );
    final summary = capture?.summary;
    final outgoing = summary?.readerFrameCount ?? 0;
    final incoming = summary?.cardFrameCount ?? 0;
    final updates = capture?.nonces.length ?? 0;
    final total = summary?.frameCount ?? 0;
    final status = error != null
        ? 'ERROR'
        : reviewing
        ? 'CAPTURING'
        : capture != null
        ? 'CAPTURED'
        : connected
        ? 'READY'
        : 'OFFLINE';
    final statusColor = error != null
        ? _red
        : reviewing
        ? _orange
        : capture != null
        ? _green
        : connected
        ? const Color(0xFF64D2FF)
        : Colors.white60;

    Widget metric(Color color, String label, String value) => Row(
      children: [
        Container(
          width: 6,
          height: 22,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(5),
            boxShadow: [
              BoxShadow(color: color.withValues(alpha: 0.34), blurRadius: 6),
            ],
          ),
        ),
        const SizedBox(width: 7),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white60,
                  fontSize: 8.5,
                  height: 1,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.6,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  height: 1,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ],
    );

    return Semantics(
      container: true,
      label:
          'HF 14A sniff, $status, $outgoing outgoing packets, $incoming incoming packets, $updates nonces',
      child: DecoratedBox(
        decoration: const ShapeDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF0F172A), Color(0xFF020617), Color(0xFF111827)],
          ),
          shape: shape,
          shadows: [
            BoxShadow(
              color: Color(0x38000000),
              blurRadius: 20,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: ClipPath(
          clipper: const ShapeBorderClipper(shape: shape),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxHeight < 150;
              final veryCompact = constraints.maxHeight < 135;
              if (veryCompact) {
                return Padding(
                  padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Expanded(
                            child: Text(
                              'HF 14A SNIFF',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                height: 1,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.8,
                              ),
                            ),
                          ),
                          Text(
                            status,
                            style: TextStyle(
                              color: statusColor,
                              fontSize: 8,
                              height: 1,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 5),
                      Expanded(
                        child: Row(
                          children: [
                            Expanded(
                              child: RepaintBoundary(
                                child: CustomPaint(
                                  key: const Key('undercover-activity-pulse'),
                                  painter: _ActivityReviewPainter(
                                    outgoing: outgoing,
                                    incoming: incoming,
                                    total: total,
                                    active: reviewing,
                                  ),
                                  child: const SizedBox.expand(),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceEvenly,
                                children: [
                                  metric(
                                    const Color(0xFF64D2FF),
                                    'OUTGOING',
                                    '$outgoing',
                                  ),
                                  metric(_green, 'INCOMING', '$incoming'),
                                  metric(_orange, 'NONCES', '$updates'),
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
              return Padding(
                padding: EdgeInsets.fromLTRB(
                  compact ? 11 : 14,
                  compact ? 10 : 12,
                  compact ? 11 : 14,
                  compact ? 9 : 11,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'HF 14A SNIFF',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              height: 1,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.9,
                            ),
                          ),
                        ),
                        DecoratedBox(
                          decoration: BoxDecoration(
                            color: statusColor.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: statusColor.withValues(alpha: 0.48),
                            ),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 3,
                            ),
                            child: Text(
                              status,
                              style: TextStyle(
                                color: statusColor,
                                fontSize: 8,
                                height: 1,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: compact ? 6 : 9),
                    Expanded(
                      child: Row(
                        children: [
                          Expanded(
                            flex: 7,
                            child: RepaintBoundary(
                              child: CustomPaint(
                                key: const Key('undercover-activity-pulse'),
                                painter: _ActivityReviewPainter(
                                  outgoing: outgoing,
                                  incoming: incoming,
                                  total: total,
                                  active: reviewing,
                                ),
                                child: const SizedBox.expand(),
                              ),
                            ),
                          ),
                          SizedBox(width: compact ? 9 : 14),
                          Expanded(
                            flex: 4,
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                              children: [
                                metric(
                                  const Color(0xFF64D2FF),
                                  'OUTGOING',
                                  '$outgoing',
                                ),
                                metric(_green, 'INCOMING', '$incoming'),
                                metric(_orange, 'NONCES', '$updates'),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      error ??
                          (reviewing
                              ? '$durationSeconds-second sniff in progress'
                              : total == 0
                              ? 'Capture HF 14A traffic between a reader and card'
                              : '$total packets captured'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: error == null ? Colors.white60 : _red,
                        fontSize: 9,
                        height: 1,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _ActivityReviewPainter extends CustomPainter {
  const _ActivityReviewPainter({
    required this.outgoing,
    required this.incoming,
    required this.total,
    required this.active,
  });

  final int outgoing;
  final int incoming;
  final int total;
  final bool active;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final centerY = size.height * 0.52;
    final guide = Paint()
      ..color = Colors.white.withValues(alpha: 0.08)
      ..strokeWidth = 1;
    for (final fraction in [0.2, 0.5, 0.8]) {
      canvas.drawLine(
        Offset(0, size.height * fraction),
        Offset(size.width, size.height * fraction),
        guide,
      );
    }

    const barCount = 22;
    final gap = size.width / barCount;
    final barWidth = math.max(2.0, gap * 0.38).toDouble();
    final activity = active
        ? 0.82
        : total == 0
        ? 0.12
        : math.min(1.0, total / 48).toDouble();
    final directionBias = total == 0 ? 0.5 : outgoing / math.max(1, total);
    for (var index = 0; index < barCount; index++) {
      final phase = index / (barCount - 1);
      final wave =
          (math.sin(phase * math.pi * 3 + directionBias * math.pi) + 1) / 2;
      final envelope = 0.38 + math.sin(phase * math.pi) * 0.62;
      final barHeight = math
          .max(3.0, size.height * activity * envelope * (0.34 + wave * 0.5))
          .toDouble();
      final color = Color.lerp(
        const Color(0xFF64D2FF),
        _green,
        (phase + incoming / math.max(1, total)) / 2,
      )!;
      final rect = RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(gap * (index + 0.5), centerY),
          width: barWidth,
          height: barHeight,
        ),
        Radius.circular(barWidth),
      );
      canvas.drawRRect(
        rect,
        Paint()
          ..color = color.withValues(alpha: active || total > 0 ? 0.9 : 0.28),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ActivityReviewPainter oldDelegate) =>
      outgoing != oldDelegate.outgoing ||
      incoming != oldDelegate.incoming ||
      total != oldDelegate.total ||
      active != oldDelegate.active;
}

class UndercoverSniffDashboard extends StatefulWidget {
  const UndercoverSniffDashboard({super.key});

  @override
  State<UndercoverSniffDashboard> createState() =>
      _UndercoverSniffDashboardState();
}

class _UndercoverSniffDashboardState extends State<UndercoverSniffDashboard>
    with AutomaticKeepAliveClientMixin {
  int _durationSeconds = 5;
  bool _capturing = false;
  HfSniffCapture? _capture;
  String? _error;
  ChameleonCommunicator? _communicator;
  bool? _capabilitySupported;
  int _operationGeneration = 0;
  _DeviceOperationLease? _sniffLease;

  @override
  bool get wantKeepAlive => true;

  bool _isCurrent(int generation, ChameleonCommunicator communicator) =>
      mounted &&
      generation == _operationGeneration &&
      identical(communicator, _communicator);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final communicator = context.watch<ChameleonGUIState>().communicator;
    if (identical(communicator, _communicator)) return;
    _operationGeneration++;
    _communicator = communicator;
    _capabilitySupported = communicator?.supportsCommandSync(
      ChameleonCommand.hf14aSniff,
    );
    _capturing = false;
    _capture = null;
    _error = null;
  }

  Future<void> _captureFrames() async {
    final communicator = _communicator;
    if (communicator == null || _capturing) return;
    final lease = _beginDeviceOperation(context, 'HF 14A sniff');
    if (lease == null) return;
    _sniffLease = lease;
    final generation = ++_operationGeneration;
    setState(() {
      _capturing = true;
      _capture = null;
      _error = null;
    });
    bool? previousReaderMode;
    try {
      previousReaderMode = await communicator.isReaderDeviceMode();
      if (!_isCurrent(generation, communicator)) return;
      if (previousReaderMode) {
        await communicator.setReaderDeviceMode(false);
        if (!_isCurrent(generation, communicator)) return;
      }
      final raw = await communicator.hf14aSniff(
        timeoutMs: _durationSeconds * 1000,
      );
      if (!_isCurrent(generation, communicator)) return;
      setState(() {
        _capture = raw.isEmpty ? null : HfSniffCapture.fromRawBytes(raw);
      });
      if (raw.isEmpty && mounted) {
        _showNotice(context, 'No HF 14A packets were captured.');
      }
    } catch (error) {
      if (!mounted) return;
      if (_isCurrent(generation, communicator)) {
        setState(() => _error = 'HF 14A sniffing could not be completed.');
        _showNotice(
          context,
          'HF 14A sniffing could not be completed.',
          error: true,
        );
      }
    } finally {
      if (previousReaderMode != null) {
        try {
          await communicator.setReaderDeviceMode(previousReaderMode);
        } catch (_) {}
      }
      lease.release();
      if (identical(_sniffLease, lease)) _sniffLease = null;
      if (_isCurrent(generation, communicator)) {
        setState(() => _capturing = false);
      }
    }
  }

  @override
  void dispose() {
    _operationGeneration++;
    super.dispose();
  }

  Future<void> _copyCapture() async {
    final capture = _capture;
    if (capture == null) return;
    await Clipboard.setData(
      ClipboardData(text: bytesToHex(capture.rawBytes).toUpperCase()),
    );
    if (mounted) _showNotice(context, 'Captured frames copied.');
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final capture = _capture;
    final summary = capture?.summary;
    return UndercoverSpringGrid(
      key: const Key('undercover-grid-activity'),
      placements: [
        UndercoverGridPlacement(
          row: 0,
          column: 0,
          rowSpan: 2,
          columnSpan: 4,
          child: _ActivityReviewWidget(
            key: const Key('undercover-activity-review'),
            capture: capture,
            connected: _communicator != null,
            reviewing: _capturing,
            durationSeconds: _durationSeconds,
            error: _error,
          ),
        ),
        UndercoverGridPlacement(
          row: 2,
          column: 0,
          rowSpan: 1,
          columnSpan: 1,
          child: UndercoverGridTile(
            key: const Key('undercover-sniff-duration'),
            label: 'Duration',
            value: '${_durationSeconds}s',
            icon: Icons.timer_outlined,
            color: _blue,
            enabled: !_capturing,
            onPressed: () => setState(() {
              _durationSeconds = switch (_durationSeconds) {
                5 => 10,
                10 => 30,
                _ => 5,
              };
            }),
          ),
        ),
        UndercoverGridPlacement(
          row: 2,
          column: 1,
          rowSpan: 1,
          columnSpan: 1,
          child: UndercoverGridTile(
            key: const Key('undercover-activity-run'),
            label: _capturing ? 'Capturing' : 'Start Sniff',
            icon: _capturing
                ? Icons.hourglass_top_rounded
                : Icons.play_arrow_rounded,
            color: _capturing ? _red : _green,
            enabled:
                !_capturing &&
                _communicator != null &&
                _capabilitySupported != false,
            busy: _capturing,
            onPressed: () => unawaited(_captureFrames()),
          ),
        ),
        UndercoverGridPlacement(
          row: 2,
          column: 2,
          rowSpan: 1,
          columnSpan: 2,
          child: UndercoverGridTile(
            key: const Key('undercover-sniff-counter'),
            label: 'Packets / Nonces',
            value:
                '${summary?.frameCount ?? 0} / ${capture?.nonces.length ?? 0}',
            details: capture == null
                ? 'Nothing captured'
                : 'Tap to copy frames',
            icon: Icons.content_copy_rounded,
            color: const Color(0xFF5E5CE6),
            enabled: capture != null && !_capturing && _error == null,
            onPressed: () => unawaited(_copyCapture()),
          ),
        ),
      ],
    );
  }
}

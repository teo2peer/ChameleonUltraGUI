import 'dart:async';
import 'dart:convert';
import 'dart:ui';

import 'package:chameleonultragui/bridge/chameleon.dart';
import 'package:chameleonultragui/helpers/definitions.dart';
import 'package:chameleonultragui/helpers/general.dart';
import 'package:chameleonultragui/helpers/hf_capture.dart';
import 'package:chameleonultragui/helpers/hf_capture_controller.dart';
import 'package:chameleonultragui/helpers/hf_sniff.dart';
import 'package:chameleonultragui/helpers/mifare_classic/autopwn_v2.dart';
import 'package:chameleonultragui/helpers/mifare_classic/general.dart';
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

const _listNames = [
  'Today',
  'Home',
  'Errands',
  'Work',
  'Ideas',
  'Health',
  'Reading',
  'Archive',
];

String _listName(int index) => _listNames[index.clamp(0, 7)];

String _tagLabel(TagType type) =>
    type == TagType.unknown ? 'Empty list' : 'Personal list';

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
  const _GlassCard({
    required this.child,
    this.padding = const EdgeInsets.all(14),
    this.color,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color ?? const Color(0xD92A2D43),
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
      child: Padding(padding: padding, child: child),
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

  final Set<String> _selectedDictionaryIds = {};
  List<Dictionary> _dictionaries = const [];
  CardData? _hfCard;
  TagType _hfTagType = TagType.unknown;
  String? _lfIdentity;
  AutopwnV2Progress? _progress;
  AutopwnV2Result? _result;
  MifareClassicAutopwnV2Port? _port;
  _DeviceOperationLease? _recoveryLease;
  bool _readingLf = false;
  bool _readingHf = false;
  bool _running = false;
  String? _error;
  bool _loadedDictionaries = false;
  ChameleonCommunicator? _communicator;
  int _operationGeneration = 0;

  @override
  bool get wantKeepAlive => true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final appState = context.watch<ChameleonGUIState>();
    final communicator = appState.communicator;
    if (!identical(communicator, _communicator)) {
      _operationGeneration++;
      _port?.cancel();
      _communicator = communicator;
      _readingLf = false;
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

  Future<void> _readLf() async {
    final communicator = _communicator;
    if (communicator == null || _readingLf || _running) return;
    final lease = _beginDeviceOperation(context, 'LF Market');
    if (lease == null) return;
    final generation = ++_operationGeneration;
    setState(() {
      _readingLf = true;
      _lfIdentity = null;
      _error = null;
    });
    try {
      final readerMode = await communicator.isReaderDeviceMode();
      if (!_isCurrent(generation, communicator)) return;
      if (!readerMode) {
        await communicator.setReaderDeviceMode(true);
        if (!_isCurrent(generation, communicator)) return;
      }
      final readers = <(ChameleonCommand, Future<Object?> Function())>[
        (ChameleonCommand.scanEM410Xtag, () async => communicator.readEM410X()),
        (
          ChameleonCommand.scanHIDProxTag,
          () async => communicator.readHIDProx(),
        ),
        (ChameleonCommand.scanVikingTag, () async => communicator.readViking()),
        (ChameleonCommand.scanPacTag, () async => communicator.readPac()),
        (ChameleonCommand.scanIoProxTag, () async => communicator.readIoProx()),
      ];
      Object? card;
      Object? lastError;
      for (final reader in readers) {
        if (!_isCurrent(generation, communicator)) return;
        if (communicator.supportsCommandSync(reader.$1) == false) continue;
        try {
          card = await reader.$2();
          if (!_isCurrent(generation, communicator)) return;
          if (card != null) break;
        } catch (error) {
          lastError = error;
        }
      }
      if (card == null && lastError != null) throw lastError;
      if (!_isCurrent(generation, communicator)) return;
      setState(() => _lfIdentity = card?.toString());
      if (card == null && mounted) {
        _showNotice(context, 'No new item was found.');
      }
    } catch (error) {
      if (!mounted) return;
      if (_isCurrent(generation, communicator)) {
        setState(() {
          _lfIdentity = null;
          _error = 'The quick review could not be completed.';
        });
        _showNotice(
          context,
          'The quick review could not be completed.',
          error: true,
        );
      }
    } finally {
      lease.release();
      if (_isCurrent(generation, communicator)) {
        setState(() => _readingLf = false);
      }
    }
  }

  Future<void> _readHf() async {
    final communicator = _communicator;
    if (communicator == null || _readingHf || _running) return;
    final lease = _beginDeviceOperation(context, 'HF Market');
    if (lease == null) return;
    final generation = ++_operationGeneration;
    setState(() {
      _readingHf = true;
      _hfCard = null;
      _hfTagType = TagType.unknown;
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
      });
      if (card == null && mounted) {
        _showNotice(context, 'No new item was found.');
      }
    } catch (error) {
      if (!mounted) return;
      if (_isCurrent(generation, communicator)) {
        setState(() {
          _hfCard = null;
          _hfTagType = TagType.unknown;
          _error = 'The full review could not be completed.';
        });
        _showNotice(
          context,
          'The full review could not be completed.',
          error: true,
        );
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
      _showNotice(context, 'This item cannot be saved yet.');
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
        name: 'Saved item ${DateTime.now().toIso8601String().substring(0, 16)}',
        tag: _hfTagType,
      ),
    );
    await appState.sharedPreferencesProvider.setCards(cards);
    if (mounted) _showNotice(context, 'Reference saved.');
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
    final lease = _beginDeviceOperation(context, 'Sector Weather');
    if (lease == null) return;
    final generation = ++_operationGeneration;
    _recoveryLease = lease;
    setState(() {
      _running = true;
      _result = null;
      _progress = null;
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
            setState(() => _progress = progress);
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
        setState(() => _result = result);
      }
    } catch (error) {
      if (!mounted) return;
      if (_isCurrent(generation, communicator)) {
        setState(() => _error = 'The review could not be completed.');
        _showNotice(context, 'The review could not be completed.', error: true);
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
      title: 'Review sources',
      child: StatefulBuilder(
        builder: (sheetContext, setSheetState) => ListView(
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 24),
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(8, 0, 8, 12),
              child: Text(
                'Long press the review card to return here. Basic items are always included.',
                style: TextStyle(color: Colors.white60),
              ),
            ),
            if (_dictionaries.isEmpty)
              const _GlassCard(
                child: Text(
                  'No additional sources are available.',
                  style: TextStyle(color: Colors.white70),
                ),
              ),
            for (final dictionary in _dictionaries)
              CheckboxListTile(
                value: _selectedDictionaryIds.contains(dictionary.id),
                activeColor: _blue,
                checkColor: Colors.white,
                title: Text(
                  'Source ${_dictionaries.indexOf(dictionary) + 1}',
                  style: const TextStyle(color: Colors.white),
                ),
                subtitle: Text(
                  '${dictionary.keys.length} items',
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

  Future<void> _showKeys() async {
    final keys = _result?.verifiedKeys ?? const <AutopwnV2VerifiedKey>[];
    await _showUndercoverSheet<void>(
      context,
      title: 'Completed items',
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(14, 0, 14, 24),
        itemCount: keys.isEmpty ? 1 : keys.length,
        itemBuilder: (context, index) {
          if (keys.isEmpty) {
            return const _GlassCard(
              child: Text(
                'No completed items yet.',
                style: TextStyle(color: Colors.white70),
              ),
            );
          }
          final key = keys[index];
          return ListTile(
            leading: const Icon(Icons.check_circle_rounded, color: _green),
            title: Text(
              'Area ${key.sector + 1} · Item ${key.keyType == 0 ? 'A' : 'B'}',
              style: const TextStyle(color: Colors.white),
            ),
            subtitle: const Text(
              'Completed',
              style: TextStyle(color: Colors.white70),
            ),
          );
        },
      ),
    );
  }

  Future<void> _showSectors() async {
    final result = _result;
    final sectorCount = (result?.totalKeySlots ?? 32) ~/ 2;
    final verified = <int, int>{};
    for (final key in result?.verifiedKeys ?? const <AutopwnV2VerifiedKey>[]) {
      verified[key.sector] = (verified[key.sector] ?? 0) + 1;
    }
    await _showUndercoverSheet<void>(
      context,
      title: 'Progress by area',
      child: GridView.builder(
        padding: const EdgeInsets.fromLTRB(14, 0, 14, 24),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 4,
          childAspectRatio: 1,
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
        ),
        itemCount: sectorCount,
        itemBuilder: (context, index) {
          final found = verified[index] ?? 0;
          return _GlassCard(
            padding: const EdgeInsets.all(9),
            color:
                (found == 2
                        ? _green
                        : found == 1
                        ? _orange
                        : _red)
                    .withValues(alpha: 0.22),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  found == 2
                      ? Icons.check_circle_rounded
                      : found == 1
                      ? Icons.pending_rounded
                      : Icons.circle_outlined,
                  color: Colors.white,
                ),
                const SizedBox(height: 5),
                Text(
                  '${index + 1}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text('$found/2', style: const TextStyle(color: Colors.white60)),
              ],
            ),
          );
        },
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
    if (mounted) _showNotice(context, 'Private summary copied.');
  }

  Future<void> _copyDump() async {
    final result = _result;
    if (result == null) return;
    final payload = const JsonEncoder.withIndent('  ').convert({
      'blocks': result.blocks.map((block) => block.toJson()).toList(),
      'complete': result.complete,
    });
    await Clipboard.setData(ClipboardData(text: payload));
    if (mounted) _showNotice(context, 'Private draft copied.');
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final card = _hfCard;
    final progress = _progress;
    final result = _result;
    final verified = result?.verifiedKeySlots ?? progress?.verifiedSlots ?? 0;
    final total = result?.totalKeySlots ?? progress?.totalSlots ?? 32;
    final ratio = total == 0 ? 0.0 : (verified / total).clamp(0.0, 1.0);
    return UndercoverSpringGrid(
      key: const Key('undercover-grid-progress'),
      placements: [
        UndercoverGridPlacement(
          row: 0,
          column: 0,
          rowSpan: 2,
          columnSpan: 4,
          child: UndercoverGridTile(
            label: 'Weekly progress',
            value: '$verified / $total',
            details:
                '${(ratio * 100).round()}% complete. ${result?.complete == true ? 'Every area is up to date.' : '${total - verified} items need attention.'}',
            icon: result?.complete == true
                ? Icons.task_alt_rounded
                : Icons.pie_chart_rounded,
            color: result?.complete == true ? _green : const Color(0xFF0B5CAD),
            selected: result?.complete == true,
            busy: _running,
          ),
        ),
        UndercoverGridPlacement(
          row: 2,
          column: 0,
          rowSpan: 1,
          columnSpan: 1,
          child: UndercoverGridTile(
            key: const Key('undercover-recovery-lf'),
            label: 'Quick review',
            value: _lfIdentity == null ? null : 'Updated',
            icon: Icons.bolt_rounded,
            color: _orange,
            enabled: !_readingLf && !_running && _communicator != null,
            busy: _readingLf,
            onPressed: () => unawaited(_readLf()),
          ),
        ),
        UndercoverGridPlacement(
          row: 2,
          column: 1,
          rowSpan: 1,
          columnSpan: 1,
          child: UndercoverGridTile(
            key: const Key('undercover-recovery-hf'),
            label: 'Full review',
            value: card == null ? null : 'Updated',
            icon: Icons.fact_check_rounded,
            color: _blue,
            enabled: !_readingHf && !_running && _communicator != null,
            busy: _readingHf,
            onPressed: () => unawaited(_readHf()),
          ),
        ),
        UndercoverGridPlacement(
          row: 2,
          column: 2,
          rowSpan: 1,
          columnSpan: 1,
          child: UndercoverGridTile(
            key: const Key('undercover-autopwn-weather'),
            label: _running ? 'Cancel review' : 'Review now',
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
          column: 3,
          rowSpan: 1,
          columnSpan: 1,
          child: UndercoverGridTile(
            label: 'Sources',
            value: '${_selectedDictionaryIds.length}',
            icon: Icons.library_books_rounded,
            color: const Color(0xFF5E5CE6),
            enabled: !_running,
            onPressed: () => unawaited(_chooseDictionaries()),
          ),
        ),
        UndercoverGridPlacement(
          row: 3,
          column: 0,
          rowSpan: 1,
          columnSpan: 1,
          child: UndercoverGridTile(
            label: 'Save reference',
            icon: Icons.bookmark_add_rounded,
            color: _blue,
            enabled: card != null && _hfTagType != TagType.unknown && !_running,
            onPressed: () => unawaited(_saveUuid()),
          ),
        ),
        UndercoverGridPlacement(
          row: 3,
          column: 1,
          rowSpan: 1,
          columnSpan: 1,
          child: UndercoverGridTile(
            label: 'Completed',
            value: '${result?.verifiedKeys.length ?? 0}',
            icon: Icons.check_circle_rounded,
            color: _green,
            enabled: result != null,
            onPressed: () => unawaited(_showKeys()),
          ),
        ),
        UndercoverGridPlacement(
          row: 3,
          column: 2,
          rowSpan: 1,
          columnSpan: 1,
          child: UndercoverGridTile(
            label: 'Areas',
            icon: Icons.grid_view_rounded,
            color: _orange,
            enabled: result != null,
            onPressed: () => unawaited(_showSectors()),
          ),
        ),
        UndercoverGridPlacement(
          row: 3,
          column: 3,
          rowSpan: 1,
          columnSpan: 1,
          child: UndercoverGridTile(
            label: result?.complete == true ? 'Complete' : 'Pending',
            icon: result?.complete == true
                ? Icons.done_all_rounded
                : Icons.schedule_rounded,
            color: result?.complete == true ? _green : _orange,
            selected: result?.complete == true,
          ),
        ),
        UndercoverGridPlacement(
          row: 4,
          column: 0,
          rowSpan: 1,
          columnSpan: 1,
          child: UndercoverGridTile(
            label: 'Copy summary',
            icon: Icons.content_copy_rounded,
            color: const Color(0xFF64D2FF),
            enabled: result?.verifiedKeys.isNotEmpty == true,
            onPressed: () => unawaited(_copyKeys()),
          ),
        ),
        UndercoverGridPlacement(
          row: 4,
          column: 1,
          rowSpan: 1,
          columnSpan: 1,
          child: UndercoverGridTile(
            label: 'Copy draft',
            icon: Icons.note_alt_rounded,
            color: const Color(0xFF5E5CE6),
            enabled: result?.blocks.isNotEmpty == true,
            onPressed: () => unawaited(_copyDump()),
          ),
        ),
        UndercoverGridPlacement(
          row: 4,
          column: 2,
          rowSpan: 1,
          columnSpan: 2,
          child: UndercoverGridTile(
            label: 'Reference',
            value: card == null ? 'Not selected' : 'Ready',
            details: card == null
                ? 'Run a full review first'
                : 'Current reference is ready',
            icon: Icons.bookmark_rounded,
            color: card == null ? const Color(0xFF3A3A56) : _green,
            selected: card != null,
          ),
        ),
        UndercoverGridPlacement(
          row: 5,
          column: 0,
          rowSpan: 1,
          columnSpan: 4,
          child: UndercoverGridTile(
            label: _error == null ? 'Review status' : 'Review failed',
            value: _running
                ? 'Running'
                : result == null
                ? 'Not started'
                : result.complete
                ? 'Complete'
                : 'Partial',
            details:
                _error ??
                (_running
                    ? 'The selected sources are being checked.'
                    : 'Use Review now to update weekly progress.'),
            icon: _error == null
                ? Icons.insights_rounded
                : Icons.error_outline_rounded,
            color: _error == null ? const Color(0xFF3A3A56) : _red,
          ),
        ),
      ],
    );
  }
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
        _showNotice(context, 'Lists could not be updated.', error: true);
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
      title: 'Choose active list',
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
                _listName(slot.index),
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
          throw StateError('Choose an active list first');
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
        _showNotice(context, 'The journal could not be started.', error: true);
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
        _showNotice(context, 'The journal could not be paused.', error: true);
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
          'The previous journal session could not be restored.',
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
        _showNotice(context, 'A marker could not be added.', error: true);
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
        final records = controller.recentRecords.reversed.take(12).toList();
        return UndercoverSpringGrid(
          key: const Key('undercover-grid-journal'),
          placements: [
            UndercoverGridPlacement(
              row: 0,
              column: 0,
              rowSpan: 1,
              columnSpan: 4,
              child: UndercoverGridTile(
                label: running ? 'Journal active' : 'Daily journal',
                value: running
                    ? '${metadata?.observedRecords ?? 0} entries'
                    : 'Paused',
                details: controller.error == null
                    ? 'Mode: ${switch (effectiveMode) {
                        HfCaptureMode.emulation => 'Routine',
                        HfCaptureMode.passive => 'Silent',
                        HfCaptureMode.reader => 'Manual',
                      }}'
                    : 'The journal could not be updated.',
                icon: running
                    ? Icons.edit_note_rounded
                    : Icons.menu_book_rounded,
                color: controller.error == null
                    ? (running ? _red : _blue)
                    : _red,
                selected: running,
                busy: controller.isBusy,
              ),
            ),
            for (var index = 0; index < HfCaptureMode.values.length; index++)
              UndercoverGridPlacement(
                row: 1,
                column: index,
                rowSpan: 1,
                columnSpan: 1,
                child: UndercoverGridTile(
                  key: Key(
                    'undercover-capture-mode-${HfCaptureMode.values[index].name}',
                  ),
                  label: switch (HfCaptureMode.values[index]) {
                    HfCaptureMode.emulation => 'Routine',
                    HfCaptureMode.passive => 'Silent',
                    HfCaptureMode.reader => 'Manual',
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
              row: 1,
              column: 3,
              rowSpan: 1,
              columnSpan: 1,
              child: UndercoverGridTile(
                key: const Key('undercover-capture-toggle'),
                label: running ? 'Pause' : 'Start',
                icon: running ? Icons.pause_rounded : Icons.play_arrow_rounded,
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
              row: 2,
              column: 0,
              rowSpan: 1,
              columnSpan: 1,
              child: UndercoverGridTile(
                label: _selectedEntry == null
                    ? 'No list'
                    : _listName(_selectedEntry!.index),
                icon: Icons.list_alt_rounded,
                color: const Color(0xFF5E5CE6),
                selected: _selectedEntry != null,
              ),
            ),
            UndercoverGridPlacement(
              row: 2,
              column: 1,
              rowSpan: 1,
              columnSpan: 1,
              child: UndercoverGridTile(
                label: 'Entries',
                value: '${metadata?.observedRecords ?? 0}',
                icon: Icons.format_list_numbered_rounded,
                color: _blue,
              ),
            ),
            UndercoverGridPlacement(
              row: 2,
              column: 2,
              rowSpan: 1,
              columnSpan: 1,
              child: UndercoverGridTile(
                label: 'Saved',
                value: '${metadata?.storedRecords ?? 0}',
                icon: Icons.save_rounded,
                color: _green,
              ),
            ),
            UndercoverGridPlacement(
              row: 2,
              column: 3,
              rowSpan: 1,
              columnSpan: 1,
              child: UndercoverGridTile(
                label: 'Skipped',
                value: '${metadata?.droppedRecords ?? 0}',
                icon: Icons.skip_next_rounded,
                color: _red,
              ),
            ),
            UndercoverGridPlacement(
              row: 3,
              column: 0,
              rowSpan: 2,
              columnSpan: 4,
              child: UndercoverGridTile(
                label: 'Recent activity',
                value: '${records.length} entries',
                details: records.isEmpty
                    ? 'No recent activity yet.'
                    : records
                          .take(3)
                          .map(
                            (record) =>
                                'Entry ${record.sequence + 1}: ${record.hasRfError ? 'needs review' : 'saved'}',
                          )
                          .join(' · '),
                icon: Icons.history_rounded,
                color: const Color(0xFF3A3A56),
              ),
            ),
            UndercoverGridPlacement(
              row: 5,
              column: 0,
              rowSpan: 1,
              columnSpan: 1,
              child: UndercoverGridTile(
                label: 'Choose list',
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
                label: 'Add marker',
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
                label: 'Restore',
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
                label: 'Sync lists',
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

class UndercoverEmulationDashboard extends StatefulWidget {
  const UndercoverEmulationDashboard({super.key});

  @override
  State<UndercoverEmulationDashboard> createState() =>
      _UndercoverEmulationDashboardState();
}

class _UndercoverEmulationDashboardState
    extends State<UndercoverEmulationDashboard>
    with AutomaticKeepAliveClientMixin {
  ChameleonCommunicator? _communicator;
  List<_SlotSnapshot> _slots = const [];
  int _selectedSlot = 0;
  bool _busy = false;
  bool _emulating = false;
  String? _error;
  _DeviceOperationLease? _emulationLease;
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
      setState(() => _selectedSlot = slot);
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

  Future<void> _restoreReaderMode(
    ChameleonCommunicator communicator,
    _DeviceOperationLease lease,
  ) async {
    try {
      await communicator.setReaderDeviceMode(true);
    } catch (_) {
      // The connection may already be gone; the lease must still be released.
    } finally {
      lease.release();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final communicator = context.watch<ChameleonGUIState>().communicator;
    if (identical(communicator, _communicator)) return;
    _operationGeneration++;
    final previous = _communicator;
    final previousLease = _emulationLease;
    if (_emulating && previous != null && previousLease != null) {
      unawaited(_restoreReaderMode(previous, previousLease));
    } else if (!_busy) {
      previousLease?.release();
    }
    _emulationLease = null;
    _communicator = communicator;
    _slots = const [];
    _emulating = false;
    _busy = false;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_refresh());
    });
  }

  Future<void> _refresh() async {
    final communicator = _communicator;
    if (communicator == null || _busy) return;
    final lease = _beginDeviceOperation(
      context,
      'Contactless Studio',
      quiet: true,
    );
    if (lease == null) return;
    final generation = ++_operationGeneration;
    setState(() {
      _busy = true;
      _error = null;
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
        setState(() => _error = 'Routines could not be updated.');
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
    final slot = _slots[_selectedSlot];
    if (!slot.enabled || slot.type == TagType.unknown) {
      _showNotice(context, 'Choose an available plan first.', error: true);
      return;
    }
    final lease = _beginDeviceOperation(context, 'Contactless Studio');
    if (lease == null) return;
    final generation = ++_operationGeneration;
    _emulationLease = lease;
    setState(() {
      _busy = true;
      _error = null;
    });
    var keepLease = false;
    var modeMayBeEmulating = false;
    try {
      await appState.runSlotOperation(
        () => communicator.activateSlot(slot.index),
      );
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
        setState(() => _error = 'The routine could not be started.');
        _showNotice(context, 'The routine could not be started.', error: true);
      }
    } finally {
      if (!keepLease) {
        if (modeMayBeEmulating) {
          await _restoreReaderMode(communicator, lease);
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
      if (_isCurrent(generation, communicator)) {
        setState(() => _emulating = false);
      }
    } catch (error) {
      if (!mounted) return;
      if (_isCurrent(generation, communicator)) {
        setState(() => _error = 'The routine could not be stopped.');
        _showNotice(context, 'The routine could not be stopped.', error: true);
      }
    } finally {
      if (stopped) {
        lease?.release();
        if (identical(_emulationLease, lease)) _emulationLease = null;
      } else if (!_isCurrent(generation, communicator) && lease != null) {
        await _restoreReaderMode(communicator, lease);
      }
      if (_isCurrent(generation, communicator)) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  void dispose() {
    _operationGeneration++;
    _deviceOperations.removeListener(_syncSharedSlot);
    final communicator = _communicator;
    final lease = _emulationLease;
    if (_emulating && communicator != null && lease != null) {
      unawaited(_restoreReaderMode(communicator, lease));
    } else if (!_busy) {
      lease?.release();
    }
    _emulationLease = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final slot = _slots.isEmpty ? null : _slots[_selectedSlot.clamp(0, 7)];
    return UndercoverSpringGrid(
      key: const Key('undercover-grid-routines'),
      placements: [
        UndercoverGridPlacement(
          row: 0,
          column: 0,
          rowSpan: 2,
          columnSpan: 4,
          child: UndercoverGridTile(
            label: _error == null
                ? (_emulating ? 'Routine active' : 'My routines')
                : 'Routine error',
            value: slot == null ? 'No plan selected' : _listName(slot.index),
            details:
                _error ??
                (_emulating
                    ? 'The selected routine is running. Use Stop below to finish.'
                    : 'The selected plan is ready. Choose Start below.'),
            icon: _emulating
                ? Icons.event_available_rounded
                : Icons.event_repeat_rounded,
            color: _error != null
                ? _red
                : (_emulating ? _green : const Color(0xFF5E5CE6)),
            selected: _emulating,
            busy: _busy,
          ),
        ),
        for (var index = 0; index < 8; index++)
          UndercoverGridPlacement(
            row: 2 + index ~/ 4,
            column: index % 4,
            rowSpan: 1,
            columnSpan: 1,
            child: UndercoverGridTile(
              key: Key('undercover-emulation-slot-${index + 1}'),
              label: _listName(index),
              value: '${index + 1}',
              icon:
                  index < _slots.length && _slots[index].type != TagType.unknown
                  ? Icons.event_note_rounded
                  : Icons.event_busy_rounded,
              color: const Color(0xFF5E5CE6),
              selected: index == _selectedSlot,
              enabled:
                  !_emulating &&
                  !_busy &&
                  index < _slots.length &&
                  _slots[index].enabled &&
                  _slots[index].type != TagType.unknown,
              onPressed: () => setState(() => _selectedSlot = index),
            ),
          ),
        UndercoverGridPlacement(
          row: 4,
          column: 0,
          rowSpan: 1,
          columnSpan: 1,
          child: UndercoverGridTile(
            key: const Key('undercover-routine-toggle'),
            label: _emulating ? 'Stop' : 'Start',
            icon: _emulating ? Icons.pause_rounded : Icons.play_arrow_rounded,
            color: _emulating ? _red : _green,
            selected: _emulating,
            enabled:
                !_busy &&
                (_emulating ||
                    (slot != null &&
                        slot.enabled &&
                        slot.type != TagType.unknown)),
            onPressed: () =>
                _emulating ? unawaited(_stop()) : unawaited(_start()),
          ),
        ),
        UndercoverGridPlacement(
          row: 4,
          column: 1,
          rowSpan: 1,
          columnSpan: 1,
          child: UndercoverGridTile(
            label: 'Refresh',
            icon: Icons.refresh_rounded,
            color: _blue,
            enabled: !_busy && !_emulating && _communicator != null,
            busy: _busy,
            onPressed: () => unawaited(_refresh()),
          ),
        ),
        UndercoverGridPlacement(
          row: 4,
          column: 2,
          rowSpan: 1,
          columnSpan: 1,
          child: UndercoverGridTile(
            label: 'Previous',
            icon: Icons.chevron_left_rounded,
            color: _orange,
            enabled: !_busy && !_emulating && _slots.isNotEmpty,
            onPressed: () =>
                setState(() => _selectedSlot = (_selectedSlot + 7) % 8),
          ),
        ),
        UndercoverGridPlacement(
          row: 4,
          column: 3,
          rowSpan: 1,
          columnSpan: 1,
          child: UndercoverGridTile(
            label: 'Next',
            icon: Icons.chevron_right_rounded,
            color: _orange,
            enabled: !_busy && !_emulating && _slots.isNotEmpty,
            onPressed: () =>
                setState(() => _selectedSlot = (_selectedSlot + 1) % 8),
          ),
        ),
        UndercoverGridPlacement(
          row: 5,
          column: 0,
          rowSpan: 1,
          columnSpan: 4,
          child: UndercoverGridTile(
            label: 'Selected plan',
            value: slot == null ? 'None' : _listName(slot.index),
            details: slot == null
                ? 'Connect and refresh to load plans.'
                : slot.enabled && slot.type != TagType.unknown
                ? 'Plan ${slot.index + 1} is selected and available.'
                : 'Plan ${slot.index + 1} is selected but unavailable.',
            icon: Icons.radio_button_checked_rounded,
            color: const Color(0xFF3A3A56),
            selected: slot != null,
          ),
        ),
      ],
    );
  }
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
    final lease = _beginDeviceOperation(context, 'Signals');
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
        _showNotice(context, 'No new activity was found.');
      }
    } catch (error) {
      if (!mounted) return;
      if (_isCurrent(generation, communicator)) {
        setState(() => _error = 'The activity review could not be completed.');
        _showNotice(
          context,
          'The activity review could not be completed.',
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
    if (mounted) _showNotice(context, 'Private details copied.');
  }

  Future<void> _showFrames() async {
    final capture = _capture;
    if (capture == null) return;
    await _showUndercoverSheet<void>(
      context,
      title: 'Recent activity',
      heightFactor: 0.82,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(14, 0, 14, 24),
        itemCount: capture.annotatedFrames.length,
        separatorBuilder: (_, _) => const Divider(color: Colors.white12),
        itemBuilder: (context, index) {
          final frame = capture.annotatedFrames[index].frame;
          return ListTile(
            leading: CircleAvatar(
              backgroundColor: frame.isReaderToCard ? _blue : _green,
              child: Icon(
                frame.isReaderToCard
                    ? Icons.arrow_forward_rounded
                    : Icons.arrow_back_rounded,
                color: Colors.white,
              ),
            ),
            title: Text(
              'Activity ${index + 1}',
              style: const TextStyle(color: Colors.white, fontSize: 13),
            ),
            subtitle: Text(
              frame.isReaderToCard ? 'Outgoing update' : 'Incoming update',
              style: const TextStyle(color: Colors.white60, fontSize: 11),
            ),
            trailing: const Text(
              'Saved',
              style: TextStyle(color: Colors.white38),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final capture = _capture;
    final summary = capture?.summary;
    final resultLabel = summary == null
        ? 'No review yet'
        : summary.arqcSeen
        ? 'Completed'
        : summary.tcSeen
        ? 'Saved'
        : summary.halted
        ? 'Interrupted'
        : 'In progress';
    return UndercoverSpringGrid(
      key: const Key('undercover-grid-activity'),
      placements: [
        UndercoverGridPlacement(
          row: 0,
          column: 0,
          rowSpan: 2,
          columnSpan: 4,
          child: UndercoverGridTile(
            label: _error == null
                ? (_capturing ? 'Reviewing now' : 'Activity')
                : 'Activity error',
            value: summary == null
                ? 'No updates'
                : '${summary.frameCount} updates',
            details:
                _error ??
                (_capturing
                    ? 'Checking activity for $_durationSeconds seconds.'
                    : summary == null
                    ? 'Choose a duration and run a review.'
                    : '${capture!.nonces.length} pending items · $resultLabel'),
            icon: _capturing ? Icons.update_rounded : Icons.history_rounded,
            color: _error != null
                ? _red
                : (_capturing ? _red : const Color(0xFF14213D)),
            busy: _capturing,
          ),
        ),
        for (var index = 0; index < 3; index++)
          UndercoverGridPlacement(
            row: 2,
            column: index,
            rowSpan: 1,
            columnSpan: 1,
            child: UndercoverGridTile(
              key: Key(
                'undercover-activity-duration-${const [5, 10, 30][index]}',
              ),
              label: const ['Quick', 'Regular', 'Full'][index],
              value: '${const [5, 10, 30][index]}s',
              icon: Icons.timer_outlined,
              color: _blue,
              selected: _durationSeconds == const [5, 10, 30][index],
              enabled: !_capturing,
              onPressed: () =>
                  setState(() => _durationSeconds = const [5, 10, 30][index]),
            ),
          ),
        UndercoverGridPlacement(
          row: 2,
          column: 3,
          rowSpan: 1,
          columnSpan: 1,
          child: UndercoverGridTile(
            key: const Key('undercover-activity-run'),
            label: _capturing ? 'Reviewing' : 'Run review',
            icon: _capturing
                ? Icons.hourglass_top_rounded
                : Icons.manage_search_rounded,
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
          row: 3,
          column: 0,
          rowSpan: 1,
          columnSpan: 1,
          child: UndercoverGridTile(
            label: 'Outgoing',
            value: '${summary?.readerFrameCount ?? 0}',
            icon: Icons.arrow_upward_rounded,
            color: _blue,
          ),
        ),
        UndercoverGridPlacement(
          row: 3,
          column: 1,
          rowSpan: 1,
          columnSpan: 1,
          child: UndercoverGridTile(
            label: 'Incoming',
            value: '${summary?.cardFrameCount ?? 0}',
            icon: Icons.arrow_downward_rounded,
            color: _green,
          ),
        ),
        UndercoverGridPlacement(
          row: 3,
          column: 2,
          rowSpan: 1,
          columnSpan: 1,
          child: UndercoverGridTile(
            label: 'Pending',
            value: '${capture?.nonces.length ?? 0}',
            icon: Icons.schedule_rounded,
            color: _orange,
          ),
        ),
        UndercoverGridPlacement(
          row: 3,
          column: 3,
          rowSpan: 1,
          columnSpan: 1,
          child: UndercoverGridTile(
            label: 'Total',
            value: '${summary?.frameCount ?? 0}',
            icon: Icons.data_usage_rounded,
            color: const Color(0xFF5E5CE6),
          ),
        ),
        UndercoverGridPlacement(
          row: 4,
          column: 0,
          rowSpan: 1,
          columnSpan: 4,
          child: UndercoverGridTile(
            label: 'Activity summary',
            value: resultLabel,
            details: summary == null
                ? 'No activity has been reviewed.'
                : 'Reference ${summary.uid == null ? 'unavailable' : 'available'} · ${summary.aids.length} groups · ${summary.ratsSeen ? 'updated' : 'pending'}',
            icon: Icons.insights_rounded,
            color: const Color(0xFF3A3A56),
            selected: summary != null,
          ),
        ),
        UndercoverGridPlacement(
          row: 5,
          column: 0,
          rowSpan: 1,
          columnSpan: 1,
          child: UndercoverGridTile(
            label: 'Activity',
            icon: Icons.timeline_rounded,
            color: _green,
            enabled: capture != null,
            onPressed: () => unawaited(_showFrames()),
          ),
        ),
        UndercoverGridPlacement(
          row: 5,
          column: 1,
          rowSpan: 1,
          columnSpan: 1,
          child: UndercoverGridTile(
            label: 'Copy details',
            icon: Icons.content_copy_rounded,
            color: const Color(0xFF5E5CE6),
            enabled: capture != null,
            onPressed: () => unawaited(_copyCapture()),
          ),
        ),
        UndercoverGridPlacement(
          row: 5,
          column: 2,
          rowSpan: 1,
          columnSpan: 2,
          child: UndercoverGridTile(
            label: 'Selected duration',
            value: '$_durationSeconds seconds',
            details: 'Use the controls above to change the review length.',
            icon: Icons.timer_rounded,
            color: const Color(0xFF3A3A56),
            selected: true,
          ),
        ),
      ],
    );
  }
}

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

class _DashboardList extends StatelessWidget {
  const _DashboardList({required this.storageKey, required this.children});

  final String storageKey;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      key: PageStorageKey(storageKey),
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 16),
      itemCount: children.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (_, index) => children[index],
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.label,
    required this.icon,
    required this.onPressed,
    this.color = _blue,
    this.enabled = true,
  });

  final String label;
  final IconData icon;
  final VoidCallback onPressed;
  final Color color;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      child: Material(
        color: enabled ? color.withValues(alpha: 0.9) : Colors.white12,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: enabled ? onPressed : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  color: enabled ? Colors.white : Colors.white38,
                  size: 18,
                ),
                const SizedBox(width: 7),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: enabled ? Colors.white : Colors.white38,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
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
      if (!mounted || !identical(communicator, _communicator)) return;
      setState(() {
        _activeSlot = active;
        _slots = slots;
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
    unawaited(_selectSlot((_activeSlot + delta + 8) % 8));
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final slot = _slots.isEmpty ? null : _slots[_activeSlot.clamp(0, 7)];
    return _DashboardList(
      storageKey: 'undercover-home-scroll',
      children: [
        _GlassCard(
          child: Row(
            children: [
              IconButton(
                key: const Key('undercover-slot-previous'),
                onPressed: _busy || _slots.isEmpty ? null : () => _move(-1),
                icon: const Icon(
                  Icons.chevron_left_rounded,
                  color: Colors.white,
                ),
              ),
              Expanded(
                child: Column(
                  children: [
                    Text(
                      'LIST ${_activeSlot + 1}',
                      style: const TextStyle(
                        color: Colors.white60,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.4,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _communicator == null
                          ? 'Available offline'
                          : _listName(_activeSlot),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 21,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 9,
                          height: 9,
                          decoration: BoxDecoration(
                            color: slot?.enabled == true
                                ? _green
                                : Colors.transparent,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white70),
                          ),
                        ),
                        const SizedBox(width: 7),
                        Flexible(
                          child: Text(
                            slot == null
                                ? 'Waiting to sync'
                                : slot.enabled
                                ? 'Ready for today'
                                : 'Not available',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              IconButton(
                key: const Key('undercover-slot-next'),
                onPressed: _busy || _slots.isEmpty ? null : () => _move(1),
                icon: const Icon(
                  Icons.chevron_right_rounded,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
        if (_busy) const LinearProgressIndicator(color: Colors.white),
        if (_error != null)
          _GlassCard(
            color: _red.withValues(alpha: 0.22),
            child: Text(_error!, style: const TextStyle(color: Colors.white)),
          ),
        _GlassCard(
          padding: const EdgeInsets.fromLTRB(10, 16, 10, 12),
          child: GridView.builder(
            key: const Key('undercover-slot-grid'),
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 4,
              childAspectRatio: 0.72,
              crossAxisSpacing: 8,
              mainAxisSpacing: 12,
            ),
            itemCount: 8,
            itemBuilder: (context, index) {
              final entry = index < _slots.length ? _slots[index] : null;
              return _SlotTile(
                index: index,
                slot: entry,
                selected: index == _activeSlot,
                busy: _busy,
                onTap: () => _selectSlot(index),
              );
            },
          ),
        ),
        LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth < 420
                ? constraints.maxWidth
                : (constraints.maxWidth - 10) / 2;
            return Wrap(
              spacing: 10,
              runSpacing: 8,
              children: [
                SizedBox(
                  width: width,
                  child: _ActionButton(
                    label: 'Sync lists',
                    icon: Icons.sync_rounded,
                    enabled: _communicator != null && !_busy,
                    onPressed: () => unawaited(_refresh()),
                  ),
                ),
                SizedBox(
                  width: width,
                  child: _ActionButton(
                    label: slot?.enabled == true
                        ? 'Ready for today'
                        : 'Not available',
                    icon: slot?.enabled == true
                        ? Icons.check_circle_rounded
                        : Icons.radio_button_unchecked_rounded,
                    color: slot?.enabled == true ? _green : Colors.white24,
                    enabled: false,
                    onPressed: () {},
                  ),
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _SlotTile extends StatelessWidget {
  const _SlotTile({
    required this.index,
    required this.slot,
    required this.selected,
    required this.busy,
    required this.onTap,
  });

  final int index;
  final _SlotSnapshot? slot;
  final bool selected;
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label:
          '${_listName(index)}, ${slot?.enabled == true ? 'ready' : 'not available'}',
      child: InkWell(
        key: Key('undercover-slot-${index + 1}'),
        borderRadius: BorderRadius.circular(18),
        onTap: busy || slot == null ? null : onTap,
        child: Column(
          children: [
            Expanded(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                decoration: BoxDecoration(
                  color: selected
                      ? _blue
                      : Colors.white.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: selected ? Colors.white70 : Colors.white24,
                    width: selected ? 2 : 1,
                  ),
                ),
                child: Stack(
                  children: [
                    Center(
                      child: _SlotGlyph(type: slot?.type ?? TagType.unknown),
                    ),
                    Positioned(
                      top: 7,
                      right: 7,
                      child: Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: slot?.enabled == true
                              ? _green
                              : Colors.transparent,
                          border: Border.all(color: Colors.white60),
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 5),
            Text(
              _listName(index),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: selected ? Colors.white : Colors.white70,
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
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
    return _DashboardList(
      storageKey: 'undercover-recovery-scroll',
      children: [
        _GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.pie_chart_rounded, color: Colors.white),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Weekly progress',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  minHeight: 12,
                  value: ratio,
                  color: _green,
                  backgroundColor: _red.withValues(alpha: 0.65),
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _MarketTicker(
                    symbol: 'Reference',
                    value: card == null ? 'Pending' : 'Added',
                    positive: card != null,
                  ),
                  _MarketTicker(
                    symbol: 'Status',
                    value: card == null ? 'Waiting' : 'Ready',
                    positive: card != null,
                  ),
                  _MarketTicker(
                    symbol: 'Groups',
                    value: result == null ? 'Pending' : '$verified of $total',
                    positive: card != null,
                  ),
                  _MarketTicker(
                    symbol: 'Notes',
                    value: result?.blocks.isNotEmpty == true ? 'Saved' : 'None',
                    positive: result?.blocks.isNotEmpty == true,
                  ),
                ],
              ),
            ],
          ),
        ),
        _GlassCard(
          padding: EdgeInsets.zero,
          child: SizedBox(
            height: 112,
            child: Row(
              children: [
                Expanded(
                  child: _ScanHalf(
                    key: const Key('undercover-recovery-lf'),
                    label: 'Quick review',
                    value: _lfIdentity == null ? 'Tap to update' : 'Updated',
                    icon: Icons.bolt_rounded,
                    busy: _readingLf,
                    onTap: () => unawaited(_readLf()),
                  ),
                ),
                Container(width: 1, color: Colors.white24),
                Expanded(
                  child: _ScanHalf(
                    key: const Key('undercover-recovery-hf'),
                    label: 'Full review',
                    value: card == null ? 'Tap to update' : 'Updated',
                    icon: Icons.fact_check_rounded,
                    busy: _readingHf,
                    onTap: () => unawaited(_readHf()),
                  ),
                ),
              ],
            ),
          ),
        ),
        GestureDetector(
          key: const Key('undercover-autopwn-weather'),
          onTap: _running ? _cancelAutopwn : () => unawaited(_runAutopwn()),
          onLongPress: _running ? null : () => unawaited(_chooseDictionaries()),
          child: _GlassCard(
            color: const Color(0xAA0B5CAD),
            child: Column(
              children: [
                Row(
                  children: [
                    Icon(
                      result?.complete == true
                          ? Icons.wb_sunny_rounded
                          : _running
                          ? Icons.cloud_sync_rounded
                          : Icons.cloud_rounded,
                      size: 42,
                      color: Colors.white,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Plan review',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 19,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            _running
                                ? 'Reviewing your items'
                                : result == null
                                ? 'Tap to review · hold for sources'
                                : result.complete
                                ? 'Every area is up to date'
                                : '${total - verified} items still need attention',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Colors.white70),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      '$verified/$total',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 31,
                        fontWeight: FontWeight.w300,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: ratio,
                    minHeight: 7,
                    color: Colors.white,
                    backgroundColor: Colors.white24,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (_error != null)
          _GlassCard(
            color: _red.withValues(alpha: 0.22),
            child: Text(_error!, style: const TextStyle(color: Colors.white)),
          ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _ActionButton(
              label: 'Save reference',
              icon: Icons.bookmark_add_rounded,
              enabled:
                  card != null && _hfTagType != TagType.unknown && !_running,
              onPressed: () => unawaited(_saveUuid()),
            ),
            _ActionButton(
              label: 'Completed',
              icon: Icons.check_circle_rounded,
              enabled: result != null,
              onPressed: () => unawaited(_showKeys()),
              color: _green,
            ),
            _ActionButton(
              label: 'Areas',
              icon: Icons.grid_view_rounded,
              enabled: result != null,
              onPressed: () => unawaited(_showSectors()),
              color: _orange,
            ),
            _ActionButton(
              label: 'Review now',
              icon: Icons.task_alt_rounded,
              enabled:
                  !_running &&
                  context.read<ChameleonGUIState>().communicator != null,
              onPressed: () => unawaited(_runAutopwn()),
              color: const Color(0xFFBF5AF2),
            ),
            _ActionButton(
              label: 'Copy private summary',
              icon: Icons.content_copy_rounded,
              enabled: result?.verifiedKeys.isNotEmpty == true,
              onPressed: () => unawaited(_copyKeys()),
              color: const Color(0xFF64D2FF),
            ),
            _ActionButton(
              label: 'Copy private draft',
              icon: Icons.note_alt_rounded,
              enabled: result?.blocks.isNotEmpty == true,
              onPressed: () => unawaited(_copyDump()),
              color: const Color(0xFF5E5CE6),
            ),
          ],
        ),
      ],
    );
  }
}

class _MarketTicker extends StatelessWidget {
  const _MarketTicker({
    required this.symbol,
    required this.value,
    required this.positive,
  });

  final String symbol;
  final String value;
  final bool positive;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 142,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(13),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  symbol,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                  ),
                ),
              ),
              Icon(
                positive ? Icons.check_circle_rounded : Icons.schedule_rounded,
                color: positive ? _green : Colors.white38,
                size: 15,
              ),
            ],
          ),
          const SizedBox(height: 5),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: positive ? _green : Colors.white60,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}

class _ScanHalf extends StatelessWidget {
  const _ScanHalf({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    required this.busy,
    required this.onTap,
  });

  final String label;
  final String value;
  final IconData icon;
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: busy ? null : onTap,
      child: Padding(
        padding: const EdgeInsets.all(13),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (busy)
              const SizedBox.square(
                dimension: 25,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            else
              Icon(icon, color: Colors.white, size: 27),
            const SizedBox(height: 7),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white60, fontSize: 10),
            ),
          ],
        ),
      ),
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
        return _DashboardList(
          storageKey: 'undercover-capture-scroll',
          children: [
            _GlassCard(
              color: (running ? _red : _blue).withValues(alpha: 0.34),
              child: Row(
                children: [
                  Container(
                    width: 58,
                    height: 58,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      running
                          ? Icons.edit_note_rounded
                          : Icons.menu_book_rounded,
                      color: Colors.white,
                      size: 31,
                    ),
                  ),
                  const SizedBox(width: 13),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          running ? 'Journal active' : 'Daily journal',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          running
                              ? '${metadata?.observedRecords ?? 0} entries · saved automatically'
                              : 'Keep a private activity log',
                          style: const TextStyle(color: Colors.white70),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    key: const Key('undercover-capture-toggle'),
                    onPressed:
                        controller.isBusy ||
                            !controller.isConnected ||
                            controller.isSupported == false ||
                            (!running && !controller.canStart)
                        ? null
                        : () => running
                              ? unawaited(_stop(controller))
                              : unawaited(_start(controller)),
                    style: IconButton.styleFrom(
                      backgroundColor: running ? Colors.white : _blue,
                      foregroundColor: running ? _blue : Colors.white,
                      minimumSize: const Size(52, 52),
                    ),
                    icon: Icon(
                      running ? Icons.pause_rounded : Icons.play_arrow_rounded,
                    ),
                  ),
                ],
              ),
            ),
            _GlassCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Journal mode',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 17,
                    ),
                  ),
                  const SizedBox(height: 11),
                  for (final mode in HfCaptureMode.values)
                    _CaptureModeRow(
                      mode: mode,
                      selected: effectiveMode == mode,
                      enabled: !running && !controller.isBusy,
                      onTap: () => setState(() => _mode = mode),
                    ),
                ],
              ),
            ),
            if (effectiveMode == HfCaptureMode.emulation)
              _GlassCard(
                child: Row(
                  children: [
                    const Icon(Icons.list_alt_rounded, color: Colors.white),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Active list',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            _slotsLoading
                                ? 'Loading lists'
                                : _selectedEntry == null
                                ? 'No list selected'
                                : '${_listName(_selectedEntry!.index)} · ${_tagLabel(_selectedEntry!.type)}',
                            style: const TextStyle(color: Colors.white60),
                          ),
                        ],
                      ),
                    ),
                    _ActionButton(
                      label: 'Choose',
                      icon: Icons.swap_horiz_rounded,
                      enabled: !running && !_slotsLoading,
                      onPressed: () => unawaited(_chooseSlot()),
                    ),
                  ],
                ),
              ),
            if (running && effectiveMode == HfCaptureMode.reader)
              SizedBox(
                width: double.infinity,
                child: _ActionButton(
                  label: 'Add marker now',
                  icon: Icons.add_task_rounded,
                  enabled: !controller.isBusy,
                  onPressed: () => unawaited(_probeReader(controller)),
                  color: _green,
                ),
              ),
            if (!running &&
                !controller.canStart &&
                (controller.needsDrain || controller.needsFinalize))
              SizedBox(
                width: double.infinity,
                child: _ActionButton(
                  label: 'Restore previous session',
                  icon: Icons.restore_rounded,
                  enabled: controller.isConnected && !controller.isBusy,
                  onPressed: () => unawaited(_retryDrain(controller)),
                  color: _orange,
                ),
              ),
            Row(
              children: [
                Expanded(
                  child: _CaptureMetric(
                    label: 'Entries',
                    value: '${metadata?.observedRecords ?? 0}',
                    color: _blue,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _CaptureMetric(
                    label: 'Saved',
                    value: '${metadata?.storedRecords ?? 0}',
                    color: _green,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _CaptureMetric(
                    label: 'Skipped',
                    value: '${metadata?.droppedRecords ?? 0}',
                    color: _red,
                  ),
                ),
              ],
            ),
            if (controller.error != null)
              _GlassCard(
                color: _red.withValues(alpha: 0.22),
                child: Text(
                  'The journal could not be updated. Try again later.',
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            _GlassCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Recent activity',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 9),
                  if (records.isEmpty)
                    const Text(
                      'No recent activity yet.',
                      style: TextStyle(color: Colors.white60),
                    ),
                  for (final record in records)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 5),
                      child: Row(
                        children: [
                          Icon(
                            record.hasRfError
                                ? Icons.error_outline_rounded
                                : Icons.check_circle_outline_rounded,
                            size: 16,
                            color: record.hasRfError ? _red : Colors.white60,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Journal entry ${record.sequence + 1}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                              ),
                            ),
                          ),
                          Text(
                            record.hasRfError ? 'Needs review' : 'Saved',
                            style: const TextStyle(
                              color: Colors.white38,
                              fontSize: 10,
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
    );
  }
}

class _CaptureModeRow extends StatelessWidget {
  const _CaptureModeRow({
    required this.mode,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final HfCaptureMode mode;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final (title, subtitle, icon) = switch (mode) {
      HfCaptureMode.emulation => (
        'Routine',
        'Add entries while the active list is in use',
        Icons.repeat_rounded,
      ),
      HfCaptureMode.passive => (
        'Silent',
        'Keep notes quietly in the background',
        Icons.notifications_off_rounded,
      ),
      HfCaptureMode.reader => (
        'Manual',
        'Add entries only when you request them',
        Icons.touch_app_rounded,
      ),
    };
    return Material(
      color: Colors.transparent,
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        enabled: enabled,
        onTap: onTap,
        leading: CircleAvatar(
          backgroundColor: selected ? _blue : Colors.white12,
          child: Icon(icon, color: Colors.white),
        ),
        title: Text(title, style: const TextStyle(color: Colors.white)),
        subtitle: Text(subtitle, style: const TextStyle(color: Colors.white54)),
        trailing: Icon(
          selected
              ? Icons.check_circle_rounded
              : Icons.radio_button_unchecked_rounded,
          color: selected ? _green : Colors.white30,
        ),
      ),
    );
  }
}

class _CaptureMetric extends StatelessWidget {
  const _CaptureMetric({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return _GlassCard(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 12),
      color: color.withValues(alpha: 0.22),
      child: Column(
        children: [
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            label,
            style: const TextStyle(color: Colors.white60, fontSize: 10),
          ),
        ],
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
    return _DashboardList(
      storageKey: 'undercover-emulation-scroll',
      children: [
        _GlassCard(
          color: (_emulating ? _green : const Color(0xFF5E5CE6)).withValues(
            alpha: 0.34,
          ),
          child: Column(
            children: [
              Row(
                children: [
                  Container(
                    width: 62,
                    height: 62,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Icon(
                      _emulating
                          ? Icons.event_available_rounded
                          : Icons.event_repeat_rounded,
                      color: Colors.white,
                      size: 30,
                    ),
                  ),
                  const SizedBox(width: 13),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _emulating ? 'Routine active' : 'My routines',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          slot == null
                              ? 'No plan selected'
                              : '${_listName(slot.index)} · ready to use',
                          style: const TextStyle(color: Colors.white70),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: _emulating ? _green : Colors.white24,
                      shape: BoxShape.circle,
                      boxShadow: _emulating
                          ? const [BoxShadow(color: _green, blurRadius: 12)]
                          : null,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: _ActionButton(
                  label: _emulating ? 'Stop routine' : 'Start routine',
                  icon: _emulating
                      ? Icons.pause_rounded
                      : Icons.play_arrow_rounded,
                  color: _emulating ? _red : _green,
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
            ],
          ),
        ),
        if (_busy) const LinearProgressIndicator(color: Colors.white),
        if (_error != null)
          _GlassCard(
            color: _red.withValues(alpha: 0.22),
            child: Text(_error!, style: const TextStyle(color: Colors.white)),
          ),
        _GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Plans',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: _busy || _emulating
                        ? null
                        : () => unawaited(_refresh()),
                    icon: const Icon(
                      Icons.refresh_rounded,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 4,
                  childAspectRatio:
                      (0.88 -
                              (MediaQuery.textScalerOf(context).scale(1) - 1)
                                      .clamp(0.0, 2.0) *
                                  0.18)
                          .clamp(0.52, 0.88),
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                ),
                itemCount: 8,
                itemBuilder: (context, index) {
                  final entry = index < _slots.length ? _slots[index] : null;
                  final selected = index == _selectedSlot;
                  return InkWell(
                    key: Key('undercover-emulation-slot-${index + 1}'),
                    borderRadius: BorderRadius.circular(16),
                    onTap: _emulating || _busy || entry == null
                        ? null
                        : () => setState(() => _selectedSlot = index),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      padding: const EdgeInsets.all(7),
                      decoration: BoxDecoration(
                        color: selected
                            ? const Color(0xFF5E5CE6)
                            : Colors.white10,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: selected ? Colors.white70 : Colors.white12,
                        ),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _SlotGlyph(type: entry?.type ?? TagType.unknown),
                          const SizedBox(height: 3),
                          Text(
                            '${index + 1}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              height: 1,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ],
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
    return _DashboardList(
      storageKey: 'undercover-signals-scroll',
      children: [
        _GlassCard(
          color: const Color(0xFF14213D).withValues(alpha: 0.78),
          child: Column(
            children: [
              Row(
                children: [
                  Container(
                    width: 62,
                    height: 62,
                    decoration: BoxDecoration(
                      color: (_capturing ? _red : _blue).withValues(alpha: 0.8),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      _capturing ? Icons.update_rounded : Icons.history_rounded,
                      color: Colors.white,
                      size: 32,
                    ),
                  ),
                  const SizedBox(width: 13),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _capturing ? 'Reviewing now' : 'Activity',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 21,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _capturing
                              ? 'Checking recent updates'
                              : summary == null
                              ? 'A simple history of your updates'
                              : '${summary.frameCount} updates · ${capture!.nonces.length} pending',
                          style: const TextStyle(color: Colors.white70),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 15),
              Row(
                children: [
                  for (final seconds in const [5, 10, 30]) ...[
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 3),
                        child: ChoiceChip(
                          label: Text(switch (seconds) {
                            5 => 'Quick',
                            10 => 'Regular',
                            _ => 'Full',
                          }),
                          selected: _durationSeconds == seconds,
                          onSelected: _capturing
                              ? null
                              : (_) =>
                                    setState(() => _durationSeconds = seconds),
                          selectedColor: _blue,
                          backgroundColor: Colors.white12,
                          labelStyle: const TextStyle(color: Colors.white),
                          side: BorderSide.none,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: _ActionButton(
                  label: _capturing ? 'Reviewing…' : 'Run review',
                  icon: _capturing
                      ? Icons.hourglass_top_rounded
                      : Icons.manage_search_rounded,
                  color: _capturing ? _red : _blue,
                  enabled:
                      !_capturing &&
                      _communicator != null &&
                      _capabilitySupported != false,
                  onPressed: () => unawaited(_captureFrames()),
                ),
              ),
            ],
          ),
        ),
        if (_capturing) const LinearProgressIndicator(color: _red),
        if (_error != null)
          _GlassCard(
            color: _red.withValues(alpha: 0.22),
            child: Text(_error!, style: const TextStyle(color: Colors.white)),
          ),
        if (summary != null)
          Row(
            children: [
              Expanded(
                child: _CaptureMetric(
                  label: 'Outgoing',
                  value: '${summary.readerFrameCount}',
                  color: _blue,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _CaptureMetric(
                  label: 'Incoming',
                  value: '${summary.cardFrameCount}',
                  color: _green,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _CaptureMetric(
                  label: 'Pending',
                  value: '${capture!.nonces.length}',
                  color: _orange,
                ),
              ),
            ],
          ),
        if (summary != null)
          _GlassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Activity summary',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 10),
                _SignalSummaryRow(
                  label: 'Reference',
                  value: summary.uid == null ? 'Not available' : 'Available',
                ),
                _SignalSummaryRow(
                  label: 'Status',
                  value: summary.ratsSeen ? 'Updated' : 'Pending',
                ),
                _SignalSummaryRow(
                  label: 'Groups',
                  value: summary.aids.isEmpty
                      ? 'None'
                      : '${summary.aids.length} available',
                ),
                _SignalSummaryRow(
                  label: 'Result',
                  value: summary.arqcSeen
                      ? 'Completed'
                      : summary.tcSeen
                      ? 'Saved'
                      : summary.halted
                      ? 'Interrupted'
                      : 'In progress',
                ),
              ],
            ),
          ),
        if (capture != null)
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _ActionButton(
                label: 'Activity',
                icon: Icons.timeline_rounded,
                onPressed: () => unawaited(_showFrames()),
                color: _green,
              ),
              _ActionButton(
                label: 'Copy private details',
                icon: Icons.content_copy_rounded,
                onPressed: () => unawaited(_copyCapture()),
                color: const Color(0xFF5E5CE6),
              ),
            ],
          ),
      ],
    );
  }
}

class _SignalSummaryRow extends StatelessWidget {
  const _SignalSummaryRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 70,
            child: Text(label, style: const TextStyle(color: Colors.white54)),
          ),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: const TextStyle(color: Colors.white, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

import 'dart:async';
import 'dart:math';

import 'package:chameleonultragui/bridge/chameleon.dart';
import 'package:chameleonultragui/gui/menu/dialogs/dictionary/export.dart';
import 'package:chameleonultragui/helpers/definitions.dart';
import 'package:chameleonultragui/helpers/general.dart';
import 'package:chameleonultragui/helpers/mifare_classic/general.dart';
import 'package:chameleonultragui/helpers/mifare_classic/reader_key_recovery.dart';
import 'package:chameleonultragui/helpers/mifare_classic/reader_key_guidance.dart';
import 'package:chameleonultragui/main.dart';
import 'package:chameleonultragui/recovery/recovery.dart' as recovery;
import 'package:chameleonultragui/sharedprefsprovider.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

// Localizations
import 'package:chameleonultragui/generated/i18n/app_localizations.dart';

enum _CardSource { saved, slot }

class _SlotEntry {
  final int index; // 0-based
  final String label;
  _SlotEntry(this.index, this.label);
}

class _ReaderKeyCaptureSession {
  final int generation;
  final ChameleonCommunicator communicator;
  final int workSlot;
  final bool autoApply;
  final bool automatic;
  final Mf1PrngType? restorePrngType;
  final CardData? restoreRandomIdentity;

  const _ReaderKeyCaptureSession({
    required this.generation,
    required this.communicator,
    required this.workSlot,
    required this.autoApply,
    required this.automatic,
    this.restorePrngType,
    this.restoreRandomIdentity,
  });
}

// Reader-key capture (MFKey32). The capture source is chosen with the tabs at
// the top: emulate a saved/slot card, a fixed UID, or a device-generated random
// UID. Below, Start capture arms the device and recovered keys are shown/saved.
class ReaderKeysPage extends StatefulWidget {
  const ReaderKeysPage({super.key});

  @override
  ReaderKeysPageState createState() => ReaderKeysPageState();
}

class ReaderKeysPageState extends State<ReaderKeysPage>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late TabController _tab;
  int _lastMode = 0;

  // Card mode
  _CardSource _cardSource = _CardSource.saved;
  String? _selectedCardId;
  int? _selectedSlot;
  String _selectedSlotUid = '';
  List<_SlotEntry> _slots = [];
  List<_SlotEntry> _workSlots = [];
  int? _workSlot;
  TagType _workSlotType = TagType.mifare1K;
  String? _preparedWorkSignature;
  bool _preparedWorkUsesSyntheticManufacturerBlock = false;
  ChameleonCommunicator? _observedCommunicator;

  // Fixed UID mode
  final TextEditingController _uidCtl = TextEditingController();
  CardData? _scannedCardIdentity;

  // Random mode
  String _currentRandomUid = '';

  // Capture / recovery
  bool armed = false;
  bool busy = false;
  bool recovering = false;
  bool _automaticCapture = true;
  int detectionCount = 0;
  final List<Uint8List> keys = [];
  final Map<ReaderKeyTarget, ReaderKeyRecoveryResult> recoveryResults = {};
  final Set<ReaderKeyTarget> _appliedTargets = {};
  final Set<String> _sessionKeyHexes = {};
  String? _sessionDictionaryId;
  String? _sessionDictionaryName;
  String outputUid = "";
  int progress = -1;
  Timer? _pollTimer;
  bool _pollInProgress = false;
  final List<DetectionResult> _detectionLedger = [];
  final Set<String> _detectionLedgerIds = {};
  int _deviceDetectionCursor = 0;
  int _sessionDetectionCount = 0;
  String _lastRecoveryFingerprint = '';
  DateTime? _lastEvidenceAt;
  bool _automaticStopPending = false;
  int _captureGeneration = 0;
  _ReaderKeyCaptureSession? _captureSession;
  Future<void>? _activeRecovery;
  _ReaderKeyCaptureSession? _activeRecoverySession;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _tab = TabController(length: 3, vsync: this);
    _tab.addListener(() {
      if (_tab.index != _lastMode) {
        _lastMode = _tab.index;
        if (!armed && !recovering) _resetWorkPreparation();
      }
      setState(() {});
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final app = context.watch<ChameleonGUIState>();
    final communicator = app.communicator;
    if (identical(communicator, _observedCommunicator)) return;

    _observedCommunicator = communicator;
    _captureGeneration++;
    _pollTimer?.cancel();
    _pollInProgress = false;
    armed = false;
    busy = false;
    detectionCount = 0;
    _resetDetectionLedger();
    _slots = [];
    _workSlots = [];
    _workSlot = null;
    _selectedSlot = null;
    _selectedSlotUid = '';
    recoveryResults.clear();
    keys.clear();
    outputUid = '';
    _sessionDictionaryId = null;
    _sessionDictionaryName = null;
    _sessionKeyHexes.clear();
    _resetWorkPreparation();

    if (communicator != null && app.connector?.connected == true) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !identical(_app.communicator, communicator)) return;
        unawaited(_refreshStatus());
        unawaited(_loadSlots());
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pollTimer?.cancel();
    final captureSession = _captureSession;
    if (armed && captureSession != null) {
      final communicator = captureSession.communicator;
      if (identical(_observedCommunicator, communicator)) {
        unawaited(() async {
          for (final cleanup in <Future<void> Function()>[
            () => communicator.setMf1ReaderKeysAnim(false),
            () => communicator.setMf1DetectionStatus(false),
            () => _restoreCaptureConfiguration(captureSession),
          ]) {
            try {
              await cleanup();
            } catch (_) {}
          }
        }());
      }
    }
    _tab.dispose();
    _uidCtl.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (armed &&
        !busy &&
        (state == AppLifecycleState.paused ||
            state == AppLifecycleState.detached ||
            state == AppLifecycleState.hidden)) {
      unawaited(_stop());
    }
  }

  ChameleonGUIState get _app => context.read<ChameleonGUIState>();
  bool get _connected =>
      _app.connector?.connected == true && _app.communicator != null;

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(
      const Duration(seconds: 2),
      (_) => _refreshCount(),
    );
  }

  Future<void> _refreshStatus() async {
    final communicator = _app.communicator;
    if (!_connected || communicator == null) return;
    final generation = _captureGeneration;
    try {
      final isArmed = await communicator.isMf1DetectionMode();
      final count = await communicator.getMf1DetectionCount();
      if (!mounted ||
          generation != _captureGeneration ||
          !identical(_app.communicator, communicator)) {
        return;
      }
      setState(() {
        armed = isArmed;
        detectionCount = count;
        _captureSession = isArmed
            ? _ReaderKeyCaptureSession(
                generation: generation,
                communicator: communicator,
                workSlot: _workSlot ?? 0,
                autoApply: false,
                automatic: false,
              )
            : null;
      });
      if (isArmed) _startPolling();
    } catch (_) {}
  }

  Future<void> _refreshCount() async {
    final communicator = _app.communicator;
    if (!_connected || communicator == null || _pollInProgress) return;
    _pollInProgress = true;
    try {
      final count = await communicator.getMf1DetectionCount();
      String uid = _currentRandomUid;
      if (_tab.index == 2) {
        try {
          final ac = await communicator.mf1GetAntiCollData();
          uid = bytesToHex(ac.uid).toUpperCase();
        } catch (_) {}
      }
      final added = await _syncDetectionLedger(communicator, count);
      if (!mounted || !identical(_app.communicator, communicator)) return;
      final fingerprint = readerKeyEvidenceFingerprint(_detectionLedger);
      final shouldRecover =
          armed &&
          added > 0 &&
          hasRecoverableReaderKeyEvidence(_detectionLedger) &&
          fingerprint != _lastRecoveryFingerprint;
      setState(() {
        detectionCount = _sessionDetectionCount;
        _currentRandomUid = uid;
      });
      if (shouldRecover && !recovering) {
        unawaited(_recoverKeys());
      } else if (count >= 1000 && armed && !busy) {
        unawaited(_stop());
      } else if (!_automaticStopPending &&
          readerKeyCaptureShouldAutoStop(
            automatic: _automaticCapture,
            armed: armed,
            busy: busy,
            recovering: recovering,
            recoveredKeyCount: recoveryResults.values
                .where((result) => result.verifiedByReader)
                .length,
            lastEvidenceAt: _lastEvidenceAt,
            now: DateTime.now(),
          )) {
        _automaticStopPending = true;
        unawaited(_stop());
      }
    } catch (_) {
    } finally {
      _pollInProgress = false;
    }
  }

  Future<void> _loadSlots() async {
    final communicator = _app.communicator;
    if (!_connected || communicator == null) return;
    try {
      final names = await communicator.getSlotTagNames();
      final types = await communicator.getSlotTagTypes();
      final enabled = await communicator.getEnabledSlots();
      final slots = <_SlotEntry>[];
      final workSlots = <_SlotEntry>[];
      for (int i = 0; i < 8 && i < types.length; i++) {
        final name = (i < names.length) ? names[i].hf : '';
        final label = name.isEmpty ? types[i].hf.name : name;
        workSlots.add(_SlotEntry(i, label));
        if (isMifareClassic(types[i].hf) &&
            i < enabled.length &&
            enabled[i].hf) {
          slots.add(_SlotEntry(i, label));
        }
      }
      final activeSlot = await communicator.getActiveSlot();
      if (mounted && identical(_app.communicator, communicator)) {
        setState(() {
          _slots = slots;
          _workSlots = workSlots;
          _workSlot ??= activeSlot;
        });
      }
    } catch (_) {}
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _scanSourceCard() async {
    if (busy || armed || recovering) return;
    final communicator = _app.communicator;
    if (!_connected || communicator == null) return;
    setState(() => busy = true);
    try {
      await communicator.setReaderDeviceMode(true);
      final card = await communicator.scan14443aTag();
      if (card == null) throw StateError('No ISO14443-A card detected');
      if (!await communicator.detectMf1Support()) {
        throw StateError('The detected card is not MIFARE Classic');
      }
      final identity = CardData(
        uid: Uint8List.fromList(card.uid),
        atqa: Uint8List.fromList(card.atqa),
        sak: card.sak,
        ats: Uint8List.fromList(card.ats),
      );
      if (!mounted || !identical(_app.communicator, communicator)) return;
      setState(() {
        _scannedCardIdentity = identity;
        _uidCtl.text = bytesToHex(identity.uid).toUpperCase();
        _workSlotType = identity.sak == 0x18
            ? TagType.mifare4K
            : TagType.mifare1K;
        _resetWorkPreparation();
        _tab.animateTo(1);
      });
      _showMessage(
        'Card identity captured. Replace it with the Chameleon once; automatic retries need no repeated removal.',
      );
    } catch (error) {
      _showMessage(error.toString());
    } finally {
      try {
        await communicator.setReaderDeviceMode(false);
      } catch (_) {}
      if (mounted) setState(() => busy = false);
    }
  }

  String _randomUidHex([int bytes = 4]) {
    final rng = Random();
    final b = List<int>.generate(bytes, (_) => rng.nextInt(256));
    if (b[0] == 0x88) b[0] = 0x08; // avoid cascade-tag marker
    return b
        .map((x) => x.toRadixString(16).padLeft(2, '0'))
        .join()
        .toUpperCase();
  }

  void _resetWorkPreparation() {
    _preparedWorkSignature = null;
    _preparedWorkUsesSyntheticManufacturerBlock = false;
    _captureSession = null;
    _appliedTargets.clear();
  }

  void _resetDetectionLedger() {
    _detectionLedger.clear();
    _detectionLedgerIds.clear();
    _deviceDetectionCursor = 0;
    _sessionDetectionCount = 0;
    _lastRecoveryFingerprint = '';
    _lastEvidenceAt = null;
    _automaticStopPending = false;
  }

  Future<int> _syncDetectionLedger(
    ChameleonCommunicator communicator,
    int deviceCount,
  ) async {
    if (deviceCount < _deviceDetectionCursor) _deviceDetectionCursor = 0;
    final startIndex = _deviceDetectionCursor;
    if (deviceCount == startIndex) return 0;

    final records = await communicator.getMf1DetectionRecords(
      deviceCount,
      startIndex: startIndex,
    );
    final expected = deviceCount - startIndex;
    if (records.length != expected) {
      throw FormatException(
        'Incomplete MF1 detection range: ${records.length}/$expected',
      );
    }
    _deviceDetectionCursor = deviceCount;
    _sessionDetectionCount += records.length;
    var added = 0;
    for (final record in records) {
      if (_detectionLedgerIds.add(readerKeyTranscriptIdentity(record))) {
        _detectionLedger.add(record);
        added++;
      }
    }
    if (added > 0) _lastEvidenceAt = DateTime.now();
    return added;
  }

  Future<void> _restoreCaptureConfiguration(
    _ReaderKeyCaptureSession session,
  ) async {
    final communicator = session.communicator;
    if (session.restoreRandomIdentity != null) {
      await communicator.setMf1RandomUidMode(false);
      await communicator.setMf1AntiCollision(session.restoreRandomIdentity!);
    }
    if (session.restorePrngType != null) {
      await communicator.setMf1PrngType(session.restorePrngType!);
    }
  }

  String _readerDictionaryName(DateTime value) {
    String two(int number) => number.toString().padLeft(2, '0');
    return 'key-reader-${two(value.hour)}-${two(value.minute)}-'
        '${two(value.day)}-${two(value.month)}-${value.year}';
  }

  Future<bool> _confirmWorkSlotReset(
    int slot, {
    bool modifiesSourceInPlace = false,
  }) async {
    if (!mounted) return false;
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(
              modifiesSourceInPlace
                  ? 'Use source slot as work slot?'
                  : 'Prepare work slot?',
            ),
            content: Text(
              modifiesSourceInPlace
                  ? 'Recovered keys and, when required, trailer access conditions '
                        'will be written directly to HF slot ${slot + 1}. LF data is not changed.'
                  : 'HF data in slot ${slot + 1} will be replaced by the selected card '
                        'or a synthetic MIFARE Classic card. LF data is not changed.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(
                  modifiesSourceInPlace ? 'Use slot' : 'Prepare slot',
                ),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _prepareSyntheticWorkSlot(
    ChameleonCommunicator communicator,
    int slot,
    TagType tag,
  ) async {
    await communicator.setReaderDeviceMode(false);
    await communicator.enableSlot(slot, TagFrequency.hf, true);
    await communicator.activateSlot(slot);
    await communicator.setSlotType(slot, tag);
    await communicator.setDefaultDataToSlot(slot, tag);
    await communicator.activateSlot(slot);
    await communicator.saveSlotData();
    _app.changesMade();
  }

  Future<void> _copySlotToWorkSlot(
    ChameleonCommunicator communicator,
    int sourceSlot,
    int workSlot,
  ) async {
    final slotTypes = await communicator.getSlotTagTypes();
    if (sourceSlot >= slotTypes.length ||
        !isMifareClassic(slotTypes[sourceSlot].hf)) {
      throw StateError('The selected source slot is not MIFARE Classic');
    }
    final tag = slotTypes[sourceSlot].hf;
    await communicator.activateSlot(sourceSlot);
    final antiCollision = await communicator.mf1GetAntiCollData();
    final blockCount = mfClassicGetBlockCount(
      chameleonTagTypeGetMfClassicType(tag),
    );
    final dump = <int>[];
    for (var block = 0; block < blockCount; block += 32) {
      final count = min(32, blockCount - block);
      dump.addAll(await communicator.mf1GetEmulatorBlock(block, count));
    }

    await _prepareSyntheticWorkSlot(communicator, workSlot, tag);
    await communicator.setMf1AntiCollision(antiCollision);
    final maxBlocks = 255;
    for (var block = 0; block < blockCount; block += maxBlocks) {
      final count = min(maxBlocks, blockCount - block);
      final start = block * 16;
      await communicator.setMf1BlockData(
        block,
        Uint8List.fromList(dump.sublist(start, start + count * 16)),
      );
    }
    await communicator.saveSlotData();
    _app.changesMade();
  }

  Future<void> _onSlotSelected(int index) async {
    setState(() {
      _selectedSlot = index;
      _selectedSlotUid = '';
      _resetWorkPreparation();
    });
    final communicator = _app.communicator;
    if (!_connected || communicator == null) return;
    try {
      final ac = await _app.runSlotOperation(() async {
        await communicator.activateSlot(index);
        return communicator.mf1GetAntiCollData();
      });
      if (mounted && identical(_app.communicator, communicator)) {
        setState(() => _selectedSlotUid = bytesToHex(ac.uid).toUpperCase());
      }
    } catch (_) {}
  }

  Future<void> _loadDumpIntoActiveSlot(
    ChameleonCommunicator communicator,
    CardSave card,
  ) async {
    final localizations = AppLocalizations.of(context)!;
    final slot = await communicator.getActiveSlot();
    var tag = card.tag;
    if (chameleonTagSaveCheckForMifareClassicEV1(card)) {
      tag = TagType.mifare2K;
    }
    await communicator.setReaderDeviceMode(false);
    await communicator.enableSlot(slot, TagFrequency.hf, true);
    await communicator.activateSlot(slot);
    await communicator.setSlotType(slot, tag);
    await communicator.setDefaultDataToSlot(slot, tag);
    await communicator.setMf1AntiCollision(
      CardData(
        uid: hexToBytes(card.uid),
        atqa: card.atqa,
        sak: card.sak,
        ats: card.ats,
      ),
    );

    List<int> blockChunk = [];
    int? chunkStart;
    Future<void> flushChunk() async {
      if (chunkStart == null || blockChunk.isEmpty) return;
      await communicator.setMf1BlockData(
        chunkStart!,
        Uint8List.fromList(blockChunk),
      );
      blockChunk = [];
      chunkStart = null;
    }

    final blockCount = mfClassicGetBlockCount(
      chameleonTagTypeGetMfClassicType(tag),
    );
    for (var blockOffset = 0; blockOffset < blockCount; blockOffset++) {
      final valid =
          card.data.length > blockOffset && card.data[blockOffset].length == 16;
      if (!valid || blockChunk.length >= 128) await flushChunk();
      if (valid) {
        chunkStart ??= blockOffset;
        blockChunk.addAll(card.data[blockOffset]);
      }
      await asyncSleep(1);
    }
    await flushChunk();
    await communicator.setSlotTagName(
      slot,
      card.name.isEmpty ? localizations.no_name : card.name,
      TagFrequency.hf,
    );
    await communicator.saveSlotData();
    _app.changesMade();
  }

  Future<void> _arm() async {
    if (busy || recovering) return;
    final localizations = AppLocalizations.of(context)!;
    final communicator = _app.communicator;
    final observedGeneration = _captureGeneration;
    if (!_connected || communicator == null) return;
    final mode = _tab.index;
    final workSlot = _workSlot;
    if (workSlot == null) {
      _showMessage('Select a work slot');
      return;
    }

    CardSave? selectedCard;
    if (mode == 0 && _cardSource == _CardSource.saved) {
      if (_selectedCardId == null) {
        _showMessage(localizations.select_a_card);
        return;
      }
      selectedCard = _app.sharedPreferencesProvider.getCards().firstWhere(
        (card) => card.id == _selectedCardId,
      );
    } else if (mode == 0 &&
        _cardSource == _CardSource.slot &&
        _selectedSlot == null) {
      _showMessage(localizations.select_a_card);
      return;
    }

    final fixedUid = mode == 1
        ? _uidCtl.text.replaceAll(' ', '').toUpperCase()
        : '';
    if (mode == 1) {
      if (!isValidHexString(fixedUid)) {
        _showMessage(localizations.invalid_uid_bytes);
        return;
      }
      final uid = hexToBytes(fixedUid);
      if (![4, 7, 10].contains(uid.length)) {
        _showMessage(localizations.invalid_uid_bytes);
        return;
      }
    }

    final signature = switch (mode) {
      0 when _cardSource == _CardSource.saved =>
        'saved:${selectedCard!.id}:$workSlot',
      0 => 'slot:${_selectedSlot!}:$workSlot',
      1 => 'fixed:$fixedUid:${_workSlotType.value}:$workSlot',
      _ => 'random:${_workSlotType.value}:$workSlot',
    };
    final sourceUsesWorkSlot =
        mode == 0 &&
        _cardSource == _CardSource.slot &&
        _selectedSlot == workSlot;
    if (_preparedWorkSignature != signature &&
        !await _confirmWorkSlotReset(
          workSlot,
          modifiesSourceInPlace: sourceUsesWorkSlot,
        )) {
      return;
    }
    if (!mounted ||
        observedGeneration != _captureGeneration ||
        !identical(_observedCommunicator, communicator)) {
      return;
    }

    _captureGeneration++;
    final sessionGeneration = _captureGeneration;
    _captureSession = null;
    void ensureCurrentSession() {
      if (!mounted ||
          sessionGeneration != _captureGeneration ||
          !identical(_observedCommunicator, communicator)) {
        throw StateError('Device changed while preparing the work slot');
      }
    }

    setState(() => busy = true);
    var detectionEnabled = false;
    var animationEnabled = false;
    Mf1PrngType? restorePrngType;
    CardData? restoreRandomIdentity;
    try {
      await _app.runSlotOperation(() async {
        if (_preparedWorkSignature != signature) {
          _appliedTargets.clear();
          var usesSyntheticManufacturerBlock = false;
          if (mode == 0 && _cardSource == _CardSource.saved) {
            await communicator.activateSlot(workSlot);
            await _loadDumpIntoActiveSlot(communicator, selectedCard!);
          } else if (mode == 0 && _cardSource == _CardSource.slot) {
            if (_selectedSlot == workSlot) {
              await communicator.activateSlot(workSlot);
            } else {
              await _copySlotToWorkSlot(communicator, _selectedSlot!, workSlot);
            }
          } else {
            await _prepareSyntheticWorkSlot(
              communicator,
              workSlot,
              _workSlotType,
            );
            usesSyntheticManufacturerBlock = true;
          }
          ensureCurrentSession();
          _preparedWorkUsesSyntheticManufacturerBlock =
              usesSyntheticManufacturerBlock;
          _preparedWorkSignature = signature;
        } else {
          await communicator.activateSlot(workSlot);
        }
        ensureCurrentSession();

        // Refuse to capture against a slot that cannot hold the recovered keys.
        final slotTypes = await communicator.getSlotTagTypes();
        final enabledSlots = await communicator.getEnabledSlots();
        final activeSlot = await communicator.getActiveSlot();
        ensureCurrentSession();
        final bool activeIsMfc =
            activeSlot < slotTypes.length &&
            activeSlot < enabledSlots.length &&
            enabledSlots[activeSlot].hf &&
            isMifareClassic(slotTypes[activeSlot].hf);
        if (!activeIsMfc) {
          throw StateError(localizations.no_mifare_classic_slot_hint);
        }

        if (communicator.supportsCommandSync(ChameleonCommand.mf1GetPrngType) !=
            false) {
          final prngType = await communicator.getMf1PrngType();
          if (prngType == Mf1PrngType.static) {
            restorePrngType = prngType;
            await communicator.setMf1PrngType(Mf1PrngType.weak);
          }
        }
        if (mode == 2) {
          restoreRandomIdentity = await communicator.mf1GetAntiCollData();
        }

        // UID handling per mode.
        if (mode == 2) {
          await communicator.setMf1RandomUidMode(true);
        } else {
          await communicator.setMf1RandomUidMode(false);
          if (mode == 1) {
            final uid = hexToBytes(fixedUid);
            final current = await communicator.mf1GetAntiCollData();
            final scanned = _scannedCardIdentity;
            final useScanned =
                scanned != null &&
                bytesToHex(scanned.uid).toUpperCase() == fixedUid;
            await communicator.setMf1AntiCollision(
              CardData(
                uid: uid,
                atqa: useScanned ? scanned.atqa : current.atqa,
                sak: useScanned ? scanned.sak : current.sak,
                ats: useScanned ? scanned.ats : current.ats,
              ),
            );
            if (_preparedWorkUsesSyntheticManufacturerBlock &&
                uid.length == 4) {
              final blockZero = await communicator.mf1GetEmulatorBlock(0, 1);
              await communicator.setMf1BlockData(
                0,
                applyUidToSyntheticManufacturerBlock(
                  block: blockZero,
                  uid: uid,
                ),
              );
              await communicator.saveSlotData();
              _app.changesMade();
            }
          }
        }
        ensureCurrentSession();

        // Force the device into emulator/tag mode. Without this, if the device
        // was left in reader mode (the default after any HF read/scan/autopwn) it
        // never emulates a card, so no reader ever authenticates against it and
        // zero nonces are captured. Only the saved-card path set this before (via
        // _loadDumpIntoActiveSlot); slot / fixed-UID / random modes did not.
        await communicator.setReaderDeviceMode(false);

        await communicator.setMf1DetectionStatus(true);
        detectionEnabled = true;
        await communicator.setMf1ReaderKeysAnim(true);
        animationEnabled = true;
        ensureCurrentSession();
        setState(() {
          _captureSession = _ReaderKeyCaptureSession(
            generation: sessionGeneration,
            communicator: communicator,
            workSlot: workSlot,
            autoApply: mode != 2,
            automatic: _automaticCapture && mode != 2,
            restorePrngType: restorePrngType,
            restoreRandomIdentity: restoreRandomIdentity,
          );
          armed = true;
          detectionCount = 0;
          _resetDetectionLedger();
          _sessionDictionaryId = null;
          _sessionDictionaryName = _readerDictionaryName(DateTime.now());
          _sessionKeyHexes.clear();
        });
        _startPolling();
      });
    } catch (e) {
      if (animationEnabled) {
        try {
          await communicator.setMf1ReaderKeysAnim(false);
        } catch (_) {}
      }
      if (detectionEnabled) {
        try {
          await communicator.setMf1DetectionStatus(false);
        } catch (_) {}
      }
      try {
        await communicator.setMf1RandomUidMode(false);
      } catch (_) {}
      if (restoreRandomIdentity != null) {
        try {
          await communicator.setMf1AntiCollision(restoreRandomIdentity!);
        } catch (_) {}
      }
      if (restorePrngType != null) {
        try {
          await communicator.setMf1PrngType(restorePrngType!);
        } catch (_) {}
      }
      if (mounted &&
          sessionGeneration == _captureGeneration &&
          identical(_observedCommunicator, communicator)) {
        _showMessage(e.toString());
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _stop() async {
    final recoverySession = _captureSession;
    if (recoverySession == null) {
      if (mounted) setState(() => armed = false);
      return;
    }
    final communicator = recoverySession.communicator;
    setState(() => busy = true);
    _pollTimer?.cancel();
    Object? cleanupError;
    try {
      // Current firmware preserves the log when detection is disabled. Freeze
      // capture first so count and paged records form one stable snapshot.
      for (final cleanup in <Future<void> Function()>[
        () => communicator.setMf1ReaderKeysAnim(false),
        () => communicator.setMf1DetectionStatus(false),
        () => _restoreCaptureConfiguration(recoverySession),
      ]) {
        try {
          await cleanup();
        } catch (error) {
          cleanupError ??= error;
        }
      }
      await _recoverKeys(recoverySession);
      if (cleanupError != null &&
          recoverySession.generation == _captureGeneration &&
          identical(_observedCommunicator, communicator)) {
        _showMessage(cleanupError.toString());
      }
    } catch (e) {
      if (recoverySession.generation == _captureGeneration &&
          identical(_observedCommunicator, communicator)) {
        _showMessage(e.toString());
      }
    } finally {
      if (mounted &&
          recoverySession.generation == _captureGeneration &&
          identical(_observedCommunicator, communicator)) {
        setState(() {
          armed = false;
          busy = false;
          _captureSession = null;
        });
      }
    }
  }

  Future<void> _persistSessionKeys(
    Iterable<ReaderKeyRecoveryResult> results,
    bool Function() isCurrentSession,
  ) async {
    final pending = <String, Uint8List>{};
    for (final result in results) {
      final key = result.key;
      if (key == null) continue;
      final hex = bytesToHex(key).toUpperCase();
      if (!_sessionKeyHexes.contains(hex)) pending[hex] = key;
    }
    if (pending.isEmpty) return;

    final provider = _app.sharedPreferencesProvider;
    final dictionaries = List<Dictionary>.from(provider.getDictionaries());
    var index = _sessionDictionaryId == null
        ? -1
        : dictionaries.indexWhere((item) => item.id == _sessionDictionaryId);
    if (index < 0) {
      final dictionary = Dictionary(
        name: _sessionDictionaryName ?? _readerDictionaryName(DateTime.now()),
        color: Colors.blue,
        keys: List<Uint8List>.from(pending.values),
        keyLength: 12,
      );
      dictionaries.add(dictionary);
      _sessionDictionaryId = dictionary.id;
      _sessionDictionaryName = dictionary.name;
    } else {
      final dictionary = dictionaries[index];
      final merged = <String, Uint8List>{
        for (final key in dictionary.keys)
          bytesToHex(key).toUpperCase(): Uint8List.fromList(key),
        ...pending,
      };
      dictionaries[index] = Dictionary(
        id: dictionary.id,
        name: dictionary.name,
        color: dictionary.color,
        keys: List<Uint8List>.from(merged.values),
        keyLength: 12,
      );
    }

    await provider.setDictionaries(dictionaries);
    if (!isCurrentSession()) return;
    _sessionKeyHexes.addAll(pending.keys);
    _app.changesMade();
    if (mounted) setState(() {});
  }

  Future<void> _applyRecoveredKeys(
    Iterable<ReaderKeyRecoveryResult> results,
    _ReaderKeyCaptureSession session,
  ) async {
    if (!session.autoApply ||
        session.generation != _captureGeneration ||
        !identical(_app.communicator, session.communicator)) {
      return;
    }
    final workSlot = session.workSlot;
    final pending = results
        .where(
          (result) =>
              result.key != null && !_appliedTargets.contains(result.target),
        )
        .toList();
    if (pending.isEmpty) return;

    await _app.runSlotOperation(() async {
      final communicator = session.communicator;
      await communicator.activateSlot(workSlot);
      final types = await communicator.getSlotTagTypes();
      if (workSlot >= types.length || !isMifareClassic(types[workSlot].hf)) {
        throw StateError('Work slot is no longer MIFARE Classic');
      }
      final blockCount = mfClassicGetBlockCount(
        chameleonTagTypeGetMfClassicType(types[workSlot].hf),
      );
      var changed = false;
      for (final result in pending) {
        if (session.generation != _captureGeneration ||
            !identical(_app.communicator, communicator)) {
          throw StateError('Reader-key capture session changed');
        }
        final trailerBlock = readerKeySectorTrailerBlock(result.target.sector);
        if (trailerBlock >= blockCount) continue;
        final trailer = await communicator.mf1GetEmulatorBlock(trailerBlock, 1);
        final patched = applyReaderKeyToTrailer(
          trailer: trailer,
          key: result.key!,
          keyB: result.target.keyB,
        );
        await communicator.setMf1BlockData(trailerBlock, patched);
        _appliedTargets.add(result.target);
        changed = true;
      }
      if (changed) {
        if (session.generation != _captureGeneration ||
            !identical(_app.communicator, communicator)) {
          throw StateError('Reader-key capture session changed');
        }
        await communicator.saveSlotData();
        _app.changesMade();
        if (session.automatic) {
          if (communicator.supportsCommandSync(
                ChameleonCommand.mf1ReaderKeysReselect,
              ) !=
              false) {
            await communicator.reselectMf1ReaderKeys();
          } else {
            // Legacy fallback reloads the slot and starts a fresh device log;
            // the host ledger already retained every downloaded transcript.
            await communicator.activateSlot(workSlot);
            await communicator.setMf1DetectionStatus(true);
            await communicator.setMf1ReaderKeysAnim(true);
            _deviceDetectionCursor = 0;
          }
        }
      }
    });
    if (mounted) setState(() {});
  }

  Future<void> _recoverKeys([_ReaderKeyCaptureSession? requestedSession]) {
    final communicator = requestedSession?.communicator ?? _app.communicator;
    if (communicator == null) return Future.value();
    final session =
        requestedSession ??
        _captureSession ??
        _ReaderKeyCaptureSession(
          generation: _captureGeneration,
          communicator: communicator,
          workSlot: _workSlot ?? 0,
          autoApply: false,
          automatic: false,
        );
    final active = _activeRecovery;
    final activeSession = _activeRecoverySession;
    if (active != null && activeSession != null) {
      if (activeSession.generation == session.generation &&
          identical(activeSession.communicator, session.communicator)) {
        return active;
      }
      return active.then((_) => _recoverKeys(session));
    }
    final operation = _runRecovery(session);
    _activeRecovery = operation;
    _activeRecoverySession = session;
    unawaited(
      operation.whenComplete(() {
        if (identical(_activeRecovery, operation)) {
          _activeRecovery = null;
          _activeRecoverySession = null;
        }
      }),
    );
    return operation;
  }

  Future<void> _runRecovery(_ReaderKeyCaptureSession session) async {
    final communicator = session.communicator;
    final generation = session.generation;

    bool isCurrentSession() =>
        mounted &&
        generation == _captureGeneration &&
        identical(_observedCommunicator, communicator);

    setState(() {
      recovering = true;
      progress = 0;
    });
    try {
      final count = await communicator.getMf1DetectionCount();
      await _syncDetectionLedger(communicator, count);
      final detections = List<DetectionResult>.from(_detectionLedger);
      if (!isCurrentSession()) return;
      _lastRecoveryFingerprint = readerKeyEvidenceFingerprint(detections);
      final results = await recoverReaderKeys(
        detections: detections,
        solver: (request) async {
          final recovered = await recovery.mfkey32(request);
          return recovered.isEmpty ? null : recovered.first;
        },
        isCancelled: () => !isCurrentSession(),
        onProgress: (completed, total, _) {
          if (isCurrentSession()) {
            setState(
              () => progress = total == 0
                  ? 100
                  : (completed * 100 / total).round(),
            );
          }
        },
      );
      if (!isCurrentSession()) return;
      final mergedResults = Map<ReaderKeyTarget, ReaderKeyRecoveryResult>.from(
        recoveryResults,
      );
      for (final result in results) {
        final previous = mergedResults[result.target];
        if (result.key != null || previous?.key == null) {
          mergedResults[result.target] = result;
        }
      }
      final unique = <String, Uint8List>{};
      for (final result in mergedResults.values) {
        if (result.key != null) {
          unique[bytesToHex(result.key!).toUpperCase()] = result.key!;
        }
      }
      setState(() {
        recoveryResults
          ..clear()
          ..addAll(mergedResults);
        keys
          ..clear()
          ..addAll(unique.values);
        final recovered = recoveryResults.values
            .where((result) => result.key != null)
            .toList();
        if (recovered.isNotEmpty) {
          outputUid = recovered.first.target.uid
              .toRadixString(16)
              .padLeft(8, '0')
              .toUpperCase();
        }
      });
      try {
        await _persistSessionKeys(
          session.autoApply
              ? results.where((result) => result.verifiedByReader)
              : results,
          isCurrentSession,
        );
      } catch (error) {
        if (isCurrentSession()) {
          _showMessage('Recovered keys could not be saved: $error');
        }
      }
      if (isCurrentSession()) {
        try {
          await _applyRecoveredKeys(results, session);
        } catch (error) {
          if (isCurrentSession()) {
            _showMessage(
              'Recovered keys were saved but not loaded into the work slot: $error',
            );
          }
        }
      }
    } catch (e) {
      if (isCurrentSession()) _showMessage(e.toString());
    } finally {
      if (mounted) {
        setState(() {
          recovering = false;
          progress = -1;
        });
      }
    }
  }

  // Save the recovered keys straight into the app's dictionary storage, with a
  // name. This is the simple path; DictionaryExportMenu still offers file export
  // and adding to an existing dictionary.
  Future<void> _saveRecoveredKeysDialog() async {
    final localizations = AppLocalizations.of(context)!;
    final appState = context.read<ChameleonGUIState>();
    final deduped = <String, Uint8List>{
      for (var k in keys.where((k) => k.isNotEmpty)) bytesToHex(k): k,
    }.values.toList();
    final nameCtl = TextEditingController(
      text: outputUid.isEmpty ? 'reader-keys' : 'reader-$outputUid',
    );
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(localizations.save_recovered_keys),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: nameCtl,
              autofocus: true,
              decoration: InputDecoration(
                labelText: localizations.enter_name_of_dictionary,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            Text("${deduped.length} keys"),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(localizations.cancel),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              showDialog<String>(
                context: context,
                builder: (_) =>
                    DictionaryExportMenu(defaultName: outputUid, keys: keys),
              );
            },
            child: Text(localizations.save_recovered_keys_to_file),
          ),
          ElevatedButton.icon(
            icon: const Icon(Icons.save),
            onPressed: () async {
              final name = nameCtl.text.trim();
              if (name.isEmpty) return;
              final dicts = appState.sharedPreferencesProvider
                  .getDictionaries();
              // MFKey32 keys are 6 bytes -> keyLength 12 (hex chars), so the
              // dictionary shows up in the MIFARE Classic pickers that filter
              // by keyLength; without it the keys save but stay invisible.
              dicts.add(
                Dictionary(
                  name: name,
                  color: Colors.blue,
                  keys: deduped,
                  keyLength: deduped.isNotEmpty ? deduped.first.length * 2 : 12,
                ),
              );
              await appState.sharedPreferencesProvider.setDictionaries(dicts);
              appState.changesMade();
              if (!ctx.mounted) return;
              Navigator.pop(ctx);
              _showMessage('✓ $name (${deduped.length} keys)');
            },
            label: Text(localizations.save_recovered_keys),
          ),
        ],
      ),
    );
    nameCtl.dispose();
  }

  // ---- Per-mode configuration widgets ----

  Widget _buildWorkSlotConfig() {
    final localizations = AppLocalizations.of(context)!;
    final syntheticMode = _tab.index != 0;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Work slot',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            const Text(
              'Recovered keys are written here so the next reader attempt can authenticate. '
              'Preparing the slot replaces its HF data.',
              style: TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<int>(
              initialValue: _workSlot,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: 'MIFARE Classic work slot',
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.build_circle_outlined),
              ),
              items: _workSlots
                  .map(
                    (entry) => DropdownMenuItem<int>(
                      value: entry.index,
                      child: Text(
                        '${localizations.slot} ${entry.index + 1}: ${entry.label}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  )
                  .toList(),
              onChanged: (armed || recovering)
                  ? null
                  : (value) => setState(() {
                      _workSlot = value;
                      _resetWorkPreparation();
                    }),
            ),
            if (syntheticMode) ...[
              const SizedBox(height: 10),
              DropdownButtonFormField<TagType>(
                initialValue: _workSlotType,
                decoration: const InputDecoration(
                  labelText: 'Synthetic card size',
                  border: OutlineInputBorder(),
                ),
                items: const [TagType.mifare1K, TagType.mifare4K]
                    .map(
                      (type) => DropdownMenuItem(
                        value: type,
                        child: Text(
                          type == TagType.mifare4K
                              ? 'MIFARE Classic 4K'
                              : 'MIFARE Classic 1K',
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (armed || recovering)
                    ? null
                    : (value) {
                        if (value == null) return;
                        setState(() {
                          _workSlotType = value;
                          _resetWorkPreparation();
                        });
                      },
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildCardConfig() {
    var localizations = AppLocalizations.of(context)!;
    final cards = _app.sharedPreferencesProvider
        .getCards()
        .where((c) => isMifareClassic(c.tag))
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: (armed || recovering || busy) ? null : _scanSourceCard,
            icon: const Icon(Icons.contactless),
            label: const Text('Scan card and configure automatically'),
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'Read the card once, then place the Chameleon on the reader. Recovery, key loading and reader retries run automatically.',
          style: TextStyle(fontSize: 12),
        ),
        const SizedBox(height: 12),
        SegmentedButton<_CardSource>(
          segments: [
            ButtonSegment(
              value: _CardSource.saved,
              icon: const Icon(Icons.sd_card),
              label: Text(localizations.simulated_card),
            ),
            ButtonSegment(
              value: _CardSource.slot,
              icon: const Icon(Icons.widgets),
              label: Text(localizations.slot_manager),
            ),
          ],
          selected: {_cardSource},
          onSelectionChanged: (armed || recovering)
              ? null
              : (s) => setState(() {
                  _cardSource = s.first;
                  _resetWorkPreparation();
                }),
        ),
        const SizedBox(height: 12),
        if (_cardSource == _CardSource.saved)
          DropdownButtonFormField<String?>(
            initialValue: _selectedCardId,
            isExpanded: true,
            decoration: InputDecoration(
              labelText: localizations.simulated_card,
              border: const OutlineInputBorder(),
            ),
            items: cards
                .map(
                  (c) => DropdownMenuItem<String?>(
                    value: c.id,
                    child: Text(
                      c.name.isEmpty ? c.uid.toUpperCase() : c.name,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                )
                .toList(),
            onChanged: (armed || recovering)
                ? null
                : (v) => setState(() {
                    _selectedCardId = v;
                    _resetWorkPreparation();
                  }),
          )
        else ...[
          DropdownButtonFormField<int?>(
            initialValue: _selectedSlot,
            isExpanded: true,
            decoration: InputDecoration(
              labelText: localizations.slot_manager,
              border: const OutlineInputBorder(),
            ),
            items: _slots
                .map(
                  (e) => DropdownMenuItem<int?>(
                    value: e.index,
                    child: Text(
                      "${localizations.slot} ${e.index + 1}: ${e.label}",
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                )
                .toList(),
            onChanged: (armed || recovering)
                ? null
                : (v) {
                    if (v != null) _onSlotSelected(v);
                  },
          ),
          if (_selectedSlotUid.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6.0),
              child: Text(
                "UID: $_selectedSlotUid",
                style: const TextStyle(fontFamily: 'RobotoMono'),
              ),
            ),
        ],
      ],
    );
  }

  Widget _buildFixedUidConfig() {
    var localizations = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _uidCtl,
                enabled: !armed && !recovering,
                onChanged: (_) {
                  _scannedCardIdentity = null;
                  _resetWorkPreparation();
                },
                decoration: InputDecoration(
                  labelText: localizations.uid,
                  hintText: "DEADBEEF",
                  border: const OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: (armed || recovering)
                  ? null
                  : () => setState(() {
                      _uidCtl.text = _randomUidHex();
                      _resetWorkPreparation();
                    }),
              icon: const Icon(Icons.casino),
              label: Text(localizations.random_uid),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildRandomConfig() {
    var localizations = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          localizations.random_uid_warning,
          style: TextStyle(
            color: Theme.of(context).colorScheme.error,
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          _currentRandomUid.isEmpty ? "UID: —" : "UID: $_currentRandomUid",
          style: const TextStyle(
            fontFamily: 'RobotoMono',
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  List<Widget> _buildRecoveryResults() {
    if (recoveryResults.isEmpty) return const [];
    final results = recoveryResults.values.toList()
      ..sort((a, b) {
        final uidOrder = a.target.uid.compareTo(b.target.uid);
        if (uidOrder != 0) return uidOrder;
        final sectorOrder = a.target.sector.compareTo(b.target.sector);
        if (sectorOrder != 0) return sectorOrder;
        return a.target.keyB == b.target.keyB ? 0 : (a.target.keyB ? 1 : -1);
      });
    final recovered = results.where((result) => result.key != null).length;

    String failureText(ReaderKeyRecoveryResult result) {
      return switch (result.failure) {
        ReaderKeyRecoveryFailure.needsMoreRecords =>
          'Needs another authentication capture',
        ReaderKeyRecoveryFailure.noKey =>
          'No valid key from ${result.attemptedPairs} candidate pairs',
        ReaderKeyRecoveryFailure.solverError =>
          result.error ?? 'Recovery solver error',
        ReaderKeyRecoveryFailure.cancelled => 'Recovery cancelled',
        null => '',
      };
    }

    return [
      Padding(
        padding: const EdgeInsets.only(top: 12, bottom: 4),
        child: Text(
          'Recovered $recovered/${results.length} sector keys '
          '(${keys.length} unique values)',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      for (final result in results)
        Builder(
          builder: (context) {
            final uid = result.target.uid
                .toRadixString(16)
                .padLeft(8, '0')
                .toUpperCase();
            final keyHex = result.key == null
                ? null
                : bytesToHex(result.key!).toUpperCase();
            final blockList = result.blocks.toList()..sort();
            return Card(
              clipBehavior: Clip.antiAlias,
              child: ListTile(
                dense: true,
                leading: Icon(
                  keyHex == null ? Icons.key_off : Icons.vpn_key,
                  color: keyHex == null ? null : Colors.green,
                ),
                title: Text(
                  keyHex ?? failureText(result),
                  style: TextStyle(
                    fontFamily: keyHex == null ? null : 'RobotoMono',
                    fontSize: keyHex == null ? null : 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                subtitle: Text(
                  'UID $uid | sector ${result.target.sector} | key ${result.target.keyType} | '
                  'blocks ${blockList.join(', ')} | ${result.transcriptCount} transcripts'
                  '${result.verifiedByReader
                      ? ' | verified by reader'
                      : keyHex == null
                      ? ''
                      : ' | awaiting reader verification'}',
                ),
                trailing: keyHex == null
                    ? null
                    : const Icon(Icons.copy, size: 18),
                onTap: keyHex == null
                    ? null
                    : () {
                        Clipboard.setData(ClipboardData(text: keyHex));
                        _showMessage('$keyHex copied');
                      },
              ),
            );
          },
        ),
    ];
  }

  Widget _buildCaptureSection() {
    var localizations = AppLocalizations.of(context)!;
    return Column(
      children: [
        SwitchListTile.adaptive(
          value: _automaticCapture,
          onChanged: (armed || recovering || busy)
              ? null
              : (value) => setState(() => _automaticCapture = value),
          title: const Text('Automatic recovery and reader retry'),
          subtitle: const Text(
            'Downloads only new transcripts, applies recovered keys, re-presents the emulated card and stops after convergence.',
          ),
          secondary: const Icon(Icons.auto_mode),
        ),
        _buildCaptureGuidance(),
        const SizedBox(height: 16),
        Center(
          child: ElevatedButton.icon(
            onPressed: busy || (!armed && recovering)
                ? null
                : (armed ? _stop : _arm),
            icon: Icon(armed ? Icons.stop : Icons.wifi_tethering),
            label: Text(
              armed ? localizations.stop_capture : localizations.arm_capture,
            ),
          ),
        ),
        const SizedBox(height: 10),
        if (armed) ...[
          Text(
            localizations.capture_armed_hint,
            textAlign: TextAlign.center,
            style: const TextStyle(fontStyle: FontStyle.italic),
          ),
          const SizedBox(height: 6),
          Text(
            localizations.captured_auth_attempts(detectionCount),
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          if (detectionCount >= 1000)
            Text(
              'Capture buffer is full. Stop and recover before starting a new session.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          const SizedBox(height: 10),
        ],
        ElevatedButton(
          onPressed: (recovering || detectionCount <= 0) ? null : _recoverKeys,
          child: Text(localizations.recover_keys_nonce(detectionCount)),
        ),
        if (progress != -1) ...[
          const SizedBox(height: 8),
          LinearProgressIndicator(value: progress / 100),
        ],
        if (recovering)
          Padding(
            padding: const EdgeInsets.only(top: 8.0),
            child: Text(localizations.recovery_in_progress),
          ),
        if (_sessionDictionaryName != null && _sessionKeyHexes.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'Auto-saved ${_sessionKeyHexes.length} unique key(s) to '
              '${_sessionDictionaryName!}.',
              textAlign: TextAlign.center,
            ),
          ),
        if (_appliedTargets.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              '${_appliedTargets.length} sector key(s) loaded into work slot '
              '${(_workSlot ?? 0) + 1}. Present the Chameleon again; the next '
              'authentication can now complete.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        if (_tab.index == 2 && keys.isNotEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text(
              'Keys are saved, but cannot be auto-applied while the UID changes '
              'on every reader activation. Use a fixed UID for learn-and-retry.',
              textAlign: TextAlign.center,
            ),
          ),
        ..._buildRecoveryResults(),
        if (keys.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8.0),
            child: ElevatedButton.icon(
              onPressed: _saveRecoveredKeysDialog,
              icon: const Icon(Icons.save),
              label: Text(localizations.save_recovered_keys),
            ),
          ),
      ],
    );
  }

  Widget _buildCaptureGuidance() {
    final guidance = readerKeyGuidanceFor(
      connected: _connected,
      armed: armed,
      busy: busy,
      recovering: recovering,
      randomUid: _tab.index == 2,
      detectionCount: detectionCount,
      resultCount: recoveryResults.length,
      appliedTargetCount: _appliedTargets.length,
      automatic: _automaticCapture && _tab.index != 2,
    );
    final colorScheme = Theme.of(context).colorScheme;
    final (background, foreground) = switch (guidance.tone) {
      ReaderKeyGuidanceTone.success => (
        colorScheme.primaryContainer,
        colorScheme.onPrimaryContainer,
      ),
      ReaderKeyGuidanceTone.warning => (
        colorScheme.tertiaryContainer,
        colorScheme.onTertiaryContainer,
      ),
      ReaderKeyGuidanceTone.danger => (
        colorScheme.errorContainer,
        colorScheme.onErrorContainer,
      ),
      ReaderKeyGuidanceTone.neutral => (
        colorScheme.surfaceContainerHighest,
        colorScheme.onSurface,
      ),
    };
    final icon = switch (guidance.step) {
      ReaderKeyGuidanceStep.unavailable => Icons.usb_off,
      ReaderKeyGuidanceStep.ready => Icons.tune,
      ReaderKeyGuidanceStep.preparing => Icons.settings_suggest,
      ReaderKeyGuidanceStep.approach => Icons.contactless,
      ReaderKeyGuidanceStep.remove => Icons.back_hand,
      ReaderKeyGuidanceStep.processing => Icons.sync,
      ReaderKeyGuidanceStep.repeat => Icons.repeat,
      ReaderKeyGuidanceStep.complete => Icons.check_circle,
    };

    return Semantics(
      container: true,
      liveRegion: true,
      excludeSemantics: true,
      label: '${guidance.title}. ${guidance.description}',
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: background,
          border: Border.all(color: foreground, width: 2),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: foreground, size: 36),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'PASO ACTUAL',
                    style: TextStyle(
                      color: foreground,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    guidance.title,
                    style: TextStyle(
                      color: foreground,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    guidance.description,
                    style: TextStyle(color: foreground, fontSize: 15),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    var localizations = AppLocalizations.of(context)!;
    context.watch<ChameleonGUIState>();

    Widget modeConfig;
    switch (_tab.index) {
      case 1:
        modeConfig = _buildFixedUidConfig();
        break;
      case 2:
        modeConfig = _buildRandomConfig();
        break;
      default:
        modeConfig = _buildCardConfig();
    }

    return Scaffold(
      appBar: AppBar(title: Text(localizations.reader_keys_capture)),
      body: !_connected
          ? Center(child: Text(localizations.no_device))
          : Column(
              children: [
                // Capture mode tabs — disabled while capturing.
                IgnorePointer(
                  ignoring: armed || recovering,
                  child: Opacity(
                    opacity: armed || recovering ? 0.5 : 1.0,
                    child: TabBar(
                      controller: _tab,
                      tabs: [
                        Tab(text: localizations.simulated_card),
                        Tab(text: localizations.fixed_uid),
                        Tab(text: localizations.random_uid),
                      ],
                    ),
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      children: [
                        _buildWorkSlotConfig(),
                        const SizedBox(height: 12),
                        modeConfig,
                        const Divider(height: 32),
                        _buildCaptureSection(),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

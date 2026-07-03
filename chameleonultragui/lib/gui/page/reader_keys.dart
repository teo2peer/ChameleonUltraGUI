import 'dart:async';
import 'dart:math';

import 'package:chameleonultragui/gui/menu/dialogs/dictionary/export.dart';
import 'package:chameleonultragui/helpers/definitions.dart';
import 'package:chameleonultragui/helpers/general.dart';
import 'package:chameleonultragui/helpers/mifare_classic/general.dart';
import 'package:chameleonultragui/main.dart';
import 'package:chameleonultragui/recovery/recovery.dart' as recovery;
import 'package:chameleonultragui/recovery/recovery.dart';
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

// Reader-key capture (MFKey32). The capture source is chosen with the tabs at
// the top: emulate a saved/slot card, a fixed UID, or a device-generated random
// UID. Below, Start capture arms the device and recovered keys are shown/saved.
class ReaderKeysPage extends StatefulWidget {
  const ReaderKeysPage({super.key});

  @override
  ReaderKeysPageState createState() => ReaderKeysPageState();
}

class ReaderKeysPageState extends State<ReaderKeysPage>
    with SingleTickerProviderStateMixin {
  late TabController _tab;

  // Card mode
  _CardSource _cardSource = _CardSource.saved;
  String? _selectedCardId;
  int? _selectedSlot;
  String _selectedSlotUid = '';
  List<_SlotEntry> _slots = [];

  // Fixed UID mode
  final TextEditingController _uidCtl = TextEditingController();

  // Random mode
  String _currentRandomUid = '';

  // Capture / recovery
  bool armed = false;
  bool busy = false;
  bool recovering = false;
  int detectionCount = 0;
  final List<Uint8List> keys = [];
  final List<Widget> displayKeys = [];
  final Set<int> seenKeyHashes = {};
  String outputUid = "";
  int progress = -1;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 3, vsync: this);
    _tab.addListener(() => setState(() {}));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refreshStatus();
      _loadSlots();
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _tab.dispose();
    _uidCtl.dispose();
    super.dispose();
  }

  ChameleonGUIState get _app => context.read<ChameleonGUIState>();
  bool get _connected => _app.connector?.connected ?? false;

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 2), (_) => _refreshCount());
  }

  Future<void> _refreshStatus() async {
    if (!_connected) return;
    try {
      final isArmed = await _app.communicator!.isMf1DetectionMode();
      final count = await _app.communicator!.getMf1DetectionCount();
      if (!mounted) return;
      setState(() {
        armed = isArmed;
        detectionCount = count;
      });
      if (isArmed) _startPolling();
    } catch (_) {}
  }

  Future<void> _refreshCount() async {
    if (!_connected) return;
    try {
      final count = await _app.communicator!.getMf1DetectionCount();
      String uid = _currentRandomUid;
      if (_tab.index == 2) {
        try {
          final ac = await _app.communicator!.mf1GetAntiCollData();
          uid = bytesToHex(ac.uid).toUpperCase();
        } catch (_) {}
      }
      if (mounted) {
        setState(() {
          detectionCount = count;
          _currentRandomUid = uid;
        });
      }
    } catch (_) {}
  }

  Future<void> _loadSlots() async {
    if (!_connected) return;
    try {
      final names = await _app.communicator!.getSlotTagNames();
      final types = await _app.communicator!.getSlotTagTypes();
      final slots = <_SlotEntry>[];
      for (int i = 0; i < 8 && i < types.length; i++) {
        if (isMifareClassic(types[i].hf)) {
          final name = (i < names.length) ? names[i].hf : '';
          slots.add(_SlotEntry(
              i, name.isEmpty ? types[i].hf.name : name));
        }
      }
      if (mounted) setState(() => _slots = slots);
    } catch (_) {}
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
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

  Future<void> _onSlotSelected(int index) async {
    setState(() {
      _selectedSlot = index;
      _selectedSlotUid = '';
    });
    if (!_connected) return;
    try {
      await _app.communicator!.activateSlot(index);
      final ac = await _app.communicator!.mf1GetAntiCollData();
      if (mounted) {
        setState(() => _selectedSlotUid = bytesToHex(ac.uid).toUpperCase());
      }
    } catch (_) {}
  }

  Future<void> _loadDumpIntoActiveSlot(CardSave card) async {
    final localizations = AppLocalizations.of(context)!;
    final slot = await _app.communicator!.getActiveSlot();
    var tag = card.tag;
    if (chameleonTagSaveCheckForMifareClassicEV1(card)) {
      tag = TagType.mifare2K;
    }
    await _app.communicator!.setReaderDeviceMode(false);
    await _app.communicator!.enableSlot(slot, TagFrequency.hf, true);
    await _app.communicator!.activateSlot(slot);
    await _app.communicator!.setSlotType(slot, tag);
    await _app.communicator!.setDefaultDataToSlot(slot, tag);
    await _app.communicator!.setMf1AntiCollision(CardData(
        uid: hexToBytes(card.uid),
        atqa: card.atqa,
        sak: card.sak,
        ats: card.ats));

    List<int> blockChunk = [];
    int lastSend = 0;
    final blockCount =
        mfClassicGetBlockCount(chameleonTagTypeGetMfClassicType(tag));
    for (var blockOffset = 0; blockOffset < blockCount; blockOffset++) {
      if ((card.data.length > blockOffset && card.data[blockOffset].isEmpty) ||
          blockChunk.length >= 128) {
        if (blockChunk.isNotEmpty) {
          await _app.communicator!
              .setMf1BlockData(lastSend, Uint8List.fromList(blockChunk));
          blockChunk = [];
          lastSend = blockOffset;
        }
      }
      if (card.data.length > blockOffset &&
          card.data[blockOffset].length == 16) {
        blockChunk.addAll(card.data[blockOffset]);
      }
      await asyncSleep(1);
    }
    if (blockChunk.isNotEmpty) {
      await _app.communicator!
          .setMf1BlockData(lastSend, Uint8List.fromList(blockChunk));
    }
    await _app.communicator!.setSlotTagName(slot,
        card.name.isEmpty ? localizations.no_name : card.name, TagFrequency.hf);
    await _app.communicator!.saveSlotData();
    _app.changesMade();
  }

  Future<void> _arm() async {
    final localizations = AppLocalizations.of(context)!;
    setState(() => busy = true);
    try {
      final mode = _tab.index; // 0 card, 1 fixed UID, 2 random

      // Establish which card / slot is emulated.
      if (mode == 0 && _cardSource == _CardSource.saved) {
        if (_selectedCardId == null) {
          _showMessage(localizations.select_a_card);
          setState(() => busy = false);
          return;
        }
        final card = _app.sharedPreferencesProvider
            .getCards()
            .firstWhere((c) => c.id == _selectedCardId);
        await _loadDumpIntoActiveSlot(card);
      } else if (mode == 0 && _cardSource == _CardSource.slot) {
        if (_selectedSlot == null) {
          _showMessage(localizations.select_a_card);
          setState(() => busy = false);
          return;
        }
        await _app.communicator!.activateSlot(_selectedSlot!);
      }

      // The active slot must be MIFARE Classic. In Fixed-UID / Random modes we
      // reuse whatever slot is active, so if it isn't MFC, fall back to any
      // configured MIFARE Classic slot instead of failing.
      final slotTypes = await _app.communicator!.getSlotTagTypes();
      final activeSlot = await _app.communicator!.getActiveSlot();
      final bool activeIsMfc = activeSlot < slotTypes.length &&
          isMifareClassic(slotTypes[activeSlot].hf);
      if (!activeIsMfc) {
        final int mfcSlot = slotTypes
            .indexWhere((t) => isMifareClassic(t.hf));
        if (mfcSlot < 0) {
          _showMessage(localizations.no_mifare_classic_slot_hint);
          setState(() => busy = false);
          return;
        }
        await _app.communicator!.activateSlot(mfcSlot);
      }

      // UID handling per mode.
      if (mode == 2) {
        await _app.communicator!.setMf1RandomUidMode(true);
      } else {
        await _app.communicator!.setMf1RandomUidMode(false);
        if (mode == 1) {
          final uid = hexToBytes(_uidCtl.text.replaceAll(' ', ''));
          if (![4, 7, 10].contains(uid.length)) {
            _showMessage(localizations.invalid_uid_bytes);
            setState(() => busy = false);
            return;
          }
          final current = await _app.communicator!.mf1GetAntiCollData();
          await _app.communicator!.setMf1AntiCollision(CardData(
              uid: uid,
              atqa: current.atqa,
              sak: current.sak,
              ats: current.ats));
        }
      }

      await _app.communicator!.setMf1DetectionStatus(true);
      await _app.communicator!.setMf1ReaderKeysAnim(true);
      if (!mounted) return;
      setState(() {
        armed = true;
        detectionCount = 0;
      });
      _startPolling();
    } catch (e) {
      _showMessage(e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _stop() async {
    setState(() => busy = true);
    _pollTimer?.cancel();
    try {
      await _app.communicator!.setMf1ReaderKeysAnim(false);
      await _app.communicator!.setMf1DetectionStatus(false);
      await _app.communicator!.setMf1RandomUidMode(false);
    } catch (e) {
      _showMessage(e.toString());
    } finally {
      if (mounted) {
        setState(() {
          armed = false;
          busy = false;
        });
      }
    }
  }

  Future<void> _recoverKeys() async {
    setState(() {
      recovering = true;
      displayKeys.clear();
      seenKeyHashes.clear();
      keys.clear();
    });
    try {
      final count = await _app.communicator!.getMf1DetectionCount();
      final detections =
          await _app.communicator!.getMf1DetectionResult(count);
      for (var uidEntry in detections.entries) {
        var uid = uidEntry.key;
        for (var blockEntry in uidEntry.value.entries) {
          var block = blockEntry.key;
          for (var keyEntry in blockEntry.value.entries) {
            var keyType = keyEntry.key;
            var records = keyEntry.value;
            for (var i = 0; i < records.length; i++) {
              for (var j = i + 1; j < records.length; j++) {
                var mfkey = Mfkey32Dart(
                  uid: uid,
                  nt0: records[i].nt,
                  nt1: records[j].nt,
                  nr0Enc: records[i].nr,
                  ar0Enc: records[i].ar,
                  nr1Enc: records[j].nr,
                  ar1Enc: records[j].ar,
                );
                var recovered = await recovery.mfkey32(mfkey);
                var keyBytes = u64ToBytes(recovered[0]).sublist(2, 8);
                var hash = Object.hashAll(keyBytes);
                outputUid =
                    bytesToHex(u64ToBytes(uid).sublist(4, 8)).toUpperCase();
                if (!seenKeyHashes.contains(hash)) {
                  seenKeyHashes.add(hash);
                  keys.add(keyBytes);
                  var keyHex = bytesToHex(keyBytes).toUpperCase();
                  displayKeys.add(Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2.0),
                    child: Row(
                      children: [
                        Text("$outputUid  ",
                            style: const TextStyle(
                                fontSize: 16, fontWeight: FontWeight.bold)),
                        Expanded(
                          child: TextButton(
                            onPressed: () async {
                              await Clipboard.setData(
                                  ClipboardData(text: keyHex));
                            },
                            child: Text("block $block key $keyType: $keyHex",
                                style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold)),
                          ),
                        ),
                      ],
                    ),
                  ));
                }
                if (mounted) {
                  setState(() {
                    progress = ((i + 1) * 100 / records.length).round();
                  });
                }
              }
            }
          }
        }
      }
    } catch (e) {
      _showMessage(e.toString());
    } finally {
      if (mounted) {
        setState(() {
          recovering = false;
          progress = -1;
        });
      }
    }
  }

  // ---- Per-mode configuration widgets ----

  Widget _buildCardConfig() {
    var localizations = AppLocalizations.of(context)!;
    final cards = _app.sharedPreferencesProvider
        .getCards()
        .where((c) => isMifareClassic(c.tag))
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SegmentedButton<_CardSource>(
          segments: [
            ButtonSegment(
                value: _CardSource.saved,
                icon: const Icon(Icons.sd_card),
                label: Text(localizations.simulated_card)),
            ButtonSegment(
                value: _CardSource.slot,
                icon: const Icon(Icons.widgets),
                label: Text(localizations.slot_manager)),
          ],
          selected: {_cardSource},
          onSelectionChanged: armed
              ? null
              : (s) => setState(() => _cardSource = s.first),
        ),
        const SizedBox(height: 12),
        if (_cardSource == _CardSource.saved)
          DropdownButtonFormField<String?>(
            initialValue: _selectedCardId,
            isExpanded: true,
            decoration: InputDecoration(
                labelText: localizations.simulated_card,
                border: const OutlineInputBorder()),
            items: cards
                .map((c) => DropdownMenuItem<String?>(
                      value: c.id,
                      child: Text(
                          c.name.isEmpty ? c.uid.toUpperCase() : c.name,
                          overflow: TextOverflow.ellipsis),
                    ))
                .toList(),
            onChanged:
                armed ? null : (v) => setState(() => _selectedCardId = v),
          )
        else ...[
          DropdownButtonFormField<int?>(
            initialValue: _selectedSlot,
            isExpanded: true,
            decoration: InputDecoration(
                labelText: localizations.slot_manager,
                border: const OutlineInputBorder()),
            items: _slots
                .map((e) => DropdownMenuItem<int?>(
                      value: e.index,
                      child: Text("${localizations.slot} ${e.index + 1}: ${e.label}",
                          overflow: TextOverflow.ellipsis),
                    ))
                .toList(),
            onChanged: armed
                ? null
                : (v) {
                    if (v != null) _onSlotSelected(v);
                  },
          ),
          if (_selectedSlotUid.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6.0),
              child: Text("UID: $_selectedSlotUid",
                  style: const TextStyle(fontFamily: 'RobotoMono')),
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
                enabled: !armed,
                decoration: InputDecoration(
                  labelText: localizations.uid,
                  hintText: "DEADBEEF",
                  border: const OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: armed
                  ? null
                  : () => setState(() => _uidCtl.text = _randomUidHex()),
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
          style:
              TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 12),
        ),
        const SizedBox(height: 8),
        Text(
          _currentRandomUid.isEmpty
              ? "UID: —"
              : "UID: $_currentRandomUid",
          style: const TextStyle(
              fontFamily: 'RobotoMono',
              fontSize: 16,
              fontWeight: FontWeight.bold),
        ),
      ],
    );
  }

  Widget _buildCaptureSection() {
    var localizations = AppLocalizations.of(context)!;
    return Column(
      children: [
        Center(
          child: ElevatedButton.icon(
            onPressed: busy ? null : (armed ? _stop : _arm),
            icon: Icon(armed ? Icons.stop : Icons.wifi_tethering),
            label: Text(
                armed ? localizations.stop_capture : localizations.arm_capture),
          ),
        ),
        const SizedBox(height: 10),
        if (armed) ...[
          Text(localizations.capture_armed_hint,
              textAlign: TextAlign.center,
              style: const TextStyle(fontStyle: FontStyle.italic)),
          const SizedBox(height: 6),
          Text(localizations.captured_auth_attempts(detectionCount),
              style: const TextStyle(
                  fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
        ],
        ElevatedButton(
          onPressed:
              (recovering || detectionCount <= 0) ? null : _recoverKeys,
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
        ...displayKeys,
        if (keys.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8.0),
            child: ElevatedButton.icon(
              onPressed: () {
                showDialog<String>(
                  context: context,
                  builder: (context) =>
                      DictionaryExportMenu(defaultName: outputUid, keys: keys),
                );
              },
              icon: const Icon(Icons.save),
              label: Text(localizations.save_recovered_keys),
            ),
          ),
      ],
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
                  ignoring: armed,
                  child: Opacity(
                    opacity: armed ? 0.5 : 1.0,
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

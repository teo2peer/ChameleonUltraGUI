import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:chameleonultragui/generated/i18n/app_localizations.dart';
import 'package:chameleonultragui/gui/component/error_message.dart';
import 'package:chameleonultragui/gui/component/key_check_marks.dart';
import 'package:chameleonultragui/gui/component/mifare_classic_activity_progress.dart';
import 'package:chameleonultragui/gui/menu/dialogs/dictionary/export.dart';
import 'package:chameleonultragui/gui/page/read_card.dart';
import 'package:chameleonultragui/helpers/general.dart';
import 'package:chameleonultragui/helpers/mifare_classic/autopwn_v2.dart';
import 'package:chameleonultragui/helpers/mifare_classic/general.dart';
import 'package:chameleonultragui/helpers/mifare_classic/recovery.dart';
import 'package:chameleonultragui/main.dart';
import 'package:chameleonultragui/sharedprefsprovider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

enum _PhaseVisualState { pending, active, complete, skipped, failed }

class AutopwnV2Page extends StatefulWidget {
  const AutopwnV2Page({super.key});

  @override
  State<AutopwnV2Page> createState() => _AutopwnV2PageState();
}

class _AutopwnV2PageState extends State<AutopwnV2Page> {
  static const _visiblePhases = [
    AutopwnV2Phase.preflight,
    AutopwnV2Phase.seeds,
    AutopwnV2Phase.classify,
    AutopwnV2Phase.backdoor,
    AutopwnV2Phase.bootstrap,
    AutopwnV2Phase.nested,
    AutopwnV2Phase.staticNested,
    AutopwnV2Phase.hardnested,
    AutopwnV2Phase.verify,
    AutopwnV2Phase.dump,
  ];

  final AutopwnV2Runner _runner = const AutopwnV2Runner();
  final Set<String> _selectedDictionaryIds = {};
  final Map<AutopwnV2Phase, _PhaseVisualState> _phaseStates = {};

  List<Dictionary> _dictionaries = [];
  HFCardInfo? _card;
  MifareClassicInfo? _mfc;
  MifareClassicAutopwnV2Port? _port;
  AutopwnV2Progress? _progress;
  AutopwnV2Result? _result;
  AutopwnV2Phase? _activePhase;
  Timer? _elapsedTicker;
  DateTime? _startedAt;
  bool _running = false;
  bool _initializedDictionaries = false;
  String _message = '';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initializedDictionaries) return;
    _dictionaries = context
        .read<ChameleonGUIState>()
        .sharedPreferencesProvider
        .getDictionaries(keyLength: 12);
    _selectedDictionaryIds.addAll(
      _dictionaries.map((dictionary) => dictionary.id),
    );
    _initializedDictionaries = true;
  }

  @override
  void dispose() {
    _elapsedTicker?.cancel();
    _port?.cancel();
    super.dispose();
  }

  void _refreshRecovery() {
    if (mounted) setState(() {});
  }

  List<Dictionary> get _selectedDictionaries => _dictionaries
      .where((dictionary) => _selectedDictionaryIds.contains(dictionary.id))
      .toList();

  Future<bool> _sameCardStillPresent(HFCardInfo expected) async {
    final communicator = context.read<ChameleonGUIState>().communicator;
    final noAts = AppLocalizations.of(context)!.no;
    if (communicator == null) return false;
    final current = await communicator.scan14443aTag();
    if (current == null) return false;
    final ats = current.ats.isEmpty ? noAts : bytesToHexSpace(current.ats);
    return bytesToHexSpace(current.uid) == expected.uid &&
        bytesToHexSpace(current.atqa) == expected.atqa &&
        current.sak.toRadixString(16).padLeft(2, '0').toUpperCase() ==
            expected.sak &&
        ats == expected.ats;
  }

  void _resetRunState() {
    _phaseStates
      ..clear()
      ..addEntries(
        _visiblePhases.map(
          (phase) => MapEntry(phase, _PhaseVisualState.pending),
        ),
      );
    _activePhase = null;
    _progress = null;
    _result = null;
    _card = null;
    _mfc = null;
    _port = null;
    _message = '';
    _startedAt = DateTime.now();
  }

  void _acceptProgress(AutopwnV2Progress progress) {
    if (!mounted) return;
    setState(() {
      if (_activePhase != null && _activePhase != progress.phase) {
        _phaseStates[_activePhase!] = _PhaseVisualState.complete;
      }
      if (_visiblePhases.contains(progress.phase)) {
        _activePhase = progress.phase;
        _phaseStates[progress.phase] = _PhaseVisualState.active;
      } else if (progress.phase == AutopwnV2Phase.complete) {
        if (_activePhase != null) {
          _phaseStates[_activePhase!] = _PhaseVisualState.complete;
        }
        for (final phase in _visiblePhases) {
          if (_phaseStates[phase] == _PhaseVisualState.pending) {
            _phaseStates[phase] = _PhaseVisualState.skipped;
          }
        }
        _activePhase = null;
      } else if (progress.phase == AutopwnV2Phase.cancelled) {
        if (_activePhase != null) {
          _phaseStates[_activePhase!] = _PhaseVisualState.failed;
        }
        _activePhase = null;
      }
      _progress = progress;
    });
  }

  Future<void> _run() async {
    if (_running) return;
    final localizations = AppLocalizations.of(context)!;
    setState(() {
      _running = true;
      _resetRunState();
    });
    _elapsedTicker?.cancel();
    _elapsedTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _running) setState(() {});
    });

    try {
      final (card, mfc, _) = await readHFInfo(context, _refreshRecovery);
      if (!mounted) return;
      if (!card.cardExist) {
        throw StateError(localizations.no_card_found);
      }
      if (mfc.type == MifareClassicType.none || mfc.recovery == null) {
        throw StateError(localizations.not_mifare_classic_slot);
      }
      final port = MifareClassicAutopwnV2Port(
        mfc.recovery!,
        hintedNtLevel: mfc.ntLevel,
        hintedBackdoor: mfc.hasBackdoor,
      );
      setState(() {
        _card = card;
        _mfc = mfc;
        _port = port;
      });

      final result = await _runner.run(
        recovery: port,
        options: AutopwnV2Options(
          dictionaries: _selectedDictionaries,
          exhaustiveEvidence: true,
        ),
        onProgress: _acceptProgress,
        cardGuard: () => _sameCardStillPresent(card),
      );
      if (mounted) setState(() => _result = result);
    } on MifareClassicRecoveryCancelled {
      // Cooperative cancellation is reflected in the runner result.
    } catch (error) {
      if (mounted) {
        setState(() {
          _message = error.toString();
          if (_activePhase != null) {
            _phaseStates[_activePhase!] = _PhaseVisualState.failed;
          }
        });
      }
    } finally {
      _elapsedTicker?.cancel();
      _elapsedTicker = null;
      if (mounted) {
        setState(() {
          _running = false;
          _activePhase = null;
        });
      }
    }
  }

  void _cancel() {
    _port?.cancel();
    if (mounted) setState(() {});
  }

  Future<void> _exportResult() async {
    final result = _result;
    final card = _card;
    if (result == null || card == null) return;
    final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-');
    await FilePicker.saveFile(
      dialogTitle: 'Export verified Autopwn v2 result',
      fileName: 'autopwn-v2-${card.uid.replaceAll(' ', '')}-$timestamp.json',
      bytes: Uint8List.fromList(
        utf8.encode(const JsonEncoder.withIndent(' ').convert(result.toJson())),
      ),
    );
  }

  String _phaseLabel(AutopwnV2Phase phase) => switch (phase) {
    AutopwnV2Phase.preflight => 'Lock card',
    AutopwnV2Phase.seeds => 'Candidate ledger',
    AutopwnV2Phase.classify => 'Classify card',
    AutopwnV2Phase.backdoor => 'Backdoor',
    AutopwnV2Phase.bootstrap => 'Darkside bootstrap',
    AutopwnV2Phase.nested => 'Nested',
    AutopwnV2Phase.staticNested => 'Static Nested',
    AutopwnV2Phase.hardnested => 'Hardnested',
    AutopwnV2Phase.verify => 'Final verification',
    AutopwnV2Phase.dump => 'Lossless dump',
    AutopwnV2Phase.complete => 'Complete',
    AutopwnV2Phase.cancelled => 'Cancelled',
  };

  Widget _phaseIcon(AutopwnV2Phase phase) {
    final state = _phaseStates[phase] ?? _PhaseVisualState.pending;
    return switch (state) {
      _PhaseVisualState.pending => const Icon(Icons.radio_button_unchecked),
      _PhaseVisualState.active => const SizedBox.square(
        dimension: 20,
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
      _PhaseVisualState.complete => const Icon(
        Icons.check_circle,
        color: Colors.green,
      ),
      _PhaseVisualState.skipped => const Icon(Icons.remove_circle_outline),
      _PhaseVisualState.failed => const Icon(
        Icons.error_outline,
        color: Colors.red,
      ),
    };
  }

  String _duration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds.remainder(60);
    return minutes == 0
        ? '${seconds}s'
        : '${minutes}m ${seconds.toString().padLeft(2, '0')}s';
  }

  Widget _introCard() => Card(
    clipBehavior: Clip.antiAlias,
    child: DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Theme.of(context).colorScheme.primaryContainer,
            Theme.of(context).colorScheme.surfaceContainerHighest,
          ],
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.hub, size: 32),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Evidence-driven recovery',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            const Text(
              'One run locks the card identity, verifies every candidate, '
              'selects compatible attacks, propagates recovered keys, and '
              'exports unreadable blocks as missing instead of fake zeros.',
            ),
            const SizedBox(height: 12),
            const Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                Chip(label: Text('No candidate truncation')),
                Chip(label: Text('On-card verification')),
                Chip(label: Text('Adaptive attack plan')),
              ],
            ),
          ],
        ),
      ),
    ),
  );

  Widget _dictionaryCard() => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Candidate sources',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          const Text(
            'Selected dictionaries are verified first. Proxmark defaults '
            'and backdoor keys follow; every unique key is retained.',
          ),
          if (_dictionaries.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final dictionary in _dictionaries)
                  FilterChip(
                    label: Text(
                      '${dictionary.name} (${dictionary.keys.length})',
                    ),
                    selected: _selectedDictionaryIds.contains(dictionary.id),
                    onSelected: _running
                        ? null
                        : (selected) => setState(() {
                            if (selected) {
                              _selectedDictionaryIds.add(dictionary.id);
                            } else {
                              _selectedDictionaryIds.remove(dictionary.id);
                            }
                          }),
                  ),
              ],
            ),
          ],
        ],
      ),
    ),
  );

  Widget _progressCard() {
    final progress = _progress;
    if (progress == null && !_running) return const SizedBox.shrink();
    final elapsed = _running && _startedAt != null
        ? DateTime.now().difference(_startedAt!)
        : progress?.elapsed ?? Duration.zero;
    return Card(
      key: const Key('autopwn-v2-progress'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Recovery pipeline',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(progress?.operation ?? 'Scanning MIFARE Classic card'),
            const SizedBox(height: 8),
            LinearProgressIndicator(value: progress?.value),
            MifareClassicActivityProgressIndicator(
              activity: _mfc?.recovery?.activityProgress,
            ),
            const SizedBox(height: 6),
            Text(
              '${progress?.verifiedSlots ?? 0}/${progress?.totalSlots ?? 0} key slots verified | ${_duration(elapsed)}',
            ),
            const Divider(height: 24),
            for (final phase in _visiblePhases)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: [
                    SizedBox(
                      width: 28,
                      child: Center(child: _phaseIcon(phase)),
                    ),
                    const SizedBox(width: 8),
                    Expanded(child: Text(_phaseLabel(phase))),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _resultCard() {
    final result = _result;
    if (result == null) return const SizedBox.shrink();
    final readable = result.blocks.where((block) => block.readable).length;
    final uniqueKeys = result.keys.map(bytesToHex).toSet().length;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  result.complete ? Icons.verified : Icons.rule,
                  color: result.complete ? Colors.green : null,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    result.complete ? 'Fully verified' : 'Partial recovery',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '${result.verifiedKeySlots}/${result.totalKeySlots} key slots, '
              '$uniqueKeys unique keys, $readable/${result.blocks.length} readable blocks',
            ),
            if (result.profile != null)
              Text(
                'Profile: ${result.profile!.ntLevel.name}'
                '${result.profile!.hasBackdoor ? ' + backdoor' : ''}',
              ),
            Text('${result.attacks.length} cryptanalytic attempts recorded'),
            if (result.error.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(result.error),
            ],
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (result.keys.isNotEmpty)
                  OutlinedButton.icon(
                    onPressed: () => showDialog<void>(
                      context: context,
                      builder: (context) => DictionaryExportMenu(
                        keys: result.keys,
                        defaultName: 'Autopwn v2 ${_card?.uid ?? ''}',
                      ),
                    ),
                    icon: const Icon(Icons.key),
                    label: Text(
                      AppLocalizations.of(context)!.save_recovered_keys,
                    ),
                  ),
                OutlinedButton.icon(
                  onPressed: _exportResult,
                  icon: const Icon(Icons.download),
                  label: const Text('Export evidence JSON'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final recovery = _mfc?.recovery;
    return Scaffold(
      appBar: AppBar(title: const Text('Autopwn v2')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _introCard(),
            const SizedBox(height: 12),
            _dictionaryCard(),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: _running ? null : _run,
                  icon: _running
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.play_arrow),
                  label: const Text('Start full recovery'),
                ),
                if (_running)
                  OutlinedButton.icon(
                    onPressed: _cancel,
                    icon: const Icon(Icons.stop),
                    label: Text(AppLocalizations.of(context)!.cancel),
                  ),
              ],
            ),
            if (_card != null) ...[
              const SizedBox(height: 12),
              Text('UID ${_card!.uid} | ${_mfc!.type.name.toUpperCase()}'),
            ],
            if (_message.isNotEmpty) ...[
              const SizedBox(height: 12),
              ErrorMessage(errorMessage: _message),
            ],
            const SizedBox(height: 12),
            _progressCard(),
            if (recovery != null) ...[
              const SizedBox(height: 12),
              KeyCheckMarks(
                checkMarks: recovery.checkMarks,
                validKeys: recovery.validKeys,
                checkmarkCount: mfClassicGetSectorCount(
                  recovery.mifareClassicType,
                  isEV1: recovery.isMifareClassicEV1,
                ),
              ),
              if (recovery.state.isNotEmpty)
                Text(recovery.state, textAlign: TextAlign.center),
            ],
            if (_result != null) ...[const SizedBox(height: 12), _resultCard()],
          ],
        ),
      ),
    );
  }
}

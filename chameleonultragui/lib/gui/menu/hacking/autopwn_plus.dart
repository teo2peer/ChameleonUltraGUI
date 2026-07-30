import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:chameleonultragui/generated/i18n/app_localizations.dart';
import 'package:chameleonultragui/gui/component/error_message.dart';
import 'package:chameleonultragui/gui/component/key_check_marks.dart';
import 'package:chameleonultragui/gui/component/mifare_classic_activity_progress.dart';
import 'package:chameleonultragui/gui/menu/dialogs/dictionary/export.dart';
import 'package:chameleonultragui/gui/page/read_card.dart'
    show HFCardInfo, MifareClassicInfo;
import 'package:chameleonultragui/helpers/definitions.dart';
import 'package:chameleonultragui/helpers/general.dart';
import 'package:chameleonultragui/helpers/mifare_classic/autopwn_plus.dart';
import 'package:chameleonultragui/helpers/mifare_classic/general.dart';
import 'package:chameleonultragui/helpers/mifare_classic/recovery.dart';
import 'package:chameleonultragui/main.dart';
import 'package:chameleonultragui/sharedprefsprovider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class AutopwnPlusPage extends StatefulWidget {
  const AutopwnPlusPage({super.key});

  @override
  State<AutopwnPlusPage> createState() => _AutopwnPlusPageState();
}

class _AutopwnPlusPageState extends State<AutopwnPlusPage> {
  final AutopwnPlusRunner _runner = const AutopwnPlusRunner();
  final Set<String> _selectedDictionaryIds = {};

  List<Dictionary> _dictionaries = [];
  HFCardInfo? _card;
  MifareClassicInfo? _mfc;
  MifareClassicAutopwnPlusPort? _port;
  AutopwnPlusProgress? _progress;
  AutopwnPlusResult? _result;
  AutopwnPlusProfile _profile = AutopwnPlusProfile.balanced;
  RangeValues _sectorRange = const RangeValues(0, 0);
  bool _partialDump = true;
  bool _scanning = false;
  bool _running = false;
  String _message = '';
  Timer? _elapsedTicker;
  DateTime? _runStartedAt;
  DateTime? _phaseStartedAt;
  AutopwnPlusPhase? _timedPhase;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_dictionaries.isEmpty) {
      _dictionaries = context
          .read<ChameleonGUIState>()
          .sharedPreferencesProvider
          .getDictionaries(keyLength: 12);
    }
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

  Future<void> _scan() async {
    if (_scanning || _running) return;
    final localizations = AppLocalizations.of(context)!;
    setState(() {
      _scanning = true;
      _message = '';
      _result = null;
      _progress = null;
      _card = null;
      _mfc = null;
      _port = null;
      _runStartedAt = null;
      _phaseStartedAt = null;
      _timedPhase = null;
    });
    try {
      final (card, mfc, _) = await readHFInfo(context, _refreshRecovery);
      if (!mounted) return;
      if (!card.cardExist) {
        setState(() => _message = localizations.no_card_found);
        return;
      }
      if (mfc.type == MifareClassicType.none || mfc.recovery == null) {
        setState(() => _message = localizations.not_mifare_classic_slot);
        return;
      }
      final port = MifareClassicAutopwnPlusPort(mfc.recovery!);
      setState(() {
        _card = card;
        _mfc = mfc;
        _port = port;
        _sectorRange = RangeValues(0, (port.sectorCount - 1).toDouble());
      });
    } catch (error) {
      if (mounted) setState(() => _message = error.toString());
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  Set<int> get _selectedSectors {
    final port = _port;
    if (port == null) return {};
    final first = _sectorRange.start.round();
    final last = _sectorRange.end.round();
    return {for (var sector = first; sector <= last; sector++) sector};
  }

  List<Dictionary> get _selectedDictionaries {
    if (_profile == AutopwnPlusProfile.deep) return List.of(_dictionaries);
    return _dictionaries
        .where((dictionary) => _selectedDictionaryIds.contains(dictionary.id))
        .toList();
  }

  Future<bool> _sameCardStillPresent() async {
    final expected = _card;
    final communicator = context.read<ChameleonGUIState>().communicator;
    final noAts = AppLocalizations.of(context)!.no;
    if (expected == null || communicator == null) return false;
    final current = await communicator.scan14443aTag();
    if (current == null) return false;
    final currentAts = current.ats.isEmpty
        ? noAts
        : bytesToHexSpace(current.ats);
    return bytesToHexSpace(current.uid) == expected.uid &&
        bytesToHexSpace(current.atqa) == expected.atqa &&
        current.sak.toRadixString(16).padLeft(2, '0').toUpperCase() ==
            expected.sak &&
        currentAts == expected.ats;
  }

  Future<void> _run() async {
    final port = _port;
    if (port == null || _running) return;
    setState(() {
      _running = true;
      _message = '';
      _result = null;
      _runStartedAt = DateTime.now();
      _phaseStartedAt = _runStartedAt;
      _timedPhase = AutopwnPlusPhase.verifying;
    });
    _elapsedTicker?.cancel();
    _elapsedTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _running) setState(() {});
    });
    try {
      if (!await _sameCardStillPresent()) {
        throw StateError(
          'The scanned card changed or left the antenna. Scan again.',
        );
      }
      final result = await _runner.run(
        recovery: port,
        options: AutopwnPlusOptions(
          profile: _profile,
          sectors: _selectedSectors,
          dictionaries: _selectedDictionaries,
          recoverMissing: _profile != AutopwnPlusProfile.quick,
          partialDump: _partialDump,
        ),
        onProgress: (progress) {
          if (mounted) {
            setState(() {
              if (_timedPhase != progress.phase) {
                _timedPhase = progress.phase;
                _phaseStartedAt = DateTime.now();
              }
              _progress = progress;
            });
          }
        },
        cardGuard: _sameCardStillPresent,
      );
      if (mounted) setState(() => _result = result);
    } on MifareClassicRecoveryCancelled {
      // The result reports cooperative cancellation after the active command.
    } catch (error) {
      if (mounted) setState(() => _message = error.toString());
    } finally {
      _elapsedTicker?.cancel();
      _elapsedTicker = null;
      if (mounted) setState(() => _running = false);
    }
  }

  void _cancel() {
    _port?.cancel();
    setState(() {
      _progress = AutopwnPlusProgress(
        phase: AutopwnPlusPhase.cancelled,
        operation: 'Stopping after the current device or solver operation',
        value: null,
        elapsed: _progress?.elapsed ?? Duration.zero,
      );
    });
  }

  Future<void> _exportResult() async {
    final result = _result;
    final card = _card;
    if (result == null || card == null) return;
    final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-');
    await FilePicker.saveFile(
      dialogTitle: 'Export lossless Autopwn+ result',
      fileName: 'autopwn-plus-${card.uid.replaceAll(' ', '')}-$timestamp.json',
      bytes: Uint8List.fromList(
        utf8.encode(
          const JsonEncoder.withIndent('  ').convert(result.toJson()),
        ),
      ),
    );
  }

  String get _strategySummary {
    final nt = _mfc?.ntLevel;
    final backdoor = _mfc?.hasBackdoor;
    final attack = switch (nt) {
      NTLevel.weak => 'weak nested / Darkside',
      NTLevel.static => 'static nested',
      NTLevel.hard => 'hardnested',
      NTLevel.backdoor => 'backdoor recovery',
      _ => 'capability-safe fallback',
    };
    return 'Detected ${nt?.name ?? 'unknown'} PRNG${backdoor == true ? ' with backdoor' : ''}. '
        'Adaptive plan: ranked dictionary waves, key reuse, then $attack.';
  }

  String get _nestedDurationHint => switch (_mfc?.ntLevel) {
    NTLevel.hard =>
      'Hardnested is the longest path: nonce collection and native solving can take several minutes per unresolved key.',
    NTLevel.static =>
      'Static nested is usually faster than hardnested, but multiple unresolved sectors and retries can still take minutes.',
    NTLevel.weak =>
      'Nested duration varies with RF quality and candidate count. A weak-nonce card can finish quickly, but retries may take several minutes.',
    NTLevel.backdoor =>
      'Backdoor recovery is normally faster than nested, but every candidate is still verified on-card.',
    _ =>
      'Recovery time is variable until the nonce type and available attack path are confirmed.',
  };

  String _formatDuration(Duration duration) {
    final seconds = duration.inSeconds;
    if (seconds < 60) return '${seconds}s';
    final minutes = seconds ~/ 60;
    final remainder = seconds % 60;
    return '${minutes}m ${remainder.toString().padLeft(2, '0')}s';
  }

  Widget _profileSelector() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SegmentedButton<AutopwnPlusProfile>(
        segments: const [
          ButtonSegment(
            value: AutopwnPlusProfile.quick,
            label: Text('Quick'),
            icon: Icon(Icons.speed),
          ),
          ButtonSegment(
            value: AutopwnPlusProfile.balanced,
            label: Text('Balanced'),
            icon: Icon(Icons.tune),
          ),
          ButtonSegment(
            value: AutopwnPlusProfile.deep,
            label: Text('Deep'),
            icon: Icon(Icons.travel_explore),
          ),
        ],
        selected: {_profile},
        onSelectionChanged: _running
            ? null
            : (selection) => setState(() => _profile = selection.first),
      ),
    );
  }

  Widget _configurationCard() {
    final port = _port!;
    final quick = _profile == AutopwnPlusProfile.quick;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Adaptive recovery plan',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(_strategySummary),
            const SizedBox(height: 16),
            _profileSelector(),
            const SizedBox(height: 8),
            Text(
              quick
                  ? 'Quick checks the top 64 ranked candidates and skips expensive cryptanalytic recovery.'
                  : _profile == AutopwnPlusProfile.deep
                  ? 'Deep uses every saved dictionary before card-specific recovery.'
                  : 'Balanced uses selected dictionaries before card-specific recovery.',
            ),
            if (!quick) ...[
              const SizedBox(height: 8),
              Text(
                _nestedDurationHint,
                style: TextStyle(color: Theme.of(context).colorScheme.tertiary),
              ),
            ],
            if (_dictionaries.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(
                'Dictionaries',
                style: Theme.of(context).textTheme.labelLarge,
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  for (final dictionary in _dictionaries)
                    FilterChip(
                      label: Text(
                        '${dictionary.name} (${dictionary.keys.length})',
                      ),
                      selected:
                          _profile == AutopwnPlusProfile.deep ||
                          _selectedDictionaryIds.contains(dictionary.id),
                      onSelected:
                          _running || _profile == AutopwnPlusProfile.deep
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
            const SizedBox(height: 16),
            Text(
              'Sector range ${_sectorRange.start.round()}-${_sectorRange.end.round()} '
              'of ${port.sectorCount - 1}',
              style: Theme.of(context).textTheme.labelLarge,
            ),
            if (port.sectorCount > 1)
              RangeSlider(
                values: _sectorRange,
                min: 0,
                max: (port.sectorCount - 1).toDouble(),
                divisions: port.sectorCount - 1,
                labels: RangeLabels(
                  _sectorRange.start.round().toString(),
                  _sectorRange.end.round().toString(),
                ),
                onChanged: _running
                    ? null
                    : (value) => setState(() => _sectorRange = value),
              ),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              value: _partialDump,
              onChanged: _running
                  ? null
                  : (value) => setState(() => _partialDump = value),
              title: const Text('Lossless partial dump'),
              subtitle: const Text(
                'Read every accessible selected block and preserve unreadable blocks as missing, not zeros.',
              ),
            ),
            if (!_selectedSectors.contains(0) && !quick)
              const Text(
                'If no selected key is known, recovery may temporarily authenticate sector 0 as a bootstrap. '
                'Bootstrap keys are removed before results are exported.',
              ),
          ],
        ),
      ),
    );
  }

  Widget _progressCard() {
    final progress = _progress;
    if (progress == null) return const SizedBox.shrink();
    final now = DateTime.now();
    final phaseElapsed = _phaseStartedAt == null
        ? Duration.zero
        : now.difference(_phaseStartedAt!);
    final totalElapsed = _running && _runStartedAt != null
        ? now.difference(_runStartedAt!)
        : progress.elapsed;
    final hardnestedCoverage = progress.phase == AutopwnPlusPhase.recovery
        ? _mfc?.recovery?.hardnestedProgress
        : null;
    final effectiveProgress = progress.value ?? hardnestedCoverage;
    final eta = estimateAutopwnPlusEta(phaseElapsed, effectiveProgress);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              progress.phase.name.toUpperCase(),
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(height: 4),
            Text(progress.operation),
            const SizedBox(height: 8),
            LinearProgressIndicator(value: effectiveProgress),
            MifareClassicActivityProgressIndicator(
              activity: _mfc?.recovery?.activityProgress,
            ),
            const SizedBox(height: 6),
            Text('Elapsed ${_formatDuration(totalElapsed)}'),
            if (hardnestedCoverage != null)
              Text(
                'Hardnested nonce coverage ${(hardnestedCoverage * 100).toStringAsFixed(0)}%',
              ),
            if (_running && eta != null && eta > Duration.zero)
              Text(
                '${hardnestedCoverage != null ? 'Nonce collection ETA' : 'ETA'} ${_formatDuration(eta)}',
                style: const TextStyle(fontWeight: FontWeight.bold),
              )
            else if (_running && progress.phase == AutopwnPlusPhase.recovery)
              const Text(
                'ETA is variable: nested solver time is not exposed by firmware/native code.',
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
    final uniqueKeys = {for (final key in result.keys) bytesToHex(key)}.length;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Result', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              '${result.verifiedKeySlots}/${result.selectedKeySlots} selected key slots verified',
            ),
            Text('$uniqueKeys unique keys recovered'),
            if (result.blocks.isNotEmpty)
              Text(
                '$readable/${result.blocks.length} selected blocks readable',
              ),
            if (result.error.isNotEmpty) Text('Recovery note: ${result.error}'),
            const SizedBox(height: 8),
            for (final entry in result.timings.entries)
              Text(
                '${entry.key.name}: '
                '${(entry.value.inMilliseconds / 1000).toStringAsFixed(2)} s',
              ),
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
                        defaultName: 'Autopwn+ ${_card?.uid ?? ''}',
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
                  label: const Text('Export lossless JSON'),
                ),
                if (!result.selectedKeysRecovered && !result.cancelled)
                  FilledButton.tonalIcon(
                    onPressed: _running ? null : _run,
                    icon: const Icon(Icons.replay),
                    label: const Text('Retry unresolved'),
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
    final localizations = AppLocalizations.of(context)!;
    final recovery = _mfc?.recovery;
    return Scaffold(
      appBar: AppBar(title: Text(localizations.autopwn_plus)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(localizations.autopwn_plus_description),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: _scanning || _running ? null : _scan,
                  icon: _scanning
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.contactless),
                  label: Text(_card == null ? 'Scan card' : 'Scan again'),
                ),
                if (_port != null)
                  FilledButton.icon(
                    onPressed: _running || _port!.isCancelled ? null : _run,
                    icon: const Icon(Icons.auto_awesome),
                    label: const Text('Run Autopwn+'),
                  ),
                if (_running)
                  OutlinedButton.icon(
                    onPressed: _cancel,
                    icon: const Icon(Icons.stop),
                    label: Text(localizations.cancel),
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
            if (_port != null) ...[
              const SizedBox(height: 12),
              _configurationCard(),
            ],
            if (_progress != null) ...[
              const SizedBox(height: 12),
              _progressCard(),
            ],
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
              if (recovery.state.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(recovery.state, textAlign: TextAlign.center),
              ],
              if (recovery.error.isNotEmpty) ...[
                const SizedBox(height: 8),
                ErrorMessage(errorMessage: recovery.error),
              ],
            ],
            if (_result != null) ...[const SizedBox(height: 12), _resultCard()],
          ],
        ),
      ),
    );
  }
}

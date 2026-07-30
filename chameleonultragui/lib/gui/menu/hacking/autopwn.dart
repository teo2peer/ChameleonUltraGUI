import 'dart:async';

import 'package:chameleonultragui/gui/component/error_message.dart';
import 'package:chameleonultragui/gui/component/key_check_marks.dart';
import 'package:chameleonultragui/gui/component/mifare_classic_activity_progress.dart';
import 'package:chameleonultragui/gui/menu/dialogs/dictionary/export.dart';
import 'package:chameleonultragui/gui/page/read_card.dart'
    show MifareClassicInfo;
import 'package:chameleonultragui/helpers/general.dart';
import 'package:chameleonultragui/helpers/mifare_classic/general.dart';
import 'package:chameleonultragui/helpers/mifare_classic/recovery.dart';
import 'package:chameleonultragui/main.dart';
import 'package:chameleonultragui/sharedprefsprovider.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

// Localizations
import 'package:chameleonultragui/generated/i18n/app_localizations.dart';

// One-click MIFARE Classic key recovery. Reuses the existing recovery engine
// (dictionary check -> darkside -> nested/hardnested/static/backdoor -> dump).
// When [dictionaryOnly] is true it stops after the dictionary phase (fchk).
class AutopwnPage extends StatefulWidget {
  final bool dictionaryOnly;
  const AutopwnPage({super.key, this.dictionaryOnly = false});

  @override
  AutopwnPageState createState() => AutopwnPageState();
}

class AutopwnPageState extends State<AutopwnPage> {
  MifareClassicInfo? mfcInfo;
  bool running = false;
  String message = '';
  MifareClassicRecovery? _activeRecovery;
  AutopwnRunProgress? _runProgress;
  Timer? _elapsedTicker;
  bool _exhaustiveRecovery = false;

  // Saved dictionaries the user can pick from as a starting key set before the
  // run. Index 0 is always the "empty" entry (default keys only).
  List<Dictionary> _dictionaries = [];
  Dictionary? _selectedDictionary;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_dictionaries.isEmpty) {
      var appState = context.read<ChameleonGUIState>();
      var localizations = AppLocalizations.of(context)!;
      _dictionaries = [
        Dictionary(id: "", name: localizations.empty, keys: []),
        ...appState.sharedPreferencesProvider.getDictionaries(keyLength: 12),
      ];
      _selectedDictionary = _dictionaries.first;
    }
  }

  @override
  void dispose() {
    _activeRecovery?.cancel();
    _elapsedTicker?.cancel();
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  Future<void> _run() async {
    var localizations = AppLocalizations.of(context)!;
    final progress = AutopwnRunProgress(exhaustive: _exhaustiveRecovery)
      ..start(AutopwnPhase.scan, "Detecting MIFARE Classic card");
    _elapsedTicker?.cancel();
    _elapsedTicker = Timer.periodic(
      const Duration(seconds: 1),
      (_) => _refresh(),
    );
    setState(() {
      running = true;
      message = '';
      mfcInfo = null;
      _activeRecovery = null;
      _runProgress = progress;
    });
    try {
      var (hfInfo, mfc, _) = await readHFInfo(context, _refresh);
      if (!mounted) return;
      if (!hfInfo.cardExist) {
        progress.fail(AutopwnPhase.scan, "No card found");
        _skipPendingPhases(progress, "No card available");
        setState(() => message = localizations.no_card_found);
        return;
      }
      if (mfc.type == MifareClassicType.none || mfc.recovery == null) {
        progress.fail(AutopwnPhase.scan, "Card is not MIFARE Classic");
        _skipPendingPhases(progress, "Incompatible card");
        setState(() => message = localizations.not_mifare_classic_slot);
        return;
      }
      progress.complete(AutopwnPhase.scan, "MIFARE Classic card detected");
      final recovery = mfc.recovery!;
      _activeRecovery = recovery;
      recovery.clearActivityProgress();
      recovery.autopwnProgress = progress;
      recovery.exhaustiveRecovery = _exhaustiveRecovery;
      setState(() => mfcInfo = mfc);

      // Seed the recovery with the dictionary the user picked before starting.
      // checkKeys() tests these keys first (default keys are still tried on top,
      // unless skipDefaultDictionary). Falls back to "empty" (defaults only).
      recovery.dictionaries = List.of(_dictionaries);
      recovery.selectedDictionary = _selectedDictionary ?? _dictionaries.first;

      await recovery.checkKeys();
      if (!mounted || recovery.isCancelled) return;
      if (widget.dictionaryOnly) {
        _skipPendingPhases(progress, "Dictionary-only run");
      } else if (!recovery.allKeysExists) {
        await recovery.recoverKeys();
      } else {
        for (final phase in [
          AutopwnPhase.backdoor,
          AutopwnPhase.darkside,
          AutopwnPhase.nested,
          AutopwnPhase.staticNested,
          AutopwnPhase.hardnested,
        ]) {
          progress.skip(phase, "All keys were found in key passes");
        }
      }
      if (!mounted || recovery.isCancelled) return;
      if (!widget.dictionaryOnly && recovery.allKeysExists) {
        await recovery.dumpData();
      } else if (!widget.dictionaryOnly) {
        progress.skip(AutopwnPhase.dump, "Not all sector keys were recovered");
      }
      if (!mounted || recovery.isCancelled) return;
      _refresh();
    } on MifareClassicRecoveryCancelled {
      // Leaving the page cancels the run cooperatively after the in-flight
      // device command returns. Do not surface this as an error.
    } catch (e) {
      progress.failCurrent(e.toString());
      _skipPendingPhases(progress, "Stopped after an error");
      if (mounted) setState(() => message = e.toString());
    } finally {
      progress.finish();
      _elapsedTicker?.cancel();
      _elapsedTicker = null;
      if (mounted) {
        setState(() {
          running = false;
          _activeRecovery = null;
        });
      }
    }
  }

  void _skipPendingPhases(AutopwnRunProgress progress, String detail) {
    for (final phase in AutopwnPhase.values) {
      progress.skip(phase, detail);
    }
  }

  bool get _hasAnyKey =>
      mfcInfo?.recovery?.validKeys.any((k) => k.isNotEmpty) ?? false;

  @override
  Widget build(BuildContext context) {
    var localizations = AppLocalizations.of(context)!;
    final recovery = mfcInfo?.recovery;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.dictionaryOnly
              ? localizations.dictionary_check
              : localizations.autopwn,
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Pick which saved dictionary to seed the run with (default keys are
            // always tried on top). Only shown when the user has saved some.
            if (_dictionaries.length > 1) ...[
              Align(
                alignment: Alignment.centerLeft,
                child: Text(localizations.additional_key_dict),
              ),
              const SizedBox(height: 4),
              DropdownButton<String>(
                value: _selectedDictionary?.id,
                isExpanded: true,
                items: _dictionaries
                    .map<DropdownMenuItem<String>>(
                      (Dictionary d) => DropdownMenuItem<String>(
                        value: d.id,
                        child: Text(
                          "${d.name} (${d.keys.length} ${localizations.keys.toLowerCase()})",
                        ),
                      ),
                    )
                    .toList(),
                onChanged: running
                    ? null
                    : (String? newValue) {
                        setState(() {
                          _selectedDictionary = _dictionaries.firstWhere(
                            (d) => d.id == newValue,
                            orElse: () => _dictionaries.first,
                          );
                        });
                      },
              ),
              const SizedBox(height: 12),
            ],
            if (!widget.dictionaryOnly) ...[
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                value: _exhaustiveRecovery,
                onChanged: running
                    ? null
                    : (value) => setState(() => _exhaustiveRecovery = value),
                title: const Text('Deep candidate sweep'),
                subtitle: const Text(
                  'Run selected keys first, then defaults, collect repeated '
                  'Nested candidates, rank every candidate by support, and '
                  'try compatible backdoor and Static Nested fallbacks.',
                ),
              ),
              const SizedBox(height: 8),
            ],
            Center(
              child: ElevatedButton.icon(
                onPressed: running ? null : _run,
                icon: running
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.play_arrow),
                label: Text(
                  widget.dictionaryOnly
                      ? localizations.run_dictionary_only
                      : localizations.start_autopwn,
                ),
              ),
            ),
            const SizedBox(height: 16),
            if (message.isNotEmpty) ErrorMessage(errorMessage: message),
            if (_runProgress != null) ...[
              AutopwnProgressChecklist(
                progress: _runProgress!,
                activity: recovery?.activityProgress,
              ),
              const SizedBox(height: 12),
            ],
            if (recovery != null) ...[
              KeyCheckMarks(
                checkMarks: recovery.checkMarks,
                validKeys: recovery.validKeys,
                checkmarkCount: mfClassicGetSectorCount(
                  recovery.mifareClassicType,
                  isEV1: recovery.isMifareClassicEV1,
                ),
              ),
              if (recovery.error.isNotEmpty) ...[
                const SizedBox(height: 12),
                ErrorMessage(errorMessage: recovery.error),
              ],
              if (recovery.allKeysExists) ...[
                const SizedBox(height: 12),
                Text(
                  localizations.all_keys_recovered,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
              if (_hasAnyKey) ...[
                const SizedBox(height: 12),
                ElevatedButton.icon(
                  onPressed: () {
                    showDialog<String>(
                      context: context,
                      builder: (context) => DictionaryExportMenu(
                        keys: recovery.validKeys
                            .where((k) => k.isNotEmpty)
                            .toList(),
                      ),
                    );
                  },
                  icon: const Icon(Icons.save),
                  label: Text(localizations.save_recovered_keys),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

class AutopwnProgressChecklist extends StatelessWidget {
  const AutopwnProgressChecklist({
    super.key,
    required this.progress,
    this.activity,
  });

  final AutopwnRunProgress progress;
  final MifareClassicRecoveryActivity? activity;

  static const _labels = {
    AutopwnPhase.scan: 'Scan card',
    AutopwnPhase.dictionary: 'Selected, default and known keys',
    AutopwnPhase.backdoor: 'Factory backdoor',
    AutopwnPhase.darkside: 'Darkside bootstrap',
    AutopwnPhase.nested: 'Nested',
    AutopwnPhase.staticNested: 'Static Nested fallback',
    AutopwnPhase.hardnested: 'Hardnested',
    AutopwnPhase.dump: 'Read card data',
  };

  String _duration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);
    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:'
          '${minutes.toString().padLeft(2, '0')}:'
          '${seconds.toString().padLeft(2, '0')}';
    }
    return '${minutes.toString().padLeft(2, '0')}:'
        '${seconds.toString().padLeft(2, '0')}';
  }

  String _status(AutopwnPhaseStatus status) => switch (status) {
    AutopwnPhaseStatus.pending => 'Pending',
    AutopwnPhaseStatus.active => 'Running',
    AutopwnPhaseStatus.completed => 'Completed',
    AutopwnPhaseStatus.skipped => 'Skipped',
    AutopwnPhaseStatus.failed => 'Failed',
  };

  Widget _leading(BuildContext context, AutopwnPhaseStatus status) {
    final colors = Theme.of(context).colorScheme;
    return switch (status) {
      AutopwnPhaseStatus.active => const SizedBox(
        width: 22,
        height: 22,
        child: CircularProgressIndicator(strokeWidth: 2.5),
      ),
      AutopwnPhaseStatus.completed => const Icon(
        Icons.check_circle,
        color: Colors.green,
      ),
      AutopwnPhaseStatus.skipped => Icon(
        Icons.remove_circle_outline,
        color: colors.onSurfaceVariant,
      ),
      AutopwnPhaseStatus.failed => Icon(
        Icons.error_outline,
        color: colors.error,
      ),
      AutopwnPhaseStatus.pending => Icon(
        Icons.radio_button_unchecked,
        color: colors.onSurfaceVariant,
      ),
    };
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    AutopwnPhase? active;
    for (final phase in AutopwnPhase.values) {
      if (progress.phase(phase).status == AutopwnPhaseStatus.active) {
        active = phase;
        break;
      }
    }
    final activeDetail = active == null ? null : progress.phase(active).detail;
    final percent = (progress.overallProgress * 100).round();

    return Card(
      key: const Key('autopwn-progress-checklist'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              runSpacing: 4,
              spacing: 12,
              children: [
                Text(
                  progress.exhaustive
                      ? 'Deep recovery checklist'
                      : 'Recovery checklist',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                Text('$percent% / ${_duration(progress.elapsed(now))}'),
              ],
            ),
            const SizedBox(height: 8),
            Semantics(
              label: 'Overall Autopwn progress $percent percent',
              child: LinearProgressIndicator(
                key: const Key('autopwn-overall-progress'),
                value: progress.overallProgress,
              ),
            ),
            MifareClassicActivityProgressIndicator(activity: activity),
            if (activeDetail != null && activeDetail.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('Current step: $activeDetail'),
            ],
            const Divider(height: 24),
            for (final phase in AutopwnPhase.values)
              _AutopwnPhaseTile(
                key: Key('autopwn-phase-${phase.name}'),
                label: _labels[phase]!,
                state: progress.phase(phase),
                status: _status(progress.phase(phase).status),
                elapsed: _duration(progress.phase(phase).elapsed(now)),
                leading: _leading(context, progress.phase(phase).status),
              ),
          ],
        ),
      ),
    );
  }
}

class _AutopwnPhaseTile extends StatelessWidget {
  const _AutopwnPhaseTile({
    super.key,
    required this.label,
    required this.state,
    required this.status,
    required this.elapsed,
    required this.leading,
  });

  final String label;
  final AutopwnPhaseState state;
  final String status;
  final String elapsed;
  final Widget leading;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '$label, $status, ${state.detail}',
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        leading: leading,
        title: Text(label),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('$status / $elapsed'),
            if (state.detail.isNotEmpty) Text(state.detail),
            if (state.status == AutopwnPhaseStatus.active) ...[
              const SizedBox(height: 6),
              LinearProgressIndicator(
                key: Key('autopwn-phase-${label.toLowerCase()}-progress'),
                value: state.progress,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

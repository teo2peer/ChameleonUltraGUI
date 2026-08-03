import 'dart:async';

import 'package:chameleonultragui/bridge/chameleon.dart';
import 'package:chameleonultragui/helpers/definitions.dart';
import 'package:chameleonultragui/helpers/general.dart';
import 'package:chameleonultragui/helpers/hf_capture.dart';
import 'package:chameleonultragui/helpers/hf_capture_controller.dart';
import 'package:chameleonultragui/helpers/mifare_classic/general.dart';
import 'package:chameleonultragui/helpers/mifare_classic/hf_capture_recovery.dart';
import 'package:chameleonultragui/main.dart';
import 'package:chameleonultragui/generated/i18n/app_localizations.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

class _HfEmulationSlot {
  const _HfEmulationSlot({
    required this.index,
    required this.name,
    required this.type,
  });

  final int index;
  final String name;
  final TagType type;
}

class _HfInspectedCard {
  const _HfInspectedCard({required this.card, required this.randomUid});

  final CardData card;
  final bool randomUid;
}

class HfContinuousCapturePage extends StatefulWidget {
  const HfContinuousCapturePage({super.key});

  @override
  State<HfContinuousCapturePage> createState() =>
      _HfContinuousCapturePageState();
}

class _HfContinuousCapturePageState extends State<HfContinuousCapturePage> {
  HfCaptureMode _mode = HfCaptureMode.emulation;
  ChameleonCommunicator? _slotCommunicator;
  List<_HfEmulationSlot> _emulationSlots = const [];
  int? _selectedEmulationSlot;
  CardData? _selectedEmulationCard;
  bool _selectedRandomUid = false;
  bool _slotsLoading = false;
  bool _slotBusy = false;
  String? _slotError;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final appState = context.watch<ChameleonGUIState>();
    final communicator = appState.communicator;
    if (identical(_slotCommunicator, communicator)) return;

    _slotCommunicator = communicator;
    _emulationSlots = const [];
    _selectedEmulationSlot = null;
    _selectedEmulationCard = null;
    _selectedRandomUid = false;
    _slotError = null;
    _slotsLoading = communicator != null;
    if (communicator != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && identical(_slotCommunicator, communicator)) {
          unawaited(_loadEmulationSlots(appState, communicator));
        }
      });
    }
  }

  Future<void> _start(
    ChameleonGUIState appState,
    HfCaptureController controller,
  ) async {
    var ownsSlotBusy = false;
    final localizations = AppLocalizations.of(context)!;
    try {
      if (_mode == HfCaptureMode.emulation) {
        if (!identical(_slotCommunicator, appState.communicator)) {
          throw StateError(localizations.hf_capture_slot_connection_changed);
        }
        final entry = _selectedSlotEntry;
        final displayedCard = _selectedEmulationCard;
        if (entry == null || displayedCard == null) {
          throw StateError(localizations.hf_capture_select_slot_first);
        }
        ownsSlotBusy = true;
        setState(() => _slotBusy = true);
        await appState.runSlotOperation(() async {
          final current = await _inspectActivatedSlot(entry);
          if (!_sameCard(
            displayedCard,
            current.card,
            ignoreUid: current.randomUid,
          )) {
            if (mounted) {
              setState(() {
                _selectedEmulationCard = current.card;
                _selectedRandomUid = current.randomUid;
              });
            }
            throw StateError(localizations.hf_capture_card_changed);
          }
          appState.hfCaptureMifareRecoveryController.prepareForCapture(
            expectedCard: isMifareClassic(entry.type) && !current.randomUid
                ? current.card
                : null,
          );
          await controller.start(_mode);
          if (mounted) {
            setState(() {
              _selectedEmulationCard = current.card;
              _selectedRandomUid = current.randomUid;
            });
          }
        }, invalidatesMonitorBaseline: false);
      } else {
        appState.hfCaptureMifareRecoveryController.prepareForCapture();
        await controller.start(_mode);
      }
    } catch (error) {
      if (mounted) _showError(error);
    } finally {
      if (ownsSlotBusy && mounted) setState(() => _slotBusy = false);
    }
  }

  Future<void> _loadEmulationSlots(
    ChameleonGUIState appState,
    ChameleonCommunicator communicator,
  ) async {
    if (!mounted || !identical(_slotCommunicator, communicator)) return;
    setState(() {
      _slotsLoading = true;
      _slotError = null;
    });
    try {
      final localizations = AppLocalizations.of(context)!;
      final names = await communicator.getSlotTagNames();
      final types = await communicator.getSlotTagTypes();
      final enabled = await communicator.getEnabledSlots();
      final activeSlot = await communicator.getActiveSlot();
      if (!mounted || !identical(_slotCommunicator, communicator)) return;

      final slots = <_HfEmulationSlot>[];
      for (
        var index = 0;
        index < 8 && index < types.length && index < enabled.length;
        index++
      ) {
        final type = types[index].hf;
        if (!enabled[index].hf || type == TagType.unknown) continue;
        final configuredName = index < names.length
            ? names[index].hf.trim()
            : '';
        slots.add(
          _HfEmulationSlot(
            index: index,
            name: configuredName.isEmpty
                ? localizations.hf_capture_slot_unnamed
                : configuredName,
            type: type,
          ),
        );
      }

      final activeEntry = _findSlot(slots, activeSlot);
      _HfInspectedCard? activeCard;
      Object? cardError;
      if (activeEntry != null) {
        try {
          activeCard = await _inspectEmulationSlot(appState, activeEntry);
        } catch (error) {
          cardError = error;
        }
      }
      if (!mounted || !identical(_slotCommunicator, communicator)) return;
      setState(() {
        _emulationSlots = slots;
        _selectedEmulationSlot = activeEntry?.index;
        _selectedEmulationCard = activeCard?.card;
        _selectedRandomUid = activeCard?.randomUid ?? false;
        _slotError = cardError?.toString();
      });
    } catch (error) {
      if (mounted && identical(_slotCommunicator, communicator)) {
        setState(() {
          _emulationSlots = const [];
          _selectedEmulationSlot = null;
          _selectedEmulationCard = null;
          _selectedRandomUid = false;
          _slotError = error.toString();
        });
      }
    } finally {
      if (mounted && identical(_slotCommunicator, communicator)) {
        setState(() => _slotsLoading = false);
      }
    }
  }

  Future<_HfInspectedCard> _inspectEmulationSlot(
    ChameleonGUIState appState,
    _HfEmulationSlot entry,
  ) async {
    final communicator = appState.communicator;
    if (communicator == null || !identical(_slotCommunicator, communicator)) {
      throw StateError(
        AppLocalizations.of(context)!.hf_capture_slot_connection_changed,
      );
    }
    return appState.runSlotOperation(
      () => _inspectActivatedSlot(entry),
      invalidatesMonitorBaseline: false,
    );
  }

  Future<_HfInspectedCard> _inspectActivatedSlot(_HfEmulationSlot entry) async {
    final communicator = _slotCommunicator;
    if (communicator == null) {
      throw StateError(
        AppLocalizations.of(context)!.hf_capture_slot_connection_changed,
      );
    }
    final localizations = AppLocalizations.of(context)!;
    final types = await communicator.getSlotTagTypes();
    final enabled = await communicator.getEnabledSlots();
    if (entry.index >= types.length ||
        entry.index >= enabled.length ||
        !enabled[entry.index].hf ||
        types[entry.index].hf != entry.type) {
      throw StateError(localizations.hf_capture_slot_changed);
    }
    await communicator.activateSlot(entry.index);
    final card = await communicator.mf1GetAntiCollData();
    final randomUid = isMifareClassic(entry.type)
        ? await communicator.getMf1RandomUidMode()
        : false;
    return _HfInspectedCard(card: card, randomUid: randomUid);
  }

  Future<void> _selectEmulationSlot(
    ChameleonGUIState appState,
    int index,
  ) async {
    final entry = _findSlot(_emulationSlots, index);
    if (entry == null || _slotBusy) return;
    setState(() {
      _slotBusy = true;
      _selectedEmulationSlot = index;
      _selectedEmulationCard = null;
      _selectedRandomUid = false;
      _slotError = null;
    });
    try {
      final inspected = await _inspectEmulationSlot(appState, entry);
      if (mounted && identical(_slotCommunicator, appState.communicator)) {
        setState(() {
          _selectedEmulationCard = inspected.card;
          _selectedRandomUid = inspected.randomUid;
        });
        appState.changesMade();
      }
    } catch (error) {
      if (mounted) {
        setState(() => _slotError = error.toString());
        _showError(error);
      }
    } finally {
      if (mounted) setState(() => _slotBusy = false);
    }
  }

  _HfEmulationSlot? get _selectedSlotEntry =>
      _findSlot(_emulationSlots, _selectedEmulationSlot);

  _HfEmulationSlot? _findSlot(List<_HfEmulationSlot> slots, int? index) {
    if (index == null) return null;
    for (final slot in slots) {
      if (slot.index == index) return slot;
    }
    return null;
  }

  bool _sameCard(CardData left, CardData right, {required bool ignoreUid}) =>
      left.sak == right.sak &&
      (ignoreUid || listEquals(left.uid, right.uid)) &&
      listEquals(left.atqa, right.atqa) &&
      listEquals(left.ats, right.ats);

  Future<void> _copyRawFrame(HfCaptureRecord record) async {
    await Clipboard.setData(ClipboardData(text: hfCaptureRawHex(record)));
    if (!mounted) return;
    final localizations = AppLocalizations.of(context)!;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(localizations.hf_capture_raw_copied)),
      );
  }

  Future<void> _copyRecoveredKey(HfCaptureRecoveredKey recoveredKey) async {
    await Clipboard.setData(ClipboardData(text: recoveredKey.keyHex));
    if (!mounted) return;
    final localizations = AppLocalizations.of(context)!;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(localizations.hf_capture_recovery_key_copied)),
      );
  }

  Future<void> _stop(HfCaptureController controller) async {
    try {
      await controller.stop();
    } catch (error) {
      if (mounted) _showError(error);
    }
  }

  Future<void> _retryDrain(HfCaptureController controller) async {
    try {
      await controller.retryDrain();
    } catch (error) {
      if (mounted) _showError(error);
    }
  }

  Future<void> _probe(HfCaptureController controller) async {
    try {
      await controller.probeReader();
    } catch (error) {
      if (mounted) _showError(error);
    }
  }

  Future<void> _setRetention(
    ChameleonGUIState appState,
    HfCaptureController controller,
    int days,
  ) async {
    try {
      await appState.sharedPreferencesProvider.setHfCaptureRetentionDays(days);
      await controller.applyRetention();
      appState.changesMade();
      if (mounted) setState(() {});
    } catch (error) {
      if (mounted) _showError(error);
    }
  }

  void _showError(Object error) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(error.toString())));
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<ChameleonGUIState>();
    final controller = appState.hfCaptureController;
    final recoveryController = appState.hfCaptureMifareRecoveryController;
    final localizations = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(title: Text(localizations.hf_capture_title)),
      body: ListenableBuilder(
        listenable: Listenable.merge([controller, recoveryController]),
        builder: (context, _) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _buildHero(context, appState, controller),
            const SizedBox(height: 16),
            _buildModeSelector(controller),
            if (_effectiveMode(controller) == HfCaptureMode.emulation) ...[
              const SizedBox(height: 16),
              _buildEmulationCard(appState, controller),
            ],
            const SizedBox(height: 16),
            _buildMetrics(context, controller),
            const SizedBox(height: 16),
            _buildMifareRecovery(context, recoveryController),
            if (controller.metadata?.overflowed == true) ...[
              const SizedBox(height: 12),
              Card(
                color: Theme.of(context).colorScheme.errorContainer,
                child: ListTile(
                  leading: const Icon(Icons.warning_amber),
                  title: Text(localizations.hf_capture_overflow_title),
                  subtitle: Text(localizations.hf_capture_overflow_description),
                ),
              ),
            ],
            if (controller.error != null) ...[
              const SizedBox(height: 12),
              Card(
                color: Theme.of(context).colorScheme.errorContainer,
                child: ListTile(
                  leading: const Icon(Icons.error_outline),
                  title: Text(localizations.hf_capture_warning),
                  subtitle: SelectableText(controller.error!),
                  trailing: IconButton(
                    tooltip: localizations.hf_capture_dismiss,
                    onPressed: controller.clearError,
                    icon: const Icon(Icons.close),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 16),
            _buildStorage(context, appState, controller),
            const SizedBox(height: 16),
            _buildRecentFrames(context, controller),
          ],
        ),
      ),
    );
  }

  HfCaptureMode _effectiveMode(HfCaptureController controller) =>
      controller.canStart ? _mode : controller.metadata?.mode ?? _mode;

  Widget _buildHero(
    BuildContext context,
    ChameleonGUIState appState,
    HfCaptureController controller,
  ) {
    final localizations = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    final active = controller.isRunning;
    final draining = !active && controller.needsDrain;
    final finalizing = !active && !draining && controller.needsFinalize;
    final statusLabel = !controller.isConnected
        ? localizations.hf_capture_status_disconnected
        : active
        ? localizations.hf_capture_status_capturing
        : draining
        ? localizations.hf_capture_status_draining
        : finalizing
        ? localizations.hf_capture_status_finalizing
        : controller.isSupported == false
        ? localizations.hf_capture_status_unsupported
        : !controller.canStart
        ? localizations.hf_capture_status_blocked
        : localizations.hf_capture_status_ready;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            colorScheme.primaryContainer,
            colorScheme.tertiaryContainer.withValues(alpha: 0.72),
          ],
        ),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final status = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      active
                          ? Icons.fiber_manual_record
                          : draining
                          ? Icons.downloading
                          : finalizing
                          ? Icons.save
                          : Icons.radar,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      statusLabel,
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  localizations.hf_capture_stream_title,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(localizations.hf_capture_stream_description),
              ],
            );
            final actions = Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                FilledButton.icon(
                  onPressed:
                      controller.isBusy ||
                          _slotBusy ||
                          controller.isSupported == false ||
                          !controller.isConnected ||
                          !controller.canStart ||
                          (_mode == HfCaptureMode.emulation &&
                              (_selectedSlotEntry == null ||
                                  _selectedEmulationCard == null))
                      ? null
                      : () => _start(appState, controller),
                  icon: controller.isBusy && !active
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.play_arrow),
                  label: Text(localizations.hf_capture_start),
                ),
                OutlinedButton.icon(
                  onPressed:
                      controller.isBusy || !active || !controller.isConnected
                      ? null
                      : () => _stop(controller),
                  icon: const Icon(Icons.stop),
                  label: Text(localizations.hf_capture_stop),
                ),
                if (!active &&
                    (controller.needsDrain || controller.needsFinalize))
                  OutlinedButton.icon(
                    onPressed:
                        controller.isBusy ||
                            (controller.needsDrain && !controller.isConnected)
                        ? null
                        : () => _retryDrain(controller),
                    icon: const Icon(Icons.refresh),
                    label: Text(localizations.hf_capture_retry),
                  ),
                if (active && controller.metadata?.mode == HfCaptureMode.reader)
                  OutlinedButton.icon(
                    onPressed: controller.isBusy || !controller.isConnected
                        ? null
                        : () => _probe(controller),
                    icon: const Icon(Icons.contactless),
                    label: Text(localizations.hf_capture_probe),
                  ),
              ],
            );
            if (constraints.maxWidth < 720) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [status, const SizedBox(height: 18), actions],
              );
            }
            return Row(
              children: [
                Expanded(child: status),
                const SizedBox(width: 24),
                actions,
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildModeSelector(HfCaptureController controller) {
    final localizations = AppLocalizations.of(context)!;
    final selectedMode = _effectiveMode(controller);
    final descriptions = switch (selectedMode) {
      HfCaptureMode.emulation =>
        localizations.hf_capture_mode_emulation_description,
      HfCaptureMode.passive =>
        localizations.hf_capture_mode_passive_description,
      HfCaptureMode.reader => localizations.hf_capture_mode_reader_description,
    };
    final setup = switch (selectedMode) {
      HfCaptureMode.emulation => localizations.hf_capture_mode_emulation_setup,
      HfCaptureMode.passive => localizations.hf_capture_mode_passive_setup,
      HfCaptureMode.reader => localizations.hf_capture_mode_reader_setup,
    };
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              localizations.hf_capture_mode_title,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SegmentedButton<HfCaptureMode>(
                segments: [
                  ButtonSegment(
                    value: HfCaptureMode.emulation,
                    icon: const Icon(Icons.nfc),
                    label: Text(localizations.hf_capture_mode_emulation),
                  ),
                  ButtonSegment(
                    value: HfCaptureMode.passive,
                    icon: const Icon(Icons.hearing),
                    label: Text(localizations.hf_capture_mode_passive),
                  ),
                  ButtonSegment(
                    value: HfCaptureMode.reader,
                    icon: const Icon(Icons.sensors),
                    label: Text(localizations.hf_capture_mode_reader),
                  ),
                ],
                selected: {selectedMode},
                onSelectionChanged: !controller.canStart || controller.isBusy
                    ? null
                    : (selection) => setState(() => _mode = selection.single),
              ),
            ),
            const SizedBox(height: 12),
            Text(descriptions),
            const SizedBox(height: 12),
            DecoratedBox(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.secondaryContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.place_outlined, size: 20),
                    const SizedBox(width: 10),
                    Expanded(child: Text(setup)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmulationCard(
    ChameleonGUIState appState,
    HfCaptureController controller,
  ) {
    final localizations = AppLocalizations.of(context)!;
    final selectedEntry = _selectedSlotEntry;
    final card = _selectedEmulationCard;
    final selectionEnabled =
        controller.canStart &&
        !controller.isBusy &&
        !_slotBusy &&
        !_slotsLoading;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.credit_card),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    localizations.hf_capture_emulation_card_title,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                IconButton(
                  tooltip: localizations.hf_capture_refresh_slots,
                  onPressed: selectionEnabled && _slotCommunicator != null
                      ? () => _loadEmulationSlots(appState, _slotCommunicator!)
                      : null,
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(localizations.hf_capture_emulation_card_description),
            if (_slotsLoading) ...[
              const SizedBox(height: 12),
              const LinearProgressIndicator(),
            ],
            const SizedBox(height: 12),
            if (!_slotsLoading && _emulationSlots.isEmpty)
              Text(
                localizations.hf_capture_no_hf_slots,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              )
            else
              DropdownButtonFormField<int>(
                key: ValueKey(_selectedEmulationSlot),
                initialValue: _selectedEmulationSlot,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: localizations.hf_capture_select_slot,
                  border: const OutlineInputBorder(),
                ),
                items: _emulationSlots
                    .map(
                      (entry) => DropdownMenuItem<int>(
                        value: entry.index,
                        child: Text(
                          '${localizations.hf_capture_slot_number(entry.index + 1)} · '
                          '${entry.name} · '
                          '${chameleonTagToString(entry.type, localizations)}',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    )
                    .toList(),
                onChanged: selectionEnabled
                    ? (index) {
                        if (index != null) {
                          unawaited(_selectEmulationSlot(appState, index));
                        }
                      }
                    : null,
              ),
            if (_slotError != null) ...[
              const SizedBox(height: 10),
              SelectableText(
                _slotError!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            if (selectedEntry != null && card != null) ...[
              const SizedBox(height: 16),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _cardDetail(
                    localizations.hf_capture_card_slot,
                    localizations.hf_capture_slot_number(
                      selectedEntry.index + 1,
                    ),
                  ),
                  _cardDetail(
                    localizations.hf_capture_card_name,
                    selectedEntry.name,
                  ),
                  _cardDetail(
                    localizations.hf_capture_card_type,
                    chameleonTagToString(selectedEntry.type, localizations),
                  ),
                  _cardDetail(
                    localizations.hf_capture_card_uid,
                    bytesToHexSpace(card.uid).toUpperCase(),
                  ),
                  _cardDetail(
                    localizations.hf_capture_card_sak,
                    '0x${card.sak.toRadixString(16).padLeft(2, '0').toUpperCase()}',
                  ),
                  _cardDetail(
                    localizations.hf_capture_card_atqa,
                    bytesToHexSpace(card.atqa).toUpperCase(),
                  ),
                  if (card.ats.isNotEmpty)
                    _cardDetail(
                      localizations.hf_capture_card_ats,
                      bytesToHexSpace(card.ats).toUpperCase(),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Icon(
                        _selectedRandomUid
                            ? Icons.shuffle
                            : Icons.verified_outlined,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _selectedRandomUid
                              ? localizations.hf_capture_card_random_uid
                              : localizations.hf_capture_card_confirmed,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _cardDetail(String label, String value) => SizedBox(
    width: 220,
    child: DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: Theme.of(context).textTheme.labelMedium),
            const SizedBox(height: 4),
            SelectableText(
              value,
              style: const TextStyle(
                fontFamily: 'RobotoMono',
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _buildMetrics(BuildContext context, HfCaptureController controller) {
    final localizations = AppLocalizations.of(context)!;
    final metadata = controller.metadata;
    final usage = metadata == null || metadata.capacityBytes == 0
        ? 0.0
        : metadata.usedBytes / metadata.capacityBytes;
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        _metric(
          context,
          localizations.hf_capture_observed,
          '${metadata?.observedRecords ?? 0}',
          Icons.visibility,
        ),
        _metric(
          context,
          localizations.hf_capture_buffered,
          '${metadata?.storedRecords ?? 0}',
          Icons.memory,
        ),
        _metric(
          context,
          localizations.hf_capture_dropped,
          '${metadata?.droppedRecords ?? 0}',
          Icons.report,
        ),
        _metric(
          context,
          localizations.hf_capture_persisted,
          _formatBytes(controller.persistedBytes),
          Icons.save,
        ),
        if (controller.lastReaderCard != null)
          _metric(
            context,
            localizations.hf_capture_last_card,
            bytesToHex(controller.lastReaderCard!.uid).toUpperCase(),
            Icons.contactless,
          ),
        SizedBox(
          width: 230,
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(localizations.hf_capture_device_buffer),
                  const SizedBox(height: 10),
                  LinearProgressIndicator(value: usage.clamp(0, 1)),
                  const SizedBox(height: 8),
                  Text(
                    localizations.hf_capture_buffer_bytes(
                      metadata?.usedBytes ?? 0,
                      metadata?.capacityBytes ?? 0,
                    ),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _metric(
    BuildContext context,
    String label,
    String value,
    IconData icon,
  ) => SizedBox(
    width: 170,
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Icon(icon, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: Theme.of(context).textTheme.bodySmall),
                  Text(
                    value,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
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

  Widget _buildMifareRecovery(
    BuildContext context,
    HfCaptureMifareRecoveryController recoveryController,
  ) {
    final localizations = AppLocalizations.of(context)!;
    final evidence = recoveryController.evidence.reversed.take(50).toList();
    final recoveredKeys = recoveryController.recoveredKeys;
    final status = recoveryController.isRecovering
        ? localizations.hf_capture_recovery_status_recovering
        : evidence.isEmpty
        ? localizations.hf_capture_recovery_status_waiting
        : localizations.hf_capture_recovery_status_monitoring;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.key),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        localizations.hf_capture_recovery_title,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Text(
                        status,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                if (recoveryController.isRecovering)
                  const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(localizations.hf_capture_recovery_description),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _recoveryCount(
                  localizations.hf_capture_recovery_nonce_count,
                  recoveryController.evidence.length,
                ),
                _recoveryCount(
                  localizations.hf_capture_recovery_target_count,
                  recoveryController.targetCount,
                ),
                _recoveryCount(
                  localizations.hf_capture_recovery_key_count,
                  recoveredKeys.length,
                ),
                _recoveryCount(
                  localizations.hf_capture_recovery_saved_count,
                  recoveryController.savedKeyCount,
                ),
              ],
            ),
            if (recoveryController.error != null) ...[
              const SizedBox(height: 12),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Expanded(
                        child: SelectableText(recoveryController.error!),
                      ),
                      IconButton(
                        tooltip: localizations.hf_capture_recovery_retry,
                        onPressed: recoveryController.retry,
                        icon: const Icon(Icons.refresh),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 8),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              childrenPadding: EdgeInsets.zero,
              title: Text(localizations.hf_capture_recovery_nonces_title),
              subtitle: evidence.isEmpty
                  ? Text(localizations.hf_capture_recovery_no_nonces)
                  : null,
              children: [
                for (final item in evidence)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      'UID ${item.uidHex} · ${localizations.sector} '
                      '${item.target.sector} · Key ${item.target.keyType} · '
                      'Block ${item.detection.block}',
                    ),
                    subtitle: SelectableText(
                      'NT=${item.ntHex}  NR=${item.nrHex}\n'
                      'AR=${item.arHex}  AT=${item.atHex ?? "--"}',
                      style: const TextStyle(fontFamily: 'RobotoMono'),
                    ),
                  ),
              ],
            ),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              childrenPadding: EdgeInsets.zero,
              title: Text(localizations.hf_capture_recovery_keys_title),
              subtitle: recoveredKeys.isEmpty
                  ? Text(localizations.hf_capture_recovery_no_keys)
                  : null,
              children: [
                for (final result in recoveredKeys)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      result.saved ? Icons.save : Icons.pending_outlined,
                    ),
                    title: SelectableText(
                      result.keyHex,
                      style: const TextStyle(
                        fontFamily: 'RobotoMono',
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    subtitle: Text(
                      'UID ${result.target.uid.toRadixString(16).padLeft(8, '0').toUpperCase()} · '
                      '${localizations.sector} ${result.target.sector} · '
                      'Key ${result.target.keyType} · ${result.method} · '
                      '${result.saved ? localizations.hf_capture_recovery_saved : localizations.hf_capture_recovery_save_pending}',
                    ),
                    trailing: IconButton(
                      tooltip: localizations.hf_capture_recovery_copy_key,
                      onPressed: () => _copyRecoveredKey(result),
                      icon: const Icon(Icons.copy),
                    ),
                  ),
              ],
            ),
            if (recoveryController.dictionaryNames.isNotEmpty) ...[
              const Divider(),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.menu_book_outlined, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: SelectableText(
                      '${localizations.hf_capture_recovery_dictionaries}: '
                      '${recoveryController.dictionaryNames.join(', ')}',
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _recoveryCount(String label, int count) => Chip(
    avatar: CircleAvatar(child: Text('$count')),
    label: Text(label),
  );

  Widget _buildStorage(
    BuildContext context,
    ChameleonGUIState appState,
    HfCaptureController controller,
  ) {
    final preferences = appState.sharedPreferencesProvider;
    final localizations = AppLocalizations.of(context)!;
    final retention = preferences.getHfCaptureRetentionDays();
    final retentionOptions = {7, 14, 30, 90, 180, 365, retention}.toList()
      ..sort();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.folder_open),
                const SizedBox(width: 8),
                Text(
                  localizations.hf_capture_storage_title,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
            const SizedBox(height: 10),
            SelectableText(
              controller.captureDirectory ??
                  localizations.hf_capture_storage_pending,
              style: const TextStyle(fontFamily: 'RobotoMono'),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Text(localizations.hf_capture_retention_description),
                ),
                const SizedBox(width: 16),
                DropdownButton<int>(
                  value: retention,
                  items: retentionOptions
                      .map(
                        (days) => DropdownMenuItem(
                          value: days,
                          child: Text(
                            localizations.hf_capture_retention_days(days),
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (days) async {
                    if (days == null) return;
                    await _setRetention(appState, controller, days);
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecentFrames(
    BuildContext context,
    HfCaptureController controller,
  ) {
    final localizations = AppLocalizations.of(context)!;
    final records = controller.recentRecords.reversed.take(100).toList();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              localizations.hf_capture_recent_title,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(localizations.hf_capture_recent_description),
            const SizedBox(height: 12),
            if (records.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Center(child: Text(localizations.hf_capture_no_frames)),
              )
            else
              for (final record in records) ...[
                _recordTile(context, record),
                const Divider(height: 1),
              ],
          ],
        ),
      ),
    );
  }

  Widget _recordTile(BuildContext context, HfCaptureRecord record) {
    final localizations = AppLocalizations.of(context)!;
    final direction = switch (record.direction) {
      HfCaptureDirection.readerToCard =>
        localizations.hf_capture_reader_to_card,
      HfCaptureDirection.cardToReader =>
        localizations.hf_capture_card_to_reader,
      HfCaptureDirection.event => localizations.hf_capture_field_event,
    };
    final elapsedMs = (record.timestampTicks * 1000) ~/ 32768;
    final payload = record.type == HfCaptureRecordType.field
        ? (record.data.isNotEmpty && record.data.first == 1
              ? localizations.hf_capture_field_on
              : localizations.hf_capture_field_off)
        : bytesToHexSpace(record.data).toUpperCase();
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        radius: 18,
        child: Text(
          '#${record.sequence}',
          style: const TextStyle(fontSize: 10),
        ),
      ),
      title: Text(direction),
      subtitle: SelectableText(
        payload,
        maxLines: 3,
        style: const TextStyle(fontFamily: 'RobotoMono'),
      ),
      trailing: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 170),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                '${_formatElapsed(elapsedMs)}${record.hasRfError ? '\n${localizations.hf_capture_rf_error}' : ''}',
                textAlign: TextAlign.end,
                style: TextStyle(
                  color: record.hasRfError
                      ? Theme.of(context).colorScheme.error
                      : null,
                ),
              ),
            ),
            if (record.isFrame && record.data.isNotEmpty)
              IconButton(
                tooltip: localizations.hf_capture_copy_raw,
                onPressed: () => _copyRawFrame(record),
                icon: const Icon(Icons.copy),
              ),
          ],
        ),
      ),
    );
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KiB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MiB';
  }

  String _formatElapsed(int milliseconds) {
    final seconds = milliseconds ~/ 1000;
    final remainder = milliseconds % 1000;
    final minutes = seconds ~/ 60;
    final secondPart = seconds % 60;
    if (minutes == 0) {
      return '$secondPart.${remainder.toString().padLeft(3, '0')} s';
    }
    return '$minutes:${secondPart.toString().padLeft(2, '0')}.${remainder.toString().padLeft(3, '0')}';
  }
}

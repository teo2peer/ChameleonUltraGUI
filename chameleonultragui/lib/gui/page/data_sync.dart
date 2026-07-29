import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:chameleonultragui/generated/i18n/app_localizations.dart';
import 'package:chameleonultragui/gui/component/qrcode_scanner.dart';
import 'package:chameleonultragui/helpers/data_sync.dart';
import 'package:chameleonultragui/helpers/data_sync_storage.dart';
import 'package:chameleonultragui/helpers/data_sync_transport.dart';
import 'package:chameleonultragui/main.dart';
import 'package:chameleonultragui/sharedprefsprovider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

String? validateDataSyncPassword(String? value, AppLocalizations strings) {
  if (value == null || value.isEmpty) {
    return strings.data_sync_password_required;
  }
  if (value.length < 8) return strings.data_sync_password_short;
  return null;
}

class DataSyncPage extends StatefulWidget {
  const DataSyncPage({super.key});

  @override
  State<DataSyncPage> createState() => _DataSyncPageState();
}

class _DataSyncPageState extends State<DataSyncPage> {
  DataSyncPeerHost? _host;
  SyncState? _hostBaseState;
  DataSyncClientExchange? _exchange;
  DataSyncHostStatus? _hostStatus;
  SyncCoordinatorRecovery? _pendingCoordinator;
  SyncTransactionReceipt? _pendingParticipant;
  bool _pendingLoaded = false;
  bool _busy = false;

  ChameleonGUIState get _app => context.read<ChameleonGUIState>();
  AppLocalizations get _strings => AppLocalizations.of(context)!;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_pendingLoaded) return;
    _pendingLoaded = true;
    unawaited(_loadPendingRecovery());
  }

  Future<void> _loadPendingRecovery() async {
    final preferences = _app.sharedPreferencesProvider;
    final coordinator = await preferences.getDataSyncCoordinatorRecovery();
    final participant = await preferences.getPendingDataSyncParticipant();
    if (!mounted) return;
    setState(() {
      _pendingCoordinator = coordinator;
      _pendingParticipant = participant;
    });
  }

  @override
  void dispose() {
    final host = _host;
    _host = null;
    if (host != null) unawaited(host.dispose());
    _exchange?.close();
    _exchange = null;
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } catch (_) {
      if (mounted) _message(_strings.data_sync_failed, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _message(String message, {bool error = false}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: error ? Theme.of(context).colorScheme.error : null,
        ),
      );
  }

  Future<void> _startHost() async {
    if (_host != null) return;
    setState(() => _busy = true);
    try {
      final preferences = _app.sharedPreferencesProvider;
      final participant = SharedPreferencesDataSyncParticipant(preferences);
      final pending = await participant.pendingParticipant();
      final baseState = pending == null
          ? await preferences.createSyncState()
          : SyncState(snapshot: SyncSnapshot(), checkpoint: pending.checkpoint);
      final host = await DataSyncPeerHost.start(
        localState: baseState,
        participant: participant,
        onApprove: _approveHostedSnapshot,
        onCommitted: (_) {
          if (!mounted) return;
          setState(() => _pendingParticipant = null);
          _app.changesMade();
          _message(_strings.data_sync_host_applied);
        },
        onStatus: (status) {
          if (mounted) setState(() => _hostStatus = status);
        },
      );
      if (!mounted) {
        await host.dispose();
        return;
      }
      setState(() {
        _host = host;
        _hostBaseState = baseState;
        _hostStatus = host.status;
      });
      unawaited(
        host.done.whenComplete(() async {
          final pendingParticipant = await participant.pendingParticipant();
          if (mounted && identical(_host, host)) {
            setState(() {
              _host = null;
              _hostBaseState = null;
              _pendingParticipant = pendingParticipant;
            });
          }
        }),
      );
    } catch (_) {
      if (mounted) _message(_strings.data_sync_host_failed, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _approveHostedSnapshot(SyncSnapshot snapshot) async {
    if (!mounted) return false;
    final current = await _app.sharedPreferencesProvider.createSyncState();
    if (!mounted) return false;
    if (_hostBaseState?.checkpoint != current.checkpoint) {
      _message(_strings.data_sync_host_local_changed, error: true);
      return false;
    }
    final approved =
        await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            title: Text(_strings.data_sync_host_review_title),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_strings.data_sync_host_review_message),
                const SizedBox(height: 12),
                Text(_snapshotSummary(snapshot, _strings)),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(_strings.data_sync_reject),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(_strings.data_sync_approve),
              ),
            ],
          ),
        ) ??
        false;
    return approved;
  }

  Future<void> _stopHost() async {
    final host = _host;
    if (host == null) return;
    setState(() {
      _host = null;
      _hostBaseState = null;
    });
    await host.dispose();
  }

  Future<void> _joinNearby() async {
    String code = '';
    final formKey = GlobalKey<FormState>();
    final scanned = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(_strings.data_sync_join),
        content: Form(
          key: formKey,
          child: TextFormField(
            key: const Key('data-sync-pairing-code'),
            decoration: InputDecoration(
              labelText: _strings.data_sync_paste_code,
              hintText: _strings.data_sync_pairing_hint,
            ),
            minLines: 2,
            maxLines: 4,
            validator: (value) => value == null || value.trim().isEmpty
                ? _strings.data_sync_pairing_required
                : null,
            onChanged: (value) => code = value,
          ),
        ),
        actions: [
          if (_canScanQr)
            TextButton.icon(
              onPressed: () async {
                final value = await showDialog<String>(
                  context: dialogContext,
                  builder: (_) => const QrCodeScanner(),
                );
                if (value != null && dialogContext.mounted) {
                  Navigator.pop(dialogContext, value);
                }
              },
              icon: const Icon(Icons.qr_code_scanner),
              label: Text(_strings.data_sync_scan_qr),
            ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(_strings.cancel),
          ),
          FilledButton(
            onPressed: () {
              if (formKey.currentState!.validate()) {
                Navigator.pop(dialogContext, code.trim());
              }
            },
            child: Text(_strings.connect),
          ),
        ],
      ),
    );
    if (scanned == null || !mounted) return;
    await _run(() => _connectAndMerge(scanned));
  }

  bool get _canScanQr => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  Future<void> _connectAndMerge(String pairingCode) async {
    final preferences = _app.sharedPreferencesProvider;
    final participant = SharedPreferencesDataSyncParticipant(preferences);
    final recovery = await participant.coordinatorRecovery();
    if (recovery != null) {
      await DataSyncPeerClient.resumePending(
        pairingCode: pairingCode,
        recovery: recovery,
        participant: participant,
      );
      if (!mounted) return;
      setState(() => _pendingCoordinator = null);
      _app.changesMade();
      _message(_strings.data_sync_success);
      return;
    }
    final local = await preferences.createSyncState();
    final exchange = await DataSyncPeerClient.connect(
      pairingCode: pairingCode,
      localState: local,
      participant: participant,
    );
    _exchange = exchange;
    try {
      if (!mounted) return;
      final plan = SyncMergePlan.merge(local.snapshot, exchange.remoteSnapshot);
      final merged = await showDataSyncConflictDialog(
        context,
        plan,
        actionLabel: _strings.data_sync_continue,
      );
      if (merged == null) return;
      final accepted = await exchange.complete(merged);
      _exchange = null;
      if (!mounted) return;
      if (!accepted) {
        _message(_strings.data_sync_host_rejected, error: true);
        return;
      }
      _app.changesMade();
      _message(_strings.data_sync_success);
    } finally {
      if (identical(_exchange, exchange)) {
        exchange.close();
        _exchange = null;
      }
    }
  }

  Future<void> _exportFile() async {
    final password = await _passwordDialog(confirm: true);
    if (password == null || !mounted) return;
    await _run(() async {
      final state = await _app.sharedPreferencesProvider.createSyncState();
      final bytes = await DataSyncBundleCodec.encode(state.snapshot, password);
      final directory = await getTemporaryDirectory();
      final path =
          '${directory.path}/chameleon-${DateTime.now().millisecondsSinceEpoch}.cusync';
      final file = File(path);
      await file.writeAsBytes(bytes, flush: true);
      if (!mounted) return;
      final box = context.findRenderObject() as RenderBox?;
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path, mimeType: 'application/octet-stream')],
          subject: _strings.data_sync_title,
          sharePositionOrigin: box == null
              ? null
              : box.localToGlobal(Offset.zero) & box.size,
        ),
      );
      if (mounted) _message(_strings.data_sync_file_ready);
    });
  }

  Future<void> _importFile() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['cusync'],
    );
    if (result == null || !mounted) return;
    final picked = result.files.single;
    if (picked.size > DataSyncBundleCodec.maxBundleBytes) {
      _message(_strings.data_sync_failed, error: true);
      return;
    }
    late final List<int> bytes;
    try {
      bytes = await picked.readAsBytes();
    } catch (_) {
      if (!mounted) return;
      _message(_strings.data_sync_failed, error: true);
      return;
    }
    if (!mounted) return;
    final password = await _passwordDialog(confirm: false);
    if (password == null || !mounted) return;
    await _run(() async {
      final remote = await DataSyncBundleCodec.decode(bytes, password);
      if (!mounted) return;
      final preferences = _app.sharedPreferencesProvider;
      final local = await preferences.createSyncState();
      if (!mounted) return;
      final plan = SyncMergePlan.merge(local.snapshot, remote);
      final merged = await showDataSyncConflictDialog(
        context,
        plan,
        actionLabel: _strings.data_sync_apply,
      );
      if (merged == null || !mounted) return;
      await preferences.applySyncSnapshot(
        merged,
        expectedCheckpoint: local.checkpoint,
      );
      _app.changesMade();
      _message(_strings.data_sync_success);
    });
  }

  Future<String?> _passwordDialog({required bool confirm}) {
    final formKey = GlobalKey<FormState>();
    var password = '';
    var confirmation = '';
    return showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          confirm
              ? _strings.data_sync_create_password_title
              : _strings.data_sync_import_password_title,
        ),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                key: const Key('data-sync-password'),
                obscureText: true,
                decoration: InputDecoration(
                  labelText: _strings.data_sync_password,
                ),
                validator: confirm
                    ? (value) => validateDataSyncPassword(value, _strings)
                    : (value) => value == null || value.isEmpty
                          ? _strings.data_sync_password_required
                          : null,
                onChanged: (value) => password = value,
              ),
              if (confirm)
                TextFormField(
                  key: const Key('data-sync-password-confirm'),
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: _strings.data_sync_confirm_password,
                  ),
                  validator: (value) => value != password
                      ? _strings.data_sync_password_mismatch
                      : null,
                  onChanged: (value) => confirmation = value,
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(_strings.cancel),
          ),
          FilledButton(
            onPressed: () {
              if (formKey.currentState!.validate() &&
                  (!confirm || confirmation == password)) {
                Navigator.pop(dialogContext, password);
              }
            },
            child: Text(
              confirm
                  ? _strings.data_sync_create_file
                  : _strings.data_sync_unlock,
            ),
          ),
        ],
      ),
    );
  }

  String _statusText(DataSyncHostStatus status) => switch (status) {
    DataSyncHostStatus.listening => _strings.data_sync_status_listening,
    DataSyncHostStatus.connected => _strings.data_sync_status_connected,
    DataSyncHostStatus.receivedSnapshot => _strings.data_sync_status_received,
    DataSyncHostStatus.awaitingApproval => _strings.data_sync_status_approval,
    DataSyncHostStatus.accepted => _strings.data_sync_status_accepted,
    DataSyncHostStatus.rejected => _strings.data_sync_status_rejected,
    DataSyncHostStatus.stopped => _strings.data_sync_status_stopped,
    DataSyncHostStatus.error => _strings.data_sync_status_error,
  };

  @override
  Widget build(BuildContext context) {
    final host = _host;
    return Scaffold(
      appBar: AppBar(title: Text(_strings.data_sync_title)),
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1000),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      _strings.data_sync_intro,
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                    if (_pendingCoordinator != null ||
                        _pendingParticipant != null) ...[
                      const SizedBox(height: 12),
                      Card(
                        color: Theme.of(context).colorScheme.secondaryContainer,
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                _pendingCoordinator != null
                                    ? _strings.data_sync_resume_coordinator(
                                        _pendingCoordinator!.transactionId,
                                      )
                                    : _strings.data_sync_resume_participant(
                                        _pendingParticipant!.transactionId,
                                      ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 20),
                    _SectionTitle(
                      icon: Icons.sync_alt,
                      title: _strings.data_sync_nearby,
                      description: _strings.data_sync_nearby_description,
                    ),
                    const SizedBox(height: 10),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final width = constraints.maxWidth >= 700
                            ? (constraints.maxWidth - 12) / 2
                            : constraints.maxWidth;
                        return Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          children: [
                            SizedBox(
                              width: width,
                              child: _ActionCard(
                                icon: Icons.wifi_tethering,
                                title: _strings.data_sync_host,
                                description:
                                    _strings.data_sync_host_description,
                                action: host == null ? _startHost : _stopHost,
                                actionLabel: host == null
                                    ? _strings.data_sync_host
                                    : _strings.data_sync_stop_host,
                                child: host == null
                                    ? null
                                    : _HostDetails(
                                        host: host,
                                        status: _strings.data_sync_host_status(
                                          _statusText(
                                            _hostStatus ?? host.status,
                                          ),
                                        ),
                                        copyLabel: _strings.data_sync_copy_code,
                                        onCopy: () async {
                                          await Clipboard.setData(
                                            ClipboardData(
                                              text: host.pairingCode,
                                            ),
                                          );
                                          if (mounted) {
                                            _message(
                                              _strings.data_sync_code_copied,
                                            );
                                          }
                                        },
                                      ),
                              ),
                            ),
                            SizedBox(
                              width: width,
                              child: _ActionCard(
                                icon: Icons.devices,
                                title: _strings.data_sync_join,
                                description:
                                    _strings.data_sync_join_description,
                                action: _joinNearby,
                                actionLabel: _strings.data_sync_join,
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 24),
                    _SectionTitle(
                      icon: Icons.lock_outline,
                      title: _strings.data_sync_files,
                      description: _strings.data_sync_files_description,
                    ),
                    const SizedBox(height: 10),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          children: [
                            FilledButton.icon(
                              onPressed: _busy ? null : _exportFile,
                              icon: const Icon(Icons.ios_share),
                              label: Text(_strings.data_sync_export),
                            ),
                            OutlinedButton.icon(
                              onPressed: _busy ? null : _importFile,
                              icon: const Icon(Icons.file_open),
                              label: Text(_strings.data_sync_import),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (_busy)
            Positioned.fill(
              child: ColoredBox(
                color: Theme.of(context).colorScheme.surface.withAlpha(180),
                child: Center(
                  child: Semantics(
                    label: _strings.data_sync_busy,
                    child: const CircularProgressIndicator(),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({
    required this.icon,
    required this.title,
    required this.description,
  });

  final IconData icon;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(icon, color: Theme.of(context).colorScheme.primary),
      const SizedBox(width: 10),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 3),
            Text(description),
          ],
        ),
      ),
    ],
  );
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.action,
    required this.actionLabel,
    this.child,
  });

  final IconData icon;
  final String title;
  final String description;
  final VoidCallback action;
  final String actionLabel;
  final Widget? child;

  @override
  Widget build(BuildContext context) => Card(
    margin: EdgeInsets.zero,
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(description),
          if (child != null) ...[const SizedBox(height: 12), child!],
          const SizedBox(height: 14),
          FilledButton(onPressed: action, child: Text(actionLabel)),
        ],
      ),
    ),
  );
}

class _HostDetails extends StatelessWidget {
  const _HostDetails({
    required this.host,
    required this.status,
    required this.copyLabel,
    required this.onCopy,
  });

  final DataSyncPeerHost host;
  final String status;
  final String copyLabel;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Center(
        child: Container(
          color: Colors.white,
          padding: const EdgeInsets.all(10),
          child: QrImageView(data: host.pairingCode, size: 190),
        ),
      ),
      const SizedBox(height: 8),
      SelectableText(
        host.pairingCode,
        maxLines: 3,
        style: const TextStyle(fontFamily: 'RobotoMono', fontSize: 11),
      ),
      TextButton.icon(
        onPressed: onCopy,
        icon: const Icon(Icons.copy),
        label: Text(copyLabel),
      ),
      Text(status, textAlign: TextAlign.center),
    ],
  );
}

Future<SyncSnapshot?> showDataSyncConflictDialog(
  BuildContext context,
  SyncMergePlan plan, {
  required String actionLabel,
}) {
  return showDialog<SyncSnapshot>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _ConflictDialog(plan: plan, actionLabel: actionLabel),
  );
}

class _ConflictDialog extends StatefulWidget {
  const _ConflictDialog({required this.plan, required this.actionLabel});

  final SyncMergePlan plan;
  final String actionLabel;

  @override
  State<_ConflictDialog> createState() => _ConflictDialogState();
}

class _ConflictDialogState extends State<_ConflictDialog> {
  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context)!;
    final plan = widget.plan;
    return AlertDialog(
      title: Text(strings.data_sync_review_title),
      content: SizedBox(
        width: 680,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                strings.data_sync_conflict_summary(
                  plan.cardConflicts.length,
                  plan.scriptConflicts.length,
                  plan.settingConflicts.length,
                ),
              ),
              const SizedBox(height: 4),
              Text(_snapshotSummary(plan.resolve(), strings)),
              const SizedBox(height: 8),
              Text(strings.data_sync_dictionary_merge),
              if (plan.cardConflicts.isNotEmpty) ...[
                _ConflictHeading(strings.data_sync_card_conflicts),
                for (final conflict in plan.cardConflicts)
                  _cardConflict(conflict, strings),
              ],
              if (plan.scriptConflicts.isNotEmpty) ...[
                _ConflictHeading(strings.data_sync_script_conflicts),
                for (final conflict in plan.scriptConflicts)
                  _scriptConflict(conflict, strings),
              ],
              if (plan.settingConflicts.isNotEmpty) ...[
                _ConflictHeading(strings.data_sync_setting_conflicts),
                for (final conflict in plan.settingConflicts)
                  _settingConflict(conflict, strings),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(strings.cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, plan.resolve()),
          child: Text(widget.actionLabel),
        ),
      ],
    );
  }

  Widget _cardConflict(CardConflict conflict, AppLocalizations strings) => Card(
    child: ExpansionTile(
      title: Text('${conflict.local.name} (${conflict.id})'),
      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      children: [
        _ChoiceRow<SyncChoice>(
          label: strings.data_sync_card_metadata,
          value: conflict.metadataSelection,
          choices: SyncChoice.values,
          choiceLabel: (choice) => choice == SyncChoice.local
              ? '${strings.data_sync_local}: ${conflict.local.name}'
              : '${strings.data_sync_remote}: ${conflict.remote.name}',
          onChanged: (choice) =>
              setState(() => conflict.metadataSelection = choice),
        ),
        for (final index in conflict.differingBlocks)
          _ChoiceRow<SyncChoice>(
            label: strings.data_sync_block(index),
            value: conflict.blockSelections[index]!,
            choices: SyncChoice.values
                .where((choice) => conflict.isBlockAvailable(index, choice))
                .toList(),
            choiceLabel: (choice) {
              final blocks = choice == SyncChoice.local
                  ? conflict.local.data
                  : conflict.remote.data;
              final side = choice == SyncChoice.local
                  ? strings.data_sync_local
                  : strings.data_sync_remote;
              final value = index < blocks.length
                  ? _hex(blocks[index])
                  : strings.data_sync_unavailable_value;
              return '$side: $value';
            },
            onChanged: (choice) =>
                setState(() => conflict.blockSelections[index] = choice),
          ),
      ],
    ),
  );

  Widget _scriptConflict(ScriptConflict conflict, AppLocalizations strings) =>
      Card(
        child: ExpansionTile(
          title: Text(conflict.local.name),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          children: [
            _ChoiceRow<ScriptChoice>(
              label: conflict.id,
              value: conflict.selection,
              choices: ScriptChoice.values,
              choiceLabel: (choice) => switch (choice) {
                ScriptChoice.local => strings.data_sync_local,
                ScriptChoice.remote => strings.data_sync_remote,
                ScriptChoice.keepBoth => strings.data_sync_keep_both,
              },
              onChanged: (choice) =>
                  setState(() => conflict.selection = choice),
            ),
            _SourceText(
              label: strings.data_sync_source(strings.data_sync_local),
              source: conflict.local.source,
            ),
            _SourceText(
              label: strings.data_sync_source(strings.data_sync_remote),
              source: conflict.remote.source,
            ),
          ],
        ),
      );

  Widget _settingConflict(SettingConflict conflict, AppLocalizations strings) =>
      Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: _ChoiceRow<SyncChoice>(
            label: conflict.key,
            value: conflict.selection,
            choices: SyncChoice.values,
            choiceLabel: (choice) {
              final side = choice == SyncChoice.local
                  ? strings.data_sync_local
                  : strings.data_sync_remote;
              final value = choice == SyncChoice.local
                  ? conflict.local
                  : conflict.remote;
              return '$side: ${jsonEncode(value)}';
            },
            onChanged: (choice) => setState(() => conflict.selection = choice),
          ),
        ),
      );
}

class _ConflictHeading extends StatelessWidget {
  const _ConflictHeading(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 18, bottom: 4),
    child: Text(text, style: Theme.of(context).textTheme.titleMedium),
  );
}

class _ChoiceRow<T> extends StatelessWidget {
  const _ChoiceRow({
    required this.label,
    required this.value,
    required this.choices,
    required this.choiceLabel,
    required this.onChanged,
  });

  final String label;
  final T value;
  final List<T> choices;
  final String Function(T) choiceLabel;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            for (final choice in choices)
              ChoiceChip(
                label: Text(choiceLabel(choice)),
                selected: choice == value,
                onSelected: (_) => onChanged(choice),
              ),
          ],
        ),
      ],
    ),
  );
}

class _SourceText extends StatelessWidget {
  const _SourceText({required this.label, required this.source});
  final String label;
  final String source;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 10),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        DecoratedBox(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: SelectableText(
              source,
              style: const TextStyle(fontFamily: 'RobotoMono'),
            ),
          ),
        ),
      ],
    ),
  );
}

String _snapshotSummary(SyncSnapshot snapshot, AppLocalizations strings) =>
    strings.data_sync_summary(
      snapshot.cards.length,
      snapshot.dictionaries.length,
      snapshot.keyboardScripts.length,
      snapshot.settings.length,
    );

String _hex(List<int> bytes) => bytes
    .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
    .join(' ')
    .toUpperCase();

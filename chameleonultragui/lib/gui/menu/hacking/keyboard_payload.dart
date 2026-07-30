import 'package:chameleonultragui/bridge/chameleon.dart';
import 'package:chameleonultragui/bridge/chameleon_keyboard.dart';
import 'package:chameleonultragui/connector/serial_abstract.dart';
import 'package:chameleonultragui/generated/i18n/app_localizations.dart';
import 'package:chameleonultragui/gui/component/module_version_navigation.dart';
import 'package:chameleonultragui/gui/page/data_sync.dart';
import 'package:chameleonultragui/helpers/definitions.dart';
import 'package:chameleonultragui/helpers/keyboard_layout.dart';
import 'package:chameleonultragui/helpers/keyboard_script.dart';
import 'package:chameleonultragui/helpers/module_versions.dart';
import 'package:chameleonultragui/helpers/saved_keyboard_script.dart';
import 'package:chameleonultragui/main.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

const _keyboardCommands = <ChameleonCommand>[
  ChameleonCommand.keyboardUploadBegin,
  ChameleonCommand.keyboardUploadChunk,
  ChameleonCommand.keyboardUploadCommit,
  ChameleonCommand.keyboardRun,
  ChameleonCommand.keyboardCancel,
  ChameleonCommand.keyboardGetStatus,
  ChameleonCommand.keyboardClear,
];

class KeyboardPayloadPage extends StatefulWidget {
  const KeyboardPayloadPage({super.key});

  @override
  State<KeyboardPayloadPage> createState() => _KeyboardPayloadPageState();
}

class _KeyboardPayloadPageState extends State<KeyboardPayloadPage> {
  final _scriptController = TextEditingController(
    text: '''REM Select the target keyboard layout above
STRING Hello from Chameleon!
ENTER
DELAY 500
CTRL L
''',
  );
  Uint8List? _program;
  KeyboardUploadCommitResult? _commit;
  KeyboardStatus? _status;
  KeyboardOutput _output = KeyboardOutput.usb;
  KeyboardLayout _layout = KeyboardLayout.us;
  String? _scriptName;
  final _temporaryBleNameController = TextEditingController();
  String? _result;
  bool _busy = false;

  @override
  void dispose() {
    _scriptController.dispose();
    _temporaryBleNameController.dispose();
    super.dispose();
  }

  void _compile() {
    final localizations = AppLocalizations.of(context)!;
    try {
      final program = compileKeyboardScript(
        _scriptController.text,
        layout: _layout,
      );
      setState(() {
        _program = program;
        _commit = null;
        _result = localizations.keyboard_compile_success(program.length);
      });
    } catch (error) {
      setState(() {
        _program = null;
        _commit = null;
        _result = localizations.keyboard_operation_failed(error.toString());
      });
    }
  }

  Future<void> _perform(Future<void> Function() operation) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await operation();
    } catch (error) {
      if (mounted) {
        setState(
          () => _result = AppLocalizations.of(
            context,
          )!.keyboard_operation_failed(error.toString()),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _upload() => _perform(() async {
    final communicator = context.read<ChameleonGUIState>().communicator!;
    final program = _program!;
    final committed = await communicator.keyboardUpload(program);
    final status = await communicator.keyboardStatus();
    if (!mounted) return;
    setState(() {
      _commit =
          identical(_program, program) && committed.matchesProgram(program)
          ? committed
          : null;
      _status = status;
      _result = AppLocalizations.of(
        context,
      )!.keyboard_upload_success(committed.totalLength, committed.commitId);
    });
  });

  Future<void> _refreshStatus() => _perform(() async {
    final status = await context
        .read<ChameleonGUIState>()
        .communicator!
        .keyboardStatus();
    if (mounted) setState(() => _status = status);
  });

  Future<void> _run() => _perform(() async {
    final communicator = context.read<ChameleonGUIState>().communicator!;
    final program = _program;
    final commit = _commit;
    if (program == null || commit == null || !commit.matchesProgram(program)) {
      throw StateError('The current compiled program has not been uploaded');
    }
    final run = await _startKeyboardRun(communicator, commit.commitId, _output);
    final status = await communicator.keyboardStatus();
    if (!mounted) return;
    setState(() {
      _status = status;
      _result = AppLocalizations.of(context)!.keyboard_run_started(run.runId);
    });
  });

  Future<KeyboardRunResult> _startKeyboardRun(
    ChameleonCommunicator communicator,
    int commitId,
    KeyboardOutput output,
  ) async {
    try {
      return await communicator.keyboardRun(commitId, output);
    } on ChameleonCommandException catch (error) {
      if (output != KeyboardOutput.usb &&
          error.command == ChameleonCommand.keyboardRun &&
          error.status == 0x75) {
        await _showBlePairingMenu();
      }
      rethrow;
    }
  }

  Future<void> _setTemporaryBleName({required bool restore}) =>
      _perform(() async {
        final communicator = context.read<ChameleonGUIState>().communicator!;
        final requestedName = _temporaryBleNameController.text.trim();
        final effective = await communicator.keyboardSetTemporaryBleName(
          restore || requestedName.isEmpty ? null : requestedName,
        );
        if (!mounted) return;
        setState(() {
          if (restore) _temporaryBleNameController.clear();
          _result = AppLocalizations.of(
            context,
          )!.keyboard_ble_name_applied(effective);
        });
      });

  Future<void> _armBle() => _perform(() async {
    final app = context.read<ChameleonGUIState>();
    final communicator = app.communicator!;
    final usingBleControl = app.connector?.connectionType == ConnectionType.ble;
    final program =
        _program ??
        compileKeyboardScript(_scriptController.text, layout: _layout);
    final existingCommit = _commit;
    final commit = existingCommit?.matchesProgram(program) == true
        ? existingCommit!
        : await communicator.keyboardUpload(program);
    final requestedName = _temporaryBleNameController.text.trim();
    final effective = await communicator.keyboardSetTemporaryBleName(
      requestedName.isEmpty ? null : requestedName,
    );
    final armed = await communicator.keyboardArmBle(commit.commitId);
    final status = await communicator.keyboardStatus();
    if (!mounted) return;
    setState(() {
      _program = program;
      _commit = commit;
      _status = status;
      final localizations = AppLocalizations.of(context)!;
      _result = usingBleControl
          ? localizations.keyboard_ble_armed_disconnect(armed.runId, effective)
          : localizations.keyboard_ble_armed(armed.runId, effective);
    });
  });

  Future<void> _saveScript() async {
    final localizations = AppLocalizations.of(context)!;
    var pendingName = _scriptName ?? '';
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(localizations.keyboard_save_script),
        content: TextFormField(
          initialValue: pendingName,
          autofocus: true,
          maxLength: savedKeyboardScriptNameLimit,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(
            labelText: localizations.keyboard_script_name,
            border: const OutlineInputBorder(),
          ),
          onChanged: (value) => pendingName = value,
          onFieldSubmitted: (value) {
            if (value.trim().isNotEmpty) Navigator.pop(dialogContext, value);
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(localizations.cancel),
          ),
          FilledButton(
            onPressed: () {
              if (pendingName.trim().isNotEmpty) {
                Navigator.pop(dialogContext, pendingName);
              }
            },
            child: Text(localizations.save),
          ),
        ],
      ),
    );
    if (name == null || !mounted) return;

    try {
      final appState = context.read<ChameleonGUIState>();
      final provider = appState.sharedPreferencesProvider;
      final scripts = provider.getKeyboardScripts();
      final normalizedName = name.trim();
      final existingIndex = scripts.indexWhere(
        (script) => script.name.toLowerCase() == normalizedName.toLowerCase(),
      );
      if (existingIndex < 0 && scripts.length >= savedKeyboardScriptLimit) {
        throw StateError(localizations.keyboard_script_limit_reached);
      }
      final saved = SavedKeyboardScript.compile(
        id: existingIndex < 0 ? null : scripts[existingIndex].id,
        name: normalizedName,
        source: _scriptController.text,
        layout: _layout,
        output: _output,
      );
      if (existingIndex < 0) {
        scripts.add(saved);
      } else {
        scripts[existingIndex] = saved;
      }
      await provider.setKeyboardScripts(scripts);
      setState(() {
        _scriptName = saved.name;
        _program = Uint8List.fromList(saved.program);
        _commit = null;
        _result = localizations.keyboard_script_saved(
          saved.name,
          saved.program.length,
        );
      });
    } catch (error) {
      setState(
        () =>
            _result = localizations.keyboard_operation_failed(error.toString()),
      );
    }
  }

  Future<void> _showScriptLibrary() async {
    final appState = context.read<ChameleonGUIState>();
    final provider = appState.sharedPreferencesProvider;
    var scripts = provider.getKeyboardScripts();
    final communicator = appState.communicator;
    final canLaunch =
        communicator != null &&
        _keyboardCommands.every(
          (command) => communicator.supportsCommandSync(command) == true,
        );

    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) {
          final localizations = AppLocalizations.of(context)!;
          return FractionallySizedBox(
            heightFactor: 0.8,
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.library_books),
                  title: Text(localizations.keyboard_saved_scripts),
                  subtitle: Text(
                    localizations.keyboard_saved_script_count(scripts.length),
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: scripts.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text(
                              localizations.keyboard_no_saved_scripts,
                              textAlign: TextAlign.center,
                            ),
                          ),
                        )
                      : ListView.separated(
                          itemCount: scripts.length,
                          separatorBuilder: (_, _) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final script = scripts[index];
                            return ListTile(
                              leading: const Icon(Icons.code),
                              title: Text(script.name),
                              subtitle: Text(
                                localizations.keyboard_saved_script_metadata(
                                  _layoutName(localizations, script.layout),
                                  _outputName(localizations, script.output),
                                  script.program.length,
                                ),
                              ),
                              onTap: () {
                                Navigator.pop(sheetContext);
                                _loadSavedScript(script);
                              },
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton.filled(
                                    onPressed: canLaunch
                                        ? () {
                                            Navigator.pop(sheetContext);
                                            _quickLaunch(script);
                                          }
                                        : null,
                                    tooltip:
                                        localizations.keyboard_quick_launch,
                                    icon: const Icon(Icons.play_arrow),
                                  ),
                                  IconButton(
                                    onPressed: () async {
                                      final confirmed = await showDialog<bool>(
                                        context: context,
                                        builder: (dialogContext) => AlertDialog(
                                          title: Text(
                                            localizations
                                                .keyboard_delete_script,
                                          ),
                                          content: Text(
                                            localizations
                                                .keyboard_delete_script_confirmation(
                                                  script.name,
                                                ),
                                          ),
                                          actions: [
                                            TextButton(
                                              onPressed: () => Navigator.pop(
                                                dialogContext,
                                                false,
                                              ),
                                              child: Text(localizations.cancel),
                                            ),
                                            FilledButton(
                                              onPressed: () => Navigator.pop(
                                                dialogContext,
                                                true,
                                              ),
                                              child: Text(localizations.delete),
                                            ),
                                          ],
                                        ),
                                      );
                                      if (confirmed != true) return;
                                      scripts = scripts
                                          .where((item) => item.id != script.id)
                                          .toList();
                                      await provider.setKeyboardScripts(
                                        scripts,
                                      );
                                      setSheetState(() {});
                                    },
                                    tooltip: localizations.delete,
                                    icon: const Icon(Icons.delete_outline),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _loadSavedScript(SavedKeyboardScript script) {
    setState(() {
      _scriptController.text = script.source;
      _scriptName = script.name;
      _layout = script.layout;
      _output = script.output;
      _program = Uint8List.fromList(script.program);
      _commit = null;
      _result = AppLocalizations.of(
        context,
      )!.keyboard_script_loaded(script.name);
    });
  }

  Future<void> _quickLaunch(SavedKeyboardScript script) {
    setState(() => _output = script.output);
    return _perform(() async {
      final communicator = context.read<ChameleonGUIState>().communicator!;
      final committed = await communicator.keyboardUpload(script.program);
      final run = await _startKeyboardRun(
        communicator,
        committed.commitId,
        script.output,
      );
      final status = await communicator.keyboardStatus();
      if (!mounted) return;
      setState(() {
        _status = status;
        _result = AppLocalizations.of(
          context,
        )!.keyboard_quick_launch_started(script.name, run.runId);
      });
    });
  }

  Future<void> _showBlePairingMenu() async {
    final communicator = context.read<ChameleonGUIState>().communicator!;
    var pairingEnabled = false;
    var passkey = '';
    String? error;

    try {
      pairingEnabled = await communicator.isBLEPairEnabled();
      if (pairingEnabled) {
        passkey = await communicator.getBLEConnectionKey();
      }
    } catch (exception) {
      error = exception.toString();
    }
    if (!mounted) return;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          final localizations = AppLocalizations.of(context)!;
          return AlertDialog(
            title: Text(localizations.keyboard_ble_pair_title),
            content: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(localizations.keyboard_ble_pair_instructions),
                  if (_temporaryBleNameController.text.trim().isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      localizations.keyboard_ble_pair_current_name(
                        _temporaryBleNameController.text.trim(),
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  Text(
                    localizations.keyboard_ble_pairing_status(
                      pairingEnabled
                          ? localizations.enabled
                          : localizations.disabled,
                    ),
                  ),
                  if (pairingEnabled && passkey.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    SelectableText(localizations.keyboard_ble_passkey(passkey)),
                  ],
                  if (error != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              if (!pairingEnabled)
                TextButton(
                  onPressed: () async {
                    try {
                      await communicator.setBLEPairEnabled(true);
                      await communicator.saveSettings();
                      final key = await communicator.getBLEConnectionKey();
                      setDialogState(() {
                        pairingEnabled = true;
                        passkey = key;
                        error = null;
                      });
                    } catch (exception) {
                      setDialogState(() => error = exception.toString());
                    }
                  },
                  child: Text(localizations.keyboard_ble_enable_pairing),
                ),
              TextButton(
                onPressed: () async {
                  try {
                    final opened = await launchUrl(
                      _bluetoothSettingsUri(),
                      mode: LaunchMode.externalApplication,
                    );
                    if (!opened) {
                      throw StateError(
                        localizations.keyboard_ble_settings_unavailable,
                      );
                    }
                  } catch (exception) {
                    setDialogState(() => error = exception.toString());
                  }
                },
                child: Text(localizations.keyboard_ble_open_settings),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: Text(localizations.close),
              ),
            ],
          );
        },
      ),
    );
  }

  Uri _bluetoothSettingsUri() => switch (defaultTargetPlatform) {
    TargetPlatform.macOS => Uri.parse(
      'x-apple.systempreferences:com.apple.Bluetooth',
    ),
    TargetPlatform.windows => Uri.parse('ms-settings:bluetooth'),
    TargetPlatform.iOS => Uri.parse('App-Prefs:Bluetooth'),
    TargetPlatform.android => Uri.parse('android.settings.BLUETOOTH_SETTINGS'),
    TargetPlatform.linux || TargetPlatform.fuchsia => Uri.parse(
      'https://support.google.com/chromebook/answer/2587653',
    ),
  };

  Future<void> _cancel() => _perform(() async {
    final communicator = context.read<ChameleonGUIState>().communicator!;
    await communicator.keyboardCancel();
    final status = await communicator.keyboardStatus();
    if (!mounted) return;
    setState(() {
      _status = status;
      _result = AppLocalizations.of(context)!.keyboard_cancelled;
    });
  });

  Future<void> _clear() => _perform(() async {
    final communicator = context.read<ChameleonGUIState>().communicator!;
    await communicator.keyboardClear();
    final status = await communicator.keyboardStatus();
    if (!mounted) return;
    setState(() {
      _commit = null;
      _status = status;
      _result = AppLocalizations.of(context)!.keyboard_cleared;
    });
  });

  @override
  Widget build(BuildContext context) {
    final app = context.watch<ChameleonGUIState>();
    final localizations = AppLocalizations.of(context)!;
    final communicator = app.communicator;
    final unsupported =
        communicator == null ||
        _keyboardCommands.any(
          (command) => communicator.supportsCommandSync(command) != true,
        );
    final connectionType = app.connector?.connectionType ?? ConnectionType.none;
    final uploadTransport =
        connectionType == ConnectionType.usb ||
        connectionType == ConnectionType.ble;
    final runTransport = uploadTransport;
    final armSupported =
        communicator != null &&
        communicator.supportsCommandSync(
              ChameleonCommand.keyboardSetTemporaryBleName,
            ) ==
            true &&
        communicator.supportsCommandSync(ChameleonCommand.keyboardArmBle) ==
            true;
    final program = _program;
    final currentCommit =
        program != null && _commit?.matchesProgram(program) == true;
    final armed = _status?.state == KeyboardPayloadState.armed;

    return Scaffold(
      appBar: AppBar(
        title: Text(localizations.keyboard_payload),
        actions: [
          IconButton(
            onPressed: _busy
                ? null
                : () => Navigator.push(
                    context,
                    ModulePageRoute<void>(
                      moduleId: ModuleId.ethicalHacking,
                      builder: (_) => const DataSyncPage(),
                    ),
                  ),
            tooltip: localizations.data_sync_title,
            icon: const Icon(Icons.sync_alt),
          ),
          IconButton(
            onPressed: _busy ? null : _showScriptLibrary,
            tooltip: localizations.keyboard_saved_scripts,
            icon: const Icon(Icons.library_books),
          ),
        ],
      ),
      body: unsupported
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  localizations.keyboard_firmware_unsupported,
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : LayoutBuilder(
              builder: (context, constraints) {
                final editor = _editorCard(context);
                final controls = _controlsCard(
                  context,
                  uploadEnabled:
                      !_busy && !armed && uploadTransport && _program != null,
                  runEnabled: !_busy && !armed && runTransport && currentCommit,
                  armEnabled:
                      !_busy && !armed && uploadTransport && armSupported,
                  armSupported: armSupported,
                  armed: armed,
                );
                return SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: constraints.maxWidth >= 800
                      ? Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(flex: 3, child: editor),
                            const SizedBox(width: 16),
                            Expanded(flex: 2, child: controls),
                          ],
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            editor,
                            const SizedBox(height: 16),
                            controls,
                          ],
                        ),
                );
              },
            ),
    );
  }

  Widget _editorCard(BuildContext context) {
    final localizations = AppLocalizations.of(context)!;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              localizations.keyboard_script,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 6),
            Text(localizations.keyboard_payload_description),
            const SizedBox(height: 16),
            DropdownButtonFormField<KeyboardLayout>(
              key: ValueKey('keyboard-layout-selector-${_layout.name}'),
              initialValue: _layout,
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                labelText: localizations.keyboard_layout,
              ),
              items: KeyboardLayout.values
                  .map(
                    (layout) => DropdownMenuItem(
                      value: layout,
                      child: Text(_layoutName(localizations, layout)),
                    ),
                  )
                  .toList(),
              onChanged: _busy
                  ? null
                  : (layout) {
                      if (layout == null || layout == _layout) return;
                      setState(() {
                        _layout = layout;
                        _program = null;
                        _commit = null;
                        _result = null;
                      });
                    },
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _scriptController,
              minLines: 14,
              maxLines: 24,
              autocorrect: false,
              enableSuggestions: false,
              style: const TextStyle(fontFamily: 'monospace'),
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                hintText: localizations.keyboard_script_hint,
              ),
              onChanged: (_) {
                if (_program != null || _commit != null) {
                  setState(() {
                    _program = null;
                    _commit = null;
                  });
                }
              },
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: _busy ? null : _compile,
                  icon: const Icon(Icons.code),
                  label: Text(localizations.keyboard_compile),
                ),
                FilledButton.tonalIcon(
                  onPressed: _busy ? null : _saveScript,
                  icon: const Icon(Icons.save),
                  label: Text(localizations.keyboard_save_script),
                ),
                OutlinedButton.icon(
                  onPressed: _busy ? null : _showScriptLibrary,
                  icon: const Icon(Icons.library_books),
                  label: Text(localizations.keyboard_saved_scripts),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _layoutName(AppLocalizations localizations, KeyboardLayout layout) =>
      switch (layout) {
        KeyboardLayout.us => localizations.keyboard_layout_us,
        KeyboardLayout.uk => localizations.keyboard_layout_uk,
        KeyboardLayout.es => localizations.keyboard_layout_es,
        KeyboardLayout.de => localizations.keyboard_layout_de,
        KeyboardLayout.fr => localizations.keyboard_layout_fr,
        KeyboardLayout.it => localizations.keyboard_layout_it,
        KeyboardLayout.pt => localizations.keyboard_layout_pt,
      };

  String _outputName(AppLocalizations localizations, KeyboardOutput output) =>
      switch (output) {
        KeyboardOutput.usb => localizations.keyboard_output_usb,
        KeyboardOutput.ble => localizations.keyboard_output_ble,
        KeyboardOutput.both => localizations.keyboard_output_both,
      };

  Widget _controlsCard(
    BuildContext context, {
    required bool uploadEnabled,
    required bool runEnabled,
    required bool armEnabled,
    required bool armSupported,
    required bool armed,
  }) {
    final localizations = AppLocalizations.of(context)!;
    final status = _status;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              localizations.keyboard_output,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            SegmentedButton<KeyboardOutput>(
              segments: [
                ButtonSegment(
                  value: KeyboardOutput.usb,
                  icon: const Icon(Icons.usb),
                  label: Text(localizations.keyboard_output_usb),
                ),
                ButtonSegment(
                  value: KeyboardOutput.ble,
                  icon: const Icon(Icons.bluetooth),
                  label: Text(localizations.keyboard_output_ble),
                ),
                ButtonSegment(
                  value: KeyboardOutput.both,
                  icon: const Icon(Icons.call_split),
                  label: Text(localizations.keyboard_output_both),
                ),
              ],
              selected: {_output},
              onSelectionChanged: _busy || armed
                  ? null
                  : (selection) => setState(() => _output = selection.single),
            ),
            const SizedBox(height: 12),
            Text(
              localizations.keyboard_ble_run_requirement,
              style: TextStyle(color: Theme.of(context).colorScheme.secondary),
            ),
            if (_output != KeyboardOutput.usb) ...[
              const SizedBox(height: 8),
              if (armSupported) ...[
                TextFormField(
                  controller: _temporaryBleNameController,
                  enabled: !_busy && !armed,
                  decoration: InputDecoration(
                    border: const OutlineInputBorder(),
                    labelText: localizations.keyboard_ble_temporary_name,
                    helperText: localizations.keyboard_ble_name_help,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: _busy || armed
                          ? null
                          : () => _setTemporaryBleName(restore: false),
                      icon: const Icon(Icons.badge_outlined),
                      label: Text(localizations.keyboard_ble_apply_name),
                    ),
                    TextButton(
                      onPressed: _busy || armed
                          ? null
                          : () => _setTemporaryBleName(restore: true),
                      child: Text(localizations.keyboard_ble_restore_name),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(localizations.keyboard_ble_arm_explanation),
                const SizedBox(height: 8),
                FilledButton.icon(
                  onPressed: armEnabled ? _armBle : null,
                  icon: const Icon(Icons.sensors),
                  label: Text(localizations.keyboard_ble_advertise_and_arm),
                ),
              ] else
                Text(localizations.keyboard_ble_arm_unsupported),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  onPressed: _busy ? null : _showBlePairingMenu,
                  icon: const Icon(Icons.bluetooth_searching),
                  label: Text(localizations.keyboard_ble_pair_host),
                ),
              ),
            ],
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.tonalIcon(
                  onPressed: uploadEnabled ? _upload : null,
                  icon: const Icon(Icons.upload),
                  label: Text(localizations.keyboard_upload),
                ),
                OutlinedButton.icon(
                  onPressed: _busy ? null : _refreshStatus,
                  icon: const Icon(Icons.sync),
                  label: Text(localizations.keyboard_status),
                ),
                FilledButton.icon(
                  onPressed: runEnabled ? _run : null,
                  icon: const Icon(Icons.play_arrow),
                  label: Text(localizations.keyboard_run),
                ),
                OutlinedButton.icon(
                  onPressed: _busy ? null : _cancel,
                  icon: const Icon(Icons.stop),
                  label: Text(localizations.keyboard_cancel),
                ),
                TextButton.icon(
                  onPressed: _busy ? null : _clear,
                  icon: const Icon(Icons.delete_outline),
                  label: Text(localizations.keyboard_clear),
                ),
              ],
            ),
            if (_busy) ...[
              const SizedBox(height: 16),
              const LinearProgressIndicator(),
            ],
            if (status != null) ...[
              const SizedBox(height: 20),
              Text(
                localizations.keyboard_status,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 6),
              SelectableText(
                localizations.keyboard_status_summary(
                  status.error,
                  status.expected,
                  status.length,
                  status.programCounter,
                  status.received,
                  status.state.name,
                ),
              ),
            ],
            if (_result != null) ...[
              const SizedBox(height: 16),
              SelectableText(_result!),
            ],
          ],
        ),
      ),
    );
  }
}

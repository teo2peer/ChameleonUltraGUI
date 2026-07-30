import 'dart:typed_data';

import 'package:chameleonultragui/helpers/definitions.dart';
import 'package:chameleonultragui/helpers/general.dart';
import 'package:chameleonultragui/helpers/pm3_protocol.dart';
import 'package:chameleonultragui/main.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class Pm3Hf14aInspectorPage extends StatefulWidget {
  const Pm3Hf14aInspectorPage({super.key});

  @override
  State<Pm3Hf14aInspectorPage> createState() => _Pm3Hf14aInspectorPageState();
}

class _Pm3Hf14aInspectorPageState extends State<Pm3Hf14aInspectorPage> {
  CardData? _card;
  Pm3Hf14aConfig? _config;
  String? _error;
  bool _busy = false;

  ChameleonGUIState get _app => context.read<ChameleonGUIState>();
  bool get _connected => _app.connector?.connected ?? false;

  Future<void> _run(Future<void> Function() operation) async {
    if (!_connected || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final communicator = _app.communicator!;
      if (!await communicator.isReaderDeviceMode()) {
        await communicator.setReaderDeviceMode(true);
      }
      await operation();
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _scan({required bool keepField}) => _run(() async {
    final card = keepField
        ? await _app.communicator!.scan14443aTagKeep()
        : await _app.communicator!.scan14443aTag();
    if (mounted) setState(() => _card = card);
  });

  Future<void> _loadConfig() => _run(() async {
    final config = await _app.communicator!.getHf14aConfig();
    if (mounted) setState(() => _config = config);
  });

  Future<void> _changeConfig(
    Pm3Hf14aConfig? current,
    int Function(Pm3Hf14aConfig config) read,
    Pm3Hf14aConfig Function(Pm3Hf14aConfig config, int value) write,
    int value,
  ) async {
    if (current == null || read(current) == value) return;
    await _run(() async {
      final next = write(current, value);
      await _app.communicator!.setHf14aConfig(next);
      if (mounted) setState(() => _config = next);
    });
  }

  String _hex(Uint8List data) => bytesToHexSpace(data).toUpperCase();

  Widget _configSelector(
    String label,
    Pm3Hf14aConfig? config,
    int Function(Pm3Hf14aConfig config) read,
    Pm3Hf14aConfig Function(Pm3Hf14aConfig config, int value) write,
  ) {
    final selectedValue = config == null ? null : read(config);
    return DropdownButtonFormField<int>(
      key: ValueKey('$label-$selectedValue'),
      initialValue: selectedValue,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
      hint: const Text('Load configuration first'),
      items: const [
        DropdownMenuItem(value: 0, child: Text('Auto')),
        DropdownMenuItem(value: 1, child: Text('Force')),
        DropdownMenuItem(value: 2, child: Text('Skip')),
      ],
      onChanged: config == null || _busy
          ? null
          : (value) => _changeConfig(config, read, write, value!),
    );
  }

  @override
  Widget build(BuildContext context) {
    final card = _card;
    final config = _config;
    return Scaffold(
      appBar: AppBar(title: const Text('PM3 hf 14a info')),
      body: !_connected
          ? const Center(child: Text('Connect a Chameleon Ultra first'))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  'Inspect an ISO14443-A card using the device reader. “Select and keep field” leaves an ISO-DEP card ready for the raw exchange tool.',
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    FilledButton.icon(
                      onPressed: _busy ? null : () => _scan(keepField: false),
                      icon: const Icon(Icons.contactless),
                      label: const Text('Scan card'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _busy ? null : () => _scan(keepField: true),
                      icon: const Icon(Icons.link),
                      label: const Text('Select and keep field'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _busy ? null : _loadConfig,
                      icon: const Icon(Icons.tune),
                      label: const Text('Read reader configuration'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _busy
                          ? null
                          : () => _run(
                              () => _app.communicator!.setHf14aField(false),
                            ),
                      icon: const Icon(Icons.power_off),
                      label: const Text('Turn field off'),
                    ),
                  ],
                ),
                if (_busy) ...[
                  const SizedBox(height: 16),
                  const LinearProgressIndicator(),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  _MessageCard(message: _error!, error: true),
                ],
                const SizedBox(height: 20),
                _Panel(
                  title: 'Card response',
                  child: card == null
                      ? const Text('No card scanned yet.')
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _KeyValue('UID', _hex(card.uid)),
                            _KeyValue('ATQA', _hex(card.atqa)),
                            _KeyValue(
                              'SAK',
                              card.sak
                                  .toRadixString(16)
                                  .padLeft(2, '0')
                                  .toUpperCase(),
                            ),
                            _KeyValue(
                              'ATS',
                              card.ats.isEmpty ? 'Not present' : _hex(card.ats),
                            ),
                          ],
                        ),
                ),
                const SizedBox(height: 16),
                _Panel(
                  title: 'hf 14a config',
                  child: Column(
                    children: [
                      _configSelector(
                        'Cascade level 1',
                        config,
                        (value) => value.uidCl1,
                        (value, next) => Pm3Hf14aConfig(
                          uidCl1: next,
                          uidCl2: value.uidCl2,
                          uidCl3: value.uidCl3,
                          rats: value.rats,
                        ),
                      ),
                      const SizedBox(height: 12),
                      _configSelector(
                        'Cascade level 2',
                        config,
                        (value) => value.uidCl2,
                        (value, next) => Pm3Hf14aConfig(
                          uidCl1: value.uidCl1,
                          uidCl2: next,
                          uidCl3: value.uidCl3,
                          rats: value.rats,
                        ),
                      ),
                      const SizedBox(height: 12),
                      _configSelector(
                        'Cascade level 3',
                        config,
                        (value) => value.uidCl3,
                        (value, next) => Pm3Hf14aConfig(
                          uidCl1: value.uidCl1,
                          uidCl2: value.uidCl2,
                          uidCl3: next,
                          rats: value.rats,
                        ),
                      ),
                      const SizedBox(height: 12),
                      _configSelector(
                        'RATS',
                        config,
                        (value) => value.rats,
                        (value, next) => Pm3Hf14aConfig(
                          uidCl1: value.uidCl1,
                          uidCl2: value.uidCl2,
                          uidCl3: value.uidCl3,
                          rats: next,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}

class Pm3Hf14aRawPage extends StatefulWidget {
  const Pm3Hf14aRawPage({super.key});

  @override
  State<Pm3Hf14aRawPage> createState() => _Pm3Hf14aRawPageState();
}

class _Pm3Hf14aRawPageState extends State<Pm3Hf14aRawPage> {
  final _formKey = GlobalKey<FormState>();
  final _payload = TextEditingController(text: '26');
  final _timeout = TextEditingController(text: '100');
  final _bits = TextEditingController();
  bool _activateField = true;
  bool _waitResponse = true;
  bool _appendCrc = false;
  bool _autoSelect = false;
  bool _keepField = false;
  bool _checkResponseCrc = false;
  bool _busy = false;
  Pm3Hf14aRawResponse? _response;
  String? _error;

  ChameleonGUIState get _app => context.read<ChameleonGUIState>();
  bool get _connected => _app.connector?.connected ?? false;

  @override
  void dispose() {
    _payload.dispose();
    _timeout.dispose();
    _bits.dispose();
    super.dispose();
  }

  String? _hexValidator(String? value) {
    final input = value?.trim().replaceAll(RegExp(r'\s+'), '') ?? '';
    if (input.isEmpty) return 'Enter a frame in hexadecimal.';
    if (input.length.isOdd || input.length > pm3Hf14aRawMaxBytes * 2) {
      return 'Use 1..$pm3Hf14aRawMaxBytes whole bytes.';
    }
    try {
      hexToBytes(input);
    } catch (_) {
      return 'Invalid hexadecimal frame.';
    }
    return null;
  }

  Future<void> _send() async {
    if (!_connected || _busy || !_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
      _response = null;
    });
    try {
      final payload = Uint8List.fromList(
        hexToBytes(_payload.text.replaceAll(RegExp(r'\s+'), '')),
      );
      final bitLength = _bits.text.trim().isEmpty
          ? payload.length * 8
          : int.parse(_bits.text.trim());
      final request = Pm3Hf14aRawRequest(
        data: payload,
        bitLength: bitLength,
        responseTimeoutMs: int.parse(_timeout.text.trim()),
        activateField: _activateField,
        waitResponse: _waitResponse,
        appendCrc: _appendCrc,
        autoSelect: _autoSelect,
        keepField: _keepField,
        checkResponseCrc: _checkResponseCrc,
      );
      final communicator = _app.communicator!;
      if (!await communicator.isReaderDeviceMode()) {
        await communicator.setReaderDeviceMode(true);
      }
      final response = await communicator.hf14aRaw(request);
      if (mounted) setState(() => _response = response);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _switch(String label, bool value, ValueChanged<bool> onChanged) {
    return SizedBox(
      width: 250,
      child: SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(label),
        value: value,
        onChanged: _busy ? null : onChanged,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final response = _response;
    return Scaffold(
      appBar: AppBar(title: const Text('PM3 hf 14a raw')),
      body: !_connected
          ? const Center(child: Text('Connect a Chameleon Ultra first'))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Transmit a bounded ISO14443-A frame through firmware command 2010. Use only with cards and readers you own or are authorised to test.',
                        style: Theme.of(context).textTheme.bodyLarge,
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _payload,
                        validator: _hexValidator,
                        decoration: const InputDecoration(
                          labelText: 'Frame (hex)',
                          helperText: 'Up to 64 bytes. Example REQA: 26',
                          border: OutlineInputBorder(),
                        ),
                        style: const TextStyle(fontFamily: 'RobotoMono'),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          SizedBox(
                            width: 220,
                            child: TextFormField(
                              controller: _bits,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: 'Bit length',
                                helperText: 'Blank = all frame bytes',
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ),
                          SizedBox(
                            width: 220,
                            child: TextFormField(
                              controller: _timeout,
                              keyboardType: TextInputType.number,
                              validator: (value) {
                                final timeout = int.tryParse(
                                  value?.trim() ?? '',
                                );
                                return timeout == null ||
                                        timeout < 1 ||
                                        timeout > 65535
                                    ? 'Use 1..65535 ms.'
                                    : null;
                              },
                              decoration: const InputDecoration(
                                labelText: 'Response timeout (ms)',
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 16,
                        runSpacing: 0,
                        children: [
                          _switch(
                            'Activate field',
                            _activateField,
                            (value) => setState(() => _activateField = value),
                          ),
                          _switch(
                            'Wait for response',
                            _waitResponse,
                            (value) => setState(() => _waitResponse = value),
                          ),
                          _switch(
                            'Append CRC-A',
                            _appendCrc,
                            (value) => setState(() => _appendCrc = value),
                          ),
                          _switch(
                            'Auto-select tag',
                            _autoSelect,
                            (value) => setState(() => _autoSelect = value),
                          ),
                          _switch(
                            'Keep field active',
                            _keepField,
                            (value) => setState(() => _keepField = value),
                          ),
                          _switch(
                            'Check response CRC',
                            _checkResponseCrc,
                            (value) =>
                                setState(() => _checkResponseCrc = value),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        onPressed: _busy ? null : _send,
                        icon: _busy
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.send),
                        label: const Text('Transmit frame'),
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 16),
                        _MessageCard(message: _error!, error: true),
                      ],
                      if (response != null) ...[
                        const SizedBox(height: 16),
                        _Panel(
                          title: 'Device response',
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _KeyValue(
                                'Status',
                                '0x${response.status.toRadixString(16).padLeft(2, '0').toUpperCase()}',
                              ),
                              _KeyValue(
                                'Frame',
                                response.data.isEmpty
                                    ? 'No response data'
                                    : bytesToHexSpace(
                                        response.data,
                                      ).toUpperCase(),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
    );
  }
}

class _Panel extends StatelessWidget {
  final String title;
  final Widget child;

  const _Panel({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

class _KeyValue extends StatelessWidget {
  final String label;
  final String value;

  const _KeyValue(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: SelectableText('$label: $value'),
    );
  }
}

class _MessageCard extends StatelessWidget {
  final String message;
  final bool error;

  const _MessageCard({required this.message, required this.error});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      color: error ? colors.errorContainer : colors.primaryContainer,
      child: Padding(padding: const EdgeInsets.all(12), child: Text(message)),
    );
  }
}

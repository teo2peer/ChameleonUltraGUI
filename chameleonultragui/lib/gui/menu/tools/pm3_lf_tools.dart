import 'dart:typed_data';

import 'package:chameleonultragui/helpers/general.dart';
import 'package:chameleonultragui/helpers/pm3_protocol.dart';
import 'package:chameleonultragui/main.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class Pm3LfDiscoveryPage extends StatefulWidget {
  const Pm3LfDiscoveryPage({super.key});

  @override
  State<Pm3LfDiscoveryPage> createState() => _Pm3LfDiscoveryPageState();
}

class _Pm3LfDiscoveryPageState extends State<Pm3LfDiscoveryPage> {
  bool _busy = false;
  String? _error;
  List<_LfResult> _results = const [];

  ChameleonGUIState get _app => context.read<ChameleonGUIState>();
  bool get _connected => _app.connector?.connected ?? false;

  Future<void> _scan() async {
    if (!_connected || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
      _results = const [];
    });
    try {
      final communicator = _app.communicator!;
      if (!await communicator.isReaderDeviceMode()) {
        await communicator.setReaderDeviceMode(true);
      }
      final results = <_LfResult>[];
      final em410x = await communicator.readEM410X();
      if (em410x != null) {
        results.add(_LfResult('EM410x', em410x.toViewableString()));
      }
      final hid = await communicator.readHIDProx();
      if (hid != null) {
        results.add(_LfResult('HID Prox', hid.toViewableString()));
      }
      final ioProx = await communicator.readIoProx();
      if (ioProx != null) {
        results.add(_LfResult('ioProx', ioProx.toViewableString()));
      }
      final pac = await communicator.readPac();
      if (pac != null) {
        results.add(_LfResult('PAC/Stanley', pac.toViewableString()));
      }
      final viking = await communicator.readViking();
      if (viking != null) {
        results.add(_LfResult('Viking', viking.toViewableString()));
      }
      final jablotron = await communicator.readJablotron();
      if (jablotron != null) {
        results.add(
          _LfResult('Jablotron', bytesToHexSpace(jablotron).toUpperCase()),
        );
      }
      if (mounted) setState(() => _results = results);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('PM3 lf search')),
      body: !_connected
          ? const Center(child: Text('Connect a Chameleon Ultra first'))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  'Run the supported LF protocol readers in sequence: EM410x, HID Prox, ioProx, PAC, Viking, and Jablotron.',
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: _busy ? null : _scan,
                  icon: _busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.radar),
                  label: const Text('Scan supported LF protocols'),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  _LfMessage(_error!, error: true),
                ],
                const SizedBox(height: 20),
                if (!_busy && _error == null && _results.isEmpty)
                  const _LfMessage(
                    'No compatible tag detected yet. Start a scan with the device positioned over a tag.',
                  ),
                ..._results.map(
                  (result) => Card(
                    child: ListTile(
                      leading: const Icon(Icons.key),
                      title: Text(result.protocol),
                      subtitle: SelectableText(result.value),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

class Pm3LfAdcPage extends StatefulWidget {
  const Pm3LfAdcPage({super.key});

  @override
  State<Pm3LfAdcPage> createState() => _Pm3LfAdcPageState();
}

class _Pm3LfAdcPageState extends State<Pm3LfAdcPage> {
  bool _busy = false;
  Uint8List? _samples;
  String? _error;

  ChameleonGUIState get _app => context.read<ChameleonGUIState>();
  bool get _connected => _app.connector?.connected ?? false;

  Future<void> _capture() async {
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
      final samples = await communicator.readLfAdc();
      if (mounted) setState(() => _samples = samples);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final samples = _samples;
    final minimum = samples?.reduce(
      (left, right) => left < right ? left : right,
    );
    final maximum = samples?.reduce(
      (left, right) => left > right ? left : right,
    );
    final preview = samples == null
        ? null
        : bytesToHexSpace(
            samples.sublist(0, samples.length < 128 ? samples.length : 128),
          ).toUpperCase();
    return Scaffold(
      appBar: AppBar(title: const Text('PM3 lf read ADC')),
      body: !_connected
          ? const Center(child: Text('Connect a Chameleon Ultra first'))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  'Capture the firmware ADC window from the LF antenna. Use LF sniff for a longer waveform capture and decoder.',
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: _busy ? null : _capture,
                  icon: _busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.graphic_eq),
                  label: const Text('Capture ADC window'),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  _LfMessage(_error!, error: true),
                ],
                if (samples != null) ...[
                  const SizedBox(height: 20),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Capture',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 12),
                          Text('Samples: ${samples.length}'),
                          Text(
                            'Range: 0x${minimum!.toRadixString(16).padLeft(2, '0')} - 0x${maximum!.toRadixString(16).padLeft(2, '0')}',
                          ),
                          const SizedBox(height: 12),
                          SelectableText(
                            preview!,
                            style: const TextStyle(fontFamily: 'RobotoMono'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
    );
  }
}

class Pm3T55xxBlockWriterPage extends StatefulWidget {
  const Pm3T55xxBlockWriterPage({super.key});

  @override
  State<Pm3T55xxBlockWriterPage> createState() =>
      _Pm3T55xxBlockWriterPageState();
}

class _Pm3T55xxBlockWriterPageState extends State<Pm3T55xxBlockWriterPage> {
  final _formKey = GlobalKey<FormState>();
  final _block = TextEditingController(text: '0');
  final _word = TextEditingController();
  final _password = TextEditingController();
  bool _page1 = false;
  bool _busy = false;
  String? _message;
  String? _error;

  ChameleonGUIState get _app => context.read<ChameleonGUIState>();
  bool get _connected => _app.connector?.connected ?? false;

  @override
  void dispose() {
    _block.dispose();
    _word.dispose();
    _password.dispose();
    super.dispose();
  }

  String? _wordValidator(String? value, {bool optional = false}) {
    final text = value?.trim() ?? '';
    if (text.isEmpty && optional) return null;
    if (!RegExp(r'^[0-9a-fA-F]{8}$').hasMatch(text)) {
      return 'Enter exactly eight hexadecimal digits.';
    }
    return null;
  }

  Future<void> _write() async {
    if (!_connected || _busy || !_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
      _message = null;
    });
    try {
      final communicator = _app.communicator!;
      if (!await communicator.isReaderDeviceMode()) {
        await communicator.setReaderDeviceMode(true);
      }
      await communicator.writeT55xxBlock(
        block: int.parse(_block.text),
        word: int.parse(_word.text, radix: 16),
        password: _password.text.trim().isEmpty
            ? null
            : int.parse(_password.text.trim(), radix: 16),
        page1: _page1,
      );
      if (mounted) setState(() => _message = 'Block written successfully.');
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('PM3 lf t55xx write')),
      body: !_connected
          ? const Center(child: Text('Connect a Chameleon Ultra first'))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 620),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Write one 32-bit word using firmware command 3016. Confirm the block, page, and optional password before writing.',
                        style: Theme.of(context).textTheme.bodyLarge,
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _block,
                        keyboardType: TextInputType.number,
                        validator: (value) {
                          final block = int.tryParse(value?.trim() ?? '');
                          final max = _page1 ? 3 : 7;
                          return block == null || block < 0 || block > max
                              ? 'Use a block between 0 and $max.'
                              : null;
                        },
                        decoration: const InputDecoration(
                          labelText: 'Block',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _word,
                        validator: _wordValidator,
                        decoration: const InputDecoration(
                          labelText: 'Data word (8 hex digits)',
                          border: OutlineInputBorder(),
                        ),
                        style: const TextStyle(fontFamily: 'RobotoMono'),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _password,
                        validator: (value) =>
                            _wordValidator(value, optional: true),
                        decoration: const InputDecoration(
                          labelText: 'Password (optional, 8 hex digits)',
                          border: OutlineInputBorder(),
                        ),
                        style: const TextStyle(fontFamily: 'RobotoMono'),
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Target page 1 (blocks 0-3)'),
                        value: _page1,
                        onChanged: _busy
                            ? null
                            : (value) => setState(() => _page1 = value),
                      ),
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        onPressed: _busy ? null : _write,
                        icon: _busy
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.save),
                        label: const Text('Write T55xx block'),
                      ),
                      if (_message != null) ...[
                        const SizedBox(height: 16),
                        _LfMessage(_message!),
                      ],
                      if (_error != null) ...[
                        const SizedBox(height: 16),
                        _LfMessage(_error!, error: true),
                      ],
                    ],
                  ),
                ),
              ),
            ),
    );
  }
}

class Pm3JablotronClonePage extends StatefulWidget {
  const Pm3JablotronClonePage({super.key});

  @override
  State<Pm3JablotronClonePage> createState() => _Pm3JablotronClonePageState();
}

class _Pm3JablotronClonePageState extends State<Pm3JablotronClonePage> {
  final _uid = TextEditingController();
  final _newPassword = TextEditingController(text: '00000000');
  final _oldPasswords = TextEditingController(text: '00000000');
  bool _busy = false;
  String? _message;
  String? _error;

  ChameleonGUIState get _app => context.read<ChameleonGUIState>();
  bool get _connected => _app.connector?.connected ?? false;

  @override
  void dispose() {
    _uid.dispose();
    _newPassword.dispose();
    _oldPasswords.dispose();
    super.dispose();
  }

  Uint8List _fixedHex(String value, int byteLength, String label) {
    final normalized = value.trim().replaceAll(RegExp(r'\s+'), '');
    if (!RegExp('^[0-9a-fA-F]{${byteLength * 2}}\$').hasMatch(normalized)) {
      throw FormatException('$label must contain exactly $byteLength bytes.');
    }
    return Uint8List.fromList(hexToBytes(normalized));
  }

  List<Uint8List> _passwords() {
    final values = _oldPasswords.text
        .split(RegExp(r'[\s,;]+'))
        .where((value) => value.isNotEmpty)
        .toList();
    if (values.isEmpty) {
      throw const FormatException('Enter at least one current T55xx password.');
    }
    return [
      for (final value in values) _fixedHex(value, 4, 'Each old password'),
    ];
  }

  Future<void> _run(Future<String> Function() operation) async {
    if (!_connected || _busy) return;
    setState(() {
      _busy = true;
      _message = null;
      _error = null;
    });
    try {
      final communicator = _app.communicator!;
      if (!await communicator.isReaderDeviceMode()) {
        await communicator.setReaderDeviceMode(true);
      }
      final message = await operation();
      if (mounted) setState(() => _message = message);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _scan() => _run(() async {
    final uid = await _app.communicator!.readJablotron();
    if (uid == null) return 'No Jablotron tag detected.';
    _uid.text = bytesToHex(uid).toUpperCase();
    return 'Tag read successfully.';
  });

  Future<void> _write() async {
    Uint8List uid;
    Uint8List newPassword;
    List<Uint8List> oldPasswords;
    try {
      uid = _fixedHex(_uid.text, 5, 'Jablotron UID');
      newPassword = _fixedHex(_newPassword.text, 4, 'New password');
      oldPasswords = _passwords();
    } catch (error) {
      setState(() => _error = error.toString());
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Write Jablotron clone?'),
        content: Text(
          'This will overwrite a T55xx tag with UID ${bytesToHex(uid).toUpperCase()}.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Write tag'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _run(() async {
      await _app.communicator!.writeJablotronToT55XX(
        uid,
        newPassword,
        oldPasswords,
      );
      return 'Jablotron clone written successfully.';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('PM3 lf jablotron clone')),
      body: !_connected
          ? const Center(child: Text('Connect a Chameleon Ultra first'))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  'Read a five-byte Jablotron identifier or write it to a T55xx tag using explicit current and replacement passwords.',
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _uid,
                  decoration: const InputDecoration(
                    labelText: 'Jablotron UID (10 hex digits)',
                    border: OutlineInputBorder(),
                  ),
                  style: const TextStyle(fontFamily: 'RobotoMono'),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _busy ? null : _scan,
                  icon: const Icon(Icons.contactless),
                  label: const Text('Read source tag'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _newPassword,
                  decoration: const InputDecoration(
                    labelText: 'New T55xx password (8 hex digits)',
                    border: OutlineInputBorder(),
                  ),
                  style: const TextStyle(fontFamily: 'RobotoMono'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _oldPasswords,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Current passwords (8 hex digits each)',
                    helperText:
                        'Separate multiple candidates with spaces or commas.',
                    border: OutlineInputBorder(),
                  ),
                  style: const TextStyle(fontFamily: 'RobotoMono'),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: _busy ? null : _write,
                  icon: _busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.copy),
                  label: const Text('Write Jablotron clone'),
                ),
                if (_message != null) ...[
                  const SizedBox(height: 16),
                  _LfMessage(_message!),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  _LfMessage(_error!, error: true),
                ],
              ],
            ),
    );
  }
}

class Pm3IoProxCodecPage extends StatefulWidget {
  const Pm3IoProxCodecPage({super.key});

  @override
  State<Pm3IoProxCodecPage> createState() => _Pm3IoProxCodecPageState();
}

class _Pm3IoProxCodecPageState extends State<Pm3IoProxCodecPage> {
  final _raw = TextEditingController();
  final _version = TextEditingController(text: '0');
  final _facility = TextEditingController(text: '0');
  final _card = TextEditingController(text: '0');
  bool _busy = false;
  String? _error;
  Pm3IoProxData? _result;

  ChameleonGUIState get _app => context.read<ChameleonGUIState>();
  bool get _connected => _app.connector?.connected ?? false;

  @override
  void dispose() {
    _raw.dispose();
    _version.dispose();
    _facility.dispose();
    _card.dispose();
    super.dispose();
  }

  Future<void> _run(Future<Pm3IoProxData> Function() operation) async {
    if (!_connected || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
      _result = null;
    });
    try {
      final result = await operation();
      if (mounted) setState(() => _result = result);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _decode() => _run(() async {
    final raw = _raw.text.trim().replaceAll(RegExp(r'\s+'), '');
    if (!RegExp(r'^[0-9a-fA-F]{16}$').hasMatch(raw)) {
      throw const FormatException(
        'Raw ioProx input must be eight bytes of hexadecimal data.',
      );
    }
    return _app.communicator!.decodeIoProxRaw(
      Uint8List.fromList(hexToBytes(raw)),
    );
  });

  Future<void> _compose() => _run(
    () => _app.communicator!.composeIoProxId(
      version: int.parse(_version.text),
      facilityCode: int.parse(_facility.text),
      cardNumber: int.parse(_card.text),
    ),
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('PM3 lf ioProx codec')),
      body: !_connected
          ? const Center(child: Text('Connect a Chameleon Ultra first'))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Decode eight raw ioProx bytes or compose the firmware card structure from version, facility, and card number.',
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _raw,
                      decoration: const InputDecoration(
                        labelText: 'Raw ioProx frame (16 hex digits)',
                        border: OutlineInputBorder(),
                      ),
                      style: const TextStyle(fontFamily: 'RobotoMono'),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton(
                      onPressed: _busy ? null : _decode,
                      child: const Text('Decode raw frame'),
                    ),
                    const SizedBox(height: 20),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        SizedBox(
                          width: 180,
                          child: TextField(
                            controller: _version,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Version',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                        SizedBox(
                          width: 180,
                          child: TextField(
                            controller: _facility,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Facility code',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                        SizedBox(
                          width: 180,
                          child: TextField(
                            controller: _card,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Card number',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    FilledButton(
                      onPressed: _busy ? null : _compose,
                      child: const Text('Compose ioProx frame'),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 16),
                      _LfMessage(_error!, error: true),
                    ],
                    if (_result != null) ...[
                      const SizedBox(height: 16),
                      _LfMessage(
                        'Version: ${_result!.version}\n'
                        'Facility code: ${_result!.facilityCode}\n'
                        'Card number: ${_result!.cardNumber}\n'
                        'Raw frame: ${bytesToHexSpace(_result!.raw).toUpperCase()}',
                      ),
                    ],
                  ],
                ),
              ),
            ),
    );
  }
}

class _LfResult {
  final String protocol;
  final String value;

  const _LfResult(this.protocol, this.value);
}

class _LfMessage extends StatelessWidget {
  final String message;
  final bool error;

  const _LfMessage(this.message, {this.error = false});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      color: error ? colors.errorContainer : colors.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: SelectableText(message),
      ),
    );
  }
}

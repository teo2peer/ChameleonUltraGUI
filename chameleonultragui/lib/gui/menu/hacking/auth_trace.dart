import 'package:chameleonultragui/helpers/general.dart';
import 'package:chameleonultragui/helpers/hf_sniff.dart';
import 'package:chameleonultragui/main.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

// Localizations
import 'package:chameleonultragui/generated/i18n/app_localizations.dart';

// Run a reader-side ISO14443A + MIFARE Classic Crypto1 authentication against a
// real card with a known key and show every wire frame (anticoll + AUTH/NT/
// NR||AR/AT). Uses the firmware HF14A_AUTH_TRACE command; frames come back in
// the sniff buffer format, so the existing sniff parser renders them.
class AuthTracePage extends StatefulWidget {
  const AuthTracePage({super.key});

  @override
  AuthTracePageState createState() => AuthTracePageState();
}

class AuthTracePageState extends State<AuthTracePage> {
  final _block = TextEditingController(text: '0');
  final _key = TextEditingController(text: 'FFFFFFFFFFFF');
  int _keyType = 0; // 0=A, 1=B
  bool _busy = false;
  String? _error;
  List<HfSniffAnnotatedFrame> _frames = [];

  ChameleonGUIState get _app => context.read<ChameleonGUIState>();
  bool get _connected => _app.connector?.connected ?? false;

  @override
  void dispose() {
    _block.dispose();
    _key.dispose();
    super.dispose();
  }

  Future<void> _run() async {
    var localizations = AppLocalizations.of(context)!;
    setState(() {
      _busy = true;
      _error = null;
      _frames = [];
    });
    try {
      final key = hexToBytes(_key.text.trim().replaceAll(' ', ''));
      if (key.length != 6) {
        setState(() => _error = localizations.invalid_hex_input);
        return;
      }
      final block = int.parse(_block.text.trim());
      if (!await _app.communicator!.isReaderDeviceMode()) {
        await _app.communicator!.setReaderDeviceMode(true);
      }
      final data = await _app.communicator!
          .hf14aAuthTrace(block, 0x60 + _keyType, key);
      final frames = annotateHf14aSniffFrames(parseHf14aSniffFrames(data));
      setState(() => _frames = frames);
      if (frames.isEmpty) {
        setState(() => _error = localizations.no_card_found);
      }
    } on FormatException {
      setState(() => _error = localizations.invalid_hex_input);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    var localizations = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(title: Text(localizations.auth_trace)),
      body: !_connected
          ? Center(child: Text(localizations.no_device))
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _block,
                              keyboardType: TextInputType.number,
                              decoration: InputDecoration(
                                  labelText: localizations.block,
                                  border: const OutlineInputBorder()),
                            ),
                          ),
                          const SizedBox(width: 8),
                          SegmentedButton<int>(
                            segments: const [
                              ButtonSegment(value: 0, label: Text("A")),
                              ButtonSegment(value: 1, label: Text("B")),
                            ],
                            selected: {_keyType},
                            onSelectionChanged: (s) =>
                                setState(() => _keyType = s.first),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _key,
                        decoration: InputDecoration(
                            labelText: localizations.recover_key,
                            hintText: 'FFFFFFFFFFFF',
                            border: const OutlineInputBorder()),
                        style: const TextStyle(fontFamily: 'RobotoMono'),
                      ),
                      const SizedBox(height: 12),
                      Center(
                        child: ElevatedButton.icon(
                          onPressed: _busy ? null : _run,
                          icon: _busy
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2))
                              : const Icon(Icons.play_arrow),
                          label: Text(localizations.auth_trace),
                        ),
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 8),
                        Text(_error!,
                            style: TextStyle(
                                color: Theme.of(context).colorScheme.error)),
                      ],
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16.0),
                    itemCount: _frames.length,
                    itemBuilder: (context, i) {
                      final f = _frames[i];
                      final isReader =
                          f.frame.direction == HfSniffDirection.readerToCard;
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3.0),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(isReader ? "→ " : "← ",
                                style: TextStyle(
                                    fontFamily: 'RobotoMono',
                                    fontWeight: FontWeight.bold,
                                    color: isReader
                                        ? Theme.of(context).colorScheme.primary
                                        : Theme.of(context)
                                            .colorScheme
                                            .tertiary)),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (f.label.isNotEmpty)
                                    Text(f.label,
                                        style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 12)),
                                  SelectableText(
                                      bytesToHexSpace(f.frame.data)
                                          .toUpperCase(),
                                      style: const TextStyle(
                                          fontFamily: 'RobotoMono',
                                          fontSize: 13)),
                                ],
                              ),
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
  }
}

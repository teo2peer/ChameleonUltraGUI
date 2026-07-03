import 'package:chameleonultragui/helpers/general.dart';
import 'package:chameleonultragui/recovery/recovery.dart' as recovery;
import 'package:chameleonultragui/recovery/recovery.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// Localizations
import 'package:chameleonultragui/generated/i18n/app_localizations.dart';

enum _MfkeyMode { mfkey32, mfkey64 }

// Manual MFKey32 / MFKey64 solver: paste captured reader nonces and recover the
// sector key offline via the bundled native solver (runs in an isolate).
class MfkeyManualMenu extends StatefulWidget {
  const MfkeyManualMenu({super.key});

  @override
  MfkeyManualMenuState createState() => MfkeyManualMenuState();
}

class MfkeyManualMenuState extends State<MfkeyManualMenu> {
  _MfkeyMode _mode = _MfkeyMode.mfkey32;
  bool _busy = false;
  String? _result;
  String? _error;

  final Map<String, TextEditingController> _c = {
    for (final k in ['uid', 'nt', 'nt0', 'nt1', 'nr0', 'ar0', 'nr1', 'ar1', 'nr', 'ar', 'at'])
      k: TextEditingController(),
  };

  @override
  void dispose() {
    for (final ctl in _c.values) {
      ctl.dispose();
    }
    super.dispose();
  }

  int _hex(String key) {
    final s = _c[key]!.text.trim().replaceAll(' ', '');
    return int.parse(s, radix: 16);
  }

  Future<void> _recover() async {
    var localizations = AppLocalizations.of(context)!;
    setState(() {
      _busy = true;
      _result = null;
      _error = null;
    });
    try {
      List<int> out;
      if (_mode == _MfkeyMode.mfkey32) {
        out = await recovery.mfkey32(Mfkey32Dart(
          uid: _hex('uid'),
          nt0: _hex('nt0'),
          nt1: _hex('nt1'),
          nr0Enc: _hex('nr0'),
          ar0Enc: _hex('ar0'),
          nr1Enc: _hex('nr1'),
          ar1Enc: _hex('ar1'),
        ));
      } else {
        out = await recovery.mfkey64(Mfkey64Dart(
          uid: _hex('uid'),
          nt: _hex('nt'),
          nrEnc: _hex('nr'),
          arEnc: _hex('ar'),
          atEnc: _hex('at'),
        ));
      }
      final keyBytes = u64ToBytes(out[0]).sublist(2, 8);
      final keyHex = bytesToHex(keyBytes).toUpperCase();
      // 0xFFFFFFFFFFFF here means the solver found nothing usable.
      setState(() => _result = keyHex);
    } on FormatException {
      setState(() => _error = localizations.invalid_hex_input);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _field(String key, String label) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4.0),
        child: TextField(
          controller: _c[key],
          decoration: InputDecoration(
              labelText: label,
              isDense: true,
              border: const OutlineInputBorder()),
          style: const TextStyle(fontFamily: 'RobotoMono'),
        ),
      );

  @override
  Widget build(BuildContext context) {
    var localizations = AppLocalizations.of(context)!;
    return AlertDialog(
      title: Text(localizations.mfkey_manual),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SegmentedButton<_MfkeyMode>(
                segments: const [
                  ButtonSegment(value: _MfkeyMode.mfkey32, label: Text("MFKey32")),
                  ButtonSegment(value: _MfkeyMode.mfkey64, label: Text("MFKey64")),
                ],
                selected: {_mode},
                onSelectionChanged: (s) => setState(() {
                  _mode = s.first;
                  _result = null;
                  _error = null;
                }),
              ),
              const SizedBox(height: 12),
              _field('uid', 'UID'),
              if (_mode == _MfkeyMode.mfkey32) ...[
                _field('nt0', 'nt0'),
                _field('nr0', 'nr0'),
                _field('ar0', 'ar0'),
                _field('nt1', 'nt1'),
                _field('nr1', 'nr1'),
                _field('ar1', 'ar1'),
              ] else ...[
                _field('nt', 'nt'),
                _field('nr', 'nr'),
                _field('ar', 'ar'),
                _field('at', 'at'),
              ],
              const SizedBox(height: 8),
              if (_error != null)
                Text(_error!,
                    style: TextStyle(color: Theme.of(context).colorScheme.error)),
              if (_result != null)
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SelectableText(_result!,
                        style: const TextStyle(
                            fontFamily: 'RobotoMono',
                            fontWeight: FontWeight.bold,
                            fontSize: 18)),
                    IconButton(
                      icon: const Icon(Icons.copy, size: 18),
                      onPressed: () => Clipboard.setData(
                          ClipboardData(text: _result!)),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(localizations.cancel)),
        ElevatedButton(
          onPressed: _busy ? null : _recover,
          child: _busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : Text(localizations.recover_key),
        ),
      ],
    );
  }
}

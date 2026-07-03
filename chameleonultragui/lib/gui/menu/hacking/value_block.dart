import 'package:chameleonultragui/helpers/definitions.dart';
import 'package:chameleonultragui/helpers/general.dart';
import 'package:chameleonultragui/main.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

// Localizations
import 'package:chameleonultragui/generated/i18n/app_localizations.dart';

// Increment / decrement / restore-and-transfer a MIFARE Classic value block on
// a real card (reader mode). Uses the mf1ManipulateValueBlock firmware command.
class ValueBlockMenu extends StatefulWidget {
  const ValueBlockMenu({super.key});

  @override
  ValueBlockMenuState createState() => ValueBlockMenuState();
}

class ValueBlockMenuState extends State<ValueBlockMenu> {
  final _block = TextEditingController();
  final _key = TextEditingController(text: 'FFFFFFFFFFFF');
  final _value = TextEditingController(text: '0');
  final _dstBlock = TextEditingController();
  int _keyType = 0; // 0=A, 1=B
  MifareClassicValueBlockOperator _op = MifareClassicValueBlockOperator.increment;
  bool _busy = false;

  ChameleonGUIState get _app => context.read<ChameleonGUIState>();
  bool get _connected => _app.connector?.connected ?? false;

  @override
  void dispose() {
    _block.dispose();
    _key.dispose();
    _value.dispose();
    _dstBlock.dispose();
    super.dispose();
  }

  Future<void> _run() async {
    var localizations = AppLocalizations.of(context)!;
    setState(() => _busy = true);
    try {
      final key = hexToBytes(_key.text.trim().replaceAll(' ', ''));
      if (key.length != 6) {
        _show(localizations.invalid_hex_input);
        return;
      }
      final src = int.parse(_block.text.trim());
      final dst = _dstBlock.text.trim().isEmpty
          ? src
          : int.parse(_dstBlock.text.trim());
      final value = int.parse(_value.text.trim());

      if (!await _app.communicator!.isReaderDeviceMode()) {
        await _app.communicator!.setReaderDeviceMode(true);
      }
      await _app.communicator!.manipulateValueBlock(
          src, _keyType, key, _op, value, dst, _keyType, key);
      _show("OK");
    } on FormatException {
      _show(localizations.invalid_hex_input);
    } catch (e) {
      _show(e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _show(String m) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
    }
  }

  @override
  Widget build(BuildContext context) {
    var localizations = AppLocalizations.of(context)!;
    return AlertDialog(
      title: Text(localizations.value_block_tool),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!_connected)
                Text(localizations.no_device,
                    style: TextStyle(color: Theme.of(context).colorScheme.error)),
              TextField(
                controller: _block,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                    labelText: localizations.block,
                    border: const OutlineInputBorder()),
              ),
              const SizedBox(height: 8),
              SegmentedButton<int>(
                segments: const [
                  ButtonSegment(value: 0, label: Text("Key A")),
                  ButtonSegment(value: 1, label: Text("Key B")),
                ],
                selected: {_keyType},
                onSelectionChanged: (s) => setState(() => _keyType = s.first),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _key,
                decoration: InputDecoration(
                    labelText: localizations.uid.replaceAll('UID', 'Key'),
                    hintText: 'FFFFFFFFFFFF',
                    border: const OutlineInputBorder()),
                style: const TextStyle(fontFamily: 'RobotoMono'),
              ),
              const SizedBox(height: 8),
              SegmentedButton<MifareClassicValueBlockOperator>(
                segments: const [
                  ButtonSegment(
                      value: MifareClassicValueBlockOperator.increment,
                      label: Text("+")),
                  ButtonSegment(
                      value: MifareClassicValueBlockOperator.decrement,
                      label: Text("-")),
                  ButtonSegment(
                      value: MifareClassicValueBlockOperator.restore,
                      label: Text("R")),
                ],
                selected: {_op},
                onSelectionChanged: (s) => setState(() => _op = s.first),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _value,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                    labelText: localizations.value_amount,
                    border: const OutlineInputBorder()),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _dstBlock,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                    labelText:
                        "${localizations.value_block_operation} → ${localizations.block}",
                    hintText: localizations.block,
                    border: const OutlineInputBorder()),
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
          onPressed: (_busy || !_connected) ? null : _run,
          child: _busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : Text(localizations.value_block_operation),
        ),
      ],
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// Localizations
import 'package:chameleonultragui/generated/i18n/app_localizations.dart';

class _WiegandFormat {
  final String name;
  final int bits;
  final int fcShift;
  final int fcMask;
  final int cnShift;
  final int cnMask;
  const _WiegandFormat(this.name, this.bits, this.fcShift, this.fcMask,
      this.cnShift, this.cnMask);
}

// Common access-control Wiegand formats (bit slices from the raw value, MSB
// first with leading/trailing parity bits).
const List<_WiegandFormat> _formats = [
  _WiegandFormat("H10301 (26-bit)", 26, 17, 0xFF, 1, 0xFFFF),
  _WiegandFormat("34-bit", 34, 17, 0xFFFF, 1, 0xFFFF),
  _WiegandFormat("Corporate 1000 (35-bit)", 35, 21, 0xFFF, 1, 0xFFFFF),
  _WiegandFormat("H10304 (37-bit)", 37, 20, 0xFFFF, 1, 0x7FFFF),
];

// Offline decoder: turn a raw Wiegand value (as read by lf hid/prox/em) into a
// facility code + card number for common access-control formats.
class WiegandMenu extends StatefulWidget {
  const WiegandMenu({super.key});

  @override
  WiegandMenuState createState() => WiegandMenuState();
}

class WiegandMenuState extends State<WiegandMenu> {
  final _raw = TextEditingController();
  _WiegandFormat _format = _formats.first;
  String? _fc;
  String? _cn;
  String? _error;

  @override
  void dispose() {
    _raw.dispose();
    super.dispose();
  }

  void _decode() {
    var localizations = AppLocalizations.of(context)!;
    setState(() {
      _fc = null;
      _cn = null;
      _error = null;
    });
    try {
      final clean = _raw.text.trim().replaceAll(' ', '').replaceAll('0x', '');
      final value = int.parse(clean, radix: 16);
      setState(() {
        _fc = ((value >> _format.fcShift) & _format.fcMask).toString();
        _cn = ((value >> _format.cnShift) & _format.cnMask).toString();
      });
    } catch (_) {
      setState(() => _error = localizations.invalid_hex_input);
    }
  }

  Widget _result(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
            Row(
              children: [
                SelectableText(value,
                    style: const TextStyle(
                        fontFamily: 'RobotoMono', fontSize: 16)),
                IconButton(
                  icon: const Icon(Icons.copy, size: 16),
                  onPressed: () =>
                      Clipboard.setData(ClipboardData(text: value)),
                ),
              ],
            ),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    var localizations = AppLocalizations.of(context)!;
    return AlertDialog(
      title: Text(localizations.wiegand_decoder),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _raw,
              decoration: InputDecoration(
                  labelText: "${localizations.wiegand_decoder} (hex)",
                  hintText: "2004063D8",
                  border: const OutlineInputBorder()),
              style: const TextStyle(fontFamily: 'RobotoMono'),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<_WiegandFormat>(
              initialValue: _format,
              isExpanded: true,
              decoration: InputDecoration(
                  labelText: localizations.format,
                  border: const OutlineInputBorder()),
              items: _formats
                  .map((f) => DropdownMenuItem(value: f, child: Text(f.name)))
                  .toList(),
              onChanged: (f) => setState(() => _format = f ?? _formats.first),
            ),
            const SizedBox(height: 12),
            if (_error != null)
              Text(_error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
            if (_fc != null) _result(localizations.facility_code, _fc!),
            if (_cn != null) _result(localizations.card_number, _cn!),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(localizations.cancel)),
        ElevatedButton(
            onPressed: _decode, child: Text(localizations.wiegand_decoder)),
      ],
    );
  }
}

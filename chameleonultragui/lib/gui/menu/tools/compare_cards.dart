import 'dart:typed_data';

import 'package:chameleonultragui/helpers/general.dart';
import 'package:chameleonultragui/helpers/mifare_classic/general.dart';
import 'package:chameleonultragui/main.dart';
import 'package:chameleonultragui/sharedprefsprovider.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

// Localizations
import 'package:chameleonultragui/generated/i18n/app_localizations.dart';

enum _CompareView { keys, data }

// Compare two saved MIFARE Classic cards: their sector keys (A/B) and their
// block data, highlighting differing keys, bytes and bits with colours.
class CompareCardsMenu extends StatefulWidget {
  const CompareCardsMenu({super.key});

  @override
  CompareCardsMenuState createState() => CompareCardsMenuState();
}

class CompareCardsMenuState extends State<CompareCardsMenu> {
  String? cardAId;
  String? cardBId;
  _CompareView _view = _CompareView.keys;

  Color _diffColor(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? Colors.red.shade300
          : Colors.red.shade700;

  Color _matchColor(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? Colors.green.shade300
          : Colors.green.shade700;

  Color _mutedColor(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? Colors.grey.shade500
          : Colors.grey.shade600;

  Color _defaultColor(BuildContext context) =>
      Theme.of(context).textTheme.bodyMedium?.color ?? Colors.black;

  int _bitDiff(Uint8List? a, Uint8List? b) {
    if (a == null || b == null) return -1;
    int count = 0;
    int len = a.length < b.length ? a.length : b.length;
    for (int i = 0; i < len; i++) {
      int x = a[i] ^ b[i];
      while (x != 0) {
        count += x & 1;
        x >>= 1;
      }
    }
    return count;
  }

  Uint8List? _block(CardSave card, int block) {
    if (block < card.data.length && card.data[block].length == 16) {
      return card.data[block];
    }
    return null;
  }

  // Colour each hex nibble of [value] red when it differs from [other].
  List<TextSpan> _hexSpans(Uint8List? value, Uint8List? other) {
    if (value == null) {
      return [
        TextSpan(
            text: '-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --',
            style: TextStyle(color: _mutedColor(context)))
      ];
    }
    Color normal = _defaultColor(context);
    Color diff = _diffColor(context);
    List<TextSpan> spans = [];
    for (int i = 0; i < value.length; i++) {
      if (i > 0) spans.add(const TextSpan(text: ' '));
      String hex = value[i].toRadixString(16).padLeft(2, '0').toUpperCase();
      int? o = (other != null && i < other.length) ? other[i] : null;
      for (int n = 0; n < 2; n++) {
        bool differs = o == null ||
            hex[n] !=
                o.toRadixString(16).padLeft(2, '0').toUpperCase()[n];
        spans.add(TextSpan(
          text: hex[n],
          style: TextStyle(
            color: differs ? diff : normal,
            fontWeight: differs ? FontWeight.bold : FontWeight.normal,
          ),
        ));
      }
    }
    return spans;
  }

  CardSave? _cardById(ChameleonGUIState appState, String? id) {
    if (id == null) return null;
    try {
      return appState.sharedPreferencesProvider
          .getCards()
          .firstWhere((c) => c.id == id);
    } catch (_) {
      return null;
    }
  }

  Widget _buildKeysView(CardSave a, CardSave b) {
    var localizations = AppLocalizations.of(context)!;
    final typeA = chameleonTagTypeGetMfClassicType(a.tag);
    final typeB = chameleonTagTypeGetMfClassicType(b.tag);
    final sectorCount = mfClassicGetSectorCount(typeA) >
            mfClassicGetSectorCount(typeB)
        ? mfClassicGetSectorCount(typeA)
        : mfClassicGetSectorCount(typeB);

    int matching = 0;
    int total = 0;
    List<TableRow> rows = [
      TableRow(
        decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest),
        children: [
          _cell(localizations.sector, bold: true),
          _cell("A ${localizations.keys}", bold: true),
          _cell("B ${localizations.keys}", bold: true),
        ],
      ),
    ];

    for (int s = 0; s < sectorCount; s++) {
      final trailer = mfClassicGetSectorTrailerBlockBySector(s);
      final ta = _block(a, trailer);
      final tb = _block(b, trailer);
      for (final part in [
        [0, 6, 'A'],
        [10, 16, 'B'],
      ]) {
        final ka = ta?.sublist(part[0] as int, part[1] as int);
        final kb = tb?.sublist(part[0] as int, part[1] as int);
        final label = "${part[2]}";
        Color color;
        if (ka == null || kb == null) {
          color = _mutedColor(context);
        } else if (_listEquals(ka, kb)) {
          color = _matchColor(context);
          matching++;
          total++;
        } else {
          color = _diffColor(context);
          total++;
        }
        rows.add(TableRow(children: [
          _cell(s == 0 && part[2] == 'A' ? '' : (part[2] == 'A' ? '$s' : '')),
          _keyCell(label, ka, color),
          _keyCell(label, kb, color),
        ]));
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8.0),
          child: Text(
            localizations.keys_match_summary(matching, total),
            style: TextStyle(
                fontWeight: FontWeight.bold,
                color: matching == total && total > 0
                    ? _matchColor(context)
                    : _diffColor(context)),
          ),
        ),
        Table(
          border: TableBorder.all(color: _mutedColor(context), width: 0.3),
          columnWidths: const {
            0: IntrinsicColumnWidth(),
          },
          defaultVerticalAlignment: TableCellVerticalAlignment.middle,
          children: rows,
        ),
      ],
    );
  }

  Widget _cell(String text, {bool bold = false}) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
        child: Text(text,
            style: TextStyle(
                fontWeight: bold ? FontWeight.bold : FontWeight.normal)),
      );

  Widget _keyCell(String label, Uint8List? key, Color color) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
        child: Text(
          "$label: ${key != null ? bytesToHex(key).toUpperCase() : '------------'}",
          style: TextStyle(
              fontFamily: 'RobotoMono', fontSize: 13, color: color),
        ),
      );

  Widget _buildDataView(CardSave a, CardSave b) {
    var localizations = AppLocalizations.of(context)!;
    final typeA = chameleonTagTypeGetMfClassicType(a.tag);
    final typeB = chameleonTagTypeGetMfClassicType(b.tag);
    final blockCount = mfClassicGetBlockCount(typeA) >
            mfClassicGetBlockCount(typeB)
        ? mfClassicGetBlockCount(typeA)
        : mfClassicGetBlockCount(typeB);

    List<TextSpan> spans = [];
    Color numColor = _mutedColor(context);
    for (int block = 0; block < blockCount; block++) {
      final ba = _block(a, block);
      final bb = _block(b, block);
      final bits = _bitDiff(ba, bb);
      final differs = ba == null || bb == null || !_listEquals(ba, bb);
      if (spans.isNotEmpty) spans.add(const TextSpan(text: '\n'));

      String num = block.toString().padLeft(3, ' ');
      if (!differs) {
        spans.add(TextSpan(
            text: '$num: ', style: TextStyle(color: numColor)));
        spans.addAll(_hexSpans(ba, bb));
        continue;
      }

      spans.add(TextSpan(
          text: '$num: ', style: TextStyle(color: numColor)));
      spans.addAll(_hexSpans(ba, bb));
      if (bits >= 0) {
        spans.add(TextSpan(
            text: '   ${localizations.bit_difference(bits)}',
            style: TextStyle(color: _diffColor(context), fontSize: 11)));
      }
      spans.add(const TextSpan(text: '\n'));
      spans.add(TextSpan(
          text: '     ', style: TextStyle(color: numColor)));
      spans.addAll(_hexSpans(bb, ba));
    }

    return SelectableText.rich(
      TextSpan(
        style: TextStyle(
            fontFamily: 'RobotoMono', fontSize: 13, height: 1.35),
        children: spans,
      ),
    );
  }

  bool _listEquals(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    var localizations = AppLocalizations.of(context)!;
    var appState = context.watch<ChameleonGUIState>();
    final cards = appState.sharedPreferencesProvider
        .getCards()
        .where((c) => isMifareClassic(c.tag))
        .toList();

    final cardA = _cardById(appState, cardAId);
    final cardB = _cardById(appState, cardBId);

    return AlertDialog(
      title: Text(localizations.compare_cards),
      content: SizedBox(
        width: 640,
        height: MediaQuery.of(context).size.height * 0.7,
        child: cards.length < 2
            ? Center(child: Text(localizations.no_mfc_cards))
            : Column(
                children: [
                  Row(
                    children: [
                      Expanded(child: _cardDropdown(cards, cardAId, "A",
                          (v) => setState(() => cardAId = v))),
                      const SizedBox(width: 8),
                      Expanded(child: _cardDropdown(cards, cardBId, "B",
                          (v) => setState(() => cardBId = v))),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SegmentedButton<_CompareView>(
                    segments: [
                      ButtonSegment(
                          value: _CompareView.keys,
                          label: Text(localizations.keys)),
                      ButtonSegment(
                          value: _CompareView.data,
                          label: Text(localizations.data)),
                    ],
                    selected: {_view},
                    onSelectionChanged: (s) =>
                        setState(() => _view = s.first),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: (cardA == null || cardB == null)
                        ? Center(
                            child: Text(localizations.select_two_cards))
                        : SingleChildScrollView(
                            child: _view == _CompareView.keys
                                ? _buildKeysView(cardA, cardB)
                                : _buildDataView(cardA, cardB),
                          ),
                  ),
                ],
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(localizations.close),
        ),
      ],
    );
  }

  Widget _cardDropdown(List<CardSave> cards, String? value, String label,
      ValueChanged<String?> onChanged) {
    return DropdownButtonFormField<String?>(
      initialValue: value,
      isExpanded: true,
      decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
      items: cards
          .map((c) => DropdownMenuItem<String?>(
                value: c.id,
                child: Text(
                  c.name.isEmpty ? c.uid.toUpperCase() : c.name,
                  overflow: TextOverflow.ellipsis,
                ),
              ))
          .toList(),
      onChanged: onChanged,
    );
  }
}

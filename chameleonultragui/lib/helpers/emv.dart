import 'dart:typed_data';

import 'package:chameleonultragui/helpers/general.dart';

// One node of a parsed EMV BER-TLV tree.
class EmvTlv {
  final String tag; // hex, uppercase
  final Uint8List value;
  final bool constructed;
  final int depth;
  EmvTlv(this.tag, this.value, this.constructed, this.depth);
}

// EMV / ISO 7816 tag names (contactless-relevant subset, per EMV Book 3).
const Map<String, String> emvTagNames = {
  '4F': 'Application Identifier (AID)',
  '50': 'Application Label',
  '56': 'Track 1 Data',
  '57': 'Track 2 Equivalent Data',
  '5A': 'Application PAN',
  '5F20': 'Cardholder Name',
  '5F24': 'Application Expiration Date',
  '5F25': 'Application Effective Date',
  '5F28': 'Issuer Country Code',
  '5F2A': 'Transaction Currency Code',
  '5F2D': 'Language Preference',
  '5F30': 'Service Code',
  '5F34': 'PAN Sequence Number',
  '5F50': 'Issuer URL',
  '61': 'Application Template',
  '6F': 'FCI Template',
  '70': 'Record Template',
  '77': 'Response Template (fmt 2)',
  '80': 'Response Template (fmt 1)',
  '82': 'Application Interchange Profile',
  '83': 'Command Template',
  '84': 'Dedicated File (DF) Name',
  '87': 'Application Priority Indicator',
  '88': 'Short File Identifier (SFI)',
  '8C': 'CDOL1',
  '8D': 'CDOL2',
  '8E': 'CVM List',
  '8F': 'CA Public Key Index',
  '90': 'Issuer Public Key Certificate',
  '92': 'Issuer Public Key Remainder',
  '93': 'Signed Static Application Data',
  '94': 'Application File Locator (AFL)',
  '95': 'Terminal Verification Results',
  '9A': 'Transaction Date',
  '9C': 'Transaction Type',
  '9F02': 'Amount, Authorised',
  '9F06': 'Application Identifier (terminal)',
  '9F07': 'Application Usage Control',
  '9F08': 'Application Version Number',
  '9F0D': 'Issuer Action Code - Default',
  '9F0E': 'Issuer Action Code - Denial',
  '9F0F': 'Issuer Action Code - Online',
  '9F10': 'Issuer Application Data',
  '9F11': 'Issuer Code Table Index',
  '9F12': 'Application Preferred Name',
  '9F13': 'Last Online ATC Register',
  '9F17': 'PIN Try Counter',
  '9F1A': 'Terminal Country Code',
  '9F1F': 'Track 1 Discretionary Data',
  '9F20': 'Track 2 Discretionary Data',
  '9F26': 'Application Cryptogram',
  '9F27': 'Cryptogram Information Data',
  '9F32': 'Issuer Public Key Exponent',
  '9F36': 'Application Transaction Counter (ATC)',
  '9F37': 'Unpredictable Number',
  '9F38': 'PDOL',
  '9F42': 'Application Currency Code',
  '9F44': 'Application Currency Exponent',
  '9F45': 'Data Authentication Code',
  '9F46': 'ICC Public Key Certificate',
  '9F47': 'ICC Public Key Exponent',
  '9F48': 'ICC Public Key Remainder',
  '9F4A': 'Static Data Authentication Tag List',
  '9F4C': 'ICC Dynamic Number',
  '9F4D': 'Log Entry',
  '9F5A': 'Application Program ID',
  '9F66': 'Terminal Transaction Qualifiers (TTQ)',
  '9F6B': 'Track 2 Data (MSD)',
  '9F6C': 'Card Transaction Qualifiers (CTQ)',
  '9F6E': 'Form Factor Indicator',
  'A5': 'FCI Proprietary Template',
  'BF0C': 'FCI Issuer Discretionary Data',
};

String emvTagName(String tag) => emvTagNames[tag] ?? 'Unknown ($tag)';

// Recursively parse BER-TLV into an ordered, depth-tagged list.
List<EmvTlv> parseEmvTlv(Uint8List data, {int depth = 0}) {
  final out = <EmvTlv>[];
  int i = 0;
  while (i < data.length) {
    if (data[i] == 0x00 || data[i] == 0xFF) {
      i++;
      continue;
    }
    final tagStart = i;
    final first = data[i];
    i++;
    final constructed = (first & 0x20) != 0;
    if ((first & 0x1F) == 0x1F) {
      while (i < data.length && (data[i] & 0x80) != 0) {
        i++;
      }
      if (i < data.length) i++;
    }
    final tag = bytesToHex(data.sublist(tagStart, i)).toUpperCase();
    if (i >= data.length) break;
    int len = data[i];
    i++;
    if ((len & 0x80) != 0) {
      final n = len & 0x7F;
      len = 0;
      for (int k = 0; k < n && i < data.length; k++) {
        len = (len << 8) | data[i];
        i++;
      }
    }
    if (i + len > data.length) len = data.length - i;
    final value = data.sublist(i, i + len);
    out.add(EmvTlv(tag, value, constructed, depth));
    if (constructed) {
      out.addAll(parseEmvTlv(value, depth: depth + 1));
    }
    i += len;
  }
  return out;
}

String _ascii(Uint8List b) =>
    String.fromCharCodes(b.where((c) => c >= 0x20 && c < 0x7F)).trim();

String _bcd(Uint8List b) => bytesToHex(b);

// ISO 4217 numeric -> alpha (common)
const Map<String, String> _currencies = {
  '0840': 'USD', '0978': 'EUR', '0826': 'GBP', '0392': 'JPY', '0756': 'CHF',
  '0124': 'CAD', '0036': 'AUD', '0156': 'CNY', '0356': 'INR', '0643': 'RUB',
  '0752': 'SEK', '0578': 'NOK', '0208': 'DKK', '0985': 'PLN', '0986': 'BRL',
  '0484': 'MXN', '0710': 'ZAR', '0344': 'HKD', '0702': 'SGD', '0410': 'KRW',
};
// ISO 3166 numeric -> alpha2 (common)
const Map<String, String> _countries = {
  '0840': 'US', '0826': 'GB', '0250': 'FR', '0276': 'DE', '0724': 'ES',
  '0380': 'IT', '0528': 'NL', '0056': 'BE', '0578': 'NO', '0752': 'SE',
  '0208': 'DK', '0246': 'FI', '0372': 'IE', '0620': 'PT', '0756': 'CH',
  '0040': 'AT', '0616': 'PL', '0124': 'CA', '0484': 'MX', '0076': 'BR',
  '0392': 'JP', '0156': 'CN', '0356': 'IN', '0643': 'RU', '0036': 'AU',
};

String _fmtExpiry(String yymmdd) {
  // YYMMDD or YYMM
  if (yymmdd.length >= 4) {
    return "${yymmdd.substring(2, 4)}/${yymmdd.substring(0, 2)}"; // MM/YY
  }
  return yymmdd;
}

String _fmtPan(String pan) {
  final b = StringBuffer();
  for (int i = 0; i < pan.length; i++) {
    if (i > 0 && i % 4 == 0) b.write(' ');
    b.write(pan[i]);
  }
  return b.toString();
}

// Card scheme from AID prefix, else PAN prefix.
String? emvScheme(String? aid, String? pan) {
  if (aid != null) {
    final a = aid.toUpperCase();
    if (a.startsWith('A000000003')) return 'Visa';
    if (a.startsWith('A000000004') || a.startsWith('A000000005')) {
      return 'Mastercard';
    }
    if (a.startsWith('A00000002501') || a.startsWith('A000000025')) {
      return 'American Express';
    }
    if (a.startsWith('A0000001523010') || a.startsWith('A0000003241010')) {
      return 'Discover';
    }
    if (a.startsWith('A000000065')) return 'JCB';
    if (a.startsWith('A0000005241010')) return 'RuPay';
    if (a.startsWith('A000000677') || a.startsWith('A0000006723010')) {
      return 'Interac';
    }
    if (a.startsWith('A0000000980840')) return 'US Debit';
  }
  if (pan != null && pan.isNotEmpty) {
    if (pan.startsWith('34') || pan.startsWith('37')) return 'American Express';
    if (pan.startsWith('35')) return 'JCB';
    final d = pan[0];
    if (d == '4') return 'Visa';
    if (d == '5' || d == '2') return 'Mastercard';
    if (d == '6') return 'Discover';
  }
  return null;
}

// Extract the human-friendly card fields from the parsed TLVs (leaf-last wins).
Map<String, String> emvExtractFields(List<EmvTlv> tlvs) {
  final leaf = <String, Uint8List>{};
  for (final t in tlvs) {
    if (!t.constructed) leaf[t.tag] = t.value;
  }
  final f = <String, String>{};
  String? pan;
  String? expiry;

  // Track 2 (57) or MSD Track 2 (9F6B): PAN 'D' YYMM service...
  final track2 = leaf['57'] ?? leaf['9F6B'];
  if (track2 != null) {
    final t2 = bytesToHex(track2).toUpperCase();
    final sep = t2.indexOf('D');
    if (sep > 0) {
      pan = t2.substring(0, sep);
      final rest = t2.substring(sep + 1);
      if (rest.length >= 4) expiry = _fmtExpiry(rest.substring(0, 4));
      if (rest.length >= 7) f['Service code'] = rest.substring(4, 7);
    }
  }
  if (pan == null && leaf.containsKey('5A')) {
    pan = bytesToHex(leaf['5A']!).toUpperCase().replaceAll('F', '');
  }
  if (expiry == null && leaf.containsKey('5F24')) {
    expiry = _fmtExpiry(_bcd(leaf['5F24']!));
  }

  if (pan != null) f['PAN'] = _fmtPan(pan);
  if (expiry != null) f['Expiry'] = expiry;
  if (leaf.containsKey('5F25')) {
    f['Effective'] = _fmtExpiry(_bcd(leaf['5F25']!));
  }
  if (leaf.containsKey('5F20')) f['Cardholder'] = _ascii(leaf['5F20']!);
  if (leaf.containsKey('9F12')) f['Preferred name'] = _ascii(leaf['9F12']!);
  if (leaf.containsKey('50')) f['Application'] = _ascii(leaf['50']!);
  if (leaf.containsKey('5F34')) {
    f['PAN sequence'] = leaf['5F34']![0].toString();
  }
  String? aid;
  if (leaf.containsKey('4F')) {
    aid = bytesToHex(leaf['4F']!).toUpperCase();
  } else if (leaf.containsKey('84')) {
    aid = bytesToHex(leaf['84']!).toUpperCase();
  }
  if (aid != null) f['AID'] = aid;
  final scheme = emvScheme(aid, pan);
  if (scheme != null) f['Scheme'] = scheme;
  if (leaf.containsKey('9F42') || leaf.containsKey('5F2A')) {
    final c = _bcd(leaf['9F42'] ?? leaf['5F2A']!).padLeft(4, '0');
    f['Currency'] = _currencies[c] ?? c;
  }
  if (leaf.containsKey('5F28')) {
    final c = _bcd(leaf['5F28']!).padLeft(4, '0');
    f['Issuer country'] = _countries[c] ?? c;
  }
  if (leaf.containsKey('5F2D')) f['Language'] = _ascii(leaf['5F2D']!);
  if (leaf.containsKey('9F08')) {
    f['App version'] = bytesToHex(leaf['9F08']!).toUpperCase();
  }
  if (leaf.containsKey('9F36')) {
    f['ATC'] = int.parse(bytesToHex(leaf['9F36']!), radix: 16).toString();
  }
  if (leaf.containsKey('9F17')) {
    f['PIN try counter'] = leaf['9F17']![0].toString();
  }
  if (leaf.containsKey('5F50')) f['Issuer URL'] = _ascii(leaf['5F50']!);
  return f;
}

// Extract the transaction/GENERATE-AC result (offline purchase simulation).
Map<String, String> emvExtractCryptogram(List<EmvTlv> tlvs) {
  final leaf = <String, Uint8List>{};
  for (final t in tlvs) {
    if (!t.constructed) leaf[t.tag] = t.value;
  }
  final f = <String, String>{};
  if (leaf.containsKey('9F26')) {
    f['Application Cryptogram'] = bytesToHex(leaf['9F26']!).toUpperCase();
  }
  if (leaf.containsKey('9F27') && leaf['9F27']!.isNotEmpty) {
    final cid = leaf['9F27']![0] & 0xC0;
    f['Cryptogram type'] = cid == 0x80
        ? 'ARQC — online authorisation requested'
        : cid == 0x40
            ? 'TC — offline approved'
            : 'AAC — declined';
  }
  if (leaf.containsKey('9F36')) {
    f['ATC'] = int.parse(bytesToHex(leaf['9F36']!), radix: 16).toString();
  }
  if (leaf.containsKey('9F10')) {
    f['Issuer Application Data'] = bytesToHex(leaf['9F10']!).toUpperCase();
  }
  return f;
}

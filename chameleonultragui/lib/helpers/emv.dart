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
  '97': 'Transaction Certificate Data Object List (TDOL)',
  '9A': 'Transaction Date',
  '9C': 'Transaction Type',
  '9F02': 'Amount, Authorised',
  '9F03': 'Amount, Other',
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
  '9F33': 'Terminal Capabilities',
  '9F34': 'Cardholder Verification Method Results',
  '9F32': 'Issuer Public Key Exponent',
  '9F36': 'Application Transaction Counter (ATC)',
  '9F37': 'Unpredictable Number',
  '9F38': 'PDOL',
  '9F40': 'Additional Terminal Capabilities',
  '9F41': 'Transaction Sequence Counter',
  '9F42': 'Application Currency Code',
  '9F44': 'Application Currency Exponent',
  '9F45': 'Data Authentication Code',
  '9F46': 'ICC Public Key Certificate',
  '9F47': 'ICC Public Key Exponent',
  '9F48': 'ICC Public Key Remainder',
  '9F4A': 'Static Data Authentication Tag List',
  '9F4C': 'ICC Dynamic Number',
  '9F4D': 'Log Entry',
  '9F53': 'Transaction Category Code',
  '9F5A': 'Application Program ID',
  '9F5D': 'Available Offline Spending Amount',
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
  if (depth > 24) return out; // guard against pathologically nested TLV (DoS)
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

// Result of parsing the firmware's packed scan buffer (EMV/DESFire scans).
class EmvScan {
  final Uint8List uid;
  final Uint8List atqa;
  final int sak;
  final Uint8List ats;
  final List<(Uint8List, Uint8List)> apdus; // (command, response)
  EmvScan(this.uid, this.atqa, this.sak, this.ats, this.apdus);
}

class EmvApduTrace {
  final int index;
  final Uint8List command;
  final Uint8List response;
  final String name;
  final List<String> commandDetails;
  final int? statusWord;
  final String statusText;
  final Uint8List responseBody;
  final List<EmvTlv> responseTlvs;

  EmvApduTrace({
    required this.index,
    required this.command,
    required this.response,
    required this.name,
    required this.commandDetails,
    required this.statusWord,
    required this.statusText,
    required this.responseBody,
    required this.responseTlvs,
  });
}

class EmvOdaAssessment {
  const EmvOdaAssessment({
    required this.advertisedMethods,
    required this.presentTags,
    required this.missingTags,
    required this.caPublicKeyIndex,
    required this.cryptographicallyVerified,
    required this.status,
  });

  final List<String> advertisedMethods;
  final List<String> presentTags;
  final List<String> missingTags;
  final int? caPublicKeyIndex;
  final bool cryptographicallyVerified;
  final String status;

  Map<String, Object?> toJson() => {
        'advertisedMethods': advertisedMethods,
        'presentTags': presentTags,
        'missingTags': missingTags,
        'caPublicKeyIndex': caPublicKeyIndex,
        'cryptographicallyVerified': cryptographicallyVerified,
        'status': status,
      };
}

EmvOdaAssessment emvAssessOda(Map<String, Uint8List> leaf) {
  final aip = leaf['82'];
  final methods = <String>[];
  if (aip != null && aip.isNotEmpty) {
    if ((aip[0] & 0x40) != 0) methods.add('SDA');
    if ((aip[0] & 0x20) != 0) methods.add('DDA');
    if ((aip[0] & 0x01) != 0) methods.add('CDA');
  }
  final required = <String>{};
  if (methods.isNotEmpty) required.addAll(['8F', '90', '9F32']);
  if (methods.contains('SDA')) required.add('93');
  if (methods.contains('DDA') || methods.contains('CDA')) {
    required.addAll(['9F46', '9F47']);
  }
  final present = required.where(leaf.containsKey).toList()..sort();
  final missing = required.where((tag) => !leaf.containsKey(tag)).toList()
    ..sort();
  final capk = leaf['8F'];
  final capkIndex = capk == null || capk.isEmpty ? null : capk.first;
  final status = methods.isEmpty
      ? 'ODA not advertised by AIP'
      : missing.isNotEmpty
          ? 'ODA evidence incomplete; missing ${missing.join(', ')}'
          : 'ODA evidence present; cryptographic verification requires the matching trusted CAPK and signed-data reconstruction';
  return EmvOdaAssessment(
    advertisedMethods: List.unmodifiable(methods),
    presentTags: List.unmodifiable(present),
    missingTags: List.unmodifiable(missing),
    caPublicKeyIndex: capkIndex,
    cryptographicallyVerified: false,
    status: status,
  );
}

String _hex(Uint8List b) => bytesToHex(b).toUpperCase();

String _asciiPrintable(Uint8List b) {
  if (b.isEmpty || !b.every((c) => c >= 0x20 && c < 0x7F)) return '';
  return String.fromCharCodes(b);
}

String emvStatusText(int? sw) {
  if (sw == null) return 'No status word';
  switch (sw) {
    case 0x9000:
      return 'Success';
    case 0x6283:
      return 'Selected file invalidated';
    case 0x6300:
      return 'Authentication failed / warning';
    case 0x6700:
      return 'Wrong length';
    case 0x6982:
      return 'Security status not satisfied';
    case 0x6985:
      return 'Conditions of use not satisfied';
    case 0x6986:
      return 'Command not allowed (no current EF)';
    case 0x6A80:
      return 'Incorrect data';
    case 0x6A81:
      return 'Function not supported';
    case 0x6A82:
      return 'File or application not found';
    case 0x6A83:
      return 'Record not found';
    case 0x6A86:
      return 'Incorrect P1/P2';
    case 0x6D00:
      return 'Instruction not supported';
    case 0x6E00:
      return 'Class not supported';
    default:
      if ((sw & 0xFF00) == 0x6100) return 'More response bytes available';
      if ((sw & 0xFF00) == 0x6C00) return 'Wrong Le; exact length in SW2';
      return 'Status 0x${sw.toRadixString(16).padLeft(4, '0').toUpperCase()}';
  }
}

String emvDescribeCommand(Uint8List cmd) {
  if (cmd.length < 4) return 'APDU';
  final cla = cmd[0];
  final ins = cmd[1];
  final p1 = cmd[2];
  final data = _apduData(cmd);
  if (cla == 0x00 && ins == 0xA4 && p1 == 0x04) {
    final hex = _hex(data);
    if (hex == '325041592E5359532E4444463031') return 'SELECT PPSE';
    if (hex == '315041592E5359532E4444463031') return 'SELECT PSE';
    return 'SELECT AID';
  }
  if (cla == 0x80 && ins == 0xA8) return 'GET PROCESSING OPTIONS';
  if (cla == 0x00 && ins == 0xB2) return 'READ RECORD';
  if (cla == 0x80 && ins == 0xAE) return 'GENERATE AC';
  if (cla == 0x00 && ins == 0xCA) return 'GET DATA';
  return 'CLA ${cla.toRadixString(16).padLeft(2, '0').toUpperCase()} INS ${ins.toRadixString(16).padLeft(2, '0').toUpperCase()}';
}

List<String> emvCommandDetails(Uint8List cmd) {
  final details = <String>[];
  if (cmd.length < 4) return details;
  final cla = cmd[0];
  final ins = cmd[1];
  final p1 = cmd[2];
  final p2 = cmd[3];
  final data = _apduData(cmd);
  if (cla == 0x00 && ins == 0xA4 && p1 == 0x04) {
    final ascii = _asciiPrintable(data);
    details
        .add("Name/AID: ${_hex(data)}${ascii.isNotEmpty ? '  "$ascii"' : ''}");
  } else if (cla == 0x80 && ins == 0xA8) {
    details.add('Command template: ${_hex(data)}');
    final pdol = _unwrap83(data);
    if (pdol != null) {
      details.add('PDOL data length: ${pdol.length}');
      if (pdol.length >= 4) {
        details.add(
            'First 4 PDOL bytes (often TTQ): ${_hex(Uint8List.fromList(pdol.sublist(0, 4)))}');
      }
    }
  } else if (cla == 0x00 && ins == 0xB2) {
    details.add('SFI: ${(p2 >> 3) & 0x1F}');
    details.add('Record: $p1');
  } else if (cla == 0x80 && ins == 0xAE) {
    final cryptogramType = switch (p1 & 0xC0) {
      0x00 => 'AAC requested',
      0x40 => 'TC requested',
      0x80 => 'ARQC requested',
      _ => 'RFU cryptogram request',
    };
    details.add(cryptogramType);
    details.add('CDOL1 data length: ${data.length}');
  }
  return details;
}

Uint8List _apduData(Uint8List cmd) {
  if (cmd.length <= 5) return Uint8List(0);
  final lc = cmd[4];
  final end = 5 + lc <= cmd.length ? 5 + lc : cmd.length;
  return Uint8List.fromList(cmd.sublist(5, end));
}

Uint8List? _unwrap83(Uint8List data) {
  if (data.length >= 2 && data[0] == 0x83 && data[1] <= data.length - 2) {
    return Uint8List.fromList(data.sublist(2, 2 + data[1]));
  }
  return null;
}

List<EmvApduTrace> emvBuildTrace(List<(Uint8List, Uint8List)> apdus) {
  final out = <EmvApduTrace>[];
  for (var i = 0; i < apdus.length; i++) {
    final (cmd, resp) = apdus[i];
    final sw =
        resp.length >= 2 ? (resp[resp.length - 2] << 8) | resp.last : null;
    final body = resp.length >= 2
        ? Uint8List.fromList(resp.sublist(0, resp.length - 2))
        : Uint8List.fromList(resp);
    out.add(EmvApduTrace(
      index: i + 1,
      command: cmd,
      response: resp,
      name: emvDescribeCommand(cmd),
      commandDetails: emvCommandDetails(cmd),
      statusWord: sw,
      statusText: emvStatusText(sw),
      responseBody: body,
      responseTlvs: parseEmvTlv(body),
    ));
  }
  return out;
}

// Parse the packed scan buffer with full bounds checking. Layout:
// uid_len,uid,atqa[2],sak,ats_len,ats,num,{cmd_len,cmd,resp_len_LE[2],resp}*
// Throws FormatException on a truncated/garbled buffer instead of RangeError.
EmvScan parseEmvScanBuffer(Uint8List d) {
  int i = 0;
  void need(int n) {
    if (n < 0 || i + n > d.length) {
      throw const FormatException('truncated scan buffer');
    }
  }

  need(1);
  final uidLen = d[i++];
  need(uidLen);
  final uid = d.sublist(i, i + uidLen);
  i += uidLen;
  need(2);
  final atqa = d.sublist(i, i + 2);
  i += 2;
  need(1);
  final sak = d[i++];
  need(1);
  final atsLen = d[i++];
  need(atsLen);
  final ats = d.sublist(i, i + atsLen);
  i += atsLen;
  need(1);
  final num = d[i++];
  final apdus = <(Uint8List, Uint8List)>[];
  for (var k = 0; k < num; k++) {
    need(1);
    final cl = d[i++];
    need(cl);
    final cmd = d.sublist(i, i + cl);
    i += cl;
    need(2);
    final rl = d[i] | (d[i + 1] << 8);
    i += 2;
    need(rl);
    final resp = d.sublist(i, i + rl);
    i += rl;
    apdus.add((cmd, resp));
  }
  return EmvScan(uid, atqa, sak, ats, apdus);
}

String emvProtocolSummary(
    Uint8List uid, Uint8List atqa, int sak, Uint8List ats) {
  final parts = <String>[];
  parts.add((sak & 0x20) != 0 ? 'ISO 14443-4A / ISO-DEP' : 'ISO 14443-A');
  parts.add('${uid.length * 8}-bit UID');
  if (ats.length >= 2) {
    final t0 = ats[1];
    final fsci = t0 & 0x0F;
    const fsd = [16, 24, 32, 40, 48, 64, 96, 128, 256];
    final fsdText = fsci < fsd.length ? ', FSD=${fsd[fsci]}' : '';
    final atsFeatures = <String>[];
    if ((t0 & 0x10) != 0) atsFeatures.add('TA');
    if ((t0 & 0x20) != 0) atsFeatures.add('TB');
    if ((t0 & 0x40) != 0) atsFeatures.add('TC');
    parts.add('ATS FSCI=$fsci$fsdText');
    if (atsFeatures.isNotEmpty) parts.add('ATS ${atsFeatures.join('/')}');
  } else if (ats.isNotEmpty) {
    parts.add('ATS present');
  }
  if (atqa.isNotEmpty) {
    parts.add('ATQA ${bytesToHexSpace(atqa).toUpperCase()}');
  }
  return parts.join(' | ');
}

// Build the primitive-tag -> value map once (last occurrence wins). Callers
// that need fields + cryptogram + AIP share this instead of rescanning 3x.
Map<String, Uint8List> emvLeafMap(List<EmvTlv> tlvs) {
  final leaf = <String, Uint8List>{};
  for (final t in tlvs) {
    if (!t.constructed) {
      leaf[t.tag] = t.value;
      if (t.tag == '80' && t.value.length >= 2) {
        _addGpoFormat1Leaves(leaf, t.value);
      }
    }
  }
  return leaf;
}

Map<String, Uint8List> emvLeafMapFromTrace(List<EmvApduTrace> traces) {
  final leaf = <String, Uint8List>{};
  for (final trace in traces) {
    for (final t in trace.responseTlvs) {
      if (t.constructed) continue;
      leaf[t.tag] = t.value;
      if (t.tag != '80') continue;
      final ins = trace.command.length >= 2 ? trace.command[1] : -1;
      if (ins == 0xA8) {
        _addGpoFormat1Leaves(leaf, t.value);
      } else if (ins == 0xAE) {
        _addGenerateAcFormat1Leaves(leaf, t.value);
      }
    }
  }
  return leaf;
}

void _addGpoFormat1Leaves(Map<String, Uint8List> leaf, Uint8List value) {
  if (value.length < 2) return;
  // GPO response format 1: tag 80 value is AIP(2) || AFL(n), without nested
  // 82/94 TLVs. Expose synthetic leaves so callers decode both formats.
  leaf.putIfAbsent('82', () => Uint8List.fromList(value.sublist(0, 2)));
  if (value.length > 2) {
    leaf.putIfAbsent('94', () => Uint8List.fromList(value.sublist(2)));
  }
}

void _addGenerateAcFormat1Leaves(Map<String, Uint8List> leaf, Uint8List value) {
  if (value.length < 11) return;
  // GENERATE AC response format 1: CID(1) || ATC(2) || AC(8) || IAD(optional).
  leaf.putIfAbsent('9F27', () => Uint8List.fromList(value.sublist(0, 1)));
  leaf.putIfAbsent('9F36', () => Uint8List.fromList(value.sublist(1, 3)));
  leaf.putIfAbsent('9F26', () => Uint8List.fromList(value.sublist(3, 11)));
  if (value.length > 11) {
    leaf.putIfAbsent('9F10', () => Uint8List.fromList(value.sublist(11)));
  }
}

int _bytesToInt(Uint8List b) {
  var v = 0;
  for (final x in b) {
    v = (v << 8) | x;
  }
  return v;
}

String _ascii(Uint8List b) =>
    String.fromCharCodes(b.where((c) => c >= 0x20 && c < 0x7F)).trim();

String _bcd(Uint8List b) => bytesToHex(b);

// ISO 4217 numeric -> alpha (common)
const Map<String, String> _currencies = {
  '0840': 'USD',
  '0978': 'EUR',
  '0826': 'GBP',
  '0392': 'JPY',
  '0756': 'CHF',
  '0124': 'CAD',
  '0036': 'AUD',
  '0156': 'CNY',
  '0356': 'INR',
  '0643': 'RUB',
  '0752': 'SEK',
  '0578': 'NOK',
  '0208': 'DKK',
  '0985': 'PLN',
  '0986': 'BRL',
  '0484': 'MXN',
  '0710': 'ZAR',
  '0344': 'HKD',
  '0702': 'SGD',
  '0410': 'KRW',
};
// ISO 3166 numeric -> alpha2 (common)
const Map<String, String> _countries = {
  '0840': 'US',
  '0826': 'GB',
  '0250': 'FR',
  '0276': 'DE',
  '0724': 'ES',
  '0380': 'IT',
  '0528': 'NL',
  '0056': 'BE',
  '0578': 'NO',
  '0752': 'SE',
  '0208': 'DK',
  '0246': 'FI',
  '0372': 'IE',
  '0620': 'PT',
  '0756': 'CH',
  '0040': 'AT',
  '0616': 'PL',
  '0124': 'CA',
  '0484': 'MX',
  '0076': 'BR',
  '0392': 'JP',
  '0156': 'CN',
  '0356': 'IN',
  '0643': 'RU',
  '0036': 'AU',
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

// Extract the human-friendly card fields from a prebuilt leaf map.
Map<String, String> emvExtractFields(Map<String, Uint8List> leaf) {
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
  if (leaf.containsKey('5F34') && leaf['5F34']!.isNotEmpty) {
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
  if (leaf.containsKey('5F2D')) {
    f['Language'] = _ascii(leaf['5F2D']!);
  }
  if (leaf.containsKey('9F08')) {
    f['App version'] = bytesToHex(leaf['9F08']!).toUpperCase();
  }
  if (leaf.containsKey('9F07')) {
    f['Application usage'] = bytesToHex(leaf['9F07']!).toUpperCase();
  }
  if (leaf.containsKey('8E')) {
    f['CVM list'] = bytesToHex(leaf['8E']!).toUpperCase();
  }
  if (leaf.containsKey('9F0D')) {
    f['IAC default'] = bytesToHex(leaf['9F0D']!).toUpperCase();
  }
  if (leaf.containsKey('9F0E')) {
    f['IAC denial'] = bytesToHex(leaf['9F0E']!).toUpperCase();
  }
  if (leaf.containsKey('9F0F')) {
    f['IAC online'] = bytesToHex(leaf['9F0F']!).toUpperCase();
  }
  if (leaf.containsKey('9F36') && leaf['9F36']!.isNotEmpty) {
    f['ATC'] = _bytesToInt(leaf['9F36']!).toString();
  }
  if (leaf.containsKey('9F17') && leaf['9F17']!.isNotEmpty) {
    f['PIN try counter'] = leaf['9F17']![0].toString();
  }
  if (leaf.containsKey('9F4D')) {
    f['Log entry'] = bytesToHex(leaf['9F4D']!).toUpperCase();
  }
  if (leaf.containsKey('9F10')) {
    f['Issuer app data'] = bytesToHex(leaf['9F10']!).toUpperCase();
  }
  if (leaf.containsKey('9F6C')) {
    f['CTQ'] = bytesToHex(leaf['9F6C']!).toUpperCase();
  }
  if (leaf.containsKey('9F6E')) {
    f['Form factor'] = bytesToHex(leaf['9F6E']!).toUpperCase();
  }
  if (leaf.containsKey('9F26')) {
    f['Cryptogram'] = bytesToHex(leaf['9F26']!).toUpperCase();
  }
  if (leaf.containsKey('5F50')) {
    f['Issuer URL'] = _ascii(leaf['5F50']!);
  }
  return f;
}

// Decoded Application Interchange Profile (tag 82) — the card's security
// posture. Relevant to a relay-resistance assessment:
//   - RRP (Relay Resistance Protocol): if supported, the terminal times the
//     ISO-DEP round-trip and rejects the latency a relay adds => relay blocked.
//   - DDA/CDA: dynamic authentication => the card can't be trivially cloned.
class EmvAip {
  final List<String> features; // human-readable enabled capabilities
  final bool rrp; // Relay Resistance Protocol supported
  final bool dda; // Dynamic Data Authentication
  final bool cda; // Combined DDA / Application Cryptogram generation
  final String raw; // AIP hex
  EmvAip(this.features, this.rrp, this.dda, this.cda, this.raw);
}

enum EmvRrpAssessment {
  advertised,
  notAdvertised,
  notApplicable,
  unknownScheme,
}

EmvRrpAssessment emvAssessRrp(EmvAip aip, String? aid) {
  if (aid == null || aid.isEmpty) return EmvRrpAssessment.unknownScheme;
  final mastercard = aid.toUpperCase().startsWith('A000000004');
  if (!mastercard) return EmvRrpAssessment.notApplicable;
  return aip.rrp ? EmvRrpAssessment.advertised : EmvRrpAssessment.notAdvertised;
}

// Decode the AIP (tag 82) from the parsed TLVs. Bit assignments per EMV Book 3
// (byte 1) and EMV Contactless Book C-2 (byte 2, incl. RRP). Returns null if
// the card exposed no AIP.
EmvAip? emvDecodeAip(Map<String, Uint8List> leaf) {
  final aip = leaf['82'];
  if (aip == null || aip.length < 2) return null;
  final b1 = aip[0];
  final b2 = aip[1];
  final f = <String>[];
  if (b1 & 0x40 != 0) f.add('SDA (static data authentication)');
  if (b1 & 0x20 != 0) f.add('DDA (dynamic data authentication)');
  if (b1 & 0x10 != 0) f.add('Cardholder verification supported');
  if (b1 & 0x08 != 0) f.add('Terminal risk management');
  if (b1 & 0x04 != 0) f.add('Issuer authentication');
  if (b1 & 0x02 != 0) f.add('On-device cardholder verification (CDCVM)');
  if (b1 & 0x01 != 0) f.add('CDA (combined DDA/AC generation)');
  if (b2 & 0x80 != 0) f.add('EMV mode supported');
  final rrp = (b2 & 0x01) != 0;
  return EmvAip(
      f, rrp, b1 & 0x20 != 0, b1 & 0x01 != 0, bytesToHex(aip).toUpperCase());
}

// Extract the transaction/GENERATE-AC result from a prebuilt leaf map.
Map<String, String> emvExtractCryptogram(Map<String, Uint8List> leaf) {
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
  if (leaf.containsKey('9F36') && leaf['9F36']!.isNotEmpty) {
    f['ATC'] = _bytesToInt(leaf['9F36']!).toString();
  }
  if (leaf.containsKey('9F10')) {
    f['Issuer Application Data'] = bytesToHex(leaf['9F10']!).toUpperCase();
  }
  return f;
}

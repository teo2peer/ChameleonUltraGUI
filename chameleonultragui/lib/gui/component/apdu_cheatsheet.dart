import 'package:flutter/material.dart';

class ApduCheatSheet extends StatelessWidget {
  const ApduCheatSheet({
    super.key,
    this.showEmv = true,
    this.showRelayLab = true,
    this.onExampleSelected,
  });

  final bool showEmv;
  final bool showRelayLab;
  final ValueChanged<String>? onExampleSelected;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ExpansionTile(
        leading: const Icon(Icons.menu_book),
        title: const Text('APDU cheat sheet'),
        subtitle: const Text('Structure, commands, status words and examples'),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          _section('APDU STRUCTURE'),
          _entry(
            'Command',
            'CLA INS P1 P2 [Lc] [Data] [Le]',
            'Lc is command-data length. Le is expected response length.',
          ),
          _entry(
            'Response',
            '[Data] SW1 SW2',
            'The final two bytes are the status word.',
          ),
          if (showEmv) ...[
            _section('COMMON EMV COMMANDS'),
            _entry(
              'SELECT PPSE',
              '00 A4 04 00 0E 325041592E5359532E4444463031 00',
              'Select contactless payment directory.',
              example: '00A404000E325041592E5359532E444446303100',
            ),
            _entry('SELECT AID', '00 A4 04 00 Lc <AID> 00',
                'Select one advertised application.'),
            _entry(
                'GET PROCESSING OPTIONS',
                '80 A8 00 00 Lc 83 L <PDOL values> 00',
                'Starts application processing; may advance card/Wallet state.'),
            _entry('READ RECORD', '00 B2 <record> <SFI control> 00',
                'Read a record referenced by AFL.'),
            _entry(
              'GET DATA (ATC)',
              '80 CA 9F 36 00',
              'Request Application Transaction Counter.',
              example: '80CA9F3600',
            ),
            _entry('GET RESPONSE', '00 C0 00 00 <Le>',
                'Retrieve bytes announced by status 61xx.'),
            _entry('GENERATE AC', '80 AE <00|40|80> 00 Lc <CDOL1> 00',
                'Request AAC, TC, or ARQC. State-changing.'),
          ],
          if (showRelayLab) ...[
            _section('SYNTHETIC RELAY LAB'),
            _entry(
              'SELECT private AID',
              '00 A4 04 00 07 F0010203040506 00',
              'Required before private CLA commands are forwarded.',
              example: '00A4040007F001020304050600',
            ),
            _entry(
              'Nonce challenge',
              'F0 10 00 00 08 <8-byte nonce>',
              'Response should bind the same nonce.',
              example: 'F0100000080102030405060708',
            ),
            _entry(
              'Status',
              'F0 30 00 00 00',
              'Example private status request.',
              example: 'F030000000',
            ),
            _entry('Any private APDU', 'F0 INS P1 P2 ...',
                'Forwarded after successful private-AID selection, up to 64 bytes.'),
          ],
          _section('COMMON STATUS WORDS'),
          _status('9000', 'Success'),
          _status('61xx', 'More response bytes; use GET RESPONSE'),
          _status('6700', 'Wrong length'),
          _status('6982', 'Security status not satisfied'),
          _status('6985', 'Conditions of use not satisfied'),
          _status('6986', 'Command not allowed/no current EF'),
          _status('6A80', 'Incorrect command data'),
          _status('6A82', 'File/application not found'),
          _status('6A83', 'Record not found'),
          _status('6A86', 'Incorrect P1/P2'),
          _status('6Cxx', 'Wrong Le; SW2 gives exact length'),
          _status('6D00', 'INS not supported'),
          _status('6E00', 'CLA not supported'),
          const SizedBox(height: 8),
          const Text(
            '9000 or a Wallet “Done” animation is protocol evidence, not issuer approval or settlement.',
            style: TextStyle(fontStyle: FontStyle.italic),
          ),
        ],
      ),
    );
  }

  Widget _section(String title) => Padding(
        padding: const EdgeInsets.only(top: 14, bottom: 5),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(title,
              style: const TextStyle(
                  fontWeight: FontWeight.bold, letterSpacing: 0.5)),
        ),
      );

  Widget _entry(String name, String syntax, String meaning, {String? example}) {
    return InkWell(
      onTap: example == null || onExampleSelected == null
          ? null
          : () => onExampleSelected!(example),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                    child: Text(name,
                        style: const TextStyle(fontWeight: FontWeight.w600))),
                if (example != null && onExampleSelected != null)
                  const Icon(Icons.input, size: 16),
              ],
            ),
            SelectableText(syntax,
                style: const TextStyle(fontFamily: 'RobotoMono', fontSize: 11)),
            Text(meaning, style: const TextStyle(fontSize: 12)),
          ],
        ),
      ),
    );
  }

  Widget _status(String status, String meaning) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 52,
              child: Text(status,
                  style: const TextStyle(
                      fontFamily: 'RobotoMono', fontWeight: FontWeight.bold)),
            ),
            Expanded(child: Text(meaning)),
          ],
        ),
      );
}

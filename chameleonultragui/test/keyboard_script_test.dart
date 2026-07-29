import 'dart:convert';

import 'package:chameleonultragui/helpers/keyboard_layout.dart';
import 'package:chameleonultragui/helpers/keyboard_script.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('compiles TEXT, DELAY, KEY, and CHORD to firmware bytecode', () {
    final program = compileKeyboardScript(r'''
# Login sequence
TEXT "aA1!?\n"
DELAY 258
KEY TAB
CHORD LCTRL+LSHIFT+ESC
CHORD LCTRL++
''');

    expect(program, [
      0x02, 0x00, 0x04, // a
      0x02, 0x02, 0x04, // A
      0x02, 0x00, 0x1E, // 1
      0x02, 0x02, 0x1E, // !
      0x02, 0x02, 0x38, // ?
      0x02, 0x00, 0x28, // newline
      0x01, 0x01, 0x02,
      0x02, 0x00, 0x2B,
      0x02, 0x03, 0x29,
      0x02, 0x03, 0x2E,
      0x00,
    ]);
  });

  test('maps the supported US keyboard names and punctuation', () {
    expect(keyboardKeyToHid('F12'), (0, 0x45));
    expect(keyboardKeyToHid('RIGHT'), (0, 0x4F));
    expect(keyboardKeyToHid('UNDERSCORE'), (0x02, 0x2D));
    expect(keyboardKeyToHid(r'$'), (0x02, 0x21));
  });

  test('compiles common DuckyScript aliases', () {
    final program = compileKeyboardScript('''REM standard syntax
GUI r
DELAY 500
STRING notepad
ENTER
CTRL SHIFT s
ALT d
STRINGLN done
''');

    expect(program, [
      0x02,
      0x08,
      0x15,
      0x01,
      0x01,
      0xF4,
      0x02,
      0x00,
      0x11,
      0x02,
      0x00,
      0x12,
      0x02,
      0x00,
      0x17,
      0x02,
      0x00,
      0x08,
      0x02,
      0x00,
      0x13,
      0x02,
      0x00,
      0x04,
      0x02,
      0x00,
      0x07,
      0x02,
      0x00,
      0x28,
      0x02,
      0x03,
      0x16,
      0x02,
      0x04,
      0x07,
      0x02,
      0x00,
      0x07,
      0x02,
      0x00,
      0x12,
      0x02,
      0x00,
      0x11,
      0x02,
      0x00,
      0x08,
      0x02,
      0x00,
      0x28,
      0x00,
    ]);
  });

  test('DuckyScript STRING accepts shell path characters', () {
    final program = compileKeyboardScript(
        r'STRING C:\Users\%USERPROFILE%\AppData\run.bat&whoami');
    expect(program.last, 0);
    expect(program.length, greaterThan(1));
  });

  test('keeps key commands layout-aware and separate from text case', () {
    expect(compileKeyboardScript('KEY A'), [0x02, 0x00, 0x04, 0x00]);
    expect(compileKeyboardScript('CHORD LCTRL+A'), [0x02, 0x01, 0x04, 0x00]);
    expect(compileKeyboardScript('TEXT "aA"'),
        [0x02, 0x00, 0x04, 0x02, 0x02, 0x04, 0x00]);
    expect(
      () => compileKeyboardScript('KEY a'),
      throwsA(isA<KeyboardScriptError>().having((error) => error.message,
          'message', contains('line 1: unsupported'))),
    );
    expect(
      compileKeyboardScript('KEY Y\nCHORD LCTRL+Z', layout: KeyboardLayout.de),
      [0x02, 0x00, 0x1D, 0x02, 0x01, 0x1C, 0x00],
    );
  });

  test('supports common printable ASCII on every layout', () {
    final ascii =
        String.fromCharCodes(List.generate(95, (index) => index + 32));
    for (final layout in KeyboardLayout.values) {
      expect(
        () => compileKeyboardScript(
          'TEXT ${jsonEncode(ascii)}',
          layout: layout,
        ),
        returnsNormally,
        reason: layout.name,
      );
    }
  });

  test('compiles each layout required non-ASCII repertoire', () {
    const repertoire = <KeyboardLayout, String>{
      KeyboardLayout.uk: '£€¬¦',
      KeyboardLayout.es: 'ñÑáéíóúÁÉÍÓÚüÜ¿¡çÇºª·€¬',
      KeyboardLayout.de: 'äöüÄÖÜßáéíóúÁÉÍÓÚàèìòùÀÈÌÒÙâêîôûÂÊÎÔÛ°§²³€µ',
      KeyboardLayout.fr: 'éèàùçâêîôûÂÊÎÔÛäëïöüÄËÏÖÜ²°£µ§€',
      KeyboardLayout.it: 'àèéìòùç£°§€',
      KeyboardLayout.pt:
          'çÇáéíóúÁÉÍÓÚàèìòùÀÈÌÒÙâêîôûÂÊÎÔÛãõÃÕäëïöüÄËÏÖÜºª«»£§€',
    };
    for (final entry in repertoire.entries) {
      expect(
        () => compileKeyboardScript(
          'TEXT ${jsonEncode(entry.value)}',
          layout: entry.key,
        ),
        returnsNormally,
        reason: entry.key.name,
      );
    }
  });

  test('maps UK symbols and ISO punctuation positions', () {
    expect(keyboardCharacterToTaps('£', KeyboardLayout.uk), [
      (modifier: 0x02, usage: 0x20),
    ]);
    expect(keyboardCharacterToTaps('€', KeyboardLayout.uk), [
      (modifier: 0x40, usage: 0x21),
    ]);
    expect(keyboardCharacterToTaps('¬', KeyboardLayout.uk), [
      (modifier: 0x02, usage: 0x35),
    ]);
    expect(keyboardCharacterToTaps('¦', KeyboardLayout.uk), [
      (modifier: 0x40, usage: 0x35),
    ]);
    expect(keyboardCharacterToTaps('\\', KeyboardLayout.uk), [
      (modifier: 0, usage: 0x64),
    ]);
  });

  test('maps Spanish direct characters and dead-key accents', () {
    expect(keyboardCharacterToTaps('ñ', KeyboardLayout.es), [
      (modifier: 0, usage: 0x33),
    ]);
    expect(keyboardCharacterToTaps('Ñ', KeyboardLayout.es), [
      (modifier: 0x02, usage: 0x33),
    ]);
    expect(keyboardCharacterToTaps('á', KeyboardLayout.es), [
      (modifier: 0, usage: 0x34),
      (modifier: 0, usage: 0x04),
    ]);
    expect(keyboardCharacterToTaps('Ü', KeyboardLayout.es), [
      (modifier: 0x02, usage: 0x34),
      (modifier: 0x02, usage: 0x18),
    ]);
    expect(keyboardCharacterToTaps('¿', KeyboardLayout.es), [
      (modifier: 0x02, usage: 0x2E),
    ]);
    expect(keyboardCharacterToTaps('¡', KeyboardLayout.es), [
      (modifier: 0, usage: 0x2E),
    ]);
    expect(keyboardCharacterToTaps('ç', KeyboardLayout.es), [
      (modifier: 0, usage: 0x32),
    ]);
  });

  test('maps German QWERTZ, umlauts, sharp s, and common accents', () {
    expect(keyboardCharacterToTaps('y', KeyboardLayout.de), [
      (modifier: 0, usage: 0x1D),
    ]);
    expect(keyboardCharacterToTaps('z', KeyboardLayout.de), [
      (modifier: 0, usage: 0x1C),
    ]);
    expect(keyboardCharacterToTaps('Ä', KeyboardLayout.de), [
      (modifier: 0x02, usage: 0x34),
    ]);
    expect(keyboardCharacterToTaps('ß', KeyboardLayout.de), [
      (modifier: 0, usage: 0x2D),
    ]);
    expect(keyboardCharacterToTaps('É', KeyboardLayout.de), [
      (modifier: 0, usage: 0x2E),
      (modifier: 0x02, usage: 0x08),
    ]);
    expect(keyboardCharacterToTaps('ô', KeyboardLayout.de), [
      (modifier: 0, usage: 0x35),
      (modifier: 0, usage: 0x12),
    ]);
  });

  test('maps French AZERTY and deterministic dead-key compositions', () {
    expect(keyboardCharacterToTaps('a', KeyboardLayout.fr), [
      (modifier: 0, usage: 0x14),
    ]);
    expect(keyboardCharacterToTaps('m', KeyboardLayout.fr), [
      (modifier: 0, usage: 0x33),
    ]);
    expect(keyboardCharacterToTaps('é', KeyboardLayout.fr), [
      (modifier: 0, usage: 0x1F),
    ]);
    expect(keyboardCharacterToTaps('ç', KeyboardLayout.fr), [
      (modifier: 0, usage: 0x26),
    ]);
    expect(keyboardCharacterToTaps('Â', KeyboardLayout.fr), [
      (modifier: 0, usage: 0x2F),
      (modifier: 0x02, usage: 0x14),
    ]);
    expect(keyboardCharacterToTaps('ë', KeyboardLayout.fr), [
      (modifier: 0x02, usage: 0x2F),
      (modifier: 0, usage: 0x08),
    ]);
    for (final impossible in ['É', 'È', 'À', 'Ù', 'Ç']) {
      expect(
        () => compileKeyboardScript(
          'TEXT ${jsonEncode(impossible)}',
          layout: KeyboardLayout.fr,
        ),
        throwsA(isA<KeyboardScriptError>()),
        reason: impossible,
      );
    }
  });

  test('maps Italian direct lowercase accents', () {
    expect(keyboardCharacterToTaps('à', KeyboardLayout.it), [
      (modifier: 0, usage: 0x34),
    ]);
    expect(keyboardCharacterToTaps('é', KeyboardLayout.it), [
      (modifier: 0x02, usage: 0x2F),
    ]);
    expect(keyboardCharacterToTaps('ì', KeyboardLayout.it), [
      (modifier: 0, usage: 0x2E),
    ]);
    expect(keyboardCharacterToTaps('ç', KeyboardLayout.it), [
      (modifier: 0x02, usage: 0x33),
    ]);
  });

  test('maps Portuguese symbols and all supported dead-key families', () {
    expect(keyboardCharacterToTaps('Ç', KeyboardLayout.pt), [
      (modifier: 0x02, usage: 0x33),
    ]);
    expect(keyboardCharacterToTaps('º', KeyboardLayout.pt), [
      (modifier: 0, usage: 0x34),
    ]);
    expect(keyboardCharacterToTaps('ª', KeyboardLayout.pt), [
      (modifier: 0x02, usage: 0x34),
    ]);
    expect(keyboardCharacterToTaps('«', KeyboardLayout.pt), [
      (modifier: 0, usage: 0x2E),
    ]);
    expect(keyboardCharacterToTaps('»', KeyboardLayout.pt), [
      (modifier: 0x02, usage: 0x2E),
    ]);
    expect(keyboardCharacterToTaps('á', KeyboardLayout.pt)!.first,
        (modifier: 0, usage: 0x30));
    expect(keyboardCharacterToTaps('à', KeyboardLayout.pt)!.first,
        (modifier: 0x02, usage: 0x30));
    expect(keyboardCharacterToTaps('â', KeyboardLayout.pt)!.first,
        (modifier: 0x02, usage: 0x32));
    expect(keyboardCharacterToTaps('ã', KeyboardLayout.pt)!.first,
        (modifier: 0, usage: 0x32));
    expect(keyboardCharacterToTaps('ä', KeyboardLayout.pt)!.first,
        (modifier: 0x40, usage: 0x2F));
  });

  test('normalizes common decomposed input without a dependency', () {
    expect(
      compileKeyboardScript('TEXT "n\\u0303a\\u0301u\\u0308c\\u0327"',
          layout: KeyboardLayout.es),
      compileKeyboardScript('TEXT "ñáüç"', layout: KeyboardLayout.es),
    );
    expect(
      compileKeyboardScript('TEXT "a\\u0303A\\u0302u\\u0308"',
          layout: KeyboardLayout.pt),
      compileKeyboardScript('TEXT "ãÂü"', layout: KeyboardLayout.pt),
    );
  });

  test('rejects malformed source with a line number', () {
    expect(
      () => compileKeyboardScript('TEXT not-json'),
      throwsA(isA<KeyboardScriptError>().having(
          (error) => error.message, 'message', contains('line 1: TEXT'))),
    );
    expect(
      () => compileKeyboardScript('CHORD CTRL+A'),
      returnsNormally,
    );
    expect(
      () => compileKeyboardScript('TEXT "é"'),
      throwsA(isA<KeyboardScriptError>()
          .having((error) => error.message, 'message', contains('US layout'))),
    );
    expect(
      () => compileKeyboardScript('DELAY 999999999999999999999999999999'),
      throwsA(isA<KeyboardScriptError>().having(
          (error) => error.message, 'message', contains('line 1: DELAY'))),
    );
  });

  test('enforces tap and explicit delay limits', () {
    final tooManyTaps = List.filled(keyboardMaxTaps + 1, 'KEY A').join('\n');
    expect(() => compileKeyboardScript(tooManyTaps),
        throwsA(isA<KeyboardScriptError>()));

    final tooMuchDelay = List.filled(7, 'DELAY 10000').join('\n');
    expect(() => compileKeyboardScript(tooMuchDelay),
        throwsA(isA<KeyboardScriptError>()));
  });

  test('accepts exactly 4096 bytes and rejects larger programs', () {
    final maximum = [
      ...List.filled(1024, 'KEY A'),
      ...List.filled(341, 'DELAY 1'),
    ].join('\n');
    expect(compileKeyboardScript(maximum), hasLength(4096));

    expect(
      () => compileKeyboardScript('$maximum\nDELAY 1'),
      throwsA(isA<KeyboardScriptError>()),
    );
  });
}

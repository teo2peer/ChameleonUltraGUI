import 'dart:convert';

import 'package:chameleonultragui/bridge/chameleon_keyboard.dart';
import 'package:chameleonultragui/helpers/keyboard_layout.dart';
import 'package:chameleonultragui/helpers/saved_keyboard_script.dart';
import 'package:chameleonultragui/sharedprefsprovider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await SharedPreferencesProvider().load();
  });

  test('saved scripts round-trip source, metadata, and compiled bytecode', () {
    final updatedAt = DateTime.utc(2026, 7, 11, 12, 30);
    final saved = SavedKeyboardScript.compile(
      id: 'script-1',
      name: ' Spanish greeting ',
      source: 'STRING Hola, senor!\nENTER',
      layout: KeyboardLayout.es,
      output: KeyboardOutput.ble,
      updatedAt: updatedAt,
    );

    final restored = SavedKeyboardScript.fromJson(saved.toJson());

    expect(restored.id, 'script-1');
    expect(restored.name, 'Spanish greeting');
    expect(restored.source, saved.source);
    expect(restored.layout, KeyboardLayout.es);
    expect(restored.output, KeyboardOutput.ble);
    expect(restored.program, orderedEquals(saved.program));
    expect(restored.updatedAt, updatedAt);
  });

  test('old compiler entries are rebuilt from their source', () {
    final saved = SavedKeyboardScript.compile(
      id: 'script-2',
      name: 'Rebuild me',
      source: 'STRINGLN updated',
      layout: KeyboardLayout.us,
      output: KeyboardOutput.usb,
    );
    final data = jsonDecode(saved.toJson()) as Map<String, dynamic>
      ..['compilerVersion'] = 0
      ..['program'] = base64Encode([0xFF]);

    final restored = SavedKeyboardScript.fromJson(jsonEncode(data));

    expect(restored.program, orderedEquals(saved.program));
  });

  test('current compiler entries reject a source and program mismatch', () {
    final saved = SavedKeyboardScript.compile(
      id: 'script-mismatch',
      name: 'Mismatch',
      source: 'ENTER',
      layout: KeyboardLayout.us,
      output: KeyboardOutput.usb,
    );
    final data = jsonDecode(saved.toJson()) as Map<String, dynamic>
      ..['source'] = 'TAB';

    expect(
      () => SavedKeyboardScript.fromJson(jsonEncode(data)),
      throwsA(isA<FormatException>()),
    );
  });

  test('preferences sort scripts and ignore corrupt entries', () async {
    final older = SavedKeyboardScript.compile(
      id: 'older',
      name: 'Older',
      source: 'ENTER',
      layout: KeyboardLayout.us,
      output: KeyboardOutput.usb,
      updatedAt: DateTime.utc(2026, 1, 1),
    );
    final newer = SavedKeyboardScript.compile(
      id: 'newer',
      name: 'Newer',
      source: 'TAB',
      layout: KeyboardLayout.uk,
      output: KeyboardOutput.both,
      updatedAt: DateTime.utc(2026, 2, 1),
    );
    final preferences = SharedPreferencesProvider();
    await preferences.setKeyboardScripts([older, newer]);
    final raw = await SharedPreferences.getInstance();
    await raw.setStringList('keyboard_scripts', [
      ...raw.getStringList('keyboard_scripts')!,
      '{not-json',
    ]);

    final restored = preferences.getKeyboardScripts();

    expect(restored.map((script) => script.id), ['newer', 'older']);
  });

  test('preferences retain the full 255-script library', () async {
    final scripts = List.generate(
      savedKeyboardScriptLimit,
      (index) => SavedKeyboardScript.compile(
        id: 'script-$index',
        name: 'Script $index',
        source: 'ENTER',
        layout: KeyboardLayout.us,
        output: KeyboardOutput.ble,
        updatedAt: DateTime.utc(2026, 1, 1).add(Duration(seconds: index)),
      ),
    );
    final preferences = SharedPreferencesProvider();

    await preferences.setKeyboardScripts(scripts);
    final restored = preferences.getKeyboardScripts();

    expect(restored, hasLength(255));
    expect(restored.first.id, 'script-254');
    expect(restored.last.id, 'script-0');
  });
}

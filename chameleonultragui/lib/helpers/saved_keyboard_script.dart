import 'dart:convert';
import 'dart:typed_data';

import 'package:chameleonultragui/bridge/chameleon_keyboard.dart';
import 'package:chameleonultragui/helpers/keyboard_layout.dart';
import 'package:chameleonultragui/helpers/keyboard_script.dart';
import 'package:uuid/uuid.dart';

const int savedKeyboardScriptLimit = 255;
const int savedKeyboardScriptNameLimit = 64;
const int savedKeyboardScriptSourceLimit = 16 * 1024;
const int _savedKeyboardScriptFormatVersion = 1;
const int _keyboardCompilerVersion = 1;

class SavedKeyboardScript {
  final String id;
  final String name;
  final String source;
  final KeyboardLayout layout;
  final KeyboardOutput output;
  final Uint8List program;
  final DateTime updatedAt;

  SavedKeyboardScript._({
    required this.id,
    required this.name,
    required this.source,
    required this.layout,
    required this.output,
    required this.program,
    required this.updatedAt,
  });

  factory SavedKeyboardScript.compile({
    String? id,
    required String name,
    required String source,
    required KeyboardLayout layout,
    required KeyboardOutput output,
    DateTime? updatedAt,
  }) {
    final normalizedName = name.trim();
    _validateText(normalizedName, source);
    return SavedKeyboardScript._(
      id: id ?? const Uuid().v4(),
      name: normalizedName,
      source: source,
      layout: layout,
      output: output,
      program: compileKeyboardScript(source, layout: layout),
      updatedAt: updatedAt ?? DateTime.now().toUtc(),
    );
  }

  factory SavedKeyboardScript.fromJson(String encoded) {
    final data = jsonDecode(encoded);
    if (data is! Map<String, dynamic> ||
        data['formatVersion'] != _savedKeyboardScriptFormatVersion) {
      throw const FormatException('Unsupported saved keyboard script format');
    }

    final id = data['id'];
    final name = data['name'];
    final source = data['source'];
    final layoutName = data['layout'];
    final outputName = data['output'];
    final compilerVersion = data['compilerVersion'];
    final encodedProgram = data['program'];
    final updatedAtMilliseconds = data['updatedAt'];
    if (id is! String ||
        id.isEmpty ||
        name is! String ||
        source is! String ||
        layoutName is! String ||
        outputName is! String ||
        compilerVersion is! int ||
        encodedProgram is! String ||
        updatedAtMilliseconds is! int) {
      throw const FormatException('Invalid saved keyboard script metadata');
    }

    final normalizedName = name.trim();
    _validateText(normalizedName, source);
    final layout = KeyboardLayout.values.byName(layoutName);
    final output = KeyboardOutput.values.byName(outputName);
    final program = compileKeyboardScript(source, layout: layout);
    if (compilerVersion < 0 || compilerVersion > _keyboardCompilerVersion) {
      throw const FormatException('Unsupported keyboard compiler version');
    }
    if (compilerVersion == _keyboardCompilerVersion) {
      final storedProgram = Uint8List.fromList(base64Decode(encodedProgram));
      if (!_programsEqual(program, storedProgram)) {
        throw const FormatException(
            'Saved keyboard program does not match its source');
      }
    }
    if (program.isEmpty || program.length > keyboardMaxProgramBytes) {
      throw const FormatException('Invalid saved keyboard program');
    }

    return SavedKeyboardScript._(
      id: id,
      name: normalizedName,
      source: source,
      layout: layout,
      output: output,
      program: program,
      updatedAt: DateTime.fromMillisecondsSinceEpoch(updatedAtMilliseconds,
          isUtc: true),
    );
  }

  String toJson() => jsonEncode({
        'formatVersion': _savedKeyboardScriptFormatVersion,
        'compilerVersion': _keyboardCompilerVersion,
        'id': id,
        'name': name,
        'source': source,
        'layout': layout.name,
        'output': output.name,
        'program': base64Encode(program),
        'updatedAt': updatedAt.millisecondsSinceEpoch,
      });

  static void _validateText(String name, String source) {
    if (name.isEmpty || name.length > savedKeyboardScriptNameLimit) {
      throw const FormatException(
          'Script name must contain 1 to 64 characters');
    }
    if (source.length > savedKeyboardScriptSourceLimit) {
      throw const FormatException('Script source exceeds the 16 KiB limit');
    }
  }
}

bool _programsEqual(Uint8List first, Uint8List second) {
  if (first.length != second.length) return false;
  for (var index = 0; index < first.length; index++) {
    if (first[index] != second[index]) return false;
  }
  return true;
}

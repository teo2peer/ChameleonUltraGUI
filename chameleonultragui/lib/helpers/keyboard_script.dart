import 'dart:convert';
import 'dart:typed_data';

import 'package:chameleonultragui/helpers/keyboard_layout.dart';

const int keyboardMaxProgramBytes = 4096;
const int keyboardMaxTaps = 1024;
const int keyboardMaxExplicitDelayMs = 60000;

const int _opEnd = 0x00;
const int _opDelay = 0x01;
const int _opTap = 0x02;

class KeyboardScriptError implements Exception {
  final String message;

  const KeyboardScriptError(this.message);

  @override
  String toString() => message;
}

const Map<String, int> _modifiers = {
  'LCTRL': 0x01,
  'LSHIFT': 0x02,
  'LALT': 0x04,
  'LGUI': 0x08,
  'RCTRL': 0x10,
  'RSHIFT': 0x20,
  'RALT': 0x40,
  'RGUI': 0x80,
};

const Map<String, String> _modifierAliases = {
  'CTRL': 'LCTRL',
  'CONTROL': 'LCTRL',
  'SHIFT': 'LSHIFT',
  'ALT': 'LALT',
  'GUI': 'LGUI',
  'WINDOWS': 'LGUI',
  'COMMAND': 'LGUI',
  'LCTRL': 'LCTRL',
  'LSHIFT': 'LSHIFT',
  'LALT': 'LALT',
  'LGUI': 'LGUI',
  'RCTRL': 'RCTRL',
  'RSHIFT': 'RSHIFT',
  'RALT': 'RALT',
  'RGUI': 'RGUI',
};

const Map<String, int> _namedKeys = {
  'ENTER': 0x28,
  'ESC': 0x29,
  'BACKSPACE': 0x2A,
  'TAB': 0x2B,
  'SPACE': 0x2C,
  'HOME': 0x4A,
  'PAGEUP': 0x4B,
  'DELETE': 0x4C,
  'END': 0x4D,
  'PAGEDOWN': 0x4E,
  'RIGHT': 0x4F,
  'LEFT': 0x50,
  'DOWN': 0x51,
  'UP': 0x52,
  'F1': 0x3A,
  'F2': 0x3B,
  'F3': 0x3C,
  'F4': 0x3D,
  'F5': 0x3E,
  'F6': 0x3F,
  'F7': 0x40,
  'F8': 0x41,
  'F9': 0x42,
  'F10': 0x43,
  'F11': 0x44,
  'F12': 0x45,
};

const Map<String, String> _punctuationNames = {
  'MINUS': '-',
  'UNDERSCORE': '_',
  'EQUAL': '=',
  'PLUS': '+',
  'LEFTBRACKET': '[',
  'LEFTBRACE': '{',
  'RIGHTBRACKET': ']',
  'RIGHTBRACE': '}',
  'BACKSLASH': '\\',
  'PIPE': '|',
  'SEMICOLON': ';',
  'COLON': ':',
  'APOSTROPHE': "'",
  'QUOTE': '"',
  'GRAVE': '`',
  'TILDE': '~',
  'COMMA': ',',
  'LESS': '<',
  'PERIOD': '.',
  'GREATER': '>',
  'SLASH': '/',
  'QUESTION': '?',
  'EXCLAMATION': '!',
  'AT': '@',
  'HASH': '#',
  'DOLLAR': r'$',
  'PERCENT': '%',
  'CARET': '^',
  'AMPERSAND': '&',
  'ASTERISK': '*',
  'LEFTPAREN': '(',
  'RIGHTPAREN': ')',
};

(int, int) keyboardKeyToHid(
  String key, [
  KeyboardLayout layout = KeyboardLayout.us,
]) {
  if (key.isEmpty) {
    throw const KeyboardScriptError('key must not be empty');
  }

  if (key.runes.length == 1) {
    final code = key.runes.single;
    if (code >= 0x61 && code <= 0x7A) {
      throw KeyboardScriptError('unsupported key ${jsonEncode(key)}');
    }
    final tap = keyboardLogicalKeyTap(key, layout);
    if (tap != null) return (tap.modifier, tap.usage);
  }

  final upper = key.toUpperCase();
  if (key == upper && _namedKeys.containsKey(upper)) {
    return (0, _namedKeys[upper]!);
  }
  if (key == upper && _punctuationNames.containsKey(upper)) {
    final tap = keyboardLogicalKeyTap(_punctuationNames[upper]!, layout);
    if (tap != null) return (tap.modifier, tap.usage);
  }
  throw KeyboardScriptError('unsupported key ${jsonEncode(key)}');
}

(int, int) _parseChord(String value, KeyboardLayout layout) {
  final parts = value.endsWith('++')
      ? <String>[...value.substring(0, value.length - 2).split('+'), '+']
      : value.split('+');
  if (parts.length < 2 || parts.any((part) => part.isEmpty)) {
    throw const KeyboardScriptError(
        'CHORD requires one or more modifiers and exactly one key');
  }

  var modifier = 0;
  final seen = <String>{};
  for (final name in parts.take(parts.length - 1)) {
    final canonical = _modifierAliases[name];
    if (canonical == null) {
      throw KeyboardScriptError('invalid chord modifier ${jsonEncode(name)}');
    }
    if (!seen.add(canonical)) {
      throw KeyboardScriptError('duplicate chord modifier ${jsonEncode(name)}');
    }
    modifier |= _modifiers[canonical]!;
  }
  final (keyModifier, usage) = keyboardKeyToHid(parts.last, layout);
  return (modifier | keyModifier, usage);
}

(int, int) _parseDuckyChord(List<String> parts, KeyboardLayout layout) {
  if (parts.length < 2) {
    throw const KeyboardScriptError(
        'modifier command requires one or more modifiers and exactly one key');
  }
  var modifier = 0;
  final seen = <String>{};
  for (final name in parts.take(parts.length - 1)) {
    final canonical = _modifierAliases[name.toUpperCase()];
    if (canonical == null) {
      throw KeyboardScriptError('invalid modifier ${jsonEncode(name)}');
    }
    if (!seen.add(canonical)) {
      throw KeyboardScriptError('duplicate modifier ${jsonEncode(name)}');
    }
    modifier |= _modifiers[canonical]!;
  }
  final (keyModifier, usage) =
      keyboardKeyToHid(parts.last.toUpperCase(), layout);
  return (modifier | keyModifier, usage);
}

Uint8List compileKeyboardScript(
  String source, {
  KeyboardLayout layout = KeyboardLayout.us,
}) {
  final program = BytesBuilder(copy: false);
  var programLength = 0;
  var tapCount = 0;
  var totalDelay = 0;

  void addBytes(List<int> bytes) {
    program.add(bytes);
    programLength += bytes.length;
  }

  void addTap(int modifier, int usage) {
    tapCount++;
    if (tapCount > keyboardMaxTaps) {
      throw const KeyboardScriptError('script exceeds $keyboardMaxTaps taps');
    }
    addBytes([_opTap, modifier, usage]);
  }

  void addText(String text, String command) {
    for (final rune in normalizeKeyboardText(text).runes) {
      final character = String.fromCharCode(rune);
      final taps = keyboardCharacterToTaps(character, layout);
      if (taps == null) {
        throw KeyboardScriptError(
            '$command cannot type ${jsonEncode(character)} with the ${layout.name.toUpperCase()} layout');
      }
      for (final tap in taps) {
        addTap(tap.modifier, tap.usage);
      }
    }
  }

  final lines = source.split('\n');
  for (var index = 0; index < lines.length; index++) {
    final line = lines[index].trim();
    if (line.isEmpty || line.startsWith('#')) continue;
    final separator = line.indexOf(' ');
    final command = separator < 0 ? line : line.substring(0, separator);
    final argument = separator < 0 ? '' : line.substring(separator + 1).trim();
    if (command == 'REM') continue;

    try {
      switch (command) {
        case 'TEXT':
          if (argument.isEmpty || !argument.startsWith('"')) {
            throw const KeyboardScriptError(
                'TEXT requires one JSON quoted string');
          }
          Object? decoded;
          try {
            decoded = jsonDecode(argument);
          } on FormatException {
            throw const KeyboardScriptError(
                'TEXT requires one valid JSON quoted string');
          }
          if (decoded is! String) {
            throw const KeyboardScriptError('TEXT value must be a JSON string');
          }
          addText(decoded, 'TEXT');
        case 'STRING':
        case 'STRINGLN':
          addText(argument, command);
          if (command == 'STRINGLN') {
            final (modifier, usage) = keyboardKeyToHid('ENTER', layout);
            addTap(modifier, usage);
          }
        case 'DELAY':
          if (argument.isEmpty || !RegExp(r'^[0-9]+$').hasMatch(argument)) {
            throw const KeyboardScriptError('DELAY must be a decimal integer');
          }
          final delay = int.tryParse(argument);
          if (delay == null || delay < 1 || delay > 10000) {
            throw const KeyboardScriptError('DELAY must be 1..10000 ms');
          }
          totalDelay += delay;
          if (totalDelay > keyboardMaxExplicitDelayMs) {
            throw const KeyboardScriptError(
                'explicit delays exceed $keyboardMaxExplicitDelayMs ms');
          }
          addBytes([_opDelay, delay >> 8, delay & 0xFF]);
        case 'KEY':
          if (argument.isEmpty || argument.runes.any(_isWhitespace)) {
            throw const KeyboardScriptError(
                'KEY requires exactly one named key');
          }
          final (modifier, usage) = keyboardKeyToHid(argument, layout);
          addTap(modifier, usage);
        case 'CHORD':
          if (argument.isEmpty || argument.runes.any(_isWhitespace)) {
            throw const KeyboardScriptError(
                'CHORD requires modifiers joined with + and exactly one key');
          }
          final (modifier, usage) = _parseChord(argument, layout);
          addTap(modifier, usage);
        default:
          if (_modifierAliases.containsKey(command.toUpperCase())) {
            final parts = <String>[
              command,
              ...argument.split(RegExp(r'\s+')).where((part) => part.isNotEmpty)
            ];
            final (modifier, usage) = _parseDuckyChord(parts, layout);
            addTap(modifier, usage);
          } else if (argument.isEmpty) {
            final (modifier, usage) =
                keyboardKeyToHid(command.toUpperCase(), layout);
            addTap(modifier, usage);
          } else {
            throw KeyboardScriptError('unknown command ${jsonEncode(command)}');
          }
      }
    } on KeyboardScriptError catch (error) {
      throw KeyboardScriptError('line ${index + 1}: ${error.message}');
    }

    if (programLength + 1 > keyboardMaxProgramBytes) {
      throw const KeyboardScriptError(
          'compiled program exceeds $keyboardMaxProgramBytes bytes');
    }
  }

  addBytes(const [_opEnd]);
  return program.takeBytes();
}

bool _isWhitespace(int rune) => String.fromCharCode(rune).trim().isEmpty;

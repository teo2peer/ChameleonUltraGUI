// SPDX-License-Identifier: GPL-2.0-or-later
//
// Layout positions are derived from QMK Firmware's GPL-2.0-or-later
// quantum/keymap_extras keymap_uk.h, keymap_spanish.h, keymap_german.h,
// keymap_french.h, keymap_italian.h, and keymap_portuguese.h:
// https://github.com/qmk/qmk_firmware/tree/master/quantum/keymap_extras

enum KeyboardLayout { us, uk, es, de, fr, it, pt }

typedef KeyboardTap = ({int modifier, int usage});

const int _shift = 0x02;
const int _altGr = 0x40;
const int _space = 0x2C;

KeyboardTap _tap(int usage, [int modifier = 0]) =>
    (modifier: modifier, usage: usage);

List<KeyboardTap> _taps(KeyboardTap tap) => [tap];

Map<String, List<KeyboardTap>> _layout({
  Map<String, int> letterUsages = const {},
  required Map<String, KeyboardTap> direct,
  Map<String, List<KeyboardTap>> sequences = const {},
}) {
  final result = <String, List<KeyboardTap>>{
    ' ': _taps(_tap(_space)),
    '\n': _taps(_tap(0x28)),
    '\t': _taps(_tap(0x2B)),
  };
  for (var code = 0x61; code <= 0x7A; code++) {
    final lower = String.fromCharCode(code);
    final usage = letterUsages[lower] ?? 0x04 + code - 0x61;
    result[lower] = _taps(_tap(usage));
    result[lower.toUpperCase()] = _taps(_tap(usage, _shift));
  }
  for (var digit = 1; digit <= 9; digit++) {
    result['$digit'] = _taps(_tap(0x1D + digit));
  }
  result['0'] = _taps(_tap(0x27));
  for (final entry in direct.entries) {
    result[entry.key] = _taps(entry.value);
  }
  result.addAll(sequences);
  return result;
}

void _addCompositions(
  Map<String, List<KeyboardTap>> map,
  KeyboardTap deadKey,
  Map<String, String> compositions,
) {
  for (final entry in compositions.entries) {
    map[entry.key] = [deadKey, ...map[entry.value]!];
  }
}

const _acuteCompositions = <String, String>{
  'á': 'a',
  'é': 'e',
  'í': 'i',
  'ó': 'o',
  'ú': 'u',
  'Á': 'A',
  'É': 'E',
  'Í': 'I',
  'Ó': 'O',
  'Ú': 'U',
};

const _graveCompositions = <String, String>{
  'à': 'a',
  'è': 'e',
  'ì': 'i',
  'ò': 'o',
  'ù': 'u',
  'À': 'A',
  'È': 'E',
  'Ì': 'I',
  'Ò': 'O',
  'Ù': 'U',
};

const _circumflexCompositions = <String, String>{
  'â': 'a',
  'ê': 'e',
  'î': 'i',
  'ô': 'o',
  'û': 'u',
  'Â': 'A',
  'Ê': 'E',
  'Î': 'I',
  'Ô': 'O',
  'Û': 'U',
};

const _diaeresisCompositions = <String, String>{
  'ä': 'a',
  'ë': 'e',
  'ï': 'i',
  'ö': 'o',
  'ü': 'u',
  'Ä': 'A',
  'Ë': 'E',
  'Ï': 'I',
  'Ö': 'O',
  'Ü': 'U',
};

const _usPunctuation = <String, KeyboardTap>{
  '-': (modifier: 0, usage: 0x2D),
  '_': (modifier: _shift, usage: 0x2D),
  '=': (modifier: 0, usage: 0x2E),
  '+': (modifier: _shift, usage: 0x2E),
  '[': (modifier: 0, usage: 0x2F),
  '{': (modifier: _shift, usage: 0x2F),
  ']': (modifier: 0, usage: 0x30),
  '}': (modifier: _shift, usage: 0x30),
  '\\': (modifier: 0, usage: 0x31),
  '|': (modifier: _shift, usage: 0x31),
  ';': (modifier: 0, usage: 0x33),
  ':': (modifier: _shift, usage: 0x33),
  "'": (modifier: 0, usage: 0x34),
  '"': (modifier: _shift, usage: 0x34),
  '`': (modifier: 0, usage: 0x35),
  '~': (modifier: _shift, usage: 0x35),
  ',': (modifier: 0, usage: 0x36),
  '<': (modifier: _shift, usage: 0x36),
  '.': (modifier: 0, usage: 0x37),
  '>': (modifier: _shift, usage: 0x37),
  '/': (modifier: 0, usage: 0x38),
  '?': (modifier: _shift, usage: 0x38),
  '!': (modifier: _shift, usage: 0x1E),
  '@': (modifier: _shift, usage: 0x1F),
  '#': (modifier: _shift, usage: 0x20),
  r'$': (modifier: _shift, usage: 0x21),
  '%': (modifier: _shift, usage: 0x22),
  '^': (modifier: _shift, usage: 0x23),
  '&': (modifier: _shift, usage: 0x24),
  '*': (modifier: _shift, usage: 0x25),
  '(': (modifier: _shift, usage: 0x26),
  ')': (modifier: _shift, usage: 0x27),
};

Map<String, List<KeyboardTap>> _buildUk() => _layout(direct: {
      ..._usPunctuation,
      '"': _tap(0x1F, _shift),
      '@': _tap(0x34, _shift),
      '#': _tap(0x32),
      '~': _tap(0x32, _shift),
      '\\': _tap(0x64),
      '|': _tap(0x64, _shift),
      '£': _tap(0x20, _shift),
      '€': _tap(0x21, _altGr),
      '¬': _tap(0x35, _shift),
      '¦': _tap(0x35, _altGr),
    });

Map<String, List<KeyboardTap>> _buildSpanish() {
  final map = _layout(
    direct: {
      '!': _tap(0x1E, _shift),
      '"': _tap(0x1F, _shift),
      '#': _tap(0x20, _altGr),
      r'$': _tap(0x21, _shift),
      '%': _tap(0x22, _shift),
      '&': _tap(0x23, _shift),
      "'": _tap(0x2D),
      '(': _tap(0x25, _shift),
      ')': _tap(0x26, _shift),
      '*': _tap(0x30, _shift),
      '+': _tap(0x30),
      ',': _tap(0x36),
      '-': _tap(0x38),
      '.': _tap(0x37),
      '/': _tap(0x24, _shift),
      ':': _tap(0x37, _shift),
      ';': _tap(0x36, _shift),
      '<': _tap(0x64),
      '=': _tap(0x27, _shift),
      '>': _tap(0x64, _shift),
      '?': _tap(0x2D, _shift),
      '@': _tap(0x1F, _altGr),
      '[': _tap(0x2F, _altGr),
      '\\': _tap(0x35, _altGr),
      ']': _tap(0x30, _altGr),
      '_': _tap(0x38, _shift),
      '{': _tap(0x34, _altGr),
      '|': _tap(0x1E, _altGr),
      '}': _tap(0x32, _altGr),
      'º': _tap(0x35),
      'ª': _tap(0x35, _shift),
      '·': _tap(0x20, _shift),
      'ñ': _tap(0x33),
      'Ñ': _tap(0x33, _shift),
      'ç': _tap(0x32),
      'Ç': _tap(0x32, _shift),
      '¡': _tap(0x2E),
      '¿': _tap(0x2E, _shift),
      '€': _tap(0x22, _altGr),
      '¬': _tap(0x23, _altGr),
    },
    sequences: {
      '`': [_tap(0x2F), _tap(_space)],
      '^': [_tap(0x2F, _shift), _tap(_space)],
      '~': [_tap(0x21, _altGr), _tap(_space)],
    },
  );
  _addCompositions(map, _tap(0x34), _acuteCompositions);
  _addCompositions(map, _tap(0x34, _shift), {
    'ü': 'u',
    'Ü': 'U',
  });
  return map;
}

Map<String, List<KeyboardTap>> _buildGerman() {
  final map = _layout(
    letterUsages: const {'y': 0x1D, 'z': 0x1C},
    direct: {
      '!': _tap(0x1E, _shift),
      '"': _tap(0x1F, _shift),
      '#': _tap(0x32),
      r'$': _tap(0x21, _shift),
      '%': _tap(0x22, _shift),
      '&': _tap(0x23, _shift),
      "'": _tap(0x32, _shift),
      '(': _tap(0x25, _shift),
      ')': _tap(0x26, _shift),
      '*': _tap(0x30, _shift),
      '+': _tap(0x30),
      ',': _tap(0x36),
      '-': _tap(0x38),
      '.': _tap(0x37),
      '/': _tap(0x24, _shift),
      ':': _tap(0x37, _shift),
      ';': _tap(0x36, _shift),
      '<': _tap(0x64),
      '=': _tap(0x27, _shift),
      '>': _tap(0x64, _shift),
      '?': _tap(0x2D, _shift),
      '@': _tap(0x14, _altGr),
      '[': _tap(0x25, _altGr),
      '\\': _tap(0x2D, _altGr),
      ']': _tap(0x26, _altGr),
      '_': _tap(0x38, _shift),
      '{': _tap(0x24, _altGr),
      '|': _tap(0x64, _altGr),
      '}': _tap(0x27, _altGr),
      '~': _tap(0x30, _altGr),
      'ä': _tap(0x34),
      'Ä': _tap(0x34, _shift),
      'ö': _tap(0x33),
      'Ö': _tap(0x33, _shift),
      'ü': _tap(0x2F),
      'Ü': _tap(0x2F, _shift),
      'ß': _tap(0x2D),
      '°': _tap(0x35, _shift),
      '§': _tap(0x20, _shift),
      '²': _tap(0x1F, _altGr),
      '³': _tap(0x20, _altGr),
      '€': _tap(0x08, _altGr),
      'µ': _tap(0x10, _altGr),
    },
    sequences: {
      '`': [_tap(0x2E, _shift), _tap(_space)],
      '^': [_tap(0x35), _tap(_space)],
    },
  );
  _addCompositions(map, _tap(0x2E), _acuteCompositions);
  _addCompositions(map, _tap(0x2E, _shift), _graveCompositions);
  _addCompositions(map, _tap(0x35), _circumflexCompositions);
  return map;
}

Map<String, List<KeyboardTap>> _buildFrench() {
  final map = _layout(
    letterUsages: const {
      'a': 0x14,
      'q': 0x04,
      'z': 0x1A,
      'w': 0x1D,
      'm': 0x33,
    },
    direct: {
      '1': _tap(0x1E, _shift),
      '2': _tap(0x1F, _shift),
      '3': _tap(0x20, _shift),
      '4': _tap(0x21, _shift),
      '5': _tap(0x22, _shift),
      '6': _tap(0x23, _shift),
      '7': _tap(0x24, _shift),
      '8': _tap(0x25, _shift),
      '9': _tap(0x26, _shift),
      '0': _tap(0x27, _shift),
      '!': _tap(0x38),
      '"': _tap(0x20),
      '#': _tap(0x20, _altGr),
      r'$': _tap(0x30),
      '%': _tap(0x34, _shift),
      '&': _tap(0x1E),
      "'": _tap(0x21),
      '(': _tap(0x22),
      ')': _tap(0x2D),
      '*': _tap(0x32),
      '+': _tap(0x2E, _shift),
      ',': _tap(0x10),
      '-': _tap(0x23),
      '.': _tap(0x36, _shift),
      '/': _tap(0x37, _shift),
      ':': _tap(0x37),
      ';': _tap(0x36),
      '<': _tap(0x64),
      '=': _tap(0x2E),
      '>': _tap(0x64, _shift),
      '?': _tap(0x10, _shift),
      '@': _tap(0x27, _altGr),
      '[': _tap(0x22, _altGr),
      '\\': _tap(0x25, _altGr),
      ']': _tap(0x2D, _altGr),
      '_': _tap(0x25),
      '{': _tap(0x21, _altGr),
      '|': _tap(0x23, _altGr),
      '}': _tap(0x2E, _altGr),
      'é': _tap(0x1F),
      'è': _tap(0x24),
      'à': _tap(0x27),
      'ù': _tap(0x34),
      'ç': _tap(0x26),
      '²': _tap(0x35),
      '°': _tap(0x2D, _shift),
      '£': _tap(0x30, _shift),
      'µ': _tap(0x32, _shift),
      '§': _tap(0x38, _shift),
      '€': _tap(0x08, _altGr),
    },
    sequences: {
      '`': [_tap(0x24, _altGr), _tap(_space)],
      '^': [_tap(0x2F), _tap(_space)],
      '~': [_tap(0x1F, _altGr), _tap(_space)],
    },
  );
  _addCompositions(map, _tap(0x2F), _circumflexCompositions);
  _addCompositions(map, _tap(0x2F, _shift), _diaeresisCompositions);
  return map;
}

Map<String, List<KeyboardTap>> _buildItalian() => _layout(
      direct: {
        '!': _tap(0x1E, _shift),
        '"': _tap(0x1F, _shift),
        '#': _tap(0x34, _altGr),
        r'$': _tap(0x21, _shift),
        '%': _tap(0x22, _shift),
        '&': _tap(0x23, _shift),
        "'": _tap(0x2D),
        '(': _tap(0x25, _shift),
        ')': _tap(0x26, _shift),
        '*': _tap(0x30, _shift),
        '+': _tap(0x30),
        ',': _tap(0x36),
        '-': _tap(0x38),
        '.': _tap(0x37),
        '/': _tap(0x24, _shift),
        ':': _tap(0x37, _shift),
        ';': _tap(0x36, _shift),
        '<': _tap(0x64),
        '=': _tap(0x27, _shift),
        '>': _tap(0x64, _shift),
        '?': _tap(0x2D, _shift),
        '@': _tap(0x33, _altGr),
        '[': _tap(0x2F, _altGr),
        '\\': _tap(0x35),
        ']': _tap(0x30, _altGr),
        '^': _tap(0x2E, _shift),
        '_': _tap(0x38, _shift),
        '{': _tap(0x2F, _altGr | _shift),
        '|': _tap(0x35, _shift),
        '}': _tap(0x30, _altGr | _shift),
        '`': _tap(0x2D, _altGr),
        '~': _tap(0x2E, _altGr),
        'à': _tap(0x34),
        'è': _tap(0x2F),
        'é': _tap(0x2F, _shift),
        'ì': _tap(0x2E),
        'ò': _tap(0x33),
        'ù': _tap(0x32),
        'ç': _tap(0x33, _shift),
        '£': _tap(0x20, _shift),
        '°': _tap(0x34, _shift),
        '§': _tap(0x32, _shift),
        '€': _tap(0x08, _altGr),
      },
    );

Map<String, List<KeyboardTap>> _buildPortuguese() {
  final map = _layout(
    direct: {
      '!': _tap(0x1E, _shift),
      '"': _tap(0x1F, _shift),
      '#': _tap(0x20, _shift),
      r'$': _tap(0x21, _shift),
      '%': _tap(0x22, _shift),
      '&': _tap(0x23, _shift),
      "'": _tap(0x2D),
      '(': _tap(0x25, _shift),
      ')': _tap(0x26, _shift),
      '*': _tap(0x2F, _shift),
      '+': _tap(0x2F),
      ',': _tap(0x36),
      '-': _tap(0x38),
      '.': _tap(0x37),
      '/': _tap(0x24, _shift),
      ':': _tap(0x37, _shift),
      ';': _tap(0x36, _shift),
      '<': _tap(0x64),
      '=': _tap(0x27, _shift),
      '>': _tap(0x64, _shift),
      '?': _tap(0x2D, _shift),
      '@': _tap(0x1F, _altGr),
      '[': _tap(0x25, _altGr),
      '\\': _tap(0x35),
      ']': _tap(0x26, _altGr),
      '_': _tap(0x38, _shift),
      '{': _tap(0x24, _altGr),
      '|': _tap(0x35, _shift),
      '}': _tap(0x27, _altGr),
      'ç': _tap(0x33),
      'Ç': _tap(0x33, _shift),
      'º': _tap(0x34),
      'ª': _tap(0x34, _shift),
      '«': _tap(0x2E),
      '»': _tap(0x2E, _shift),
      '£': _tap(0x20, _altGr),
      '§': _tap(0x21, _altGr),
      '€': _tap(0x08, _altGr),
    },
    sequences: {
      '`': [_tap(0x30, _shift), _tap(_space)],
      '^': [_tap(0x32, _shift), _tap(_space)],
      '~': [_tap(0x32), _tap(_space)],
    },
  );
  _addCompositions(map, _tap(0x30), _acuteCompositions);
  _addCompositions(map, _tap(0x30, _shift), _graveCompositions);
  _addCompositions(map, _tap(0x32, _shift), _circumflexCompositions);
  _addCompositions(map, _tap(0x2F, _altGr), _diaeresisCompositions);
  _addCompositions(map, _tap(0x32), const {
    'ã': 'a',
    'õ': 'o',
    'Ã': 'A',
    'Õ': 'O',
  });
  return map;
}

final _layouts = <KeyboardLayout, Map<String, List<KeyboardTap>>>{
  KeyboardLayout.us: _layout(direct: _usPunctuation),
  KeyboardLayout.uk: _buildUk(),
  KeyboardLayout.es: _buildSpanish(),
  KeyboardLayout.de: _buildGerman(),
  KeyboardLayout.fr: _buildFrench(),
  KeyboardLayout.it: _buildItalian(),
  KeyboardLayout.pt: _buildPortuguese(),
};

const _decomposedCharacters = <String, String>{
  'a\u0301': 'á',
  'e\u0301': 'é',
  'i\u0301': 'í',
  'o\u0301': 'ó',
  'u\u0301': 'ú',
  'A\u0301': 'Á',
  'E\u0301': 'É',
  'I\u0301': 'Í',
  'O\u0301': 'Ó',
  'U\u0301': 'Ú',
  'a\u0300': 'à',
  'e\u0300': 'è',
  'i\u0300': 'ì',
  'o\u0300': 'ò',
  'u\u0300': 'ù',
  'A\u0300': 'À',
  'E\u0300': 'È',
  'I\u0300': 'Ì',
  'O\u0300': 'Ò',
  'U\u0300': 'Ù',
  'a\u0302': 'â',
  'e\u0302': 'ê',
  'i\u0302': 'î',
  'o\u0302': 'ô',
  'u\u0302': 'û',
  'A\u0302': 'Â',
  'E\u0302': 'Ê',
  'I\u0302': 'Î',
  'O\u0302': 'Ô',
  'U\u0302': 'Û',
  'a\u0303': 'ã',
  'n\u0303': 'ñ',
  'o\u0303': 'õ',
  'A\u0303': 'Ã',
  'N\u0303': 'Ñ',
  'O\u0303': 'Õ',
  'a\u0308': 'ä',
  'e\u0308': 'ë',
  'i\u0308': 'ï',
  'o\u0308': 'ö',
  'u\u0308': 'ü',
  'A\u0308': 'Ä',
  'E\u0308': 'Ë',
  'I\u0308': 'Ï',
  'O\u0308': 'Ö',
  'U\u0308': 'Ü',
  'c\u0327': 'ç',
  'C\u0327': 'Ç',
};

String normalizeKeyboardText(String text) {
  var normalized = text;
  for (final entry in _decomposedCharacters.entries) {
    normalized = normalized.replaceAll(entry.key, entry.value);
  }
  return normalized;
}

List<KeyboardTap>? keyboardCharacterToTaps(
  String character,
  KeyboardLayout layout,
) =>
    _layouts[layout]![character];

KeyboardTap? keyboardLogicalKeyTap(
  String character,
  KeyboardLayout layout,
) {
  final lookup = RegExp(r'^[A-Z]$').hasMatch(character)
      ? character.toLowerCase()
      : character;
  final taps = _layouts[layout]![lookup];
  return taps == null || taps.isEmpty ? null : taps.first;
}

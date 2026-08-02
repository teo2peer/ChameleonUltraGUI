import 'dart:convert';
import 'dart:typed_data';

import 'package:chameleonultragui/helpers/definitions.dart';
import 'package:chameleonultragui/helpers/saved_keyboard_script.dart';
import 'package:chameleonultragui/sharedprefsprovider.dart';
import 'package:flutter/material.dart';

/// Defensive limits for imported sync data.
abstract final class SyncLimits {
  static const int maxEncodedBytes = 16 * 1024 * 1024;
  static const int maxCards = 1024;
  static const int maxCardBlocks = 8192;
  static const int maxDictionaries = 256;
  static const int maxDictionaryKeys = 100000;
  static const int maxScripts = savedKeyboardScriptLimit;
  static const int maxSettings = 256;
  static const int maxSettingDepth = 8;
  static const int maxSettingStringBytes = 16 * 1024;
}

class SyncState {
  final SyncSnapshot snapshot;
  final SyncCheckpoint checkpoint;

  const SyncState({required this.snapshot, required this.checkpoint});

  factory SyncState.fromJsonMap(Object? value) {
    final root = _stringMap(value, 'sync state');
    _requireKeys(root, const {
      'version',
      'snapshot',
      'checkpoint',
    }, 'sync state');
    if (root['version'] != 2) {
      throw const FormatException('Unsupported peer sync protocol version');
    }
    return SyncState(
      snapshot: SyncSnapshot.fromJson(jsonEncode(root['snapshot'])),
      checkpoint: SyncCheckpoint.fromJson(root['checkpoint']),
    );
  }

  Map<String, Object> toJsonMap() => {
    'version': 2,
    'snapshot': snapshot.toJsonMap(),
    'checkpoint': checkpoint.toJson(),
  };
}

class SyncSnapshot {
  static const int currentVersion = 3;

  final int version;
  final List<CardSave> cards;
  final List<Dictionary> dictionaries;
  final List<SavedKeyboardScript> keyboardScripts;
  final Map<String, Object> settings;

  factory SyncSnapshot({
    int version = currentVersion,
    Iterable<CardSave> cards = const [],
    Iterable<Dictionary> dictionaries = const [],
    Iterable<SavedKeyboardScript> keyboardScripts = const [],
    Map<String, Object> settings = const {},
  }) {
    final snapshot = SyncSnapshot._(
      version: version,
      cards: List.unmodifiable(cards.map(_copyCard)),
      dictionaries: List.unmodifiable(dictionaries.map(_copyDictionary)),
      keyboardScripts: List.unmodifiable(keyboardScripts.map(_copyScript)),
      settings: Map.unmodifiable(_copySettings(settings)),
    );
    snapshot._validate();
    return snapshot;
  }

  const SyncSnapshot._({
    required this.version,
    required this.cards,
    required this.dictionaries,
    required this.keyboardScripts,
    required this.settings,
  });

  factory SyncSnapshot.fromJson(String encoded) {
    if (utf8.encode(encoded).length > SyncLimits.maxEncodedBytes) {
      throw const FormatException('Sync snapshot exceeds the size limit');
    }

    final Object? decoded;
    try {
      decoded = jsonDecode(encoded);
    } on FormatException {
      throw const FormatException('Invalid sync snapshot JSON');
    }
    final root = _stringMap(decoded, 'snapshot');
    _requireKeys(root, const {
      'version',
      'cards',
      'dictionaries',
      'keyboardScripts',
      'settings',
    }, 'snapshot');
    final encodedVersion = root['version'];
    if (encodedVersion is! int ||
        encodedVersion < 1 ||
        encodedVersion > currentVersion) {
      throw const FormatException('Unsupported sync snapshot version');
    }

    final cardData = _list(root['cards'], 'cards');
    final dictionaryData = _list(root['dictionaries'], 'dictionaries');
    final scriptData = _list(root['keyboardScripts'], 'keyboardScripts');
    final settingData = _stringMap(root['settings'], 'settings');

    try {
      final settings = _decodeSettings(settingData);
      if (encodedVersion < 3 &&
          !settings.containsKey('hf_capture_retention_days')) {
        settings['hf_capture_retention_days'] = 30;
      }
      return SyncSnapshot(
        cards: cardData.map(_decodeCard),
        dictionaries: dictionaryData.map(_decodeDictionary),
        keyboardScripts: scriptData.map(_decodeScript),
        settings: settings,
      );
    } on FormatException {
      rethrow;
    } catch (_) {
      throw const FormatException('Invalid sync snapshot data');
    }
  }

  Map<String, Object> toJsonMap() => {
    'version': version,
    'cards': cards.map((card) => jsonDecode(card.toJson())).toList(),
    'dictionaries': dictionaries
        .map((dictionary) => jsonDecode(dictionary.toJson()))
        .toList(),
    'keyboardScripts': keyboardScripts
        .map((script) => jsonDecode(script.toJson()))
        .toList(),
    'settings': _copySettings(settings),
  };

  String toJson() {
    final encoded = jsonEncode(toJsonMap());
    if (utf8.encode(encoded).length > SyncLimits.maxEncodedBytes) {
      throw const FormatException('Sync snapshot exceeds the size limit');
    }
    return encoded;
  }

  void _validate() {
    if (version != currentVersion) {
      throw const FormatException('Unsupported sync snapshot version');
    }
    if (cards.length > SyncLimits.maxCards) {
      throw const FormatException('Too many cards in sync snapshot');
    }
    if (dictionaries.length > SyncLimits.maxDictionaries) {
      throw const FormatException('Too many dictionaries in sync snapshot');
    }
    if (keyboardScripts.length > SyncLimits.maxScripts) {
      throw const FormatException('Too many scripts in sync snapshot');
    }
    if (settings.length > SyncLimits.maxSettings) {
      throw const FormatException('Too many settings in sync snapshot');
    }
    if (cards.fold<int>(0, (count, card) => count + card.data.length) >
        SyncLimits.maxCardBlocks) {
      throw const FormatException('Too many card blocks in sync snapshot');
    }
    if (dictionaries.fold<int>(
          0,
          (count, dictionary) => count + dictionary.keys.length,
        ) >
        SyncLimits.maxDictionaryKeys) {
      throw const FormatException('Too many dictionary keys in sync snapshot');
    }
    _ensureUniqueIds(cards.map((card) => card.id), 'card');
    _ensureUniqueIds(
      dictionaries.map((dictionary) => dictionary.id),
      'dictionary',
    );
    _ensureUniqueIds(keyboardScripts.map((script) => script.id), 'script');
    for (final card in cards) {
      _validateCardSemantics(card);
    }
    for (final dictionary in dictionaries) {
      _validateDictionarySemantics(dictionary);
    }
    _validateSettingValue(settings, 0);
    if (utf8.encode(jsonEncode(toJsonMap())).length >
        SyncLimits.maxEncodedBytes) {
      throw const FormatException('Sync snapshot exceeds the size limit');
    }
  }
}

enum SyncChoice { local, remote }

enum ScriptChoice { local, remote, keepBoth }

class CardConflict {
  final String id;
  final CardSave local;
  final CardSave remote;
  final List<int> differingBlocks;
  final Map<int, SyncChoice> blockSelections;
  SyncChoice metadataSelection;

  CardConflict._(this.local, this.remote)
    : id = local.id,
      differingBlocks = List.unmodifiable(_differingBlocks(local, remote)),
      blockSelections = {
        for (final index in _differingBlocks(local, remote))
          index: index < local.data.length
              ? SyncChoice.local
              : SyncChoice.remote,
      },
      metadataSelection = SyncChoice.local;

  bool isBlockAvailable(int index, SyncChoice choice) {
    final blocks = choice == SyncChoice.local ? local.data : remote.data;
    return index >= 0 && index < blocks.length;
  }

  CardSave resolve({
    Map<int, SyncChoice> blockOverrides = const {},
    SyncChoice? metadataOverride,
  }) {
    final metadata = metadataOverride ?? metadataSelection;
    final selected = metadata == SyncChoice.local ? local : remote;
    final localMap = _modelMap(local.toJson());
    final remoteMap = _modelMap(remote.toJson());
    final result = Map<String, dynamic>.from(
      metadata == SyncChoice.local ? localMap : remoteMap,
    );
    final localBlocks = localMap['data']! as List<dynamic>;
    final remoteBlocks = remoteMap['data']! as List<dynamic>;
    final blocks = <Object>[];
    final count = localBlocks.length > remoteBlocks.length
        ? localBlocks.length
        : remoteBlocks.length;
    for (var index = 0; index < count; index++) {
      final choice =
          blockOverrides[index] ?? blockSelections[index] ?? SyncChoice.local;
      final source = choice == SyncChoice.local ? localBlocks : remoteBlocks;
      if (index >= source.length) {
        throw FormatException(
          'Selected ${choice.name} card has no block $index',
        );
      }
      blocks.add(source[index] as Object);
    }
    result['id'] = id;
    result['data'] = blocks;
    result['name'] = selected.name;
    return CardSave.fromJson(jsonEncode(result));
  }
}

class ScriptConflict {
  final String id;
  final SavedKeyboardScript local;
  final SavedKeyboardScript remote;
  ScriptChoice selection;

  ScriptConflict._(this.local, this.remote)
    : id = local.id,
      selection = ScriptChoice.local;
}

class SettingConflict {
  final String key;
  final Object local;
  final Object remote;
  SyncChoice selection;

  SettingConflict._(this.key, this.local, this.remote)
    : selection = SyncChoice.local;
}

/// Optional immutable-by-convention overrides for UI state or persistence.
class SyncResolution {
  final Map<String, Map<int, SyncChoice>> cardBlocks;
  final Map<String, SyncChoice> cardMetadata;
  final Map<String, ScriptChoice> scripts;
  final Map<String, SyncChoice> settings;

  const SyncResolution({
    this.cardBlocks = const {},
    this.cardMetadata = const {},
    this.scripts = const {},
    this.settings = const {},
  });
}

class SyncMergePlan {
  final List<CardSave> cards;
  final List<Dictionary> dictionaries;
  final List<SavedKeyboardScript> keyboardScripts;
  final Map<String, Object> settings;
  final List<CardConflict> cardConflicts;
  final List<ScriptConflict> scriptConflicts;
  final List<SettingConflict> settingConflicts;

  SyncMergePlan._({
    required this.cards,
    required this.dictionaries,
    required this.keyboardScripts,
    required this.settings,
    required this.cardConflicts,
    required this.scriptConflicts,
    required this.settingConflicts,
  });

  factory SyncMergePlan.merge(SyncSnapshot local, SyncSnapshot remote) {
    final cardResult = <CardSave>[];
    final cardFingerprints = <String>{};
    final cardConflicts = <CardConflict>[];
    final remoteCards = {for (final card in remote.cards) card.id: card};
    final handledCardIds = <String>{};
    for (final card in local.cards) {
      final other = remoteCards[card.id];
      if (other != null) {
        _ensureCompatibleCardGeometry(card, other);
        handledCardIds.add(card.id);
        if (_cardFingerprint(card, includeId: true) !=
            _cardFingerprint(other, includeId: true)) {
          cardConflicts.add(CardConflict._(card, other));
          continue;
        }
      }
      _addUniqueCard(cardResult, cardFingerprints, card);
    }
    for (final card in remote.cards) {
      if (!handledCardIds.contains(card.id)) {
        _addUniqueCard(cardResult, cardFingerprints, card);
      }
    }

    final scriptResult = <SavedKeyboardScript>[];
    final scriptConflicts = <ScriptConflict>[];
    final remoteScripts = {
      for (final script in remote.keyboardScripts) script.id: script,
    };
    final handledScriptIds = <String>{};
    for (final script in local.keyboardScripts) {
      final other = remoteScripts[script.id];
      if (other != null) {
        handledScriptIds.add(script.id);
        if (_scriptFingerprint(script, includeId: true) !=
            _scriptFingerprint(other, includeId: true)) {
          scriptConflicts.add(ScriptConflict._(script, other));
          continue;
        }
      }
      scriptResult.add(_copyScript(script));
    }
    for (final script in remote.keyboardScripts) {
      if (!handledScriptIds.contains(script.id)) {
        scriptResult.add(_copyScript(script));
      }
    }

    final settingResult = <String, Object>{};
    final settingConflicts = <SettingConflict>[];
    for (final entry in local.settings.entries) {
      if (remote.settings.containsKey(entry.key) &&
          !_jsonEqual(entry.value, remote.settings[entry.key])) {
        settingConflicts.add(
          SettingConflict._(
            entry.key,
            entry.value,
            remote.settings[entry.key]!,
          ),
        );
      } else {
        settingResult[entry.key] = _copySettingValue(entry.value);
      }
    }
    for (final entry in remote.settings.entries) {
      if (!local.settings.containsKey(entry.key)) {
        settingResult[entry.key] = _copySettingValue(entry.value);
      }
    }

    final extractedKeys = _extractConflictCardKeys(cardConflicts);
    final dictionaries = <Dictionary>[
      ...local.dictionaries,
      ...remote.dictionaries,
      if (extractedKeys.isNotEmpty)
        Dictionary(
          id: 'sync-card-keys',
          name: 'Synced card keys',
          keys: extractedKeys,
          color: Colors.deepOrange,
          keyLength: 12,
        ),
    ];

    final plan = SyncMergePlan._(
      cards: List.unmodifiable(cardResult),
      dictionaries: List.unmodifiable(_mergeDictionaries(dictionaries)),
      keyboardScripts: List.unmodifiable(scriptResult),
      settings: Map.unmodifiable(settingResult),
      cardConflicts: cardConflicts,
      scriptConflicts: scriptConflicts,
      settingConflicts: settingConflicts,
    );
    plan._validateWorstCaseResolution();
    return plan;
  }

  SyncSnapshot resolve([SyncResolution resolution = const SyncResolution()]) {
    final resolvedCards = cards.map(_copyCard).toList();
    final cardFingerprints = resolvedCards
        .map((card) => _cardFingerprint(card, includeId: false))
        .toSet();
    for (final conflict in cardConflicts) {
      _addUniqueCard(
        resolvedCards,
        cardFingerprints,
        conflict.resolve(
          blockOverrides: resolution.cardBlocks[conflict.id] ?? const {},
          metadataOverride: resolution.cardMetadata[conflict.id],
        ),
      );
    }

    final resolvedScripts = keyboardScripts.map(_copyScript).toList();
    final usedScriptIds = resolvedScripts.map((script) => script.id).toSet();
    final usedScriptNames = resolvedScripts
        .map((script) => script.name.toLowerCase())
        .toSet();
    for (final conflict in scriptConflicts) {
      usedScriptIds
        ..add(conflict.local.id)
        ..add(conflict.remote.id);
      usedScriptNames
        ..add(conflict.local.name.toLowerCase())
        ..add(conflict.remote.name.toLowerCase());
    }
    for (final conflict in scriptConflicts) {
      final choice = resolution.scripts[conflict.id] ?? conflict.selection;
      if (choice == ScriptChoice.local || choice == ScriptChoice.keepBoth) {
        resolvedScripts.add(_copyScript(conflict.local));
        usedScriptIds.add(conflict.local.id);
        usedScriptNames.add(conflict.local.name.toLowerCase());
      }
      if (choice == ScriptChoice.remote) {
        resolvedScripts.add(_copyScript(conflict.remote));
        usedScriptIds.add(conflict.remote.id);
        usedScriptNames.add(conflict.remote.name.toLowerCase());
      } else if (choice == ScriptChoice.keepBoth) {
        final id = _uniqueValue('${conflict.remote.id}-remote', usedScriptIds);
        final name = _uniqueScriptName(conflict.remote.name, usedScriptNames);
        resolvedScripts.add(
          _recreateScript(conflict.remote, id: id, name: name),
        );
      }
    }

    final resolvedSettings = _copySettings(settings);
    for (final conflict in settingConflicts) {
      final choice = resolution.settings[conflict.key] ?? conflict.selection;
      resolvedSettings[conflict.key] = _copySettingValue(
        choice == SyncChoice.local ? conflict.local : conflict.remote,
      );
    }

    return SyncSnapshot(
      cards: resolvedCards,
      dictionaries: dictionaries,
      keyboardScripts: resolvedScripts,
      settings: resolvedSettings,
    );
  }

  void _validateWorstCaseResolution() {
    resolve(
      SyncResolution(
        scripts: {
          for (final conflict in scriptConflicts)
            conflict.id: ScriptChoice.keepBoth,
        },
      ),
    );
  }
}

List<Uint8List> _extractConflictCardKeys(List<CardConflict> conflicts) {
  final keys = <String, Uint8List>{};
  for (final conflict in conflicts) {
    for (final card in [conflict.local, conflict.remote]) {
      if (!_isMifareClassic(card.tag)) continue;
      for (var index = 0; index < card.data.length; index++) {
        final block = card.data[index];
        if (!_isSectorTrailer(card.tag, index) || block.length != 16) continue;
        for (final key in [block.sublist(0, 6), block.sublist(10, 16)]) {
          keys.putIfAbsent(base64Encode(key), () => Uint8List.fromList(key));
        }
      }
    }
  }
  return keys.values.toList(growable: false);
}

bool _isMifareClassic(TagType tag) =>
    tag == TagType.mifareMini ||
    tag == TagType.mifare1K ||
    tag == TagType.mifare2K ||
    tag == TagType.mifare4K;

bool _isSectorTrailer(TagType tag, int block) {
  if (tag == TagType.mifare4K && block >= 128) {
    return (block - 128) % 16 == 15;
  }
  return block % 4 == 3;
}

CardSave _decodeCard(Object? value) {
  final map = _stringMap(value, 'card');
  _requireKeys(map, const {
    'id',
    'uid',
    'sak',
    'atqa',
    'ats',
    'name',
    'tag',
    'color',
    'data',
    'extra',
  }, 'card');
  if (map['id'] is! String ||
      (map['id']! as String).isEmpty ||
      map['uid'] is! String ||
      map['sak'] is! int ||
      map['name'] is! String ||
      map['tag'] is! int ||
      map['color'] is! String) {
    throw const FormatException('Invalid card metadata');
  }
  _byteList(map['atqa'], 'card atqa');
  _byteList(map['ats'], 'card ats');
  for (final block in _list(map['data'], 'card data')) {
    _byteList(block, 'card block');
  }
  final extra = _stringMap(map['extra'], 'card extra');
  if (extra.keys.any(
    (key) => !const {
      'ultralightSignature',
      'ultralightVersion',
      'ultralightCounters',
    }.contains(key),
  )) {
    throw const FormatException('Invalid card extra metadata');
  }
  if (extra['ultralightSignature'] case final signature?) {
    _byteList(signature, 'Ultralight signature');
  }
  if (extra['ultralightVersion'] case final version?) {
    _byteList(version, 'Ultralight version');
  }
  if (extra['ultralightCounters'] case final counters?) {
    final values = _list(counters, 'Ultralight counters');
    if (values.any(
      (counter) => counter is! int || counter < 0 || counter > 0xffffff,
    )) {
      throw const FormatException('Invalid Ultralight counter');
    }
  }
  return CardSave.fromJson(jsonEncode(map));
}

Dictionary _decodeDictionary(Object? value) {
  final map = _stringMap(value, 'dictionary');
  _requireKeys(map, const {
    'id',
    'name',
    'color',
    'keys',
    'keyLength',
  }, 'dictionary');
  if (map['id'] is! String ||
      (map['id']! as String).isEmpty ||
      map['name'] is! String ||
      map['color'] is! String ||
      map['keyLength'] is! int ||
      (map['keyLength']! as int) < 0) {
    throw const FormatException('Invalid dictionary metadata');
  }
  for (final key in _list(map['keys'], 'dictionary keys')) {
    _byteList(key, 'dictionary key');
  }
  return Dictionary.fromJson(jsonEncode(map));
}

SavedKeyboardScript _decodeScript(Object? value) {
  final map = _stringMap(value, 'keyboard script');
  _requireKeys(map, const {
    'formatVersion',
    'compilerVersion',
    'id',
    'name',
    'source',
    'layout',
    'output',
    'program',
    'updatedAt',
  }, 'keyboard script');
  return SavedKeyboardScript.fromJson(jsonEncode(map));
}

Map<String, Object> _decodeSettings(Map<String, dynamic> source) {
  final result = <String, Object>{};
  for (final entry in source.entries) {
    if (entry.key.isEmpty || entry.value == null) {
      throw const FormatException('Invalid safe setting');
    }
    _validateSettingValue(entry.value, 1);
    result[entry.key] = _copySettingValue(entry.value as Object);
  }
  return result;
}

void _validateSettingValue(Object? value, int depth) {
  if (depth > SyncLimits.maxSettingDepth) {
    throw const FormatException('Safe setting nesting is too deep');
  }
  if (value is String) {
    if (utf8.encode(value).length > SyncLimits.maxSettingStringBytes) {
      throw const FormatException('Safe setting string is too long');
    }
    return;
  }
  if (value is bool || value is int) return;
  if (value is double) {
    if (!value.isFinite) {
      throw const FormatException('Safe setting number must be finite');
    }
    return;
  }
  if (value is List) {
    for (final item in value) {
      if (item == null) {
        throw const FormatException('Safe settings cannot contain null');
      }
      _validateSettingValue(item, depth + 1);
    }
    return;
  }
  if (value is Map) {
    for (final entry in value.entries) {
      if (entry.key is! String ||
          (entry.key as String).isEmpty ||
          entry.value == null) {
        throw const FormatException('Invalid safe setting map');
      }
      _validateSettingValue(entry.value, depth + 1);
    }
    return;
  }
  throw const FormatException('Unsupported safe setting value');
}

Object _copySettingValue(Object value) {
  if (value is List) {
    return List<Object>.unmodifiable(
      value.map((item) => _copySettingValue(item as Object)),
    );
  }
  if (value is Map) {
    return Map<String, Object>.unmodifiable({
      for (final entry in value.entries)
        entry.key as String: _copySettingValue(entry.value as Object),
    });
  }
  return value;
}

Map<String, Object> _copySettings(Map<String, Object> settings) => {
  for (final entry in settings.entries)
    entry.key: _copySettingValue(entry.value),
};

List<Dictionary> _mergeDictionaries(List<Dictionary> dictionaries) {
  final parent = List<int>.generate(dictionaries.length, (index) => index);
  int root(int index) {
    while (parent[index] != index) {
      parent[index] = parent[parent[index]];
      index = parent[index];
    }
    return index;
  }

  for (var left = 0; left < dictionaries.length; left++) {
    for (var right = left + 1; right < dictionaries.length; right++) {
      final a = dictionaries[left];
      final b = dictionaries[right];
      if (a.id == b.id && a.keyLength != b.keyLength) {
        throw FormatException(
          'Dictionary ${a.id} has incompatible key lengths',
        );
      }
      if (a.id == b.id ||
          (a.name.trim().toLowerCase() == b.name.trim().toLowerCase() &&
              a.keyLength == b.keyLength)) {
        parent[root(right)] = root(left);
      }
    }
  }

  final groups = <int, List<Dictionary>>{};
  for (var index = 0; index < dictionaries.length; index++) {
    groups.putIfAbsent(root(index), () => []).add(dictionaries[index]);
  }
  return groups.values.map((group) {
    final base = _modelMap(group.first.toJson());
    final keys = <String, List<int>>{};
    for (final dictionary in group) {
      for (final key in dictionary.keys) {
        keys.putIfAbsent(base64Encode(key), key.toList);
      }
    }
    base['keys'] = keys.values.toList();
    return Dictionary.fromJson(jsonEncode(base));
  }).toList();
}

void _addUniqueCard(
  List<CardSave> cards,
  Set<String> fingerprints,
  CardSave candidate,
) {
  final fingerprint = _cardFingerprint(candidate, includeId: false);
  if (fingerprints.add(fingerprint)) {
    cards.add(_copyCard(candidate));
  }
}

void _ensureCompatibleCardGeometry(CardSave local, CardSave remote) {
  if (local.tag != remote.tag ||
      _normalizedUid(local.uid) != _normalizedUid(remote.uid)) {
    throw FormatException('Card ${local.id} has incompatible identity');
  }
  final commonBlocks = local.data.length < remote.data.length
      ? local.data.length
      : remote.data.length;
  for (var index = 0; index < commonBlocks; index++) {
    if (local.data[index].isNotEmpty &&
        remote.data[index].isNotEmpty &&
        local.data[index].length != remote.data[index].length) {
      throw FormatException('Card ${local.id} has incompatible block geometry');
    }
  }
}

void _validateCardSemantics(CardSave card) {
  validateCardSaveSemantics(card);
}

String _normalizedUid(String value) =>
    value.replaceAll(RegExp(r'\s+'), '').toUpperCase();

void _validateDictionarySemantics(Dictionary dictionary) {
  if (!const {0, 8, 12, 32}.contains(dictionary.keyLength) ||
      (dictionary.keys.isNotEmpty && dictionary.keyLength == 0) ||
      dictionary.keys.any((key) => key.length * 2 != dictionary.keyLength)) {
    throw const FormatException('Invalid dictionary key length');
  }
}

List<int> _differingBlocks(CardSave local, CardSave remote) {
  final result = <int>[];
  final count = local.data.length > remote.data.length
      ? local.data.length
      : remote.data.length;
  for (var index = 0; index < count; index++) {
    if (index >= local.data.length ||
        index >= remote.data.length ||
        base64Encode(local.data[index]) != base64Encode(remote.data[index])) {
      result.add(index);
    }
  }
  return result;
}

String _cardFingerprint(CardSave card, {required bool includeId}) {
  final map = _modelMap(card.toJson());
  if (!includeId) map.remove('id');
  return jsonEncode(map);
}

String _scriptFingerprint(
  SavedKeyboardScript script, {
  required bool includeId,
}) {
  final map = _modelMap(script.toJson());
  if (!includeId) map.remove('id');
  return jsonEncode(map);
}

CardSave _copyCard(CardSave card) => CardSave.fromJson(card.toJson());

Dictionary _copyDictionary(Dictionary dictionary) =>
    Dictionary.fromJson(dictionary.toJson());

SavedKeyboardScript _copyScript(SavedKeyboardScript script) =>
    SavedKeyboardScript.fromJson(script.toJson());

SavedKeyboardScript _recreateScript(
  SavedKeyboardScript script, {
  required String id,
  required String name,
}) => SavedKeyboardScript.compile(
  id: id,
  name: name,
  source: script.source,
  layout: script.layout,
  output: script.output,
  updatedAt: script.updatedAt,
);

String _uniqueScriptName(String original, Set<String> used) {
  var suffix = ' (remote)';
  var number = 2;
  while (true) {
    final available = savedKeyboardScriptNameLimit - suffix.length;
    final base = original.length > available
        ? original.substring(0, available).trimRight()
        : original;
    final candidate = '$base$suffix';
    if (used.add(candidate.toLowerCase())) return candidate;
    suffix = ' (remote $number)';
    number++;
  }
}

String _uniqueValue(String preferred, Set<String> used) {
  var candidate = preferred;
  var number = 2;
  while (!used.add(candidate)) {
    candidate = '$preferred-$number';
    number++;
  }
  return candidate;
}

bool _jsonEqual(Object? left, Object? right) {
  if (left.runtimeType != right.runtimeType) return false;
  if (left is List && right is List) {
    if (left.length != right.length) return false;
    for (var index = 0; index < left.length; index++) {
      if (!_jsonEqual(left[index], right[index])) return false;
    }
    return true;
  }
  if (left is Map && right is Map) {
    if (left.length != right.length) return false;
    for (final entry in left.entries) {
      if (!right.containsKey(entry.key) ||
          !_jsonEqual(entry.value, right[entry.key])) {
        return false;
      }
    }
    return true;
  }
  return left == right;
}

Map<String, dynamic> _modelMap(String encoded) =>
    Map<String, dynamic>.from(jsonDecode(encoded) as Map);

Map<String, dynamic> _stringMap(Object? value, String label) {
  if (value is! Map) throw FormatException('$label must be an object');
  final result = <String, dynamic>{};
  for (final entry in value.entries) {
    if (entry.key is! String) {
      throw FormatException('$label keys must be strings');
    }
    result[entry.key as String] = entry.value;
  }
  return result;
}

List<dynamic> _list(Object? value, String label) {
  if (value is! List) throw FormatException('$label must be a list');
  return value;
}

void _byteList(Object? value, String label) {
  final bytes = _list(value, label);
  if (bytes.any((byte) => byte is! int || byte < 0 || byte > 255)) {
    throw FormatException('$label must contain bytes');
  }
}

void _requireKeys(Map<String, dynamic> value, Set<String> keys, String label) {
  if (value.keys.toSet().length != keys.length ||
      !value.keys.toSet().containsAll(keys)) {
    throw FormatException('$label has missing or unknown fields');
  }
}

void _ensureUniqueIds(Iterable<String> ids, String label) {
  final seen = <String>{};
  for (final id in ids) {
    if (id.isEmpty || !seen.add(id)) {
      throw FormatException('Invalid or duplicate $label ID');
    }
  }
}

import 'dart:async';
import 'dart:convert';

import 'package:chameleonultragui/helpers/colors.dart' as colors;
import 'package:chameleonultragui/helpers/definitions.dart';
import 'package:chameleonultragui/helpers/emulation_change.dart';
import 'package:chameleonultragui/helpers/general.dart';
import 'package:chameleonultragui/helpers/saved_keyboard_script.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

// Localizations
import 'package:chameleonultragui/generated/i18n/app_localizations.dart';

const int _legacySettingsFormatVersion = 1;
const int _legacySettingsMaxEncodedBytes = 16 * 1024;
const Set<String> _legacyBooleanSettingKeys = {
  'confirm_delete',
  'auto_scan_enabled',
  'auto_connect_first_found',
  'device_found_banner',
  'sidebar_auto_expanded',
  'emulation_change_monitoring',
};
const Set<String> _legacyScalarSettingKeys = {
  ..._legacyBooleanSettingKeys,
  'app_theme',
  'app_theme_color',
  'locale',
  'sidebar_expanded_index',
};

const String dataSyncMetaPreferenceKey = 'data_sync_meta_v1';
const String dataSyncTransactionManifestPreferenceKey =
    'data_sync_tx_manifest_v1';
const String dataSyncTransactionStagePrefix = 'data_sync_tx_stage_v1_';
const String dataSyncCoordinatorPreferenceKey = 'data_sync_coordinator_v1';
const String dataSyncTransactionReceiptsPreferenceKey =
    'data_sync_tx_receipts_v1';
const String dataSyncDeferredMutationsPreferenceKey =
    'data_sync_deferred_mutations_v1';
const String _mifareClassicNonceHistoryEnabledPreferenceKey =
    'mifare_classic_nonce_history_enabled_v1';
const String _mifareClassicNonceHistoryPreferenceKey =
    'mifare_classic_nonce_history_v1';
const int _dataSyncTransactionVersion = 2;
const List<String> dataSyncStoredPreferenceKeys = [
  'cards',
  'dictionaries',
  'keyboard_scripts',
  'app_theme',
  'app_theme_color',
  'locale',
  'confirm_delete',
  'auto_scan_enabled',
  'auto_connect_first_found',
  'device_found_banner',
  'sidebar_auto_expanded',
  'sidebar_expanded_index',
  'emulation_change_monitoring',
];

class MifareClassicNonceHistorySummary {
  const MifareClassicNonceHistorySummary({
    required this.cardUid,
    required this.sampleCount,
    required this.byteSize,
  });

  final String cardUid;
  final int sampleCount;
  final int byteSize;
}

class SyncCheckpoint {
  final int revision;
  final String stateHash;

  const SyncCheckpoint({required this.revision, required this.stateHash});

  factory SyncCheckpoint.fromJson(Object? value) {
    if (value is! Map) {
      throw const FormatException('Invalid data sync checkpoint');
    }
    final revision = value['revision'];
    final stateHash = value['stateHash'];
    if (value.length != 2 ||
        revision is! int ||
        revision < 0 ||
        stateHash is! String ||
        !_isSha256(stateHash)) {
      throw const FormatException('Invalid data sync checkpoint');
    }
    return SyncCheckpoint(revision: revision, stateHash: stateHash);
  }

  Map<String, Object> toJson() => {
    'revision': revision,
    'stateHash': stateHash,
  };

  @override
  bool operator ==(Object other) =>
      other is SyncCheckpoint &&
      revision == other.revision &&
      stateHash == other.stateHash;

  @override
  int get hashCode => Object.hash(revision, stateHash);

  @override
  String toString() => 'SyncCheckpoint($revision, $stateHash)';
}

enum SyncTransactionOutcome { prepared, committed, aborted }

enum SyncTransactionRole { local, participant, coordinator }

enum SyncCoordinatorDecision { prepared, commitDecided, abortDecided }

class SyncCoordinatorRecovery {
  final String transactionId;
  final String targetHash;
  final SyncCoordinatorDecision decision;
  final SyncCheckpoint peerCheckpoint;

  const SyncCoordinatorRecovery({
    required this.transactionId,
    required this.targetHash,
    required this.decision,
    required this.peerCheckpoint,
  });

  factory SyncCoordinatorRecovery.fromJson(Object? value) {
    if (value is! Map || value.length != 6) {
      throw const FormatException('Invalid data sync coordinator record');
    }
    final version = value['version'];
    final role = value['role'];
    final transactionId = value['transactionId'];
    final targetHash = value['targetHash'];
    final decisionName = value['decision'];
    SyncCoordinatorDecision? decision;
    for (final candidate in SyncCoordinatorDecision.values) {
      if (candidate.name == decisionName) decision = candidate;
    }
    if (version != 1 ||
        role != SyncTransactionRole.coordinator.name ||
        transactionId is! String ||
        transactionId.isEmpty ||
        targetHash is! String ||
        !_isSha256(targetHash) ||
        decision == null) {
      throw const FormatException('Invalid data sync coordinator record');
    }
    return SyncCoordinatorRecovery(
      transactionId: transactionId,
      targetHash: targetHash,
      decision: decision,
      peerCheckpoint: SyncCheckpoint.fromJson(value['peerCheckpoint']),
    );
  }

  SyncCoordinatorRecovery withDecision(SyncCoordinatorDecision value) =>
      SyncCoordinatorRecovery(
        transactionId: transactionId,
        targetHash: targetHash,
        decision: value,
        peerCheckpoint: peerCheckpoint,
      );

  Map<String, Object> toJson() => {
    'version': 1,
    'role': SyncTransactionRole.coordinator.name,
    'transactionId': transactionId,
    'targetHash': targetHash,
    'decision': decision.name,
    'peerCheckpoint': peerCheckpoint.toJson(),
  };
}

class SyncTransactionReceipt {
  final String transactionId;
  final SyncTransactionOutcome outcome;
  final String targetHash;
  final SyncCheckpoint checkpoint;

  const SyncTransactionReceipt({
    required this.transactionId,
    required this.outcome,
    required this.targetHash,
    required this.checkpoint,
  });

  factory SyncTransactionReceipt.fromJson(Object? value) {
    if (value is! Map) {
      throw const FormatException('Invalid data sync transaction receipt');
    }
    final transactionId = value['transactionId'];
    final outcomeName = value['outcome'];
    final targetHash = value['targetHash'];
    if (value.length != 4 ||
        transactionId is! String ||
        transactionId.isEmpty ||
        outcomeName is! String ||
        targetHash is! String ||
        !_isSha256(targetHash)) {
      throw const FormatException('Invalid data sync transaction receipt');
    }
    SyncTransactionOutcome? outcome;
    for (final candidate in SyncTransactionOutcome.values) {
      if (candidate.name == outcomeName) outcome = candidate;
    }
    if (outcome == null) {
      throw const FormatException('Invalid data sync transaction outcome');
    }
    return SyncTransactionReceipt(
      transactionId: transactionId,
      outcome: outcome,
      targetHash: targetHash,
      checkpoint: SyncCheckpoint.fromJson(value['checkpoint']),
    );
  }

  Map<String, Object> toJson() => {
    'transactionId': transactionId,
    'outcome': outcome.name,
    'targetHash': targetHash,
    'checkpoint': checkpoint.toJson(),
  };
}

class SyncCheckpointConflict implements Exception {
  final SyncCheckpoint expected;
  final SyncCheckpoint actual;

  const SyncCheckpointConflict(this.expected, this.actual);

  @override
  String toString() =>
      'Data sync state changed (expected $expected, found $actual)';
}

class SyncPersistenceException implements Exception {
  final String operation;
  final String key;

  const SyncPersistenceException(this.operation, this.key);

  @override
  String toString() => 'SharedPreferences $operation failed for $key';
}

typedef DataSyncWriteInterceptor =
    FutureOr<bool> Function(String operation, String key, Object? value);

class _DeferredMutationJournal {
  final String transactionId;
  final int nextSequence;
  final List<Map<String, Object>> operations;

  const _DeferredMutationJournal({
    required this.transactionId,
    required this.nextSequence,
    required this.operations,
  });

  factory _DeferredMutationJournal.empty(String transactionId) =>
      _DeferredMutationJournal(
        transactionId: transactionId,
        nextSequence: 0,
        operations: const [],
      );

  factory _DeferredMutationJournal.fromJson(Object? value) {
    if (value is! Map || value.length != 4) {
      throw const FormatException('Invalid deferred mutation journal');
    }
    final transactionId = value['transactionId'];
    final nextSequence = value['nextSequence'];
    final encodedOperations = value['operations'];
    if (value['version'] != 1 ||
        transactionId is! String ||
        transactionId.isEmpty ||
        nextSequence is! int ||
        nextSequence < 0 ||
        encodedOperations is! List) {
      throw const FormatException('Invalid deferred mutation journal');
    }
    final operations = <Map<String, Object>>[];
    var previousSequence = -1;
    for (final encoded in encodedOperations) {
      if (encoded is! Map) {
        throw const FormatException('Invalid deferred mutation operation');
      }
      final operation = <String, Object>{
        for (final entry in encoded.entries)
          if (entry.key is String && entry.value != null)
            entry.key as String: entry.value as Object,
      };
      final sequence = operation['sequence'];
      final kind = operation['kind'];
      final key = operation['key'];
      if (operation.length != encoded.length ||
          sequence is! int ||
          sequence <= previousSequence ||
          sequence >= nextSequence ||
          kind is! String ||
          key is! String ||
          !dataSyncStoredPreferenceKeys.contains(key)) {
        throw const FormatException('Invalid deferred mutation operation');
      }
      if (kind == 'scalar') {
        final scalar = operation['value'];
        if (operation.length != 4 || !_validDeferredScalar(key, scalar)) {
          throw const FormatException('Invalid deferred scalar mutation');
        }
      } else if (kind == 'records') {
        final upserts = operation['upserts'];
        final removals = operation['removals'];
        final order = operation['order'];
        if (operation.length != 6 ||
            !const {
              'cards',
              'dictionaries',
              'keyboard_scripts',
            }.contains(key) ||
            upserts is! Map ||
            removals is! List ||
            order is! List) {
          throw const FormatException('Invalid deferred records mutation');
        }
        final upsertIds = <String>{};
        for (final entry in upserts.entries) {
          if (entry.key is! String ||
              (entry.key as String).isEmpty ||
              entry.value is! String ||
              _recordId(entry.value as String) != entry.key ||
              !upsertIds.add(entry.key as String)) {
            throw const FormatException('Invalid deferred record upsert');
          }
          _validateDeferredRecord(key, entry.value as String);
        }
        if (!_validUniqueIds(removals) || !_validUniqueIds(order)) {
          throw const FormatException('Invalid deferred record ordering');
        }
      } else {
        throw const FormatException('Invalid deferred mutation kind');
      }
      previousSequence = sequence;
      operations.add(Map<String, Object>.unmodifiable(operation));
    }
    return _DeferredMutationJournal(
      transactionId: transactionId,
      nextSequence: nextSequence,
      operations: List.unmodifiable(operations),
    );
  }

  _DeferredMutationJournal withScalar(String key, Object value) {
    final retained = operations
        .where(
          (operation) =>
              operation['kind'] != 'scalar' || operation['key'] != key,
        )
        .toList();
    retained.add({
      'sequence': nextSequence,
      'kind': 'scalar',
      'key': key,
      'value': value,
    });
    retained.sort(
      (left, right) =>
          (left['sequence'] as int).compareTo(right['sequence'] as int),
    );
    return _DeferredMutationJournal(
      transactionId: transactionId,
      nextSequence: nextSequence + 1,
      operations: List.unmodifiable(retained),
    );
  }

  _DeferredMutationJournal withRecords({
    required String key,
    required Map<String, String> upserts,
    required List<String> removals,
    required List<String> order,
  }) => _DeferredMutationJournal(
    transactionId: transactionId,
    nextSequence: nextSequence + 1,
    operations: List.unmodifiable([
      ...operations,
      {
        'sequence': nextSequence,
        'kind': 'records',
        'key': key,
        'upserts': Map<String, String>.unmodifiable(upserts),
        'removals': List<String>.unmodifiable(removals),
        'order': List<String>.unmodifiable(order),
      },
    ]),
  );

  Object? apply(String key, Object? base) {
    Object? value = base is List
        ? List<String>.from(base.cast<String>())
        : base;
    for (final operation in operations) {
      if (operation['key'] != key) continue;
      if (operation['kind'] == 'scalar') {
        value = operation['value'];
      } else {
        value = _applyRecordOperation(
          value is List ? List<String>.from(value.cast<String>()) : const [],
          operation,
        );
      }
    }
    return value;
  }

  Map<String, Object> toJson() => {
    'version': 1,
    'transactionId': transactionId,
    'nextSequence': nextSequence,
    'operations': operations,
  };
}

bool _validUniqueIds(List<dynamic> values) {
  final ids = <String>{};
  return values.every(
    (value) => value is String && value.isNotEmpty && ids.add(value),
  );
}

String? _recordId(String encoded) {
  try {
    final decoded = jsonDecode(encoded);
    final id = decoded is Map ? decoded['id'] : null;
    return id is String && id.isNotEmpty ? id : null;
  } catch (_) {
    return null;
  }
}

bool _validDeferredScalar(String key, Object? value) => switch (key) {
  'app_theme' => value is int && value >= 0 && value < ThemeMode.values.length,
  'app_theme_color' => value is int && value >= 0 && value <= 7,
  'locale' =>
    value is String &&
        AppLocalizations.supportedLocales.any(
          (locale) => locale.toLanguageTag() == value,
        ),
  'sidebar_expanded_index' => value is int && value >= 0 && value <= 2,
  'confirm_delete' ||
  'auto_scan_enabled' ||
  'auto_connect_first_found' ||
  'device_found_banner' ||
  'sidebar_auto_expanded' ||
  'emulation_change_monitoring' => value is bool,
  _ => false,
};

void _validateDeferredRecord(String key, String encoded) {
  switch (key) {
    case 'cards':
      validateCardSaveSemantics(CardSave.fromJson(encoded));
    case 'dictionaries':
      _validateStoredDictionary(Dictionary.fromJson(encoded));
    case 'keyboard_scripts':
      SavedKeyboardScript.fromJson(encoded);
    default:
      throw const FormatException('Invalid deferred record collection');
  }
}

List<String> _applyRecordOperation(
  List<String> records,
  Map<String, Object> operation,
) {
  final byId = <String, String>{};
  final existingOrder = <String>[];
  final opaque = <String>[];
  for (final record in records) {
    final id = _recordId(record);
    if (id == null) {
      opaque.add(record);
    } else if (!byId.containsKey(id)) {
      byId[id] = record;
      existingOrder.add(id);
    }
  }
  for (final id in (operation['removals'] as List).cast<String>()) {
    byId.remove(id);
    existingOrder.remove(id);
  }
  for (final entry
      in (operation['upserts'] as Map).cast<String, String>().entries) {
    if (!byId.containsKey(entry.key)) existingOrder.add(entry.key);
    byId[entry.key] = entry.value;
  }
  final desiredOrder = (operation['order'] as List).cast<String>();
  final outputIds = <String>[];
  final included = <String>{};
  for (final id in desiredOrder) {
    if (byId.containsKey(id) && included.add(id)) outputIds.add(id);
  }
  for (final id in existingOrder) {
    if (byId.containsKey(id) && included.add(id)) outputIds.add(id);
  }
  return [...outputIds.map((id) => byId[id]!), ...opaque];
}

class Dictionary {
  String id;
  String name;
  List<Uint8List> keys;
  Color color;
  int keyLength;

  factory Dictionary.fromJson(String json) {
    Map<String, dynamic> data = jsonDecode(json);
    final id = data['id'] as String;
    final name = data['name'] as String;
    final encodedKeys = data['keys'] as List<dynamic>;
    if (data['color'] == null) {
      data['color'] = colorToHex(Colors.deepOrange);
    }

    if (data['keyLength'] == null) {
      // legacy
      data['keyLength'] = 12;
    }

    final keyLength = data['keyLength'] as int;
    final color = hexToColor(data['color']);

    List<Uint8List> keys = [];
    for (var key in encodedKeys) {
      keys.add(Uint8List.fromList(List<int>.from(key)));
    }
    return Dictionary(
      id: id,
      name: name,
      keys: keys,
      color: color,
      keyLength: keyLength,
    );
  }

  String toJson() {
    return jsonEncode({
      'id': id,
      'name': name,
      'color': colorToHex(color),
      'keys': keys.map((key) => key.toList()).toList(),
      'keyLength': keyLength,
    });
  }

  @override
  String toString() {
    String output = "";
    for (var key in keys) {
      output += "${bytesToHex(key).toUpperCase()}\n";
    }
    return output;
  }

  Uint8List toFile() {
    return const Utf8Encoder().convert(toString());
  }

  factory Dictionary.fromString(
    String input, {
    String name = '',
    Color color = Colors.deepOrange,
  }) {
    List<Uint8List> keys = [];
    List<int> allowedKeySizes = [
      12, // 6 - Mifare Classic
      8, // 4 - Mifare Ultralight / T55XX
      32, // 16 - Mifare Ultralight C / AES / Mifare Plus
    ];
    int currentKeySize = 0;

    for (var key in input.split("\n")) {
      key = key.trim().replaceAll('#', ' ');

      if (key.contains(' ')) {
        key = key.split(' ')[0];
      }

      if (allowedKeySizes.contains(key.length) &&
          isValidHexString(key) &&
          (currentKeySize == 0 || currentKeySize == key.length)) {
        if (currentKeySize == 0) {
          currentKeySize = key.length;
        }

        keys.add(hexToBytes(key));
      }
    }

    return Dictionary(
      id: const Uuid().v4(),
      name: name,
      keys: keys,
      color: color,
      keyLength: currentKeySize,
    );
  }

  Dictionary({
    String? id,
    this.name = "",
    this.keys = const [],
    this.color = Colors.deepOrange,
    this.keyLength = 0,
  }) : id = id ?? const Uuid().v4();
}

class CardSave {
  String id;
  String uid;
  int sak;
  Uint8List atqa;
  Uint8List ats;
  String name;
  TagType tag;
  List<Uint8List> data;
  CardSaveExtra extraData;
  Color color;

  factory CardSave.fromJson(String json) {
    Map<String, dynamic> data = jsonDecode(json);
    final id = data['id'] as String;
    final uid = data['uid'] as String;
    final sak = data['sak'] as int;
    final atqa = List<int>.from(data['atqa'] as List<dynamic>);
    final ats = List<int>.from((data['ats'] ?? []) as List<dynamic>);
    final name = data['name'] as String;
    final tag = getTagTypeByValue(data['tag']);
    final extraData = CardSaveExtra.import(data['extra'] ?? {});
    final color = data['color'] == null
        ? Colors.deepOrange
        : hexToColor(data['color']);
    List<Uint8List> tagData = (data['data'] as List<dynamic>)
        .map((e) => Uint8List.fromList(List<int>.from(e)))
        .toList();

    return CardSave(
      id: id,
      uid: uid,
      sak: sak,
      name: name,
      tag: tag,
      data: tagData,
      color: color,
      extraData: extraData,
      ats: Uint8List.fromList(ats),
      atqa: Uint8List.fromList(atqa),
    );
  }

  String toJson() {
    return jsonEncode({
      'id': id,
      'uid': uid,
      'sak': sak,
      'atqa': atqa.toList(),
      'ats': ats.toList(),
      'name': name,
      'tag': tag.value,
      'color': colorToHex(color),
      'data': data.map((data) => data.toList()).toList(),
      'extra': extraData.export(),
    });
  }

  CardSave({
    String? id,
    required this.uid,
    required this.name,
    required this.tag,
    int? sak,
    Uint8List? atqa,
    Uint8List? ats,
    CardSaveExtra? extraData,
    this.color = Colors.deepOrange,
    this.data = const [],
  }) : id = id ?? const Uuid().v4(),
       sak = sak ?? 0,
       atqa = atqa ?? Uint8List(0),
       ats = ats ?? Uint8List(0),
       extraData = extraData ?? CardSaveExtra();
}

class CardSaveExtra {
  Uint8List ultralightSignature;
  Uint8List ultralightVersion;
  List<int> ultralightCounters;

  factory CardSaveExtra.import(Map<String, dynamic> data) {
    List<int> readBytes(Map<String, dynamic> data, String key) {
      return List<int>.from(
        data[key] != null ? data[key] as List<dynamic> : [],
      );
    }

    final ultralightSignature = readBytes(data, 'ultralightSignature');
    final ultralightVersion = readBytes(data, 'ultralightVersion');
    final ultralightCounters = data['ultralightCounters'] != null
        ? List<int>.from(data['ultralightCounters'] as List<dynamic>)
        : <int>[];

    return CardSaveExtra(
      ultralightSignature: Uint8List.fromList(ultralightSignature),
      ultralightVersion: Uint8List.fromList(ultralightVersion),
      ultralightCounters: ultralightCounters,
    );
  }

  Map<String, dynamic> export() {
    Map<String, dynamic> json = {};

    if (ultralightSignature.isNotEmpty) {
      json['ultralightSignature'] = ultralightSignature;
    }

    if (ultralightVersion.isNotEmpty) {
      json['ultralightVersion'] = ultralightVersion;
    }

    if (ultralightCounters.isNotEmpty) {
      json['ultralightCounters'] = ultralightCounters;
    }

    return json;
  }

  CardSaveExtra({
    Uint8List? ultralightSignature,
    Uint8List? ultralightVersion,
    List<int>? ultralightCounters,
  }) : ultralightSignature = ultralightSignature ?? Uint8List(0),
       ultralightVersion = ultralightVersion ?? Uint8List(0),
       ultralightCounters = ultralightCounters ?? <int>[];
}

class SharedPreferencesProvider extends ChangeNotifier {
  SharedPreferencesProvider._privateConstructor();

  static final SharedPreferencesProvider _instance =
      SharedPreferencesProvider._privateConstructor();

  factory SharedPreferencesProvider() {
    return _instance;
  }

  late SharedPreferences _sharedPreferences;
  Future<void> _dataSyncQueue = Future<void>.value();
  int _queuedDataSyncActions = 0;
  int _syncMutationEpoch = 0;
  String? _reservedDataSyncTransaction;
  _DeferredMutationJournal? _deferredMutationJournal;
  _DeferredMutationJournal? _persistedDeferredMutationJournal;
  Map<String, Object>? _committedDataSyncValues;
  final Map<String, int> _pendingDeferredCaptures = {};

  @visibleForTesting
  DataSyncWriteInterceptor? debugDataSyncWriteInterceptor;
  @visibleForTesting
  Future<bool> Function(List<String> values)?
  debugEmulationChangeWriteInterceptor;

  @visibleForTesting
  DataSyncWriteInterceptor? debugDataSyncResultInterceptor;

  @visibleForTesting
  void debugAdvanceDataSyncMutationEpoch() {
    _syncMutationEpoch++;
  }

  Future<void> load() async {
    final sharedPreferences = await SharedPreferences.getInstance();
    if (_queuedDataSyncActions == 0) {
      // Do not retain a completed Future from a previous process/test zone.
      _dataSyncQueue = Future<void>.value();
    }
    await _serializeDataSync(() async {
      _sharedPreferences = sharedPreferences;
      final manifest = _readDataSyncManifestLocked();
      final deferred = _readDeferredMutationJournalLocked();
      if (manifest != null &&
          deferred != null &&
          manifest.transactionId != deferred.transactionId) {
        throw StateError('Data sync reservation journals do not match');
      }
      _syncMutationEpoch = manifest?.mutationEpoch ?? 0;
      _deferredMutationJournal = deferred;
      _persistedDeferredMutationJournal = deferred;
      _pendingDeferredCaptures.clear();
      _reservedDataSyncTransaction =
          manifest?.transactionId ?? deferred?.transactionId;
      await _recoverDataSyncTransactionLocked();
      await _dataSyncCheckpointLocked();
      _publishCommittedDataSyncValues(_currentDataSyncValues());
    });
  }

  Future<T> withDataSyncCheckpoint<T>(
    T Function(SyncCheckpoint checkpoint) read,
  ) {
    return _serializeDataSync(() async {
      await _recoverDataSyncTransactionLocked();
      if (_reservedDataSyncTransaction != null) {
        throw StateError('Data sync transaction is awaiting a peer decision');
      }
      while (true) {
        final epoch = _syncMutationEpoch;
        final checkpoint = await _dataSyncCheckpointLocked();
        final result = read(checkpoint);
        if (epoch == _syncMutationEpoch &&
            checkpoint.stateHash ==
                _hashDataSyncValues(_currentDataSyncValues())) {
          return result;
        }
      }
    });
  }

  Future<SyncCheckpoint> getDataSyncCheckpoint() =>
      withDataSyncCheckpoint((checkpoint) => checkpoint);

  Future<SyncTransactionReceipt> applyDataSyncValues({
    required String transactionId,
    required SyncCheckpoint expectedCheckpoint,
    required Map<String, Object> values,
  }) {
    return _serializeDataSync(() async {
      await _recoverDataSyncTransactionLocked();
      final prepared = await _prepareDataSyncTransactionLocked(
        transactionId: transactionId,
        expectedCheckpoint: expectedCheckpoint,
        values: values,
        role: SyncTransactionRole.local,
      );
      if (prepared.outcome != SyncTransactionOutcome.prepared) return prepared;
      return _commitDataSyncTransactionLocked(transactionId);
    });
  }

  Future<SyncTransactionReceipt> prepareDataSyncValues({
    required String transactionId,
    required SyncCheckpoint expectedCheckpoint,
    required Map<String, Object> values,
    SyncTransactionRole role = SyncTransactionRole.participant,
    SyncCheckpoint? peerCheckpoint,
    String? claimedTargetHash,
  }) {
    return _serializeDataSync(() async {
      await _recoverDataSyncTransactionLocked();
      return _prepareDataSyncTransactionLocked(
        transactionId: transactionId,
        expectedCheckpoint: expectedCheckpoint,
        values: values,
        role: role,
        peerCheckpoint: peerCheckpoint,
        claimedTargetHash: claimedTargetHash,
      );
    });
  }

  Future<SyncTransactionReceipt> commitDataSyncTransaction(
    String transactionId,
  ) =>
      _serializeDataSync(() => _commitDataSyncTransactionLocked(transactionId));

  Future<SyncTransactionReceipt> abortDataSyncParticipantFromCoordinator(
    String transactionId,
    String targetHash,
  ) {
    return _serializeDataSync(() async {
      final stored = _findDataSyncReceiptLocked(transactionId);
      final manifest = _readDataSyncManifestLocked();
      if (manifest == null || manifest.transactionId != transactionId) {
        if (stored != null && stored.targetHash == targetHash) {
          if (manifest == null) {
            await _finishTerminalWithoutManifestLocked(stored);
          }
          return stored;
        }
        throw StateError('Data sync participant is not prepared');
      }
      if (manifest.role != SyncTransactionRole.participant) {
        throw StateError('Data sync transaction is not a participant');
      }
      if (manifest.target.stateHash != targetHash) {
        throw StateError('Coordinator ABORT target does not match PREPARE');
      }
      if (manifest.phase == _DataSyncTransactionPhase.commitDecided) {
        return _commitDataSyncTransactionLocked(transactionId);
      }
      return _abortDataSyncManifestLocked(manifest);
    });
  }

  Future<SyncTransactionReceipt> recordDataSyncAbort(
    String transactionId,
    String targetHash,
  ) {
    return _serializeDataSync(() async {
      if (transactionId.isEmpty ||
          transactionId.length > 128 ||
          !_isSha256(targetHash)) {
        throw const FormatException('Invalid data sync abort receipt');
      }
      final stored = _findDataSyncReceiptLocked(transactionId);
      final active = _readDataSyncManifestLocked();
      if (active != null) {
        if (active.transactionId != transactionId ||
            active.target.stateHash != targetHash) {
          throw StateError('Another data sync transaction is already prepared');
        }
        if (active.role == SyncTransactionRole.participant) {
          throw StateError(
            'A prepared participant requires authenticated coordinator ABORT',
          );
        }
        if (active.phase == _DataSyncTransactionPhase.commitDecided ||
            _coordinatorDecisionLocked(transactionId) ==
                SyncCoordinatorDecision.commitDecided) {
          return _commitDataSyncTransactionLocked(transactionId);
        }
        return _abortDataSyncManifestLocked(active);
      }
      if (stored != null) {
        if (stored.targetHash != targetHash) {
          throw StateError('Data sync transaction ID was reused');
        }
        await _finishTerminalWithoutManifestLocked(stored);
        return stored;
      }
      final receipt = SyncTransactionReceipt(
        transactionId: transactionId,
        outcome: SyncTransactionOutcome.aborted,
        targetHash: targetHash,
        checkpoint: await _dataSyncCheckpointLocked(),
      );
      await _saveDataSyncReceiptLocked(receipt);
      return receipt;
    });
  }

  Future<SyncTransactionReceipt?> getDataSyncTransactionReceipt(
    String transactionId,
  ) {
    return _serializeDataSync(() async {
      await _recoverDataSyncTransactionLocked();
      final stored = _findDataSyncReceiptLocked(transactionId);
      if (stored != null) return stored;
      final manifest = _readDataSyncManifestLocked();
      if (manifest == null || manifest.transactionId != transactionId) {
        return null;
      }
      if (manifest.phase == _DataSyncTransactionPhase.prepared) {
        await _validatePreparedDataSyncManifestLocked(manifest);
      }
      return SyncTransactionReceipt(
        transactionId: transactionId,
        outcome: manifest.phase == _DataSyncTransactionPhase.prepared
            ? SyncTransactionOutcome.prepared
            : SyncTransactionOutcome.committed,
        targetHash: manifest.target.stateHash,
        checkpoint: manifest.phase == _DataSyncTransactionPhase.prepared
            ? manifest.expected
            : manifest.target,
      );
    });
  }

  Future<SyncCoordinatorRecovery?> getDataSyncCoordinatorRecovery() {
    return _serializeDataSync(() async => _readCoordinatorRecoveryLocked());
  }

  Future<SyncCoordinatorRecovery> decideDataSyncCoordinatorAbort(
    String transactionId,
  ) {
    return _serializeDataSync(() async {
      var recovery = _readCoordinatorRecoveryLocked();
      if (recovery == null || recovery.transactionId != transactionId) {
        throw StateError('Data sync coordinator record is missing');
      }
      if (recovery.decision == SyncCoordinatorDecision.commitDecided) {
        throw StateError('A committed data sync cannot be aborted');
      }
      if (recovery.decision != SyncCoordinatorDecision.abortDecided) {
        recovery = recovery.withDecision(SyncCoordinatorDecision.abortDecided);
        await _checkedSet(
          dataSyncCoordinatorPreferenceKey,
          jsonEncode(recovery.toJson()),
        );
      }
      final manifest = _readDataSyncManifestLocked();
      if (manifest?.transactionId == transactionId) {
        await _abortDataSyncManifestLocked(manifest!);
      } else {
        var receipt = _findDataSyncReceiptLocked(transactionId);
        if (receipt == null) {
          receipt = SyncTransactionReceipt(
            transactionId: transactionId,
            outcome: SyncTransactionOutcome.aborted,
            targetHash: recovery.targetHash,
            checkpoint: await _dataSyncCheckpointLocked(),
          );
          await _saveDataSyncReceiptLocked(receipt);
        }
        if (receipt.outcome != SyncTransactionOutcome.aborted ||
            receipt.targetHash != recovery.targetHash) {
          throw StateError('Local coordinator ABORT outcome does not match');
        }
        if (manifest == null) {
          await _finishTerminalWithoutManifestLocked(receipt);
        }
      }
      return recovery;
    });
  }

  Future<void> completeDataSyncCoordinator(String transactionId) {
    return _serializeDataSync(() async {
      final recovery = _readCoordinatorRecoveryLocked();
      if (recovery == null) return;
      if (recovery.transactionId != transactionId ||
          recovery.decision == SyncCoordinatorDecision.prepared) {
        throw StateError('Data sync coordinator decision does not match');
      }
      final receipt = _findDataSyncReceiptLocked(transactionId);
      final expectedOutcome =
          recovery.decision == SyncCoordinatorDecision.commitDecided
          ? SyncTransactionOutcome.committed
          : SyncTransactionOutcome.aborted;
      if (receipt?.outcome != expectedOutcome) {
        throw StateError('Local data sync decision is not complete');
      }
      if (_readDataSyncManifestLocked() == null) {
        await _finishTerminalWithoutManifestLocked(receipt!);
      }
      await _checkedRemove(dataSyncCoordinatorPreferenceKey);
    });
  }

  Future<SyncTransactionReceipt?> getPendingDataSyncParticipant() {
    return _serializeDataSync(() async {
      await _recoverDataSyncTransactionLocked();
      final manifest = _readDataSyncManifestLocked();
      if (manifest == null ||
          manifest.role != SyncTransactionRole.participant) {
        return null;
      }
      if (manifest.phase == _DataSyncTransactionPhase.prepared) {
        await _validatePreparedDataSyncManifestLocked(manifest);
      }
      return SyncTransactionReceipt(
        transactionId: manifest.transactionId,
        outcome: manifest.phase == _DataSyncTransactionPhase.prepared
            ? SyncTransactionOutcome.prepared
            : SyncTransactionOutcome.committed,
        targetHash: manifest.target.stateHash,
        checkpoint: manifest.phase == _DataSyncTransactionPhase.prepared
            ? manifest.expected
            : manifest.target,
      );
    });
  }

  void notifyDataSyncCommitted() {
    notifyListeners();
  }

  ThemeMode getTheme() {
    final themeValue = _visibleInt('app_theme') ?? 0;
    return themeValue >= 0 && themeValue < ThemeMode.values.length
        ? ThemeMode.values[themeValue]
        : ThemeMode.system;
  }

  Future<void> setTheme(ThemeMode theme) =>
      _setSynchronizedScalar('app_theme', theme.index);

  bool getSideBarAutoExpansion() {
    return _visibleBool('sidebar_auto_expanded') ?? true;
  }

  bool getSideBarExpanded() {
    return _sharedPreferences.getBool('sidebar_expanded') ?? false;
  }

  int getSideBarExpandedIndex() {
    return _visibleInt('sidebar_expanded_index') ?? 1;
  }

  Future<void> setSideBarAutoExpansion(bool autoExpanded) =>
      _setSynchronizedScalar('sidebar_auto_expanded', autoExpanded);

  void setSideBarExpanded(bool expanded) {
    _sharedPreferences.setBool('sidebar_expanded', expanded);
  }

  Future<void> setSideBarExpandedIndex(int index) =>
      _setSynchronizedScalar('sidebar_expanded_index', index);

  int getThemeColorIndex() {
    final color = _visibleInt('app_theme_color') ?? 0;
    return color >= 0 && color <= 7 ? color : 0;
  }

  MaterialColor getThemeColor() {
    return colors.getThemeColor(getThemeColorIndex());
  }

  Color getThemeComplementaryColor() {
    final themeMode = getTheme().index;
    return colors.getThemeComplementary(themeMode, getThemeColorIndex());
  }

  Future<void> setThemeColor(int color) =>
      _setSynchronizedScalar('app_theme_color', color);

  bool isDebugMode() {
    return _sharedPreferences.getBool('debug') ?? false;
  }

  void setDebugMode(bool value) {
    _sharedPreferences.setBool('debug', value);
  }

  bool isEmulatedChameleon() {
    return _sharedPreferences.getBool('emulate_device') ?? false;
  }

  void setEmulatedChameleon(bool value) {
    _sharedPreferences.setBool('emulate_device', value);
  }

  bool getMifareClassicNonceHistoryEnabled() =>
      _sharedPreferences.getBool(
        _mifareClassicNonceHistoryEnabledPreferenceKey,
      ) ??
      false;

  Future<void> setMifareClassicNonceHistoryEnabled(bool enabled) async {
    final stored = await _sharedPreferences.setBool(
      _mifareClassicNonceHistoryEnabledPreferenceKey,
      enabled,
    );
    if (!stored || getMifareClassicNonceHistoryEnabled() != enabled) {
      throw StateError('MIFARE Classic nonce history setting was not stored');
    }
    notifyListeners();
  }

  bool hasMifareClassicNonceSample(String cardUid, String sample) {
    if (!getMifareClassicNonceHistoryEnabled()) return false;
    final uid = _normaliseMifareClassicNonceHistoryUid(cardUid);
    if (uid == null || sample.isEmpty) return false;
    return _readMifareClassicNonceHistory()[uid]?.contains(
          _mifareClassicNonceSampleDigest(sample),
        ) ??
        false;
  }

  Future<void> recordMifareClassicNonceSample(
    String cardUid,
    String sample,
  ) async {
    if (!getMifareClassicNonceHistoryEnabled()) return;
    final uid = _normaliseMifareClassicNonceHistoryUid(cardUid);
    if (uid == null || sample.isEmpty) return;
    final history = _readMifareClassicNonceHistory();
    final entries = history.putIfAbsent(uid, () => <String>{});
    if (!entries.add(_mifareClassicNonceSampleDigest(sample))) return;
    await _writeMifareClassicNonceHistory(history);
  }

  List<MifareClassicNonceHistorySummary>
  getMifareClassicNonceHistorySummaries() {
    final history = _readMifareClassicNonceHistory();
    final summaries = [
      for (final entry in history.entries)
        MifareClassicNonceHistorySummary(
          cardUid: entry.key,
          sampleCount: entry.value.length,
          byteSize: utf8
              .encode(
                jsonEncode({
                  'uid': entry.key,
                  'samples': entry.value.toList()..sort(),
                }),
              )
              .length,
        ),
    ];
    summaries.sort((left, right) => left.cardUid.compareTo(right.cardUid));
    return List.unmodifiable(summaries);
  }

  Future<void> clearMifareClassicNonceHistoryForCard(String cardUid) async {
    final uid = _normaliseMifareClassicNonceHistoryUid(cardUid);
    if (uid == null) return;
    final history = _readMifareClassicNonceHistory();
    if (history.remove(uid) == null) return;
    await _writeMifareClassicNonceHistory(history);
  }

  Map<String, Set<String>> _readMifareClassicNonceHistory() {
    final encoded = _sharedPreferences.getString(
      _mifareClassicNonceHistoryPreferenceKey,
    );
    if (encoded == null) return {};
    try {
      final decoded = jsonDecode(encoded);
      if (decoded is! Map ||
          decoded['version'] != 1 ||
          decoded['cards'] is! Map) {
        return {};
      }
      final history = <String, Set<String>>{};
      for (final entry in (decoded['cards'] as Map).entries) {
        final uid = entry.key is String
            ? _normaliseMifareClassicNonceHistoryUid(entry.key as String)
            : null;
        if (uid == null || entry.value is! List) continue;
        final samples = <String>{
          for (final sample in entry.value as List)
            if (sample is String && RegExp(r'^[a-f0-9]{64}$').hasMatch(sample))
              sample,
        };
        if (samples.isNotEmpty) history[uid] = samples;
      }
      return history;
    } catch (_) {
      return {};
    }
  }

  Future<void> _writeMifareClassicNonceHistory(
    Map<String, Set<String>> history,
  ) async {
    if (history.isEmpty) {
      final removed = await _sharedPreferences.remove(
        _mifareClassicNonceHistoryPreferenceKey,
      );
      if (!removed &&
          _sharedPreferences.containsKey(
            _mifareClassicNonceHistoryPreferenceKey,
          )) {
        throw StateError('MIFARE Classic nonce history was not removed');
      }
    } else {
      final encoded = jsonEncode({
        'version': 1,
        'cards': {
          for (final uid in history.keys.toList()..sort())
            uid: history[uid]!.toList()..sort(),
        },
      });
      final stored = await _sharedPreferences.setString(
        _mifareClassicNonceHistoryPreferenceKey,
        encoded,
      );
      if (!stored ||
          _sharedPreferences.getString(
                _mifareClassicNonceHistoryPreferenceKey,
              ) !=
              encoded) {
        throw StateError('MIFARE Classic nonce history was not stored');
      }
    }
    notifyListeners();
  }

  String? _normaliseMifareClassicNonceHistoryUid(String value) {
    final uid = value.replaceAll(RegExp(r'[^a-fA-F0-9]'), '').toUpperCase();
    return uid.length >= 8 && uid.length <= 20 && uid.length.isEven
        ? uid
        : null;
  }

  String _mifareClassicNonceSampleDigest(String sample) =>
      sha256.convert(utf8.encode(sample)).toString();

  List<Dictionary> getDictionaries({int keyLength = 0}) {
    return _decodeStoredDictionaries(
          _visibleStringList('dictionaries') ?? const [],
        )
        .where(
          (dictionary) => keyLength == 0 || dictionary.keyLength == keyLength,
        )
        .toList();
  }

  Future<void> setDictionaries(List<Dictionary> dictionaries) async {
    List<String> output = [];
    for (var dictionary in dictionaries) {
      if (dictionary.id != "") {
        // system empty dictionary, never save it
        output.add(dictionary.toJson());
      }
    }
    await _setSynchronizedRecords('dictionaries', output);
  }

  List<CardSave> getCards() {
    return _decodeStoredCards(_visibleStringList('cards') ?? const []);
  }

  Future<void> setCards(List<CardSave> cards) async {
    List<String> output = [];
    for (var card in cards) {
      validateCardSaveSemantics(card);
      output.add(card.toJson());
    }
    await _setSynchronizedRecords('cards', output);
  }

  bool getEmulationChangeMonitoring() {
    return _visibleBool('emulation_change_monitoring') ?? false;
  }

  Future<void> setEmulationChangeMonitoring(bool value) =>
      _setSynchronizedScalar('emulation_change_monitoring', value);

  bool getAuthorizedRelayAppleTransit() {
    return _sharedPreferences.getBool('authorized_relay_apple_transit') ??
        false;
  }

  void setAuthorizedRelayAppleTransit(bool value) {
    _sharedPreferences.setBool('authorized_relay_apple_transit', value);
  }

  List<EmulationChangeEntry> getEmulationChangeHistory() {
    final entries = <EmulationChangeEntry>[];
    for (final encoded
        in _sharedPreferences.getStringList('emulation_change_history') ??
            const []) {
      try {
        entries.add(EmulationChangeEntry.fromJson(encoded));
      } catch (_) {
        // Keep valid history entries if one record is corrupt.
      }
    }
    entries.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return entries;
  }

  Future<void> addEmulationChange(EmulationChangeEntry entry) async {
    final entryJson = entry.toJson();
    final entries = getEmulationChangeHistory()
      ..removeWhere((item) => item.toJson() == entryJson)
      ..insert(0, entry);
    final encoded = entries
        .take(emulationChangeHistoryLimit)
        .map((item) => item.toJson())
        .toList();
    final interceptor = debugEmulationChangeWriteInterceptor;
    final written = interceptor != null
        ? await interceptor(List<String>.unmodifiable(encoded))
        : await _sharedPreferences.setStringList(
            'emulation_change_history',
            encoded,
          );
    if (!written ||
        !listEquals(
          _sharedPreferences.getStringList('emulation_change_history'),
          encoded,
        )) {
      throw StateError('Emulation change history was not durably stored');
    }
  }

  void clearEmulationChangeHistory() {
    _sharedPreferences.remove('emulation_change_history');
  }

  List<SavedKeyboardScript> getKeyboardScripts() {
    return _decodeStoredScripts(
      _visibleStringList('keyboard_scripts') ?? const [],
    );
  }

  Future<void> setKeyboardScripts(List<SavedKeyboardScript> scripts) async {
    final ordered = scripts.toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    final encoded = ordered
        .take(savedKeyboardScriptLimit)
        .map((script) => script.toJson())
        .toList();
    await _setSynchronizedRecords('keyboard_scripts', encoded);
  }

  Future<void> setLocale(Locale loc) {
    for (var locale in AppLocalizations.supportedLocales) {
      if (locale.toLanguageTag().toLowerCase() ==
          loc.toLanguageTag().toLowerCase()) {
        return _setSynchronizedScalar(
          'locale',
          loc.toLanguageTag(),
          notify: true,
        );
      }
    }
    return Future<void>.value();
  }

  String getLocaleString() {
    return _visibleString("locale") ?? "en";
  }

  Locale getLocale() {
    final localeId = getLocaleString();
    Locale locale;
    if (localeId.contains("-")) {
      final [lcode, ccode] = localeId.toString().split("-");
      locale = Locale(lcode, ccode);
    } else {
      locale = Locale(localeId);
    }
    if (!AppLocalizations.supportedLocales.contains(locale)) {
      return const Locale('en');
    } else {
      return locale;
    }
  }

  Future<void> clearLocale() =>
      _setSynchronizedScalar('locale', 'en', notify: true);

  bool isDebugLogging() {
    return _sharedPreferences.getBool('debug_logging') ?? false;
  }

  void setDebugLogging(bool value) {
    _sharedPreferences.setBool('debug_logging', value);
  }

  void addLogLine(String value) {
    List<String> rows =
        _sharedPreferences.getStringList('debug_logging_value') ?? [];
    rows.add(value);

    if (rows.length > 5000) {
      rows.removeAt(0);
    }

    _sharedPreferences.setStringList('debug_logging_value', rows);
  }

  void clearLogLines() {
    _sharedPreferences.setStringList('debug_logging_value', []);
  }

  List<String> getLogLines() {
    return _sharedPreferences.getStringList('debug_logging_value') ?? [];
  }

  String dumpSettingsToJson() {
    final settings = <String, Object>{
      'app_theme': getTheme().index,
      'app_theme_color': getThemeColorIndex(),
      'locale': getLocaleString(),
      'confirm_delete': getConfirmDelete(),
      'auto_scan_enabled': getAutoScanEnabled(),
      'auto_connect_first_found': getAutoConnectFirstFoundDevice(),
      'device_found_banner': getDeviceFoundBanner(),
      'sidebar_auto_expanded': getSideBarAutoExpansion(),
      'sidebar_expanded_index': getSideBarExpandedIndex(),
      'emulation_change_monitoring': getEmulationChangeMonitoring(),
    };
    _validateLegacySettings(settings);
    return jsonEncode({
      'version': _legacySettingsFormatVersion,
      'settings': settings,
    });
  }

  Future<void> restoreSettingsFromJson(String jsonSettings) async {
    if (jsonSettings.length > _legacySettingsMaxEncodedBytes ||
        utf8.encode(jsonSettings).length > _legacySettingsMaxEncodedBytes) {
      throw const FormatException('Settings backup exceeds the size limit');
    }

    final decoded = jsonDecode(jsonSettings);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Invalid settings backup');
    }
    Object? candidate;
    if (decoded.length == 2 &&
        decoded.containsKey('version') &&
        decoded.containsKey('settings')) {
      final version = decoded['version'];
      if (version is! int || version != _legacySettingsFormatVersion) {
        throw const FormatException('Unsupported settings backup version');
      }
      candidate = decoded['settings'];
    } else {
      final migrated = <String, dynamic>{
        for (final entry in decoded.entries)
          if (_legacyScalarSettingKeys.contains(entry.key))
            entry.key: entry.value,
      };
      if (migrated.isEmpty) {
        throw const FormatException('Legacy backup has no safe settings');
      }
      candidate = migrated;
    }

    // Validate and copy every value before mutating any preference.
    final settings = _validateLegacySettings(candidate);
    await _setSynchronizedScalars(
      settings,
      notify: settings.containsKey('locale'),
    );
  }

  bool getConfirmDelete() {
    return _visibleBool('confirm_delete') ?? true;
  }

  Future<void> setConfirmDelete(bool value) =>
      _setSynchronizedScalar('confirm_delete', value);

  bool getAutoScanEnabled() {
    return _visibleBool('auto_scan_enabled') ?? true;
  }

  Future<void> setAutoScanEnabled(bool value) =>
      _setSynchronizedScalar('auto_scan_enabled', value);

  bool getAutoConnectFirstFoundDevice() {
    return _visibleBool('auto_connect_first_found') ?? false;
  }

  Future<void> setAutoConnectFirstFoundDevice(bool value) =>
      _setSynchronizedScalar('auto_connect_first_found', value);

  bool getEthicalHackingAck() {
    return _sharedPreferences.getBool('ethical_hacking_ack') ?? false;
  }

  void setEthicalHackingAck(bool value) {
    _sharedPreferences.setBool('ethical_hacking_ack', value);
  }

  bool getDeviceFoundBanner() {
    return _visibleBool('device_found_banner') ?? true;
  }

  Future<void> setDeviceFoundBanner(bool value) =>
      _setSynchronizedScalar('device_found_banner', value);

  int? _visibleInt(String key) => _visiblePreferenceValue(key) as int?;

  bool? _visibleBool(String key) => _visiblePreferenceValue(key) as bool?;

  String? _visibleString(String key) => _visiblePreferenceValue(key) as String?;

  List<String>? _visibleStringList(String key) {
    final value = _visiblePreferenceValue(key);
    return value == null ? null : List<String>.from((value as List).cast());
  }

  Object? _visiblePreferenceValue(String key) {
    final committed = _committedDataSyncValues;
    final actual = committed == null
        ? _sharedPreferences.get(key)
        : committed[key];
    final journal = _deferredMutationJournal;
    if (journal != null &&
        (_reservedDataSyncTransaction == journal.transactionId ||
            (_pendingDeferredCaptures[journal.transactionId] ?? 0) > 0)) {
      return journal.apply(key, actual);
    }
    return actual;
  }

  void _publishCommittedDataSyncValues(Map<String, Object> values) {
    _committedDataSyncValues = Map<String, Object>.unmodifiable({
      for (final key in dataSyncStoredPreferenceKeys)
        key: _copyDataSyncPreferenceValue(values[key]!),
    });
  }

  void _publishCommittedPreferenceValues(Map<String, Object> values) {
    final committed = Map<String, Object>.from(
      _committedDataSyncValues ?? _currentDataSyncValues(),
    );
    for (final entry in values.entries) {
      committed[entry.key] = _copyDataSyncPreferenceValue(entry.value);
    }
    _publishCommittedDataSyncValues(committed);
  }

  Future<void> _setSynchronizedScalar(
    String key,
    Object value, {
    bool notify = false,
  }) => _setSynchronizedScalars({key: value}, notify: notify);

  Future<void> _setSynchronizedScalars(
    Map<String, Object> values, {
    bool notify = false,
  }) {
    if (values.isEmpty) {
      if (notify) notifyListeners();
      return Future<void>.value();
    }
    for (final entry in values.entries) {
      if (!_validDeferredScalar(entry.key, entry.value)) {
        return Future<void>.error(
          FormatException('Invalid synchronized setting: ${entry.key}'),
        );
      }
    }
    final reservedAtInvocation = _reservedDataSyncTransaction;
    final capturedAtInvocation = reservedAtInvocation == null
        ? null
        : _captureDeferredScalars(reservedAtInvocation, values);
    return _serializeDataSync(() async {
      if (capturedAtInvocation != null) {
        await _persistCapturedDeferredJournal(
          reservedAtInvocation!,
          capturedAtInvocation,
        );
      } else if (_reservedDataSyncTransaction case final reserved?) {
        final captured = _captureDeferredScalars(reserved, values);
        await _persistCapturedDeferredJournal(reserved, captured);
      } else {
        for (final entry in values.entries) {
          await _checkedSet(entry.key, entry.value);
        }
        _publishCommittedPreferenceValues(values);
        _syncMutationEpoch++;
      }
      if (notify) notifyListeners();
    });
  }

  Future<void> _setSynchronizedRecords(String key, List<String> desired) {
    final desiredCopy = List<String>.unmodifiable(desired);
    final reservedAtInvocation = _reservedDataSyncTransaction;
    final capturedAtInvocation = reservedAtInvocation == null
        ? null
        : _captureDeferredRecords(reservedAtInvocation, key, desiredCopy);
    return _serializeDataSync(() async {
      if (capturedAtInvocation != null) {
        await _persistCapturedDeferredJournal(
          reservedAtInvocation!,
          capturedAtInvocation,
        );
      } else if (_reservedDataSyncTransaction case final reserved?) {
        final captured = _captureDeferredRecords(reserved, key, desiredCopy);
        await _persistCapturedDeferredJournal(reserved, captured);
      } else {
        await _checkedSet(key, desiredCopy);
        _publishCommittedPreferenceValues({key: desiredCopy});
        _syncMutationEpoch++;
      }
    });
  }

  _DeferredMutationJournal _captureDeferredScalars(
    String transactionId,
    Map<String, Object> values,
  ) {
    var journal =
        _deferredMutationJournal ??
        _DeferredMutationJournal.empty(transactionId);
    if (journal.transactionId != transactionId) {
      throw StateError('Deferred mutation reservation does not match');
    }
    for (final entry in values.entries) {
      journal = journal.withScalar(entry.key, entry.value);
    }
    _deferredMutationJournal = journal;
    _beginDeferredCapture(transactionId);
    return journal;
  }

  _DeferredMutationJournal _captureDeferredRecords(
    String transactionId,
    String key,
    List<String> desired,
  ) {
    final desiredById = <String, String>{};
    final desiredOrder = <String>[];
    for (final record in desired) {
      final id = _recordId(record);
      if (id == null || desiredById.containsKey(id)) {
        throw FormatException('Invalid or duplicate $key record ID');
      }
      _validateDeferredRecord(key, record);
      desiredById[id] = record;
      desiredOrder.add(id);
    }
    final before = _persistedVisibleStringList(key) ?? const [];
    final beforeById = <String, String>{};
    for (final record in before) {
      final id = _recordId(record);
      if (id != null) beforeById[id] = record;
    }
    final upserts = <String, String>{
      for (final entry in desiredById.entries)
        if (beforeById[entry.key] != entry.value) entry.key: entry.value,
    };
    final removals = beforeById.keys
        .where((id) => !desiredById.containsKey(id))
        .toList();
    var journal =
        _deferredMutationJournal ??
        _DeferredMutationJournal.empty(transactionId);
    if (journal.transactionId != transactionId) {
      throw StateError('Deferred mutation reservation does not match');
    }
    journal = journal.withRecords(
      key: key,
      upserts: upserts,
      removals: removals,
      order: desiredOrder,
    );
    _deferredMutationJournal = journal;
    _beginDeferredCapture(transactionId);
    return journal;
  }

  List<String>? _persistedVisibleStringList(String key) {
    final committed = _committedDataSyncValues;
    final base = committed == null
        ? _sharedPreferences.get(key)
        : committed[key];
    final value = _persistedDeferredMutationJournal?.apply(key, base) ?? base;
    return value == null ? null : List<String>.from((value as List).cast());
  }

  void _beginDeferredCapture(String transactionId) {
    _pendingDeferredCaptures[transactionId] =
        (_pendingDeferredCaptures[transactionId] ?? 0) + 1;
  }

  void _completeDeferredCapture(String transactionId) {
    final remaining = (_pendingDeferredCaptures[transactionId] ?? 1) - 1;
    if (remaining > 0) {
      _pendingDeferredCaptures[transactionId] = remaining;
      return;
    }
    _pendingDeferredCaptures.remove(transactionId);
    if (_reservedDataSyncTransaction != transactionId &&
        !_sharedPreferences.containsKey(
          dataSyncDeferredMutationsPreferenceKey,
        )) {
      if (_deferredMutationJournal?.transactionId == transactionId) {
        _deferredMutationJournal = null;
      }
      if (_persistedDeferredMutationJournal?.transactionId == transactionId) {
        _persistedDeferredMutationJournal = null;
      }
    }
  }

  Future<void> _persistCapturedDeferredJournal(
    String transactionId,
    _DeferredMutationJournal captured,
  ) async {
    try {
      await _checkedSet(
        dataSyncDeferredMutationsPreferenceKey,
        jsonEncode(captured.toJson()),
      );
      _persistedDeferredMutationJournal = captured;
      final visibleJournal = _deferredMutationJournal;
      if (visibleJournal == null ||
          (visibleJournal.transactionId == transactionId &&
              visibleJournal.nextSequence < captured.nextSequence)) {
        _deferredMutationJournal = captured;
      }

      final manifest = _readDataSyncManifestLocked();
      if (manifest?.transactionId == transactionId) return;
      if (manifest != null) {
        throw StateError('Another data sync transaction is active');
      }
      final receipt = _findDataSyncReceiptLocked(transactionId);
      if (receipt != null &&
          receipt.outcome != SyncTransactionOutcome.prepared) {
        try {
          await _finishTerminalWithoutManifestLocked(receipt);
        } on SyncPersistenceException {
          // The intent itself is durable and remains visible; recovery retries
          // terminal replay/cleanup without failing the accepted setter.
        }
      } else if (receipt == null) {
        try {
          await _finishDeferredWithoutTransactionLocked(transactionId);
        } on SyncPersistenceException {
          // Keep the durable journal and reservation for the next recovery.
        }
      }
    } finally {
      _completeDeferredCapture(transactionId);
    }
  }

  Future<void> _finishDeferredWithoutTransactionLocked(
    String transactionId,
  ) async {
    _reserveSynchronizedData(transactionId);
    await _drainDeferredMutationsLocked(transactionId);
    await _removeOrphanDataSyncStagesLocked();
    await _checkedRemove(dataSyncDeferredMutationsPreferenceKey);
    _persistedDeferredMutationJournal = null;
    _releaseSynchronizedData(transactionId);
  }

  void _reserveSynchronizedData(String transactionId) {
    final reserved = _reservedDataSyncTransaction;
    if (reserved != null && reserved != transactionId) {
      throw StateError('Synchronized data is reserved by another transaction');
    }
    _reservedDataSyncTransaction = transactionId;
  }

  void _releaseSynchronizedData(String transactionId) {
    if (_reservedDataSyncTransaction != transactionId) return;
    if (_sharedPreferences.containsKey(
      dataSyncDeferredMutationsPreferenceKey,
    )) {
      throw StateError('Cannot release a reservation with deferred mutations');
    }
    _reservedDataSyncTransaction = null;
    _persistedDeferredMutationJournal = null;
    if ((_pendingDeferredCaptures[transactionId] ?? 0) == 0) {
      _deferredMutationJournal = null;
    }
  }

  _DeferredMutationJournal? _readDeferredMutationJournalLocked() {
    final encoded = _sharedPreferences.getString(
      dataSyncDeferredMutationsPreferenceKey,
    );
    if (encoded == null) return null;
    try {
      return _DeferredMutationJournal.fromJson(jsonDecode(encoded));
    } catch (_) {
      throw StateError('The deferred mutation journal is corrupt');
    }
  }

  Future<void> _drainDeferredMutationsLocked(String transactionId) async {
    final journal = _readDeferredMutationJournalLocked();
    if (journal == null) {
      _persistedDeferredMutationJournal = null;
      return;
    }
    if (journal.transactionId != transactionId) {
      throw StateError('Deferred mutation transaction does not match');
    }
    _persistedDeferredMutationJournal = journal;
    final values = <String, Object?>{};
    final keyOrder = <String>[];
    for (final operation in journal.operations) {
      final key = operation['key']! as String;
      if (!values.containsKey(key)) {
        final actual = _sharedPreferences.get(key);
        values[key] = actual is List
            ? List<String>.from(actual.cast<String>())
            : actual;
        keyOrder.add(key);
      }
      values[key] = operation['kind'] == 'scalar'
          ? operation['value']
          : _applyRecordOperation(
              values[key] is List
                  ? List<String>.from((values[key] as List).cast<String>())
                  : const [],
              operation,
            );
    }
    for (final key in keyOrder) {
      await _checkedSet(key, values[key]!);
    }
    if (keyOrder.isNotEmpty) {
      _publishCommittedDataSyncValues(_currentDataSyncValues());
      _syncMutationEpoch++;
    }
    final visibleJournal = _deferredMutationJournal;
    if (visibleJournal == null ||
        (visibleJournal.transactionId == transactionId &&
            visibleJournal.nextSequence < journal.nextSequence)) {
      _deferredMutationJournal = journal;
    }
  }

  Future<T> _serializeDataSync<T>(Future<T> Function() action) {
    _queuedDataSyncActions++;
    final result = _dataSyncQueue.then((_) => action());
    _dataSyncQueue = result.then<void>(
      (_) => _queuedDataSyncActions--,
      onError: (_, _) => _queuedDataSyncActions--,
    );
    return result;
  }

  Future<SyncCheckpoint> _dataSyncCheckpointLocked() async {
    final stateHash = _hashDataSyncValues(_currentDataSyncValues());
    final encoded = _sharedPreferences.getString(dataSyncMetaPreferenceKey);
    if (encoded == null) {
      final checkpoint = SyncCheckpoint(revision: 0, stateHash: stateHash);
      await _checkedSet(
        dataSyncMetaPreferenceKey,
        jsonEncode(checkpoint.toJson()),
      );
      return checkpoint;
    }

    final SyncCheckpoint persisted;
    try {
      persisted = SyncCheckpoint.fromJson(jsonDecode(encoded));
    } catch (_) {
      throw StateError('The data sync metadata is corrupt');
    }
    if (persisted.stateHash == stateHash) return persisted;

    // Legacy void setters are outside the transaction queue. Reconcile them as
    // a new revision before issuing a checkpoint or evaluating transaction CAS.
    final reconciled = SyncCheckpoint(
      revision: persisted.revision + 1,
      stateHash: stateHash,
    );
    await _checkedSet(
      dataSyncMetaPreferenceKey,
      jsonEncode(reconciled.toJson()),
    );
    return reconciled;
  }

  Map<String, Object> _currentDataSyncValues() => {
    'cards': _decodeStoredCards(
      _sharedPreferences.getStringList('cards') ?? const [],
    ).map((card) => card.toJson()).toList(),
    'dictionaries': _decodeStoredDictionaries(
      _sharedPreferences.getStringList('dictionaries') ?? const [],
    ).map((dictionary) => dictionary.toJson()).toList(),
    'keyboard_scripts': _decodeStoredScripts(
      _sharedPreferences.getStringList('keyboard_scripts') ?? const [],
    ).map((script) => script.toJson()).toList(),
    'app_theme': _sharedPreferences.getInt('app_theme') ?? 0,
    'app_theme_color': _sharedPreferences.getInt('app_theme_color') ?? 0,
    'locale': _sharedPreferences.getString('locale') ?? 'en',
    'confirm_delete': _sharedPreferences.getBool('confirm_delete') ?? true,
    'auto_scan_enabled':
        _sharedPreferences.getBool('auto_scan_enabled') ?? true,
    'auto_connect_first_found':
        _sharedPreferences.getBool('auto_connect_first_found') ?? false,
    'device_found_banner':
        _sharedPreferences.getBool('device_found_banner') ?? true,
    'sidebar_auto_expanded':
        _sharedPreferences.getBool('sidebar_auto_expanded') ?? true,
    'sidebar_expanded_index':
        _sharedPreferences.getInt('sidebar_expanded_index') ?? 1,
    'emulation_change_monitoring':
        _sharedPreferences.getBool('emulation_change_monitoring') ?? false,
  };

  Future<SyncTransactionReceipt> _prepareDataSyncTransactionLocked({
    required String transactionId,
    required SyncCheckpoint expectedCheckpoint,
    required Map<String, Object> values,
    required SyncTransactionRole role,
    SyncCheckpoint? peerCheckpoint,
    String? claimedTargetHash,
  }) async {
    if (transactionId.isEmpty || transactionId.length > 128) {
      throw const FormatException('Invalid data sync transaction ID');
    }
    if ((role == SyncTransactionRole.coordinator) != (peerCheckpoint != null)) {
      throw const FormatException('Invalid data sync coordinator identity');
    }
    final stagedValues = _validateDataSyncValues(values);
    final targetHash = _hashDataSyncValues(stagedValues);
    if (claimedTargetHash != null && claimedTargetHash != targetHash) {
      throw const FormatException(
        'Claimed data sync target hash does not match',
      );
    }
    final stored = _findDataSyncReceiptLocked(transactionId);
    if (stored != null) {
      if (stored.targetHash != targetHash) {
        throw StateError('Data sync transaction ID was reused');
      }
      if (_readDataSyncManifestLocked() == null) {
        await _finishTerminalWithoutManifestLocked(stored);
      }
      return stored;
    }

    final active = _readDataSyncManifestLocked();
    if (active != null) {
      if (active.transactionId == transactionId &&
          active.target.stateHash == targetHash) {
        if (active.role != role || active.expected != expectedCheckpoint) {
          throw StateError('Data sync transaction identity does not match');
        }
        _reserveSynchronizedData(transactionId);
        if (active.phase == _DataSyncTransactionPhase.prepared) {
          await _validatePreparedDataSyncManifestLocked(active);
        } else {
          _readValidatedDataSyncStagesLocked(active);
        }
        return SyncTransactionReceipt(
          transactionId: transactionId,
          outcome: active.phase == _DataSyncTransactionPhase.prepared
              ? SyncTransactionOutcome.prepared
              : SyncTransactionOutcome.committed,
          targetHash: targetHash,
          checkpoint: active.phase == _DataSyncTransactionPhase.prepared
              ? active.expected
              : active.target,
        );
      }
      throw StateError('Another data sync transaction is already prepared');
    }

    final epoch = _syncMutationEpoch;
    final current = await _dataSyncCheckpointLocked();
    if (current != expectedCheckpoint || epoch != _syncMutationEpoch) {
      throw SyncCheckpointConflict(expectedCheckpoint, current);
    }
    _reserveSynchronizedData(transactionId);
    final target = SyncCheckpoint(
      revision: current.revision + 1,
      stateHash: targetHash,
    );
    final entries = <_DataSyncStageEntry>[];
    for (var index = 0; index < dataSyncStoredPreferenceKeys.length; index++) {
      final key = dataSyncStoredPreferenceKeys[index];
      final value = stagedValues[key]!;
      entries.add(
        _DataSyncStageEntry(
          key: key,
          stageKey: '$dataSyncTransactionStagePrefix$index',
          valueType: _dataSyncValueType(value),
        ),
      );
    }
    final manifest = _DataSyncManifest(
      transactionId: transactionId,
      phase: _DataSyncTransactionPhase.prepared,
      role: role,
      expected: current,
      target: target,
      entries: entries,
      mutationEpoch: _syncMutationEpoch,
    );

    try {
      for (final entry in entries) {
        await _checkedSet(entry.stageKey, stagedValues[entry.key]!);
      }
      await _checkedSet(
        dataSyncTransactionManifestPreferenceKey,
        jsonEncode(manifest.toJson()),
      );
      if (role == SyncTransactionRole.coordinator) {
        await _checkedSet(
          dataSyncCoordinatorPreferenceKey,
          jsonEncode(
            SyncCoordinatorRecovery(
              transactionId: transactionId,
              targetHash: targetHash,
              decision: SyncCoordinatorDecision.prepared,
              peerCheckpoint: peerCheckpoint!,
            ).toJson(),
          ),
        );
      }
      await _validatePreparedDataSyncManifestLocked(manifest);
    } catch (_) {
      try {
        await _sharedPreferences.reload();
        final persisted = _readDataSyncManifestLocked();
        if (persisted?.transactionId == transactionId) {
          await _abortDataSyncManifestLocked(persisted!);
        } else {
          await _removeDataSyncStagesLocked(entries);
          final coordinator = _readCoordinatorRecoveryLocked();
          if (coordinator?.transactionId == transactionId) {
            await _checkedRemove(dataSyncCoordinatorPreferenceKey);
          }
          _releaseSynchronizedData(transactionId);
        }
      } catch (_) {
        // load() reconciles any journal state that cleanup could not finish.
      }
      rethrow;
    }
    return SyncTransactionReceipt(
      transactionId: transactionId,
      outcome: SyncTransactionOutcome.prepared,
      targetHash: targetHash,
      checkpoint: current,
    );
  }

  Future<SyncTransactionReceipt> _commitDataSyncTransactionLocked(
    String transactionId,
  ) async {
    final stored = _findDataSyncReceiptLocked(transactionId);
    var manifest = _readDataSyncManifestLocked();
    if (manifest == null || manifest.transactionId != transactionId) {
      if (stored != null) {
        if (manifest == null) {
          await _finishTerminalWithoutManifestLocked(stored);
        }
        return stored;
      }
      throw StateError('Data sync transaction is not prepared');
    }
    final coordinatorDecided =
        _coordinatorDecisionLocked(transactionId) ==
        SyncCoordinatorDecision.commitDecided;
    final coordinatorAborted =
        _coordinatorDecisionLocked(transactionId) ==
        SyncCoordinatorDecision.abortDecided;
    if (coordinatorAborted) {
      if (stored?.outcome == SyncTransactionOutcome.aborted) return stored!;
      return _abortDataSyncManifestLocked(manifest);
    }
    _reserveSynchronizedData(transactionId);
    if (stored?.outcome == SyncTransactionOutcome.aborted &&
        manifest.phase == _DataSyncTransactionPhase.prepared &&
        !coordinatorDecided) {
      await _cleanupDataSyncManifestLocked(manifest);
      return stored!;
    }
    if (manifest.phase == _DataSyncTransactionPhase.prepared) {
      final stagedValues = _readValidatedDataSyncStagesLocked(manifest);
      if (!coordinatorDecided) {
        if (manifest.role == SyncTransactionRole.coordinator) {
          final coordinator = _readCoordinatorRecoveryLocked();
          if (coordinator == null ||
              coordinator.transactionId != transactionId ||
              coordinator.targetHash != manifest.target.stateHash) {
            throw StateError('Data sync coordinator record is missing');
          }
          await _checkedSet(
            dataSyncCoordinatorPreferenceKey,
            jsonEncode(
              coordinator
                  .withDecision(SyncCoordinatorDecision.commitDecided)
                  .toJson(),
            ),
          );
        }
      }
      manifest = manifest.withPhase(_DataSyncTransactionPhase.commitDecided);
      await _checkedSet(
        dataSyncTransactionManifestPreferenceKey,
        jsonEncode(manifest.toJson()),
      );
      return _rollForwardDataSyncManifestLocked(
        manifest,
        stagedValues: stagedValues,
      );
    }
    return _rollForwardDataSyncManifestLocked(manifest);
  }

  Future<void> _recoverDataSyncTransactionLocked() async {
    var coordinator = _readCoordinatorRecoveryLocked();
    if (coordinator?.decision == SyncCoordinatorDecision.prepared) {
      coordinator = coordinator!.withDecision(
        SyncCoordinatorDecision.abortDecided,
      );
      await _checkedSet(
        dataSyncCoordinatorPreferenceKey,
        jsonEncode(coordinator.toJson()),
      );
    }
    var manifest = _readDataSyncManifestLocked();
    if (manifest != null) {
      final receipt = _findDataSyncReceiptLocked(manifest.transactionId);
      final coordinatorDecision = _coordinatorDecisionLocked(
        manifest.transactionId,
      );
      if (manifest.phase == _DataSyncTransactionPhase.commitDecided ||
          receipt?.outcome == SyncTransactionOutcome.committed ||
          coordinatorDecision == SyncCoordinatorDecision.commitDecided) {
        if (manifest.phase != _DataSyncTransactionPhase.commitDecided) {
          _readValidatedDataSyncStagesLocked(manifest);
          manifest = manifest.withPhase(
            _DataSyncTransactionPhase.commitDecided,
          );
          await _checkedSet(
            dataSyncTransactionManifestPreferenceKey,
            jsonEncode(manifest.toJson()),
          );
        }
        await _rollForwardDataSyncManifestLocked(manifest);
      } else if (receipt?.outcome == SyncTransactionOutcome.aborted) {
        await _cleanupDataSyncManifestLocked(manifest);
      } else if (manifest.role != SyncTransactionRole.participant) {
        await _abortDataSyncManifestLocked(manifest);
      }
    }
    coordinator = _readCoordinatorRecoveryLocked();
    if (coordinator != null) {
      var receipt = _findDataSyncReceiptLocked(coordinator.transactionId);
      final expectedOutcome =
          coordinator.decision == SyncCoordinatorDecision.commitDecided
          ? SyncTransactionOutcome.committed
          : SyncTransactionOutcome.aborted;
      if (receipt == null &&
          coordinator.decision == SyncCoordinatorDecision.abortDecided) {
        receipt = SyncTransactionReceipt(
          transactionId: coordinator.transactionId,
          outcome: SyncTransactionOutcome.aborted,
          targetHash: coordinator.targetHash,
          checkpoint: await _dataSyncCheckpointLocked(),
        );
        await _saveDataSyncReceiptLocked(receipt);
      }
      if (receipt?.outcome != expectedOutcome) {
        throw StateError('Coordinator decision is not locally durable');
      }
    }
    if (_readDataSyncManifestLocked() == null) {
      final reserved = _reservedDataSyncTransaction;
      final journal =
          _deferredMutationJournal ?? _readDeferredMutationJournalLocked();
      if (journal != null) {
        final receipt = _findDataSyncReceiptLocked(journal.transactionId);
        if (receipt == null) {
          await _finishDeferredWithoutTransactionLocked(journal.transactionId);
        } else if (receipt.outcome == SyncTransactionOutcome.prepared) {
          throw StateError('Deferred mutations have no terminal transaction');
        } else {
          await _finishTerminalWithoutManifestLocked(receipt);
        }
      } else {
        await _removeOrphanDataSyncStagesLocked();
        if (reserved != null) _releaseSynchronizedData(reserved);
      }
    }
  }

  Future<SyncTransactionReceipt> _rollForwardDataSyncManifestLocked(
    _DataSyncManifest manifest, {
    Map<String, Object>? stagedValues,
  }) async {
    if (manifest.phase != _DataSyncTransactionPhase.commitDecided) {
      throw StateError('Data sync transaction has no commit decision');
    }

    final validated =
        stagedValues ?? _readValidatedDataSyncStagesLocked(manifest);

    for (final key in dataSyncStoredPreferenceKeys) {
      await _checkedSet(key, validated[key]!);
    }
    if (_hashDataSyncValues(_currentDataSyncValues()) !=
        manifest.target.stateHash) {
      throw StateError('Data sync roll-forward verification failed');
    }
    await _checkedSet(
      dataSyncMetaPreferenceKey,
      jsonEncode(manifest.target.toJson()),
    );
    final receipt = SyncTransactionReceipt(
      transactionId: manifest.transactionId,
      outcome: SyncTransactionOutcome.committed,
      targetHash: manifest.target.stateHash,
      checkpoint: manifest.target,
    );
    await _saveDataSyncReceiptLocked(receipt);
    _publishCommittedDataSyncValues(validated);

    // Remove the manifest first. A crash can then leave only harmless stages;
    // while the manifest exists, every stage needed for roll-forward remains.
    await _cleanupDataSyncManifestLocked(manifest);
    return receipt;
  }

  Future<SyncTransactionReceipt> _abortDataSyncManifestLocked(
    _DataSyncManifest manifest,
  ) async {
    if (manifest.phase == _DataSyncTransactionPhase.commitDecided ||
        _coordinatorDecisionLocked(manifest.transactionId) ==
            SyncCoordinatorDecision.commitDecided) {
      return _commitDataSyncTransactionLocked(manifest.transactionId);
    }
    final checkpoint = await _dataSyncCheckpointLocked();
    final receipt = SyncTransactionReceipt(
      transactionId: manifest.transactionId,
      outcome: SyncTransactionOutcome.aborted,
      targetHash: manifest.target.stateHash,
      checkpoint: checkpoint,
    );
    await _saveDataSyncReceiptLocked(receipt);
    await _cleanupDataSyncManifestLocked(manifest);
    final coordinator = _readCoordinatorRecoveryLocked();
    if (coordinator?.transactionId == manifest.transactionId &&
        coordinator?.decision != SyncCoordinatorDecision.abortDecided) {
      await _checkedRemove(dataSyncCoordinatorPreferenceKey);
    }
    return receipt;
  }

  Map<String, Object> _readValidatedDataSyncStagesLocked(
    _DataSyncManifest manifest,
  ) {
    final values = <String, Object>{};
    for (final entry in manifest.entries) {
      final value = _sharedPreferences.get(entry.stageKey);
      if (value == null || _dataSyncValueType(value) != entry.valueType) {
        throw StateError('A data sync transaction stage is missing or corrupt');
      }
      values[entry.key] = value is List
          ? List<String>.from(value.cast<String>())
          : value;
    }
    final validated = _validateDataSyncValues(values);
    if (_hashDataSyncValues(validated) != manifest.target.stateHash) {
      throw StateError('Data sync transaction stage hash does not match');
    }
    return validated;
  }

  Future<Map<String, Object>> _validatePreparedDataSyncManifestLocked(
    _DataSyncManifest manifest,
  ) async {
    if (manifest.phase != _DataSyncTransactionPhase.prepared) {
      throw StateError('Data sync transaction is not PREPARED');
    }
    final staged = _readValidatedDataSyncStagesLocked(manifest);
    final epochBeforeCheckpoint = _syncMutationEpoch;
    final current = await _dataSyncCheckpointLocked();
    if (current != manifest.expected) {
      throw SyncCheckpointConflict(manifest.expected, current);
    }
    if (manifest.mutationEpoch != epochBeforeCheckpoint ||
        epochBeforeCheckpoint != _syncMutationEpoch) {
      throw StateError('Prepared data sync mutation epoch does not match');
    }
    return staged;
  }

  Future<void> _finishTerminalWithoutManifestLocked(
    SyncTransactionReceipt receipt,
  ) async {
    if (receipt.outcome == SyncTransactionOutcome.prepared ||
        _readDataSyncManifestLocked() != null) {
      throw StateError(
        'Data sync transaction is not terminal without manifest',
      );
    }
    final persistedJournal = _readDeferredMutationJournalLocked();
    final inMemoryJournal = _deferredMutationJournal;
    if (persistedJournal == null &&
        inMemoryJournal != null &&
        (_pendingDeferredCaptures[receipt.transactionId] ?? 0) == 0) {
      throw StateError('Deferred mutation journal was not durably retained');
    }
    final journal = persistedJournal;
    if (journal != null) {
      if (journal.transactionId != receipt.transactionId) {
        throw StateError(
          'Deferred mutation transaction does not match receipt',
        );
      }
      _reserveSynchronizedData(receipt.transactionId);
      _persistedDeferredMutationJournal = journal;
      await _drainDeferredMutationsLocked(receipt.transactionId);
    }
    await _removeOrphanDataSyncStagesLocked();
    if (journal != null) {
      await _checkedRemove(dataSyncDeferredMutationsPreferenceKey);
      _persistedDeferredMutationJournal = null;
    }
    if (_sharedPreferences.containsKey(
      dataSyncDeferredMutationsPreferenceKey,
    )) {
      throw StateError('Deferred mutation journal cleanup is incomplete');
    }
    final reserved = _reservedDataSyncTransaction;
    if (reserved != null && reserved != receipt.transactionId) {
      throw StateError('Another data sync reservation is active');
    }
    _releaseSynchronizedData(receipt.transactionId);
  }

  Future<void> _cleanupDataSyncManifestLocked(
    _DataSyncManifest manifest,
  ) async {
    await _drainDeferredMutationsLocked(manifest.transactionId);
    await _checkedRemove(dataSyncTransactionManifestPreferenceKey);
    await _removeDataSyncStagesLocked(manifest.entries);
    if (_deferredMutationJournal != null ||
        _sharedPreferences.containsKey(
          dataSyncDeferredMutationsPreferenceKey,
        )) {
      await _checkedRemove(dataSyncDeferredMutationsPreferenceKey);
      _persistedDeferredMutationJournal = null;
    }
    _releaseSynchronizedData(manifest.transactionId);
  }

  SyncCoordinatorRecovery? _readCoordinatorRecoveryLocked() {
    final encoded = _sharedPreferences.getString(
      dataSyncCoordinatorPreferenceKey,
    );
    if (encoded == null) return null;
    try {
      return SyncCoordinatorRecovery.fromJson(jsonDecode(encoded));
    } catch (_) {
      throw StateError('The data sync coordinator record is corrupt');
    }
  }

  SyncCoordinatorDecision? _coordinatorDecisionLocked(String transactionId) {
    final recovery = _readCoordinatorRecoveryLocked();
    return recovery?.transactionId == transactionId ? recovery?.decision : null;
  }

  _DataSyncManifest? _readDataSyncManifestLocked() {
    final encoded = _sharedPreferences.getString(
      dataSyncTransactionManifestPreferenceKey,
    );
    if (encoded == null) return null;
    try {
      return _DataSyncManifest.fromJson(jsonDecode(encoded));
    } catch (_) {
      throw StateError('The data sync transaction manifest is corrupt');
    }
  }

  SyncTransactionReceipt? _findDataSyncReceiptLocked(String transactionId) {
    for (final encoded
        in _sharedPreferences.getStringList(
              dataSyncTransactionReceiptsPreferenceKey,
            ) ??
            const <String>[]) {
      try {
        final receipt = SyncTransactionReceipt.fromJson(jsonDecode(encoded));
        if (receipt.transactionId == transactionId) return receipt;
      } catch (_) {
        throw StateError('The data sync transaction receipts are corrupt');
      }
    }
    return null;
  }

  Future<void> _saveDataSyncReceiptLocked(
    SyncTransactionReceipt receipt,
  ) async {
    final receipts = <SyncTransactionReceipt>[];
    for (final encoded
        in _sharedPreferences.getStringList(
              dataSyncTransactionReceiptsPreferenceKey,
            ) ??
            const <String>[]) {
      final candidate = SyncTransactionReceipt.fromJson(jsonDecode(encoded));
      if (candidate.transactionId != receipt.transactionId) {
        receipts.add(candidate);
      }
    }
    receipts.add(receipt);
    await _checkedSet(
      dataSyncTransactionReceiptsPreferenceKey,
      receipts.map((item) => jsonEncode(item.toJson())).toList(),
    );
  }

  Future<void> _removeDataSyncStagesLocked(
    Iterable<_DataSyncStageEntry> entries,
  ) async {
    for (final entry in entries) {
      await _checkedRemove(entry.stageKey);
    }
  }

  Future<void> _removeOrphanDataSyncStagesLocked() async {
    final orphanStages = _sharedPreferences
        .getKeys()
        .where((key) => key.startsWith(dataSyncTransactionStagePrefix))
        .toList();
    for (final key in orphanStages) {
      await _checkedRemove(key);
    }
  }

  Future<void> _checkedSet(String key, Object value) async {
    final interceptor = debugDataSyncWriteInterceptor;
    try {
      if (interceptor != null &&
          !await Future<bool>.sync(() => interceptor('set', key, value))) {
        return _reconcileFailedSet(key, value);
      }
    } catch (_) {
      return _reconcileFailedSet(key, value);
    }
    bool result;
    try {
      switch (value) {
        case String string:
          result = await _sharedPreferences.setString(key, string);
        case int integer:
          result = await _sharedPreferences.setInt(key, integer);
        case bool boolean:
          result = await _sharedPreferences.setBool(key, boolean);
        case double number:
          result = await _sharedPreferences.setDouble(key, number);
        case List<String> strings:
          result = await _sharedPreferences.setStringList(key, strings);
        default:
          throw ArgumentError.value(value, key, 'Unsupported preference value');
      }
      final resultInterceptor = debugDataSyncResultInterceptor;
      if (resultInterceptor != null) {
        result =
            result &&
            await Future<bool>.sync(() => resultInterceptor('set', key, value));
      }
    } catch (_) {
      return _reconcileFailedSet(key, value);
    }
    if (!result) return _reconcileFailedSet(key, value);
  }

  Future<void> _checkedRemove(String key) async {
    if (!_sharedPreferences.containsKey(key)) return;
    final interceptor = debugDataSyncWriteInterceptor;
    try {
      if (interceptor != null &&
          !await Future<bool>.sync(() => interceptor('remove', key, null))) {
        return _reconcileFailedRemove(key);
      }
    } catch (_) {
      return _reconcileFailedRemove(key);
    }
    bool result;
    try {
      result = await _sharedPreferences.remove(key);
      final resultInterceptor = debugDataSyncResultInterceptor;
      if (resultInterceptor != null) {
        result =
            result &&
            await Future<bool>.sync(
              () => resultInterceptor('remove', key, null),
            );
      }
    } catch (_) {
      return _reconcileFailedRemove(key);
    }
    if (!result) return _reconcileFailedRemove(key);
  }

  Future<void> _reconcileFailedSet(String key, Object value) async {
    await _sharedPreferences.reload();
    if (_preferenceValuesEqual(_sharedPreferences.get(key), value)) return;
    throw SyncPersistenceException('set', key);
  }

  Future<void> _reconcileFailedRemove(String key) async {
    await _sharedPreferences.reload();
    if (!_sharedPreferences.containsKey(key)) return;
    throw SyncPersistenceException('remove', key);
  }
}

enum _DataSyncTransactionPhase { prepared, commitDecided }

class _DataSyncStageEntry {
  final String key;
  final String stageKey;
  final String valueType;

  const _DataSyncStageEntry({
    required this.key,
    required this.stageKey,
    required this.valueType,
  });

  factory _DataSyncStageEntry.fromJson(Object? value) {
    if (value is! Map || value.length != 3) {
      throw const FormatException('Invalid data sync stage entry');
    }
    final key = value['key'];
    final stageKey = value['stageKey'];
    final valueType = value['valueType'];
    if (key is! String ||
        !dataSyncStoredPreferenceKeys.contains(key) ||
        stageKey is! String ||
        !stageKey.startsWith(dataSyncTransactionStagePrefix) ||
        valueType is! String ||
        !const {
          'string',
          'int',
          'bool',
          'double',
          'stringList',
        }.contains(valueType)) {
      throw const FormatException('Invalid data sync stage entry');
    }
    return _DataSyncStageEntry(
      key: key,
      stageKey: stageKey,
      valueType: valueType,
    );
  }

  Map<String, Object> toJson() => {
    'key': key,
    'stageKey': stageKey,
    'valueType': valueType,
  };
}

class _DataSyncManifest {
  final String transactionId;
  final _DataSyncTransactionPhase phase;
  final SyncTransactionRole role;
  final SyncCheckpoint expected;
  final SyncCheckpoint target;
  final List<_DataSyncStageEntry> entries;
  final int mutationEpoch;

  const _DataSyncManifest({
    required this.transactionId,
    required this.phase,
    required this.role,
    required this.expected,
    required this.target,
    required this.entries,
    required this.mutationEpoch,
  });

  factory _DataSyncManifest.fromJson(Object? value) {
    if (value is! Map || value.length != 8) {
      throw const FormatException('Invalid data sync manifest');
    }
    final version = value['version'];
    final transactionId = value['transactionId'];
    final phaseName = value['phase'];
    final roleName = value['role'];
    final rawEntries = value['entries'];
    final mutationEpoch = value['mutationEpoch'];
    if (version != _dataSyncTransactionVersion ||
        transactionId is! String ||
        transactionId.isEmpty ||
        phaseName is! String ||
        roleName is! String ||
        rawEntries is! List ||
        mutationEpoch is! int ||
        mutationEpoch < 0) {
      throw const FormatException('Invalid data sync manifest');
    }
    _DataSyncTransactionPhase? phase;
    for (final candidate in _DataSyncTransactionPhase.values) {
      if (candidate.name == phaseName) phase = candidate;
    }
    SyncTransactionRole? role;
    for (final candidate in SyncTransactionRole.values) {
      if (candidate.name == roleName) role = candidate;
    }
    final entries = rawEntries.map(_DataSyncStageEntry.fromJson).toList();
    if (phase == null ||
        role == null ||
        entries.length != dataSyncStoredPreferenceKeys.length ||
        entries.map((entry) => entry.key).toSet().length != entries.length ||
        !entries
            .map((entry) => entry.key)
            .toSet()
            .containsAll(dataSyncStoredPreferenceKeys) ||
        entries.map((entry) => entry.stageKey).toSet().length !=
            entries.length) {
      throw const FormatException('Invalid data sync manifest');
    }
    return _DataSyncManifest(
      transactionId: transactionId,
      phase: phase,
      role: role,
      expected: SyncCheckpoint.fromJson(value['expected']),
      target: SyncCheckpoint.fromJson(value['target']),
      entries: List.unmodifiable(entries),
      mutationEpoch: mutationEpoch,
    );
  }

  _DataSyncManifest withPhase(_DataSyncTransactionPhase value) =>
      _DataSyncManifest(
        transactionId: transactionId,
        phase: value,
        role: role,
        expected: expected,
        target: target,
        entries: entries,
        mutationEpoch: mutationEpoch,
      );

  Map<String, Object> toJson() => {
    'version': _dataSyncTransactionVersion,
    'transactionId': transactionId,
    'phase': phase.name,
    'role': role.name,
    'expected': expected.toJson(),
    'target': target.toJson(),
    'entries': entries.map((entry) => entry.toJson()).toList(),
    'mutationEpoch': mutationEpoch,
  };
}

Map<String, Object> _validateDataSyncValues(Map<String, Object> values) {
  if (values.length != dataSyncStoredPreferenceKeys.length ||
      !values.keys.toSet().containsAll(dataSyncStoredPreferenceKeys)) {
    throw const FormatException('Data sync transaction has invalid keys');
  }

  List<String> stringList(String key) {
    final value = values[key];
    if (value is! List<String>) {
      throw FormatException('Invalid data sync value for $key');
    }
    return value;
  }

  int integer(String key, int min, int max) {
    final value = values[key];
    if (value is! int || value < min || value > max) {
      throw FormatException('Invalid data sync value for $key');
    }
    return value;
  }

  bool boolean(String key) {
    final value = values[key];
    if (value is! bool) {
      throw FormatException('Invalid data sync value for $key');
    }
    return value;
  }

  final cardModels = stringList('cards').map(CardSave.fromJson).toList();
  for (final card in cardModels) {
    validateCardSaveSemantics(card);
  }
  final cards = cardModels.map((card) => card.toJson()).toList();
  final dictionaryModels = stringList(
    'dictionaries',
  ).map(Dictionary.fromJson).toList();
  for (final dictionary in dictionaryModels) {
    _validateStoredDictionary(dictionary);
  }
  final dictionaries = dictionaryModels
      .map((dictionary) => dictionary.toJson())
      .toList();
  final scripts =
      stringList('keyboard_scripts').map(SavedKeyboardScript.fromJson).toList()
        ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  final localeValue = values['locale'];
  if (localeValue is! String || localeValue.isEmpty) {
    throw const FormatException('Invalid data sync value for locale');
  }
  final localeParts = localeValue.split('-');
  if (localeParts.isEmpty || localeParts.length > 2) {
    throw const FormatException('Invalid data sync value for locale');
  }
  final locale = localeParts.length == 1
      ? Locale(localeParts.single)
      : Locale(localeParts[0], localeParts[1]);
  if (!AppLocalizations.supportedLocales.contains(locale)) {
    throw const FormatException('Invalid data sync value for locale');
  }

  return {
    'cards': cards,
    'dictionaries': dictionaries,
    'keyboard_scripts': scripts.map((script) => script.toJson()).toList(),
    'app_theme': integer('app_theme', 0, ThemeMode.values.length - 1),
    'app_theme_color': integer('app_theme_color', 0, 7),
    'locale': locale.toLanguageTag(),
    'confirm_delete': boolean('confirm_delete'),
    'auto_scan_enabled': boolean('auto_scan_enabled'),
    'auto_connect_first_found': boolean('auto_connect_first_found'),
    'device_found_banner': boolean('device_found_banner'),
    'sidebar_auto_expanded': boolean('sidebar_auto_expanded'),
    'sidebar_expanded_index': integer('sidebar_expanded_index', 0, 2),
    'emulation_change_monitoring': boolean('emulation_change_monitoring'),
  };
}

String _hashDataSyncValues(Map<String, Object> values) {
  final canonical = <String, Object>{
    for (final key in dataSyncStoredPreferenceKeys) key: values[key]!,
  };
  return sha256.convert(utf8.encode(jsonEncode(canonical))).toString();
}

String _dataSyncValueType(Object value) => switch (value) {
  String() => 'string',
  int() => 'int',
  bool() => 'bool',
  double() => 'double',
  List<String>() => 'stringList',
  _ => throw ArgumentError.value(value, 'value'),
};

bool _isSha256(String value) =>
    value.length == 64 && RegExp(r'^[0-9a-f]{64}$').hasMatch(value);

bool _preferenceValuesEqual(Object? actual, Object expected) {
  if (actual is List && expected is List) {
    if (actual.length != expected.length) return false;
    for (var index = 0; index < actual.length; index++) {
      if (actual[index] != expected[index]) return false;
    }
    return true;
  }
  return actual == expected;
}

Object _copyDataSyncPreferenceValue(Object value) =>
    value is List ? List<String>.unmodifiable(value.cast<String>()) : value;

List<CardSave> _decodeStoredCards(List<String> encodedCards) {
  final cards = <CardSave>[];
  for (final encoded in encodedCards) {
    try {
      cards.add(CardSave.fromJson(encoded));
    } catch (_) {
      // Preserve valid cards if one persisted record is corrupt.
    }
  }
  return cards;
}

List<Dictionary> _decodeStoredDictionaries(List<String> encodedDictionaries) {
  final dictionaries = <Dictionary>[];
  for (final encoded in encodedDictionaries) {
    try {
      dictionaries.add(Dictionary.fromJson(encoded));
    } catch (_) {
      // Preserve valid dictionaries if one persisted record is corrupt.
    }
  }
  return dictionaries;
}

List<SavedKeyboardScript> _decodeStoredScripts(List<String> encodedScripts) {
  final scripts = <SavedKeyboardScript>[];
  for (final encoded in encodedScripts) {
    try {
      scripts.add(SavedKeyboardScript.fromJson(encoded));
    } catch (_) {
      // Preserve valid scripts if one persisted record is corrupt.
    }
  }
  scripts.sort((left, right) => right.updatedAt.compareTo(left.updatedAt));
  return scripts;
}

void validateCardSaveSemantics(CardSave card) {
  if (card.sak < 0 ||
      card.sak > 0xff ||
      (card.atqa.isNotEmpty && card.atqa.length != 2) ||
      card.ats.length > 20) {
    throw const FormatException('Invalid card identity metadata');
  }
  final uidBytes = _storedCardUidBytes(card.tag);
  final normalizedUid = card.uid.replaceAll(RegExp(r'\s+'), '').toUpperCase();
  if (uidBytes != null &&
      (normalizedUid.length.isOdd ||
          !RegExp(r'^[0-9A-F]+$').hasMatch(normalizedUid) ||
          !uidBytes.contains(normalizedUid.length ~/ 2))) {
    throw const FormatException('Invalid card UID width');
  }
  if (card.tag == TagType.hidProx) {
    final formatType = int.parse(normalizedUid.substring(0, 2), radix: 16);
    if (formatType < 1 || formatType > 30) {
      throw const FormatException('Invalid HID format type');
    }
  }
  final classicBlocks = switch (card.tag) {
    TagType.mifareMini => 20,
    // EV1 recovery stores the additional two sectors as blocks 64..71.
    TagType.mifare1K => 72,
    TagType.mifare2K => 128,
    TagType.mifare4K => 256,
    _ => null,
  };
  if (classicBlocks != null) {
    if (card.data.length > 256) {
      throw const FormatException('Invalid MIFARE Classic card geometry');
    }
    for (var index = 0; index < card.data.length; index++) {
      final block = card.data[index];
      if (block.isNotEmpty && (block.length != 16 || index >= classicBlocks)) {
        throw const FormatException('Invalid MIFARE Classic card geometry');
      }
    }
    return;
  }
  final pageCount = _storedUltralightPageCount(card.tag);
  if (pageCount != null) {
    if (card.data.length > pageCount ||
        card.data.any((page) => page.isNotEmpty && page.length != 4)) {
      throw const FormatException('Invalid MIFARE Ultralight page geometry');
    }
    final version = card.extraData.ultralightVersion;
    final signature = card.extraData.ultralightSignature;
    final counters = card.extraData.ultralightCounters;
    final counterCount = _storedUltralightCounterCount(card.tag);
    if ((version.isNotEmpty && version.length != 8) ||
        (signature.isNotEmpty && signature.length != 32) ||
        (counters.isNotEmpty && counters.length != counterCount) ||
        counters.any((counter) => counter < 0 || counter > 0xffffff)) {
      throw const FormatException('Invalid MIFARE Ultralight metadata');
    }
    return;
  }
  if (card.extraData.ultralightVersion.isNotEmpty ||
      card.extraData.ultralightSignature.isNotEmpty ||
      card.extraData.ultralightCounters.isNotEmpty) {
    throw const FormatException('Unexpected MIFARE Ultralight metadata');
  }
  if (_isStoredLfTag(card.tag) && card.data.isNotEmpty) {
    throw const FormatException('LF cards cannot contain HF block data');
  }
}

Set<int>? _storedCardUidBytes(TagType tag) => switch (tag) {
  TagType.mifareMini ||
  TagType.mifare1K ||
  TagType.mifare2K ||
  TagType.mifare4K ||
  TagType.ntag210 ||
  TagType.ntag212 ||
  TagType.ntag213 ||
  TagType.ntag215 ||
  TagType.ntag216 ||
  TagType.ultralight ||
  TagType.ultralightC ||
  TagType.ultralight11 ||
  TagType.ultralight21 ||
  TagType.hf14a4 => const {4, 7, 10},
  TagType.em410X ||
  TagType.em410X16 ||
  TagType.em410X32 ||
  TagType.em410X64 => const {5},
  TagType.em410XElectra => const {13},
  TagType.hidProx => const {13},
  TagType.viking => const {4},
  TagType.pac => const {8},
  TagType.ioProx => const {16},
  TagType.idteck => const {8},
  _ => null,
};

int? _storedUltralightPageCount(TagType tag) => switch (tag) {
  TagType.ultralight => 16,
  TagType.ultralightC => 48,
  TagType.ultralight11 || TagType.ntag210 => 20,
  TagType.ultralight21 || TagType.ntag212 => 41,
  TagType.ntag213 => 45,
  TagType.ntag215 => 135,
  TagType.ntag216 => 231,
  _ => null,
};

int _storedUltralightCounterCount(TagType tag) => switch (tag) {
  TagType.ultralight11 || TagType.ultralight21 => 3,
  TagType.ntag210 ||
  TagType.ntag212 ||
  TagType.ntag213 ||
  TagType.ntag215 ||
  TagType.ntag216 => 1,
  _ => 0,
};

bool _isStoredLfTag(TagType tag) => switch (tag) {
  TagType.em410X ||
  TagType.em410X16 ||
  TagType.em410X32 ||
  TagType.em410X64 ||
  TagType.em410XElectra ||
  TagType.hidProx ||
  TagType.viking ||
  TagType.pac ||
  TagType.ioProx ||
  TagType.idteck => true,
  _ => false,
};

void _validateStoredDictionary(Dictionary dictionary) {
  if (!const {0, 8, 12, 32}.contains(dictionary.keyLength) ||
      (dictionary.keys.isNotEmpty && dictionary.keyLength == 0) ||
      dictionary.keys.any((key) => key.length * 2 != dictionary.keyLength)) {
    throw const FormatException('Invalid dictionary key length');
  }
}

Map<String, Object> _validateLegacySettings(Object? value) {
  if (value is! Map<String, dynamic>) {
    throw const FormatException('Invalid settings backup values');
  }

  final settings = <String, Object>{};
  for (final entry in value.entries) {
    final key = entry.key;
    final setting = entry.value;
    if (_legacyBooleanSettingKeys.contains(key)) {
      if (setting is! bool) {
        throw FormatException('Invalid settings backup value: $key');
      }
      settings[key] = setting;
      continue;
    }

    switch (key) {
      case 'app_theme':
        if (setting is! int ||
            setting < 0 ||
            setting >= ThemeMode.values.length) {
          throw FormatException('Invalid settings backup value: $key');
        }
        settings[key] = setting;
      case 'app_theme_color':
        if (setting is! int || setting < 0 || setting > 7) {
          throw FormatException('Invalid settings backup value: $key');
        }
        settings[key] = setting;
      case 'locale':
        if (setting is! String ||
            !AppLocalizations.supportedLocales
                .map((locale) => locale.toLanguageTag())
                .contains(setting)) {
          throw FormatException('Invalid settings backup value: $key');
        }
        settings[key] = setting;
      case 'sidebar_expanded_index':
        if (setting is! int || setting < 0 || setting > 2) {
          throw FormatException('Invalid settings backup value: $key');
        }
        settings[key] = setting;
      default:
        throw FormatException('Unknown settings backup key: $key');
    }
  }
  return settings;
}

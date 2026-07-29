import 'dart:convert';

import 'package:chameleonultragui/helpers/data_sync.dart';
import 'package:chameleonultragui/helpers/saved_keyboard_script.dart';
import 'package:chameleonultragui/helpers/data_sync_transport.dart';
import 'package:chameleonultragui/generated/i18n/app_localizations.dart';
import 'package:chameleonultragui/sharedprefsprovider.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

const Set<String> dataSyncSafeSettingKeys = {
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
};

extension DataSyncStorage on SharedPreferencesProvider {
  Future<SyncState> createSyncState() {
    return withDataSyncCheckpoint(
      (checkpoint) =>
          SyncState(snapshot: _createSyncSnapshot(), checkpoint: checkpoint),
    );
  }

  SyncSnapshot _createSyncSnapshot() => SyncSnapshot(
    cards: _uniqueCards(getCards()),
    dictionaries: _uniqueDictionaries(getDictionaries()),
    keyboardScripts: _uniqueScripts(getKeyboardScripts()),
    settings: {
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
    },
  );

  Future<SyncTransactionReceipt> applySyncSnapshot(
    SyncSnapshot snapshot, {
    required SyncCheckpoint expectedCheckpoint,
    String? transactionId,
  }) async {
    final receipt = await applyDataSyncValues(
      transactionId: transactionId ?? const Uuid().v4(),
      expectedCheckpoint: expectedCheckpoint,
      values: _validatedSyncValues(snapshot),
    );
    if (receipt.outcome != SyncTransactionOutcome.committed) {
      throw StateError('Data sync transaction did not commit');
    }
    notifyDataSyncCommitted();
    return receipt;
  }

  Future<SyncTransactionReceipt> prepareSyncSnapshot(
    String transactionId,
    SyncSnapshot snapshot, {
    required SyncCheckpoint expectedCheckpoint,
    SyncTransactionRole role = SyncTransactionRole.participant,
    SyncCheckpoint? peerCheckpoint,
    String? claimedTargetHash,
  }) {
    return prepareDataSyncValues(
      transactionId: transactionId,
      expectedCheckpoint: expectedCheckpoint,
      values: _validatedSyncValues(snapshot),
      role: role,
      peerCheckpoint: peerCheckpoint,
      claimedTargetHash: claimedTargetHash,
    );
  }

  Future<SyncTransactionReceipt> commitSyncSnapshot(
    String transactionId,
  ) async {
    final receipt = await commitDataSyncTransaction(transactionId);
    if (receipt.outcome == SyncTransactionOutcome.committed) {
      notifyDataSyncCommitted();
    }
    return receipt;
  }

  Map<String, Object> _validatedSyncValues(SyncSnapshot snapshot) {
    if (snapshot.settings.keys.toSet().length !=
            dataSyncSafeSettingKeys.length ||
        !snapshot.settings.keys.toSet().containsAll(dataSyncSafeSettingKeys)) {
      throw const FormatException(
        'Sync snapshot has missing or unsafe settings',
      );
    }
    final settings = snapshot.settings;
    final theme = _syncInt(
      settings,
      'app_theme',
      0,
      ThemeMode.values.length - 1,
    );
    final themeColor = _syncInt(settings, 'app_theme_color', 0, 7);
    final locale = _syncString(settings, 'locale', 32);
    final parsedLocale = _parseLocale(locale);
    if (!AppLocalizations.supportedLocales.contains(parsedLocale)) {
      throw const FormatException('Unsupported locale in sync snapshot');
    }
    final sidebarIndex = _syncInt(settings, 'sidebar_expanded_index', 0, 2);
    final confirmDelete = _syncBool(settings, 'confirm_delete');
    final autoScan = _syncBool(settings, 'auto_scan_enabled');
    final autoConnect = _syncBool(settings, 'auto_connect_first_found');
    final deviceBanner = _syncBool(settings, 'device_found_banner');
    final sidebarAuto = _syncBool(settings, 'sidebar_auto_expanded');
    final monitor = _syncBool(settings, 'emulation_change_monitoring');

    final scripts = snapshot.keyboardScripts.toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return {
      'cards': snapshot.cards.map((card) => card.toJson()).toList(),
      'dictionaries': snapshot.dictionaries
          .map((dictionary) => dictionary.toJson())
          .toList(),
      'keyboard_scripts': scripts.map((script) => script.toJson()).toList(),
      'app_theme': theme,
      'app_theme_color': themeColor,
      'locale': parsedLocale.toLanguageTag(),
      'confirm_delete': confirmDelete,
      'auto_scan_enabled': autoScan,
      'auto_connect_first_found': autoConnect,
      'device_found_banner': deviceBanner,
      'sidebar_auto_expanded': sidebarAuto,
      'sidebar_expanded_index': sidebarIndex,
      'emulation_change_monitoring': monitor,
    };
  }
}

class SharedPreferencesDataSyncParticipant
    implements DataSyncTransactionParticipant {
  final SharedPreferencesProvider preferences;

  const SharedPreferencesDataSyncParticipant(this.preferences);

  @override
  Future<SyncTransactionReceipt> prepare(
    String transactionId,
    SyncSnapshot snapshot,
    SyncCheckpoint expectedCheckpoint, {
    SyncTransactionRole role = SyncTransactionRole.participant,
    SyncCheckpoint? peerCheckpoint,
    String? claimedTargetHash,
  }) => preferences.prepareSyncSnapshot(
    transactionId,
    snapshot,
    expectedCheckpoint: expectedCheckpoint,
    role: role,
    peerCheckpoint: peerCheckpoint,
    claimedTargetHash: claimedTargetHash,
  );

  @override
  Future<SyncTransactionReceipt> commit(String transactionId) =>
      preferences.commitSyncSnapshot(transactionId);

  @override
  Future<SyncTransactionReceipt> abortFromCoordinator(
    String transactionId,
    String targetHash,
  ) => preferences.abortDataSyncParticipantFromCoordinator(
    transactionId,
    targetHash,
  );

  @override
  Future<SyncTransactionReceipt> reject(
    String transactionId,
    String targetHash,
  ) => preferences.recordDataSyncAbort(transactionId, targetHash);

  @override
  Future<SyncTransactionReceipt?> query(String transactionId) =>
      preferences.getDataSyncTransactionReceipt(transactionId);

  @override
  Future<SyncCoordinatorRecovery?> coordinatorRecovery() =>
      preferences.getDataSyncCoordinatorRecovery();

  @override
  Future<SyncCoordinatorRecovery> decideCoordinatorAbort(
    String transactionId,
  ) => preferences.decideDataSyncCoordinatorAbort(transactionId);

  @override
  Future<void> completeCoordinator(String transactionId) =>
      preferences.completeDataSyncCoordinator(transactionId);

  @override
  Future<SyncTransactionReceipt?> pendingParticipant() =>
      preferences.getPendingDataSyncParticipant();
}

bool _syncBool(Map<String, Object> settings, String key) {
  final value = settings[key];
  if (value is! bool) throw FormatException('Invalid sync setting: $key');
  return value;
}

int _syncInt(Map<String, Object> settings, String key, int min, int max) {
  final value = settings[key];
  if (value is! int || value < min || value > max) {
    throw FormatException('Invalid sync setting: $key');
  }
  return value;
}

String _syncString(Map<String, Object> settings, String key, int maxLength) {
  final value = settings[key];
  if (value is! String || value.isEmpty || value.length > maxLength) {
    throw FormatException('Invalid sync setting: $key');
  }
  return value;
}

Locale _parseLocale(String value) {
  final parts = value.split('-');
  if (parts.length == 1) return Locale(parts.single);
  if (parts.length == 2) return Locale(parts[0], parts[1]);
  throw const FormatException('Invalid locale in sync snapshot');
}

List<CardSave> _uniqueCards(List<CardSave> cards) {
  final seen = <String, String>{};
  final result = <CardSave>[];
  for (final card in cards) {
    final encoded = card.toJson();
    final previous = seen[card.id];
    if (previous == encoded) continue;
    if (previous == null) {
      seen[card.id] = encoded;
      result.add(card);
      continue;
    }
    final data = jsonDecode(encoded) as Map<String, dynamic>;
    data['id'] = _stableDuplicateId(card.id, encoded);
    final normalized = CardSave.fromJson(jsonEncode(data));
    seen[normalized.id] = normalized.toJson();
    result.add(normalized);
  }
  return result;
}

List<Dictionary> _uniqueDictionaries(List<Dictionary> dictionaries) {
  final seen = <String, String>{};
  final result = <Dictionary>[];
  for (final dictionary in dictionaries) {
    final encoded = dictionary.toJson();
    final previous = seen[dictionary.id];
    if (previous == encoded) continue;
    if (previous == null) {
      seen[dictionary.id] = encoded;
      result.add(dictionary);
      continue;
    }
    final data = jsonDecode(encoded) as Map<String, dynamic>;
    data['id'] = _stableDuplicateId(dictionary.id, encoded);
    final normalized = Dictionary.fromJson(jsonEncode(data));
    seen[normalized.id] = normalized.toJson();
    result.add(normalized);
  }
  return result;
}

List<SavedKeyboardScript> _uniqueScripts(List<SavedKeyboardScript> scripts) {
  final seen = <String, String>{};
  final result = <SavedKeyboardScript>[];
  for (final script in scripts) {
    final encoded = script.toJson();
    final previous = seen[script.id];
    if (previous == encoded) continue;
    if (previous == null) {
      seen[script.id] = encoded;
      result.add(script);
      continue;
    }
    final normalized = SavedKeyboardScript.compile(
      id: _stableDuplicateId(script.id, encoded),
      name: script.name,
      source: script.source,
      layout: script.layout,
      output: script.output,
      updatedAt: script.updatedAt,
    );
    seen[normalized.id] = normalized.toJson();
    result.add(normalized);
  }
  return result;
}

String _stableDuplicateId(String base, String encoded) =>
    '$base-sync-${sha256.convert(utf8.encode(encoded)).toString().substring(0, 16)}';

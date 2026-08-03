import 'dart:convert';
import 'dart:typed_data';

import 'package:chameleonultragui/bridge/chameleon_keyboard.dart';
import 'package:chameleonultragui/helpers/data_sync.dart';
import 'package:chameleonultragui/helpers/data_sync_storage.dart';
import 'package:chameleonultragui/helpers/definitions.dart';
import 'package:chameleonultragui/helpers/keyboard_layout.dart';
import 'package:chameleonultragui/helpers/saved_keyboard_script.dart';
import 'package:chameleonultragui/sharedprefsprovider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SharedPreferencesProvider preferences;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    preferences = SharedPreferencesProvider();
    preferences.debugDataSyncWriteInterceptor = null;
    preferences.debugDataSyncResultInterceptor = null;
    await preferences.load();
  });

  test('snapshot includes libraries and only safe GUI settings', () async {
    preferences.setDebugMode(true);
    preferences.setEthicalHackingAck(true);
    await preferences.setTheme(ThemeMode.dark);
    await preferences.setLocale(const Locale('es'));

    final state = await preferences.createSyncState();
    final snapshot = state.snapshot;

    expect(snapshot.settings.keys.toSet(), dataSyncSafeSettingKeys);
    expect(snapshot.settings['app_theme'], ThemeMode.dark.index);
    expect(snapshot.settings['locale'], 'es');
    expect(snapshot.settings, isNot(contains('debug')));
    expect(snapshot.settings, isNot(contains('ethical_hacking_ack')));
  });

  test('snapshot round trips card and dictionary folder trees', () async {
    final cardFolder = CardFolder(id: 'cards-root', name: 'Card root');
    final cardChild = CardFolder(
      id: 'cards-child',
      name: 'Card child',
      parentId: cardFolder.id,
    );
    final dictionaryFolder = DictionaryFolder(
      id: 'dictionary-root',
      name: 'Dictionary root',
    );
    await preferences.setCardFolders([cardFolder, cardChild]);
    await preferences.setDictionaryFolders([dictionaryFolder]);
    await preferences.setCards([
      _card('folder-card', 'Folder card')..folderId = cardChild.id,
    ]);
    await preferences.setDictionaries([
      Dictionary(
        id: 'folder-dictionary',
        name: 'Folder dictionary',
        keyLength: 12,
        folderId: dictionaryFolder.id,
      ),
    ]);

    final source = await preferences.createSyncState();
    await preferences.setCards(const []);
    await preferences.setDictionaries(const []);
    await preferences.setCardFolders(const []);
    await preferences.setDictionaryFolders(const []);
    final emptyCheckpoint = await preferences.getDataSyncCheckpoint();

    await preferences.applySyncSnapshot(
      source.snapshot,
      expectedCheckpoint: emptyCheckpoint,
    );

    expect(preferences.getCardFolders().map((folder) => folder.id), [
      'cards-root',
      'cards-child',
    ]);
    expect(preferences.getCards().single.folderId, 'cards-child');
    expect(preferences.getDictionaryFolders().single.id, 'dictionary-root');
    expect(preferences.getDictionaries().single.folderId, 'dictionary-root');
  });

  test(
    'apply updates allowlisted settings and rejects unknown settings',
    () async {
      final source = await preferences.createSyncState();
      final updated = SyncSnapshot(
        settings: {
          ...source.snapshot.settings,
          'app_theme': ThemeMode.dark.index,
          'locale': 'fr',
          'confirm_delete': false,
        },
      );

      await preferences.applySyncSnapshot(
        updated,
        expectedCheckpoint: source.checkpoint,
      );

      expect(preferences.getTheme(), ThemeMode.dark);
      expect(preferences.getLocaleString(), 'fr');
      expect(preferences.getConfirmDelete(), isFalse);
      await expectLater(
        preferences.applySyncSnapshot(
          SyncSnapshot(settings: {...source.snapshot.settings, 'debug': true}),
          expectedCheckpoint: source.checkpoint,
        ),
        throwsFormatException,
      );
    },
  );

  test('invalid setting types are rejected before journal writes', () async {
    await preferences.setTheme(ThemeMode.light);
    final source = await preferences.createSyncState();
    final invalid = SyncSnapshot(
      settings: {...source.snapshot.settings, 'app_theme': 'dark'},
    );

    await expectLater(
      preferences.applySyncSnapshot(
        invalid,
        expectedCheckpoint: source.checkpoint,
      ),
      throwsFormatException,
    );
    expect(preferences.getTheme(), ThemeMode.light);
    final raw = await SharedPreferences.getInstance();
    expect(raw.containsKey(dataSyncTransactionManifestPreferenceKey), isFalse);
  });

  test(
    'legacy duplicate IDs are normalized deterministically for sync',
    () async {
      await preferences.setDictionaries([
        Dictionary(
          id: 'duplicate',
          name: 'First',
          keys: [
            Uint8List.fromList([1, 2, 3, 4, 5, 6]),
          ],
          keyLength: 12,
        ),
        Dictionary(
          id: 'duplicate',
          name: 'Second',
          keys: [
            Uint8List.fromList([6, 5, 4, 3, 2, 1]),
          ],
          keyLength: 12,
        ),
      ]);

      final first = (await preferences.createSyncState()).snapshot;
      final second = (await preferences.createSyncState()).snapshot;

      expect(first.dictionaries, hasLength(2));
      expect(first.dictionaries.map((item) => item.id).toSet(), hasLength(2));
      expect(
        first.dictionaries.map((item) => item.id),
        second.dictionaries.map((item) => item.id),
      );
    },
  );

  test(
    'apply preserves spaced UID and trailing Classic placeholders',
    () async {
      final source = await preferences.createSyncState();
      final blocks = List<Uint8List>.generate(
        256,
        (index) => index < 4 ? Uint8List(16) : Uint8List(0),
      );
      final target = SyncSnapshot(
        cards: [
          CardSave(
            id: 'saved-classic',
            uid: '01 02 03 04',
            name: 'Saved recovery',
            tag: TagType.mifare1K,
            data: blocks,
          ),
        ],
        settings: source.snapshot.settings,
      );

      await preferences.applySyncSnapshot(
        target,
        expectedCheckpoint: source.checkpoint,
      );

      final saved = preferences.getCards().single;
      expect(saved.uid, '01 02 03 04');
      expect(saved.data, hasLength(256));
      expect(saved.data.last, isEmpty);
    },
  );

  test('deferred add preserves records introduced by sync', () async {
    final a = _card('a', 'A');
    final b = _card('b', 'B');
    final c = _card('c', 'C');
    await preferences.setCards([a]);
    final source = await preferences.createSyncState();
    final target = SyncSnapshot(
      cards: [a, b],
      settings: source.snapshot.settings,
    );
    await preferences.prepareSyncSnapshot(
      'records-a-b-c',
      target,
      expectedCheckpoint: source.checkpoint,
    );

    await preferences.setCards([...preferences.getCards(), c]);
    expect(preferences.getCards().map((card) => card.id), ['a', 'c']);
    expect(
      (await SharedPreferences.getInstance()).containsKey(
        dataSyncDeferredMutationsPreferenceKey,
      ),
      isTrue,
    );
    await preferences.commitDataSyncTransaction('records-a-b-c');

    expect(preferences.getCards().map((card) => card.id).toSet(), {
      'a',
      'b',
      'c',
    });
  });

  test(
    'two awaited deferred record adds compose through the overlay',
    () async {
      final a = _card('a', 'A');
      await preferences.setCards([a]);
      final source = await preferences.createSyncState();
      await preferences.prepareSyncSnapshot(
        'two-record-adds',
        source.snapshot,
        expectedCheckpoint: source.checkpoint,
      );

      await preferences.setCards([...preferences.getCards(), _card('c', 'C')]);
      await preferences.setCards([...preferences.getCards(), _card('d', 'D')]);
      await preferences.commitDataSyncTransaction('two-record-adds');

      expect(preferences.getCards().map((card) => card.id), ['a', 'c', 'd']);
    },
  );

  test(
    'back-to-back deferred adds from one snapshot compose synchronously',
    () async {
      final a = _card('a', 'A');
      final b = _card('b', 'B');
      final c = _card('c', 'C');
      await preferences.setCards([a]);
      final source = await preferences.createSyncState();
      await preferences.prepareSyncSnapshot(
        'back-to-back-adds',
        source.snapshot,
        expectedCheckpoint: source.checkpoint,
      );
      final sameSnapshot = preferences.getCards();

      final addB = preferences.setCards([...sameSnapshot, b]);
      final addC = preferences.setCards([...sameSnapshot, c]);

      expect(preferences.getCards().map((card) => card.id).toSet(), {
        'a',
        'b',
        'c',
      });
      await Future.wait([addB, addC]);
      await preferences.commitDataSyncTransaction('back-to-back-adds');
      expect(preferences.getCards().map((card) => card.id).toSet(), {
        'a',
        'b',
        'c',
      });
    },
  );

  test(
    'mutation invoked during roll-forward is replayed after target commit',
    () async {
      final a = _card('a', 'A');
      final b = _card('b', 'B');
      final c = _card('c', 'C');
      await preferences.setCards([a]);
      final source = await preferences.createSyncState();
      await preferences.prepareSyncSnapshot(
        'mutation-during-roll-forward',
        SyncSnapshot(cards: [a, b], settings: source.snapshot.settings),
        expectedCheckpoint: source.checkpoint,
      );
      Future<void>? mutation;
      var injected = false;
      preferences.debugDataSyncWriteInterceptor = (operation, key, value) {
        if (!injected && operation == 'set' && key == 'cards') {
          injected = true;
          mutation = preferences.setCards([...preferences.getCards(), c]);
          expect(preferences.getCards().map((card) => card.id).toSet(), {
            'a',
            'c',
          });
        }
        return true;
      };

      await preferences.commitDataSyncTransaction(
        'mutation-during-roll-forward',
      );
      await mutation;
      preferences.debugDataSyncWriteInterceptor = null;

      expect(injected, isTrue);
      expect(preferences.getCards().map((card) => card.id).toSet(), {
        'a',
        'b',
        'c',
      });
    },
  );

  test(
    'authenticated ABORT replays records against the pre-sync state',
    () async {
      final a = _card('a', 'A');
      final b = _card('b', 'B');
      final c = _card('c', 'C');
      await preferences.setCards([a]);
      final source = await preferences.createSyncState();
      final prepared = await preferences.prepareSyncSnapshot(
        'record-abort',
        SyncSnapshot(cards: [a, b], settings: source.snapshot.settings),
        expectedCheckpoint: source.checkpoint,
      );
      await preferences.setCards([...preferences.getCards(), c]);

      await preferences.abortDataSyncParticipantFromCoordinator(
        'record-abort',
        prepared.targetHash,
      );

      expect(preferences.getCards().map((card) => card.id), ['a', 'c']);
    },
  );

  test('deferred record remove and edit preserve sync additions', () async {
    final a = _card('a', 'A');
    final x = _card('x', 'X');
    final b = _card('b', 'B');
    await preferences.setCards([a, x]);
    final source = await preferences.createSyncState();
    final target = SyncSnapshot(
      cards: [a, b, _card('x', 'X from sync')],
      settings: source.snapshot.settings,
    );
    await preferences.prepareSyncSnapshot(
      'record-remove-edit',
      target,
      expectedCheckpoint: source.checkpoint,
    );

    await preferences.setCards([_card('x', 'X edited locally')]);
    await preferences.commitDataSyncTransaction('record-remove-edit');

    final cards = {for (final card in preferences.getCards()) card.id: card};
    expect(cards.keys, {'b', 'x'});
    expect(cards['x']?.name, 'X edited locally');
  });

  test('restart before outcome reconstructs durable record overlay', () async {
    final a = _card('a', 'A');
    await preferences.setCards([a]);
    final source = await preferences.createSyncState();
    await preferences.prepareSyncSnapshot(
      'record-intent-restart',
      source.snapshot,
      expectedCheckpoint: source.checkpoint,
    );
    await preferences.setCards([...preferences.getCards(), _card('c', 'C')]);

    await preferences.load();

    expect(preferences.getCards().map((card) => card.id), ['a', 'c']);
    await preferences.commitDataSyncTransaction('record-intent-restart');
    expect(preferences.getCards().map((card) => card.id), ['a', 'c']);
  });

  test(
    'restart replays a durable deferred journal without a transaction',
    () async {
      final raw = await SharedPreferences.getInstance();
      await raw.setString(
        dataSyncDeferredMutationsPreferenceKey,
        jsonEncode({
          'version': 1,
          'transactionId': 'failed-prepare-intent',
          'nextSequence': 1,
          'operations': [
            {
              'sequence': 0,
              'kind': 'scalar',
              'key': 'app_theme',
              'value': ThemeMode.dark.index,
            },
          ],
        }),
      );

      await preferences.load();

      expect(preferences.getTheme(), ThemeMode.dark);
      expect(raw.containsKey(dataSyncDeferredMutationsPreferenceKey), isFalse);
    },
  );

  test(
    'reentrant scalar setters retain queue order and last-write-wins',
    () async {
      final source = await preferences.createSyncState();
      await preferences.prepareSyncSnapshot(
        'reentrant-scalars',
        source.snapshot,
        expectedCheckpoint: source.checkpoint,
      );

      final first = preferences.setTheme(ThemeMode.light);
      final second = preferences.setTheme(ThemeMode.dark);
      await Future.wait([first, second]);

      expect(preferences.getTheme(), ThemeMode.dark);
      await preferences.commitDataSyncTransaction('reentrant-scalars');
      expect(preferences.getTheme(), ThemeMode.dark);
    },
  );

  test('cleanup failure retains and replays durable record intents', () async {
    final a = _card('a', 'A');
    final b = _card('b', 'B');
    final c = _card('c', 'C');
    await preferences.setCards([a]);
    final source = await preferences.createSyncState();
    await preferences.prepareSyncSnapshot(
      'intent-cleanup-failure',
      SyncSnapshot(cards: [a, b], settings: source.snapshot.settings),
      expectedCheckpoint: source.checkpoint,
    );
    await preferences.setCards([...preferences.getCards(), c]);
    preferences.debugDataSyncWriteInterceptor = (operation, key, value) =>
        !(operation == 'remove' &&
            key == dataSyncTransactionManifestPreferenceKey);

    await expectLater(
      preferences.commitDataSyncTransaction('intent-cleanup-failure'),
      throwsA(isA<SyncPersistenceException>()),
    );
    final raw = await SharedPreferences.getInstance();
    expect(raw.containsKey(dataSyncDeferredMutationsPreferenceKey), isTrue);

    preferences.debugDataSyncWriteInterceptor = null;
    await preferences.load();
    expect(preferences.getCards().map((card) => card.id).toSet(), {
      'a',
      'b',
      'c',
    });
    expect(raw.containsKey(dataSyncDeferredMutationsPreferenceKey), isFalse);
  });

  test(
    'manifest removal before deferred removal preserves newer intent on restart',
    () async {
      final a = _card('a', 'A');
      final b = _card('b', 'B');
      final c = _card('c', 'C');
      final d = _card('d', 'D');
      await preferences.setCards([a]);
      final source = await preferences.createSyncState();
      await preferences.prepareSyncSnapshot(
        'deferred-remove-failure',
        SyncSnapshot(cards: [a, b], settings: source.snapshot.settings),
        expectedCheckpoint: source.checkpoint,
      );
      await preferences.setCards([...preferences.getCards(), c]);
      preferences.debugDataSyncWriteInterceptor = (operation, key, value) =>
          !(operation == 'remove' &&
              key == dataSyncDeferredMutationsPreferenceKey);

      await expectLater(
        preferences.commitDataSyncTransaction('deferred-remove-failure'),
        throwsA(isA<SyncPersistenceException>()),
      );
      final raw = await SharedPreferences.getInstance();
      expect(
        raw.containsKey(dataSyncTransactionManifestPreferenceKey),
        isFalse,
      );
      expect(raw.containsKey(dataSyncDeferredMutationsPreferenceKey), isTrue);
      expect(
        raw.getKeys().where(
          (key) => key.startsWith(dataSyncTransactionStagePrefix),
        ),
        isEmpty,
      );

      await preferences.setCards([...preferences.getCards(), d]);
      expect(preferences.getCards().map((card) => card.id), [
        'a',
        'c',
        'b',
        'd',
      ]);

      preferences.debugDataSyncWriteInterceptor = null;
      await preferences.load();

      expect(preferences.getCards().map((card) => card.id), [
        'a',
        'c',
        'b',
        'd',
      ]);
      expect(raw.containsKey(dataSyncDeferredMutationsPreferenceKey), isFalse);
    },
  );

  test(
    'deferred replay write failure retains intents for commit retry',
    () async {
      final a = _card('a', 'A');
      final b = _card('b', 'B');
      final c = _card('c', 'C');
      await preferences.setCards([a]);
      final source = await preferences.createSyncState();
      await preferences.prepareSyncSnapshot(
        'intent-write-failure',
        SyncSnapshot(cards: [a, b], settings: source.snapshot.settings),
        expectedCheckpoint: source.checkpoint,
      );
      await preferences.setCards([...preferences.getCards(), c]);
      var cardWrites = 0;
      preferences.debugDataSyncWriteInterceptor = (operation, key, value) {
        if (operation == 'set' && key == 'cards') {
          cardWrites++;
          return cardWrites != 2;
        }
        return true;
      };

      await expectLater(
        preferences.commitDataSyncTransaction('intent-write-failure'),
        throwsA(isA<SyncPersistenceException>()),
      );
      final raw = await SharedPreferences.getInstance();
      expect(raw.containsKey(dataSyncDeferredMutationsPreferenceKey), isTrue);
      expect(
        raw.getString(dataSyncTransactionManifestPreferenceKey),
        contains('commitDecided'),
      );

      preferences.debugDataSyncWriteInterceptor = null;
      await preferences.commitDataSyncTransaction('intent-write-failure');
      expect(preferences.getCards().map((card) => card.id).toSet(), {
        'a',
        'b',
        'c',
      });
      expect(raw.containsKey(dataSyncDeferredMutationsPreferenceKey), isFalse);
    },
  );

  test('failed prepare exposes no partial target state', () async {
    final source = await preferences.createSyncState();
    final updated = SyncSnapshot(
      settings: {...source.snapshot.settings, 'confirm_delete': false},
    );
    preferences.debugDataSyncWriteInterceptor = (operation, key, value) =>
        key != dataSyncTransactionManifestPreferenceKey;

    await expectLater(
      preferences.applySyncSnapshot(
        updated,
        expectedCheckpoint: source.checkpoint,
      ),
      throwsA(isA<SyncPersistenceException>()),
    );

    expect(preferences.getConfirmDelete(), isTrue);
    final raw = await SharedPreferences.getInstance();
    expect(raw.containsKey(dataSyncTransactionManifestPreferenceKey), isFalse);
  });

  test(
    'initial PREPARED vote validates persisted stages before returning',
    () async {
      final source = await preferences.createSyncState();
      final target = SyncSnapshot(
        settings: {...source.snapshot.settings, 'confirm_delete': false},
      );
      final raw = await SharedPreferences.getInstance();
      var corrupted = false;
      preferences.debugDataSyncResultInterceptor =
          (operation, key, value) async {
            if (!corrupted &&
                operation == 'set' &&
                key == dataSyncTransactionManifestPreferenceKey) {
              corrupted = true;
              await raw.setString(
                '${dataSyncTransactionStagePrefix}0',
                'wrong type',
              );
            }
            return true;
          };

      await expectLater(
        preferences.prepareSyncSnapshot(
          'corrupt-before-vote',
          target,
          expectedCheckpoint: source.checkpoint,
        ),
        throwsStateError,
      );

      preferences.debugDataSyncResultInterceptor = null;
      expect(corrupted, isTrue);
      expect(
        raw.containsKey(dataSyncTransactionManifestPreferenceKey),
        isFalse,
      );
      expect(
        raw.getKeys().where(
          (key) => key.startsWith(dataSyncTransactionStagePrefix),
        ),
        isEmpty,
      );
      expect(
        (await preferences.getDataSyncTransactionReceipt(
          'corrupt-before-vote',
        ))?.outcome,
        SyncTransactionOutcome.aborted,
      );
    },
  );

  test(
    'initial PREPARED vote rechecks checkpoint CAS after stage writes',
    () async {
      final source = await preferences.createSyncState();
      final target = SyncSnapshot(
        settings: {...source.snapshot.settings, 'auto_scan_enabled': false},
      );
      final raw = await SharedPreferences.getInstance();
      var changed = false;
      preferences.debugDataSyncResultInterceptor =
          (operation, key, value) async {
            if (!changed &&
                operation == 'set' &&
                key == dataSyncTransactionManifestPreferenceKey) {
              changed = true;
              await raw.setBool('confirm_delete', false);
            }
            return true;
          };

      await expectLater(
        preferences.prepareSyncSnapshot(
          'cas-before-vote',
          target,
          expectedCheckpoint: source.checkpoint,
        ),
        throwsA(isA<SyncCheckpointConflict>()),
      );

      preferences.debugDataSyncResultInterceptor = null;
      expect(preferences.getConfirmDelete(), isTrue);
      expect(raw.getBool('confirm_delete'), isFalse);
      expect(
        raw.containsKey(dataSyncTransactionManifestPreferenceKey),
        isFalse,
      );
    },
  );

  test(
    'initial PREPARED vote rechecks mutation epoch after stage writes',
    () async {
      final source = await preferences.createSyncState();
      var changed = false;
      preferences.debugDataSyncResultInterceptor = (operation, key, value) {
        if (!changed &&
            operation == 'set' &&
            key == dataSyncTransactionManifestPreferenceKey) {
          changed = true;
          preferences.debugAdvanceDataSyncMutationEpoch();
        }
        return true;
      };

      await expectLater(
        preferences.prepareSyncSnapshot(
          'epoch-before-vote',
          source.snapshot,
          expectedCheckpoint: source.checkpoint,
        ),
        throwsStateError,
      );

      preferences.debugDataSyncResultInterceptor = null;
      expect(changed, isTrue);
      expect(
        (await SharedPreferences.getInstance()).containsKey(
          dataSyncTransactionManifestPreferenceKey,
        ),
        isFalse,
      );
    },
  );

  test(
    'duplicate and query PREPARED fail closed on corrupt persisted stage',
    () async {
      final source = await preferences.createSyncState();
      final prepared = await preferences.prepareSyncSnapshot(
        'corrupt-prepared-query',
        source.snapshot,
        expectedCheckpoint: source.checkpoint,
      );
      final raw = await SharedPreferences.getInstance();
      await raw.setString('${dataSyncTransactionStagePrefix}0', 'wrong type');

      await expectLater(
        preferences.prepareSyncSnapshot(
          'corrupt-prepared-query',
          source.snapshot,
          expectedCheckpoint: source.checkpoint,
        ),
        throwsStateError,
      );
      await expectLater(
        preferences.getDataSyncTransactionReceipt('corrupt-prepared-query'),
        throwsStateError,
      );
      expect(
        raw.getString(dataSyncTransactionManifestPreferenceKey),
        contains('prepared'),
      );

      await preferences.abortDataSyncParticipantFromCoordinator(
        'corrupt-prepared-query',
        prepared.targetHash,
      );
    },
  );

  test('commit-decided transaction rolls forward after restart', () async {
    final source = await preferences.createSyncState();
    final updated = SyncSnapshot(
      settings: {
        ...source.snapshot.settings,
        'app_theme': ThemeMode.dark.index,
        'confirm_delete': false,
      },
    );
    preferences.debugDataSyncWriteInterceptor = (operation, key, value) =>
        !(operation == 'set' && key == 'confirm_delete');

    await expectLater(
      preferences.applySyncSnapshot(
        updated,
        expectedCheckpoint: source.checkpoint,
        transactionId: 'restart-test',
      ),
      throwsA(isA<SyncPersistenceException>()),
    );
    final raw = await SharedPreferences.getInstance();
    expect(
      raw.getString(dataSyncTransactionManifestPreferenceKey),
      contains('commitDecided'),
    );

    preferences.debugDataSyncWriteInterceptor = null;
    await preferences.load();

    expect(preferences.getTheme(), ThemeMode.dark);
    expect(preferences.getConfirmDelete(), isFalse);
    expect(raw.containsKey(dataSyncTransactionManifestPreferenceKey), isFalse);
    final receipt = await preferences.getDataSyncTransactionReceipt(
      'restart-test',
    );
    expect(receipt?.outcome, SyncTransactionOutcome.committed);
  });

  test('participant cannot locally abort PREPARED after restart', () async {
    final source = await preferences.createSyncState();
    final updated = SyncSnapshot(
      settings: {...source.snapshot.settings, 'confirm_delete': false},
    );

    final prepared = await preferences.prepareSyncSnapshot(
      'peer-prepared-test',
      updated,
      expectedCheckpoint: source.checkpoint,
    );
    final raw = await SharedPreferences.getInstance();
    expect(prepared.outcome, SyncTransactionOutcome.prepared);
    expect(
      raw.getString(dataSyncTransactionManifestPreferenceKey),
      contains('prepared'),
    );

    await preferences.load();

    expect(preferences.getConfirmDelete(), isTrue);
    expect(
      (await preferences.getDataSyncTransactionReceipt(
        'peer-prepared-test',
      ))?.outcome,
      SyncTransactionOutcome.prepared,
    );
    await expectLater(
      preferences.recordDataSyncAbort(
        'peer-prepared-test',
        prepared.targetHash,
      ),
      throwsStateError,
    );
    final aborted = await preferences.abortDataSyncParticipantFromCoordinator(
      'peer-prepared-test',
      prepared.targetHash,
    );
    expect(aborted.outcome, SyncTransactionOutcome.aborted);
  });

  test('stale reviewed checkpoint is rejected without overwrite', () async {
    final reviewed = await preferences.createSyncState();
    await preferences.setTheme(ThemeMode.dark);
    final merged = SyncSnapshot(
      settings: {...reviewed.snapshot.settings, 'confirm_delete': false},
    );

    await expectLater(
      preferences.applySyncSnapshot(
        merged,
        expectedCheckpoint: reviewed.checkpoint,
      ),
      throwsA(isA<SyncCheckpointConflict>()),
    );

    expect(preferences.getTheme(), ThemeMode.dark);
    expect(preferences.getConfirmDelete(), isTrue);
  });

  test('duplicate transaction ID returns one committed outcome', () async {
    final source = await preferences.createSyncState();
    final updated = SyncSnapshot(
      settings: {...source.snapshot.settings, 'confirm_delete': false},
    );

    final first = await preferences.applySyncSnapshot(
      updated,
      expectedCheckpoint: source.checkpoint,
      transactionId: 'idempotent-test',
    );
    final second = await preferences.applySyncSnapshot(
      updated,
      expectedCheckpoint: source.checkpoint,
      transactionId: 'idempotent-test',
    );

    expect(second.outcome, SyncTransactionOutcome.committed);
    expect(second.checkpoint, first.checkpoint);
    expect((await preferences.createSyncState()).checkpoint, first.checkpoint);
  });

  test(
    'concurrent applies serialize and only one wins checkpoint CAS',
    () async {
      final source = await preferences.createSyncState();
      final first = SyncSnapshot(
        settings: {...source.snapshot.settings, 'confirm_delete': false},
      );
      final second = SyncSnapshot(
        settings: {...source.snapshot.settings, 'auto_scan_enabled': false},
      );

      final outcomes = await Future.wait<Object>([
        preferences
            .applySyncSnapshot(
              first,
              expectedCheckpoint: source.checkpoint,
              transactionId: 'queue-first',
            )
            .then<Object>((value) => value)
            .catchError((Object error) => error),
        preferences
            .applySyncSnapshot(
              second,
              expectedCheckpoint: source.checkpoint,
              transactionId: 'queue-second',
            )
            .then<Object>((value) => value)
            .catchError((Object error) => error),
      ]);

      expect(outcomes.whereType<SyncTransactionReceipt>(), hasLength(1));
      expect(outcomes.whereType<SyncCheckpointConflict>(), hasLength(1));
    },
  );

  for (final failedTargetKey in dataSyncStoredPreferenceKeys) {
    test(
      'target failure at $failedTargetKey never publishes a mixed view',
      () async {
        final source = await preferences.createSyncState();
        final baseline = _visibleSynchronizedValues(preferences);
        final target = SyncSnapshot(
          cards: [_card('target-card', 'Target card')],
          dictionaries: [
            Dictionary(
              id: 'target-dictionary',
              name: 'Target dictionary',
              keys: [Uint8List(6)],
              color: Colors.blue,
              keyLength: 12,
            ),
          ],
          keyboardScripts: [_script('target-script')],
          settings: {
            ...source.snapshot.settings,
            'app_theme': ThemeMode.dark.index,
            'app_theme_color': 1,
            'locale': 'es',
            'confirm_delete': false,
            'auto_scan_enabled': false,
            'auto_connect_first_found': true,
            'device_found_banner': false,
            'sidebar_auto_expanded': false,
            'sidebar_expanded_index': 2,
            'emulation_change_monitoring': true,
            'hf_capture_retention_days': 90,
          },
        );
        final observedDuringWrites = <Map<String, Object>>[];
        preferences.debugDataSyncWriteInterceptor = (operation, key, value) {
          if (operation == 'set' &&
              dataSyncStoredPreferenceKeys.contains(key)) {
            observedDuringWrites.add(_visibleSynchronizedValues(preferences));
            if (key == failedTargetKey) return false;
          }
          return true;
        };

        await expectLater(
          preferences.applySyncSnapshot(
            target,
            expectedCheckpoint: source.checkpoint,
            transactionId: 'visibility-$failedTargetKey',
          ),
          throwsA(isA<SyncPersistenceException>()),
        );

        expect(observedDuringWrites, isNotEmpty);
        for (final observed in observedDuringWrites) {
          expect(observed, baseline, reason: 'before $failedTargetKey failure');
        }
        expect(_visibleSynchronizedValues(preferences), baseline);

        preferences.debugDataSyncWriteInterceptor = null;
        await preferences.commitDataSyncTransaction(
          'visibility-$failedTargetKey',
        );

        expect(preferences.getCards().single.id, 'target-card');
        expect(preferences.getDictionaries().single.id, 'target-dictionary');
        expect(preferences.getKeyboardScripts().single.id, 'target-script');
        expect(preferences.getTheme(), ThemeMode.dark);
        expect(preferences.getThemeColorIndex(), 1);
        expect(preferences.getLocaleString(), 'es');
        expect(preferences.getConfirmDelete(), isFalse);
        expect(preferences.getAutoScanEnabled(), isFalse);
        expect(preferences.getAutoConnectFirstFoundDevice(), isTrue);
        expect(preferences.getDeviceFoundBanner(), isFalse);
        expect(preferences.getSideBarAutoExpansion(), isFalse);
        expect(preferences.getSideBarExpandedIndex(), 2);
        expect(preferences.getEmulationChangeMonitoring(), isTrue);
      },
    );
  }

  for (final failure in const {
    'target': ('set', 'confirm_delete'),
    'metadata': ('set', dataSyncMetaPreferenceKey),
    'receipt': ('set', dataSyncTransactionReceiptsPreferenceKey),
    'cleanup': ('remove', dataSyncTransactionManifestPreferenceKey),
    'stage cleanup': ('remove', '${dataSyncTransactionStagePrefix}0'),
  }.entries) {
    test('${failure.key} failure remains irrevocably commit-decided', () async {
      final source = await preferences.createSyncState();
      final updated = SyncSnapshot(
        settings: {...source.snapshot.settings, 'confirm_delete': false},
      );
      preferences.debugDataSyncWriteInterceptor = (operation, key, value) =>
          operation != failure.value.$1 || key != failure.value.$2;

      await expectLater(
        preferences.applySyncSnapshot(
          updated,
          expectedCheckpoint: source.checkpoint,
          transactionId: 'failure-${failure.key}',
        ),
        throwsA(isA<SyncPersistenceException>()),
      );
      final raw = await SharedPreferences.getInstance();
      if (failure.key == 'stage cleanup') {
        expect(raw.getString(dataSyncTransactionManifestPreferenceKey), isNull);
        expect(
          raw.getStringList(dataSyncTransactionReceiptsPreferenceKey),
          contains(contains('committed')),
        );
      } else {
        expect(
          raw.getString(dataSyncTransactionManifestPreferenceKey),
          contains('commitDecided'),
        );
      }

      preferences.debugDataSyncWriteInterceptor = null;
      final receipt = await preferences.commitDataSyncTransaction(
        'failure-${failure.key}',
      );

      expect(receipt.outcome, SyncTransactionOutcome.committed);
      expect(preferences.getConfirmDelete(), isFalse);
      expect(
        raw.containsKey(dataSyncTransactionManifestPreferenceKey),
        isFalse,
      );
      expect(
        raw.getKeys().where(
          (key) => key.startsWith(dataSyncTransactionStagePrefix),
        ),
        isEmpty,
      );
    });
  }

  test('failed result reloads cache and reconciles persisted write', () async {
    final source = await preferences.createSyncState();
    final updated = SyncSnapshot(
      settings: {...source.snapshot.settings, 'confirm_delete': false},
    );
    var injected = false;
    preferences.debugDataSyncResultInterceptor = (operation, key, value) {
      if (!injected &&
          operation == 'set' &&
          key == dataSyncTransactionManifestPreferenceKey) {
        injected = true;
        return false;
      }
      return true;
    };

    final receipt = await preferences.applySyncSnapshot(
      updated,
      expectedCheckpoint: source.checkpoint,
    );

    expect(injected, isTrue);
    expect(receipt.outcome, SyncTransactionOutcome.committed);
    expect(preferences.getConfirmDelete(), isFalse);
  });

  test(
    'failed result reloads cache before aborting an unpersisted prepare',
    () async {
      final source = await preferences.createSyncState();
      final updated = SyncSnapshot(
        settings: {...source.snapshot.settings, 'confirm_delete': false},
      );
      final raw = await SharedPreferences.getInstance();
      var injected = false;
      preferences.debugDataSyncResultInterceptor =
          (operation, key, value) async {
            if (!injected &&
                operation == 'set' &&
                key == dataSyncTransactionManifestPreferenceKey) {
              injected = true;
              await raw.remove(key);
              return false;
            }
            return true;
          };

      await expectLater(
        preferences.applySyncSnapshot(
          updated,
          expectedCheckpoint: source.checkpoint,
        ),
        throwsA(isA<SyncPersistenceException>()),
      );

      expect(injected, isTrue);
      expect(preferences.getConfirmDelete(), isTrue);
      expect(
        raw.containsKey(dataSyncTransactionManifestPreferenceKey),
        isFalse,
      );
      expect(
        raw.getKeys().where(
          (key) => key.startsWith(dataSyncTransactionStagePrefix),
        ),
        isEmpty,
      );
    },
  );

  test('throw after metadata cache mutation reconciles and commits', () async {
    final source = await preferences.createSyncState();
    final updated = SyncSnapshot(
      settings: {...source.snapshot.settings, 'confirm_delete': false},
    );
    var injected = false;
    preferences.debugDataSyncResultInterceptor = (operation, key, value) {
      if (!injected && operation == 'set' && key == dataSyncMetaPreferenceKey) {
        injected = true;
        throw StateError('simulated Future failure after cache mutation');
      }
      return true;
    };

    final receipt = await preferences.applySyncSnapshot(
      updated,
      expectedCheckpoint: source.checkpoint,
    );

    expect(injected, isTrue);
    expect(receipt.outcome, SyncTransactionOutcome.committed);
  });

  test('failed remove result reloads cache and recognizes cleanup', () async {
    final source = await preferences.createSyncState();
    final updated = SyncSnapshot(
      settings: {...source.snapshot.settings, 'confirm_delete': false},
    );
    var injected = false;
    preferences.debugDataSyncResultInterceptor = (operation, key, value) {
      if (!injected &&
          operation == 'remove' &&
          key == dataSyncTransactionManifestPreferenceKey) {
        injected = true;
        return false;
      }
      return true;
    };

    final receipt = await preferences.applySyncSnapshot(
      updated,
      expectedCheckpoint: source.checkpoint,
    );

    expect(injected, isTrue);
    expect(receipt.outcome, SyncTransactionOutcome.committed);
    expect(
      (await SharedPreferences.getInstance()).containsKey(
        dataSyncTransactionManifestPreferenceKey,
      ),
      isFalse,
    );
  });

  test(
    'aborted terminal receipt cleans matching prepared manifest on load',
    () async {
      final source = await preferences.createSyncState();
      final updated = SyncSnapshot(
        settings: {...source.snapshot.settings, 'confirm_delete': false},
      );
      final prepared = await preferences.prepareSyncSnapshot(
        'aborted-terminal',
        updated,
        expectedCheckpoint: source.checkpoint,
      );
      preferences.debugDataSyncWriteInterceptor = (operation, key, value) =>
          !(operation == 'remove' &&
              key == dataSyncTransactionManifestPreferenceKey);
      await expectLater(
        preferences.abortDataSyncParticipantFromCoordinator(
          'aborted-terminal',
          prepared.targetHash,
        ),
        throwsA(isA<SyncPersistenceException>()),
      );

      preferences.debugDataSyncWriteInterceptor = null;
      await preferences.load();

      final raw = await SharedPreferences.getInstance();
      expect(preferences.getConfirmDelete(), isTrue);
      expect(
        raw.containsKey(dataSyncTransactionManifestPreferenceKey),
        isFalse,
      );
    },
  );

  test(
    'committed terminal receipt finishes matching manifest on load',
    () async {
      final source = await preferences.createSyncState();
      final updated = SyncSnapshot(
        settings: {...source.snapshot.settings, 'confirm_delete': false},
      );
      preferences.debugDataSyncWriteInterceptor = (operation, key, value) =>
          !(operation == 'remove' &&
              key == dataSyncTransactionManifestPreferenceKey);
      await expectLater(
        preferences.applySyncSnapshot(
          updated,
          expectedCheckpoint: source.checkpoint,
          transactionId: 'committed-terminal',
        ),
        throwsA(isA<SyncPersistenceException>()),
      );

      preferences.debugDataSyncWriteInterceptor = null;
      await preferences.load();

      final raw = await SharedPreferences.getInstance();
      expect(preferences.getConfirmDelete(), isFalse);
      expect(
        raw.containsKey(dataSyncTransactionManifestPreferenceKey),
        isFalse,
      );
      expect(
        (await preferences.getDataSyncTransactionReceipt(
          'committed-terminal',
        ))?.outcome,
        SyncTransactionOutcome.committed,
      );
    },
  );

  test('commit validates every stage before persisting decision', () async {
    final source = await preferences.createSyncState();
    final updated = SyncSnapshot(
      settings: {...source.snapshot.settings, 'confirm_delete': false},
    );
    final prepared = await preferences.prepareSyncSnapshot(
      'corrupt-stage',
      updated,
      expectedCheckpoint: source.checkpoint,
    );
    final raw = await SharedPreferences.getInstance();
    await raw.setString('${dataSyncTransactionStagePrefix}0', 'wrong type');

    await expectLater(
      preferences.commitDataSyncTransaction('corrupt-stage'),
      throwsStateError,
    );

    expect(
      raw.getString(dataSyncTransactionManifestPreferenceKey),
      contains('prepared'),
    );
    await preferences.abortDataSyncParticipantFromCoordinator(
      'corrupt-stage',
      prepared.targetHash,
    );
  });

  test('claimed target hash is checked before any durable write', () async {
    final source = await preferences.createSyncState();
    await expectLater(
      preferences.prepareDataSyncValues(
        transactionId: 'wrong-claim',
        expectedCheckpoint: source.checkpoint,
        values: {
          'cards': <String>[],
          'dictionaries': <String>[],
          'keyboard_scripts': <String>[],
          ...source.snapshot.settings,
        },
        claimedTargetHash: '0' * 64,
      ),
      throwsFormatException,
    );
    final raw = await SharedPreferences.getInstance();
    expect(raw.containsKey(dataSyncTransactionManifestPreferenceKey), isFalse);
    expect(
      raw.getKeys().where(
        (key) => key.startsWith(dataSyncTransactionStagePrefix),
      ),
      isEmpty,
    );
  });

  test('coordinator decision survives restart until acknowledged', () async {
    final source = await preferences.createSyncState();
    final updated = SyncSnapshot(
      settings: {...source.snapshot.settings, 'confirm_delete': false},
    );
    await preferences.prepareSyncSnapshot(
      'coordinator-restart',
      updated,
      expectedCheckpoint: source.checkpoint,
      role: SyncTransactionRole.coordinator,
      peerCheckpoint: const SyncCheckpoint(
        revision: 7,
        stateHash:
            'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      ),
    );
    preferences.debugDataSyncWriteInterceptor = (operation, key, value) =>
        !(operation == 'set' && key == 'confirm_delete');
    await expectLater(
      preferences.commitDataSyncTransaction('coordinator-restart'),
      throwsA(isA<SyncPersistenceException>()),
    );
    expect(
      (await preferences.getDataSyncCoordinatorRecovery())?.decision,
      SyncCoordinatorDecision.commitDecided,
    );

    preferences.debugDataSyncWriteInterceptor = null;
    await preferences.load();

    final recovery = await preferences.getDataSyncCoordinatorRecovery();
    expect(recovery?.transactionId, 'coordinator-restart');
    expect(recovery?.decision, SyncCoordinatorDecision.commitDecided);
    expect(preferences.getConfirmDelete(), isFalse);
    await preferences.completeDataSyncCoordinator('coordinator-restart');
    expect(await preferences.getDataSyncCoordinatorRecovery(), isNull);
  });

  test(
    'pre-decision coordinator restart persists ABORT until peer ACK',
    () async {
      final source = await preferences.createSyncState();
      await preferences.prepareSyncSnapshot(
        'coordinator-prepared',
        source.snapshot,
        expectedCheckpoint: source.checkpoint,
        role: SyncTransactionRole.coordinator,
        peerCheckpoint: source.checkpoint,
      );

      await preferences.load();

      expect(
        (await preferences.getDataSyncCoordinatorRecovery())?.decision,
        SyncCoordinatorDecision.abortDecided,
      );
      expect(
        (await preferences.getDataSyncTransactionReceipt(
          'coordinator-prepared',
        ))?.outcome,
        SyncTransactionOutcome.aborted,
      );
      await preferences.completeDataSyncCoordinator('coordinator-prepared');
      expect(await preferences.getDataSyncCoordinatorRecovery(), isNull);
    },
  );

  test(
    'participant PREPARED reserves setters and cannot re-vote at COMMIT',
    () async {
      final source = await preferences.createSyncState();
      final target = SyncSnapshot(
        settings: {...source.snapshot.settings, 'auto_scan_enabled': false},
      );
      await preferences.prepareSyncSnapshot(
        'reserved-commit',
        target,
        expectedCheckpoint: source.checkpoint,
      );

      await preferences.setTheme(ThemeMode.dark);
      expect(preferences.getTheme(), ThemeMode.dark);
      expect(preferences.getAutoScanEnabled(), isTrue);
      expect(
        (await preferences.getDataSyncTransactionReceipt(
          'reserved-commit',
        ))?.outcome,
        SyncTransactionOutcome.prepared,
      );

      final receipt = await preferences.commitDataSyncTransaction(
        'reserved-commit',
      );

      expect(receipt.outcome, SyncTransactionOutcome.committed);
      expect(preferences.getAutoScanEnabled(), isFalse);
      expect(preferences.getTheme(), ThemeMode.dark);
    },
  );

  test('setter racing PREPARE is deferred by the reservation', () async {
    final source = await preferences.createSyncState();
    var injected = false;
    Future<void>? deferredMutation;
    preferences.debugDataSyncWriteInterceptor = (operation, key, value) {
      if (!injected &&
          operation == 'set' &&
          key.startsWith(dataSyncTransactionStagePrefix)) {
        injected = true;
        deferredMutation = preferences.setTheme(ThemeMode.dark);
      }
      return true;
    };

    final prepared = await preferences.prepareSyncSnapshot(
      'reserved-during-prepare',
      source.snapshot,
      expectedCheckpoint: source.checkpoint,
    );
    await deferredMutation;

    expect(prepared.outcome, SyncTransactionOutcome.prepared);
    expect(injected, isTrue);
    expect(preferences.getTheme(), ThemeMode.dark);
    preferences.debugDataSyncWriteInterceptor = null;
    final committed = await preferences.commitDataSyncTransaction(
      'reserved-during-prepare',
    );
    expect(committed.outcome, SyncTransactionOutcome.committed);
    expect(preferences.getTheme(), ThemeMode.dark);
  });

  test(
    'authenticated coordinator ABORT replays deferred participant intents',
    () async {
      final source = await preferences.createSyncState();
      final target = SyncSnapshot(
        settings: {...source.snapshot.settings, 'auto_scan_enabled': false},
      );
      final prepared = await preferences.prepareSyncSnapshot(
        'reserved-abort',
        target,
        expectedCheckpoint: source.checkpoint,
      );
      await preferences.setTheme(ThemeMode.dark);

      final receipt = await preferences.abortDataSyncParticipantFromCoordinator(
        'reserved-abort',
        prepared.targetHash,
      );

      expect(receipt.outcome, SyncTransactionOutcome.aborted);
      expect(preferences.getAutoScanEnabled(), isTrue);
      expect(preferences.getTheme(), ThemeMode.dark);
    },
  );

  test('participant reservation is restored after restart', () async {
    final source = await preferences.createSyncState();
    final target = SyncSnapshot(
      settings: {...source.snapshot.settings, 'auto_scan_enabled': false},
    );
    await preferences.prepareSyncSnapshot(
      'reserved-restart',
      target,
      expectedCheckpoint: source.checkpoint,
    );
    await preferences.load();

    await preferences.setTheme(ThemeMode.dark);
    expect(preferences.getTheme(), ThemeMode.dark);
    final receipt = await preferences.commitDataSyncTransaction(
      'reserved-restart',
    );

    expect(receipt.outcome, SyncTransactionOutcome.committed);
    expect(preferences.getAutoScanEnabled(), isFalse);
    expect(preferences.getTheme(), ThemeMode.dark);
  });

  test('post-decision setter waits through roll-forward recovery', () async {
    final source = await preferences.createSyncState();
    final target = SyncSnapshot(
      settings: {...source.snapshot.settings, 'auto_scan_enabled': false},
    );
    await preferences.prepareSyncSnapshot(
      'reserved-decided',
      target,
      expectedCheckpoint: source.checkpoint,
    );
    preferences.debugDataSyncWriteInterceptor = (operation, key, value) =>
        !(operation == 'set' && key == 'auto_scan_enabled');
    await expectLater(
      preferences.commitDataSyncTransaction('reserved-decided'),
      throwsA(isA<SyncPersistenceException>()),
    );

    await preferences.setTheme(ThemeMode.dark);
    expect(preferences.getTheme(), ThemeMode.dark);
    preferences.debugDataSyncWriteInterceptor = null;
    final receipt = await preferences.commitDataSyncTransaction(
      'reserved-decided',
    );

    expect(receipt.outcome, SyncTransactionOutcome.committed);
    expect(preferences.getAutoScanEnabled(), isFalse);
    expect(preferences.getTheme(), ThemeMode.dark);
  });
}

CardSave _card(String id, String name) =>
    CardSave(id: id, uid: 'opaque-$id', name: name, tag: TagType.unknown);

SavedKeyboardScript _script(String id) => SavedKeyboardScript.compile(
  id: id,
  name: 'Script $id',
  source: 'ENTER',
  layout: KeyboardLayout.us,
  output: KeyboardOutput.usb,
  updatedAt: DateTime.utc(2026, 7, 16),
);

Map<String, Object> _visibleSynchronizedValues(
  SharedPreferencesProvider preferences,
) => {
  'cards': preferences.getCards().map((card) => card.toJson()).toList(),
  'dictionaries': preferences
      .getDictionaries()
      .map((dictionary) => dictionary.toJson())
      .toList(),
  'keyboard_scripts': preferences
      .getKeyboardScripts()
      .map((script) => script.toJson())
      .toList(),
  'app_theme': preferences.getTheme().index,
  'app_theme_color': preferences.getThemeColorIndex(),
  'locale': preferences.getLocaleString(),
  'confirm_delete': preferences.getConfirmDelete(),
  'auto_scan_enabled': preferences.getAutoScanEnabled(),
  'auto_connect_first_found': preferences.getAutoConnectFirstFoundDevice(),
  'device_found_banner': preferences.getDeviceFoundBanner(),
  'sidebar_auto_expanded': preferences.getSideBarAutoExpansion(),
  'sidebar_expanded_index': preferences.getSideBarExpandedIndex(),
  'emulation_change_monitoring': preferences.getEmulationChangeMonitoring(),
  'hf_capture_retention_days': preferences.getHfCaptureRetentionDays(),
};

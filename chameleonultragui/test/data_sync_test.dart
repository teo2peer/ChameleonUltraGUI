import 'dart:convert';
import 'dart:typed_data';

import 'package:chameleonultragui/bridge/chameleon_keyboard.dart';
import 'package:chameleonultragui/helpers/data_sync.dart';
import 'package:chameleonultragui/helpers/definitions.dart';
import 'package:chameleonultragui/helpers/keyboard_layout.dart';
import 'package:chameleonultragui/helpers/saved_keyboard_script.dart';
import 'package:chameleonultragui/sharedprefsprovider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  CardSave card(String id, List<List<int>> blocks, {String name = 'Card'}) =>
      CardSave(
        id: id,
        uid: '01020304',
        name: name,
        tag: TagType.mifare1K,
        sak: 8,
        atqa: Uint8List.fromList([4, 0]),
        data: blocks
            .map(
              (block) => Uint8List.fromList(
                block.length == 16
                    ? block
                    : [...block, ...List<int>.filled(16 - block.length, 0)],
              ),
            )
            .toList(),
      );

  Dictionary dictionary(String id, String name, List<List<int>> keys) =>
      Dictionary(
        id: id,
        name: name,
        keys: keys
            .map(
              (key) => Uint8List.fromList(
                key.length == 6
                    ? key
                    : [...key, ...List<int>.filled(6 - key.length, 0)],
              ),
            )
            .toList(),
        color: Colors.blue,
        keyLength: 12,
      );

  SavedKeyboardScript script(String id, String name, String source) =>
      SavedKeyboardScript.compile(
        id: id,
        name: name,
        source: source,
        layout: KeyboardLayout.us,
        output: KeyboardOutput.usb,
        updatedAt: DateTime.utc(2026, 7, 12),
      );

  test('current snapshot round trips every data category', () {
    final cardFolder = CardFolder(id: 'card-folder', name: 'Cards');
    final dictionaryFolder = DictionaryFolder(
      id: 'dictionary-folder',
      name: 'Dictionaries',
    );
    final original = SyncSnapshot(
      cards: [
        card('card-1', [
          [1, 2, 3],
        ])..folderId = cardFolder.id,
      ],
      cardFolders: [cardFolder],
      dictionaries: [
        dictionary('dict-1', 'Keys', [
          [1, 2, 3, 4, 5, 6],
        ])..folderId = dictionaryFolder.id,
      ],
      dictionaryFolders: [dictionaryFolder],
      keyboardScripts: [script('script-1', 'Hello', 'STRING hello')],
      settings: {
        'theme': 'dark',
        'retries': 3,
        'options': <Object>[
          true,
          <String, Object>{'rate': 1.5},
        ],
      },
    );

    final restored = SyncSnapshot.fromJson(original.toJson());

    expect(restored.version, SyncSnapshot.currentVersion);
    expect(restored.cards.single.toJson(), original.cards.single.toJson());
    expect(
      restored.cardFolders.single.toJson(),
      original.cardFolders.single.toJson(),
    );
    expect(
      restored.dictionaries.single.toJson(),
      original.dictionaries.single.toJson(),
    );
    expect(
      restored.dictionaryFolders.single.toJson(),
      original.dictionaryFolders.single.toJson(),
    );
    expect(
      restored.keyboardScripts.single.toJson(),
      original.keyboardScripts.single.toJson(),
    );
    expect(restored.settings, original.settings);
  });

  test('strict decoder rejects malformed and unsafe data', () {
    final valid = SyncSnapshot().toJsonMap();

    expect(() => SyncSnapshot.fromJson('{bad json'), throwsFormatException);
    expect(
      () => SyncSnapshot.fromJson(jsonEncode({...valid, 'version': 5})),
      throwsFormatException,
    );
    expect(
      () => SyncSnapshot.fromJson(jsonEncode({...valid, 'unknown': true})),
      throwsFormatException,
    );
    expect(
      () => SyncSnapshot.fromJson(jsonEncode({...valid, 'cards': 'no'})),
      throwsFormatException,
    );
    expect(
      () => SyncSnapshot(settings: {'unsafe': Object()}),
      throwsFormatException,
    );
  });

  test('legacy safe settings gain the default capture retention', () {
    final legacy = SyncSnapshot().toJsonMap()
      ..['version'] = 2
      ..remove('cardFolders')
      ..remove('dictionaryFolders')
      ..['settings'] = <String, Object>{'app_theme': 0};

    final restored = SyncSnapshot.fromJson(jsonEncode(legacy));

    expect(restored.version, SyncSnapshot.currentVersion);
    expect(restored.settings['hf_capture_retention_days'], 30);
    expect(restored.cardFolders, isEmpty);
    expect(restored.dictionaryFolders, isEmpty);
  });

  test('folder trees reject cycles and dangling library references', () {
    expect(
      () => SyncSnapshot(
        cardFolders: [
          CardFolder(id: 'a', name: 'A', parentId: 'b'),
          CardFolder(id: 'b', name: 'B', parentId: 'a'),
        ],
      ),
      throwsFormatException,
    );
    expect(
      () => SyncSnapshot(
        cards: [card('card-in-missing-folder', const [])..folderId = 'missing'],
      ),
      throwsFormatException,
    );
    expect(
      () => SyncSnapshot(
        dictionaries: [
          dictionary('dict-in-missing-folder', 'Keys', const [])
            ..folderId = 'missing',
        ],
      ),
      throwsFormatException,
    );
  });

  test('semantic validation rejects invalid card and dictionary geometry', () {
    expect(
      () => SyncSnapshot(
        cards: [
          CardSave(
            id: 'bad-card',
            uid: '01020304',
            name: 'Bad',
            tag: TagType.mifare1K,
            data: [Uint8List(15)],
          ),
        ],
      ),
      throwsFormatException,
    );
    expect(
      () => SyncSnapshot(
        dictionaries: [
          Dictionary(
            id: 'bad-dictionary',
            name: 'Bad',
            keyLength: 12,
            keys: [Uint8List(4)],
          ),
        ],
      ),
      throwsFormatException,
    );
    for (final format in const ['00', '1F']) {
      expect(
        () => SyncSnapshot(
          cards: [
            CardSave(
              id: 'hid-format-$format',
              uid: '$format ${List.filled(12, '00').join(' ')}',
              name: 'Bad HID format',
              tag: TagType.hidProx,
            ),
          ],
        ),
        throwsFormatException,
      );
    }
  });

  test(
    'normal Classic, Ultralight, LF, and opaque save fixtures are accepted',
    () {
      final classicData = List<Uint8List>.generate(
        256,
        (index) => index < 4 ? Uint8List(16) : Uint8List(0),
      );
      final classic = CardSave(
        id: 'classic-fixture',
        uid: '01 02 03 04',
        name: 'Recovered 1K',
        tag: TagType.mifare1K,
        data: classicData,
      );
      final ev1 = CardSave(
        id: 'classic-ev1-fixture',
        uid: '01 02 03 04',
        name: 'Recovered 1K EV1',
        tag: TagType.mifare1K,
        data: List<Uint8List>.generate(72, (_) => Uint8List(16)),
      );
      final ultralight = CardSave(
        id: 'ul-fixture',
        uid: '04 11 22 33 44 55 66',
        name: 'NTAG213',
        tag: TagType.ntag213,
        data: List<Uint8List>.generate(
          45,
          (index) => index == 10 ? Uint8List(0) : Uint8List(4),
        ),
        extraData: CardSaveExtra(
          ultralightVersion: Uint8List(8),
          ultralightSignature: Uint8List(32),
          ultralightCounters: const [0xffffff],
        ),
      );
      final hid = CardSave(
        id: 'hid-fixture',
        uid: '01 00 00 00 01 00 00 00 02 00 00 00 00',
        name: 'HID',
        tag: TagType.hidProx,
      );
      final em410x = CardSave(
        id: 'em-fixture',
        uid: '01 02 03 04 05',
        name: 'EM410X',
        tag: TagType.em410X64,
      );
      final opaque = CardSave(
        id: 'opaque-fixture',
        uid: 'vendor:opaque-id',
        name: 'Opaque',
        tag: TagType.unknown,
        data: [
          Uint8List.fromList([1, 2, 3]),
        ],
      );

      final snapshot = SyncSnapshot(
        cards: [classic, ev1, ultralight, hid, em410x, opaque],
      );

      expect(snapshot.cards.first.uid, '01 02 03 04');
      expect(snapshot.cards.first.data, hasLength(256));
      expect(snapshot.cards[1].data, hasLength(72));
      expect(snapshot.cards[2].data[10], isEmpty);
      expect(snapshot.cards.last.uid, 'vendor:opaque-id');
    },
  );

  test('known hardware-write shapes reject out-of-geometry data', () {
    final classicData = List<Uint8List>.generate(256, (_) => Uint8List(0));
    classicData[72] = Uint8List(16);
    expect(
      () => SyncSnapshot(
        cards: [
          CardSave(
            id: 'classic-overflow',
            uid: '01 02 03 04',
            name: 'Bad 1K',
            tag: TagType.mifare1K,
            data: classicData,
          ),
        ],
      ),
      throwsFormatException,
    );
    expect(
      () => SyncSnapshot(
        cards: [
          CardSave(
            id: 'ul-page-width',
            uid: '04 11 22 33 44 55 66',
            name: 'Bad UL',
            tag: TagType.ntag213,
            data: [Uint8List(5)],
          ),
        ],
      ),
      throwsFormatException,
    );
    expect(
      () => SyncSnapshot(
        cards: [
          CardSave(
            id: 'hid-width',
            uid: '01 02 03 04 05',
            name: 'Bad HID',
            tag: TagType.hidProx,
          ),
        ],
      ),
      throwsFormatException,
    );
    expect(
      () => SyncSnapshot(
        cards: [
          CardSave(
            id: 'lf-data',
            uid: '01 02 03 04',
            name: 'Bad Viking',
            tag: TagType.viking,
            data: [Uint8List(4)],
          ),
        ],
      ),
      throwsFormatException,
    );
  });

  test('malformed hardware metadata is rejected before use', () {
    CardSave malformed({
      Uint8List? atqa,
      Uint8List? ats,
      CardSaveExtra? extraData,
    }) => CardSave(
      id: 'bad-metadata',
      uid: '04 11 22 33 44 55 66',
      name: 'Bad metadata',
      tag: TagType.ntag213,
      atqa: atqa,
      ats: ats,
      data: [Uint8List(4)],
      extraData: extraData,
    );

    expect(
      () => SyncSnapshot(cards: [malformed(atqa: Uint8List(1))]),
      throwsFormatException,
    );
    expect(
      () => SyncSnapshot(cards: [malformed(ats: Uint8List(21))]),
      throwsFormatException,
    );
    expect(
      () => SyncSnapshot(
        cards: [
          malformed(extraData: CardSaveExtra(ultralightVersion: Uint8List(7))),
        ],
      ),
      throwsFormatException,
    );
    expect(
      () => SyncSnapshot(
        cards: [
          malformed(
            extraData: CardSaveExtra(ultralightSignature: Uint8List(31)),
          ),
        ],
      ),
      throwsFormatException,
    );
    expect(
      () => SyncSnapshot(
        cards: [
          malformed(extraData: CardSaveExtra(ultralightCounters: const [1, 2])),
        ],
      ),
      throwsFormatException,
    );
    expect(
      () => SyncSnapshot(
        cards: [
          malformed(
            extraData: CardSaveExtra(ultralightCounters: const [0x1000000]),
          ),
        ],
      ),
      throwsFormatException,
    );
    final encoded =
        jsonDecode(
              SyncSnapshot(
                cards: [
                  malformed(
                    extraData: CardSaveExtra(ultralightVersion: Uint8List(8)),
                  ),
                ],
              ).toJson(),
            )
            as Map<String, dynamic>;
    final encodedCard =
        (encoded['cards'] as List).single as Map<String, dynamic>;
    final encodedExtra = encodedCard['extra'] as Map<String, dynamic>;
    encodedExtra['ultralightVersion'] = [256, ...List<int>.filled(7, 0)];
    expect(
      () => SyncSnapshot.fromJson(jsonEncode(encoded)),
      throwsFormatException,
    );
  });

  test('merge rejects incompatible same-ID card and dictionary geometry', () {
    final localCard = card('same-card', [
      [1],
    ]);
    final remoteCard = CardSave(
      id: 'same-card',
      uid: localCard.uid,
      name: 'Other type',
      tag: TagType.mifare4K,
      data: [Uint8List(16)],
    );
    expect(
      () => SyncMergePlan.merge(
        SyncSnapshot(cards: [localCard]),
        SyncSnapshot(cards: [remoteCard]),
      ),
      throwsFormatException,
    );

    expect(
      () => SyncMergePlan.merge(
        SyncSnapshot(
          dictionaries: [
            Dictionary(
              id: 'same-dictionary',
              name: 'Keys',
              keyLength: 12,
              keys: [Uint8List(6)],
            ),
          ],
        ),
        SyncSnapshot(
          dictionaries: [
            Dictionary(
              id: 'same-dictionary',
              name: 'Keys',
              keyLength: 8,
              keys: [Uint8List(4)],
            ),
          ],
        ),
      ),
      throwsFormatException,
    );
  });

  test('merge rejects aggregate overflow before conflict review', () {
    final local = SyncSnapshot(
      cards: List.generate(
        SyncLimits.maxCards,
        (index) => card('local-$index', const [], name: 'Local $index'),
      ),
    );
    final remote = SyncSnapshot(
      cards: [card('remote-overflow', const [], name: 'Remote overflow')],
    );

    expect(() => SyncMergePlan.merge(local, remote), throwsFormatException);
  });

  test('card conflict resolves each block and metadata independently', () {
    final local = SyncSnapshot(
      cards: [
        card('same', [
          [1],
          [2],
          [3],
        ], name: 'Local'),
      ],
    );
    final remote = SyncSnapshot(
      cards: [
        card('same', [
          [1],
          [9],
          [8],
        ], name: 'Remote'),
      ],
    );

    final plan = SyncMergePlan.merge(local, remote);
    final conflict = plan.cardConflicts.single;
    expect(conflict.differingBlocks, [1, 2]);
    conflict.blockSelections[1] = SyncChoice.remote;
    conflict.metadataSelection = SyncChoice.remote;

    final resolved = plan.resolve();
    expect(resolved.cards.single.name, 'Remote');
    expect(resolved.cards.single.data.map((block) => block.first), [1, 9, 3]);

    final overridden = plan.resolve(
      SyncResolution(
        cardBlocks: {
          'same': {2: SyncChoice.remote},
        },
        cardMetadata: const {'same': SyncChoice.local},
      ),
    );
    expect(overridden.cards.single.name, 'Local');
    expect(overridden.cards.single.data.map((block) => block.first), [1, 9, 8]);
  });

  test('card conflict never shifts blocks when one side is shorter', () {
    final plan = SyncMergePlan.merge(
      SyncSnapshot(
        cards: [
          card('same', [
            [1],
            [2],
          ]),
        ],
      ),
      SyncSnapshot(
        cards: [
          card('same', [
            [1],
            [2],
            [3],
          ]),
        ],
      ),
    );
    final conflict = plan.cardConflicts.single;

    expect(conflict.blockSelections[2], SyncChoice.remote);
    expect(plan.resolve().cards.single.data.map((block) => block.first), [
      1,
      2,
      3,
    ]);
    expect(
      () => plan.resolve(
        const SyncResolution(
          cardBlocks: {
            'same': {2: SyncChoice.local},
          },
        ),
      ),
      throwsFormatException,
    );
  });

  test('conflicting MIFARE trailers preserve every key in a dictionary', () {
    final localBlocks = List.generate(4, (_) => List<int>.filled(16, 0));
    final remoteBlocks = List.generate(4, (_) => List<int>.filled(16, 0));
    localBlocks[3] = [
      1,
      1,
      1,
      1,
      1,
      1,
      0xff,
      0x07,
      0x80,
      0x69,
      2,
      2,
      2,
      2,
      2,
      2,
    ];
    remoteBlocks[3] = [
      3,
      3,
      3,
      3,
      3,
      3,
      0xff,
      0x07,
      0x80,
      0x69,
      4,
      4,
      4,
      4,
      4,
      4,
    ];

    final merged = SyncMergePlan.merge(
      SyncSnapshot(cards: [card('same', localBlocks)]),
      SyncSnapshot(cards: [card('same', remoteBlocks)]),
    ).resolve();

    final keys = merged.dictionaries
        .singleWhere((item) => item.name == 'Synced card keys')
        .keys;
    expect(keys, hasLength(4));
    expect(keys, contains(orderedEquals(List<int>.filled(6, 1))));
    expect(keys, contains(orderedEquals(List<int>.filled(6, 2))));
    expect(keys, contains(orderedEquals(List<int>.filled(6, 3))));
    expect(keys, contains(orderedEquals(List<int>.filled(6, 4))));
  });

  test('cards dedupe exact records and independently assigned IDs', () {
    final first = card('first', [
      [1, 2],
      [3, 4],
    ]);
    final duplicateId = CardSave.fromJson(first.toJson());
    final duplicateContent = card('second', [
      [1, 2],
      [3, 4],
    ]);

    final plan = SyncMergePlan.merge(
      SyncSnapshot(cards: [first]),
      SyncSnapshot(cards: [duplicateId, duplicateContent]),
    );

    expect(plan.cardConflicts, isEmpty);
    expect(plan.resolve().cards, hasLength(1));
    expect(plan.resolve().cards.single.id, 'first');
  });

  test('dictionaries merge by ID or case-insensitive name and key length', () {
    final local = SyncSnapshot(
      dictionaries: [
        dictionary('one', 'Main Keys', [
          [1],
          [2],
        ]),
        dictionary('separate', 'Other', [
          [8],
        ]),
      ],
    );
    final remote = SyncSnapshot(
      dictionaries: [
        dictionary('two', ' main keys ', [
          [2],
          [3],
        ]),
        dictionary('separate', 'Renamed', [
          [8],
          [9],
        ]),
        dictionary('unique', 'Unique', [
          [7],
        ]),
      ],
    );

    final dictionaries = SyncMergePlan.merge(
      local,
      remote,
    ).resolve().dictionaries;

    expect(dictionaries, hasLength(3));
    expect(
      dictionaries
          .firstWhere((item) => item.id == 'one')
          .keys
          .map((key) => key.first),
      [1, 2, 3],
    );
    expect(
      dictionaries
          .firstWhere((item) => item.id == 'separate')
          .keys
          .map((key) => key.first),
      [8, 9],
    );
  });

  test('script conflict supports keep both with unique ID and name', () {
    final local = SyncSnapshot(
      keyboardScripts: [
        script('shared', 'Action', 'ENTER'),
        script('shared-remote', 'Action (remote)', 'TAB'),
      ],
    );
    final remote = SyncSnapshot(
      keyboardScripts: [script('shared', 'Action', 'STRING remote')],
    );
    final plan = SyncMergePlan.merge(local, remote);
    plan.scriptConflicts.single.selection = ScriptChoice.keepBoth;

    final scripts = plan.resolve().keyboardScripts;

    expect(scripts, hasLength(3));
    expect(scripts.map((item) => item.id).toSet(), hasLength(3));
    expect(
      scripts.map((item) => item.name.toLowerCase()).toSet(),
      hasLength(3),
    );
    expect(scripts.any((item) => item.source == 'STRING remote'), isTrue);
  });

  test('remote x-remote selection reserves ID and name before keepBoth', () {
    final plan = SyncMergePlan.merge(
      SyncSnapshot(
        keyboardScripts: [
          script('x-remote', 'Other', 'ENTER'),
          script('x', 'X', 'TAB'),
        ],
      ),
      SyncSnapshot(
        keyboardScripts: [
          script('x-remote', 'X (remote)', 'STRING selected'),
          script('x', 'X', 'STRING keep both'),
        ],
      ),
    );

    final scripts = plan
        .resolve(
          const SyncResolution(
            scripts: {
              'x-remote': ScriptChoice.remote,
              'x': ScriptChoice.keepBoth,
            },
          ),
        )
        .keyboardScripts;

    expect(scripts.map((item) => item.id).toSet(), hasLength(scripts.length));
    expect(
      scripts.map((item) => item.name.toLowerCase()).toSet(),
      hasLength(scripts.length),
    );
    expect(scripts.map((item) => item.id), contains('x-remote-2'));
    expect(scripts.map((item) => item.name), contains('X (remote 2)'));
  });

  test('x then x-remote conflict choices are globally unique', () {
    for (final xChoice in ScriptChoice.values) {
      for (final remoteChoice in ScriptChoice.values) {
        final plan = SyncMergePlan.merge(
          SyncSnapshot(
            keyboardScripts: [
              script('x', 'X', 'ENTER'),
              script('x-remote', 'X (remote)', 'TAB'),
            ],
          ),
          SyncSnapshot(
            keyboardScripts: [
              script('x', 'X', 'STRING x'),
              script('x-remote', 'X (remote)', 'STRING x-remote'),
            ],
          ),
        );
        final scripts = plan
            .resolve(
              SyncResolution(scripts: {'x': xChoice, 'x-remote': remoteChoice}),
            )
            .keyboardScripts;

        expect(
          scripts.map((item) => item.id).toSet(),
          hasLength(scripts.length),
          reason: '$xChoice / $remoteChoice IDs',
        );
        expect(
          scripts.map((item) => item.name.toLowerCase()).toSet(),
          hasLength(scripts.length),
          reason: '$xChoice / $remoteChoice names',
        );
      }
    }
  });

  test('exact same-ID scripts dedupe without a conflict', () {
    final saved = script('same', 'Same', 'ENTER');
    final plan = SyncMergePlan.merge(
      SyncSnapshot(keyboardScripts: [saved]),
      SyncSnapshot(
        keyboardScripts: [SavedKeyboardScript.fromJson(saved.toJson())],
      ),
    );
    expect(plan.scriptConflicts, isEmpty);
    expect(plan.resolve().keyboardScripts, hasLength(1));
  });

  test('safe setting conflict supports mutable and explicit choices', () {
    final plan = SyncMergePlan.merge(
      SyncSnapshot(settings: const {'theme': 'light', 'localOnly': true}),
      SyncSnapshot(settings: const {'theme': 'dark', 'remoteOnly': 4}),
    );
    plan.settingConflicts.single.selection = SyncChoice.remote;

    expect(plan.resolve().settings, {
      'theme': 'dark',
      'localOnly': true,
      'remoteOnly': 4,
    });
    expect(
      plan
          .resolve(const SyncResolution(settings: {'theme': SyncChoice.local}))
          .settings['theme'],
      'light',
    );
  });

  test('aggregate count, nesting, string, and encoded-size limits apply', () {
    expect(
      () => SyncSnapshot(
        cards: List.generate(
          SyncLimits.maxCards + 1,
          (index) => card('card-$index', const []),
        ),
      ),
      throwsFormatException,
    );
    expect(
      () => SyncSnapshot(
        settings: {
          'deep': List.generate(
            1,
            (_) => List.generate(
              1,
              (_) => List.generate(
                1,
                (_) => List.generate(
                  1,
                  (_) => List.generate(
                    1,
                    (_) => List.generate(
                      1,
                      (_) => List.generate(
                        1,
                        (_) => List.generate(1, (_) => <Object>[true]),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        },
      ),
      throwsFormatException,
    );
    expect(
      () => SyncSnapshot(
        settings: {'large': 'x' * (SyncLimits.maxSettingStringBytes + 1)},
      ),
      throwsFormatException,
    );
    expect(
      () => SyncSnapshot.fromJson(' ' * (SyncLimits.maxEncodedBytes + 1)),
      throwsFormatException,
    );
  });
}

import 'dart:typed_data';

import 'package:chameleonultragui/helpers/definitions.dart';
import 'package:chameleonultragui/helpers/emulation_change.dart';
import 'package:chameleonultragui/sharedprefsprovider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('diffEmulationBlocks reports only changed 16-byte blocks', () {
    final before = Uint8List(48);
    final after = Uint8List.fromList(before);
    after[17] = 0x12;
    after[31] = 0x34;

    final changes = diffEmulationBlocks(before, after);

    expect(changes, hasLength(1));
    expect(changes.single.block, 1);
    expect(changes.single.before, Uint8List(16));
    expect(changes.single.after[1], 0x12);
    expect(changes.single.after[15], 0x34);
  });

  test('diffEmulationBlocks rejects incompatible snapshots', () {
    expect(diffEmulationBlocks(Uint8List(16), Uint8List(32)), isEmpty);
    expect(diffEmulationBlocks(Uint8List(15), Uint8List(15)), isEmpty);
  });

  test('history entry preserves timestamp, tag identity, and block data', () {
    final entry = EmulationChangeEntry(
      timestamp: DateTime.utc(2026, 7, 12, 10, 30),
      slot: 2,
      tagType: TagType.mifare1K,
      uid: 'a1b2c3d4',
      changes: [
        EmulationBlockChange(
          block: 5,
          before: Uint8List(16),
          after: Uint8List.fromList(List.filled(16, 0xAA)),
        ),
      ],
    );

    final decoded = EmulationChangeEntry.fromJson(entry.toJson());

    expect(decoded.timestamp, entry.timestamp);
    expect(decoded.slot, 2);
    expect(decoded.tagType, TagType.mifare1K);
    expect(decoded.uid, 'a1b2c3d4');
    expect(decoded.changes.single.block, 5);
    expect(decoded.changes.single.after, List.filled(16, 0xAA));
  });

  test('preferences retain bounded newest-first change history', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = SharedPreferencesProvider();
    await preferences.load();
    preferences.debugEmulationChangeWriteInterceptor = null;

    for (var index = 0; index < emulationChangeHistoryLimit + 5; index++) {
      await preferences.addEmulationChange(
        EmulationChangeEntry(
          timestamp: DateTime.fromMillisecondsSinceEpoch(index, isUtc: true),
          slot: index % 8,
          tagType: TagType.mifare1K,
          uid: index.toString(),
          changes: [
            EmulationBlockChange(
              block: 1,
              before: Uint8List(16),
              after: Uint8List.fromList(List.filled(16, index & 0xFF)),
            ),
          ],
        ),
      );
    }

    final history = preferences.getEmulationChangeHistory();
    expect(history, hasLength(emulationChangeHistoryLimit));
    expect(history.first.uid, '${emulationChangeHistoryLimit + 4}');
    expect(history.last.uid, '5');

    preferences.clearEmulationChangeHistory();
    expect(preferences.getEmulationChangeHistory(), isEmpty);
  });

  test(
    'history write failure is awaited and leaves stored history unchanged',
    () async {
      SharedPreferences.setMockInitialValues({});
      final preferences = SharedPreferencesProvider();
      await preferences.load();
      preferences.debugEmulationChangeWriteInterceptor = (_) async => false;
      final entry = EmulationChangeEntry(
        timestamp: DateTime.utc(2026, 7, 12),
        slot: 0,
        tagType: TagType.mifare1K,
        uid: '01020304',
        changes: [
          EmulationBlockChange(
            block: 0,
            before: Uint8List(16),
            after: Uint8List.fromList(List.filled(16, 1)),
          ),
        ],
      );

      await expectLater(
        preferences.addEmulationChange(entry),
        throwsA(isA<StateError>()),
      );
      expect(preferences.getEmulationChangeHistory(), isEmpty);
      preferences.debugEmulationChangeWriteInterceptor = null;
    },
  );
}

import 'dart:convert';
import 'dart:typed_data';

import 'package:chameleonultragui/helpers/definitions.dart';

const int emulationChangeHistoryLimit = 100;

class EmulationBlockChange {
  final int block;
  final Uint8List before;
  final Uint8List after;

  EmulationBlockChange({
    required this.block,
    required Uint8List before,
    required Uint8List after,
  })  : before = Uint8List.fromList(before),
        after = Uint8List.fromList(after);

  factory EmulationBlockChange.fromMap(Map<String, dynamic> data) {
    return EmulationBlockChange(
      block: data['block'] as int,
      before: Uint8List.fromList(List<int>.from(data['before'] as List)),
      after: Uint8List.fromList(List<int>.from(data['after'] as List)),
    );
  }

  Map<String, dynamic> toMap() => {
        'block': block,
        'before': before.toList(),
        'after': after.toList(),
      };
}

class EmulationChangeEntry {
  final DateTime timestamp;
  final int slot;
  final TagType tagType;
  final String uid;
  final List<EmulationBlockChange> changes;

  EmulationChangeEntry({
    required this.timestamp,
    required this.slot,
    required this.tagType,
    required this.uid,
    required List<EmulationBlockChange> changes,
  }) : changes = List.unmodifiable(changes);

  factory EmulationChangeEntry.fromJson(String encoded) {
    final data = jsonDecode(encoded) as Map<String, dynamic>;
    return EmulationChangeEntry(
      timestamp: DateTime.fromMillisecondsSinceEpoch(data['timestamp'] as int,
          isUtc: true),
      slot: data['slot'] as int,
      tagType: TagType.values.firstWhere(
        (tagType) => tagType.value == data['tagType'],
        orElse: () => TagType.unknown,
      ),
      uid: data['uid'] as String? ?? '',
      changes: (data['changes'] as List)
          .map((item) => EmulationBlockChange.fromMap(
              Map<String, dynamic>.from(item as Map)))
          .toList(),
    );
  }

  String toJson() => jsonEncode({
        'version': 1,
        'timestamp': timestamp.toUtc().millisecondsSinceEpoch,
        'slot': slot,
        'tagType': tagType.value,
        'uid': uid,
        'changes': changes.map((change) => change.toMap()).toList(),
      });
}

List<EmulationBlockChange> diffEmulationBlocks(
  Uint8List before,
  Uint8List after,
) {
  if (before.length != after.length || before.length % 16 != 0) {
    return const [];
  }

  final changes = <EmulationBlockChange>[];
  for (var offset = 0; offset < before.length; offset += 16) {
    final oldBlock = before.sublist(offset, offset + 16);
    final newBlock = after.sublist(offset, offset + 16);
    var changed = false;
    for (var index = 0; index < 16; index++) {
      if (oldBlock[index] != newBlock[index]) {
        changed = true;
        break;
      }
    }
    if (changed) {
      changes.add(EmulationBlockChange(
        block: offset ~/ 16,
        before: Uint8List.fromList(oldBlock),
        after: Uint8List.fromList(newBlock),
      ));
    }
  }
  return changes;
}

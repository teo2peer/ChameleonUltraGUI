import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:chameleonultragui/helpers/flash.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Uint8List archiveWith(List<ArchiveFile> files) {
    final archive = Archive();
    for (final file in files) {
      archive.addFile(file);
    }
    return Uint8List.fromList(ZipEncoder().encode(archive));
  }

  test('firmware archive extracts one bounded dat and bin', () async {
    final encoded = archiveWith([
      ArchiveFile.bytes('application.dat', [1, 2, 3]),
      ArchiveFile.bytes('application.bin', [4, 5, 6]),
    ]);

    final (dat, bin) = await unpackFirmware(encoded);

    expect(dat, [1, 2, 3]);
    expect(bin, [4, 5, 6]);
  });

  test('firmware archive rejects duplicate target names', () async {
    final encoded = archiveWith([
      ArchiveFile.bytes('duplicate00.dat', [2]),
      ArchiveFile.bytes('application.dat', [2]),
      ArchiveFile.bytes('application.bin', [3]),
    ]);
    final oldName = utf8.encode('duplicate00.dat');
    final newName = utf8.encode('application.dat');
    var replacements = 0;
    for (var offset = 0; offset <= encoded.length - oldName.length; offset++) {
      var matches = true;
      for (var index = 0; index < oldName.length; index++) {
        if (encoded[offset + index] != oldName[index]) {
          matches = false;
          break;
        }
      }
      if (!matches) continue;
      encoded.setRange(offset, offset + newName.length, newName);
      replacements++;
    }
    expect(replacements, 2);

    await expectLater(unpackFirmware(encoded), throwsFormatException);
  });

  test('firmware archive rejects an oversized expanded target', () async {
    final encoded = archiveWith([
      ArchiveFile.bytes(
          'application.dat', List<int>.filled(2 * 1024 * 1024 + 1, 0)),
      ArchiveFile.bytes('application.bin', [1]),
    ]);

    await expectLater(unpackFirmware(encoded), throwsFormatException);
  });
}

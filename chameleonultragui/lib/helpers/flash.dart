import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:chameleonultragui/helpers/github.dart';
import 'package:crypto/crypto.dart';
import 'package:collection/collection.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:chameleonultragui/connector/serial_abstract.dart';
import 'package:chameleonultragui/bridge/chameleon.dart';
import 'package:chameleonultragui/bridge/dfu.dart';
import 'package:chameleonultragui/helpers/general.dart';
import 'package:chameleonultragui/main.dart';
import 'package:chameleonultragui/protobuf/dfu-cc.pb.dart';
import 'dart:math';

const int _maxFirmwareArchiveBytes = 16 * 1024 * 1024;

Future<Uint8List> fetchFirmware(ChameleonDevice device) async {
  var content = await fetchFirmwareFromActions(device);

  if (content.isEmpty) {
    content = await fetchFirmwareFromReleases(device);
  }

  return content;
}

Future<(Uint8List, Uint8List)> unpackFirmware(Uint8List content) =>
    Isolate.run(() => _unpackFirmware(content));

(Uint8List, Uint8List) _unpackFirmware(Uint8List content) {
  const maxExpandedBytes = 32 * 1024 * 1024;
  const maxFirmwareEntryBytes = 2 * 1024 * 1024;
  if (content.isEmpty || content.length > _maxFirmwareArchiveBytes) {
    throw const FormatException('Firmware archive exceeds the 16 MiB limit');
  }
  Uint8List applicationDat = Uint8List(0);
  Uint8List applicationBin = Uint8List(0);

  _validateZipDirectory(content);
  final archive = ZipDecoder().decodeBytes(content, verify: true);
  if (archive.files.length > 64) {
    throw const FormatException('Firmware archive contains too many entries');
  }
  var expandedBytes = 0;
  var foundDat = false;
  var foundBin = false;

  for (var file in archive.files) {
    expandedBytes += file.size;
    if (expandedBytes > maxExpandedBytes) {
      throw const FormatException('Firmware archive expands beyond 32 MiB');
    }
    if (file.isFile) {
      if (file.name == "application.dat") {
        if (foundDat) {
          throw const FormatException('Duplicate application.dat entry');
        }
        foundDat = true;
        if (file.size > maxFirmwareEntryBytes) {
          throw const FormatException('application.dat is too large');
        }
        applicationDat = _readFirmwareEntry(file, maxFirmwareEntryBytes);
      } else if (file.name == "application.bin") {
        if (foundBin) {
          throw const FormatException('Duplicate application.bin entry');
        }
        foundBin = true;
        if (file.size > maxFirmwareEntryBytes) {
          throw const FormatException('application.bin is too large');
        }
        applicationBin = _readFirmwareEntry(file, maxFirmwareEntryBytes);
      }
    }
  }

  return (applicationDat, applicationBin);
}

void _validateZipDirectory(Uint8List content) {
  const endSignature = 0x06054b50;
  const centralSignature = 0x02014b50;
  final data = ByteData.sublistView(content);
  final searchStart = max(0, content.length - 65557);
  int? endOffset;
  for (var offset = content.length - 22; offset >= searchStart; offset--) {
    if (data.getUint32(offset, Endian.little) == endSignature) {
      endOffset = offset;
      break;
    }
  }
  if (endOffset == null || endOffset + 22 > content.length) {
    throw const FormatException('Invalid ZIP end record');
  }
  final disk = data.getUint16(endOffset + 4, Endian.little);
  final centralDisk = data.getUint16(endOffset + 6, Endian.little);
  final diskEntries = data.getUint16(endOffset + 8, Endian.little);
  final entryCount = data.getUint16(endOffset + 10, Endian.little);
  final centralSize = data.getUint32(endOffset + 12, Endian.little);
  final centralOffset = data.getUint32(endOffset + 16, Endian.little);
  final commentLength = data.getUint16(endOffset + 20, Endian.little);
  if (disk != 0 ||
      centralDisk != 0 ||
      diskEntries != entryCount ||
      entryCount > 64 ||
      endOffset + 22 + commentLength != content.length ||
      centralOffset + centralSize > endOffset) {
    throw const FormatException('Unsupported or malformed ZIP directory');
  }

  var position = centralOffset;
  var datEntries = 0;
  var binEntries = 0;
  for (var index = 0; index < entryCount; index++) {
    if (position + 46 > endOffset ||
        data.getUint32(position, Endian.little) != centralSignature) {
      throw const FormatException('Invalid ZIP central-directory entry');
    }
    final flags = data.getUint16(position + 8, Endian.little);
    final compression = data.getUint16(position + 10, Endian.little);
    final expandedSize = data.getUint32(position + 24, Endian.little);
    final nameLength = data.getUint16(position + 28, Endian.little);
    final extraLength = data.getUint16(position + 30, Endian.little);
    final entryCommentLength = data.getUint16(position + 32, Endian.little);
    final entryEnd =
        position + 46 + nameLength + extraLength + entryCommentLength;
    if (entryEnd > endOffset) {
      throw const FormatException('Truncated ZIP central-directory entry');
    }
    final name = utf8.decode(
      content.sublist(position + 46, position + 46 + nameLength),
      allowMalformed: false,
    );
    if (name == 'application.dat' || name == 'application.bin') {
      if ((flags & 0x01) != 0 || (compression != 0 && compression != 8)) {
        throw FormatException('Unsupported ZIP encoding for $name');
      }
      if (expandedSize > 2 * 1024 * 1024) {
        throw FormatException('$name is too large');
      }
      if (name == 'application.dat') {
        datEntries++;
      } else {
        binEntries++;
      }
    }
    position = entryEnd;
  }
  if (position != centralOffset + centralSize ||
      datEntries != 1 ||
      binEntries != 1) {
    throw const FormatException(
        'Firmware ZIP must contain one application.dat and application.bin');
  }
}

Uint8List _readFirmwareEntry(ArchiveFile file, int maxBytes) {
  if (file.compression != CompressionType.none &&
      file.compression != CompressionType.deflate) {
    throw FormatException('Unsupported compression for ${file.name}');
  }
  final output = _BoundedOutputMemoryStream(maxBytes);
  try {
    file.writeContent(output);
  } on StateError catch (error) {
    throw FormatException('${file.name}: ${error.message}');
  }
  final bytes = Uint8List.fromList(output.getBytes());
  if (bytes.length != file.size) {
    throw FormatException('${file.name} expanded size does not match metadata');
  }
  if (file.crc32 case final expected? when getCrc32(bytes) != expected) {
    throw FormatException('${file.name} CRC32 mismatch');
  }
  return bytes;
}

class _BoundedOutputMemoryStream extends OutputMemoryStream {
  final int maxBytes;

  _BoundedOutputMemoryStream(this.maxBytes)
      : super(
            size: maxBytes < OutputMemoryStream.defaultBufferSize
                ? maxBytes
                : OutputMemoryStream.defaultBufferSize);

  void _ensureCapacity(int additional) {
    if (additional < 0 || length + additional > maxBytes) {
      throw StateError('expanded data exceeds the $maxBytes-byte limit');
    }
  }

  @override
  void writeByte(int value) {
    _ensureCapacity(1);
    super.writeByte(value);
  }

  @override
  void writeBytes(List<int> bytes, {int? length}) {
    _ensureCapacity(length ?? bytes.length);
    super.writeBytes(bytes, length: length);
  }

  @override
  void writeStream(InputStream stream) {
    _ensureCapacity(stream.length);
    super.writeStream(stream);
  }
}

Future<File> createTempFile() async {
  final tempDir = await Directory.systemTemp.createTemp('firmware');
  final tempFile = File('${tempDir.path}/flash.zip');
  return tempFile;
}

void validateFiles(Uint8List dat, Uint8List bin) {
  if (dat.isEmpty || bin.isEmpty) {
    throw ("Empty firmware file");
  }

  final metadata = Packet.fromBuffer(dat);
  if (!metadata.hasSignedCommand()) {
    throw ("Package isn't signed");
  }

  final command = metadata.signedCommand.command;
  if (!command.hasInit()) {
    throw ("Package command doesn't have init");
  }

  final hash = command.init.hash;
  final expectedHash = hash.hash.reversed;
  final actualHash = switch (hash.hashType) {
    HashType.SHA128 => sha1,
    HashType.SHA256 => sha256,
    HashType.SHA512 => sha512,
    _ => throw ("Unsupported hash type ${hash.hashType}"),
  }
      .convert(bin)
      .bytes;

  if (!const IterableEquality().equals(expectedHash, actualHash)) {
    throw ("Hashes don't match! expected: ${expectedHash.toList()}, actual: $actualHash");
  }
}

Future<void> flashFirmware(ChameleonGUIState appState,
    {ScaffoldMessengerState? scaffoldMessenger,
    ChameleonDevice? device,
    bool enterDFU = true}) async {
  Uint8List applicationDat, applicationBin;

  Uint8List content = await fetchFirmware(
      (device != null) ? device : appState.connector!.device);

  (applicationDat, applicationBin) = await unpackFirmware(content);

  await flashFile(appState.communicator, appState, applicationDat,
      applicationBin, (progress) => appState.setProgressBar(progress / 100),
      firmwareZip: content,
      scaffoldMessenger: scaffoldMessenger,
      enterDFU: enterDFU);
}

Future<void> flashFirmwareZip(ChameleonGUIState appState,
    {ScaffoldMessengerState? scaffoldMessenger, bool enterDFU = true}) async {
  Uint8List applicationDat, applicationBin;

  PlatformFile? result = await FilePicker.pickFile();

  if (result != null) {
    File file = File(result.path!);
    if (result.size > _maxFirmwareArchiveBytes ||
        await file.length() > _maxFirmwareArchiveBytes) {
      throw const FormatException('Firmware archive exceeds the 16 MiB limit');
    }
    final firmwareZip = await file.readAsBytes();
    (applicationDat, applicationBin) = await unpackFirmware(firmwareZip);

    await flashFile(appState.communicator, appState, applicationDat,
        applicationBin, (progress) => appState.setProgressBar(progress / 100),
        firmwareZip: firmwareZip,
        scaffoldMessenger: scaffoldMessenger,
        enterDFU: enterDFU);
  }
}

Future<void> flashFile(
    ChameleonCommunicator? connection,
    ChameleonGUIState appState,
    Uint8List applicationDat,
    Uint8List applicationBin,
    void Function(int progress) callback,
    {bool enterDFU = true,
    List<int> firmwareZip = const [],
    ScaffoldMessengerState? scaffoldMessenger}) async {
  await Isolate.run(() => validateFiles(applicationDat, applicationBin));
  final connector = appState.connector;
  if (connector == null) throw StateError('No connector available for DFU');
  final expectedDevice = connector.device;

  // Flashing easter egg
  var rng = Random();
  var randomNumber = rng.nextInt(100) + 1;
  appState.easterEgg = false;
  if (randomNumber == 1) {
    appState.easterEgg = true;
  }

  if (enterDFU) {
    await connection?.enterDFUMode();
    await connector.performDisconnect();
  }

  if (connector.isOpen) {
    await connector.performDisconnect();
  }

  if (Platform.isAndroid) {
    // BLE appears bit earlier than USB
    await asyncSleep(1000);
  }

  List<Chameleon> chameleons = [];
  final discoveryDeadline = DateTime.now().add(const Duration(seconds: 30));
  while (chameleons.isEmpty) {
    if (DateTime.now().isAfter(discoveryDeadline)) {
      throw TimeoutException('Timed out waiting for the device in DFU mode');
    }
    await asyncSleep(250);
    chameleons = await connector
        .availableChameleons(true)
        .timeout(const Duration(seconds: 5));
    if (expectedDevice != ChameleonDevice.none) {
      chameleons = chameleons
          .where((candidate) => candidate.device == expectedDevice)
          .toList();
    }
  }

  if (chameleons.length != 1) {
    throw StateError(
        'Multiple compatible DFU devices found. Leave only the intended device connected.');
  }
  final toFlash = chameleons.single;

  final connected = await connector.connectSpecificDevice(toFlash.port);
  if (!connected || !connector.connected) {
    await connector.performDisconnect();
    throw StateError('Could not connect to the selected DFU device');
  }

  if (scaffoldMessenger != null) {
    scaffoldMessenger.removeCurrentSnackBar();
  }

  try {
    var dfu = DFUCommunicator(appState.log!,
        port: connector, viaBLE: toFlash.type == ConnectionType.ble);
    appState.changesMade();
    await dfu.setPRN();
    await dfu.getMTU();
    await dfu.flashFirmware(0x01, applicationDat, callback);
    await dfu.flashFirmware(0x02, applicationBin, callback);
    appState.log!.i("Firmware flashed!");
  } finally {
    await connector.performDisconnect();
    await asyncSleep(500); // allow exit DFU mode
    appState.changesMade();
  }
}

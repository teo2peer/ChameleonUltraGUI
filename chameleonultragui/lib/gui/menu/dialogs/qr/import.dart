import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:chameleonultragui/gui/component/qrcode_scanner.dart';
import 'package:crypto/crypto.dart';

// Localizations
import 'package:chameleonultragui/generated/i18n/app_localizations.dart';

class QrCodeImport extends StatefulWidget {
  const QrCodeImport({super.key});

  @override
  State<StatefulWidget> createState() => QrCodeImportState();
}

class QrCodeImportState extends State<QrCodeImport> {
  static const int _maxChunks = 64;
  static const int _maxChunkBytes = 4096;
  static const int _maxTotalBytes = 16 * 1024;
  String? shasum;
  int? qrCodeChunks;
  List<String?> chunks = [];

  int get currentChunk => chunks.whereType<String>().length;
  String get resultingJson => chunks.whereType<String>().join();
  bool get checksumMatches =>
      shasum != null &&
      sha256.convert(utf8.encode(resultingJson)).toString() == shasum;
  bool get isComplete =>
      qrCodeChunks != null && currentChunk == qrCodeChunks && checksumMatches;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(AppLocalizations.of(context)!.qrCodeImport),
      actions: [
        TextButton(
          onPressed: () {
            Navigator.of(context).pop();
          },
          child: Text(AppLocalizations.of(context)!.cancel),
        ),
        TextButton(
          onPressed: () async {
            if (isComplete) {
              Navigator.pop(context, resultingJson);
              return;
            }

            String? qrCodeData = await showDialog<String>(
                context: context,
                builder: (BuildContext context) {
                  return const QrCodeScanner();
                });
            if (qrCodeData == null) return;
            Object? decoded;
            try {
              decoded = jsonDecode(qrCodeData);
            } on FormatException {
              return;
            }
            if (decoded is! Map<String, dynamic>) return;
            if (decoded["Info"] == "Chameleon Ultra GUI Settings") {
              final digest = decoded["sha256"];
              final count = decoded["chunks"];
              if (decoded.keys
                      .toSet()
                      .difference({"Info", "sha256", "chunks"}).isNotEmpty ||
                  digest is! String ||
                  !RegExp(r'^[0-9a-f]{64}$').hasMatch(digest) ||
                  count is! int ||
                  count < 1 ||
                  count > _maxChunks) {
                return;
              }
              setState(() {
                shasum = digest;
                qrCodeChunks = count;
                chunks = List<String?>.filled(count, null);
              });
            } else {
              final digest = decoded["sha256"];
              final count = decoded["chunks"];
              final index = decoded["index"];
              final value = decoded["data"];
              if (decoded["Info"] != "Chameleon Ultra GUI Settings Chunk" ||
                  digest != shasum ||
                  count != qrCodeChunks ||
                  index is! int ||
                  index < 0 ||
                  index >= chunks.length ||
                  value is! String ||
                  utf8.encode(value).length > _maxChunkBytes) {
                return;
              }
              final next = chunks.toList()..[index] = value;
              if (utf8.encode(next.whereType<String>().join()).length >
                  _maxTotalBytes) {
                return;
              }
              setState(() => chunks = next);
            }
          },
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              qrCodeChunks == null
                  ? Text(AppLocalizations.of(context)!.startScanning)
                  : isComplete
                      ? Text(AppLocalizations.of(context)!.finishImport)
                      : Text(AppLocalizations.of(context)!.scan_next_qr_code(
                          "${currentChunk + 1}", "${qrCodeChunks! + 1}")),
              const SizedBox(width: 5),
              if (checksumMatches)
                Tooltip(
                  message: AppLocalizations.of(context)!.checksumOk,
                  child: const Icon(Icons.check),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

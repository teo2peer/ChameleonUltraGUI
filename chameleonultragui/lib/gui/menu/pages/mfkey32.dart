import 'package:chameleonultragui/gui/component/error_page.dart';
import 'package:chameleonultragui/gui/menu/dialogs/dictionary/export.dart';
import 'package:chameleonultragui/helpers/general.dart';
import 'package:chameleonultragui/helpers/mifare_classic/reader_key_recovery.dart';
import 'package:chameleonultragui/main.dart';
import 'package:chameleonultragui/recovery/recovery.dart' as recovery;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter/services.dart';

// Localizations
import 'package:chameleonultragui/generated/i18n/app_localizations.dart';

class Mfkey32Menu extends StatefulWidget {
  const Mfkey32Menu({super.key});

  @override
  Mfkey32MenuState createState() => Mfkey32MenuState();
}

class Mfkey32MenuState extends State<Mfkey32Menu> {
  final TextEditingController controller = TextEditingController();
  late Future<(bool, int)> detectionStatusFuture;
  bool isDetectionMode = false;
  int detectionCount = -1;
  List<Uint8List> keys = [];
  bool saveKeys = false;
  bool loading = false;
  String outputUid = "";
  List<Widget> displayKeys = [];
  int progress = -1;

  @override
  void initState() {
    super.initState();
    detectionStatusFuture = getMf1DetectionStatus();
  }

  Future<(bool, int)> getMf1DetectionStatus() async {
    var appState = context.read<ChameleonGUIState>();

    return (
      await appState.communicator!.isMf1DetectionMode(),
      await appState.communicator!.getMf1DetectionCount(),
    );
  }

  Future<void> updateDetectionStatus() async {
    var (mode, count) = await getMf1DetectionStatus();

    setState(() {
      isDetectionMode = mode;
      detectionCount = count;
    });
  }

  Future<void> handleMfkeyCalculation() async {
    var appState = context.read<ChameleonGUIState>();

    var count = await appState.communicator!.getMf1DetectionCount();
    final detections =
        await appState.communicator!.getMf1DetectionRecords(count);
    final results = await recoverReaderKeys(
      detections: detections,
      solver: (request) async {
        final recovered = await recovery.mfkey32(request);
        return recovered.isEmpty ? null : recovered.first;
      },
      isCancelled: () => !mounted,
      onProgress: (completed, total, _) {
        if (mounted) {
          setState(() =>
              progress = total == 0 ? 100 : (completed * 100 / total).round());
        }
      },
    );
    if (!mounted) return;

    final unique = <String, Uint8List>{};
    final widgets = <Widget>[];
    for (final result in results) {
      final uid =
          result.target.uid.toRadixString(16).padLeft(8, '0').toUpperCase();
      final key = result.key;
      if (key != null) {
        final keyHex = bytesToHex(key).toUpperCase();
        unique[keyHex] = key;
        outputUid = outputUid.isEmpty ? uid : outputUid;
        widgets.add(ListTile(
          leading: const Icon(Icons.vpn_key),
          title: Text(keyHex,
              style: const TextStyle(
                  fontFamily: 'RobotoMono', fontWeight: FontWeight.bold)),
          subtitle: Text(
              'UID $uid | sector ${result.target.sector} | key ${result.target.keyType}'),
          onTap: () => Clipboard.setData(ClipboardData(text: keyHex)),
        ));
      } else {
        widgets.add(ListTile(
          leading: const Icon(Icons.key_off),
          title: const Text('Not enough valid authentication pairs'),
          subtitle: Text(
              'UID $uid | sector ${result.target.sector} | key ${result.target.keyType} | ${result.transcriptCount} transcripts'),
        ));
      }
    }
    setState(() {
      keys = unique.values.toList();
      displayKeys = widgets;
      saveKeys = keys.isNotEmpty;
    });
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    var localizations = AppLocalizations.of(context)!;
    return FutureBuilder(
      future: detectionStatusFuture,
      builder: (BuildContext context, AsyncSnapshot snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Scaffold(
            appBar: AppBar(
              title: const Text('Mfkey32'),
            ),
            body: const Center(child: CircularProgressIndicator()),
          );
        } else if (snapshot.hasError) {
          return ErrorPage(errorMessage: snapshot.error.toString());
        } else {
          if (detectionCount == -1) {
            updateDetectionStatus();
            return Scaffold(
              appBar: AppBar(
                title: const Text('Mfkey32'),
              ),
              body: const Center(child: CircularProgressIndicator()),
            );
          }

          return Scaffold(
            appBar: AppBar(
              title: const Text('Mfkey32'),
            ),
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  mainAxisSize: MainAxisSize.max,
                  children: [
                    Text(
                      localizations.recover_keys_via("Mfkey32"),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 25.0),
                    loading
                        ? OutlinedButton(
                            onPressed: null,
                            child: Text(localizations
                                .recover_keys_nonce(detectionCount)),
                          )
                        : ElevatedButton(
                            onPressed: (detectionCount > 0)
                                ? () async {
                                    setState(() {
                                      loading = true;
                                    });
                                    try {
                                      await handleMfkeyCalculation();
                                    } catch (error) {
                                      if (context.mounted) {
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(SnackBar(
                                                content:
                                                    Text(error.toString())));
                                      }
                                    } finally {
                                      if (mounted) {
                                        setState(() {
                                          loading = false;
                                          progress = -1;
                                        });
                                      }
                                    }
                                  }
                                : null,
                            child: Text(localizations
                                .recover_keys_nonce(detectionCount)),
                          ),
                    const SizedBox(height: 8.0),
                    Visibility(
                      visible: saveKeys,
                      child: ElevatedButton(
                        onPressed: () {
                          showDialog<String>(
                              context: context,
                              builder: (BuildContext context) =>
                                  DictionaryExportMenu(
                                      defaultName: outputUid, keys: keys));
                        },
                        child: Text(localizations.save_recovered_keys),
                      ),
                    ),
                    const SizedBox(height: 16.0),
                    Expanded(
                      child: ListView(
                        children: [
                          ...displayKeys,
                          loading
                              ? const Center(child: CircularProgressIndicator())
                              : const SizedBox(),
                          loading
                              ? const SizedBox(height: 8.0)
                              : const SizedBox(),
                          loading
                              ? Center(
                                  child:
                                      Text(localizations.recovery_in_progress))
                              : const SizedBox(),
                        ],
                      ),
                    ),
                    if (progress != -1)
                      LinearProgressIndicator(
                        value: (progress / 100).toDouble(),
                      )
                  ],
                ),
              ),
            ),
          );
        }
      },
    );
  }
}

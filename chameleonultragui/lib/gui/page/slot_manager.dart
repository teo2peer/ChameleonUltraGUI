import 'dart:typed_data';

import 'package:chameleonultragui/gui/component/card_list.dart';
import 'package:chameleonultragui/gui/component/error_page.dart';
import 'package:chameleonultragui/gui/menu/dialogs/slot/settings.dart';
import 'package:chameleonultragui/helpers/definitions.dart';
import 'package:chameleonultragui/helpers/general.dart';
import 'package:chameleonultragui/helpers/mifare_classic/general.dart';
import 'package:chameleonultragui/helpers/mifare_classic/slot_transfer.dart';
import 'package:chameleonultragui/helpers/mifare_ultralight/general.dart';
import 'package:chameleonultragui/main.dart';
import 'package:chameleonultragui/sharedprefsprovider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:provider/provider.dart';

// Localizations
import 'package:chameleonultragui/generated/i18n/app_localizations.dart';

class SlotManagerPage extends StatefulWidget {
  const SlotManagerPage({super.key});

  @override
  SlotManagerPageState createState() => SlotManagerPageState();
}

class SlotManagerPageState extends State<SlotManagerPage> {
  List<SlotTypes> usedSlots = List.generate(8, (_) => SlotTypes());

  List<EnabledSlotInfo> enabledSlots = List.generate(
    8,
    (_) => EnabledSlotInfo(),
  );

  List<SlotNames> slotData = List.generate(8, (_) => SlotNames());

  int progress = -1;
  int gridPosition = 0;
  bool onlyOneSlot = false;
  Future<void>? _loadFuture;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loadFuture ??= loadSlotData();
  }

  Future<void> loadSlotData() async {
    if (progress != -1) {
      return;
    }

    var appState = context.read<ChameleonGUIState>();
    var localizations = AppLocalizations.of(context)!;

    final communicator = appState.communicator;
    if (communicator == null) {
      throw StateError('No connected device');
    }
    final loadedSlots = await communicator.getSlotTagTypes();
    final loadedEnabledSlots = await communicator.getEnabledSlots();
    final loadedSlotData = await communicator.getSlotTagNames();

    for (SlotNames slot in loadedSlotData) {
      slot.hf = slot.hf.isEmpty ? localizations.no_name : slot.hf;
      slot.lf = slot.lf.isEmpty ? localizations.no_name : slot.lf;
    }
    usedSlots = loadedSlots;
    enabledSlots = loadedEnabledSlots;
    slotData = loadedSlotData;
  }

  void refreshSlot() {
    setUploadState(-1);

    if (!mounted) return;
    var appState = context.read<ChameleonGUIState>();
    if (appState.connector?.connected == true &&
        appState.communicator != null) {
      setState(() => _loadFuture = loadSlotData());
    }
    appState.changesMade();
  }

  void setUploadState(int progressBar) {
    if (!mounted) {
      progress = progressBar;
      return;
    }

    setState(() {
      progress = progressBar;
    });

    var appState = context.read<ChameleonGUIState>();
    appState.changesMade();
  }

  Future<void> onTap(
    CardSave card,
    dynamic close,
    AppLocalizations localizations,
  ) async {
    if (!mounted || progress != -1) return;

    var appState = Provider.of<ChameleonGUIState>(context, listen: false);
    final targetSlot = gridPosition;
    final originalTag = card.tag;
    final isClassicEV1 =
        isMifareClassic(originalTag) &&
        chameleonTagSaveCheckForMifareClassicEV1(card);
    final slotTag = isClassicEV1 ? TagType.mifare2K : originalTag;

    try {
      CardData? antiCollision;
      Uint8List? lfId;
      int? sourceBlockCount;
      if (isMifareClassic(originalTag)) {
        sourceBlockCount = mfClassicGetBlockCount(
          chameleonTagTypeGetMfClassicType(originalTag),
          isEV1: isClassicEV1,
        );
        validateSlotDump(
          card.data,
          expectedCount: sourceBlockCount,
          recordSize: mifareClassicBlockSize,
          maxStoredCount: 256,
        );
      } else if (isMifareUltralight(originalTag)) {
        validateSlotDump(
          card.data,
          expectedCount: mfUltralightGetPagesCount(originalTag),
          recordSize: 4,
        );
      }
      if (isMifareClassic(originalTag) || isMifareUltralight(originalTag)) {
        antiCollision = CardData(
          uid: hexToBytes(card.uid),
          atqa: card.atqa,
          sak: card.sak,
          ats: card.ats,
        );
        validateHfAntiCollisionData(antiCollision);
      } else {
        lfId = _prepareLfId(card, originalTag);
      }

      setUploadState(0);
      await appState.runSlotOperation(() async {
        if (isMifareClassic(originalTag)) {
          close(context, card.name);

          await appState.communicator!.setReaderDeviceMode(false);
          await appState.communicator!.enableSlot(
            targetSlot,
            TagFrequency.hf,
            true,
          );
          await appState.communicator!.activateSlot(targetSlot);
          await appState.communicator!.setSlotType(targetSlot, slotTag);
          await appState.communicator!.setDefaultDataToSlot(
            targetSlot,
            slotTag,
          );
          await appState.communicator!.setMf1AntiCollision(antiCollision!);

          final blockCount = mfClassicGetBlockCount(
            chameleonTagTypeGetMfClassicType(slotTag),
          );
          final chunks = planMifareClassicUpload(card.data, blockCount);
          for (final chunk in chunks) {
            await appState.communicator!.setMf1BlockData(
              chunk.startBlock,
              chunk.data,
            );
            final nextBlock =
                chunk.startBlock + chunk.data.length ~/ mifareClassicBlockSize;
            setUploadState((nextBlock / blockCount * 100).round());
            await asyncSleep(1);
          }
          for (final chunk in chunks) {
            final chunkBlockCount = chunk.data.length ~/ mifareClassicBlockSize;
            final actual = await appState.communicator!.mf1GetEmulatorBlock(
              chunk.startBlock,
              chunkBlockCount,
            );
            if (!_sameBytes(actual, chunk.data)) {
              throw StateError(
                'MIFARE Classic verification failed at block ${chunk.startBlock}',
              );
            }
          }

          setUploadState(100);

          await appState.communicator!.setSlotTagName(
            targetSlot,
            (card.name.isEmpty) ? localizations.no_name : card.name,
            TagFrequency.hf,
          );
          await appState.communicator!.saveSlotData();
          appState.changesMade();
        } else if (isEM410X(originalTag)) {
          close(context, card.name);
          await appState.communicator!.setReaderDeviceMode(false);
          await appState.communicator!.enableSlot(
            targetSlot,
            TagFrequency.lf,
            true,
          );
          await appState.communicator!.activateSlot(targetSlot);
          TagType slotTagType = originalTag == TagType.em410XElectra
              ? TagType.em410XElectra
              : TagType.em410X;
          await appState.communicator!.setSlotType(targetSlot, slotTagType);
          await appState.communicator!.setDefaultDataToSlot(
            targetSlot,
            slotTagType,
          );
          await appState.communicator!.setEM410XEmulatorID(lfId!);
          await appState.communicator!.setSlotTagName(
            targetSlot,
            (card.name.isEmpty) ? localizations.no_name : card.name,
            TagFrequency.lf,
          );
          await appState.communicator!.saveSlotData();
          appState.changesMade();
        } else if (originalTag == TagType.hidProx) {
          close(context, card.name);
          await appState.communicator!.setReaderDeviceMode(false);
          await appState.communicator!.enableSlot(
            targetSlot,
            TagFrequency.lf,
            true,
          );
          await appState.communicator!.activateSlot(targetSlot);
          await appState.communicator!.setSlotType(targetSlot, originalTag);
          await appState.communicator!.setDefaultDataToSlot(
            targetSlot,
            originalTag,
          );
          await appState.communicator!.setHIDProxEmulatorID(lfId!);
          await appState.communicator!.setSlotTagName(
            targetSlot,
            (card.name.isEmpty) ? localizations.no_name : card.name,
            TagFrequency.lf,
          );
          await appState.communicator!.saveSlotData();
          appState.changesMade();
        } else if (originalTag == TagType.viking) {
          close(context, card.name);
          await appState.communicator!.setReaderDeviceMode(false);
          await appState.communicator!.enableSlot(
            targetSlot,
            TagFrequency.lf,
            true,
          );
          await appState.communicator!.activateSlot(targetSlot);
          await appState.communicator!.setSlotType(targetSlot, originalTag);
          await appState.communicator!.setDefaultDataToSlot(
            targetSlot,
            originalTag,
          );
          await appState.communicator!.setVikingEmulatorID(lfId!);
          await appState.communicator!.setSlotTagName(
            targetSlot,
            (card.name.isEmpty) ? localizations.no_name : card.name,
            TagFrequency.lf,
          );
          await appState.communicator!.saveSlotData();
          appState.changesMade();
        } else if (originalTag == TagType.pac) {
          close(context, card.name);
          await appState.communicator!.setReaderDeviceMode(false);
          await appState.communicator!.enableSlot(
            targetSlot,
            TagFrequency.lf,
            true,
          );
          await appState.communicator!.activateSlot(targetSlot);
          await appState.communicator!.setSlotType(targetSlot, originalTag);
          await appState.communicator!.setDefaultDataToSlot(
            targetSlot,
            originalTag,
          );
          await appState.communicator!.setPacEmulatorID(lfId!);
          await appState.communicator!.setSlotTagName(
            targetSlot,
            (card.name.isEmpty) ? localizations.no_name : card.name,
            TagFrequency.lf,
          );
          await appState.communicator!.saveSlotData();
          appState.changesMade();
        } else if (originalTag == TagType.ioProx) {
          close(context, card.name);
          await appState.communicator!.setReaderDeviceMode(false);
          await appState.communicator!.enableSlot(
            targetSlot,
            TagFrequency.lf,
            true,
          );
          await appState.communicator!.activateSlot(targetSlot);
          await appState.communicator!.setSlotType(targetSlot, originalTag);
          await appState.communicator!.setDefaultDataToSlot(
            targetSlot,
            originalTag,
          );
          await appState.communicator!.setIoProxEmulatorID(lfId!);
          await appState.communicator!.setSlotTagName(
            targetSlot,
            (card.name.isEmpty) ? localizations.no_name : card.name,
            TagFrequency.lf,
          );
          await appState.communicator!.saveSlotData();
          appState.changesMade();
        } else if (originalTag == TagType.idteck) {
          close(context, card.name);
          await appState.communicator!.setReaderDeviceMode(false);
          await appState.communicator!.enableSlot(
            targetSlot,
            TagFrequency.lf,
            true,
          );
          await appState.communicator!.activateSlot(targetSlot);
          await appState.communicator!.setSlotType(targetSlot, originalTag);
          await appState.communicator!.setDefaultDataToSlot(
            targetSlot,
            originalTag,
          );
          await appState.communicator!.setIdteckEmulatorID(lfId!);
          await appState.communicator!.setSlotTagName(
            targetSlot,
            (card.name.isEmpty) ? localizations.no_name : card.name,
            TagFrequency.lf,
          );
          await appState.communicator!.saveSlotData();
          appState.changesMade();
        } else if (isMifareUltralight(originalTag)) {
          close(context, card.name);

          await appState.communicator!.setReaderDeviceMode(false);
          await appState.communicator!.enableSlot(
            targetSlot,
            TagFrequency.hf,
            true,
          );
          await appState.communicator!.activateSlot(targetSlot);
          await appState.communicator!.setSlotType(targetSlot, originalTag);
          await appState.communicator!.setDefaultDataToSlot(
            targetSlot,
            originalTag,
          );
          await appState.communicator!.setMf1AntiCollision(antiCollision!);

          final pageCount = mfUltralightGetPagesCount(originalTag);
          final pageChunks = planFixedSizeSlotUpload(
            card.data,
            recordCount: pageCount,
            recordSize: 4,
            maxChunkBytes: 128,
          );
          for (final chunk in pageChunks) {
            await appState.communicator!.mf0EmulatorWritePages(
              chunk.startRecord,
              chunk.data,
            );
            final nextPage = chunk.startRecord + chunk.data.length ~/ 4;
            setUploadState((nextPage / pageCount * 100).round());
            await asyncSleep(1);
          }
          for (final chunk in pageChunks) {
            final count = chunk.data.length ~/ 4;
            final actual = await appState.communicator!.mf0EmulatorReadPages(
              chunk.startRecord,
              count,
            );
            if (!_sameBytes(actual, chunk.data)) {
              throw StateError(
                'MIFARE Ultralight verification failed at page ${chunk.startRecord}',
              );
            }
          }

          if (card.extraData.ultralightVersion.isNotEmpty) {
            await appState.communicator!.mf0EmulatorSetVersionData(
              card.extraData.ultralightVersion,
            );
          }

          if (card.extraData.ultralightSignature.isNotEmpty) {
            await appState.communicator!.mf0EmulatorSetSignatureData(
              card.extraData.ultralightSignature,
            );
          }

          if (card.extraData.ultralightCounters.isNotEmpty) {
            for (int i = 0; i < card.extraData.ultralightCounters.length; i++) {
              await appState.communicator!.mf0EmulatorSetCounterData(
                i,
                card.extraData.ultralightCounters[i],
                true,
              );
            }
          }

          if (mfUltralightHasCounters(originalTag)) {
            await appState.communicator!.mf0ResetAuthCount();
          }

          setUploadState(100);

          await appState.communicator!.setSlotTagName(
            targetSlot,
            (card.name.isEmpty) ? localizations.no_name : card.name,
            TagFrequency.hf,
          );
          await appState.communicator!.saveSlotData();
          appState.changesMade();
        } else {
          appState.log!.e("Can't write this card type yet.");
          close(context, card.name);
        }
      });
    } catch (error, stackTrace) {
      appState.log?.e(
        'Slot upload failed',
        error: error,
        stackTrace: stackTrace,
      );
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(error.toString())));
      }
    } finally {
      refreshSlot();
    }
  }

  Uint8List? _prepareLfId(CardSave card, TagType type) {
    if (isEM410X(type)) {
      final id = hexToBytes(card.uid);
      final expectedLength = type == TagType.em410XElectra ? 13 : 5;
      if (id.length != expectedLength) {
        throw FormatException(
          'Invalid LF dump: expected $expectedLength ID bytes, got ${id.length}',
        );
      }
      return id;
    }
    final expectedLength = switch (type) {
      TagType.hidProx => 13,
      TagType.viking => 4,
      TagType.pac => 8,
      TagType.ioProx => 16,
      TagType.idteck => 8,
      _ => null,
    };
    if (expectedLength == null) return null;
    final id = type == TagType.hidProx
        ? hexToBytes(HIDCard.fromUID(card.uid).toString())
        : hexToBytes(card.uid);
    if (id.length != expectedLength) {
      throw FormatException(
        'Invalid LF dump: expected $expectedLength ID bytes, got ${id.length}',
      );
    }
    return id;
  }

  bool _sameBytes(Uint8List first, Uint8List second) {
    if (first.length != second.length) return false;
    for (var index = 0; index < first.length; index++) {
      if (first[index] != second[index]) return false;
    }
    return true;
  }

  Future<String?> cardSelectDialog(BuildContext context) {
    var appState = context.read<ChameleonGUIState>();
    var tags = appState.sharedPreferencesProvider.getCards();

    // Don't allow user to upload more tags while already uploading dump
    if (progress != -1) {
      return Future.value("");
    }

    tags.sort((a, b) => a.name.compareTo(b.name));

    return showSearch<String>(
      context: context,
      delegate: CardSearchDelegate(cards: tags, onTap: onTap),
    );
  }

  @override
  Widget build(BuildContext context) {
    var localizations = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(title: Text(localizations.slot_manager)),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            FutureBuilder(
              future: _loadFuture,
              builder: (BuildContext context, AsyncSnapshot<void> snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting ||
                    progress != -1) {
                  return const Center(child: CircularProgressIndicator());
                } else if (snapshot.hasError) {
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ErrorPage(errorMessage: snapshot.error.toString()),
                      IconButton(
                        onPressed: refreshSlot,
                        icon: const Icon(Icons.refresh),
                      ),
                    ],
                  );
                } else {
                  return Expanded(
                    child: AlignedGridView.count(
                      padding: const EdgeInsets.all(20),
                      crossAxisCount: MediaQuery.of(context).size.width >= 700
                          ? 2
                          : 1,
                      crossAxisSpacing: 10,
                      mainAxisSpacing: 10,
                      itemCount: 8,
                      itemBuilder: (BuildContext context, int index) {
                        return Container(
                          constraints: const BoxConstraints(
                            maxHeight: 160,
                            minHeight: 100,
                          ),
                          child: ElevatedButton(
                            onPressed: () {
                              setState(() {
                                gridPosition = index;
                              });
                              cardSelectDialog(context);
                            },
                            style: ButtonStyle(
                              shape:
                                  WidgetStateProperty.all<
                                    RoundedRectangleBorder
                                  >(
                                    RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(18.0),
                                    ),
                                  ),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.only(
                                top: 8.0,
                                left: 8.0,
                                bottom: 6.0,
                              ),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Row(
                                    children: [
                                      Icon(
                                        Icons.nfc,
                                        color: enabledSlots[index].any()
                                            ? Colors.green
                                            : Colors.deepOrange,
                                      ),
                                      const SizedBox(width: 5),
                                      Expanded(
                                        child: Text(
                                          "${localizations.slot} ${index + 1}",
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 20),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.start,
                                    children: [
                                      const Icon(Icons.credit_card),
                                      const SizedBox(width: 5),
                                      Expanded(
                                        child: Text(
                                          "${slotData[index].hf} (${chameleonTagToString(usedSlots[index].hf, localizations)})",
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.start,
                                          children: [
                                            const Icon(Icons.wifi),
                                            const SizedBox(width: 5),
                                            Expanded(
                                              child: Text(
                                                "${slotData[index].lf} (${chameleonTagToString(usedSlots[index].lf, localizations)})",
                                                maxLines: 2,
                                                overflow: TextOverflow.ellipsis,
                                                softWrap: true,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      IconButton(
                                        onPressed: () {
                                          showDialog(
                                            context: context,
                                            builder: (BuildContext context) {
                                              return SlotSettings(
                                                slot: index,
                                                refresh: refreshSlot,
                                              );
                                            },
                                          );
                                        },
                                        icon: const Icon(Icons.settings),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  );
                }
              },
            ),
            if (progress != -1) ...[
              const SizedBox(height: 32),
              Text(localizations.uploading_dump),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: LinearProgressIndicator(
                  value: (progress / 100).toDouble(),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

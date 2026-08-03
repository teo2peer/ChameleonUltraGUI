import 'package:chameleonultragui/generated/i18n/app_localizations.dart';
import 'package:chameleonultragui/gui/component/module_version_navigation.dart';
import 'package:chameleonultragui/gui/menu/dialogs/card/edit.dart';
import 'package:chameleonultragui/gui/menu/dialogs/confirm_delete.dart';
import 'package:chameleonultragui/gui/menu/dialogs/dictionary/export.dart';
import 'package:chameleonultragui/gui/menu/pages/dump_editor.dart';
import 'package:chameleonultragui/helpers/definitions.dart';
import 'package:chameleonultragui/helpers/general.dart';
import 'package:chameleonultragui/helpers/mifare_classic/general.dart';
import 'package:chameleonultragui/helpers/mifare_ultralight/general.dart';
import 'package:chameleonultragui/helpers/module_versions.dart';
import 'package:chameleonultragui/main.dart';
import 'package:chameleonultragui/sharedprefsprovider.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

class CardViewMenu extends StatefulWidget {
  final CardSave tagSave;
  final Future<void> Function(CardSave card) onMove;

  const CardViewMenu({super.key, required this.tagSave, required this.onMove});

  @override
  CardViewMenuState createState() => CardViewMenuState();
}

class CardViewMenuState extends State<CardViewMenu> {
  late CardSave currentSavedCard;
  String uid = '';

  @override
  void initState() {
    super.initState();
    currentSavedCard = widget.tagSave;
    _updateUid(currentSavedCard);
  }

  void _updateUid(CardSave card) {
    if (chameleonTagToFrequency(card.tag) == TagFrequency.lf) {
      uid = getLFCardFromUID(card.tag, card.uid).toViewableString();
    } else {
      uid = card.uid;
    }
  }

  void _refreshCardData() {
    if (!mounted) return;
    final cards = context
        .read<ChameleonGUIState>()
        .sharedPreferencesProvider
        .getCards();
    final updatedCard = cards.firstWhere(
      (card) => card.id == currentSavedCard.id,
      orElse: () => currentSavedCard,
    );
    _updateUid(updatedCard);
    setState(() => currentSavedCard = updatedCard);
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context)!;
    final appState = context.watch<ChameleonGUIState>();

    Widget copyButton(String value) => IconButton(
      onPressed: () => Clipboard.setData(ClipboardData(text: value)),
      icon: const Icon(Icons.copy),
    );

    return AlertDialog(
      title: Text(
        currentSavedCard.name,
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${localizations.uid}: $uid',
                    softWrap: true,
                    overflow: TextOverflow.visible,
                  ),
                ),
                copyButton(currentSavedCard.uid),
              ],
            ),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${localizations.tag_type}: ${chameleonTagToString(currentSavedCard.tag, localizations)}',
                    softWrap: true,
                    overflow: TextOverflow.visible,
                  ),
                ),
                copyButton(
                  chameleonTagToString(currentSavedCard.tag, localizations),
                ),
              ],
            ),
            if (chameleonTagToFrequency(currentSavedCard.tag) ==
                TagFrequency.hf) ...[
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${localizations.sak}: ${bytesToHex(u8ToBytes(currentSavedCard.sak))}',
                      softWrap: true,
                      overflow: TextOverflow.visible,
                    ),
                  ),
                  copyButton(
                    currentSavedCard.sak == 0
                        ? localizations.unavailable
                        : bytesToHex(u8ToBytes(currentSavedCard.sak)),
                  ),
                ],
              ),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${localizations.atqa}: ${currentSavedCard.atqa.isNotEmpty ? bytesToHexSpace(currentSavedCard.atqa) : localizations.unavailable}',
                      softWrap: true,
                      overflow: TextOverflow.visible,
                    ),
                  ),
                  copyButton(
                    currentSavedCard.atqa.isNotEmpty
                        ? bytesToHex(currentSavedCard.atqa)
                        : localizations.unavailable,
                  ),
                ],
              ),
              if (isMifareClassic(currentSavedCard.tag)) ...[
                const SizedBox(height: 8),
                ElevatedButton(
                  onPressed:
                      mfClassicGetKeysFromDump(currentSavedCard.data).isNotEmpty
                      ? () async {
                          final keys = mfClassicGetKeysFromDump(
                            currentSavedCard.data,
                          );
                          await showDialog(
                            context: context,
                            builder: (_) => DictionaryExportMenu(keys: keys),
                          );
                        }
                      : null,
                  child: Text(localizations.export_to_dictionary),
                ),
              ],
              if (isMifareUltralight(currentSavedCard.tag)) ...[
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${localizations.ultralight_version}: ${currentSavedCard.extraData.ultralightVersion.isNotEmpty ? bytesToHexSpace(currentSavedCard.extraData.ultralightVersion) : localizations.unavailable}',
                        softWrap: true,
                        overflow: TextOverflow.visible,
                      ),
                    ),
                    copyButton(
                      currentSavedCard.extraData.ultralightVersion.isNotEmpty
                          ? bytesToHexSpace(
                              currentSavedCard.extraData.ultralightVersion,
                            )
                          : localizations.unavailable,
                    ),
                  ],
                ),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${localizations.ultralight_signature}: ${currentSavedCard.extraData.ultralightSignature.isNotEmpty ? bytesToHexSpace(currentSavedCard.extraData.ultralightSignature) : localizations.unavailable}',
                        softWrap: true,
                        overflow: TextOverflow.visible,
                      ),
                    ),
                    copyButton(
                      currentSavedCard.extraData.ultralightSignature.isNotEmpty
                          ? bytesToHexSpace(
                              currentSavedCard.extraData.ultralightSignature,
                            )
                          : localizations.unavailable,
                    ),
                  ],
                ),
              ],
            ],
          ],
        ),
      ),
      actions: [
        Wrap(
          spacing: 4,
          runSpacing: 4,
          alignment: WrapAlignment.end,
          children: [
            IconButton(
              tooltip: localizations.move_card,
              onPressed: () async {
                await widget.onMove(currentSavedCard);
                _refreshCardData();
              },
              icon: const Icon(Icons.drive_file_move_outline),
            ),
            IconButton(
              onPressed: () async {
                await showDialog(
                  context: context,
                  builder: (_) => CardEditMenu(tagSave: currentSavedCard),
                );
                _refreshCardData();
              },
              icon: const Icon(Icons.edit),
            ),
            IconButton(
              onPressed: () async {
                final cards = appState.sharedPreferencesProvider.getCards();
                final duplicate = CardSave.fromJson(currentSavedCard.toJson())
                  ..id = const Uuid().v4()
                  ..name = '${currentSavedCard.name} (${localizations.copy})';
                cards.add(duplicate);
                await appState.sharedPreferencesProvider.setCards(cards);
                appState.changesMade();
                if (!context.mounted) return;
                Navigator.pop(context);
              },
              icon: const Icon(Icons.copy_all),
            ),
            if (isMifareClassic(currentSavedCard.tag) ||
                isMifareUltralight(currentSavedCard.tag))
              IconButton(
                onPressed: () async {
                  await Navigator.push(
                    context,
                    ModulePageRoute(
                      moduleId: ModuleId.dumpEditor,
                      builder: (_) => DumpEditor(
                        cardSave: currentSavedCard,
                        onSave: (dumpData) async {
                          final updatedCard = CardSave(
                            id: currentSavedCard.id,
                            uid: currentSavedCard.uid,
                            sak: currentSavedCard.sak,
                            atqa: currentSavedCard.atqa,
                            name: currentSavedCard.name,
                            tag: currentSavedCard.tag,
                            data: dumpData,
                            ats: currentSavedCard.ats,
                            extraData: currentSavedCard.extraData,
                            folderId: currentSavedCard.folderId,
                            color: currentSavedCard.color,
                          );
                          final cards = appState.sharedPreferencesProvider
                              .getCards();
                          final index = cards.indexWhere(
                            (card) => card.id == currentSavedCard.id,
                          );
                          if (index >= 0) cards[index] = updatedCard;
                          await appState.sharedPreferencesProvider.setCards(
                            cards,
                          );
                          appState.changesMade();
                          if (!context.mounted) return;
                          Navigator.pop(context);
                        },
                      ),
                    ),
                  );
                },
                icon: const Icon(Icons.edit_document),
              ),
            IconButton(
              onPressed: () async {
                await showDialog(
                  context: context,
                  builder: (dialogContext) => AlertDialog(
                    title: Text(localizations.select_save_format),
                    actions: [
                      if (isMifareClassic(currentSavedCard.tag))
                        ElevatedButton(
                          onPressed: () async {
                            await saveTag(
                              currentSavedCard,
                              dialogContext,
                              true,
                            );
                            if (dialogContext.mounted) {
                              Navigator.pop(dialogContext);
                            }
                          },
                          child: Text(localizations.save_as('.bin')),
                        ),
                      ElevatedButton(
                        onPressed: () async {
                          await saveTag(currentSavedCard, dialogContext, false);
                          if (dialogContext.mounted) {
                            Navigator.pop(dialogContext);
                          }
                        },
                        child: Text(localizations.save_as('.json')),
                      ),
                    ],
                  ),
                );
                if (context.mounted) Navigator.pop(context);
              },
              icon: const Icon(Icons.download_rounded),
            ),
            IconButton(
              onPressed: () async {
                if (appState.sharedPreferencesProvider.getConfirmDelete()) {
                  final confirm = await showDialog<bool>(
                    context: context,
                    builder: (_) => ConfirmDeletionMenu(
                      thingBeingDeleted: currentSavedCard.name,
                    ),
                  );
                  if (confirm != true) return;
                }
                final cards = appState.sharedPreferencesProvider
                    .getCards()
                    .where((card) => card.id != currentSavedCard.id)
                    .toList();
                await appState.sharedPreferencesProvider.setCards(cards);
                appState.changesMade();
                if (context.mounted) Navigator.pop(context);
              },
              icon: const Icon(Icons.delete_outline),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              child: Text(localizations.ok),
            ),
          ],
        ),
      ],
    );
  }
}

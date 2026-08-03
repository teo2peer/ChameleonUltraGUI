import 'dart:convert';
import 'dart:io';

import 'package:chameleonultragui/generated/i18n/app_localizations.dart';
import 'package:chameleonultragui/gui/component/card_button.dart';
import 'package:chameleonultragui/gui/component/element_button.dart';
import 'package:chameleonultragui/gui/component/module_version_navigation.dart';
import 'package:chameleonultragui/gui/menu/dialogs/card/create.dart';
import 'package:chameleonultragui/gui/menu/dialogs/card/edit.dart';
import 'package:chameleonultragui/gui/menu/dialogs/card/view.dart';
import 'package:chameleonultragui/gui/menu/dialogs/confirm_delete.dart';
import 'package:chameleonultragui/gui/menu/dialogs/dictionary/edit.dart';
import 'package:chameleonultragui/gui/menu/dialogs/dictionary/view.dart';
import 'package:chameleonultragui/gui/page/data_sync.dart';
import 'package:chameleonultragui/helpers/card_save_converters.dart';
import 'package:chameleonultragui/helpers/definitions.dart';
import 'package:chameleonultragui/helpers/general.dart';
import 'package:chameleonultragui/helpers/mifare_classic/general.dart';
import 'package:chameleonultragui/helpers/module_versions.dart';
import 'package:chameleonultragui/helpers/validators.dart';
import 'package:chameleonultragui/main.dart';
import 'package:chameleonultragui/sharedprefsprovider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:path/path.dart' show basename;
import 'package:provider/provider.dart';

class SavedCardsPage extends StatefulWidget {
  const SavedCardsPage({super.key});

  @override
  SavedCardsPageState createState() => SavedCardsPageState();
}

class SavedCardsPageState extends State<SavedCardsPage> {
  TagType selectedType = TagType.unknown;
  String? currentFolderId;
  String? currentDictionaryFolderId;

  Future<void> _createCard() async {
    await showDialog(
      context: context,
      builder: (_) => CardCreateMenu(folderId: currentFolderId),
    );
  }

  Future<void> _createDictionary() async {
    await showDialog(
      context: context,
      builder: (_) => DictionaryEditMenu(
        dictionary: Dictionary(name: '', folderId: currentDictionaryFolderId),
        isNew: true,
      ),
    );
  }

  Widget _createMenuButton(
    ChameleonGUIState appState, {
    required bool elevated,
    required bool dictionary,
  }) {
    final localizations = AppLocalizations.of(context)!;
    return MenuAnchor(
      menuChildren: [
        MenuItemButton(
          leadingIcon: Icon(dictionary ? Icons.key : Icons.credit_card),
          onPressed: dictionary ? _createDictionary : _createCard,
          child: Text(
            dictionary ? localizations.dictionary : localizations.card,
          ),
        ),
        MenuItemButton(
          leadingIcon: const Icon(Icons.create_new_folder),
          onPressed: () => dictionary ? _editDictionaryFolder() : _editFolder(),
          child: Text(localizations.folder),
        ),
      ],
      builder: (context, controller, child) {
        void toggleMenu() {
          controller.isOpen ? controller.close() : controller.open();
        }

        if (elevated) {
          return ElevatedButton(
            onPressed: toggleMenu,
            style: customCardButtonStyle(appState),
            child: const Icon(Icons.add),
          );
        }
        return IconButton(
          onPressed: toggleMenu,
          tooltip: localizations.create,
          icon: const Icon(Icons.add),
        );
      },
    );
  }

  Future<Color?> _pickFolderColor(Color initial) async {
    final localizations = AppLocalizations.of(context)!;
    var picked = initial;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(localizations.folder_color),
        content: SingleChildScrollView(
          child: ColorPicker(
            pickerColor: picked,
            onColorChanged: (value) => picked = value,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(localizations.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(localizations.ok),
          ),
        ],
      ),
    );
    return accepted == true ? picked : null;
  }

  Future<({String name, Color color})?> _folderDialog({
    required String name,
    required Color color,
    required bool editing,
  }) async {
    final localizations = AppLocalizations.of(context)!;
    final controller = TextEditingController(text: name);
    var selectedColor = color;
    return showDialog<({String name, Color color})>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(
            editing ? localizations.edit_folder : localizations.create_folder,
          ),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: InputDecoration(
              labelText: localizations.name,
              prefixIcon: IconButton(
                icon: Icon(Icons.folder, color: selectedColor),
                tooltip: localizations.pick_color,
                onPressed: () async {
                  final picked = await _pickFolderColor(selectedColor);
                  if (picked != null) {
                    setDialogState(() => selectedColor = picked);
                  }
                },
              ),
            ),
            onSubmitted: (_) {
              final value = controller.text.trim();
              if (value.isNotEmpty) {
                Navigator.pop(dialogContext, (
                  name: value,
                  color: selectedColor,
                ));
              }
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(localizations.cancel),
            ),
            TextButton(
              onPressed: () {
                final value = controller.text.trim();
                if (value.isNotEmpty) {
                  Navigator.pop(dialogContext, (
                    name: value,
                    color: selectedColor,
                  ));
                }
              },
              child: Text(editing ? localizations.save : localizations.create),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _editFolder([CardFolder? folder]) async {
    final result = await _folderDialog(
      name: folder?.name ?? '',
      color: folder?.color ?? Colors.deepOrange,
      editing: folder != null,
    );
    if (result == null || !mounted) return;
    final appState = context.read<ChameleonGUIState>();
    final folders = appState.sharedPreferencesProvider.getCardFolders();
    if (folder == null) {
      folders.add(
        CardFolder(
          name: result.name,
          color: result.color,
          parentId: currentFolderId,
        ),
      );
    } else {
      final index = folders.indexWhere((item) => item.id == folder.id);
      if (index >= 0) {
        folders[index]
          ..name = result.name
          ..color = result.color;
      }
    }
    await appState.sharedPreferencesProvider.setCardFolders(folders);
    appState.changesMade();
  }

  Future<void> _editDictionaryFolder([DictionaryFolder? folder]) async {
    final result = await _folderDialog(
      name: folder?.name ?? '',
      color: folder?.color ?? Colors.deepOrange,
      editing: folder != null,
    );
    if (result == null || !mounted) return;
    final appState = context.read<ChameleonGUIState>();
    final folders = appState.sharedPreferencesProvider.getDictionaryFolders();
    if (folder == null) {
      folders.add(
        DictionaryFolder(
          name: result.name,
          color: result.color,
          parentId: currentDictionaryFolderId,
        ),
      );
    } else {
      final index = folders.indexWhere((item) => item.id == folder.id);
      if (index >= 0) {
        folders[index]
          ..name = result.name
          ..color = result.color;
      }
    }
    await appState.sharedPreferencesProvider.setDictionaryFolders(folders);
    appState.changesMade();
  }

  Set<String> _folderTreeIds<T>(
    String rootId,
    List<T> folders,
    String Function(T folder) id,
    String? Function(T folder) parentId,
  ) {
    final result = <String>{rootId};
    var changed = true;
    while (changed) {
      changed = false;
      for (final folder in folders) {
        final parent = parentId(folder);
        if (parent != null &&
            result.contains(parent) &&
            result.add(id(folder))) {
          changed = true;
        }
      }
    }
    return result;
  }

  Future<String?> _pickFolderDestination({CardFolder? movingFolder}) {
    final folders = context
        .read<ChameleonGUIState>()
        .sharedPreferencesProvider
        .getCardFolders();
    final excluded = movingFolder == null
        ? <String>{}
        : _folderTreeIds(
            movingFolder.id,
            folders,
            (folder) => folder.id,
            (folder) => folder.parentId,
          );
    return _destinationDialog(
      rootName: AppLocalizations.of(context)!.saved_cards,
      folders: folders
          .where((folder) => !excluded.contains(folder.id))
          .map(
            (folder) => (id: folder.id, name: folder.name, color: folder.color),
          )
          .toList(),
    );
  }

  Future<String?> _pickDictionaryFolderDestination({
    DictionaryFolder? movingFolder,
  }) {
    final folders = context
        .read<ChameleonGUIState>()
        .sharedPreferencesProvider
        .getDictionaryFolders();
    final excluded = movingFolder == null
        ? <String>{}
        : _folderTreeIds(
            movingFolder.id,
            folders,
            (folder) => folder.id,
            (folder) => folder.parentId,
          );
    return _destinationDialog(
      rootName: AppLocalizations.of(context)!.dictionaries,
      folders: folders
          .where((folder) => !excluded.contains(folder.id))
          .map(
            (folder) => (id: folder.id, name: folder.name, color: folder.color),
          )
          .toList(),
    );
  }

  Future<String?> _destinationDialog({
    required String rootName,
    required List<({String id, String name, Color color})> folders,
  }) {
    final localizations = AppLocalizations.of(context)!;
    return showDialog<String>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: Text(localizations.move_to_folder),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(dialogContext, '__root__'),
            child: ListTile(
              leading: const Icon(Icons.home),
              title: Text(rootName),
            ),
          ),
          ...folders.map(
            (folder) => SimpleDialogOption(
              onPressed: () => Navigator.pop(dialogContext, folder.id),
              child: ListTile(
                leading: Icon(Icons.folder, color: folder.color),
                title: Text(folder.name),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _moveCard(CardSave card) async {
    final destination = await _pickFolderDestination();
    if (destination == null || !mounted) return;
    final appState = context.read<ChameleonGUIState>();
    final cards = appState.sharedPreferencesProvider.getCards();
    final index = cards.indexWhere((item) => item.id == card.id);
    if (index < 0) return;
    cards[index].folderId = destination == '__root__' ? null : destination;
    await appState.sharedPreferencesProvider.setCards(cards);
    appState.changesMade();
  }

  Future<void> _moveDictionary(Dictionary dictionary) async {
    final destination = await _pickDictionaryFolderDestination();
    if (destination == null || !mounted) return;
    final appState = context.read<ChameleonGUIState>();
    final dictionaries = appState.sharedPreferencesProvider.getDictionaries();
    final index = dictionaries.indexWhere((item) => item.id == dictionary.id);
    if (index < 0) return;
    dictionaries[index].folderId = destination == '__root__'
        ? null
        : destination;
    await appState.sharedPreferencesProvider.setDictionaries(dictionaries);
    appState.changesMade();
  }

  Future<void> _moveFolder(CardFolder folder) async {
    final destination = await _pickFolderDestination(movingFolder: folder);
    if (destination == null || !mounted) return;
    final appState = context.read<ChameleonGUIState>();
    final folders = appState.sharedPreferencesProvider.getCardFolders();
    final index = folders.indexWhere((item) => item.id == folder.id);
    if (index < 0) return;
    folders[index].parentId = destination == '__root__' ? null : destination;
    await appState.sharedPreferencesProvider.setCardFolders(folders);
    appState.changesMade();
  }

  Future<void> _moveDictionaryFolder(DictionaryFolder folder) async {
    final destination = await _pickDictionaryFolderDestination(
      movingFolder: folder,
    );
    if (destination == null || !mounted) return;
    final appState = context.read<ChameleonGUIState>();
    final folders = appState.sharedPreferencesProvider.getDictionaryFolders();
    final index = folders.indexWhere((item) => item.id == folder.id);
    if (index < 0) return;
    folders[index].parentId = destination == '__root__' ? null : destination;
    await appState.sharedPreferencesProvider.setDictionaryFolders(folders);
    appState.changesMade();
  }

  Future<bool> _confirmFolderDelete(String name, String message) async {
    final localizations = AppLocalizations.of(context)!;
    return await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text(localizations.delete_folder_title(name)),
            content: Text(message),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: Text(localizations.cancel),
              ),
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: Text(localizations.delete),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _deleteFolder(CardFolder folder) async {
    final localizations = AppLocalizations.of(context)!;
    if (!await _confirmFolderDelete(
      folder.name,
      localizations.delete_card_folder_confirmation,
    )) {
      return;
    }
    if (!mounted) return;
    final appState = context.read<ChameleonGUIState>();
    final folders = appState.sharedPreferencesProvider.getCardFolders();
    final ids = _folderTreeIds(
      folder.id,
      folders,
      (item) => item.id,
      (item) => item.parentId,
    );
    final cards = appState.sharedPreferencesProvider
        .getCards()
        .where((card) => !ids.contains(card.folderId))
        .toList();
    await appState.sharedPreferencesProvider.setCards(cards);
    await appState.sharedPreferencesProvider.setCardFolders(
      folders.where((item) => !ids.contains(item.id)).toList(),
    );
    appState.changesMade();
  }

  Future<void> _deleteDictionaryFolder(DictionaryFolder folder) async {
    final localizations = AppLocalizations.of(context)!;
    if (!await _confirmFolderDelete(
      folder.name,
      localizations.delete_dictionary_folder_confirmation,
    )) {
      return;
    }
    if (!mounted) return;
    final appState = context.read<ChameleonGUIState>();
    final folders = appState.sharedPreferencesProvider.getDictionaryFolders();
    final ids = _folderTreeIds(
      folder.id,
      folders,
      (item) => item.id,
      (item) => item.parentId,
    );
    final dictionaries = appState.sharedPreferencesProvider
        .getDictionaries()
        .where((dictionary) => !ids.contains(dictionary.folderId))
        .toList();
    await appState.sharedPreferencesProvider.setDictionaries(dictionaries);
    await appState.sharedPreferencesProvider.setDictionaryFolders(
      folders.where((item) => !ids.contains(item.id)).toList(),
    );
    appState.changesMade();
  }

  Future<void> _exportFolder(CardFolder folder) async {
    final localizations = AppLocalizations.of(context)!;
    final provider = context
        .read<ChameleonGUIState>()
        .sharedPreferencesProvider;
    final folders = provider.getCardFolders();
    final ids = _folderTreeIds(
      folder.id,
      folders,
      (item) => item.id,
      (item) => item.parentId,
    );
    final bundle = CardFolderBundle(
      rootFolderId: folder.id,
      folders: folders.where((item) => ids.contains(item.id)).toList(),
      cards: provider
          .getCards()
          .where((card) => ids.contains(card.folderId))
          .toList(),
    );
    await FilePicker.saveFile(
      dialogTitle: localizations.export_folder,
      fileName: '${folder.name}.json',
      bytes: const Utf8Encoder().convert(bundle.toJson()),
    );
  }

  Future<void> _exportDictionaryFolder(DictionaryFolder folder) async {
    final localizations = AppLocalizations.of(context)!;
    final provider = context
        .read<ChameleonGUIState>()
        .sharedPreferencesProvider;
    final folders = provider.getDictionaryFolders();
    final ids = _folderTreeIds(
      folder.id,
      folders,
      (item) => item.id,
      (item) => item.parentId,
    );
    final bundle = DictionaryFolderBundle(
      rootFolderId: folder.id,
      folders: folders.where((item) => ids.contains(item.id)).toList(),
      dictionaries: provider
          .getDictionaries()
          .where((dictionary) => ids.contains(dictionary.folderId))
          .toList(),
    );
    await FilePicker.saveFile(
      dialogTitle: localizations.export_dictionary_folder,
      fileName: '${folder.name}.json',
      bytes: const Utf8Encoder().convert(bundle.toJson()),
    );
  }

  Future<void> _importFolderSource(String source) async {
    final localizations = AppLocalizations.of(context)!;
    try {
      final bundle = CardFolderBundle.fromJson(source);
      final appState = context.read<ChameleonGUIState>();
      final folders = appState.sharedPreferencesProvider.getCardFolders();
      final cards = appState.sharedPreferencesProvider.getCards();
      final idMap = <String, String>{
        for (final folder in bundle.folders)
          folder.id: CardFolder(name: 'Imported').id,
      };
      for (final imported in bundle.folders) {
        folders.add(
          CardFolder(
            id: idMap[imported.id],
            name: imported.name,
            color: imported.color,
            parentId: imported.id == bundle.rootFolderId
                ? currentFolderId
                : idMap[imported.parentId],
          ),
        );
      }
      for (final imported in bundle.cards) {
        final copy = CardSave.fromJson(imported.toJson())
          ..id = CardFolder(name: 'Imported').id
          ..folderId = idMap[imported.folderId];
        cards.add(copy);
      }
      await appState.sharedPreferencesProvider.setCardFolders(folders);
      await appState.sharedPreferencesProvider.setCards(cards);
      appState.changesMade();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(localizations.invalid_folder_export)),
      );
    }
  }

  Future<void> _importDictionaryFolderSource(String source) async {
    final localizations = AppLocalizations.of(context)!;
    try {
      final bundle = DictionaryFolderBundle.fromJson(source);
      final appState = context.read<ChameleonGUIState>();
      final folders = appState.sharedPreferencesProvider.getDictionaryFolders();
      final dictionaries = appState.sharedPreferencesProvider.getDictionaries();
      final idMap = <String, String>{
        for (final folder in bundle.folders)
          folder.id: DictionaryFolder(name: 'Imported').id,
      };
      for (final imported in bundle.folders) {
        folders.add(
          DictionaryFolder(
            id: idMap[imported.id],
            name: imported.name,
            color: imported.color,
            parentId: imported.id == bundle.rootFolderId
                ? currentDictionaryFolderId
                : idMap[imported.parentId],
          ),
        );
      }
      for (final imported in bundle.dictionaries) {
        final copy = Dictionary.fromJson(imported.toJson())
          ..id = DictionaryFolder(name: 'Imported').id
          ..folderId = idMap[imported.folderId];
        dictionaries.add(copy);
      }
      await appState.sharedPreferencesProvider.setDictionaryFolders(folders);
      await appState.sharedPreferencesProvider.setDictionaries(dictionaries);
      appState.changesMade();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(localizations.invalid_dictionary_folder_export)),
      );
    }
  }

  Future<void> _importCard() async {
    final result = await FilePicker.pickFile();
    if (result?.path == null || !mounted) return;
    final file = File(result!.path!);
    final contents = await file.readAsBytes();
    if (!mounted) return;
    try {
      final source = const Utf8Decoder().convert(contents);
      Object? decoded;
      try {
        decoded = jsonDecode(source);
      } catch (_) {
        // Text dump formats are identified below.
      }
      if (decoded is Map && decoded['format'] == 'chameleon-ultra-gui-folder') {
        await _importFolderSource(source);
        return;
      }
      final CardSave card;
      if (source.contains('"Created": "proxmark3",')) {
        card = pm3JsonToCardSave(source);
      } else if (source.contains('Filetype: Flipper NFC device')) {
        card = flipperNfcToCardSave(source);
      } else if (source.contains('+Sector: 0')) {
        card = mctToCardSave(source);
      } else if (source.contains('Filetype: Flipper RFID key')) {
        card = flipperRfidToCardSave(source);
      } else {
        card = CardSave.fromJson(source);
      }
      card
        ..name = _fileStem(file.path)
        ..folderId = currentFolderId;
      final appState = context.read<ChameleonGUIState>();
      final cards = appState.sharedPreferencesProvider.getCards()..add(card);
      await appState.sharedPreferencesProvider.setCards(cards);
      appState.changesMade();
    } catch (_) {
      await _importRawCard(contents, _fileStem(file.path));
    }
  }

  String _fileStem(String path) {
    final name = basename(path);
    return name.contains('.') ? name.split('.').first : name;
  }

  Future<void> _importRawCard(Uint8List contents, String fileName) async {
    selectedType = getTagTypeByDumpSize(contents.length);
    if (selectedType == TagType.unknown || !mounted) return;

    final classic = isMifareClassic(selectedType);
    final uid4 = classic ? contents.sublist(0, 4) : Uint8List(0);
    final uid7 = classic
        ? contents.sublist(0, 7)
        : Uint8List.fromList([
            ...contents.sublist(0, 3),
            ...contents.sublist(4, 8),
          ]);
    final uidController = TextEditingController(
      text: bytesToHexSpace(classic ? uid4 : uid7),
    );
    final sakController = TextEditingController(
      text: bytesToHex(Uint8List.fromList([classic ? contents[5] : 0])),
    );
    final atqaController = TextEditingController(
      text: bytesToHexSpace(
        classic
            ? Uint8List.fromList([contents[7], contents[6]])
            : Uint8List.fromList([0x00, 0x44]),
      ),
    );
    final nameController = TextEditingController(text: fileName);
    var useFourByteUid = classic;
    final formKey = GlobalKey<FormState>();
    final localizations = AppLocalizations.of(context)!;

    await showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(localizations.correct_tag_data),
          content: SingleChildScrollView(
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (classic)
                    SegmentedButton<bool>(
                      segments: [
                        ButtonSegment(
                          value: true,
                          label: Text(localizations.uid_len(4)),
                        ),
                        ButtonSegment(
                          value: false,
                          label: Text(localizations.uid_len(7)),
                        ),
                      ],
                      selected: {useFourByteUid},
                      onSelectionChanged: (selection) {
                        setDialogState(() {
                          useFourByteUid = selection.single;
                          uidController.text = bytesToHexSpace(
                            useFourByteUid ? uid4 : uid7,
                          );
                        });
                      },
                    ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: uidController,
                    inputFormatters: hexFormatter,
                    validator: (value) => validateHex(
                      value,
                      localizations,
                      exactBytes: useFourByteUid ? 4 : 7,
                      fieldName: localizations.uid,
                    ),
                    decoration: InputDecoration(labelText: localizations.uid),
                  ),
                  TextFormField(
                    controller: sakController,
                    inputFormatters: hexFormatter,
                    validator: (value) => validateHex(
                      value,
                      localizations,
                      exactBytes: 1,
                      fieldName: localizations.sak,
                    ),
                    decoration: InputDecoration(labelText: localizations.sak),
                  ),
                  TextFormField(
                    controller: atqaController,
                    inputFormatters: hexFormatter,
                    validator: (value) => validateHex(
                      value,
                      localizations,
                      exactBytes: 2,
                      fieldName: localizations.atqa,
                    ),
                    decoration: InputDecoration(labelText: localizations.atqa),
                  ),
                  TextFormField(
                    controller: nameController,
                    validator: (value) => validateName(value, localizations),
                    decoration: InputDecoration(labelText: localizations.name),
                  ),
                  DropdownButton<TagType>(
                    value: selectedType,
                    items: getTagTypesByFrequency(TagFrequency.hf)
                        .map(
                          (type) => DropdownMenuItem(
                            value: type,
                            child: Text(
                              chameleonTagToString(type, localizations),
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value != null) {
                        setDialogState(() => selectedType = value);
                      }
                    },
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(localizations.cancel),
            ),
            ElevatedButton(
              onPressed: () async {
                if (formKey.currentState?.validate() != true) return;
                final blockSize = isMifareClassic(selectedType) ? 16 : 4;
                final blocks = <Uint8List>[];
                for (
                  var offset = 0;
                  offset + blockSize <= contents.length;
                  offset += blockSize
                ) {
                  blocks.add(contents.sublist(offset, offset + blockSize));
                }
                final card = CardSave(
                  name: nameController.text.trim(),
                  sak: hexToBytes(sakController.text).first,
                  atqa: hexToBytes(atqaController.text),
                  uid: uidController.text,
                  tag: selectedType,
                  data: blocks,
                  folderId: currentFolderId,
                );
                final appState = context.read<ChameleonGUIState>();
                final cards = appState.sharedPreferencesProvider.getCards()
                  ..add(card);
                await appState.sharedPreferencesProvider.setCards(cards);
                appState.changesMade();
                if (dialogContext.mounted) Navigator.pop(dialogContext);
              },
              child: Text(localizations.save),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _importDictionary() async {
    final result = await FilePicker.pickFile();
    if (result?.path == null || !mounted) return;
    final file = File(result!.path!);
    final String contents;
    try {
      contents = const Utf8Decoder().convert(await file.readAsBytes());
    } catch (_) {
      return;
    }
    if (!mounted) return;
    Object? decoded;
    try {
      decoded = jsonDecode(contents);
    } catch (_) {
      // Plain dictionary files are handled below.
    }
    if (decoded is Map &&
        decoded['format'] == 'chameleon-ultra-gui-dictionary-folder') {
      await _importDictionaryFolderSource(contents);
      return;
    }
    final dictionary = Dictionary.fromString(
      contents,
      name: result.name.split('.').first,
    )..folderId = currentDictionaryFolderId;
    if (dictionary.keys.isEmpty) return;
    final appState = context.read<ChameleonGUIState>();
    final dictionaries = appState.sharedPreferencesProvider.getDictionaries()
      ..add(dictionary);
    await appState.sharedPreferencesProvider.setDictionaries(dictionaries);
    appState.changesMade();
  }

  Widget _sectionHeader({
    required String title,
    required List<Widget> actions,
    required bool compact,
  }) {
    final text = Text(
      title,
      textAlign: TextAlign.center,
      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
    );
    return Padding(
      padding: const EdgeInsets.all(8),
      child: compact
          ? Row(
              children: [
                SizedBox(width: actions.length * 48),
                Expanded(child: text),
                Row(mainAxisSize: MainAxisSize.min, children: actions),
              ],
            )
          : text,
    );
  }

  Widget _desktopControls({
    required ChameleonGUIState appState,
    required VoidCallback onImport,
    required bool dictionary,
    Widget? backButton,
  }) {
    return Visibility(
      visible: MediaQuery.of(context).size.width >= 700,
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Row(
          children: [
            if (backButton != null) ...[
              Expanded(child: backButton),
              const SizedBox(width: 10),
            ],
            Expanded(
              child: ElevatedButton(
                onPressed: onImport,
                style: customCardButtonStyle(appState),
                child: const Icon(Icons.file_upload),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _createMenuButton(
                appState,
                elevated: true,
                dictionary: dictionary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<ChameleonGUIState>();
    final localizations = AppLocalizations.of(context)!;
    final compact = MediaQuery.of(context).size.width < 700;
    final allCards = appState.sharedPreferencesProvider.getCards();
    final allCardFolders = appState.sharedPreferencesProvider.getCardFolders();
    final cards = allCards
        .where((card) => card.folderId == currentFolderId)
        .toList();
    final cardFolders = allCardFolders
        .where((folder) => folder.parentId == currentFolderId)
        .toList();
    final currentFolder = currentFolderId == null
        ? null
        : allCardFolders.cast<CardFolder?>().firstWhere(
            (folder) => folder?.id == currentFolderId,
            orElse: () => null,
          );
    final allDictionaries = appState.sharedPreferencesProvider
        .getDictionaries();
    final allDictionaryFolders = appState.sharedPreferencesProvider
        .getDictionaryFolders();
    final dictionaries = allDictionaries
        .where((dictionary) => dictionary.folderId == currentDictionaryFolderId)
        .toList();
    final dictionaryFolders = allDictionaryFolders
        .where((folder) => folder.parentId == currentDictionaryFolderId)
        .toList();
    final currentDictionaryFolder = currentDictionaryFolderId == null
        ? null
        : allDictionaryFolders.cast<DictionaryFolder?>().firstWhere(
            (folder) => folder?.id == currentDictionaryFolderId,
            orElse: () => null,
          );

    return Scaffold(
      appBar: AppBar(
        title: Text(localizations.saved_cards),
        leading: currentFolder == null
            ? null
            : IconButton(
                tooltip: localizations.parent_folder,
                onPressed: () =>
                    setState(() => currentFolderId = currentFolder.parentId),
                icon: const Icon(Icons.arrow_back),
              ),
        actions: [
          IconButton(
            tooltip: localizations.data_sync_title,
            icon: const Icon(Icons.sync_alt),
            onPressed: () => Navigator.push(
              context,
              ModulePageRoute<void>(
                moduleId: ModuleId.dataSync,
                builder: (_) => const DataSyncPage(),
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Card(
              child: Column(
                children: [
                  _sectionHeader(
                    title: currentFolder?.name ?? localizations.cards,
                    compact: compact,
                    actions: [
                      IconButton(
                        onPressed: _importCard,
                        icon: const Icon(Icons.file_upload),
                      ),
                      _createMenuButton(
                        appState,
                        elevated: false,
                        dictionary: false,
                      ),
                    ],
                  ),
                  _desktopControls(
                    appState: appState,
                    onImport: _importCard,
                    dictionary: false,
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      child: AlignedGridView.count(
                        clipBehavior: Clip.antiAlias,
                        physics: const NeverScrollableScrollPhysics(),
                        padding: const EdgeInsets.all(10),
                        crossAxisCount: MediaQuery.of(context).size.width >= 700
                            ? 2
                            : 1,
                        crossAxisSpacing: 10,
                        mainAxisSpacing: 10,
                        itemCount: cardFolders.length + cards.length,
                        shrinkWrap: true,
                        itemBuilder: (context, index) {
                          if (index < cardFolders.length) {
                            final folder = cardFolders[index];
                            final subtree = _folderTreeIds(
                              folder.id,
                              allCardFolders,
                              (item) => item.id,
                              (item) => item.parentId,
                            );
                            final count = allCards
                                .where(
                                  (card) => subtree.contains(card.folderId),
                                )
                                .length;
                            return ElementButton(
                              icon: Icons.folder,
                              iconColor: folder.color,
                              firstLine: folder.name,
                              secondLine: localizations.folder_card_count(
                                count,
                              ),
                              itemIndex: index,
                              onPressed: () =>
                                  setState(() => currentFolderId = folder.id),
                              children: [
                                IconButton(
                                  tooltip: localizations.move_folder,
                                  onPressed: () => _moveFolder(folder),
                                  icon: const Icon(
                                    Icons.drive_file_move_outline,
                                  ),
                                ),
                                IconButton(
                                  tooltip: localizations.edit_folder,
                                  onPressed: () => _editFolder(folder),
                                  icon: const Icon(Icons.edit),
                                ),
                                IconButton(
                                  tooltip: localizations.export_folder,
                                  onPressed: () => _exportFolder(folder),
                                  icon: const Icon(Icons.download),
                                ),
                                IconButton(
                                  tooltip: localizations.delete_folder,
                                  onPressed: () => _deleteFolder(folder),
                                  icon: const Icon(Icons.delete_outline),
                                ),
                              ],
                            );
                          }
                          final card = cards[index - cardFolders.length];
                          return _cardItem(
                            appState,
                            localizations,
                            card,
                            index,
                          );
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: Card(
              child: Column(
                children: [
                  _sectionHeader(
                    title:
                        currentDictionaryFolder?.name ??
                        localizations.dictionaries,
                    compact: compact,
                    actions: [
                      if (currentDictionaryFolder != null)
                        IconButton(
                          tooltip: localizations.parent_folder,
                          onPressed: () => setState(
                            () => currentDictionaryFolderId =
                                currentDictionaryFolder.parentId,
                          ),
                          icon: const Icon(Icons.arrow_back),
                        ),
                      IconButton(
                        onPressed: _importDictionary,
                        icon: const Icon(Icons.upload),
                      ),
                      _createMenuButton(
                        appState,
                        elevated: false,
                        dictionary: true,
                      ),
                    ],
                  ),
                  _desktopControls(
                    appState: appState,
                    onImport: _importDictionary,
                    dictionary: true,
                    backButton: currentDictionaryFolder == null
                        ? null
                        : ElevatedButton(
                            onPressed: () => setState(
                              () => currentDictionaryFolderId =
                                  currentDictionaryFolder.parentId,
                            ),
                            style: customCardButtonStyle(appState),
                            child: const Icon(Icons.arrow_back),
                          ),
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      child: AlignedGridView.count(
                        clipBehavior: Clip.antiAlias,
                        physics: const NeverScrollableScrollPhysics(),
                        padding: const EdgeInsets.all(10),
                        crossAxisCount: MediaQuery.of(context).size.width >= 700
                            ? 2
                            : 1,
                        crossAxisSpacing: 10,
                        mainAxisSpacing: 10,
                        itemCount:
                            dictionaryFolders.length + dictionaries.length,
                        shrinkWrap: true,
                        itemBuilder: (context, index) {
                          if (index < dictionaryFolders.length) {
                            final folder = dictionaryFolders[index];
                            final subtree = _folderTreeIds(
                              folder.id,
                              allDictionaryFolders,
                              (item) => item.id,
                              (item) => item.parentId,
                            );
                            final count = allDictionaries
                                .where(
                                  (dictionary) =>
                                      subtree.contains(dictionary.folderId),
                                )
                                .length;
                            return ElementButton(
                              icon: Icons.folder,
                              iconColor: folder.color,
                              firstLine: folder.name,
                              secondLine: localizations.folder_dictionary_count(
                                count,
                              ),
                              itemIndex: index,
                              onPressed: () => setState(
                                () => currentDictionaryFolderId = folder.id,
                              ),
                              children: [
                                IconButton(
                                  tooltip: localizations.move_folder,
                                  onPressed: () =>
                                      _moveDictionaryFolder(folder),
                                  icon: const Icon(
                                    Icons.drive_file_move_outline,
                                  ),
                                ),
                                IconButton(
                                  tooltip: localizations.edit_folder,
                                  onPressed: () =>
                                      _editDictionaryFolder(folder),
                                  icon: const Icon(Icons.edit),
                                ),
                                IconButton(
                                  tooltip: localizations.export_folder,
                                  onPressed: () =>
                                      _exportDictionaryFolder(folder),
                                  icon: const Icon(Icons.download),
                                ),
                                IconButton(
                                  tooltip: localizations.delete_folder,
                                  onPressed: () =>
                                      _deleteDictionaryFolder(folder),
                                  icon: const Icon(Icons.delete_outline),
                                ),
                              ],
                            );
                          }
                          final dictionary =
                              dictionaries[index - dictionaryFolders.length];
                          return _dictionaryItem(
                            appState,
                            localizations,
                            dictionary,
                            index,
                          );
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _cardItem(
    ChameleonGUIState appState,
    AppLocalizations localizations,
    CardSave card,
    int index,
  ) {
    return ElementButton(
      icon: chameleonTagToFrequency(card.tag) == TagFrequency.hf
          ? Icons.credit_card
          : Icons.wifi,
      iconColor: card.color,
      firstLine: card.name.isEmpty ? ' ' : card.name,
      secondLine: chameleonCardToString(card, localizations),
      itemIndex: index,
      onPressed: () => showDialog(
        context: context,
        builder: (_) => CardViewMenu(tagSave: card, onMove: _moveCard),
      ),
      children: [
        IconButton(
          tooltip: localizations.move_card,
          onPressed: () => _moveCard(card),
          icon: const Icon(Icons.drive_file_move_outline),
        ),
        IconButton(
          onPressed: () => showDialog(
            context: context,
            builder: (_) => CardEditMenu(tagSave: card),
          ),
          icon: const Icon(Icons.edit),
        ),
        IconButton(
          onPressed: () async {
            await showDialog(
              context: context,
              builder: (dialogContext) => AlertDialog(
                title: Text(localizations.select_save_format),
                actions: [
                  if (isMifareClassic(card.tag))
                    ElevatedButton(
                      onPressed: () async {
                        await saveTag(card, dialogContext, true);
                        if (dialogContext.mounted) Navigator.pop(dialogContext);
                      },
                      child: Text(localizations.save_as('.bin')),
                    ),
                  ElevatedButton(
                    onPressed: () async {
                      await saveTag(card, dialogContext, false);
                      if (dialogContext.mounted) Navigator.pop(dialogContext);
                    },
                    child: Text(localizations.save_as('.json')),
                  ),
                ],
              ),
            );
          },
          icon: const Icon(Icons.download),
        ),
        IconButton(
          onPressed: () async {
            if (appState.sharedPreferencesProvider.getConfirmDelete()) {
              final confirm = await showDialog<bool>(
                context: context,
                builder: (_) =>
                    ConfirmDeletionMenu(thingBeingDeleted: card.name),
              );
              if (confirm != true) return;
            }
            final cards = appState.sharedPreferencesProvider
                .getCards()
                .where((item) => item.id != card.id)
                .toList();
            await appState.sharedPreferencesProvider.setCards(cards);
            appState.changesMade();
          },
          icon: const Icon(Icons.delete_outline),
        ),
      ],
    );
  }

  Widget _dictionaryItem(
    ChameleonGUIState appState,
    AppLocalizations localizations,
    Dictionary dictionary,
    int index,
  ) {
    return ElementButton(
      icon: Icons.key,
      iconColor: dictionary.color,
      firstLine: dictionary.name,
      secondLine: '${localizations.key_count}: ${dictionary.keys.length}',
      itemIndex: index,
      onPressed: () => showDialog(
        context: context,
        builder: (_) =>
            DictionaryViewMenu(dictionary: dictionary, onMove: _moveDictionary),
      ),
      children: [
        IconButton(
          tooltip: localizations.move_dictionary,
          onPressed: () => _moveDictionary(dictionary),
          icon: const Icon(Icons.drive_file_move_outline),
        ),
        IconButton(
          onPressed: () => showDialog(
            context: context,
            builder: (_) => DictionaryEditMenu(dictionary: dictionary),
          ),
          icon: const Icon(Icons.edit),
        ),
        IconButton(
          onPressed: () => FilePicker.saveFile(
            dialogTitle: '${localizations.output_file}:',
            fileName: '${dictionary.name}.dic',
            bytes: dictionary.toFile(),
          ),
          icon: const Icon(Icons.download),
        ),
        IconButton(
          onPressed: () async {
            if (appState.sharedPreferencesProvider.getConfirmDelete()) {
              final confirm = await showDialog<bool>(
                context: context,
                builder: (_) =>
                    ConfirmDeletionMenu(thingBeingDeleted: dictionary.name),
              );
              if (confirm != true) return;
            }
            final dictionaries = appState.sharedPreferencesProvider
                .getDictionaries()
                .where((item) => item.id != dictionary.id)
                .toList();
            await appState.sharedPreferencesProvider.setDictionaries(
              dictionaries,
            );
            appState.changesMade();
          },
          icon: const Icon(Icons.delete_outline),
        ),
      ],
    );
  }

  Future<String?> dictMergeDialog(BuildContext context, Dictionary mergeDict) {
    final dicts =
        context
            .read<ChameleonGUIState>()
            .sharedPreferencesProvider
            .getDictionaries()
          ..sort((a, b) => a.name.compareTo(b.name));
    return showSearch<String>(
      context: context,
      delegate: DictMergeDelegate(dicts, mergeDict),
    );
  }
}

class DictMergeDelegate extends SearchDelegate<String> {
  final List<Dictionary> dicts;
  final Dictionary mergeDict;
  late final List<bool> selectedDicts = List.filled(dicts.length, false);

  DictMergeDelegate(this.dicts, this.mergeDict);

  @override
  List<Widget> buildActions(BuildContext context) {
    final appState = context.read<ChameleonGUIState>();
    return [
      IconButton(icon: const Icon(Icons.clear), onPressed: () => query = ''),
      const SizedBox(width: 10),
      IconButton(
        icon: const Icon(Icons.merge),
        onPressed: () async {
          for (var index = 0; index < selectedDicts.length; index++) {
            if (selectedDicts[index]) {
              mergeDict.keys = [...mergeDict.keys, ...dicts[index].keys];
            }
          }
          mergeDict.keys = <int, Uint8List>{
            for (final key in mergeDict.keys) Object.hashAll(key): key,
          }.values.toList();
          final output = dicts.toList();
          final index = output.indexWhere((item) => item.id == mergeDict.id);
          if (index >= 0) output[index] = mergeDict;
          await appState.sharedPreferencesProvider.setDictionaries(output);
          appState.changesMade();
          if (context.mounted) Navigator.pop(context);
        },
      ),
    ];
  }

  @override
  Widget buildLeading(BuildContext context) => IconButton(
    icon: const Icon(Icons.arrow_back),
    onPressed: () => close(context, ''),
  );

  Widget _results(BuildContext context, {required bool editable}) {
    final localizations = AppLocalizations.of(context)!;
    final results = dicts
        .where((dict) => dict.name.toLowerCase().contains(query.toLowerCase()))
        .toList();
    return ListView.builder(
      itemCount: results.length,
      itemBuilder: (context, resultIndex) {
        final dictionary = results[resultIndex];
        if (dictionary.id == mergeDict.id) return const SizedBox.shrink();
        final sourceIndex = dicts.indexWhere(
          (item) => item.id == dictionary.id,
        );
        return CheckboxListTile(
          value: selectedDicts[sourceIndex],
          title: Text(dictionary.name),
          secondary: Icon(Icons.key, color: dictionary.color),
          subtitle: Text(
            '${dictionary.keys.length} ${localizations.total_keys.toLowerCase()}',
          ),
          onChanged: editable
              ? (value) => selectedDicts[sourceIndex] = value ?? false
              : null,
        );
      },
    );
  }

  @override
  Widget buildResults(BuildContext context) =>
      _results(context, editable: false);

  @override
  Widget buildSuggestions(BuildContext context) =>
      _results(context, editable: true);
}

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:chameleonultragui/bridge/chameleon.dart';
import 'package:chameleonultragui/gui/component/developer_list.dart';
import 'package:chameleonultragui/gui/component/error_page.dart';
import 'package:chameleonultragui/gui/component/module_version_navigation.dart';
import 'package:chameleonultragui/gui/component/toggle_buttons.dart';
import 'package:chameleonultragui/gui/menu/dialogs/qr/settings.dart';
import 'package:chameleonultragui/helpers/general.dart';
import 'package:chameleonultragui/helpers/github.dart';
import 'package:chameleonultragui/helpers/definitions.dart';
import 'package:chameleonultragui/helpers/module_versions.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:chameleonultragui/helpers/open_collective.dart';
import 'package:chameleonultragui/main.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:file_picker/file_picker.dart';
import 'package:chameleonultragui/gui/component/qrcode_viewer.dart';
import 'package:crypto/crypto.dart';
import 'package:chameleonultragui/gui/menu/dialogs/qr/import.dart';
import 'package:chameleonultragui/gui/menu/pages/changelog_view.dart';
import 'package:chameleonultragui/gui/page/data_sync.dart';
import 'package:chameleonultragui/gui/page/mifare_classic_nonce_history.dart';
import 'package:flutter/services.dart' show rootBundle;

// Localizations
import 'package:chameleonultragui/generated/i18n/app_localizations.dart';

Future<String> loadLicense(String license) async {
  return await rootBundle.loadString('assets/licenses/$license.md');
}

class SettingsMainPage extends StatefulWidget {
  const SettingsMainPage({super.key});

  @override
  SettingsMainPageState createState() => SettingsMainPageState();
}

class SettingsMainPageState extends State<SettingsMainPage> {
  ChameleonCommunicator? _ledCommunicator;
  AnimationSetting? _deviceLedMode;
  bool _deviceLedBusy = false;
  String? _deviceLedError;
  bool? _pendingDeviceLedsEnabled;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final communicator = context.watch<ChameleonGUIState>().communicator;
    if (identical(communicator, _ledCommunicator)) return;
    _ledCommunicator = communicator;
    _deviceLedMode = null;
    _deviceLedBusy = false;
    _deviceLedError = null;
    _pendingDeviceLedsEnabled = null;
    if (communicator != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_refreshDeviceLeds());
      });
    }
  }

  Future<void> _refreshDeviceLeds() async {
    final communicator = _ledCommunicator;
    if (communicator == null || _deviceLedBusy) return;
    setState(() {
      _deviceLedBusy = true;
      _deviceLedError = null;
    });
    try {
      final mode = await communicator.getAnimationMode();
      if (!mounted || !identical(communicator, _ledCommunicator)) return;
      if (mode != AnimationSetting.none) {
        await context
            .read<ChameleonGUIState>()
            .sharedPreferencesProvider
            .setDeviceLedAnimationMode(mode);
      }
      if (!mounted || !identical(communicator, _ledCommunicator)) return;
      setState(() => _deviceLedMode = mode);
    } catch (error) {
      if (mounted && identical(communicator, _ledCommunicator)) {
        setState(() => _deviceLedError = error.toString());
      }
    } finally {
      if (mounted && identical(communicator, _ledCommunicator)) {
        setState(() => _deviceLedBusy = false);
      }
    }
  }

  Future<void> _setDeviceLedsEnabled(bool enabled) async {
    final communicator = _ledCommunicator;
    if (communicator == null || _deviceLedBusy || _deviceLedMode == null) {
      return;
    }
    final appState = context.read<ChameleonGUIState>();
    setState(() {
      _deviceLedBusy = true;
      _deviceLedError = null;
      _pendingDeviceLedsEnabled = enabled;
    });
    try {
      if (!enabled) {
        final currentMode = await communicator.getAnimationMode();
        if (!mounted || !identical(communicator, _ledCommunicator)) return;
        if (currentMode != AnimationSetting.none) {
          await appState.sharedPreferencesProvider.setDeviceLedAnimationMode(
            currentMode,
          );
        }
      }
      final mode = enabled
          ? appState.sharedPreferencesProvider.getDeviceLedAnimationMode()
          : AnimationSetting.none;
      await communicator.setAnimationMode(mode);
      await communicator.saveSettings();
      if (!mounted || !identical(communicator, _ledCommunicator)) return;
      setState(() {
        _deviceLedMode = mode;
        _pendingDeviceLedsEnabled = null;
      });
      appState.changesMade();
    } catch (error) {
      AnimationSetting? actualMode;
      try {
        actualMode = await communicator.getAnimationMode();
      } catch (_) {
        // Keep the previous UI state if the device can no longer be queried.
      }
      if (mounted && identical(communicator, _ledCommunicator)) {
        setState(() {
          if (actualMode != null) _deviceLedMode = actualMode;
          _deviceLedError = error.toString();
        });
      }
    } finally {
      if (mounted && identical(communicator, _ledCommunicator)) {
        setState(() => _deviceLedBusy = false);
      }
    }
  }

  String _deviceLedSubtitle(AppLocalizations localizations) {
    if (_ledCommunicator == null) {
      return localizations.device_leds_disconnected_description;
    }
    if (_deviceLedError case final error?) {
      return localizations.device_leds_update_failed(error);
    }
    if (_deviceLedMode == null) return localizations.device_leds_loading;
    return _deviceLedMode == AnimationSetting.none
        ? localizations.device_leds_disabled_description
        : localizations.device_leds_enabled_description;
  }

  Future<(String, List<Map<String, String>>, PackageInfo)>
  getFutureData() async {
    return (
      await fetchOCnames(),
      await fetchContributors(),
      await PackageInfo.fromPlatform(),
    );
  }

  Future<String> fetchOCnames() async {
    final List<String> names = await fetchOpenCollectiveContributors();

    if (names.isEmpty && mounted) {
      return AppLocalizations.of(context)!.failed_to_fetch_oc_contributors;
    }

    String finalNames = "";
    for (String name in names) {
      finalNames += "$name, ";
    }
    return finalNames.substring(0, finalNames.length - 2);
  }

  Future<List<Map<String, String>>> fetchContributors() async {
    return await fetchGitHubContributors();
  }

  @override
  Widget build(BuildContext context) {
    var appState = context.watch<ChameleonGUIState>();
    var localizations = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(title: Text(localizations.settings)),
      body: SingleChildScrollView(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(height: 10),
              Text(
                localizations.sidebar_expansion,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 5),
              ToggleButtonsWrapper(
                items: [
                  localizations.expand,
                  localizations.auto,
                  localizations.retract,
                ],
                selectedValue: appState.sharedPreferencesProvider
                    .getSideBarExpandedIndex(),
                onChange: (int index) async {
                  if (index == 0) {
                    appState.sharedPreferencesProvider.setSideBarExpanded(true);
                    await appState.sharedPreferencesProvider
                        .setSideBarAutoExpansion(false);
                  } else if (index == 2) {
                    appState.sharedPreferencesProvider.setSideBarExpanded(
                      false,
                    );
                    await appState.sharedPreferencesProvider
                        .setSideBarAutoExpansion(false);
                  } else {
                    await appState.sharedPreferencesProvider
                        .setSideBarAutoExpansion(true);
                  }
                  await appState.sharedPreferencesProvider
                      .setSideBarExpandedIndex(index);
                  appState.changesMade();

                  WidgetsBinding.instance.addPostFrameCallback(
                    (_) => updateNavigationRailWidth(context),
                  );
                },
              ),
              const SizedBox(height: 10),
              Text(
                localizations.theme,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 5),
              ToggleButtonsWrapper(
                items: [
                  localizations.system,
                  localizations.light,
                  localizations.dark,
                ],
                selectedValue: appState.sharedPreferencesProvider
                    .getTheme()
                    .index,
                onChange: (int index) async {
                  await appState.sharedPreferencesProvider.setTheme(
                    ThemeMode.values[index],
                  );
                  appState.changesMade();
                },
              ),
              const SizedBox(height: 10),
              Text(
                localizations.color_scheme,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 5),
              DropdownButton(
                value: appState.sharedPreferencesProvider.getThemeColorIndex(),
                icon: const Icon(Icons.arrow_downward),
                elevation: 16,
                onChanged: (value) async {
                  await appState.sharedPreferencesProvider.setThemeColor(
                    value ?? 0,
                  );
                  appState.changesMade();
                },
                items: [
                  DropdownMenuItem(value: 0, child: Text(localizations.def)),
                  DropdownMenuItem(value: 1, child: Text(localizations.purple)),
                  DropdownMenuItem(value: 2, child: Text(localizations.blue)),
                  DropdownMenuItem(value: 3, child: Text(localizations.green)),
                  DropdownMenuItem(value: 4, child: Text(localizations.indigo)),
                  DropdownMenuItem(value: 5, child: Text(localizations.lime)),
                  DropdownMenuItem(value: 6, child: Text(localizations.red)),
                  DropdownMenuItem(value: 7, child: Text(localizations.yellow)),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                localizations.language,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 5),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: DropdownButton(
                  value: appState.sharedPreferencesProvider.getLocaleString(),
                  onChanged: (value) async {
                    await appState.sharedPreferencesProvider.setLocale(
                      Locale(value ?? 'en'),
                    );
                    appState.changesMade();
                  },
                  items: AppLocalizations.supportedLocales.map((locale) {
                    final localeLocalizations = lookupAppLocalizations(locale);
                    return DropdownMenuItem(
                      value: locale.toLanguageTag(),
                      child: Text(localeLocalizations.language_name),
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    localizations.auto_scan_devices,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(width: 5),
                  Switch(
                    value: appState.sharedPreferencesProvider
                        .getAutoScanEnabled(),
                    onChanged: (value) async {
                      await appState.sharedPreferencesProvider
                          .setAutoScanEnabled(value);
                      appState.changesMade();
                    },
                  ),
                ],
              ),
              const SizedBox(height: 10),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: Card(
                  child: Column(
                    children: [
                      SwitchListTile.adaptive(
                        key: const Key('device-led-toggle'),
                        secondary: const Icon(Icons.lightbulb_outline_rounded),
                        title: Text(localizations.device_leds),
                        subtitle: Text(_deviceLedSubtitle(localizations)),
                        value:
                            _deviceLedMode != null &&
                            _deviceLedMode != AnimationSetting.none,
                        onChanged:
                            _ledCommunicator == null ||
                                _deviceLedBusy ||
                                _deviceLedMode == null
                            ? null
                            : (enabled) =>
                                  unawaited(_setDeviceLedsEnabled(enabled)),
                      ),
                      if (_deviceLedBusy)
                        const LinearProgressIndicator(minHeight: 2),
                      if (_deviceLedError != null)
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton.icon(
                            key: const Key('device-led-retry'),
                            onPressed: _deviceLedBusy
                                ? null
                                : () {
                                    final enabled = _pendingDeviceLedsEnabled;
                                    unawaited(
                                      enabled == null
                                          ? _refreshDeviceLeds()
                                          : _setDeviceLedsEnabled(enabled),
                                    );
                                  },
                            icon: const Icon(Icons.refresh_rounded),
                            label: Text(localizations.device_leds_retry),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    localizations.auto_connect_first_device,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(width: 5),
                  Switch(
                    value: appState.sharedPreferencesProvider
                        .getAutoConnectFirstFoundDevice(),
                    onChanged: (value) async {
                      await appState.sharedPreferencesProvider
                          .setAutoConnectFirstFoundDevice(value);
                      appState.changesMade();
                    },
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    localizations.device_found_notification,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(width: 5),
                  Switch(
                    value: appState.sharedPreferencesProvider
                        .getDeviceFoundBanner(),
                    onChanged: (value) async {
                      await appState.sharedPreferencesProvider
                          .setDeviceFoundBanner(value);
                      appState.changesMade();
                    },
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    localizations.confirm_deletions,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(width: 5),
                  Switch(
                    value: appState.sharedPreferencesProvider
                        .getConfirmDelete(),
                    onChanged: (value) async {
                      await appState.sharedPreferencesProvider.setConfirmDelete(
                        value,
                      );
                      appState.changesMade();
                    },
                  ),
                ],
              ),
              const SizedBox(height: 10),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: Card(
                  child: Column(
                    children: [
                      SwitchListTile.adaptive(
                        title: const Text(
                          'Remember MIFARE Classic nonces and failed keys',
                        ),
                        subtitle: const Text(
                          'Skip identical Nested and Static Nested captures, plus keys confirmed invalid for every sector of the same UID.',
                        ),
                        value: appState.sharedPreferencesProvider
                            .getMifareClassicNonceHistoryEnabled(),
                        onChanged: (enabled) async {
                          await appState.sharedPreferencesProvider
                              .setMifareClassicNonceHistoryEnabled(enabled);
                          appState.changesMade();
                          if (mounted) setState(() {});
                        },
                      ),
                      const Divider(height: 1),
                      ListTile(
                        leading: const Icon(Icons.manage_search),
                        title: const Text('Manage stored recovery history'),
                        subtitle: Builder(
                          builder: (context) {
                            final entries = appState.sharedPreferencesProvider
                                .getMifareClassicNonceHistorySummaries();
                            final bytes = entries.fold<int>(
                              0,
                              (sum, entry) => sum + entry.byteSize,
                            );
                            final failedKeys = entries.fold<int>(
                              0,
                              (sum, entry) => sum + entry.failedKeyCount,
                            );
                            return Text(
                              '${entries.length} cards | $failedKeys failed keys | ${formatMifareClassicNonceHistoryBytes(bytes)}',
                            );
                          },
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => Navigator.push(
                          context,
                          ModulePageRoute<void>(
                            moduleId: ModuleId.mifareClassicNonceHistory,
                            builder: (_) =>
                                const MifareClassicNonceHistoryPage(),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: Card(
                  child: ListTile(
                    leading: const Icon(Icons.sync_alt),
                    title: Text(localizations.data_sync_title),
                    subtitle: Text(localizations.data_sync_intro),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.push(
                      context,
                      ModulePageRoute<void>(
                        moduleId: ModuleId.dataSync,
                        builder: (_) => const DataSyncPage(),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: TextButton(
                  onPressed: () => showDialog<String>(
                    context: context,
                    builder: (BuildContext context) => AlertDialog(
                      title: Text(
                        AppLocalizations.of(context)!.choose_export_method,
                      ),
                      content: Text(
                        AppLocalizations.of(
                          context,
                        )!.choose_export_method_description,
                      ),
                      actions: <Widget>[
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: Text(localizations.cancel),
                        ),
                        TextButton(
                          onPressed: () async {
                            String string = appState.sharedPreferencesProvider
                                .dumpSettingsToJson();

                            Map<String, int> settings =
                                await showDialog(
                                  context: context,
                                  builder: (BuildContext context) {
                                    return const QRCodeSettings();
                                  },
                                ) ??
                                {};

                            if (settings.isEmpty) {
                              return;
                            }

                            List<String> qrChunks = splitStringIntoQrChunks(
                              string,
                              settings["splitSize"]!,
                            ); //2048
                            final digest = sha256
                                .convert(const Utf8Encoder().convert(string))
                                .toString();
                            qrChunks = [
                              for (
                                var index = 0;
                                index < qrChunks.length;
                                index++
                              )
                                jsonEncode({
                                  "Info": "Chameleon Ultra GUI Settings Chunk",
                                  "sha256": digest,
                                  "index": index,
                                  "chunks": qrChunks.length,
                                  "data": qrChunks[index],
                                }),
                            ];

                            // Generate Header Info
                            Map<String, dynamic> headerData = {
                              "Info": "Chameleon Ultra GUI Settings",
                              "chunks": qrChunks.length,
                              "sha256": digest,
                            };
                            qrChunks.insert(0, jsonEncode(headerData));

                            if (context.mounted) {
                              await showDialog(
                                context: context,
                                builder: (BuildContext context) => QrCodeViewer(
                                  qrChunks: qrChunks,
                                  errorCorrection: settings["errorCorrection"]!,
                                ),
                              );
                            }

                            appState.changesMade();
                            if (context.mounted) {
                              Navigator.pop(context);
                            }
                          },
                          child: Text(localizations.qr_code),
                        ),
                        TextButton(
                          onPressed: () async {
                            await FilePicker.saveFile(
                              dialogTitle: '${localizations.output_file}:',
                              fileName: 'ChameleonUltraGUISettings.json',
                              bytes: const Utf8Encoder().convert(
                                appState.sharedPreferencesProvider
                                    .dumpSettingsToJson(),
                              ),
                            );
                          },
                          child: Text(AppLocalizations.of(context)!.json_file),
                        ),
                      ],
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(AppLocalizations.of(context)!.export_settings),
                      const Icon(Icons.upload),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: TextButton(
                  onPressed: () => showDialog<String>(
                    context: context,
                    builder: (BuildContext context) => AlertDialog(
                      title: Text(
                        AppLocalizations.of(context)!.import_settings,
                      ),
                      content: Text(
                        AppLocalizations.of(
                          context,
                        )!.import_settings_description,
                      ),
                      actions: <Widget>[
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: Text(localizations.cancel),
                        ),
                        TextButton(
                          onPressed: () async {
                            if (!(Platform.isAndroid || Platform.isIOS)) {
                              await showDialog(
                                context: context,
                                builder: (BuildContext context) => AlertDialog(
                                  title: Text(
                                    AppLocalizations.of(context)!.error,
                                  ),
                                  content: Text(
                                    AppLocalizations.of(
                                      context,
                                    )!.qr_code_import_not_supported_description,
                                  ),
                                  actions: <Widget>[
                                    TextButton(
                                      onPressed: () => Navigator.pop(context),
                                      child: Text(localizations.ok),
                                    ),
                                  ],
                                ),
                              );
                              return;
                            }

                            String? jsonData = await showDialog(
                              context: context,
                              builder: (BuildContext context) {
                                return const QrCodeImport();
                              },
                            );

                            if (jsonData == null) {
                              return;
                            }
                            await appState.sharedPreferencesProvider
                                .restoreSettingsFromJson(jsonData);

                            appState.changesMade();
                            if (context.mounted) {
                              Navigator.pop(context);
                            }
                          },
                          child: Text(localizations.qr_code),
                        ),
                        TextButton(
                          onPressed: () async {
                            PlatformFile? result = await FilePicker.pickFile();
                            if (result != null) {
                              File file = File(result.path!);
                              if (await file.length() > 16 * 1024) {
                                throw const FormatException(
                                  'Settings backup exceeds the size limit',
                                );
                              }
                              var contents = await file.readAsBytes();
                              var string = const Utf8Decoder().convert(
                                contents,
                              );
                              await appState.sharedPreferencesProvider
                                  .restoreSettingsFromJson(string);
                              appState.changesMade();
                              if (context.mounted) {
                                Navigator.pop(context);
                              }
                            }
                          },
                          child: Text(AppLocalizations.of(context)!.json_file),
                        ),
                      ],
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(AppLocalizations.of(context)!.import_settings),
                      const Icon(Icons.download),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),
              TextButton(
                onPressed: () => showDialog<String>(
                  context: context,
                  builder: (BuildContext context) => AlertDialog(
                    title: Text(localizations.about),
                    content: Center(
                      child: FutureBuilder(
                        future: getFutureData(),
                        builder: (BuildContext context, AsyncSnapshot snapshot) {
                          if (snapshot.connectionState ==
                              ConnectionState.waiting) {
                            return const Center(
                              child: CircularProgressIndicator(),
                            );
                          } else if (snapshot.hasError) {
                            appState.connector!.performDisconnect();
                            return ErrorPage(
                              errorMessage: snapshot.error.toString(),
                            );
                          } else {
                            final (names, contributors, packageInfo) =
                                snapshot.data;
                            return SingleChildScrollView(
                              child: Column(
                                children: [
                                  const Text(
                                    'Chameleon Ultra GUI',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  Text(localizations.about_text),
                                  const SizedBox(height: 10),
                                  Text('${localizations.version}:'),
                                  Text(
                                    '${packageInfo.version} (Build ${packageInfo.buildNumber})',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  Text('${localizations.developed_by}:'),
                                  const SizedBox(height: 10),
                                  DeveloperList(avatars: developers),
                                  const SizedBox(height: 10),
                                  Text('${localizations.license}:'),
                                  const Text(
                                    'GNU General Public License v3.0',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  GestureDetector(
                                    onTap: () async {
                                      await launchUrl(
                                        Uri.parse(
                                          'https://github.com/GameTec-live/ChameleonUltraGUI',
                                        ),
                                      );
                                    },
                                    child: const Text(
                                      'https://github.com/GameTec-live/ChameleonUltraGUI',
                                    ),
                                  ),
                                  const SizedBox(height: 30),
                                  GestureDetector(
                                    onTap: () async {
                                      await launchUrl(
                                        Uri.parse(
                                          'https://opencollective.com/chameleon-ultra-gui',
                                        ),
                                      );
                                    },
                                    child: Text(
                                      localizations.thanks_for_support,
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  Text(
                                    names,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  Text('${localizations.code_contributors}:'),
                                  const SizedBox(height: 10),
                                  DeveloperList(avatars: contributors),
                                  const SizedBox(height: 10),
                                  Text(localizations.trademarks_mifare),
                                  const SizedBox(height: 10),
                                  Text(localizations.trademarks_em),
                                  const SizedBox(height: 10),
                                  Text(localizations.trademarks_hid),
                                ],
                              ),
                            );
                          }
                        },
                      ),
                    ),
                    actions: <Widget>[
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: Text(localizations.ok),
                      ),
                    ],
                  ),
                ),
                child: Text(localizations.about),
              ),
              const SizedBox(height: 10),
              TextButton(
                onPressed: () async {
                  Map<String, String> licenses = {
                    'BSD-3-Clause': await loadLicense('BSD-3-Clause'),
                    'GPL3': await loadLicense('GPL3'),
                    'LGPL3': await loadLicense('LGPL3'),
                    'MIT': await loadLicense('MIT'),
                  };

                  // font.dart
                  LicenseRegistry.addLicense(
                    () => Stream<LicenseEntry>.value(
                      LicenseEntryWithLineBreaks(<String>[
                        'chinese_font_library',
                      ], licenses['BSD-3-Clause']!),
                    ),
                  );

                  // ported hardnested to Windows + MSVC, separation from proxmark3 code
                  LicenseRegistry.addLicense(
                    () => Stream<LicenseEntry>.value(
                      LicenseEntryWithLineBreaks(<String>[
                        'FlipperNestedRecovery',
                      ], licenses['LGPL3']!),
                    ),
                  );

                  LicenseRegistry.addLicense(
                    () => Stream<LicenseEntry>.value(
                      LicenseEntryWithLineBreaks(<String>[
                        'proxmark3',
                      ], licenses['GPL3']!),
                    ),
                  );

                  // hardnested tables uncompressor
                  LicenseRegistry.addLicense(
                    () => Stream<LicenseEntry>.value(
                      LicenseEntryWithLineBreaks(<String>[
                        'minlzma',
                      ], licenses['MIT']!),
                    ),
                  );

                  if (context.mounted) {
                    showLicensePage(context: context);
                  }
                },
                child: Text(localizations.licenses),
              ),
              const SizedBox(height: 10),
              TextButton(
                onPressed: () => showDialog<String>(
                  context: context,
                  builder: (BuildContext context) => const ChangelogView(),
                ),
                child: Text(localizations.changelog),
              ),
              const SizedBox(height: 10),
              TextButton(
                onPressed: () async {
                  await launchUrl(
                    Uri.parse('https://crowdin.com/project/chameleonultragui'),
                  );
                },
                child: Text(localizations.help_translate),
              ),
              const SizedBox(height: 10),
              TextButton(
                onPressed: () => showDialog<String>(
                  context: context,
                  builder: (BuildContext context) => AlertDialog(
                    title: Text(localizations.emulate_device),
                    content: Text(
                      localizations.emulate_device_confirmation(
                        appState.sharedPreferencesProvider.isEmulatedChameleon()
                            ? localizations.deactivate.toLowerCase()
                            : localizations.activate.toLowerCase(),
                      ),
                    ),
                    actions: <Widget>[
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: Text(localizations.cancel),
                      ),
                      TextButton(
                        onPressed: () async {
                          final wasEmulated = appState.sharedPreferencesProvider
                              .isEmulatedChameleon();
                          appState.sharedPreferencesProvider
                              .setEmulatedChameleon(!wasEmulated);
                          try {
                            await appState.resetConnector();
                          } catch (error) {
                            appState.sharedPreferencesProvider
                                .setEmulatedChameleon(wasEmulated);
                            appState.changesMade();
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text(error.toString())),
                              );
                            }
                            return;
                          }
                          if (!context.mounted) return;
                          Navigator.pop(context);
                        },
                        child: Text(localizations.ok),
                      ),
                    ],
                  ),
                ),
                child: Text(
                  "${appState.sharedPreferencesProvider.isEmulatedChameleon() ? localizations.deactivate : localizations.activate} ${localizations.emulate_device.toLowerCase()}",
                ),
              ),
              const SizedBox(height: 10),
              TextButton(
                onPressed: () => showDialog<String>(
                  context: context,
                  builder: (BuildContext context) => AlertDialog(
                    title: Text(localizations.debug_mode),
                    content: Text(
                      localizations.debug_mode_confirmation(
                        appState.sharedPreferencesProvider.isDebugMode()
                            ? localizations.deactivate.toLowerCase()
                            : localizations.activate.toLowerCase(),
                      ),
                    ),
                    actions: <Widget>[
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: Text(localizations.cancel),
                      ),
                      TextButton(
                        onPressed: () {
                          appState.sharedPreferencesProvider.setDebugMode(
                            !appState.sharedPreferencesProvider.isDebugMode(),
                          );
                          appState.changesMade();
                          Navigator.pop(context);
                        },
                        child: Text(localizations.ok),
                      ),
                    ],
                  ),
                ),
                child: Text(
                  "${appState.sharedPreferencesProvider.isDebugMode() ? localizations.deactivate : localizations.activate} ${localizations.debug_mode.toLowerCase()}",
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

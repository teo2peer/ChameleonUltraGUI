import 'dart:async';
import 'dart:io';
import 'package:chameleonultragui/bridge/chameleon.dart';
import 'package:chameleonultragui/connector/serial_abstract.dart';
import 'package:chameleonultragui/connector/serial_android.dart';
import 'package:chameleonultragui/connector/serial_ble.dart';
import 'package:chameleonultragui/connector/serial_emulator.dart';
import 'package:chameleonultragui/connector/serial_macos.dart';
import 'package:chameleonultragui/gui/component/device_found_banner.dart';
import 'package:chameleonultragui/gui/page/tools.dart';
import 'package:chameleonultragui/helpers/font.dart';
import 'package:chameleonultragui/helpers/general.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'connector/serial_native.dart';

// Page imports
import 'package:chameleonultragui/gui/page/home.dart';
import 'package:chameleonultragui/gui/page/saved_cards.dart';
import 'package:chameleonultragui/gui/page/settings.dart';
import 'package:chameleonultragui/gui/page/connect.dart';
import 'package:chameleonultragui/gui/page/debug.dart';
import 'package:chameleonultragui/gui/page/slot_manager.dart';
import 'package:chameleonultragui/gui/page/flashing.dart';
import 'package:chameleonultragui/gui/page/read_card.dart';
import 'package:chameleonultragui/gui/page/write_card.dart';
import 'package:chameleonultragui/gui/page/reader_keys.dart';
import 'package:chameleonultragui/gui/page/ethical_hacking.dart';
import 'package:chameleonultragui/gui/page/pending_connection.dart';

// Localizations
import 'package:chameleonultragui/generated/i18n/app_localizations.dart';

// Shared Preferences Provider
import 'package:chameleonultragui/sharedprefsprovider.dart';

// Logger
import 'package:logger/logger.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final sharedPreferencesProvider = SharedPreferencesProvider();
  await sharedPreferencesProvider.load();
  runApp(ChameleonGUI(sharedPreferencesProvider));
}

class ChameleonGUI extends StatelessWidget {
  // Root Widget
  final SharedPreferencesProvider _sharedPreferencesProvider;
  const ChameleonGUI(this._sharedPreferencesProvider, {super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: _sharedPreferencesProvider),
        ChangeNotifierProvider(
          create: (context) => ChameleonGUIState(_sharedPreferencesProvider),
        ),
      ],
      child: MainPage(sharedPreferencesProvider: _sharedPreferencesProvider),
    );
  }
}

class ChameleonGUIState extends ChangeNotifier {
  final SharedPreferencesProvider sharedPreferencesProvider;
  ChameleonGUIState(this.sharedPreferencesProvider);

  SharedPreferencesProvider? _sharedPreferencesProvider;
  Logger? log; // Logger

  // Android uses AndroidSerial, iOS can only use BLESerial
  // The rest (desktops?) can use NativeSerial
  AbstractSerial? connector;
  ChameleonCommunicator? communicator;

  bool devMode = false;
  double? progress; // DFU

  // Flashing easter egg
  bool easterEgg = false;
  dynamic _suppressedAutoReconnectPort;

  GlobalKey navigationRailKey = GlobalKey();
  Size? navigationRailSize;

  void changesMade() {
    notifyListeners();
  }

  void onConnectorStateChanged() {
    if (connector == null || !connector!.connected) {
      communicator?.dispose('Connector disconnected');
      communicator = null;
      progress = null;
    }
    notifyListeners();
  }

  bool isAutoReconnectSuppressed(dynamic devicePort) {
    return _suppressedAutoReconnectPort == devicePort;
  }

  void clearAutoReconnectSuppression([dynamic devicePort]) {
    if (devicePort == null || _suppressedAutoReconnectPort == devicePort) {
      _suppressedAutoReconnectPort = null;
    }
  }

  void syncAutoReconnectSuppression(Iterable<dynamic> visiblePorts) {
    if (_suppressedAutoReconnectPort == null) {
      return;
    }

    for (final port in visiblePorts) {
      if (port == _suppressedAutoReconnectPort) {
        return;
      }
    }

    _suppressedAutoReconnectPort = null;
  }

  Future<void> disconnect({bool manual = false}) async {
    final suppressedPort = manual ? connector?.activeDevicePort : null;
    communicator?.dispose('Disconnected by the application');
    communicator = null;
    await connector?.performDisconnect();
    if (manual && suppressedPort != null) {
      _suppressedAutoReconnectPort = suppressedPort;
    }
    progress = null;
    notifyListeners();
  }

  Future<void> attachConnectedCommunicator() async {
    final activeConnector = connector;
    if (activeConnector == null || !activeConnector.connected) {
      throw StateError('Cannot attach communicator without a connection');
    }
    final next = ChameleonCommunicator(log!, port: activeConnector);
    try {
      await next.initializeCapabilities();
    } catch (error) {
      next.dispose(error);
      communicator?.dispose(error);
      communicator = null;
      activeConnector.pendingConnection = false;
      await activeConnector.performDisconnect();
      progress = null;
      notifyListeners();
      rethrow;
    }
    communicator?.dispose('Replaced by a new connection');
    communicator = next;
  }

  void setProgressBar(dynamic value) {
    progress = value;
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Device discovery (single owner)
  //
  // Scanning used to live inside ConnectPage, so it only ran while that page
  // was mounted (tab 0 while disconnected). It now lives here so the scan runs
  // on every tab while disconnected and both ConnectPage and the app-wide
  // "device found" banner read one shared list — no two scanners racing on the
  // BLE `inSearch` guard. Lifecycle is driven from _MainPageState.build().
  List<Chameleon> availableDevices = [];
  Object? scanError;
  bool hasCompletedDeviceScan = false;
  Duration scanInterval = const Duration(seconds: 3);
  Timer? _scanTimer;
  bool _scanInProgress = false;
  bool _connecting = false;
  dynamic _lastAutoConnectAttemptPort;
  String _lastDevicesSignature = '';
  bool _lastScanHadError = false;

  bool _shouldScan() {
    final c = connector;
    return c != null &&
        !_connecting &&
        !c.connected &&
        !c.pendingConnection &&
        !c.isDFU;
  }

  /// Start the periodic scan if it isn't already running and we're in a state
  /// where scanning makes sense. Idempotent — safe to call from build().
  void ensureDeviceScanRunning() {
    if (_scanTimer != null || _scanInProgress) {
      return;
    }
    if (!_shouldScan() || !sharedPreferencesProvider.getAutoScanEnabled()) {
      return;
    }
    _scanTick();
  }

  void stopDeviceScan() {
    _scanTimer?.cancel();
    _scanTimer = null;
  }

  Future<void> refreshDeviceScan() => _scanTick();

  void _scheduleNextScan() {
    _scanTimer?.cancel();
    _scanTimer = null;
    if (!_shouldScan() || !sharedPreferencesProvider.getAutoScanEnabled()) {
      return;
    }
    _scanTimer = Timer(scanInterval, _scanTick);
  }

  List<Chameleon> _normalizeDevices(List<Chameleon> devices) {
    final output = <Chameleon>[];
    final seen = <String>{};
    for (final device in devices) {
      final key = '${device.port}|${device.type.name}|${device.dfu}';
      if (seen.add(key)) {
        output.add(device);
      }
    }
    return output;
  }

  String _signatureOf(List<Chameleon> devices) {
    final keys = devices
        .map((d) => '${d.port}|${d.type.name}|${d.dfu}')
        .toList()
      ..sort();
    return keys.join(',');
  }

  dynamic _firstConnectablePort(List<Chameleon> devices) {
    for (final device in devices) {
      if (!device.dfu) {
        return device.port;
      }
    }
    return null;
  }

  Future<void> _scanTick() async {
    if (_scanInProgress || !_shouldScan()) {
      return;
    }
    _scanTimer?.cancel();
    _scanTimer = null;
    _scanInProgress = true;
    try {
      final devices =
          _normalizeDevices(await connector!.availableChameleons(false));
      syncAutoReconnectSuppression(devices.map((device) => device.port));

      final firstConnectablePort = _firstConnectablePort(devices);
      if (firstConnectablePort != _lastAutoConnectAttemptPort) {
        _lastAutoConnectAttemptPort = null;
      }

      final signature = _signatureOf(devices);
      final changed = signature != _lastDevicesSignature ||
          _lastScanHadError ||
          !hasCompletedDeviceScan;
      _lastDevicesSignature = signature;
      _lastScanHadError = false;
      availableDevices = devices;
      scanError = null;
      hasCompletedDeviceScan = true;
      if (changed) {
        notifyListeners();
      }

      await _maybeAutoConnect(devices);
    } catch (error) {
      await connector?.performDisconnect();
      final wasError = _lastScanHadError;
      _lastScanHadError = true;
      _lastDevicesSignature = '';
      scanError = error;
      availableDevices = [];
      hasCompletedDeviceScan = true;
      if (!wasError) {
        notifyListeners();
      }
    } finally {
      _scanInProgress = false;
      _scheduleNextScan();
    }
  }

  Future<void> _maybeAutoConnect(List<Chameleon> devices) async {
    if (!_shouldScan() ||
        !sharedPreferencesProvider.getAutoConnectFirstFoundDevice()) {
      return;
    }

    Chameleon? connectableDevice;
    for (final device in devices) {
      if (!device.dfu && !isAutoReconnectSuppressed(device.port)) {
        connectableDevice = device;
        break;
      }
    }

    if (connectableDevice == null) {
      _lastAutoConnectAttemptPort = null;
      return;
    }

    if (_lastAutoConnectAttemptPort == connectableDevice.port) {
      return;
    }

    _lastAutoConnectAttemptPort = connectableDevice.port;
    await connectToDevice(connectableDevice);
  }

  /// Connect to a discovered (non-DFU) device. DFU devices need a BuildContext
  /// dialog, so those are handled in the UI layer (ConnectPage) — this returns
  /// false for them. Returns true on a successful connection.
  Future<bool> connectToDevice(Chameleon chameleonDevice) async {
    if (chameleonDevice.dfu || _connecting) {
      return false;
    }

    _connecting = true;
    _scanTimer?.cancel();
    _scanTimer = null;

    bool success = false;
    try {
      if (chameleonDevice.type == ConnectionType.ble) {
        connector!.pendingConnection = true;
        notifyListeners();
      }

      final connected =
          await connector!.connectSpecificDevice(chameleonDevice.port);
      if (connected) {
        connector!.pendingConnection = false;
        clearAutoReconnectSuppression(chameleonDevice.port);
        await attachConnectedCommunicator();
        success = true;
      } else {
        connector!.pendingConnection = false;
      }
      notifyListeners();
    } catch (error) {
      connector!.pendingConnection = false;
      communicator?.dispose(error);
      communicator = null;
      await connector!.performDisconnect();
      scanError = error;
      notifyListeners();
    } finally {
      _connecting = false;
      if (!connector!.connected) {
        _scheduleNextScan();
      }
    }

    return success;
  }
}

class MainPage extends StatefulWidget {
  const MainPage({super.key, required this.sharedPreferencesProvider});

  final SharedPreferencesProvider sharedPreferencesProvider;

  @override
  State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> {
  var selectedIndex = 0;

  // Port of a device the user dismissed from the "device found" banner, so it
  // stays hidden until a different device appears or we reconnect.
  dynamic _dismissedPort;

  // Tracks the disconnected->connected transition so we show the "connected"
  // confirmation exactly once, on whichever path connected (banner, connect
  // page, manual connect, or auto-connect).
  bool _wasConnected = false;
  final GlobalKey<ScaffoldMessengerState> _scaffoldMessengerKey =
      GlobalKey<ScaffoldMessengerState>();

  void _confirmConnected(String deviceName) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final messenger = _scaffoldMessengerKey.currentState;
      final messengerContext = _scaffoldMessengerKey.currentContext;
      if (messenger == null || messengerContext == null) {
        return;
      }
      final localizations = AppLocalizations.of(messengerContext)!;
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
          content: Row(
            children: [
              const Icon(Icons.check_circle, color: Colors.green),
              const SizedBox(width: 12),
              Expanded(
                child: Text(localizations.connected_to_device(deviceName)),
              ),
            ],
          ),
        ),
      );
    });
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance
        .addPostFrameCallback((_) => updateNavigationRailWidth(context));
  }

  @override
  void reassemble() async {
    // Disconnect on reload
    var appState = Provider.of<ChameleonGUIState>(context, listen: false);
    await appState.disconnect();

    super.reassemble();
  }

  AbstractSerial getConnector(ChameleonGUIState appState) {
    if (appState._sharedPreferencesProvider!.isEmulatedChameleon()) {
      return EmulatorSerial(log: appState.log!);
    }

    if (Platform.isMacOS) {
      return MacOSSerial(log: appState.log!);
    }

    if (Platform.isAndroid) {
      return AndroidSerial(log: appState.log!);
    }

    if (Platform.isIOS) {
      return BLESerial(log: appState.log!);
    }

    return NativeSerial(log: appState.log!);
  }

  Logger getLogger(ChameleonGUIState appState) {
    if (appState._sharedPreferencesProvider!.isDebugLogging() &&
        appState._sharedPreferencesProvider!.isDebugMode()) {
      return Logger(
        output: SharedPreferencesLogger(appState._sharedPreferencesProvider!),
        printer: PrettyPrinter(
          noBoxingByDefault: true,
        ),
        filter: ChameleonLogFilter(),
      );
    } else {
      return Logger();
    }
  }

  @override
  Widget build(BuildContext context) {
    var appState = context.watch<ChameleonGUIState>();
    appState._sharedPreferencesProvider = widget.sharedPreferencesProvider;
    appState.log ??= getLogger(appState);
    appState.connector ??= getConnector(appState);
    appState.connector!.connectionStateCallback =
        appState.onConnectorStateChanged;

    if (appState.sharedPreferencesProvider.getSideBarAutoExpansion()) {
      double width = MediaQuery.of(context).size.width;
      if (width >= 600) {
        appState.sharedPreferencesProvider.setSideBarExpanded(true);
      } else {
        appState.sharedPreferencesProvider.setSideBarExpanded(false);
      }
    }

    appState.devMode = appState.sharedPreferencesProvider.isDebugMode();

    // Drive the shared device scanner: run while disconnected, stop otherwise.
    if (appState.connector!.connected ||
        appState.connector!.pendingConnection ||
        appState.connector!.isDFU) {
      appState.stopDeviceScan();
    } else {
      appState.ensureDeviceScanRunning();
    }

    Widget page; // Set Page
    if (!appState.connector!.connected &&
        selectedIndex != 0 &&
        selectedIndex != 2 &&
        selectedIndex != 5 &&
        selectedIndex != 6 &&
        selectedIndex != 8 &&
        selectedIndex != 9) {
      // If not connected, and not on home, tools, settings, ethical hacking hub
      // or dev page, go to home page (reader keys, index 7, requires a device)
      selectedIndex = 0;
    }

    switch (selectedIndex) {
      // Sidebar Navigation
      case 0:
        if (appState.connector!.pendingConnection) {
          page = const PendingConnectionPage();
        } else {
          if (appState.connector!.connected) {
            if (appState.connector!.isDFU) {
              page = const FlashingPage();
            } else {
              page = const HomePage();
            }
          } else {
            page = const ConnectPage();
          }
        }
        break;
      case 1:
        page = const SlotManagerPage();
        break;
      case 2:
        page = const SavedCardsPage();
        break;
      case 3:
        page = const ReadCardPage();
        break;
      case 4:
        page = const WriteCardPage();
        break;
      case 5:
        page = const ToolsPage();
        break;
      case 6:
        page = const SettingsMainPage();
        break;
      case 7:
        page = const ReaderKeysPage();
        break;
      case 8:
        page = const EthicalHackingPage();
        break;
      case 9:
        page = const DebugPage();
        break;
      default:
        throw UnimplementedError('no widget for $selectedIndex');
    }

    try {
      WakelockPlus.toggle(enable: page is FlashingPage);
    } catch (_) {}

    // Confirmation on the disconnected -> connected transition (skip DFU, which
    // is a bootloader link, not a usable device connection).
    final nowConnected =
        appState.connector!.connected && !appState.connector!.isDFU;
    if (nowConnected && !_wasConnected) {
      _confirmConnected(chameleonDeviceName(appState.connector!.device));
    }
    _wasConnected = nowConnected;

    // "Device found" banner: shown on every screen while disconnected (enabled
    // in settings) when a non-DFU device is available that the user hasn't
    // dismissed.
    Chameleon? bannerDevice;
    if (appState.sharedPreferencesProvider.getDeviceFoundBanner() &&
        !appState.connector!.connected &&
        !appState.connector!.pendingConnection &&
        !appState.connector!.isDFU) {
      for (final device in appState.availableDevices) {
        if (!device.dfu && device.port != _dismissedPort) {
          bannerDevice = device;
          break;
        }
      }
    }

    return MaterialApp(
      title: 'Chameleon Ultra GUI', // App Name
      scaffoldMessengerKey: _scaffoldMessengerKey,
      locale: widget.sharedPreferencesProvider.getLocale(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
            seedColor: widget.sharedPreferencesProvider.getThemeColor()),
        brightness: Brightness.light,
        appBarTheme: AppBarTheme(
            systemOverlayStyle: SystemUiOverlayStyle(
                statusBarColor: ColorScheme.fromSeed(
                        seedColor:
                            widget.sharedPreferencesProvider.getThemeColor(),
                        brightness: Brightness.light)
                    .surface,
                statusBarBrightness: Brightness.light,
                statusBarIconBrightness: Brightness.dark)),
      ).useCustomSystemFont(Brightness.light),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
            seedColor: widget.sharedPreferencesProvider.getThemeColor(),
            brightness: Brightness.dark),
        brightness: Brightness.dark,
        appBarTheme: AppBarTheme(
            systemOverlayStyle: SystemUiOverlayStyle(
                statusBarColor: ColorScheme.fromSeed(
                        seedColor:
                            widget.sharedPreferencesProvider.getThemeColor(),
                        brightness: Brightness.dark)
                    .surface,
                statusBarBrightness: Brightness.dark,
                statusBarIconBrightness: Brightness.light)),
      ).useCustomSystemFont(Brightness.dark),
      themeMode: widget.sharedPreferencesProvider.getTheme(), // Dark Theme
      home: LayoutBuilder(// Build Page
          builder: (context, constraints) {
        return SafeArea(
          left: false,
          right: false,
          top: false,
          bottom: true,
          child: Scaffold(
              body: Column(
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        (!appState.connector!.isDFU ||
                                !appState.connector!.connected)
                            ? SafeArea(
                                child: NavigationRail(
                                  key: appState.navigationRailKey,
                                  // Sidebar
                                  extended: appState.sharedPreferencesProvider
                                      .getSideBarExpanded(),
                                  destinations: [
                                    // Sidebar Items
                                    NavigationRailDestination(
                                      icon: const Icon(Icons.home),
                                      label: Text(AppLocalizations.of(context)!
                                          .home), // Home
                                    ),
                                    NavigationRailDestination(
                                      disabled: !appState.connector!.connected,
                                      icon: const Icon(Icons.widgets),
                                      label: Text(AppLocalizations.of(context)!
                                          .slot_manager),
                                    ),
                                    NavigationRailDestination(
                                      icon:
                                          const Icon(Icons.auto_awesome_motion),
                                      label: Text(AppLocalizations.of(context)!
                                          .saved_cards),
                                    ),
                                    NavigationRailDestination(
                                      disabled: !appState.connector!.connected,
                                      icon: const Icon(Icons.sensors),
                                      label: Text(AppLocalizations.of(context)!
                                          .read_card),
                                    ),
                                    NavigationRailDestination(
                                      disabled: !appState.connector!.connected,
                                      icon: const Icon(Icons.system_update_alt),
                                      label: Text(AppLocalizations.of(context)!
                                          .write_card),
                                    ),
                                    NavigationRailDestination(
                                      icon: const Icon(Icons.handyman),
                                      label: Text(
                                          AppLocalizations.of(context)!.tools),
                                    ),
                                    NavigationRailDestination(
                                      icon: const Icon(Icons.settings),
                                      label: Text(AppLocalizations.of(context)!
                                          .settings),
                                    ),
                                    NavigationRailDestination(
                                      disabled: !appState.connector!.connected,
                                      icon: const Icon(Icons.vpn_key),
                                      label: Text(AppLocalizations.of(context)!
                                          .reader_keys_capture),
                                    ),
                                    NavigationRailDestination(
                                      icon: const Icon(Icons.security),
                                      label: Text(AppLocalizations.of(context)!
                                          .ethical_hacking),
                                    ),
                                    if (appState.devMode)
                                      NavigationRailDestination(
                                        icon: const Icon(Icons.bug_report),
                                        label: Text(
                                            '🐞 ${AppLocalizations.of(context)!.debug} 🐞'),
                                      ),
                                  ],
                                  selectedIndex: selectedIndex,
                                  onDestinationSelected: (value) {
                                    setState(() {
                                      selectedIndex = value;
                                    });
                                  },
                                ),
                              )
                            : const SizedBox(),
                        Expanded(
                          child: Container(
                            color:
                                Theme.of(context).colorScheme.primaryContainer,
                            child: page,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Full-width banner spanning both the sidebar and the page.
                  if (bannerDevice != null)
                    DeviceFoundBanner(
                      device: bannerDevice,
                      // Connect in place — don't navigate to the Connect
                      // screen. The banner hides itself once the connection
                      // becomes pending/connected.
                      onConnect: () => appState.connectToDevice(bannerDevice!),
                      onDismiss: () {
                        setState(() {
                          _dismissedPort = bannerDevice!.port;
                        });
                      },
                    ),
                ],
              ),
              bottomNavigationBar: const BottomProgressBar()),
        );
      }),
    );
  }
}

class BottomProgressBar extends StatelessWidget {
  const BottomProgressBar({super.key});

  @override
  Widget build(BuildContext context) {
    var appState = context.watch<ChameleonGUIState>();
    return (appState.connector!.connected && appState.connector!.isDFU)
        ? LinearProgressIndicator(
            value: appState.progress,
            backgroundColor: Colors.grey[300],
            valueColor: const AlwaysStoppedAnimation<Color>(Colors.blue),
          )
        : const SizedBox();
  }
}

import 'dart:async';
import 'dart:io';
import 'package:chameleonultragui/bridge/chameleon.dart';
import 'package:chameleonultragui/connector/serial_abstract.dart';
import 'package:chameleonultragui/connector/serial_android.dart';
import 'package:chameleonultragui/connector/serial_ble.dart';
import 'package:chameleonultragui/connector/serial_emulator.dart';
import 'package:chameleonultragui/connector/serial_macos.dart';
import 'package:chameleonultragui/gui/component/device_found_banner.dart';
import 'package:chameleonultragui/gui/component/module_version_footer.dart';
import 'package:chameleonultragui/gui/component/module_version_navigation.dart';
import 'package:chameleonultragui/gui/undercover/undercover_launcher.dart';
import 'package:chameleonultragui/gui/page/tools.dart';
import 'package:chameleonultragui/helpers/font.dart';
import 'package:chameleonultragui/helpers/emulation_change.dart';
import 'package:chameleonultragui/helpers/definitions.dart';
import 'package:chameleonultragui/helpers/general.dart';
import 'package:chameleonultragui/helpers/mifare_classic/general.dart';
import 'package:chameleonultragui/helpers/module_versions.dart';
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
  bool undercoverMode = false;
  bool undercoverDeviceArmed = false;

  // Flashing easter egg
  bool easterEgg = false;
  dynamic _suppressedAutoReconnectPort;
  bool _disposed = false;

  Timer? _emulationMonitorTimer;
  bool _emulationMonitorInProgress = false;
  int _emulationMonitorGeneration = 0;
  int _emulationMonitorPauseCount = 0;
  _EmulationSnapshot? _emulationBaseline;
  _PendingEmulationChange? _pendingEmulationChange;
  EmulationChangeEntry? latestEmulationChange;
  int emulationChangeSequence = 0;
  Duration emulationMonitorInterval = const Duration(seconds: 3);
  Future<void> _slotOperationTail = Future<void>.value();
  int _slotOperationGeneration = 0;

  GlobalKey navigationRailKey = GlobalKey();
  Size? navigationRailSize;

  void changesMade() {
    if (_disposed) return;
    notifyListeners();
  }

  Future<T> runSlotOperation<T>(
    Future<T> Function() operation, {
    bool invalidatesMonitorBaseline = true,
  }) async {
    final generation = _slotOperationGeneration;
    final expectedCommunicator = communicator;
    final expectedConnector = connector;
    if (expectedCommunicator == null || expectedConnector == null) {
      throw StateError('No connected device for slot operation');
    }
    final previous = _slotOperationTail;
    final release = Completer<void>();
    _slotOperationTail = release.future;
    await previous;
    try {
      if (_disposed ||
          generation != _slotOperationGeneration ||
          !identical(communicator, expectedCommunicator) ||
          !identical(connector, expectedConnector) ||
          !expectedConnector.connected) {
        throw StateError('Slot operation connection changed while queued');
      }
      return await operation();
    } finally {
      if (invalidatesMonitorBaseline) {
        _emulationBaseline = null;
        _pendingEmulationChange?.baselineEligible = false;
      }
      release.complete();
    }
  }

  void onConnectorStateChanged() {
    if (_disposed) return;
    if (connector == null || !connector!.connected) {
      undercoverDeviceArmed = false;
      _slotOperationGeneration++;
      stopEmulationChangeMonitor();
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
    _slotOperationGeneration++;
    final suppressedPort = manual ? connector?.activeDevicePort : null;
    stopEmulationChangeMonitor();
    communicator?.dispose('Disconnected by the application');
    communicator = null;
    await connector?.performDisconnect();
    undercoverDeviceArmed = false;
    if (manual && suppressedPort != null) {
      _suppressedAutoReconnectPort = suppressedPort;
    }
    progress = null;
    if (!_disposed) notifyListeners();
  }

  Future<void> resetConnector() async {
    _slotOperationGeneration++;
    stopDeviceScan();
    stopEmulationChangeMonitor();
    communicator?.dispose('Connector mode changed');
    communicator = null;
    undercoverDeviceArmed = false;
    final previous = connector;
    connector = null;
    previous?.connectionStateCallback = null;
    try {
      await previous?.performDisconnect();
      progress = null;
      if (!_disposed) notifyListeners();
    } catch (_) {
      connector = previous;
      previous?.connectionStateCallback = onConnectorStateChanged;
      rethrow;
    }
  }

  Future<void> attachConnectedCommunicator() async {
    final activeConnector = connector;
    if (_disposed || activeConnector == null || !activeConnector.connected) {
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
      if (!_disposed && identical(connector, activeConnector)) {
        notifyListeners();
      }
      rethrow;
    }
    if (_disposed ||
        !identical(connector, activeConnector) ||
        !activeConnector.connected) {
      next.dispose('Connection completed after application state disposal');
      await activeConnector.performDisconnect();
      return;
    }
    if (undercoverMode && !undercoverDeviceArmed) {
      next.dispose('Undercover mode does not reconnect automatically');
      await activeConnector.performDisconnect();
      progress = null;
      if (!_disposed && identical(connector, activeConnector)) {
        notifyListeners();
      }
      return;
    }
    communicator?.dispose('Replaced by a new connection');
    communicator = next;
    startEmulationChangeMonitor();
  }

  bool get canEnterUndercover {
    final activeConnector = connector;
    return !_disposed &&
        activeConnector != null &&
        activeConnector.connected &&
        !activeConnector.isDFU &&
        activeConnector.connectionType == ConnectionType.ble &&
        communicator?.supportsCommandSync(
              ChameleonCommand.setRuntimeUndercoverMode,
            ) ==
            true;
  }

  Future<void> enterUndercover() async {
    if (!canEnterUndercover) {
      throw StateError('Undercover mode is unavailable on this connection');
    }
    final activeConnector = connector!;
    final activeCommunicator = communicator!;
    await activeCommunicator.setRuntimeUndercoverMode(true);
    if (_disposed ||
        !identical(connector, activeConnector) ||
        !identical(communicator, activeCommunicator) ||
        !activeConnector.connected) {
      throw StateError('Connection changed while entering Undercover mode');
    }
    stopEmulationChangeMonitor();
    undercoverDeviceArmed = true;
    undercoverMode = true;
    notifyListeners();
  }

  Future<void> exitUndercover() async {
    final activeConnector = connector;
    final activeCommunicator = communicator;
    Object? exitError;
    try {
      if (undercoverDeviceArmed &&
          activeConnector != null &&
          activeConnector.connected &&
          activeCommunicator != null) {
        try {
          await activeCommunicator.setRuntimeUndercoverMode(false);
        } catch (_) {
          try {
            if (activeConnector.connected) {
              await disconnect(manual: true);
            }
          } catch (error) {
            exitError = error;
          }
        }
      }
    } finally {
      undercoverDeviceArmed = false;
      undercoverMode = false;
      startEmulationChangeMonitor();
      if (!_disposed) notifyListeners();
    }
    if (exitError != null) throw exitError;
  }

  bool _shouldMonitorEmulationChanges() {
    final activeConnector = connector;
    return !_disposed &&
        !undercoverMode &&
        sharedPreferencesProvider.getEmulationChangeMonitoring() &&
        _emulationMonitorPauseCount == 0 &&
        activeConnector != null &&
        activeConnector.connected &&
        !activeConnector.isDFU &&
        communicator != null &&
        communicator!.supportsCommandSync(
              ChameleonCommand.activeSlotSnapshot,
            ) ==
            true;
  }

  Future<void> setEmulationChangeMonitoring(bool enabled) async {
    await sharedPreferencesProvider.setEmulationChangeMonitoring(enabled);
    if (enabled) {
      startEmulationChangeMonitor();
    } else {
      stopEmulationChangeMonitor();
    }
    notifyListeners();
  }

  void startEmulationChangeMonitor() {
    if (!_shouldMonitorEmulationChanges() ||
        _emulationMonitorTimer != null ||
        _emulationMonitorInProgress) {
      return;
    }
    final generation = ++_emulationMonitorGeneration;
    _emulationBaseline = null;
    _pollEmulationChanges(generation);
  }

  void stopEmulationChangeMonitor() {
    _emulationMonitorGeneration++;
    _emulationMonitorTimer?.cancel();
    _emulationMonitorTimer = null;
    _emulationBaseline = null;
  }

  Future<void> pauseEmulationChangeMonitor() async {
    _emulationMonitorPauseCount++;
    stopEmulationChangeMonitor();
    while (_emulationMonitorInProgress) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  }

  void resumeEmulationChangeMonitor() {
    if (_emulationMonitorPauseCount == 0) return;
    _emulationMonitorPauseCount--;
    if (_emulationMonitorPauseCount == 0) startEmulationChangeMonitor();
  }

  void _scheduleEmulationChangePoll(int generation) {
    _emulationMonitorTimer?.cancel();
    _emulationMonitorTimer = null;
    if (generation != _emulationMonitorGeneration ||
        !_shouldMonitorEmulationChanges()) {
      return;
    }
    _emulationMonitorTimer = Timer(
      emulationMonitorInterval,
      () => _pollEmulationChanges(generation),
    );
  }

  Future<_FrozenEmulationSnapshot> _captureEmulationSnapshot(
    ChameleonCommunicator activeCommunicator,
    AbstractSerial activeConnector,
    int generation,
  ) async {
    _requireCurrentEmulationMonitor(
      activeCommunicator,
      activeConnector,
      generation,
    );
    final transaction = await activeCommunicator.beginActiveSlotSnapshot();
    try {
      _requireCurrentEmulationMonitor(
        activeCommunicator,
        activeConnector,
        generation,
      );
      final blockCount = mfClassicGetBlockCount(
        chameleonTagTypeGetMfClassicType(transaction.tagType),
      );
      if (blockCount == 0) {
        throw const FormatException('Snapshot has an invalid MIFARE type');
      }

      _requireCurrentEmulationMonitor(
        activeCommunicator,
        activeConnector,
        generation,
      );
      final cardData = await activeCommunicator.mf1GetSnapshotAntiColl(
        transaction,
      );
      _requireCurrentEmulationMonitor(
        activeCommunicator,
        activeConnector,
        generation,
      );
      final memory = Uint8List(blockCount * 16);
      for (var start = 0; start < blockCount; start += 16) {
        _requireCurrentEmulationMonitor(
          activeCommunicator,
          activeConnector,
          generation,
        );
        final remaining = blockCount - start;
        final count = remaining > 16 ? 16 : remaining;
        final chunk = await activeCommunicator.mf1GetSnapshotBlocks(
          transaction,
          start,
          count,
        );
        _requireCurrentEmulationMonitor(
          activeCommunicator,
          activeConnector,
          generation,
        );
        memory.setRange(start * 16, (start + count) * 16, chunk);
      }

      return _FrozenEmulationSnapshot(
        transaction: transaction,
        snapshot: _EmulationSnapshot(
          slot: transaction.slot,
          tagType: transaction.tagType,
          ownerGeneration: transaction.ownerGeneration,
          uid: bytesToHex(cardData.uid),
          memory: memory,
        ),
      );
    } catch (_) {
      try {
        await activeCommunicator.abortActiveSlotSnapshot(transaction);
      } catch (_) {}
      rethrow;
    }
  }

  void _requireCurrentEmulationMonitor(
    ChameleonCommunicator activeCommunicator,
    AbstractSerial activeConnector,
    int generation,
  ) {
    if (_disposed ||
        generation != _emulationMonitorGeneration ||
        !identical(communicator, activeCommunicator) ||
        !identical(connector, activeConnector) ||
        !activeConnector.connected) {
      throw const _EmulationMonitorCancelled();
    }
  }

  Future<bool> _persistPendingEmulationChange(
    ChameleonCommunicator activeCommunicator,
    AbstractSerial activeConnector,
    int generation,
  ) async {
    final pending = _pendingEmulationChange;
    if (pending == null) return true;
    try {
      await sharedPreferencesProvider.addEmulationChange(pending.entry);
    } catch (error, stackTrace) {
      log?.w(
        'Emulation history persistence failed; retry is pending',
        error: error,
        stackTrace: stackTrace,
      );
      return false;
    }
    if (!identical(_pendingEmulationChange, pending)) return false;
    _pendingEmulationChange = null;
    if (pending.baselineEligible &&
        generation == _emulationMonitorGeneration &&
        identical(pending.communicator, activeCommunicator) &&
        identical(pending.connector, activeConnector) &&
        identical(communicator, activeCommunicator) &&
        identical(connector, activeConnector) &&
        activeConnector.connected) {
      _emulationBaseline = pending.snapshot;
    }
    if (!_disposed) {
      latestEmulationChange = pending.entry;
      emulationChangeSequence++;
      notifyListeners();
    }
    return true;
  }

  Future<void> _pollEmulationChanges(int generation) async {
    if (_emulationMonitorInProgress ||
        generation != _emulationMonitorGeneration ||
        !_shouldMonitorEmulationChanges()) {
      return;
    }
    _emulationMonitorTimer?.cancel();
    _emulationMonitorTimer = null;
    _emulationMonitorInProgress = true;
    final activeCommunicator = communicator!;
    final activeConnector = connector!;
    try {
      await runSlotOperation(() async {
        if (_pendingEmulationChange != null) {
          await _persistPendingEmulationChange(
            activeCommunicator,
            activeConnector,
            generation,
          );
          return;
        }
        final frozen = await _captureEmulationSnapshot(
          activeCommunicator,
          activeConnector,
          generation,
        );
        var released = false;
        try {
          final snapshot = frozen.snapshot;
          if (generation != _emulationMonitorGeneration ||
              !identical(communicator, activeCommunicator) ||
              !identical(connector, activeConnector) ||
              !activeConnector.connected) {
            try {
              await activeCommunicator.abortActiveSlotSnapshot(
                frozen.transaction,
              );
            } catch (_) {}
            released = true;
            return;
          }

          final baseline = _emulationBaseline;
          if (baseline == null || !baseline.matchesTag(snapshot)) {
            await activeCommunicator.abortActiveSlotSnapshot(
              frozen.transaction,
            );
            released = true;
            _emulationBaseline = snapshot;
            return;
          }

          final changes = diffEmulationBlocks(baseline.memory, snapshot.memory);
          if (changes.isEmpty) {
            await activeCommunicator.abortActiveSlotSnapshot(
              frozen.transaction,
            );
            released = true;
            _emulationBaseline = snapshot;
            return;
          }

          final entry = EmulationChangeEntry(
            timestamp: DateTime.now().toUtc(),
            slot: snapshot.slot,
            tagType: snapshot.tagType,
            uid: snapshot.uid,
            changes: changes,
          );
          if (generation != _emulationMonitorGeneration ||
              !identical(communicator, activeCommunicator) ||
              !identical(connector, activeConnector) ||
              !activeConnector.connected) {
            try {
              await activeCommunicator.abortActiveSlotSnapshot(
                frozen.transaction,
              );
            } catch (_) {}
            released = true;
            return;
          }

          await activeCommunicator.saveReleaseActiveSlotSnapshot(
            frozen.transaction,
          );
          released = true;
          _pendingEmulationChange = _PendingEmulationChange(
            entry: entry,
            snapshot: snapshot,
            communicator: activeCommunicator,
            connector: activeConnector,
          );
          await _persistPendingEmulationChange(
            activeCommunicator,
            activeConnector,
            generation,
          );
        } finally {
          if (!released) {
            try {
              await activeCommunicator.abortActiveSlotSnapshot(
                frozen.transaction,
              );
            } catch (_) {}
          }
        }
      }, invalidatesMonitorBaseline: false);
    } catch (error, stackTrace) {
      log?.w(
        'Emulation change monitor failed',
        error: error,
        stackTrace: stackTrace,
      );
    } finally {
      _emulationMonitorInProgress = false;
      if (generation == _emulationMonitorGeneration) {
        _scheduleEmulationChangePoll(generation);
      } else if (_shouldMonitorEmulationChanges()) {
        startEmulationChangeMonitor();
      }
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _slotOperationGeneration++;
    stopDeviceScan();
    stopEmulationChangeMonitor();
    communicator?.dispose('Application state disposed');
    communicator = null;
    final activeConnector = connector;
    connector = null;
    activeConnector?.connectionStateCallback = null;
    if (activeConnector != null) {
      unawaited(
        activeConnector.performDisconnect().then<void>((_) {}).catchError((
          Object error,
          StackTrace stackTrace,
        ) {
          log?.w(
            'Connector teardown failed during state disposal',
            error: error,
            stackTrace: stackTrace,
          );
        }),
      );
    }
    super.dispose();
  }

  void setProgressBar(dynamic value) {
    if (_disposed) return;
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
  int _deviceScanGeneration = 0;
  bool _connecting = false;
  dynamic _lastAutoConnectAttemptPort;
  String _lastDevicesSignature = '';
  bool _lastScanHadError = false;

  bool _shouldScan() {
    final c = connector;
    return !_disposed &&
        c != null &&
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
    _deviceScanGeneration++;
    _scanTimer?.cancel();
    _scanTimer = null;
    _scanInProgress = false;
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
    final keys =
        devices.map((d) => '${d.port}|${d.type.name}|${d.dfu}').toList()
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
    final activeConnector = connector;
    if (_scanInProgress || !_shouldScan() || activeConnector == null) {
      return;
    }
    final generation = _deviceScanGeneration;
    _scanTimer?.cancel();
    _scanTimer = null;
    _scanInProgress = true;
    try {
      final devices = _normalizeDevices(
        await activeConnector.availableChameleons(false),
      );
      if (!_isCurrentDeviceScan(generation, activeConnector)) return;
      syncAutoReconnectSuppression(devices.map((device) => device.port));

      final firstConnectablePort = _firstConnectablePort(devices);
      if (firstConnectablePort != _lastAutoConnectAttemptPort) {
        _lastAutoConnectAttemptPort = null;
      }

      final signature = _signatureOf(devices);
      final changed =
          signature != _lastDevicesSignature ||
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
      if (!_isCurrentDeviceScan(generation, activeConnector)) return;
      await activeConnector.performDisconnect();
      if (!_isCurrentDeviceScan(generation, activeConnector)) return;
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
      if (_isCurrentDeviceScan(generation, activeConnector)) {
        _scanInProgress = false;
        _scheduleNextScan();
      }
    }
  }

  bool _isCurrentDeviceScan(int generation, AbstractSerial activeConnector) =>
      !_disposed &&
      generation == _deviceScanGeneration &&
      identical(connector, activeConnector);

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
    final activeConnector = connector;
    if (_disposed ||
        activeConnector == null ||
        chameleonDevice.dfu ||
        _connecting) {
      return false;
    }

    _connecting = true;
    _scanTimer?.cancel();
    _scanTimer = null;

    bool success = false;
    try {
      if (chameleonDevice.type == ConnectionType.ble) {
        activeConnector.pendingConnection = true;
        notifyListeners();
      }

      final connected = await activeConnector.connectSpecificDevice(
        chameleonDevice.port,
      );
      if (_disposed || !identical(connector, activeConnector)) {
        if (connected) await activeConnector.performDisconnect();
        return false;
      }
      if (connected) {
        activeConnector.pendingConnection = false;
        clearAutoReconnectSuppression(chameleonDevice.port);
        await attachConnectedCommunicator();
        success =
            !_disposed &&
            identical(connector, activeConnector) &&
            activeConnector.connected &&
            communicator != null;
      } else {
        activeConnector.pendingConnection = false;
      }
      if (!_disposed && identical(connector, activeConnector)) {
        notifyListeners();
      }
    } catch (error) {
      activeConnector.pendingConnection = false;
      communicator?.dispose(error);
      communicator = null;
      await activeConnector.performDisconnect();
      if (!_disposed && identical(connector, activeConnector)) {
        scanError = error;
        notifyListeners();
      }
    } finally {
      _connecting = false;
      if (!_disposed &&
          identical(connector, activeConnector) &&
          !activeConnector.connected) {
        _scheduleNextScan();
      }
    }

    return success;
  }
}

class _EmulationSnapshot {
  final int slot;
  final TagType tagType;
  final int ownerGeneration;
  final String uid;
  final Uint8List memory;

  const _EmulationSnapshot({
    required this.slot,
    required this.tagType,
    required this.ownerGeneration,
    required this.uid,
    required this.memory,
  });

  bool matchesTag(_EmulationSnapshot other) {
    return slot == other.slot &&
        tagType == other.tagType &&
        ownerGeneration == other.ownerGeneration;
  }
}

class _PendingEmulationChange {
  final EmulationChangeEntry entry;
  final _EmulationSnapshot snapshot;
  final ChameleonCommunicator communicator;
  final AbstractSerial connector;
  bool baselineEligible = true;

  _PendingEmulationChange({
    required this.entry,
    required this.snapshot,
    required this.communicator,
    required this.connector,
  });
}

class _EmulationMonitorCancelled implements Exception {
  const _EmulationMonitorCancelled();
}

class _FrozenEmulationSnapshot {
  final MifareClassicActiveSlotSnapshot transaction;
  final _EmulationSnapshot snapshot;

  const _FrozenEmulationSnapshot({
    required this.transaction,
    required this.snapshot,
  });
}

class MainPage extends StatefulWidget {
  const MainPage({super.key, required this.sharedPreferencesProvider});

  final SharedPreferencesProvider sharedPreferencesProvider;

  @override
  State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> {
  var selectedIndex = 0;
  final ValueNotifier<ModuleId> _activeModule = ValueNotifier(ModuleId.device);
  late final ModuleNavigationObserver _moduleNavigationObserver =
      ModuleNavigationObserver(
        activeModule: _activeModule,
        rootModule: ModuleId.device,
      );

  // Port of a device the user dismissed from the "device found" banner, so it
  // stays hidden until a different device appears or we reconnect.
  dynamic _dismissedPort;

  // Tracks the disconnected->connected transition so we show the "connected"
  // confirmation exactly once, on whichever path connected (banner, connect
  // page, manual connect, or auto-connect).
  bool _wasConnected = false;
  bool _wasUndercover = false;
  int _lastShownEmulationChangeSequence = 0;
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
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

  void _notifyEmulationChange(EmulationChangeEntry entry) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final messenger = _scaffoldMessengerKey.currentState;
      if (messenger == null) return;
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 5),
          content: Row(
            children: [
              const Icon(Icons.history, color: Colors.amber),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Emulated tag changed in slot ${entry.slot + 1}: '
                  '${entry.changes.length} block${entry.changes.length == 1 ? '' : 's'} archived.',
                ),
              ),
            ],
          ),
        ),
      );
    });
  }

  Future<void> _requestUndercoverExit(ChameleonGUIState appState) async {
    final dialogContext = _navigatorKey.currentContext;
    if (dialogContext == null) return;
    final localizations = AppLocalizations.of(dialogContext)!;
    final confirmed =
        await showDialog<bool>(
          context: dialogContext,
          builder: (context) => AlertDialog(
            title: Text(localizations.undercover_exit_title),
            content: Text(localizations.undercover_exit_message),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(localizations.cancel),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(localizations.undercover_exit),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed) return;

    try {
      await appState.exitUndercover();
      if (!mounted) return;
      _moduleNavigationObserver.setRootModule(ModuleId.device);
      setState(() => selectedIndex = 0);
    } catch (error) {
      final errorContext = _navigatorKey.currentContext;
      if (errorContext == null || !errorContext.mounted) return;
      await showDialog<void>(
        context: errorContext,
        builder: (context) => AlertDialog(
          title: Text(localizations.error),
          content: Text(error.toString()),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(localizations.close),
            ),
          ],
        ),
      );
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => updateNavigationRailWidth(context),
    );
  }

  @override
  void dispose() {
    _activeModule.dispose();
    super.dispose();
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
        printer: PrettyPrinter(noBoxingByDefault: true),
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

    if (!appState.undercoverMode &&
        appState.sharedPreferencesProvider.getSideBarAutoExpansion()) {
      double width = MediaQuery.of(context).size.width;
      if (width >= 600) {
        appState.sharedPreferencesProvider.setSideBarExpanded(true);
      } else {
        appState.sharedPreferencesProvider.setSideBarExpanded(false);
      }
    }

    appState.devMode = appState.sharedPreferencesProvider.isDebugMode();

    // Drive the shared device scanner: run while disconnected, stop otherwise.
    if (appState.undercoverMode ||
        appState.connector!.connected ||
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
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _moduleNavigationObserver.setRootModule(ModuleId.device);
        }
      });
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
    if (nowConnected && !_wasConnected && !appState.undercoverMode) {
      _confirmConnected(chameleonDeviceName(appState.connector!.device));
    }
    _wasConnected = nowConnected;

    if (appState.undercoverMode != _wasUndercover) {
      _wasUndercover = appState.undercoverMode;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _moduleNavigationObserver.setRootModule(
          appState.undercoverMode ? ModuleId.undercover : ModuleId.device,
        );
        if (appState.undercoverMode) {
          _scaffoldMessengerKey.currentState?.hideCurrentSnackBar();
        }
      });
    }

    if (!appState.undercoverMode &&
        appState.emulationChangeSequence > _lastShownEmulationChangeSequence &&
        appState.latestEmulationChange != null) {
      _lastShownEmulationChangeSequence = appState.emulationChangeSequence;
      _notifyEmulationChange(appState.latestEmulationChange!);
    }

    // "Device found" banner: shown on every screen while disconnected (enabled
    // in settings) when a non-DFU device is available that the user hasn't
    // dismissed.
    Chameleon? bannerDevice;
    if (!appState.undercoverMode &&
        appState.sharedPreferencesProvider.getDeviceFoundBanner() &&
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
      navigatorKey: _navigatorKey,
      onGenerateTitle: (context) => appState.undercoverMode
          ? AppLocalizations.of(context)!.home
          : 'Chameleon Ultra GUI',
      scaffoldMessengerKey: _scaffoldMessengerKey,
      locale: widget.sharedPreferencesProvider.getLocale(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: widget.sharedPreferencesProvider.getThemeColor(),
        ),
        brightness: Brightness.light,
        appBarTheme: AppBarTheme(
          systemOverlayStyle: SystemUiOverlayStyle(
            statusBarColor: ColorScheme.fromSeed(
              seedColor: widget.sharedPreferencesProvider.getThemeColor(),
              brightness: Brightness.light,
            ).surface,
            statusBarBrightness: Brightness.light,
            statusBarIconBrightness: Brightness.dark,
          ),
        ),
      ).useCustomSystemFont(Brightness.light),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: widget.sharedPreferencesProvider.getThemeColor(),
          brightness: Brightness.dark,
        ),
        brightness: Brightness.dark,
        appBarTheme: AppBarTheme(
          systemOverlayStyle: SystemUiOverlayStyle(
            statusBarColor: ColorScheme.fromSeed(
              seedColor: widget.sharedPreferencesProvider.getThemeColor(),
              brightness: Brightness.dark,
            ).surface,
            statusBarBrightness: Brightness.dark,
            statusBarIconBrightness: Brightness.light,
          ),
        ),
      ).useCustomSystemFont(Brightness.dark),
      themeMode: widget.sharedPreferencesProvider.getTheme(), // Dark Theme
      navigatorObservers: [_moduleNavigationObserver],
      builder: (context, child) {
        return ModuleVersionScope(
          notifier: _activeModule,
          child: appState.undercoverMode
              ? child ?? const SizedBox.shrink()
              : Column(
                  children: [
                    Expanded(child: child ?? const SizedBox.shrink()),
                    ValueListenableBuilder<ModuleId>(
                      valueListenable: _activeModule,
                      builder: (context, moduleId, _) {
                        return ModuleVersionFooter(moduleId: moduleId);
                      },
                    ),
                  ],
                ),
        );
      },
      home: LayoutBuilder(
        // Build Page
        builder: (context, constraints) {
          if (appState.undercoverMode) {
            return UndercoverLauncher(
              connected: nowConnected && appState.undercoverDeviceArmed,
              onExitRequested: () => _requestUndercoverExit(appState),
            );
          }
          return SafeArea(
            left: false,
            right: false,
            top: false,
            bottom: false,
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
                                      label: Text(
                                        AppLocalizations.of(context)!.home,
                                      ), // Home
                                    ),
                                    NavigationRailDestination(
                                      disabled: !appState.connector!.connected,
                                      icon: const Icon(Icons.widgets),
                                      label: Text(
                                        AppLocalizations.of(
                                          context,
                                        )!.slot_manager,
                                      ),
                                    ),
                                    NavigationRailDestination(
                                      icon: const Icon(
                                        Icons.auto_awesome_motion,
                                      ),
                                      label: Text(
                                        AppLocalizations.of(
                                          context,
                                        )!.saved_cards,
                                      ),
                                    ),
                                    NavigationRailDestination(
                                      disabled: !appState.connector!.connected,
                                      icon: const Icon(Icons.sensors),
                                      label: Text(
                                        AppLocalizations.of(context)!.read_card,
                                      ),
                                    ),
                                    NavigationRailDestination(
                                      disabled: !appState.connector!.connected,
                                      icon: const Icon(Icons.system_update_alt),
                                      label: Text(
                                        AppLocalizations.of(
                                          context,
                                        )!.write_card,
                                      ),
                                    ),
                                    NavigationRailDestination(
                                      icon: const Icon(Icons.handyman),
                                      label: Text(
                                        AppLocalizations.of(context)!.tools,
                                      ),
                                    ),
                                    NavigationRailDestination(
                                      icon: const Icon(Icons.settings),
                                      label: Text(
                                        AppLocalizations.of(context)!.settings,
                                      ),
                                    ),
                                    NavigationRailDestination(
                                      disabled: !appState.connector!.connected,
                                      icon: const Icon(Icons.vpn_key),
                                      label: Text(
                                        AppLocalizations.of(
                                          context,
                                        )!.reader_keys_capture,
                                      ),
                                    ),
                                    NavigationRailDestination(
                                      icon: const Icon(Icons.security),
                                      label: Text(
                                        AppLocalizations.of(
                                          context,
                                        )!.ethical_hacking,
                                      ),
                                    ),
                                    if (appState.devMode)
                                      NavigationRailDestination(
                                        icon: const Icon(Icons.bug_report),
                                        label: Text(
                                          '🐞 ${AppLocalizations.of(context)!.debug} 🐞',
                                        ),
                                      ),
                                  ],
                                  selectedIndex: selectedIndex,
                                  onDestinationSelected: (value) {
                                    _moduleNavigationObserver.setRootModule(
                                      _moduleForIndex(value),
                                    );
                                    setState(() {
                                      selectedIndex = value;
                                    });
                                  },
                                ),
                              )
                            : const SizedBox(),
                        Expanded(
                          child: Container(
                            color: Theme.of(
                              context,
                            ).colorScheme.primaryContainer,
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
              bottomNavigationBar: const BottomProgressBar(),
            ),
          );
        },
      ),
    );
  }

  ModuleId _moduleForIndex(int index) {
    return switch (index) {
      0 => ModuleId.device,
      1 => ModuleId.slotManager,
      2 => ModuleId.library,
      3 => ModuleId.readCard,
      4 => ModuleId.writeCard,
      5 => ModuleId.tools,
      6 => ModuleId.settings,
      7 => ModuleId.readerKeysCapture,
      8 => ModuleId.ethicalHacking,
      9 => ModuleId.debug,
      _ => ModuleId.appShell,
    };
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

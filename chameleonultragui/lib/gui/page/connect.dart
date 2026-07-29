import 'package:chameleonultragui/connector/serial_abstract.dart';
import 'package:chameleonultragui/connector/serial_android.dart';
import 'package:chameleonultragui/gui/component/error_page.dart';
import 'package:chameleonultragui/gui/menu/dialogs/manual_connect.dart';
import 'package:chameleonultragui/helpers/flash.dart';
import 'package:chameleonultragui/helpers/general.dart';
import 'package:chameleonultragui/main.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

// Localizations
import 'package:chameleonultragui/generated/i18n/app_localizations.dart';

class ConnectPage extends StatefulWidget {
  const ConnectPage({super.key});

  @override
  State<ConnectPage> createState() => _ConnectPageState();
}

class _ConnectPageState extends State<ConnectPage> {
  bool _showedPermissionsSnackbar = false;

  ChameleonGUIState get _appState =>
      Provider.of<ChameleonGUIState>(context, listen: false);

  @override
  void initState() {
    super.initState();
    // The scanner is owned by ChameleonGUIState and normally started from
    // MainPage.build while disconnected; make sure it's running when this page
    // is shown.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _appState.ensureDeviceScanRunning();
      }
    });
  }

  void _showPermissionsWarningIfNeeded(List<Chameleon> devices) {
    final appState = _appState;
    if (appState.connector is! AndroidSerial) {
      _showedPermissionsSnackbar = false;
      return;
    }

    final androidSerial = appState.connector as AndroidSerial;
    final shouldShow = devices.isEmpty && !androidSerial.hasAllPermissions;
    if (!shouldShow) {
      _showedPermissionsSnackbar = false;
      return;
    }

    if (_showedPermissionsSnackbar) {
      return;
    }

    _showedPermissionsSnackbar = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }

      final scaffoldMessenger = ScaffoldMessenger.of(context);
      final localizations = AppLocalizations.of(context)!;
      final snackBar = SnackBar(
        content: Text(localizations.android_ble_permissions_missing),
        action: SnackBarAction(label: localizations.close, onPressed: () {}),
      );

      scaffoldMessenger.hideCurrentSnackBar();
      scaffoldMessenger.showSnackBar(snackBar);
    });
  }

  Future<void> _onDeviceTap(Chameleon chameleonDevice) async {
    if (chameleonDevice.dfu) {
      _showDfuDialog(chameleonDevice);
      return;
    }
    await _appState.connectToDevice(chameleonDevice);
  }

  void _showDfuDialog(Chameleon chameleonDevice) {
    final appState = _appState;
    final localizations = AppLocalizations.of(context)!;
    final scaffoldMessenger = ScaffoldMessenger.of(context);

    showDialog<String>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: Text(localizations.chameleon_is_dfu),
        content: Text(localizations.firmware_is_corrupted),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, localizations.cancel),
            child: Text(localizations.cancel),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(dialogContext, localizations.flash);
              appState.changesMade();

              scaffoldMessenger.hideCurrentSnackBar();
              scaffoldMessenger.showSnackBar(
                SnackBar(
                  content: Text(
                    localizations.downloading_fw(
                      chameleonDeviceName(chameleonDevice.device),
                    ),
                  ),
                  action: SnackBarAction(
                    label: localizations.close,
                    onPressed: scaffoldMessenger.hideCurrentSnackBar,
                  ),
                ),
              );

              await flashFirmware(
                appState,
                scaffoldMessenger: scaffoldMessenger,
                device: chameleonDevice.device,
                enterDFU: false,
              );

              appState.changesMade();
              if (mounted) {
                appState.refreshDeviceScan();
              }
            },
            child: Text(localizations.flash),
          ),
        ],
      ),
    );
  }

  Widget _buildDeviceGrid(
    AppLocalizations localizations,
    List<Chameleon> devices,
  ) {
    return GridView(
      padding: const EdgeInsets.all(20),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        childAspectRatio: 1,
      ),
      scrollDirection: Axis.vertical,
      children: [
        ...devices.map<Widget>((chameleonDevice) {
          return ElevatedButton(
            onPressed: () => _onDeviceTap(chameleonDevice),
            style: ButtonStyle(
              shape: WidgetStateProperty.all<RoundedRectangleBorder>(
                RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18.0),
                ),
              ),
            ),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: FittedBox(
                    alignment: Alignment.centerRight,
                    fit: BoxFit.scaleDown,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            chameleonDevice.type == ConnectionType.ble
                                ? const Icon(Icons.bluetooth)
                                : const Icon(Icons.usb),
                            Text(chameleonDevice.port ?? ""),
                            if (chameleonDevice.dfu) Text(localizations.dfu),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                FittedBox(
                  alignment: Alignment.topRight,
                  fit: BoxFit.scaleDown,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.start,
                    children: [
                      Text(
                        "Chameleon ${chameleonDeviceName(chameleonDevice.device)}",
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 20,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: Image.asset(
                    chameleonDevice.device == ChameleonDevice.ultra
                        ? 'assets/black-ultra-standing-front.webp'
                        : 'assets/black-lite-standing-front.webp',
                    fit: BoxFit.fitHeight,
                    errorBuilder: (_, _, _) => const SizedBox.shrink(),
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ),
          );
        }),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<ChameleonGUIState>();
    final localizations = AppLocalizations.of(context)!;

    if (appState.scanError != null) {
      return Scaffold(
        appBar: AppBar(title: Text(localizations.connect)),
        body: ErrorPage(errorMessage: appState.scanError.toString()),
      );
    }

    final devices = appState.availableDevices;
    _showPermissionsWarningIfNeeded(devices);

    return Scaffold(
      appBar: AppBar(title: Text(localizations.connect)),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Align(
              alignment: Alignment.topRight,
              child: IconButton(
                onPressed: () => appState.refreshDeviceScan(),
                icon: const Icon(Icons.refresh),
              ),
            ),
            Expanded(
              child: !appState.hasCompletedDeviceScan
                  ? const Center(child: CircularProgressIndicator())
                  : _buildDeviceGrid(localizations, devices),
            ),
            if (appState.connector!.isManualConnectionSupported())
              Align(
                alignment: Alignment.bottomRight,
                child: Row(
                  children: [
                    const Spacer(),
                    Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: IconButton(
                        onPressed: () => showDialog<String>(
                          context: context,
                          builder: (BuildContext dialogContext) =>
                              const ManualConnect(),
                        ),
                        icon: const Icon(Icons.add),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

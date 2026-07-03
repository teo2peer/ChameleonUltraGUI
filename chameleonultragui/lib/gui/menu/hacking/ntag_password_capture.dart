import 'dart:async';

import 'package:chameleonultragui/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

// Localizations
import 'package:chameleonultragui/generated/i18n/app_localizations.dart';

// Capture reader PWD_AUTH passwords by emulating an NTAG / Ultralight tag.
// Reuses the firmware NTAG detection log (mf0Ntag* commands). The user should
// have an NTAG/Ultralight slot active before arming.
class NtagPasswordCapturePage extends StatefulWidget {
  const NtagPasswordCapturePage({super.key});

  @override
  NtagPasswordCapturePageState createState() => NtagPasswordCapturePageState();
}

class NtagPasswordCapturePageState extends State<NtagPasswordCapturePage> {
  bool armed = false;
  bool busy = false;
  int count = 0;
  List<String> passwords = [];
  Timer? _poll;

  ChameleonGUIState get _app => context.read<ChameleonGUIState>();
  bool get _connected => _app.connector?.connected ?? false;

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  void _startPolling() {
    _poll?.cancel();
    _poll = Timer.periodic(const Duration(seconds: 2), (_) => _refreshCount());
  }

  Future<void> _refreshCount() async {
    if (!_connected) return;
    try {
      final c = await _app.communicator!.mf0NtagGetDetectionCount();
      if (mounted) setState(() => count = c);
    } catch (_) {}
  }

  Future<void> _arm() async {
    setState(() => busy = true);
    try {
      await _app.communicator!.mf0NtagSetDetectionEnable(true);
      if (!mounted) return;
      setState(() {
        armed = true;
        count = 0;
        passwords = [];
      });
      _startPolling();
    } catch (e) {
      _show(e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _stop() async {
    setState(() => busy = true);
    _poll?.cancel();
    try {
      await _app.communicator!.mf0NtagSetDetectionEnable(false);
    } catch (e) {
      _show(e.toString());
    } finally {
      if (mounted) {
        setState(() {
          armed = false;
          busy = false;
        });
      }
    }
  }

  Future<void> _download() async {
    setState(() => busy = true);
    try {
      final total = await _app.communicator!.mf0NtagGetDetectionCount();
      final List<String> all = [];
      int index = 0;
      while (index < total) {
        final chunk = await _app.communicator!.mf0NtagGetDetectionLog(index);
        if (chunk.isEmpty) break;
        all.addAll(chunk);
        index += chunk.length;
      }
      if (mounted) setState(() => passwords = all);
    } catch (e) {
      _show(e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void _show(String m) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
    }
  }

  @override
  Widget build(BuildContext context) {
    var localizations = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(title: Text(localizations.ntag_password_capture)),
      body: !_connected
          ? Center(child: Text(localizations.no_device))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  Text(localizations.ntag_password_capture_description,
                      textAlign: TextAlign.center),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: busy ? null : (armed ? _stop : _arm),
                    icon: Icon(armed ? Icons.stop : Icons.wifi_tethering),
                    label: Text(armed
                        ? localizations.stop_capture
                        : localizations.arm_capture),
                  ),
                  const SizedBox(height: 10),
                  if (armed)
                    Text(localizations.captured_passwords(count),
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 10),
                  ElevatedButton(
                    onPressed: (busy || count <= 0) ? null : _download,
                    child: Text(localizations.recover_key),
                  ),
                  const SizedBox(height: 12),
                  if (passwords.isEmpty)
                    Text(localizations.no_passwords_captured,
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.outline))
                  else
                    ...passwords.map((p) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2.0),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              SelectableText(p.toUpperCase(),
                                  style: const TextStyle(
                                      fontFamily: 'RobotoMono',
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold)),
                              IconButton(
                                icon: const Icon(Icons.copy, size: 16),
                                onPressed: () => Clipboard.setData(
                                    ClipboardData(text: p.toUpperCase())),
                              ),
                            ],
                          ),
                        )),
                ],
              ),
            ),
    );
  }
}

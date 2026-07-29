import 'package:flutter/services.dart';

class RelayLabPlatform {
  static const _methods = MethodChannel('io.chameleon.ultra/relay_lab_methods');
  static const _events = EventChannel('io.chameleon.ultra/relay_lab_events');

  Stream<Map<String, Object?>> get apduEvents => _events
      .receiveBroadcastStream()
      .where((event) => event is Map)
      .map((event) => Map<String, Object?>.from(event as Map));

  Future<bool> isAvailable() async {
    try {
      return await _methods.invokeMethod<bool>('isAvailable') ?? false;
    } on MissingPluginException {
      return false;
    }
  }

  Future<bool> setEnabled(bool enabled) async {
    try {
      return await _methods.invokeMethod<bool>(
            'setEnabled',
            {'enabled': enabled},
          ) ??
          false;
    } on MissingPluginException {
      return false;
    }
  }

  Future<bool> respond(int id, String responseHex) async {
    try {
      return await _methods.invokeMethod<bool>(
            'respond',
            {'id': id, 'responseHex': responseHex},
          ) ??
          false;
    } on MissingPluginException {
      return false;
    }
  }
}

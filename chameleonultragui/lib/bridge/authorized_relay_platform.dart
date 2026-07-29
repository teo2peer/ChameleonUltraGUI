import 'package:flutter/services.dart';

enum AuthorizedRelayEventType { apdu, expired, deactivated, invalidated }

class AuthorizedRelayEvent {
  const AuthorizedRelayEvent({
    required this.type,
    required this.armToken,
    this.id,
    this.apdu,
    this.receivedUs,
    this.expiresAtUs,
    this.reason,
  });

  final AuthorizedRelayEventType type;
  final int armToken;
  final int? id;
  final Uint8List? apdu;
  final int? receivedUs;
  final int? expiresAtUs;
  final Object? reason;

  bool isPendingAt(int monotonicUs) {
    final expiry = expiresAtUs;
    return type == AuthorizedRelayEventType.apdu &&
        expiry != null &&
        monotonicUs < expiry;
  }

  factory AuthorizedRelayEvent.fromMap(Map<Object?, Object?> value) {
    final token = _exactInteger(value['armToken']);
    if (token == null || token <= 0) {
      throw const FormatException('Invalid authorized-relay arm token');
    }
    final type = switch (value['type']) {
      'apdu' => AuthorizedRelayEventType.apdu,
      'expired' => AuthorizedRelayEventType.expired,
      'deactivated' => AuthorizedRelayEventType.deactivated,
      'invalidated' => AuthorizedRelayEventType.invalidated,
      _ => throw const FormatException('Unknown authorized-relay event'),
    };
    final id = _exactInteger(value['id']);
    final apdu = value['apdu'];
    final receivedUs = _exactInteger(value['receivedUs']);
    final expiresAtUs = _exactInteger(value['expiresAtUs']);
    if (type == AuthorizedRelayEventType.apdu &&
        (id == null ||
            id <= 0 ||
            apdu is! Uint8List ||
            apdu.length < 4 ||
            apdu.length > 512 ||
            receivedUs == null ||
            receivedUs < 0 ||
            expiresAtUs == null ||
            expiresAtUs <= receivedUs ||
            expiresAtUs - receivedUs < 50000 ||
            expiresAtUs - receivedUs > 5000000)) {
      throw const FormatException('Malformed authorized-relay APDU event');
    }
    Object? reason = value['reason'];
    if (type == AuthorizedRelayEventType.deactivated) {
      final code = _exactInteger(reason);
      if (code != 0 && code != 1) {
        throw const FormatException(
          'Malformed authorized-relay deactivation reason',
        );
      }
      reason = code;
    }
    return AuthorizedRelayEvent(
      type: type,
      armToken: token,
      id: id,
      apdu: apdu is Uint8List ? Uint8List.fromList(apdu) : null,
      receivedUs: receivedUs,
      expiresAtUs: expiresAtUs,
      reason: reason,
    );
  }
}

int? _exactInteger(Object? value) {
  if (value is! num || !value.isFinite) return null;
  final integer = value.toInt();
  return value == integer ? integer : null;
}

class AuthorizedRelayReadiness {
  const AuthorizedRelayReadiness({
    required this.hceSupported,
    required this.nfcEnabled,
    required this.deviceLocked,
    required this.isDefaultPaymentService,
    required this.registeredAids,
  });

  final bool hceSupported;
  final bool nfcEnabled;
  final bool deviceLocked;
  final bool isDefaultPaymentService;
  final List<String> registeredAids;

  bool get platformReady => hceSupported && nfcEnabled && !deviceLocked;

  factory AuthorizedRelayReadiness.fromMap(Map<Object?, Object?> value) {
    final aids = value['registeredAids'];
    return AuthorizedRelayReadiness(
      hceSupported: value['hceSupported'] == true,
      nfcEnabled: value['nfcEnabled'] == true,
      deviceLocked: value['deviceLocked'] != false,
      isDefaultPaymentService: value['isDefaultPaymentService'] == true,
      registeredAids: aids is List
          ? aids.whereType<String>().map((aid) => aid.toUpperCase()).toList()
          : const [],
    );
  }
}

class AuthorizedRelayArmToken {
  const AuthorizedRelayArmToken({
    required this.armToken,
    required this.nativeMonotonicUs,
  });

  final int armToken;
  final int nativeMonotonicUs;

  factory AuthorizedRelayArmToken.fromMap(Map<Object?, Object?> value) {
    final armToken = _exactInteger(value['armToken']);
    final monotonicUs = _exactInteger(value['monotonicUs']);
    if (armToken == null ||
        armToken <= 0 ||
        monotonicUs == null ||
        monotonicUs < 0) {
      throw const FormatException('Invalid authorized-relay arm allocation');
    }
    return AuthorizedRelayArmToken(
      armToken: armToken,
      nativeMonotonicUs: monotonicUs,
    );
  }
}

class AuthorizedRelayPlatform {
  static const _methods = MethodChannel(
    'io.chameleon.ultra/authorized_relay_methods',
  );
  static const _events = EventChannel(
    'io.chameleon.ultra/authorized_relay_events',
  );
  static final Stream<AuthorizedRelayEvent> _eventStream = _events
      .receiveBroadcastStream()
      .where((event) => event is Map)
      .map(
        (event) => AuthorizedRelayEvent.fromMap(
          Map<Object?, Object?>.from(event as Map),
        ),
      );

  Future<AuthorizedRelayArmToken> allocateArmToken() async {
    final result = await _methods.invokeMapMethod<Object?, Object?>(
      'allocateArmToken',
    );
    if (result == null) {
      throw const FormatException('Missing authorized-relay arm allocation');
    }
    return AuthorizedRelayArmToken.fromMap(result);
  }

  // All routes share one native EventChannel subscription. Cancelling an old
  // route therefore cannot tear down a replacement route's event sink.
  Stream<AuthorizedRelayEvent> get events => _eventStream;

  Future<AuthorizedRelayReadiness> getReadiness() async {
    try {
      final result = await _methods.invokeMapMethod<Object?, Object?>(
        'getReadiness',
      );
      if (result == null) {
        throw const FormatException('Missing authorized-relay readiness');
      }
      return AuthorizedRelayReadiness.fromMap(result);
    } on MissingPluginException {
      return const AuthorizedRelayReadiness(
        hceSupported: false,
        nfcEnabled: false,
        deviceLocked: true,
        isDefaultPaymentService: false,
        registeredAids: [],
      );
    }
  }

  Future<void> registerAids(Iterable<String> aids) async {
    final normalized = aids.map((aid) => aid.toUpperCase()).toSet().toList();
    final result = await _methods.invokeMethod<bool>('registerAids', {
      'aids': normalized,
    });
    if (result != true) {
      throw PlatformException(
        code: 'AID_REGISTRATION_FAILED',
        message: 'Android did not register the payment AIDs',
      );
    }
  }

  Future<void> authorizeAndEnable(
    int armToken, {
    required Iterable<String> aids,
    int deadlineMs = 1000,
  }) async {
    if (armToken <= 0) {
      throw ArgumentError.value(armToken, 'armToken', 'must be positive');
    }
    if (deadlineMs < 50 || deadlineMs > 5000) {
      throw RangeError.range(deadlineMs, 50, 5000, 'deadlineMs');
    }
    final normalizedAids = aids
        .map((aid) => aid.toUpperCase())
        .toSet()
        .toList();
    if (normalizedAids.isEmpty) {
      throw ArgumentError.value(aids, 'aids', 'must not be empty');
    }
    final result = await _methods.invokeMethod<bool>('authorizeAndEnable', {
      'armToken': armToken,
      'aids': normalizedAids,
      'deadlineMs': deadlineMs,
    });
    if (result != true) {
      throw PlatformException(
        code: 'HCE_STATE_FAILED',
        message: 'Android rejected the atomic relay arm',
      );
    }
  }

  Future<void> setEnabled(bool enabled, {int? armToken}) async {
    if (enabled) {
      throw ArgumentError.value(
        enabled,
        'enabled',
        'use authorizeAndEnable to arm HCE atomically',
      );
    }
    final result = await _methods.invokeMethod<bool>('setEnabled', {
      'enabled': enabled,
      'armToken': armToken,
    });
    if (result != true) {
      throw PlatformException(
        code: 'HCE_STATE_FAILED',
        message: 'Android did not apply the requested relay state',
      );
    }
  }

  Future<bool> respond(int armToken, int id, Uint8List response) async {
    if (armToken <= 0) {
      throw ArgumentError.value(armToken, 'armToken', 'must be positive');
    }
    if (id <= 0) {
      throw ArgumentError.value(id, 'id', 'must be positive');
    }
    if (response.length < 2 || response.length > 512) {
      throw RangeError.range(response.length, 2, 512, 'response length');
    }
    return await _methods.invokeMethod<bool>('respond', {
          'armToken': armToken,
          'id': id,
          'response': response,
        }) ??
        false;
  }

  Future<bool> isPending(int armToken, int id) async {
    if (armToken <= 0) {
      throw ArgumentError.value(armToken, 'armToken', 'must be positive');
    }
    if (id <= 0) {
      throw ArgumentError.value(id, 'id', 'must be positive');
    }
    return await _methods.invokeMethod<bool>('isPending', {
          'armToken': armToken,
          'id': id,
        }) ??
        false;
  }

  Future<void> openPaymentSettings() async {
    final result =
        await _methods.invokeMethod<bool>('openPaymentSettings') ?? false;
    if (!result) {
      throw PlatformException(
        code: 'SETTINGS_UNAVAILABLE',
        message: 'Android payment settings are unavailable',
      );
    }
  }
}

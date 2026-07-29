import 'dart:async';
import 'dart:typed_data';

import 'package:chameleonultragui/bridge/chameleon.dart';
import 'package:chameleonultragui/helpers/definitions.dart';
import 'package:chameleonultragui/helpers/general.dart';

const String authorizedRelayPpseAidHex = '325041592E5359532E4444463031';
const String authorizedRelaySelectPpseHex =
    '00A404000E325041592E5359532E444446303100';
const Duration authorizedRelayCardPollInterval = Duration(milliseconds: 500);
const int authorizedRelayDeactivationLinkLoss = 0;
const int authorizedRelayDeactivationDeselected = 1;
const int authorizedRelayMaxFciLength = 1024;
const int authorizedRelayMaxPdolDefinitionLength = 252;

class AuthorizedRelayPollDelay {
  Completer<void>? _waiter;
  bool _wakePending = false;

  Future<void> wait(Duration duration) async {
    if (_wakePending) {
      _wakePending = false;
      return;
    }
    if (_waiter != null) {
      throw StateError('An authorized-relay poll delay is already active');
    }
    final waiter = Completer<void>();
    final timer = Timer(duration, waiter.complete);
    _waiter = waiter;
    try {
      await waiter.future;
    } finally {
      timer.cancel();
      if (identical(_waiter, waiter)) _waiter = null;
    }
  }

  void wake() {
    final waiter = _waiter;
    if (waiter == null) {
      _wakePending = true;
    } else if (!waiter.isCompleted) {
      waiter.complete();
    }
  }

  void reset() {
    _wakePending = false;
    final waiter = _waiter;
    if (waiter != null && !waiter.isCompleted) waiter.complete();
  }
}

enum AuthorizedRelayBackendMode { transparent, appleTransit }

/// Lets the page map policy modes to transport-specific commands later.
class AuthorizedRelayBackendModeMapping<T> {
  const AuthorizedRelayBackendModeMapping({
    required this.transparent,
    required this.appleTransit,
  });

  final T transparent;
  final T appleTransit;

  T resolve(AuthorizedRelayBackendMode mode) => switch (mode) {
    AuthorizedRelayBackendMode.transparent => transparent,
    AuthorizedRelayBackendMode.appleTransit => appleTransit,
  };
}

/// One exact backend response obtained while establishing the live session.
///
/// The first terminal APDU consumes the entry even when it does not match, so
/// a response can never be reused after backend application state advances.
class AuthorizedRelayPrefetchedResponse {
  AuthorizedRelayPrefetchedResponse({
    required Uint8List command,
    required Uint8List response,
  }) : _command = Uint8List.fromList(command),
       _response = Uint8List.fromList(response) {
    if (command.isEmpty || command.length > 512) {
      throw RangeError.range(command.length, 1, 512, 'command length');
    }
    if (response.length < 2 || response.length > 512) {
      throw RangeError.range(response.length, 2, 512, 'response length');
    }
  }

  final Uint8List _command;
  Uint8List? _response;

  bool get available => _response != null;

  Uint8List? takeFor(Uint8List command) {
    final response = _response;
    _response = null;
    if (response == null || !_sameBytes(_command, command)) return null;
    return Uint8List.fromList(response);
  }

  static bool _sameBytes(Uint8List left, Uint8List right) {
    if (left.length != right.length) return false;
    for (var index = 0; index < left.length; index++) {
      if (left[index] != right[index]) return false;
    }
    return true;
  }
}

enum AuthorizedRelayPolicyFailureReason {
  malformedSelect,
  selectResponseNotSuccessful,
  fciTooLarge,
  malformedFci,
  missingFciAid,
  duplicateFciAid,
  fciAidMismatch,
  missingPdol,
  duplicatePdol,
  pdolTooLarge,
  malformedPdol,
  duplicateRelevantPdolTag,
  missingTtq,
  wrongTtqLength,
  wrongTerminalTypeLength,
  wrongTerminalCapabilitiesLength,
  stalePdol,
  malformedGpo,
  extendedGpo,
  gpoPdolLengthMismatch,
}

class AuthorizedRelayPolicyFailure {
  const AuthorizedRelayPolicyFailure(this.reason);

  final AuthorizedRelayPolicyFailureReason reason;

  String get message => switch (reason) {
    AuthorizedRelayPolicyFailureReason.malformedSelect =>
      'Malformed SELECT AID command',
    AuthorizedRelayPolicyFailureReason.selectResponseNotSuccessful =>
      'SELECT AID did not return exact success',
    AuthorizedRelayPolicyFailureReason.fciTooLarge =>
      'SELECT AID FCI exceeds the policy limit',
    AuthorizedRelayPolicyFailureReason.malformedFci =>
      'SELECT AID FCI is malformed',
    AuthorizedRelayPolicyFailureReason.missingFciAid =>
      'SELECT AID FCI has no primitive DF name',
    AuthorizedRelayPolicyFailureReason.duplicateFciAid =>
      'SELECT AID FCI has duplicate primitive DF names',
    AuthorizedRelayPolicyFailureReason.fciAidMismatch =>
      'SELECT AID FCI DF name does not match the selected AID',
    AuthorizedRelayPolicyFailureReason.missingPdol =>
      'SELECT AID FCI has no PDOL',
    AuthorizedRelayPolicyFailureReason.duplicatePdol =>
      'SELECT AID FCI has duplicate PDOL definitions',
    AuthorizedRelayPolicyFailureReason.pdolTooLarge =>
      'PDOL exceeds the policy limit',
    AuthorizedRelayPolicyFailureReason.malformedPdol =>
      'PDOL definition is malformed',
    AuthorizedRelayPolicyFailureReason.duplicateRelevantPdolTag =>
      'PDOL repeats an Apple Transit field',
    AuthorizedRelayPolicyFailureReason.missingTtq =>
      'PDOL does not request TTQ',
    AuthorizedRelayPolicyFailureReason.wrongTtqLength =>
      'PDOL TTQ length is not four bytes',
    AuthorizedRelayPolicyFailureReason.wrongTerminalTypeLength =>
      'PDOL terminal type length is not one byte',
    AuthorizedRelayPolicyFailureReason.wrongTerminalCapabilitiesLength =>
      'PDOL terminal capabilities length is not three bytes',
    AuthorizedRelayPolicyFailureReason.stalePdol =>
      'No current successful SELECT AID PDOL is available',
    AuthorizedRelayPolicyFailureReason.malformedGpo =>
      'GPO is not a standard short command with one tag 83',
    AuthorizedRelayPolicyFailureReason.extendedGpo =>
      'Extended-length GPO is not supported',
    AuthorizedRelayPolicyFailureReason.gpoPdolLengthMismatch =>
      'GPO tag 83 length does not match the selected PDOL',
  };

  Map<String, String> toJson() => {'reason': reason.name, 'message': message};

  @override
  String toString() => message;
}

enum AuthorizedRelayApduDisposition { passThrough, rewritten, rejected }

class AuthorizedRelayApduDecision {
  AuthorizedRelayApduDecision._({
    required this.disposition,
    Uint8List? apdu,
    this.failure,
    this.evidence,
  }) : apdu = apdu == null ? null : Uint8List.fromList(apdu);

  final AuthorizedRelayApduDisposition disposition;
  final Uint8List? apdu;
  final AuthorizedRelayPolicyFailure? failure;
  final AuthorizedRelayGpoRewriteEvidence? evidence;

  bool get shouldForward => apdu != null;

  factory AuthorizedRelayApduDecision.passThrough(Uint8List apdu) =>
      AuthorizedRelayApduDecision._(
        disposition: AuthorizedRelayApduDisposition.passThrough,
        apdu: apdu,
      );

  factory AuthorizedRelayApduDecision.rewritten(
    Uint8List apdu,
    AuthorizedRelayGpoRewriteEvidence evidence,
  ) => AuthorizedRelayApduDecision._(
    disposition: AuthorizedRelayApduDisposition.rewritten,
    apdu: apdu,
    evidence: evidence,
  );

  factory AuthorizedRelayApduDecision.rejected(
    AuthorizedRelayPolicyFailureReason reason,
  ) => AuthorizedRelayApduDecision._(
    disposition: AuthorizedRelayApduDisposition.rejected,
    failure: AuthorizedRelayPolicyFailure(reason),
  );
}

enum AuthorizedRelayBackendObservationDisposition {
  ignored,
  accepted,
  rejected,
}

class AuthorizedRelayBackendObservation {
  const AuthorizedRelayBackendObservation._({
    required this.disposition,
    this.failure,
  });

  final AuthorizedRelayBackendObservationDisposition disposition;
  final AuthorizedRelayPolicyFailure? failure;

  static const ignored = AuthorizedRelayBackendObservation._(
    disposition: AuthorizedRelayBackendObservationDisposition.ignored,
  );
  static const accepted = AuthorizedRelayBackendObservation._(
    disposition: AuthorizedRelayBackendObservationDisposition.accepted,
  );

  factory AuthorizedRelayBackendObservation.rejected(
    AuthorizedRelayPolicyFailureReason reason,
  ) => AuthorizedRelayBackendObservation._(
    disposition: AuthorizedRelayBackendObservationDisposition.rejected,
    failure: AuthorizedRelayPolicyFailure(reason),
  );
}

enum AuthorizedRelayApprovedPdolField {
  ttq('9F66'),
  terminalType('9F35'),
  terminalCapabilities('9F33');

  const AuthorizedRelayApprovedPdolField(this.tagHex);

  final String tagHex;
}

class AuthorizedRelayApprovedFieldRewrite {
  const AuthorizedRelayApprovedFieldRewrite({
    required this.field,
    required this.beforeHex,
    required this.afterHex,
  });

  final AuthorizedRelayApprovedPdolField field;
  final String beforeHex;
  final String afterHex;

  Map<String, String> toJson() => {
    'tag': field.tagHex,
    'before': beforeHex,
    'after': afterHex,
  };
}

class AuthorizedRelayGpoRewriteEvidence {
  AuthorizedRelayGpoRewriteEvidence({
    required this.aidHex,
    required this.pdolDefinitionHex,
    required this.pdolDefinitionLength,
    required this.pdolValueLength,
    required this.apduLength,
    required this.leLength,
    required List<AuthorizedRelayApprovedFieldRewrite> fields,
  }) : fields = List.unmodifiable(fields);

  final String aidHex;
  final String pdolDefinitionHex;
  final int pdolDefinitionLength;
  final int pdolValueLength;
  final int apduLength;
  final int leLength;
  final List<AuthorizedRelayApprovedFieldRewrite> fields;

  Map<String, Object> toJson() => {
    'aid': aidHex,
    'pdolDefinition': pdolDefinitionHex,
    'pdolDefinitionLength': pdolDefinitionLength,
    'pdolValueLength': pdolValueLength,
    'apduLength': apduLength,
    'leLength': leLength,
    'fields': fields.map((field) => field.toJson()).toList(growable: false),
  };
}

/// Session-local APDU policy. Instantiate one per backend ISO-DEP session or
/// call [clear] whenever that session ends.
class AuthorizedRelaySessionPolicy {
  AuthorizedRelaySessionPolicy({
    this.mode = AuthorizedRelayBackendMode.transparent,
  });

  final AuthorizedRelayBackendMode mode;
  Uint8List? _pendingAid;
  _AuthorizedRelayPdolLayout? _activePdol;

  bool get hasActivePdol => _activePdol != null;

  void clear() {
    _pendingAid = null;
    _activePdol = null;
  }

  /// Must run before the APDU is sent to the backend.
  AuthorizedRelayApduDecision prepareTerminalApdu(Uint8List apdu) {
    if (mode == AuthorizedRelayBackendMode.transparent) {
      return AuthorizedRelayApduDecision.passThrough(apdu);
    }
    if (_isAuthorizedRelaySelect(apdu)) {
      clear();
      final aid = _authorizedRelaySelectAid(apdu);
      if (aid != null && !_isAuthorizedRelayPpseAid(aid)) _pendingAid = aid;
      return AuthorizedRelayApduDecision.passThrough(apdu);
    }
    if (!_isAuthorizedRelayGpo(apdu)) {
      return AuthorizedRelayApduDecision.passThrough(apdu);
    }
    return _rewriteGpo(apdu);
  }

  /// Observes the exact backend response after a SELECT has been forwarded.
  AuthorizedRelayBackendObservation observeBackendResponse({
    required Uint8List terminalApdu,
    required Uint8List backendResponse,
  }) {
    if (mode == AuthorizedRelayBackendMode.transparent ||
        !_isAuthorizedRelaySelect(terminalApdu)) {
      return AuthorizedRelayBackendObservation.ignored;
    }

    final aid = _authorizedRelaySelectAid(terminalApdu);
    if (aid == null) {
      return AuthorizedRelayBackendObservation.rejected(
        AuthorizedRelayPolicyFailureReason.malformedSelect,
      );
    }
    if (_isAuthorizedRelayPpseAid(aid)) {
      return AuthorizedRelayBackendObservation.ignored;
    }
    final pendingAid = _pendingAid;
    if (pendingAid == null || !_authorizedRelayBytesMatch(pendingAid, aid)) {
      return AuthorizedRelayBackendObservation.rejected(
        AuthorizedRelayPolicyFailureReason.stalePdol,
      );
    }

    _pendingAid = null;
    _activePdol = null;
    final parsed = _parseAuthorizedRelayFci(aid, backendResponse);
    if (parsed.failure != null) {
      return AuthorizedRelayBackendObservation.rejected(parsed.failure!);
    }
    _activePdol = parsed.layout;
    return AuthorizedRelayBackendObservation.accepted;
  }

  AuthorizedRelayApduDecision _rewriteGpo(Uint8List apdu) {
    final parsedGpo = _parseAuthorizedRelayGpo(apdu);
    if (parsedGpo.failure != null) {
      return AuthorizedRelayApduDecision.rejected(parsedGpo.failure!);
    }
    final gpo = parsedGpo.layout!;
    final pdol = _activePdol;
    if (pdol == null) {
      return AuthorizedRelayApduDecision.rejected(
        AuthorizedRelayPolicyFailureReason.stalePdol,
      );
    }
    if (gpo.valueLength != pdol.valueLength) {
      return AuthorizedRelayApduDecision.rejected(
        AuthorizedRelayPolicyFailureReason.gpoPdolLengthMismatch,
      );
    }

    final rewritten = Uint8List.fromList(apdu);
    final evidenceFields = <AuthorizedRelayApprovedFieldRewrite>[];
    for (final field in AuthorizedRelayApprovedPdolField.values) {
      final location = pdol.fields[field];
      if (location == null) continue;
      final replacement = _authorizedRelayAppleValue(field);
      final start = gpo.valueOffset + location.offset;
      final before = Uint8List.fromList(
        rewritten.sublist(start, start + location.length),
      );
      rewritten.setRange(start, start + location.length, replacement);
      evidenceFields.add(
        AuthorizedRelayApprovedFieldRewrite(
          field: field,
          beforeHex: _authorizedRelayHex(before),
          afterHex: _authorizedRelayHex(replacement),
        ),
      );
    }

    return AuthorizedRelayApduDecision.rewritten(
      rewritten,
      AuthorizedRelayGpoRewriteEvidence(
        aidHex: _authorizedRelayHex(pdol.aid),
        pdolDefinitionHex: _authorizedRelayHex(pdol.definition),
        pdolDefinitionLength: pdol.definition.length,
        pdolValueLength: pdol.valueLength,
        apduLength: apdu.length,
        leLength: gpo.leLength,
        fields: evidenceFields,
      ),
    );
  }
}

class _AuthorizedRelayPdolFieldLocation {
  const _AuthorizedRelayPdolFieldLocation(this.offset, this.length);

  final int offset;
  final int length;
}

class _AuthorizedRelayPdolLayout {
  _AuthorizedRelayPdolLayout({
    required Uint8List aid,
    required Uint8List definition,
    required this.valueLength,
    required Map<
      AuthorizedRelayApprovedPdolField,
      _AuthorizedRelayPdolFieldLocation
    >
    fields,
  }) : aid = Uint8List.fromList(aid),
       definition = Uint8List.fromList(definition),
       fields = Map.unmodifiable(fields);

  final Uint8List aid;
  final Uint8List definition;
  final int valueLength;
  final Map<AuthorizedRelayApprovedPdolField, _AuthorizedRelayPdolFieldLocation>
  fields;
}

class _AuthorizedRelayPdolParseResult {
  const _AuthorizedRelayPdolParseResult._({this.layout, this.failure});

  final _AuthorizedRelayPdolLayout? layout;
  final AuthorizedRelayPolicyFailureReason? failure;

  factory _AuthorizedRelayPdolParseResult.success(
    _AuthorizedRelayPdolLayout layout,
  ) => _AuthorizedRelayPdolParseResult._(layout: layout);

  factory _AuthorizedRelayPdolParseResult.failure(
    AuthorizedRelayPolicyFailureReason failure,
  ) => _AuthorizedRelayPdolParseResult._(failure: failure);
}

class _AuthorizedRelayGpoLayout {
  const _AuthorizedRelayGpoLayout({
    required this.valueOffset,
    required this.valueLength,
    required this.leLength,
  });

  final int valueOffset;
  final int valueLength;
  final int leLength;
}

class _AuthorizedRelayGpoParseResult {
  const _AuthorizedRelayGpoParseResult._({this.layout, this.failure});

  final _AuthorizedRelayGpoLayout? layout;
  final AuthorizedRelayPolicyFailureReason? failure;

  factory _AuthorizedRelayGpoParseResult.success(
    _AuthorizedRelayGpoLayout layout,
  ) => _AuthorizedRelayGpoParseResult._(layout: layout);

  factory _AuthorizedRelayGpoParseResult.failure(
    AuthorizedRelayPolicyFailureReason failure,
  ) => _AuthorizedRelayGpoParseResult._(failure: failure);
}

bool _isAuthorizedRelaySelect(Uint8List apdu) =>
    apdu.length >= 2 && apdu[1] == 0xA4;

bool _isAuthorizedRelayGpo(Uint8List apdu) =>
    apdu.length >= 2 && apdu[1] == 0xA8;

Uint8List? _authorizedRelaySelectAid(Uint8List apdu) {
  if (apdu.length < 5 ||
      apdu[0] != 0x00 ||
      apdu[1] != 0xA4 ||
      apdu[2] != 0x04 ||
      apdu[3] != 0x00) {
    return null;
  }
  final length = apdu[4];
  if (length < 5 || length > 16) return null;
  final withoutLe = 5 + length;
  if (apdu.length != withoutLe && apdu.length != withoutLe + 1) return null;
  return Uint8List.fromList(apdu.sublist(5, withoutLe));
}

bool _isAuthorizedRelayPpseAid(Uint8List aid) =>
    _authorizedRelayHex(aid) == authorizedRelayPpseAidHex;

_AuthorizedRelayPdolParseResult _parseAuthorizedRelayFci(
  Uint8List selectedAid,
  Uint8List response,
) {
  if (response.length < 2 ||
      response[response.length - 2] != 0x90 ||
      response.last != 0x00) {
    return _AuthorizedRelayPdolParseResult.failure(
      AuthorizedRelayPolicyFailureReason.selectResponseNotSuccessful,
    );
  }
  final fciLength = response.length - 2;
  if (fciLength > authorizedRelayMaxFciLength) {
    return _AuthorizedRelayPdolParseResult.failure(
      AuthorizedRelayPolicyFailureReason.fciTooLarge,
    );
  }

  try {
    final parser = _AuthorizedRelayBerParser(
      Uint8List.fromList(response.sublist(0, fciLength)),
    );
    final roots = parser.parse();
    if (roots.length != 1 ||
        roots.single.tagHex != '6F' ||
        !roots.single.constructed) {
      return _AuthorizedRelayPdolParseResult.failure(
        AuthorizedRelayPolicyFailureReason.malformedFci,
      );
    }

    final root = roots.single;
    final aidNodes = root.children
        .where((node) => !node.constructed && node.tagHex == '84')
        .toList(growable: false);
    if (aidNodes.isEmpty) {
      return _AuthorizedRelayPdolParseResult.failure(
        AuthorizedRelayPolicyFailureReason.missingFciAid,
      );
    }
    if (aidNodes.length != 1) {
      return _AuthorizedRelayPdolParseResult.failure(
        AuthorizedRelayPolicyFailureReason.duplicateFciAid,
      );
    }
    if (!_authorizedRelayBytesMatch(aidNodes.single.value, selectedAid)) {
      return _AuthorizedRelayPdolParseResult.failure(
        AuthorizedRelayPolicyFailureReason.fciAidMismatch,
      );
    }

    final proprietaryNodes = root.children
        .where((node) => node.constructed && node.tagHex == 'A5')
        .toList(growable: false);
    if (proprietaryNodes.isEmpty) {
      return _AuthorizedRelayPdolParseResult.failure(
        AuthorizedRelayPolicyFailureReason.missingPdol,
      );
    }
    if (proprietaryNodes.length != 1) {
      return _AuthorizedRelayPdolParseResult.failure(
        AuthorizedRelayPolicyFailureReason.malformedFci,
      );
    }
    final pdolNodes = proprietaryNodes.single.children
        .where((node) => !node.constructed && node.tagHex == '9F38')
        .toList(growable: false);
    if (pdolNodes.isEmpty) {
      return _AuthorizedRelayPdolParseResult.failure(
        AuthorizedRelayPolicyFailureReason.missingPdol,
      );
    }
    if (pdolNodes.length != 1) {
      return _AuthorizedRelayPdolParseResult.failure(
        AuthorizedRelayPolicyFailureReason.duplicatePdol,
      );
    }
    return _parseAuthorizedRelayPdol(selectedAid, pdolNodes.single.value);
  } on _AuthorizedRelayBerParseException {
    return _AuthorizedRelayPdolParseResult.failure(
      AuthorizedRelayPolicyFailureReason.malformedFci,
    );
  }
}

_AuthorizedRelayPdolParseResult _parseAuthorizedRelayPdol(
  Uint8List selectedAid,
  Uint8List definition,
) {
  if (definition.length > authorizedRelayMaxPdolDefinitionLength) {
    return _AuthorizedRelayPdolParseResult.failure(
      AuthorizedRelayPolicyFailureReason.pdolTooLarge,
    );
  }

  final fields =
      <AuthorizedRelayApprovedPdolField, _AuthorizedRelayPdolFieldLocation>{};
  var offset = 0;
  var valueLength = 0;
  try {
    while (offset < definition.length) {
      final tagStart = offset;
      final tagEnd = _authorizedRelayReadTagEnd(
        definition,
        tagStart,
        definition.length,
      );
      if (tagEnd >= definition.length) {
        throw const _AuthorizedRelayBerParseException();
      }
      final length = definition[tagEnd];
      if (length == 0) {
        throw const _AuthorizedRelayBerParseException();
      }
      final field = _authorizedRelayApprovedField(definition, tagStart, tagEnd);
      if (field != null) {
        if (fields.containsKey(field)) {
          return _AuthorizedRelayPdolParseResult.failure(
            AuthorizedRelayPolicyFailureReason.duplicateRelevantPdolTag,
          );
        }
        fields[field] = _AuthorizedRelayPdolFieldLocation(valueLength, length);
      }
      valueLength += length;
      if (valueLength > authorizedRelayMaxPdolDefinitionLength) {
        return _AuthorizedRelayPdolParseResult.failure(
          AuthorizedRelayPolicyFailureReason.pdolTooLarge,
        );
      }
      offset = tagEnd + 1;
    }
  } on _AuthorizedRelayBerParseException {
    return _AuthorizedRelayPdolParseResult.failure(
      AuthorizedRelayPolicyFailureReason.malformedPdol,
    );
  }

  final ttq = fields[AuthorizedRelayApprovedPdolField.ttq];
  if (ttq == null) {
    return _AuthorizedRelayPdolParseResult.failure(
      AuthorizedRelayPolicyFailureReason.missingTtq,
    );
  }
  if (ttq.length != 4) {
    return _AuthorizedRelayPdolParseResult.failure(
      AuthorizedRelayPolicyFailureReason.wrongTtqLength,
    );
  }
  final terminalType = fields[AuthorizedRelayApprovedPdolField.terminalType];
  if (terminalType != null && terminalType.length != 1) {
    return _AuthorizedRelayPdolParseResult.failure(
      AuthorizedRelayPolicyFailureReason.wrongTerminalTypeLength,
    );
  }
  final capabilities =
      fields[AuthorizedRelayApprovedPdolField.terminalCapabilities];
  if (capabilities != null && capabilities.length != 3) {
    return _AuthorizedRelayPdolParseResult.failure(
      AuthorizedRelayPolicyFailureReason.wrongTerminalCapabilitiesLength,
    );
  }

  return _AuthorizedRelayPdolParseResult.success(
    _AuthorizedRelayPdolLayout(
      aid: selectedAid,
      definition: definition,
      valueLength: valueLength,
      fields: fields,
    ),
  );
}

_AuthorizedRelayGpoParseResult _parseAuthorizedRelayGpo(Uint8List apdu) {
  if (apdu.length < 5 ||
      apdu[0] != 0x80 ||
      apdu[1] != 0xA8 ||
      apdu[2] != 0x00 ||
      apdu[3] != 0x00) {
    return _AuthorizedRelayGpoParseResult.failure(
      AuthorizedRelayPolicyFailureReason.malformedGpo,
    );
  }
  final lc = apdu[4];
  if (lc == 0) {
    return _AuthorizedRelayGpoParseResult.failure(
      apdu.length >= 7
          ? AuthorizedRelayPolicyFailureReason.extendedGpo
          : AuthorizedRelayPolicyFailureReason.malformedGpo,
    );
  }
  final dataEnd = 5 + lc;
  final leLength = apdu.length - dataEnd;
  if (dataEnd > apdu.length || leLength < 0 || leLength > 1) {
    return _AuthorizedRelayGpoParseResult.failure(
      AuthorizedRelayPolicyFailureReason.malformedGpo,
    );
  }
  if (apdu[5] != 0x83 || lc < 2) {
    return _AuthorizedRelayGpoParseResult.failure(
      AuthorizedRelayPolicyFailureReason.malformedGpo,
    );
  }

  var valueOffset = 7;
  var valueLength = apdu[6];
  if ((valueLength & 0x80) != 0) {
    if (valueLength != 0x81 || lc < 3 || apdu[7] < 0x80) {
      return _AuthorizedRelayGpoParseResult.failure(
        AuthorizedRelayPolicyFailureReason.malformedGpo,
      );
    }
    valueLength = apdu[7];
    valueOffset = 8;
  }
  if (valueOffset + valueLength != dataEnd) {
    return _AuthorizedRelayGpoParseResult.failure(
      AuthorizedRelayPolicyFailureReason.malformedGpo,
    );
  }
  return _AuthorizedRelayGpoParseResult.success(
    _AuthorizedRelayGpoLayout(
      valueOffset: valueOffset,
      valueLength: valueLength,
      leLength: leLength,
    ),
  );
}

AuthorizedRelayApprovedPdolField? _authorizedRelayApprovedField(
  Uint8List data,
  int start,
  int end,
) {
  if (end - start != 2 || data[start] != 0x9F) return null;
  return switch (data[start + 1]) {
    0x66 => AuthorizedRelayApprovedPdolField.ttq,
    0x35 => AuthorizedRelayApprovedPdolField.terminalType,
    0x33 => AuthorizedRelayApprovedPdolField.terminalCapabilities,
    _ => null,
  };
}

Uint8List _authorizedRelayAppleValue(AuthorizedRelayApprovedPdolField field) =>
    Uint8List.fromList(switch (field) {
      AuthorizedRelayApprovedPdolField.ttq => const [0x33, 0x80, 0x40, 0x00],
      AuthorizedRelayApprovedPdolField.terminalType => const [0x14],
      AuthorizedRelayApprovedPdolField.terminalCapabilities => const [
        0xE0,
        0x08,
        0x00,
      ],
    });

String _authorizedRelayHex(Uint8List bytes) => bytes
    .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
    .join()
    .toUpperCase();

class _AuthorizedRelayBerNode {
  _AuthorizedRelayBerNode({
    required this.tagHex,
    required this.constructed,
    required Uint8List value,
    required List<_AuthorizedRelayBerNode> children,
  }) : value = Uint8List.fromList(value),
       children = List.unmodifiable(children);

  final String tagHex;
  final bool constructed;
  final Uint8List value;
  final List<_AuthorizedRelayBerNode> children;
}

class _AuthorizedRelayBerParser {
  _AuthorizedRelayBerParser(this.data);

  static const int _maxDepth = 8;
  static const int _maxNodes = 128;

  final Uint8List data;
  final List<_AuthorizedRelayBerNode> nodes = [];

  List<_AuthorizedRelayBerNode> parse() {
    if (data.isEmpty) throw const _AuthorizedRelayBerParseException();
    return _parseRange(0, data.length, 0);
  }

  List<_AuthorizedRelayBerNode> _parseRange(int start, int end, int depth) {
    if (depth > _maxDepth) {
      throw const _AuthorizedRelayBerParseException();
    }
    final rangeNodes = <_AuthorizedRelayBerNode>[];
    var offset = start;
    while (offset < end) {
      final tagStart = offset;
      final tagEnd = _authorizedRelayReadTagEnd(data, tagStart, end);
      final constructed = (data[tagStart] & 0x20) != 0;
      offset = tagEnd;
      if (offset >= end) throw const _AuthorizedRelayBerParseException();

      final firstLength = data[offset++];
      int length;
      if ((firstLength & 0x80) == 0) {
        length = firstLength;
      } else {
        final count = firstLength & 0x7F;
        if (count == 0 || count > 2 || offset + count > end) {
          throw const _AuthorizedRelayBerParseException();
        }
        if (data[offset] == 0) {
          throw const _AuthorizedRelayBerParseException();
        }
        length = 0;
        for (var index = 0; index < count; index++) {
          length = (length << 8) | data[offset++];
        }
        if (length < 0x80) {
          throw const _AuthorizedRelayBerParseException();
        }
      }
      if (length > end - offset) {
        throw const _AuthorizedRelayBerParseException();
      }

      final valueEnd = offset + length;
      final children = constructed && length > 0
          ? _parseRange(offset, valueEnd, depth + 1)
          : const <_AuthorizedRelayBerNode>[];
      final node = _AuthorizedRelayBerNode(
        tagHex: _authorizedRelayHex(
          Uint8List.fromList(data.sublist(tagStart, tagEnd)),
        ),
        constructed: constructed,
        value: Uint8List.fromList(data.sublist(offset, valueEnd)),
        children: children,
      );
      nodes.add(node);
      rangeNodes.add(node);
      if (nodes.length > _maxNodes) {
        throw const _AuthorizedRelayBerParseException();
      }
      offset = valueEnd;
    }
    if (offset != end) throw const _AuthorizedRelayBerParseException();
    return rangeNodes;
  }
}

int _authorizedRelayReadTagEnd(Uint8List data, int start, int end) {
  if (start >= end || data[start] == 0x00 || data[start] == 0xFF) {
    throw const _AuthorizedRelayBerParseException();
  }
  var offset = start + 1;
  if ((data[start] & 0x1F) != 0x1F) return offset;
  if (offset >= end || (data[offset] & 0x7F) == 0) {
    throw const _AuthorizedRelayBerParseException();
  }
  var tagLength = 1;
  while (true) {
    if (offset >= end || ++tagLength > 4) {
      throw const _AuthorizedRelayBerParseException();
    }
    if ((data[offset++] & 0x80) == 0) return offset;
  }
}

class _AuthorizedRelayBerParseException implements Exception {
  const _AuthorizedRelayBerParseException();
}

enum AuthorizedRelayRendezvousPhase {
  waitingForBoth,
  waitingForBackend,
  waitingForTerminal,
  exchanging,
  closed,
}

class AuthorizedRelayTerminalApdu {
  const AuthorizedRelayTerminalApdu({
    required this.armToken,
    required this.id,
    required this.apdu,
    this.receivedUs,
    this.expiresAtUs,
  });

  final int armToken;
  final int id;
  final Uint8List apdu;
  final int? receivedUs;
  final int? expiresAtUs;
}

class AuthorizedRelayExchange<T> {
  const AuthorizedRelayExchange({
    required this.backend,
    required this.terminal,
  });

  final T backend;
  final AuthorizedRelayTerminalApdu terminal;
}

/// Joins one native terminal request to one persistent backend session.
///
/// Transport and timeout ownership stays with the caller. This object only
/// makes the ordering and exactly-once transition explicit and testable.
class AuthorizedRelayRendezvous<T> {
  AuthorizedRelayRendezvous(this.armToken) {
    if (armToken <= 0) {
      throw ArgumentError.value(armToken, 'armToken', 'must be positive');
    }
  }

  final int armToken;
  T? _backend;
  AuthorizedRelayTerminalApdu? _terminal;
  bool _exchanging = false;
  bool _closed = false;

  T? get backend => _backend;
  AuthorizedRelayTerminalApdu? get terminal => _terminal;

  AuthorizedRelayRendezvousPhase get phase {
    if (_closed) return AuthorizedRelayRendezvousPhase.closed;
    if (_exchanging) return AuthorizedRelayRendezvousPhase.exchanging;
    if (_backend == null && _terminal == null) {
      return AuthorizedRelayRendezvousPhase.waitingForBoth;
    }
    if (_backend == null) {
      return AuthorizedRelayRendezvousPhase.waitingForBackend;
    }
    return AuthorizedRelayRendezvousPhase.waitingForTerminal;
  }

  bool acceptBackend(int token, T backend) {
    if (_closed || _exchanging || token != armToken || _backend != null) {
      return false;
    }
    _backend = backend;
    return true;
  }

  bool acceptTerminal(AuthorizedRelayTerminalApdu terminal) {
    if (_closed ||
        _exchanging ||
        _backend == null ||
        terminal.armToken != armToken ||
        _terminal != null) {
      return false;
    }
    _terminal = terminal;
    return true;
  }

  AuthorizedRelayExchange<T>? beginExchange(int token) {
    if (_closed || _exchanging || token != armToken) return null;
    final backend = _backend;
    final terminal = _terminal;
    if (backend == null || terminal == null) return null;
    _exchanging = true;
    return AuthorizedRelayExchange(backend: backend, terminal: terminal);
  }

  bool completeExchange(int token) {
    if (_closed || !_exchanging || token != armToken) return false;
    _terminal = null;
    _exchanging = false;
    return true;
  }

  T? close() {
    if (_closed) return null;
    _closed = true;
    _exchanging = false;
    _terminal = null;
    final backend = _backend;
    _backend = null;
    return backend;
  }
}

/// Identifies the exact live firmware session acquired for HCE.
///
/// Card RF metadata and PPSE data are deliberately absent: those values are
/// diagnostic and are not authorization credentials.
class AuthorizedRelaySessionBinding<C extends Object> {
  const AuthorizedRelaySessionBinding({
    required this.communicator,
    required this.generation,
    required this.mode,
    required this.sessionId,
  }) : assert(generation > 0),
       assert(sessionId > 0);

  final C communicator;
  final int generation;
  final AuthorizedRelayBackendMode mode;
  final int sessionId;

  bool matches({
    required C communicator,
    required int generation,
    required AuthorizedRelayBackendMode mode,
    required int sessionId,
  }) =>
      identical(this.communicator, communicator) &&
      this.generation == generation &&
      this.mode == mode &&
      this.sessionId == sessionId;
}

/// A one-shot handle to a live backend. A successful [consume] removes the
/// backend even if arming later fails before the first terminal APDU.
class AuthorizedRelaySessionCapability<B, C extends Object> {
  factory AuthorizedRelaySessionCapability({
    required AuthorizedRelaySessionBinding<C> binding,
    required B backend,
  }) => AuthorizedRelaySessionCapability<B, C>._(binding, backend);

  AuthorizedRelaySessionCapability._(this.binding, this._backend);

  final AuthorizedRelaySessionBinding<C> binding;
  B? _backend;

  bool get available => _backend != null;

  B? consume({
    required C communicator,
    required int generation,
    required AuthorizedRelayBackendMode mode,
    required int sessionId,
  }) {
    if (!binding.matches(
      communicator: communicator,
      generation: generation,
      mode: mode,
      sessionId: sessionId,
    )) {
      return null;
    }
    return invalidate();
  }

  B? invalidate() {
    final backend = _backend;
    _backend = null;
    return backend;
  }
}

class AuthorizedRelayCleanupBarrier {
  AuthorizedRelayCleanupBarrier._(this.predecessor, this._completions);

  final Future<void> predecessor;
  final List<Completer<void>> _completions;

  bool get completed => _completions.every((value) => value.isCompleted);

  void complete() {
    for (final completion in _completions) {
      if (!completion.isCompleted) completion.complete();
    }
  }
}

/// Connection-scoped relay state. It is intentionally independent of widget
/// lifetime so route recreation cannot clear poison or overtake cleanup.
class AuthorizedRelayConnectionCoordinator {
  Future<void> _cleanupTail = Future<void>.value();
  bool _connected = true;
  bool _disconnectObserved = false;
  int _generation = 1;
  String? _poisonReason;

  bool get connected => _connected;
  bool get poisoned => _poisonReason != null;
  int get generation => _generation;
  String? get poisonReason => _poisonReason;

  Future<void> awaitCleanup() => _cleanupTail;

  AuthorizedRelayCleanupBarrier beginCleanup() {
    final predecessor = _cleanupTail;
    final completion = Completer<void>();
    _cleanupTail = predecessor.then((_) => completion.future);
    return AuthorizedRelayCleanupBarrier._(predecessor, [completion]);
  }

  void poison(String reason) {
    _poisonReason = reason;
    _disconnectObserved = !_connected;
  }

  void observeConnected() {
    if (_connected) return;
    _connected = true;
    _generation++;
    if (_disconnectObserved) {
      _poisonReason = null;
      _disconnectObserved = false;
    }
  }

  void observeDisconnected() {
    if (_connected) {
      _connected = false;
      _generation++;
    }
    _disconnectObserved = true;
  }

  void observeReplacement() {
    if (_connected) _generation++;
    _connected = false;
    _disconnectObserved = true;
    _poisonReason = null;
  }
}

/// Weakly keys coordinators by exact communicator while retaining the last
/// observed connection identity across relay page instances.
class AuthorizedRelayConnectionRegistry<C extends Object> {
  final Expando<AuthorizedRelayConnectionCoordinator> _coordinators =
      Expando<AuthorizedRelayConnectionCoordinator>(
        'authorized-relay-connection',
      );
  C? _observedCommunicator;
  bool _observedConnected = false;
  Future<void> _globalCleanupTail = Future<void>.value();

  AuthorizedRelayConnectionCoordinator forCommunicator(C communicator) =>
      _coordinators[communicator] ??= AuthorizedRelayConnectionCoordinator();

  Future<void> awaitCleanup(C communicator) => Future.wait([
    _globalCleanupTail,
    forCommunicator(communicator).awaitCleanup(),
  ]);

  AuthorizedRelayCleanupBarrier beginCleanup(C communicator) {
    final local = forCommunicator(communicator).beginCleanup();
    final globalPredecessor = _globalCleanupTail;
    final globalCompletion = Completer<void>();
    final predecessor = Future.wait([globalPredecessor, local.predecessor]);
    _globalCleanupTail = predecessor.then((_) => globalCompletion.future);
    return AuthorizedRelayCleanupBarrier._(predecessor, [
      ...local._completions,
      globalCompletion,
    ]);
  }

  AuthorizedRelayConnectionCoordinator? observeConnection({
    required bool connected,
    required C? communicator,
  }) {
    final previous = _observedCommunicator;
    if (_observedConnected && previous != null) {
      if (!connected || communicator == null) {
        forCommunicator(previous).observeDisconnected();
      } else if (!identical(previous, communicator)) {
        forCommunicator(previous).observeReplacement();
      }
    }

    _observedConnected = connected && communicator != null;
    _observedCommunicator = _observedConnected ? communicator : null;
    if (!_observedConnected) return null;
    final coordinator = forCommunicator(communicator as C);
    coordinator.observeConnected();
    return coordinator;
  }
}

bool isAuthorizedRelaySessionUncertainError(Object error) {
  if (error is IsoDepReaderSessionStartMetadataException) {
    return !error.cleanupConfirmed;
  }
  if (error is ChameleonResponseTimeoutException ||
      error is ChameleonCommandResponseUncertainException ||
      error is TimeoutException) {
    return true;
  }
  if (error is! FormatException) return false;
  final message = error.message.toString();
  return message.contains('cleanup failed') ||
      message.contains('Missing ISO-DEP session response') ||
      message.contains('Missing ISO-DEP exchange response');
}

String authorizedRelayDeactivationFailure({
  required Object? reason,
  required bool hasForwardedApdu,
}) {
  return switch (reason) {
    authorizedRelayDeactivationLinkLoss =>
      hasForwardedApdu
          ? 'Terminal NFC link was lost after an APDU exchange; the transaction '
                'may be incomplete. Keep the phone on the terminal and retry with '
                'the backend ready first.'
          : 'Terminal NFC link was lost before an APDU completed. Keep the phone '
                'on the terminal, use USB, and have the backend ready before tapping.',
    authorizedRelayDeactivationDeselected =>
      'Terminal deselected CU GUI before any APDU completed. Verify the default '
          'payment service and registered payment AIDs.',
    _ => 'Terminal NFC link deactivated for unknown reason $reason',
  };
}

String authorizedRelayDeactivationNotice({
  required Object? reason,
  required int deliveredApdus,
}) {
  final suffix = deliveredApdus == 1 ? 'APDU response' : 'APDU responses';
  return switch (reason) {
    authorizedRelayDeactivationLinkLoss =>
      'NFC exchange ended normally after $deliveredApdus relayed $suffix. Android '
          'labels the reader turning its field off as LINK_LOSS. This is normal '
          'transport closure, not a relay error; the terminal result remains '
          'authoritative for approval or decline.',
    authorizedRelayDeactivationDeselected =>
      'Terminal deselected CU GUI after $deliveredApdus relayed $suffix. The relay '
          'session closed normally; check the terminal for the transaction result.',
    _ => 'Terminal session closed after $deliveredApdus relayed $suffix.',
  };
}

bool _authorizedRelayBytesMatch(Uint8List first, Uint8List second) {
  if (first.length != second.length) return false;
  for (var index = 0; index < first.length; index++) {
    if (first[index] != second[index]) return false;
  }
  return true;
}

bool isAuthorizedRelayCardAbsentError(Object error) =>
    error is ChameleonCommandException &&
    (error.command == ChameleonCommand.hf14a4ReaderSessionStart ||
        error.command ==
            ChameleonCommand.hf14a4ReaderSessionStartAppleTransit) &&
    error.status == 0x01;

Future<T?> waitForAuthorizedRelayBackendCard<T>({
  required Future<T> Function() attempt,
  required bool Function() isCancelled,
  void Function()? onWaiting,
  Future<void> Function(Duration)? delay,
}) async {
  while (!isCancelled()) {
    try {
      return await attempt();
    } catch (error) {
      if (!isAuthorizedRelayCardAbsentError(error)) rethrow;
      if (isCancelled()) return null;
      onWaiting?.call();
      if (delay == null) {
        await Future<void>.delayed(authorizedRelayCardPollInterval);
      } else {
        await delay(authorizedRelayCardPollInterval);
      }
    }
  }
  return null;
}

List<String> extractAuthorizedRelayAids(Uint8List ppseResponse) {
  if (ppseResponse.length < 2 ||
      ppseResponse[ppseResponse.length - 2] != 0x90 ||
      ppseResponse.last != 0x00) {
    throw const FormatException('Backend card did not accept PPSE');
  }
  final body = Uint8List.fromList(
    ppseResponse.sublist(0, ppseResponse.length - 2),
  );
  final aids = <String>{};
  _collectPaymentAids(body, aids, inApplicationTemplate: false, depth: 0);
  if (aids.isEmpty) {
    throw const FormatException('PPSE did not advertise a payment AID');
  }
  return aids.toList(growable: false);
}

void _collectPaymentAids(
  Uint8List data,
  Set<String> aids, {
  required bool inApplicationTemplate,
  required int depth,
}) {
  if (depth > 16) throw const FormatException('PPSE TLV nesting is too deep');
  var offset = 0;
  while (offset < data.length) {
    if (data[offset] == 0x00 || data[offset] == 0xFF) {
      offset++;
      continue;
    }
    final tagStart = offset;
    final first = data[offset++];
    final constructed = (first & 0x20) != 0;
    if ((first & 0x1F) == 0x1F) {
      var tagBytes = 1;
      while (true) {
        if (offset >= data.length || ++tagBytes > 4) {
          throw const FormatException('Malformed PPSE tag');
        }
        if ((data[offset++] & 0x80) == 0) break;
      }
    }
    final tag = bytesToHex(
      Uint8List.fromList(data.sublist(tagStart, offset)),
    ).toUpperCase();
    if (offset >= data.length) {
      throw const FormatException('Missing PPSE TLV length');
    }
    var length = data[offset++];
    if ((length & 0x80) != 0) {
      final count = length & 0x7F;
      if (count == 0 || count > 3 || offset + count > data.length) {
        throw const FormatException('Malformed PPSE TLV length');
      }
      length = 0;
      for (var index = 0; index < count; index++) {
        length = (length << 8) | data[offset++];
      }
    }
    if (length > data.length - offset) {
      throw const FormatException('Truncated PPSE TLV value');
    }
    final value = Uint8List.fromList(data.sublist(offset, offset + length));
    offset += length;
    final insideApplication = inApplicationTemplate || tag == '61';
    if (tag == '4F' && insideApplication) {
      if (value.length < 5 || value.length > 16) {
        throw const FormatException('Invalid payment AID length');
      }
      aids.add(bytesToHex(value).toUpperCase());
    }
    if (constructed) {
      _collectPaymentAids(
        value,
        aids,
        inApplicationTemplate: insideApplication,
        depth: depth + 1,
      );
    }
  }
}

String authorizedRelayApduSummary(Uint8List apdu) {
  if (apdu.length < 4) return 'Malformed APDU (${apdu.length} bytes)';
  final header = bytesToHex(
    Uint8List.fromList(apdu.sublist(0, 4)),
  ).toUpperCase();
  return '$header (${apdu.length} bytes)';
}

String authorizedRelayStatusSummary(Uint8List response) {
  if (response.length < 2) return 'No status word';
  return bytesToHex(
    Uint8List.fromList(response.sublist(response.length - 2)),
  ).toUpperCase();
}

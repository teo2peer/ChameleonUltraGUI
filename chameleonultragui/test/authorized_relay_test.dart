import 'dart:convert';

import 'package:chameleonultragui/bridge/authorized_relay_platform.dart';
import 'package:chameleonultragui/bridge/chameleon.dart';
import 'package:chameleonultragui/helpers/authorized_relay.dart';
import 'package:chameleonultragui/helpers/definitions.dart';
import 'package:chameleonultragui/helpers/general.dart';
import 'package:chameleonultragui/sharedprefsprovider.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('relay routes share one native event stream', () {
    final first = AuthorizedRelayPlatform().events;
    final second = AuthorizedRelayPlatform().events;

    expect(identical(first, second), isTrue);
  });

  TestWidgetsFlutterBinding.ensureInitialized();

  group('authorized relay rendezvous', () {
    test(
      'persists Apple Transit selection until explicitly disabled',
      () async {
        SharedPreferences.setMockInitialValues({});
        final preferences = SharedPreferencesProvider();
        await preferences.load();

        expect(preferences.getAuthorizedRelayAppleTransit(), isFalse);
        preferences.setAuthorizedRelayAppleTransit(true);
        expect(preferences.getAuthorizedRelayAppleTransit(), isTrue);
        preferences.setAuthorizedRelayAppleTransit(false);
        expect(preferences.getAuthorizedRelayAppleTransit(), isFalse);
      },
    );

    test('uses an exact live-session prefetch once', () {
      final command = hexToBytes(authorizedRelaySelectPpseHex);
      final response = hexToBytes('6F038401019000');
      final prefetch = AuthorizedRelayPrefetchedResponse(
        command: command,
        response: response,
      );

      command[0] = 0xFF;
      response[0] = 0xFF;
      expect(prefetch.available, isTrue);
      expect(
        bytesToHex(prefetch.takeFor(hexToBytes(authorizedRelaySelectPpseHex))!),
        '6f038401019000',
      );
      expect(prefetch.available, isFalse);
      expect(
        prefetch.takeFor(hexToBytes(authorizedRelaySelectPpseHex)),
        isNull,
      );
    });

    test('invalidates a live-session prefetch on the first APDU mismatch', () {
      final prefetch = AuthorizedRelayPrefetchedResponse(
        command: hexToBytes(authorizedRelaySelectPpseHex),
        response: hexToBytes('9000'),
      );

      expect(prefetch.takeFor(hexToBytes('00A4040000')), isNull);
      expect(prefetch.available, isFalse);
      expect(
        prefetch.takeFor(hexToBytes(authorizedRelaySelectPpseHex)),
        isNull,
      );
    });

    test('backend-first waits for one terminal APDU and exchanges once', () {
      final rendezvous = AuthorizedRelayRendezvous<String>(7);

      expect(rendezvous.acceptBackend(7, 'session'), isTrue);
      expect(
        rendezvous.phase,
        AuthorizedRelayRendezvousPhase.waitingForTerminal,
      );
      expect(
        rendezvous.acceptTerminal(
          AuthorizedRelayTerminalApdu(
            armToken: 7,
            id: 11,
            apdu: Uint8List.fromList([0x00, 0xA4, 0x04, 0x00]),
          ),
        ),
        isTrue,
      );

      final exchange = rendezvous.beginExchange(7);
      expect(exchange?.backend, 'session');
      expect(exchange?.terminal.id, 11);
      expect(rendezvous.beginExchange(7), isNull);
      expect(rendezvous.completeExchange(7), isTrue);
      expect(
        rendezvous.phase,
        AuthorizedRelayRendezvousPhase.waitingForTerminal,
      );
    });

    test('terminal cannot arrive before the prepared backend is consumed', () {
      final rendezvous = AuthorizedRelayRendezvous<String>(9);
      expect(
        rendezvous.acceptTerminal(
          AuthorizedRelayTerminalApdu(
            armToken: 9,
            id: 13,
            apdu: Uint8List.fromList([0x00, 0xA4, 0x04, 0x00]),
          ),
        ),
        isFalse,
      );
      expect(rendezvous.phase, AuthorizedRelayRendezvousPhase.waitingForBoth);
    });

    test('rejects stale arm tokens without consuming either side', () {
      final rendezvous = AuthorizedRelayRendezvous<String>(21);
      expect(rendezvous.acceptBackend(20, 'stale'), isFalse);
      expect(
        rendezvous.acceptTerminal(
          AuthorizedRelayTerminalApdu(
            armToken: 20,
            id: 1,
            apdu: Uint8List.fromList([0x00, 0xA4, 0x04, 0x00]),
          ),
        ),
        isFalse,
      );
      expect(rendezvous.phase, AuthorizedRelayRendezvousPhase.waitingForBoth);
    });

    test('refuses both sides and exchanges after close', () {
      final rendezvous = AuthorizedRelayRendezvous<String>(22);
      expect(rendezvous.acceptBackend(22, 'session'), isTrue);
      expect(rendezvous.close(), 'session');

      expect(rendezvous.acceptBackend(22, 'new-session'), isFalse);
      expect(
        rendezvous.acceptTerminal(
          AuthorizedRelayTerminalApdu(
            armToken: 22,
            id: 2,
            apdu: Uint8List.fromList([0x00, 0xA4, 0x04, 0x00]),
          ),
        ),
        isFalse,
      );
      expect(rendezvous.beginExchange(22), isNull);
      expect(rendezvous.close(), isNull);
    });

    test('distinct session IDs never match identical static fingerprints', () {
      CardData diagnosticCard() => CardData(
        uid: Uint8List.fromList([1, 2, 3, 4]),
        atqa: Uint8List.fromList([0x04, 0x00]),
        sak: 0x20,
        ats: Uint8List.fromList([0x02, 0x08]),
      );
      final first = IsoDepReaderSessionInfo(
        sessionId: 17,
        card: diagnosticCard(),
      );
      final second = IsoDepReaderSessionInfo(
        sessionId: 18,
        card: diagnosticCard(),
      );
      final communicator = Object();
      final binding = AuthorizedRelaySessionBinding<Object>(
        communicator: communicator,
        generation: 3,
        mode: AuthorizedRelayBackendMode.transparent,
        sessionId: first.sessionId,
      );

      expect(second.card.uid, orderedEquals(first.card.uid));
      expect(second.card.atqa, orderedEquals(first.card.atqa));
      expect(second.card.sak, first.card.sak);
      expect(second.card.ats, orderedEquals(first.card.ats));
      expect(
        binding.matches(
          communicator: communicator,
          generation: 3,
          mode: AuthorizedRelayBackendMode.transparent,
          sessionId: second.sessionId,
        ),
        isFalse,
      );
    });

    test('arming consumes the exact capability before any APDU', () {
      final communicator = Object();
      final capability = AuthorizedRelaySessionCapability<String, Object>(
        binding: AuthorizedRelaySessionBinding(
          communicator: communicator,
          generation: 4,
          mode: AuthorizedRelayBackendMode.transparent,
          sessionId: 19,
        ),
        backend: 'live-session',
      );

      expect(
        capability.consume(
          communicator: communicator,
          generation: 4,
          mode: AuthorizedRelayBackendMode.transparent,
          sessionId: 19,
        ),
        'live-session',
      );
      expect(capability.available, isFalse);
      expect(
        capability.consume(
          communicator: communicator,
          generation: 4,
          mode: AuthorizedRelayBackendMode.transparent,
          sessionId: 19,
        ),
        isNull,
      );
    });

    test(
      'invalidation removes a capability without replacement or reacquire',
      () {
        final communicator = Object();
        final capability = AuthorizedRelaySessionCapability<String, Object>(
          binding: AuthorizedRelaySessionBinding(
            communicator: communicator,
            generation: 5,
            mode: AuthorizedRelayBackendMode.appleTransit,
            sessionId: 20,
          ),
          backend: 'expiring-session',
        );

        expect(capability.invalidate(), 'expiring-session');
        expect(capability.invalidate(), isNull);
        expect(
          capability.consume(
            communicator: communicator,
            generation: 5,
            mode: AuthorizedRelayBackendMode.appleTransit,
            sessionId: 20,
          ),
          isNull,
        );
      },
    );

    test('stale operation completion cannot consume a current capability', () {
      final communicator = Object();
      final capability = AuthorizedRelaySessionCapability<String, Object>(
        binding: AuthorizedRelaySessionBinding(
          communicator: communicator,
          generation: 8,
          mode: AuthorizedRelayBackendMode.transparent,
          sessionId: 21,
        ),
        backend: 'current-session',
      );

      expect(
        capability.consume(
          communicator: communicator,
          generation: 7,
          mode: AuthorizedRelayBackendMode.transparent,
          sessionId: 21,
        ),
        isNull,
      );
      expect(capability.available, isTrue);
    });

    test('connection registry preserves poison across route recreation', () {
      final first = Object();
      final second = Object();
      final registry = AuthorizedRelayConnectionRegistry<Object>();
      final coordinator = registry.observeConnection(
        connected: true,
        communicator: first,
      )!..poison('uncertain STOP');

      final recreated = registry.observeConnection(
        connected: true,
        communicator: first,
      );
      expect(identical(recreated, coordinator), isTrue);
      expect(recreated!.poisoned, isTrue);

      registry.observeConnection(connected: true, communicator: second);
      expect(coordinator.poisoned, isFalse);
    });

    test('poison clears only after observed disconnect and reconnect', () {
      final communicator = Object();
      final registry = AuthorizedRelayConnectionRegistry<Object>();
      final coordinator = registry.observeConnection(
        connected: true,
        communicator: communicator,
      )!..poison('uncertain exchange');
      final generation = coordinator.generation;

      registry.observeConnection(connected: false, communicator: null);
      expect(coordinator.poisoned, isTrue);
      expect(coordinator.generation, greaterThan(generation));
      coordinator.poison('STOP failed after disconnect');

      registry.observeConnection(connected: true, communicator: communicator);
      expect(coordinator.poisoned, isFalse);
    });

    test('new preparation waits for the connection cleanup barrier', () async {
      final communicator = Object();
      final registry = AuthorizedRelayConnectionRegistry<Object>();
      final coordinator = registry.observeConnection(
        connected: true,
        communicator: communicator,
      )!;
      final cleanup = registry.beginCleanup(communicator);
      final recreated = registry.observeConnection(
        connected: true,
        communicator: communicator,
      )!;
      var released = false;
      final waiting = registry
          .awaitCleanup(communicator)
          .then((_) => released = true);

      await Future<void>.delayed(Duration.zero);
      expect(released, isFalse);
      cleanup.complete();
      await waiting;
      expect(released, isTrue);
      expect(identical(recreated, coordinator), isTrue);
    });

    test(
      'replacement connection also waits for global relay cleanup',
      () async {
        final first = Object();
        final second = Object();
        final registry = AuthorizedRelayConnectionRegistry<Object>();
        registry.observeConnection(connected: true, communicator: first);
        final cleanup = registry.beginCleanup(first);
        registry.observeConnection(connected: true, communicator: second);
        var released = false;
        final waiting = registry
            .awaitCleanup(second)
            .then((_) => released = true);

        await Future<void>.delayed(Duration.zero);
        expect(released, isFalse);
        cleanup.complete();
        await waiting;
        expect(released, isTrue);
      },
    );

    test(
      'disconnect generation invalidates an otherwise identical binding',
      () {
        final communicator = Object();
        final registry = AuthorizedRelayConnectionRegistry<Object>();
        final coordinator = registry.observeConnection(
          connected: true,
          communicator: communicator,
        )!;
        final binding = AuthorizedRelaySessionBinding<Object>(
          communicator: communicator,
          generation: coordinator.generation,
          mode: AuthorizedRelayBackendMode.transparent,
          sessionId: 31,
        );

        registry.observeConnection(connected: false, communicator: null);
        registry.observeConnection(connected: true, communicator: communicator);

        expect(
          binding.matches(
            communicator: communicator,
            generation: coordinator.generation,
            mode: AuthorizedRelayBackendMode.transparent,
            sessionId: 31,
          ),
          isFalse,
        );
      },
    );

    test('parses token-bound native events and rejects missing tokens', () {
      final event = AuthorizedRelayEvent.fromMap({
        'type': 'apdu',
        'armToken': 33,
        'id': 4,
        'apdu': Uint8List.fromList([0x00, 0xA4, 0x04, 0x00]),
        'receivedUs': 1000000,
        'expiresAtUs': 1100000,
      });
      expect(event.armToken, 33);
      expect(event.type, AuthorizedRelayEventType.apdu);
      expect(event.isPendingAt(1099999), isTrue);
      expect(event.isPendingAt(1100000), isFalse);
      expect(
        () => AuthorizedRelayEvent.fromMap({'type': 'expired', 'id': 4}),
        throwsFormatException,
      );
    });

    test('classifies terminal deactivation reason and completion state', () {
      final deselected = AuthorizedRelayEvent.fromMap({
        'type': 'deactivated',
        'armToken': 33,
        'reason': authorizedRelayDeactivationDeselected,
      });
      expect(deselected.reason, authorizedRelayDeactivationDeselected);
      expect(
        authorizedRelayDeactivationFailure(
          reason: authorizedRelayDeactivationLinkLoss,
          hasForwardedApdu: false,
        ),
        contains('before an APDU completed'),
      );
      expect(
        authorizedRelayDeactivationFailure(
          reason: authorizedRelayDeactivationLinkLoss,
          hasForwardedApdu: true,
        ),
        contains('may be incomplete'),
      );
      expect(
        authorizedRelayDeactivationNotice(
          reason: authorizedRelayDeactivationLinkLoss,
          deliveredApdus: 2,
        ),
        allOf(
          contains('2 relayed APDU responses'),
          contains('normal transport closure'),
        ),
      );
      expect(
        () => AuthorizedRelayEvent.fromMap({
          'type': 'deactivated',
          'armToken': 33,
          'reason': 2,
        }),
        throwsFormatException,
      );
    });

    test('rejects malformed native APDU deadline metadata', () {
      Map<String, Object> event(int receivedUs, int expiresAtUs) => {
        'type': 'apdu',
        'armToken': 33,
        'id': 4,
        'apdu': Uint8List.fromList([0x00, 0xA4, 0x04, 0x00]),
        'receivedUs': receivedUs,
        'expiresAtUs': expiresAtUs,
      };

      expect(
        () => AuthorizedRelayEvent.fromMap(event(1000000, 1049999)),
        throwsFormatException,
      );
      expect(
        () => AuthorizedRelayEvent.fromMap(event(1000000, 6000001)),
        throwsFormatException,
      );
      expect(
        () => AuthorizedRelayEvent.fromMap({
          ...event(1000000, 1100000),
          'armToken': 1.5,
        }),
        throwsFormatException,
      );
    });

    test('does not retry an uncertain START', () async {
      var attempts = 0;
      await expectLater(
        waitForAuthorizedRelayBackendCard<int>(
          attempt: () async {
            attempts++;
            throw const ChameleonResponseTimeoutException(
              ChameleonCommand.hf14a4ReaderSessionStart,
              Duration(seconds: 6),
            );
          },
          isCancelled: () => false,
          delay: (_) async {},
        ),
        throwsA(isA<ChameleonResponseTimeoutException>()),
      );
      expect(attempts, 1);
      expect(
        isAuthorizedRelaySessionUncertainError(
          const ChameleonResponseTimeoutException(
            ChameleonCommand.hf14a4ReaderSessionStart,
            Duration(seconds: 6),
          ),
        ),
        isTrue,
      );
      expect(
        isAuthorizedRelaySessionUncertainError(
          const IsoDepReaderSessionStartMetadataException(
            command: ChameleonCommand.hf14a4ReaderSessionStart,
            formatError: FormatException('truncated metadata'),
            sessionId: null,
            cleanupConfirmed: false,
          ),
        ),
        isTrue,
      );
      expect(
        isAuthorizedRelaySessionUncertainError(
          const IsoDepReaderSessionStartMetadataException(
            command: ChameleonCommand.hf14a4ReaderSessionStart,
            formatError: FormatException('truncated metadata'),
            sessionId: 4,
            cleanupConfirmed: true,
          ),
        ),
        isFalse,
      );
    });

    test(
      'retries clean no-card responses from Apple Transit START only',
      () async {
        var attempts = 0;
        final result = await waitForAuthorizedRelayBackendCard<int>(
          attempt: () async {
            attempts++;
            if (attempts == 1) {
              throw const ChameleonCommandException(
                ChameleonCommand.hf14a4ReaderSessionStartAppleTransit,
                0x01,
              );
            }
            return 14;
          },
          isCancelled: () => false,
          delay: (_) async {},
        );

        expect(result, 14);
        expect(attempts, 2);
        expect(
          isAuthorizedRelayCardAbsentError(
            const ChameleonCommandException(
              ChameleonCommand.hf14a4ReaderSessionStartAppleTransit,
              0x02,
            ),
          ),
          isFalse,
        );
      },
    );
  });

  group('authorized Apple Transit GPO policy', () {
    const aidHex = 'A0000000031010';
    final selectAid = hexToBytes('00A4040007${aidHex}00');
    final pdolDefinition = hexToBytes(
      '9F66049F02069F03069F1A0295055F2A029A039C019F37049F35019F3303',
    );
    final successfulFci = hexToBytes(
      '6F2C8407A0000000031010A5219F381E'
      '9F66049F02069F03069F1A0295055F2A029A039C019F37049F35019F3303'
      '9000',
    );
    final suppliedGpo = hexToBytes(
      '80A80000278325'
      '36000000'
      '000000001234'
      '000000000000'
      '0840'
      '0000000000'
      '0840'
      '260714'
      '00'
      'DEADBEEF'
      '22'
      'A0A0A0'
      '00',
    );
    final expectedGpo = hexToBytes(
      '80A80000278325'
      '33804000'
      '000000001234'
      '000000000000'
      '0840'
      '0000000000'
      '0840'
      '260714'
      '00'
      'DEADBEEF'
      '14'
      'E00800'
      '00',
    );

    test('maps modes generically and keeps transparent mode unchanged', () {
      const commands = AuthorizedRelayBackendModeMapping<int>(
        transparent: 6011,
        appleTransit: 6014,
      );
      expect(commands.resolve(AuthorizedRelayBackendMode.transparent), 6011);
      expect(commands.resolve(AuthorizedRelayBackendMode.appleTransit), 6014);

      final policy = AuthorizedRelaySessionPolicy();
      final extendedGpo = hexToBytes('80A8000000000283000000');
      final result = policy.prepareTerminalApdu(extendedGpo);
      expect(result.disposition, AuthorizedRelayApduDisposition.passThrough);
      expect(result.apdu, orderedEquals(extendedGpo));
      expect(result.failure, isNull);
    });

    test('rewrites the supplied FCI/GPO vector in exact PDOL order', () {
      final policy = AuthorizedRelaySessionPolicy(
        mode: AuthorizedRelayBackendMode.appleTransit,
      );

      final select = policy.prepareTerminalApdu(selectAid);
      expect(select.disposition, AuthorizedRelayApduDisposition.passThrough);
      expect(policy.hasActivePdol, isFalse);
      final observation = policy.observeBackendResponse(
        terminalApdu: selectAid,
        backendResponse: successfulFci,
      );
      expect(
        observation.disposition,
        AuthorizedRelayBackendObservationDisposition.accepted,
      );
      expect(policy.hasActivePdol, isTrue);

      final original = Uint8List.fromList(suppliedGpo);
      final result = policy.prepareTerminalApdu(original);
      expect(result.disposition, AuthorizedRelayApduDisposition.rewritten);
      expect(result.apdu, orderedEquals(expectedGpo));
      expect(original, orderedEquals(suppliedGpo));

      final evidence = result.evidence!;
      expect(evidence.aidHex, aidHex);
      expect(
        evidence.pdolDefinitionHex,
        bytesToHex(pdolDefinition).toUpperCase(),
      );
      expect(evidence.pdolDefinitionLength, 30);
      expect(evidence.pdolValueLength, 37);
      expect(evidence.apduLength, suppliedGpo.length);
      expect(evidence.leLength, 1);
      expect(evidence.fields.map((field) => field.toJson()).toList(), [
        {'tag': '9F66', 'before': '36000000', 'after': '33804000'},
        {'tag': '9F35', 'before': '22', 'after': '14'},
        {'tag': '9F33', 'before': 'A0A0A0', 'after': 'E00800'},
      ]);
    });

    test('allows omitted optional fields and preserves nonzero Le', () {
      final definition = hexToBytes('9F66049F02069F3704');
      final policy = _appleTransitPolicy(
        selectAid,
        _fci(aidHex: aidHex, pdolDefinitions: [definition]),
      );
      final gpo = hexToBytes('80A8000010830E01020304000000001234CAFEBABE7F');

      final result = policy.prepareTerminalApdu(gpo);

      expect(
        result.apdu,
        orderedEquals(
          hexToBytes('80A8000010830E33804000000000001234CAFEBABE7F'),
        ),
      );
      expect(result.evidence!.leLength, 1);
      expect(result.evidence!.fields, hasLength(1));
    });

    test('accepts a canonical long tag 83 length in a short APDU', () {
      final definition = hexToBytes('9F6604DF017C');
      final policy = _appleTransitPolicy(
        selectAid,
        _fci(aidHex: aidHex, pdolDefinitions: [definition]),
      );
      final values = Uint8List.fromList([
        1,
        2,
        3,
        4,
        ...List<int>.generate(124, (index) => index),
      ]);
      final gpo = _shortGpo(values, le: 0x5A);

      final result = policy.prepareTerminalApdu(gpo);

      expect(result.disposition, AuthorizedRelayApduDisposition.rewritten);
      expect(result.apdu!.sublist(8, 12), orderedEquals([0x33, 0x80, 0x40, 0]));
      expect(
        result.apdu!.sublist(12, result.apdu!.length),
        orderedEquals(gpo.sublist(12)),
      );
      expect(result.evidence!.leLength, 1);
    });

    test('passes non-GPO commands without consuming selected PDOL', () {
      final policy = _appleTransitPolicy(selectAid, successfulFci);
      final getData = hexToBytes('80CA9F3600');

      final passthrough = policy.prepareTerminalApdu(getData);
      final rewritten = policy.prepareTerminalApdu(suppliedGpo);

      expect(
        passthrough.disposition,
        AuthorizedRelayApduDisposition.passThrough,
      );
      expect(passthrough.apdu, orderedEquals(getData));
      expect(rewritten.disposition, AuthorizedRelayApduDisposition.rewritten);
    });

    test(
      'PPSE SELECT clears application state without reporting FCI failure',
      () {
        final policy = _appleTransitPolicy(selectAid, successfulFci);
        final ppse = hexToBytes(authorizedRelaySelectPpseHex);

        expect(policy.prepareTerminalApdu(ppse).shouldForward, isTrue);
        final observation = policy.observeBackendResponse(
          terminalApdu: ppse,
          backendResponse: hexToBytes(
            '6F17840E325041592E5359532E4444463031A505BF0C029000',
          ),
        );

        expect(
          observation.disposition,
          AuthorizedRelayBackendObservationDisposition.ignored,
        );
        expect(policy.hasActivePdol, isFalse);
        expect(
          policy.prepareTerminalApdu(suppliedGpo).failure?.reason,
          AuthorizedRelayPolicyFailureReason.stalePdol,
        );
      },
    );

    test('clears active state before forwarding every new SELECT', () {
      final policy = _appleTransitPolicy(selectAid, successfulFci);
      final nextSelect = hexToBytes('00A4040007A000000004101000');

      final forwarded = policy.prepareTerminalApdu(nextSelect);
      final gpo = policy.prepareTerminalApdu(suppliedGpo);

      expect(forwarded.disposition, AuthorizedRelayApduDisposition.passThrough);
      expect(policy.hasActivePdol, isFalse);
      expect(gpo.shouldForward, isFalse);
      expect(gpo.failure?.reason, AuthorizedRelayPolicyFailureReason.stalePdol);
    });

    test('failed and malformed SELECT responses leave no active state', () {
      final policy = _appleTransitPolicy(selectAid, successfulFci);

      policy.prepareTerminalApdu(selectAid);
      final failed = policy.observeBackendResponse(
        terminalApdu: selectAid,
        backendResponse: hexToBytes('6A82'),
      );
      expect(
        failed.failure?.reason,
        AuthorizedRelayPolicyFailureReason.selectResponseNotSuccessful,
      );
      expect(policy.hasActivePdol, isFalse);

      policy.prepareTerminalApdu(selectAid);
      final malformed = policy.observeBackendResponse(
        terminalApdu: selectAid,
        backendResponse: hexToBytes('6F039F389000'),
      );
      expect(
        malformed.failure?.reason,
        AuthorizedRelayPolicyFailureReason.malformedFci,
      );
      expect(policy.hasActivePdol, isFalse);
      expect(
        policy.prepareTerminalApdu(suppliedGpo).failure?.reason,
        AuthorizedRelayPolicyFailureReason.stalePdol,
      );
    });

    test('rejects malformed SELECT commands without reviving old state', () {
      final policy = _appleTransitPolicy(selectAid, successfulFci);
      final malformedSelect = hexToBytes('00A4040007A00000');

      policy.prepareTerminalApdu(malformedSelect);
      final observation = policy.observeBackendResponse(
        terminalApdu: malformedSelect,
        backendResponse: successfulFci,
      );

      expect(
        observation.failure?.reason,
        AuthorizedRelayPolicyFailureReason.malformedSelect,
      );
      expect(policy.hasActivePdol, isFalse);
    });

    test('cannot install a stale SELECT response over a newer SELECT', () {
      const secondAidHex = 'A0000000041010';
      final secondSelect = hexToBytes('00A4040007${secondAidHex}00');
      final policy = AuthorizedRelaySessionPolicy(
        mode: AuthorizedRelayBackendMode.appleTransit,
      );
      policy.prepareTerminalApdu(selectAid);
      policy.prepareTerminalApdu(secondSelect);

      final stale = policy.observeBackendResponse(
        terminalApdu: selectAid,
        backendResponse: successfulFci,
      );
      expect(
        stale.failure?.reason,
        AuthorizedRelayPolicyFailureReason.stalePdol,
      );
      expect(policy.hasActivePdol, isFalse);

      final current = policy.observeBackendResponse(
        terminalApdu: secondSelect,
        backendResponse: _fci(
          aidHex: secondAidHex,
          pdolDefinitions: [hexToBytes('9F6604')],
        ),
      );
      expect(
        current.disposition,
        AuthorizedRelayBackendObservationDisposition.accepted,
      );
      expect(policy.hasActivePdol, isTrue);
    });

    test('requires one matching primitive 84 and exactly one 9F38', () {
      final aid = hexToBytes(aidHex);
      final otherAid = hexToBytes('A0000000041010');
      final validPdol = hexToBytes('9F6604');
      final cases = <(Uint8List, AuthorizedRelayPolicyFailureReason)>[
        (
          _fci(aidHex: aidHex, aidValues: const []),
          AuthorizedRelayPolicyFailureReason.missingFciAid,
        ),
        (
          _fci(aidHex: aidHex, aidValues: [aid, aid]),
          AuthorizedRelayPolicyFailureReason.duplicateFciAid,
        ),
        (
          _fci(aidHex: aidHex, aidValues: [otherAid]),
          AuthorizedRelayPolicyFailureReason.fciAidMismatch,
        ),
        (
          _fci(aidHex: aidHex, pdolDefinitions: const []),
          AuthorizedRelayPolicyFailureReason.missingPdol,
        ),
        (
          _fci(aidHex: aidHex, pdolDefinitions: [validPdol, validPdol]),
          AuthorizedRelayPolicyFailureReason.duplicatePdol,
        ),
      ];

      for (final testCase in cases) {
        final policy = AuthorizedRelaySessionPolicy(
          mode: AuthorizedRelayBackendMode.appleTransit,
        );
        policy.prepareTerminalApdu(selectAid);
        final result = policy.observeBackendResponse(
          terminalApdu: selectAid,
          backendResponse: testCase.$1,
        );
        expect(result.failure?.reason, testCase.$2);
        expect(policy.hasActivePdol, isFalse);
      }
    });

    test('requires DF name and PDOL in their direct FCI templates', () {
      final aid = hexToBytes(aidHex);
      final pdol = hexToBytes('9F6604');
      final nestedAid = Uint8List.fromList([
        ..._berTlv(
          [0x6F],
          Uint8List.fromList([
            ..._berTlv(
              [0xA5],
              Uint8List.fromList([
                ..._berTlv([0x84], aid),
                ..._berTlv([0x9F, 0x38], pdol),
              ]),
            ),
          ]),
        ),
        0x90,
        0x00,
      ]);
      final nestedPdol = Uint8List.fromList([
        ..._berTlv(
          [0x6F],
          Uint8List.fromList([
            ..._berTlv([0x84], aid),
            ..._berTlv(
              [0xA5],
              Uint8List.fromList([
                ..._berTlv([
                  0xBF,
                  0x0C,
                ], Uint8List.fromList(_berTlv([0x9F, 0x38], pdol))),
              ]),
            ),
          ]),
        ),
        0x90,
        0x00,
      ]);

      for (final testCase in [
        (nestedAid, AuthorizedRelayPolicyFailureReason.missingFciAid),
        (nestedPdol, AuthorizedRelayPolicyFailureReason.missingPdol),
      ]) {
        final policy = AuthorizedRelaySessionPolicy(
          mode: AuthorizedRelayBackendMode.appleTransit,
        );
        policy.prepareTerminalApdu(selectAid);
        expect(
          policy
              .observeBackendResponse(
                terminalApdu: selectAid,
                backendResponse: testCase.$1,
              )
              .failure
              ?.reason,
          testCase.$2,
        );
      }
    });

    test('strictly rejects malformed or oversized BER-TLV FCI', () {
      final malformedResponses = [
        hexToBytes('8407A00000000310109000'),
        hexToBytes('6F808407A000000003101000009000'),
        hexToBytes('6F81009000'),
        hexToBytes('6F039F38019000'),
      ];
      for (final response in malformedResponses) {
        final policy = AuthorizedRelaySessionPolicy(
          mode: AuthorizedRelayBackendMode.appleTransit,
        );
        policy.prepareTerminalApdu(selectAid);
        expect(
          policy
              .observeBackendResponse(
                terminalApdu: selectAid,
                backendResponse: response,
              )
              .failure
              ?.reason,
          AuthorizedRelayPolicyFailureReason.malformedFci,
        );
      }

      final oversized = Uint8List.fromList([
        ...List<int>.filled(authorizedRelayMaxFciLength + 1, 0),
        0x90,
        0x00,
      ]);
      final policy = AuthorizedRelaySessionPolicy(
        mode: AuthorizedRelayBackendMode.appleTransit,
      );
      policy.prepareTerminalApdu(selectAid);
      expect(
        policy
            .observeBackendResponse(
              terminalApdu: selectAid,
              backendResponse: oversized,
            )
            .failure
            ?.reason,
        AuthorizedRelayPolicyFailureReason.fciTooLarge,
      );
    });

    test(
      'rejects malformed, duplicate, absent, and wrong-size PDOL fields',
      () {
        final oversizedDefinition = Uint8List.fromList(
          List<int>.filled(authorizedRelayMaxPdolDefinitionLength + 1, 0x01),
        );
        final cases = <(Uint8List, AuthorizedRelayPolicyFailureReason)>[
          (hexToBytes('9F'), AuthorizedRelayPolicyFailureReason.malformedPdol),
          (
            hexToBytes('9F66049F0200'),
            AuthorizedRelayPolicyFailureReason.malformedPdol,
          ),
          (
            hexToBytes('9F66049F6604'),
            AuthorizedRelayPolicyFailureReason.duplicateRelevantPdolTag,
          ),
          (hexToBytes('9F0206'), AuthorizedRelayPolicyFailureReason.missingTtq),
          (
            hexToBytes('9F6603'),
            AuthorizedRelayPolicyFailureReason.wrongTtqLength,
          ),
          (
            hexToBytes('9F66049F3502'),
            AuthorizedRelayPolicyFailureReason.wrongTerminalTypeLength,
          ),
          (
            hexToBytes('9F66049F3302'),
            AuthorizedRelayPolicyFailureReason.wrongTerminalCapabilitiesLength,
          ),
          (
            oversizedDefinition,
            AuthorizedRelayPolicyFailureReason.pdolTooLarge,
          ),
        ];

        for (final testCase in cases) {
          final policy = AuthorizedRelaySessionPolicy(
            mode: AuthorizedRelayBackendMode.appleTransit,
          );
          policy.prepareTerminalApdu(selectAid);
          final observation = policy.observeBackendResponse(
            terminalApdu: selectAid,
            backendResponse: _fci(
              aidHex: aidHex,
              pdolDefinitions: [testCase.$1],
            ),
          );
          expect(observation.failure?.reason, testCase.$2);
          expect(policy.hasActivePdol, isFalse);
        }
      },
    );

    test('rejects malformed and extended GPOs with bounded reasons', () {
      final policy = _appleTransitPolicy(selectAid, successfulFci);
      final cases = <(Uint8List, AuthorizedRelayPolicyFailureReason)>[
        (hexToBytes('80A8'), AuthorizedRelayPolicyFailureReason.malformedGpo),
        (
          hexToBytes('80A8010002830000'),
          AuthorizedRelayPolicyFailureReason.malformedGpo,
        ),
        (
          hexToBytes('80A8000000000283000000'),
          AuthorizedRelayPolicyFailureReason.extendedGpo,
        ),
        (
          hexToBytes('80A8000007830401020304'),
          AuthorizedRelayPolicyFailureReason.malformedGpo,
        ),
        (
          hexToBytes('80A800000684040102030400'),
          AuthorizedRelayPolicyFailureReason.malformedGpo,
        ),
        (
          hexToBytes('80A80000078381040102030400'),
          AuthorizedRelayPolicyFailureReason.malformedGpo,
        ),
      ];

      for (final testCase in cases) {
        final result = policy.prepareTerminalApdu(testCase.$1);
        expect(result.shouldForward, isFalse);
        expect(result.failure?.reason, testCase.$2);
        expect(result.failure!.message.length, lessThan(80));
        expect(result.failure!.toJson().keys, {'reason', 'message'});
      }
    });

    test('rejects tag 83 values that do not exactly match the PDOL', () {
      final policy = _appleTransitPolicy(selectAid, successfulFci);
      final result = policy.prepareTerminalApdu(
        hexToBytes('80A800000683040102030400'),
      );

      expect(result.shouldForward, isFalse);
      expect(
        result.failure?.reason,
        AuthorizedRelayPolicyFailureReason.gpoPdolLengthMismatch,
      );
    });

    test('evidence contains no amount, UN, Le value, APDU, or response', () {
      final policy = _appleTransitPolicy(selectAid, successfulFci);
      final result = policy.prepareTerminalApdu(suppliedGpo);
      final evidence = result.evidence!;
      final encoded = jsonEncode(evidence.toJson());

      expect(evidence.toJson().keys, {
        'aid',
        'pdolDefinition',
        'pdolDefinitionLength',
        'pdolValueLength',
        'apduLength',
        'leLength',
        'fields',
      });
      expect(encoded, isNot(contains('000000001234')));
      expect(encoded, isNot(contains('DEADBEEF')));
      expect(encoded, isNot(contains(bytesToHex(suppliedGpo).toUpperCase())));
      expect(encoded, isNot(contains(bytesToHex(successfulFci).toUpperCase())));
      expect(encoded, isNot(contains('"le":"00"')));
      expect(evidence.fields.map((field) => field.field).toSet(), {
        AuthorizedRelayApprovedPdolField.ttq,
        AuthorizedRelayApprovedPdolField.terminalType,
        AuthorizedRelayApprovedPdolField.terminalCapabilities,
      });
      expect(
        () => evidence.fields.add(
          const AuthorizedRelayApprovedFieldRewrite(
            field: AuthorizedRelayApprovedPdolField.ttq,
            beforeHex: '',
            afterHex: '',
          ),
        ),
        throwsUnsupportedError,
      );
    });

    test('explicit session clear invalidates the selected PDOL', () {
      final policy = _appleTransitPolicy(selectAid, successfulFci);
      policy.clear();

      expect(policy.hasActivePdol, isFalse);
      expect(
        policy.prepareTerminalApdu(suppliedGpo).failure?.reason,
        AuthorizedRelayPolicyFailureReason.stalePdol,
      );
    });
  });

  group('authorized relay platform ownership', () {
    const channel = MethodChannel(
      'io.chameleon.ultra/authorized_relay_methods',
    );

    tearDown(() async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    test('uses native arm tokens and token-bound pending checks', () async {
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            return switch (call.method) {
              'allocateArmToken' => {'armToken': 41, 'monotonicUs': 1000000},
              'authorizeAndEnable' => true,
              'isPending' => false,
              _ => throw MissingPluginException(),
            };
          });
      final platform = AuthorizedRelayPlatform();

      final allocation = await platform.allocateArmToken();
      expect(allocation.armToken, 41);
      expect(allocation.nativeMonotonicUs, 1000000);
      await platform.authorizeAndEnable(
        41,
        aids: const ['A0000000031010'],
        deadlineMs: 900,
      );
      expect(await platform.isPending(41, 9), isFalse);
      expect(calls.map((call) => call.method), [
        'allocateArmToken',
        'authorizeAndEnable',
        'isPending',
      ]);
      expect(calls[1].arguments, {
        'armToken': 41,
        'aids': ['A0000000031010'],
        'deadlineMs': 900,
      });
      expect(calls.last.arguments, {'armToken': 41, 'id': 9});
    });

    test('delivers exact binary responses without hex conversion', () async {
      MethodCall? responseCall;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            responseCall = call;
            return true;
          });
      final response = Uint8List.fromList([0x80, 0xCA, 0x00, 0x90, 0x00]);

      expect(await AuthorizedRelayPlatform().respond(41, 9, response), isTrue);
      expect(responseCall?.method, 'respond');
      final arguments = responseCall?.arguments as Map<Object?, Object?>;
      expect(arguments['armToken'], 41);
      expect(arguments['id'], 9);
      expect(arguments['response'], orderedEquals(response));
    });

    test('rejects invalid native tokens and pending identities', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            channel,
            (call) async => call.method == 'allocateArmToken'
                ? {'armToken': 0, 'monotonicUs': 1}
                : 0,
          );
      final platform = AuthorizedRelayPlatform();

      await expectLater(platform.allocateArmToken(), throwsFormatException);
      await expectLater(platform.isPending(0, 1), throwsArgumentError);
      await expectLater(platform.isPending(1, 0), throwsArgumentError);
      await expectLater(
        platform.authorizeAndEnable(0, aids: const ['A0000000031010']),
        throwsArgumentError,
      );
      await expectLater(
        platform.authorizeAndEnable(1, aids: const []),
        throwsArgumentError,
      );
      await expectLater(platform.respond(1, 1, Uint8List(1)), throwsRangeError);
      await expectLater(platform.setEnabled(true), throwsArgumentError);
    });

    test('surfaces a rejected token-bound native disable', () async {
      MethodCall? call;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (value) async {
            call = value;
            return false;
          });
      final platform = AuthorizedRelayPlatform();

      await expectLater(
        platform.setEnabled(false, armToken: 17),
        throwsA(
          isA<PlatformException>().having(
            (error) => error.code,
            'code',
            'HCE_STATE_FAILED',
          ),
        ),
      );
      expect(call?.method, 'setEnabled');
      expect(call?.arguments, {'enabled': false, 'armToken': 17});
    });
  });

  group('authorized relay PPSE preflight', () {
    test('extracts and deduplicates payment AIDs', () {
      final response = hexToBytes(
        '6F2C840E325041592E5359532E4444463031A51ABF0C176109'
        '4F07A0000000031010610A4F08A0000000041010009000',
      );

      expect(extractAuthorizedRelayAids(response), [
        'A0000000031010',
        'A000000004101000',
      ]);
    });

    test('rejects failed or empty PPSE responses', () {
      expect(
        () => extractAuthorizedRelayAids(hexToBytes('6A82')),
        throwsFormatException,
      );
      expect(
        () => extractAuthorizedRelayAids(hexToBytes('6F009000')),
        throwsFormatException,
      );
      expect(
        () => extractAuthorizedRelayAids(hexToBytes('4F10A00000000310109000')),
        throwsFormatException,
      );
      expect(
        () => extractAuthorizedRelayAids(hexToBytes('4F07A00000000310109000')),
        throwsFormatException,
      );
    });

    test('summaries retain no APDU body', () {
      final command = hexToBytes('80AE8000080102030405060708');
      expect(authorizedRelayApduSummary(command), '80AE8000 (13 bytes)');
      expect(authorizedRelayStatusSummary(hexToBytes('01029000')), '9000');
    });

    test('waits through no-card responses until a card appears', () async {
      var attempts = 0;
      var waits = 0;
      final delays = <Duration>[];
      final result = await waitForAuthorizedRelayBackendCard<int>(
        attempt: () async {
          attempts++;
          if (attempts < 3) {
            throw const ChameleonCommandException(
              ChameleonCommand.hf14a4ReaderSessionStart,
              0x01,
            );
          }
          return 42;
        },
        isCancelled: () => false,
        onWaiting: () => waits++,
        delay: (value) async => delays.add(value),
      );

      expect(result, 42);
      expect(attempts, 3);
      expect(waits, 2);
      expect(delays, [
        authorizedRelayCardPollInterval,
        authorizedRelayCardPollInterval,
      ]);
    });

    test('terminal arrival wakes a pending card-poll delay', () async {
      final pollDelay = AuthorizedRelayPollDelay();
      final waiting = pollDelay.wait(const Duration(days: 1));
      await Future<void>.delayed(Duration.zero);

      pollDelay.wake();

      await waiting.timeout(const Duration(milliseconds: 100));
    });

    test('card-poll wakeup is retained until the delay starts', () async {
      final pollDelay = AuthorizedRelayPollDelay()..wake();

      await pollDelay
          .wait(const Duration(days: 1))
          .timeout(const Duration(milliseconds: 100));
    });

    test('continuous card wait is cancellable', () async {
      var cancelled = false;
      final result = await waitForAuthorizedRelayBackendCard<int>(
        attempt: () async => throw const ChameleonCommandException(
          ChameleonCommand.hf14a4ReaderSessionStart,
          0x01,
        ),
        isCancelled: () => cancelled,
        onWaiting: () => cancelled = true,
        delay: (_) async {},
      );

      expect(result, isNull);
    });

    test('continuous card wait does not hide other firmware errors', () async {
      expect(
        isAuthorizedRelayCardAbsentError(
          const ChameleonCommandException(
            ChameleonCommand.hf14a4ReaderSessionExchange,
            0x01,
          ),
        ),
        isFalse,
      );
      expect(
        () => waitForAuthorizedRelayBackendCard<int>(
          attempt: () async => throw const ChameleonCommandException(
            ChameleonCommand.hf14a4ReaderSessionStart,
            0x08,
          ),
          isCancelled: () => false,
          delay: (_) async {},
        ),
        throwsA(
          isA<ChameleonCommandException>().having(
            (error) => error.status,
            'status',
            0x08,
          ),
        ),
      );
    });
  });
}

AuthorizedRelaySessionPolicy _appleTransitPolicy(
  Uint8List selectAid,
  Uint8List fci,
) {
  final policy = AuthorizedRelaySessionPolicy(
    mode: AuthorizedRelayBackendMode.appleTransit,
  );
  policy.prepareTerminalApdu(selectAid);
  final observation = policy.observeBackendResponse(
    terminalApdu: selectAid,
    backendResponse: fci,
  );
  if (observation.disposition !=
      AuthorizedRelayBackendObservationDisposition.accepted) {
    throw StateError('Test FCI was rejected: ${observation.failure}');
  }
  return policy;
}

Uint8List _fci({
  required String aidHex,
  List<Uint8List>? aidValues,
  List<Uint8List>? pdolDefinitions,
}) {
  final aid = hexToBytes(aidHex);
  final body = <int>[];
  for (final value in aidValues ?? [aid]) {
    body.addAll(_berTlv([0x84], value));
  }
  final proprietary = <int>[];
  for (final definition in pdolDefinitions ?? [hexToBytes('9F6604')]) {
    proprietary.addAll(_berTlv([0x9F, 0x38], definition));
  }
  if (proprietary.isNotEmpty) {
    body.addAll(_berTlv([0xA5], Uint8List.fromList(proprietary)));
  }
  return Uint8List.fromList([
    ..._berTlv([0x6F], Uint8List.fromList(body)),
    0x90,
    0x00,
  ]);
}

List<int> _berTlv(List<int> tag, Uint8List value) => [
  ...tag,
  ..._berLength(value.length),
  ...value,
];

List<int> _berLength(int length) {
  if (length < 0x80) return [length];
  if (length <= 0xFF) return [0x81, length];
  return [0x82, length >> 8, length & 0xFF];
}

Uint8List _shortGpo(Uint8List values, {int? le}) {
  final valueLength = _berLength(values.length);
  final data = [0x83, ...valueLength, ...values];
  return Uint8List.fromList([
    0x80,
    0xA8,
    0x00,
    0x00,
    data.length,
    ...data,
    ?le,
  ]);
}

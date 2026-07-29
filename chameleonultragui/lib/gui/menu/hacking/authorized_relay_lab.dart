import 'dart:async';
import 'dart:convert';

import 'package:chameleonultragui/bridge/authorized_relay_platform.dart';
import 'package:chameleonultragui/bridge/chameleon.dart';
import 'package:chameleonultragui/helpers/authorized_relay.dart';
import 'package:chameleonultragui/helpers/definitions.dart';
import 'package:chameleonultragui/helpers/general.dart';
import 'package:chameleonultragui/main.dart';
import 'package:chameleonultragui/generated/i18n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

class AuthorizedRelayLabPage extends StatefulWidget {
  const AuthorizedRelayLabPage({super.key});

  @override
  State<AuthorizedRelayLabPage> createState() => _AuthorizedRelayLabPageState();
}

class _AuthorizedRelayLabPageState extends State<AuthorizedRelayLabPage>
    with WidgetsBindingObserver {
  static final _connectionRegistry =
      AuthorizedRelayConnectionRegistry<ChameleonCommunicator>();
  static const _startCommands =
      AuthorizedRelayBackendModeMapping<ChameleonCommand>(
        transparent: ChameleonCommand.hf14a4ReaderSessionStart,
        appleTransit: ChameleonCommand.hf14a4ReaderSessionStartAppleTransit,
      );

  final _platform = AuthorizedRelayPlatform();
  final _deadline = TextEditingController(text: '1000');
  final _backendPollDelay = AuthorizedRelayPollDelay();
  StreamSubscription<AuthorizedRelayEvent>? _events;
  ChameleonGUIState? _app;
  AuthorizedRelayReadiness _readiness = const AuthorizedRelayReadiness(
    hceSupported: false,
    nfcEnabled: false,
    deviceLocked: true,
    isDefaultPaymentService: false,
    registeredAids: [],
  );
  AuthorizedRelayRendezvous<_AuthorizedRelayBackend>? _rendezvous;
  AuthorizedRelaySessionCapability<
    _AuthorizedRelayBackend,
    ChameleonCommunicator
  >?
  _preparedCapability;
  AuthorizedRelayConnectionCoordinator? _preparedCoordinator;
  AuthorizedRelayConnectionCoordinator? _armedCoordinator;
  ChameleonCommunicator? _armedCommunicator;
  ChameleonCommunicator? _preparingCommunicator;
  int? _armToken;
  int? _armedDeadlineMs;
  CardData? _preparedCard;
  List<String> _paymentAids = const [];
  AuthorizedRelayBackendMode _backendMode =
      AuthorizedRelayBackendMode.transparent;
  AuthorizedRelayBackendMode? _preparedBackendMode;
  AuthorizedRelayBackendMode? _armedBackendMode;
  final List<_AuthorizedRelayRecord> _records = [];
  bool _armed = false;
  bool _arming = false;
  bool _busy = false;
  bool _waitingForCard = false;
  bool _cancelCardWaitRequested = false;
  bool _disarming = false;
  bool _monitorPaused = false;
  int? _activePreparationGeneration;
  bool _hasForwardedApdu = false;
  final Set<int> _backendApdusInFlight = <int>{};
  int _sessionDeliveredApdus = 0;
  int _operationGeneration = 0;
  Completer<void>? _preparationCompletion;
  Completer<void>? _disarmCompletion;
  String? _error;
  String? _notice;

  bool get _connected =>
      _app?.connector?.connected == true && _app?.communicator != null;

  bool get _prepared => _preparedCapability?.available == true;

  bool get _armActive => _prepared || _armed || _arming || _rendezvous != null;

  bool get _backendApduInFlight => _backendApdusInFlight.isNotEmpty;

  String get _backendModeLabel => switch (_backendMode) {
    AuthorizedRelayBackendMode.transparent => 'Transparent',
    AuthorizedRelayBackendMode.appleTransit => 'Apple Transit',
  };

  ChameleonCommand _startCommand(AuthorizedRelayBackendMode mode) =>
      _startCommands.resolve(mode);

  Future<IsoDepReaderSessionInfo> _startBackendSession(
    ChameleonCommunicator communicator,
    AuthorizedRelayBackendMode mode,
  ) => switch (mode) {
    AuthorizedRelayBackendMode.transparent =>
      communicator.hf14a4ReaderSessionStart(),
    AuthorizedRelayBackendMode.appleTransit =>
      communicator.hf14a4ReaderSessionStartAppleTransit(),
  };

  String? get _relayStateLabel {
    if (!_armed) return null;
    final phase = _rendezvous?.phase;
    return switch (phase) {
      AuthorizedRelayRendezvousPhase.waitingForBoth ||
      AuthorizedRelayRendezvousPhase.waitingForBackend =>
        'Armed state lost its live backend',
      AuthorizedRelayRendezvousPhase.waitingForTerminal =>
        'Armed: live backend session is waiting for the terminal',
      AuthorizedRelayRendezvousPhase.exchanging => 'Armed: exchanging APDU',
      _ => null,
    };
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _events = _platform.events.listen(
      _handlePlatformEvent,
      onError: (Object error) {
        if (_armActive) {
          unawaited(
            _disarm(message: 'Native relay event channel failed: $error'),
          );
        } else if (mounted) {
          setState(() => _error = error.toString());
        }
      },
    );
    unawaited(_refreshReadiness());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final app = context.read<ChameleonGUIState>();
    if (!identical(_app, app)) {
      _app?.removeListener(_onAppStateChanged);
      _app = app..addListener(_onAppStateChanged);
      _connectionRegistry.observeConnection(
        connected: _connected,
        communicator: app.communicator,
      );
      _backendMode =
          app.sharedPreferencesProvider.getAuthorizedRelayAppleTransit()
          ? AuthorizedRelayBackendMode.appleTransit
          : AuthorizedRelayBackendMode.transparent;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_refreshReadiness());
      return;
    }
    _cancelCardWaitRequested = true;
    _backendPollDelay.wake();
    if (_armActive && !_disarming) {
      unawaited(
        _disarm(
          message:
              'App left the foreground; turn Arm on again to acquire the backend',
        ),
      );
    } else if (_busy) {
      _operationGeneration++;
    }
  }

  void _onAppStateChanged() {
    final communicator = _app?.communicator;
    _connectionRegistry.observeConnection(
      connected: _connected,
      communicator: communicator,
    );
    final boundCommunicator =
        _preparedCapability?.binding.communicator ?? _armedCommunicator;
    final communicatorChanged =
        boundCommunicator != null &&
        !identical(boundCommunicator, communicator);
    final preparationConnectionChanged =
        _preparingCommunicator != null &&
        (!_connected || !identical(_preparingCommunicator, communicator));
    if (preparationConnectionChanged) {
      _operationGeneration++;
      _cancelCardWaitRequested = true;
      _backendPollDelay.wake();
    }
    if (_armActive && (!_connected || communicatorChanged) && !_disarming) {
      unawaited(
        _disarm(
          message: communicatorChanged
              ? 'Backend Chameleon connection was replaced'
              : 'Backend Chameleon disconnected',
        ),
      );
    } else if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _backendPollDelay.reset();
    WidgetsBinding.instance.removeObserver(this);
    _app?.removeListener(_onAppStateChanged);
    unawaited(_disarm(updateUi: false));
    _events?.cancel();
    _deadline.dispose();
    super.dispose();
  }

  Future<void> _refreshReadiness() async {
    try {
      final readiness = await _platform.getReadiness();
      if (mounted) setState(() => _readiness = readiness);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    }
  }

  Future<void> _setBackendMode(AuthorizedRelayBackendMode mode) async {
    if (mode == _backendMode || _busy) return;
    if (_armActive) {
      await _disarm(message: 'Backend mode changed; turn Arm on again');
      if (!mounted) return;
    }
    if (mode == AuthorizedRelayBackendMode.appleTransit) {
      final accepted =
          await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Enable Apple Transit relay mode?'),
              content: const Text(
                'This mode uses ECP2 polling on the backend link and '
                'rewrites only TTQ, terminal type and terminal capabilities in a '
                'GPO built from the selected application\'s exact PDOL. Amount, '
                'currency, date, unpredictable number and all card responses stay '
                'unchanged. It remains selected across relay sessions and app '
                'restarts until you disable it. Use only an owned or explicitly '
                'authorized credential.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Enable Apple Transit'),
                ),
              ],
            ),
          ) ??
          false;
      if (!accepted || !mounted) return;
    }

    _operationGeneration++;
    _app?.sharedPreferencesProvider.setAuthorizedRelayAppleTransit(
      mode == AuthorizedRelayBackendMode.appleTransit,
    );
    setState(() {
      _backendMode = mode;
      _preparedBackendMode = null;
      _preparedCard = null;
      _error = null;
      _notice =
          'Backend mode changed. The next Arm will acquire a new session.';
    });
  }

  Future<void> _prepare() async {
    if (!_connected) {
      setState(() => _error = 'Connect a Chameleon Ultra first');
      return;
    }
    if (_armActive) {
      setState(
        () => _error = 'Discard the current live session before preparing',
      );
      return;
    }
    final generation = ++_operationGeneration;
    final preparationCompletion = Completer<void>();
    _preparationCompletion = preparationCompletion;
    final communicator = _app!.communicator!;
    final coordinator = _connectionRegistry.forCommunicator(communicator);
    final mode = _backendMode;
    _activePreparationGeneration = generation;
    _preparingCommunicator = communicator;
    setState(() {
      _busy = true;
      _waitingForCard = false;
      _cancelCardWaitRequested = false;
      _error = null;
      _notice = 'Waiting for prior relay cleanup to finish';
      _preparedBackendMode = null;
      _preparedCard = null;
    });

    IsoDepReaderSessionInfo? preflight;
    var completed = false;
    Object? cancellationCleanupError;
    Object? preparationCleanupError;
    AuthorizedRelayCleanupBarrier? preparationBarrier;
    late int connectionGeneration;
    try {
      await _connectionRegistry.awaitCleanup(communicator);
      _ensureCurrentOperation(generation);
      if (!_connected ||
          !identical(communicator, _app?.communicator) ||
          !coordinator.connected) {
        throw const _RelayOperationCancelled();
      }
      if (coordinator.poisoned) {
        throw _RelayReconnectRequired(
          coordinator.poisonReason ?? 'Backend session state is uncertain',
        );
      }
      final initialReadiness = await _platform.getReadiness();
      _ensureCurrentOperation(generation);
      if (!initialReadiness.platformReady) {
        throw const FormatException(
          'Unlock Android and enable NFC before turning on Arm',
        );
      }
      if (!initialReadiness.isDefaultPaymentService) {
        throw const FormatException(
          'Open Payment settings and select CU GUI Authorized Relay before turning on Arm',
        );
      }
      connectionGeneration = coordinator.generation;
      preparationBarrier = _connectionRegistry.beginCleanup(communicator);
      await preparationBarrier.predecessor;
      _ensureCurrentOperation(generation);
      if (mounted) {
        setState(() {
          _waitingForCard = true;
          _notice = null;
        });
      }
      await _pauseMonitor();
      _ensureCurrentOperation(generation);
      await _requireRelayCapabilities(communicator, mode);
      if (!await communicator.isReaderDeviceMode()) {
        _ensureCurrentOperation(generation);
        await communicator.setReaderDeviceMode(true);
      }
      _ensureCurrentOperation(generation);
      preflight = await waitForAuthorizedRelayBackendCard(
        attempt: () {
          if (!_connected) {
            throw StateError('Backend Chameleon disconnected while waiting');
          }
          return _startBackendSession(communicator, mode);
        },
        isCancelled: () =>
            _cancelCardWaitRequested ||
            !mounted ||
            generation != _operationGeneration,
        onWaiting: () {
          if (mounted && generation == _operationGeneration) {
            setState(() {
              _error =
                  'No backend card detected. Waiting for a card on the Ultra';
            });
          }
        },
        delay: _backendPollDelay.wait,
      );
      if (preflight == null || _cancelCardWaitRequested) {
        throw const _RelayOperationCancelled();
      }
      _ensureCurrentOperation(generation);
      setState(() {
        _waitingForCard = false;
        _error = null;
      });
      final preparedCard = preflight.card;
      final ppse = await communicator.hf14a4ReaderSessionExchange(
        preflight.sessionId,
        hexToBytes(authorizedRelaySelectPpseHex),
      );
      _ensureCurrentOperation(generation);
      final aids = extractAuthorizedRelayAids(ppse);

      await _platform.registerAids(aids);
      _ensureCurrentOperation(generation);
      final readiness = await _platform.getReadiness();
      _ensureCurrentOperation(generation);
      final backend = _AuthorizedRelayBackend(
        communicator,
        preflight,
        mode,
        prefetchedResponse: AuthorizedRelayPrefetchedResponse(
          command: hexToBytes(authorizedRelaySelectPpseHex),
          response: ppse,
        ),
      );
      final capability =
          AuthorizedRelaySessionCapability<
            _AuthorizedRelayBackend,
            ChameleonCommunicator
          >(
            binding: AuthorizedRelaySessionBinding(
              communicator: communicator,
              generation: connectionGeneration,
              mode: mode,
              sessionId: preflight.sessionId,
            ),
            backend: backend,
          );
      _preparedCapability = capability;
      _preparedCoordinator = coordinator;
      preflight = null;
      completed = true;
      setState(() {
        _readiness = readiness;
        _preparedBackendMode = mode;
        _preparedCard = preparedCard;
        _paymentAids = aids;
        if (!readiness.isDefaultPaymentService) {
          _error = 'Select CU GUI as the default contactless payment service';
        } else {
          _notice =
              'Backend session ${backend.session.sessionId} is ready to arm.';
        }
      });
    } on _RelayReconnectRequired catch (error) {
      if (mounted && generation == _operationGeneration) {
        setState(() => _error = '${error.message}. Reconnect required.');
      }
    } on _RelayOperationCancelled {
      if (mounted &&
          generation == _operationGeneration &&
          _cancelCardWaitRequested) {
        setState(() => _error = 'Backend card wait cancelled');
      }
    } on ChameleonResponseTimeoutException catch (error) {
      final sessionCanBeReset = preflight != null;
      if (!sessionCanBeReset) {
        _poisonConnection(
          communicator,
          'Backend START timed out during preparation: $error',
        );
      }
      if (mounted && generation == _operationGeneration) {
        setState(() {
          _error = sessionCanBeReset
              ? 'Automatic backend acquisition failed: $error. The backend '
                    'session was reset; try Arm again.'
              : 'Automatic backend acquisition failed: $error. Reconnect the '
                    'Chameleon before trying again.';
        });
      }
    } catch (error) {
      if (isAuthorizedRelaySessionUncertainError(error) && preflight == null) {
        _poisonConnection(
          communicator,
          'Backend START outcome is uncertain: $error',
        );
      }
      if (mounted && generation == _operationGeneration) {
        setState(() => _error = 'Automatic backend acquisition failed: $error');
      }
    } finally {
      if (preflight != null) {
        try {
          await communicator.hf14a4ReaderSessionReset(preflight.sessionId);
        } catch (error) {
          _poisonConnection(
            communicator,
            'Backend session reset failed: $error',
          );
          if (_cancelCardWaitRequested) {
            cancellationCleanupError = error;
          } else {
            preparationCleanupError = error;
          }
        }
      }
      if (!completed) _resumeMonitor();
      if (_activePreparationGeneration == generation) {
        _activePreparationGeneration = null;
        _preparingCommunicator = null;
      }
      if (!preparationCompletion.isCompleted) preparationCompletion.complete();
      if (identical(_preparationCompletion, preparationCompletion)) {
        _preparationCompletion = null;
      }
      if (mounted &&
          (generation == _operationGeneration ||
              _activePreparationGeneration == null)) {
        setState(() {
          _busy = false;
          _waitingForCard = false;
          if (_cancelCardWaitRequested && cancellationCleanupError != null) {
            _error =
                'Backend card wait cancelled, but session cleanup failed: '
                '$cancellationCleanupError';
          } else if (preparationCleanupError != null) {
            _error =
                '${_error ?? 'Backend acquisition failed'}. Relay cleanup '
                'incomplete: $preparationCleanupError. Reconnect required.';
          } else if (coordinator.poisoned &&
              _error?.contains('Reconnect required') != true) {
            _error =
                '${_error ?? 'Backend acquisition failed'}. Reconnect required.';
          }
          _cancelCardWaitRequested = false;
        });
      }
      preparationBarrier?.complete();
    }
  }

  void _cancelCardWait() {
    if (!_waitingForCard || _cancelCardWaitRequested) return;
    setState(() {
      _cancelCardWaitRequested = true;
      _error = 'Cancelling backend card wait...';
    });
  }

  Future<void> _openPaymentSettings() async {
    try {
      final preparationCompletion = _preparationCompletion;
      if (preparationCompletion != null) {
        _cancelCardWaitRequested = true;
        _operationGeneration++;
        _backendPollDelay.wake();
        await preparationCompletion.future;
      }
      if (_armActive) {
        await _disarm(
          notice:
              'Live authorization was closed before opening Android settings. '
              'Turn Arm on again after selecting CU GUI.',
        );
      }
      await _platform.openPaymentSettings();
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    }
  }

  Future<void> _arm() async {
    final capability = _preparedCapability;
    final coordinator = _preparedCoordinator;
    if (capability == null ||
        coordinator == null ||
        !capability.available ||
        _preparedBackendMode != _backendMode) {
      setState(() {
        _error = 'Automatic backend acquisition did not complete';
      });
      _resumeMonitor();
      return;
    }
    final deadlineMs = int.tryParse(_deadline.text);
    if (deadlineMs == null || deadlineMs < 50 || deadlineMs > 5000) {
      setState(() => _error = 'Deadline must be 50..5000 ms');
      _resumeMonitor();
      return;
    }
    if (!_connected) {
      setState(() => _error = 'Backend Chameleon is disconnected');
      _resumeMonitor();
      return;
    }

    final preparationGeneration = _operationGeneration;
    final mode = _backendMode;
    final communicator = _app!.communicator!;
    final sessionId = capability.binding.sessionId;
    if (!capability.binding.matches(
          communicator: communicator,
          generation: coordinator.generation,
          mode: mode,
          sessionId: sessionId,
        ) ||
        !coordinator.connected ||
        coordinator.poisoned) {
      await _disarm(
        message: 'Backend continuity was lost; reconnect and turn Arm on again',
      );
      return;
    }
    setState(() {
      _busy = true;
      _arming = true;
      _error = null;
      _notice = null;
    });
    int? token;
    var generation = preparationGeneration;
    try {
      await _pauseMonitor();
      _ensurePreparedCurrent(
        capability,
        preparationGeneration,
        communicator,
        mode,
        coordinator,
      );
      final readiness = await _platform.getReadiness();
      _ensurePreparedCurrent(
        capability,
        preparationGeneration,
        communicator,
        mode,
        coordinator,
      );
      if (!readiness.platformReady || !readiness.isDefaultPaymentService) {
        throw const FormatException(
          'Unlock Android, enable NFC and select CU GUI for contactless payments',
        );
      }
      final allocation = await _platform.allocateArmToken();
      token = allocation.armToken;
      _ensurePreparedCurrent(
        capability,
        preparationGeneration,
        communicator,
        mode,
        coordinator,
      );
      final backend = capability.consume(
        communicator: communicator,
        generation: coordinator.generation,
        mode: mode,
        sessionId: sessionId,
      );
      if (backend == null) throw const _RelayOperationCancelled();
      _preparedCapability = null;
      _preparedCoordinator = null;
      generation = ++_operationGeneration;
      _armToken = token;
      _armedDeadlineMs = deadlineMs;
      _armedCommunicator = communicator;
      _armedCoordinator = coordinator;
      _armedBackendMode = mode;
      _hasForwardedApdu = false;
      _backendApdusInFlight.clear();
      _sessionDeliveredApdus = 0;
      _rendezvous = AuthorizedRelayRendezvous(token);
      if (_rendezvous!.acceptBackend(token, backend) != true) {
        throw StateError('Could not consume the prepared backend capability');
      }
      await _platform.authorizeAndEnable(
        token,
        aids: _paymentAids,
        deadlineMs: deadlineMs,
      );
      _ensureArmCurrent(generation, token, communicator);
      setState(() {
        _readiness = readiness;
        _armed = true;
        _arming = false;
        _busy = false;
      });
    } on _RelayOperationCancelled {
      if (token != null && _armToken == token) {
        await _disarm();
      } else {
        _resumeMonitor();
        if (mounted) {
          setState(() {
            _busy = false;
            _arming = false;
          });
        }
      }
    } catch (error) {
      if (token != null && _armToken == token) {
        await _disarm(message: 'Arming failed: $error');
      } else if (mounted && generation == _operationGeneration) {
        _resumeMonitor();
        setState(() {
          _busy = false;
          _arming = false;
          _error = 'Arming failed: $error';
        });
      }
    }
  }

  Future<void> _requireRelayCapabilities(
    ChameleonCommunicator communicator,
    AuthorizedRelayBackendMode mode,
  ) async {
    final support = await Future.wait([
      communicator.supportsCommand(_startCommand(mode)),
      communicator.supportsCommand(
        ChameleonCommand.hf14a4ReaderSessionExchange,
      ),
      communicator.supportsCommand(ChameleonCommand.hf14a4ReaderSessionStop),
    ]);
    if (support.any((value) => value != true)) {
      throw const FormatException(
        'Firmware does not advertise the selected persistent ISO-DEP relay mode',
      );
    }
  }

  Future<void> _setArmed(bool value) async {
    if (value) {
      if (!_prepared) {
        await _prepare();
        if (!mounted || !_prepared) return;
      }
      await _arm();
    } else {
      await _disarm(message: 'Relay disarmed');
    }
  }

  Future<void> _handlePlatformEvent(AuthorizedRelayEvent event) async {
    if (event.armToken != _armToken) return;
    if (event.type == AuthorizedRelayEventType.expired) {
      final backendApduInFlight = _backendApduInFlight;
      await _disarm(
        message: backendApduInFlight
            ? 'Native terminal deadline expired while a backend APDU was in '
                  'flight. Do not retry this APDU; the backend session was reset.'
            : 'Native terminal response deadline expired',
      );
      return;
    }
    if (event.type == AuthorizedRelayEventType.deactivated) {
      final deliveredApdus = _sessionDeliveredApdus;
      final completedApdu = deliveredApdus > 0;
      final backendApduInFlight = _backendApduInFlight;
      await _disarm(
        message: backendApduInFlight
            ? 'Terminal NFC deactivated while a backend APDU was in flight. '
                  'Do not retry this APDU; the backend session was reset.'
            : completedApdu
            ? null
            : authorizedRelayDeactivationFailure(
                reason: event.reason,
                hasForwardedApdu: _hasForwardedApdu,
              ),
        notice: completedApdu && !backendApduInFlight
            ? authorizedRelayDeactivationNotice(
                reason: event.reason,
                deliveredApdus: deliveredApdus,
              )
            : null,
      );
      return;
    }
    if (event.type == AuthorizedRelayEventType.invalidated) {
      await _disarm(
        message: 'Native relay invalidated: ${event.reason ?? 'unavailable'}',
      );
      return;
    }
    final id = event.id;
    final apdu = event.apdu;
    final rendezvous = _rendezvous;
    if (id == null || apdu == null || rendezvous == null) return;
    final accepted = rendezvous.acceptTerminal(
      AuthorizedRelayTerminalApdu(
        armToken: event.armToken,
        id: id,
        apdu: apdu,
        receivedUs: event.receivedUs,
        expiresAtUs: event.expiresAtUs,
      ),
    );
    if (!accepted) {
      await _disarm(message: 'Unexpected concurrent terminal APDU');
      return;
    }
    await _tryExchange(_operationGeneration, event.armToken);
  }

  Future<void> _tryExchange(int generation, int token) async {
    final exchange = _rendezvous?.beginExchange(token);
    if (exchange == null) return;
    final backend = exchange.backend;
    final terminal = exchange.terminal;
    if (!_isCurrentArm(generation, token, backend.communicator)) {
      if (_armToken == token) {
        await _disarm(
          message: 'Backend Chameleon connection changed before exchange',
        );
      }
      return;
    }
    if (mounted) setState(() => _busy = true);
    final command = terminal.apdu;
    final policyDecision = backend.policy.prepareTerminalApdu(command);
    final outboundCommand = policyDecision.apdu;
    var transitRewrite = policyDecision.evidence;
    var transitPolicyFailure = policyDecision.failure;
    final stopwatch = Stopwatch()..start();

    bool pending;
    try {
      pending = await _platform.isPending(token, terminal.id);
    } catch (error) {
      await _disarm(
        message: 'Could not validate the native terminal deadline: $error',
      );
      return;
    }
    if (!_isCurrentArm(generation, token, backend.communicator)) return;
    if (!pending) {
      await _disarm(
        message: 'Terminal request expired before backend exchange',
      );
      return;
    }

    Uint8List response = Uint8List.fromList([0x64, 0x00]);
    Object? failure;
    var delivered = false;
    var syntheticFallback = false;
    var prefetchedBackendResponse = false;
    var backendApduStarted = false;
    int? backendExchangeUs;
    int? nativeDeliveryUs;
    try {
      if (outboundCommand == null) {
        throw _RelayPolicyRejected(
          transitPolicyFailure ??
              const AuthorizedRelayPolicyFailure(
                AuthorizedRelayPolicyFailureReason.malformedGpo,
              ),
        );
      }
      final prefetched = backend.takePrefetchedResponse(outboundCommand);
      if (prefetched != null) {
        response = prefetched;
        prefetchedBackendResponse = true;
        backendExchangeUs = 0;
      } else {
        backendApduStarted = true;
        _backendApdusInFlight.add(terminal.id);
        final backendStopwatch = Stopwatch()..start();
        try {
          response = await backend.communicator.hf14a4ReaderSessionExchange(
            backend.session.sessionId,
            outboundCommand,
          );
        } finally {
          backendStopwatch.stop();
          backendExchangeUs = backendStopwatch.elapsedMicroseconds;
        }
      }
      final observation = backend.policy.observeBackendResponse(
        terminalApdu: command,
        backendResponse: response,
      );
      transitPolicyFailure ??= observation.failure;
      _ensureArmCurrent(generation, token, backend.communicator);
      if (_rendezvous?.completeExchange(token) != true) {
        throw const _RelayOperationCancelled();
      }
      final deliveryStopwatch = Stopwatch()..start();
      try {
        delivered = await _platform.respond(token, terminal.id, response);
      } finally {
        deliveryStopwatch.stop();
        nativeDeliveryUs = deliveryStopwatch.elapsedMicroseconds;
      }
    } catch (error) {
      failure = error;
      syntheticFallback = true;
      response = Uint8List.fromList([0x64, 0x00]);
      if (error is IsoDepReaderSessionExchangeException &&
          error.firmwareSessionClosed) {
        backend.firmwareSessionClosed = true;
      }
      if (_isCurrentArm(generation, token, backend.communicator)) {
        final deliveryStopwatch = Stopwatch()..start();
        try {
          delivered = await _platform.respond(
            token,
            terminal.id,
            Uint8List.fromList([0x64, 0x00]),
          );
        } catch (_) {
        } finally {
          deliveryStopwatch.stop();
          nativeDeliveryUs =
              (nativeDeliveryUs ?? 0) + deliveryStopwatch.elapsedMicroseconds;
        }
      }
    }
    if (failure == null && delivered && backendApduStarted) {
      _backendApdusInFlight.remove(terminal.id);
    }
    stopwatch.stop();
    if (!_isCurrentArm(generation, token, backend.communicator)) return;
    if (mounted) {
      setState(() {
        _records.insert(
          0,
          _AuthorizedRelayRecord(
            armToken: token,
            requestId: terminal.id,
            receivedUs: terminal.receivedUs,
            expiresAtUs: terminal.expiresAtUs,
            backendSessionId: backend.session.sessionId,
            terminalBudgetUs:
                terminal.receivedUs == null || terminal.expiresAtUs == null
                ? null
                : terminal.expiresAtUs! - terminal.receivedUs!,
            backendMode: backend.mode,
            command: authorizedRelayApduSummary(command),
            status: authorizedRelayStatusSummary(response),
            elapsedUs: stopwatch.elapsedMicroseconds,
            backendExchangeUs: backendExchangeUs,
            nativeDeliveryUs: nativeDeliveryUs,
            delivered: delivered,
            syntheticFallback: syntheticFallback,
            prefetchedBackendResponse: prefetchedBackendResponse,
            deviceStatus: failure is IsoDepReaderSessionExchangeException
                ? failure.status
                : null,
            isoDepError: failure is IsoDepReaderSessionExchangeException
                ? failure.isoDepError
                : null,
            rfStatus: failure is IsoDepReaderSessionExchangeException
                ? failure.rfStatus
                : null,
            wtxCount: failure is IsoDepReaderSessionExchangeException
                ? failure.wtxCount
                : null,
            firmwareSessionClosed: backend.firmwareSessionClosed,
            transitRewrite: transitRewrite,
            transitPolicyFailure: transitPolicyFailure,
            error: failure?.toString(),
          ),
        );
        if (_records.length > 100) _records.removeLast();
      });
    }
    if (failure != null || !delivered) {
      final uncertainty =
          backendApduStarted ||
          failure is ChameleonResponseTimeoutException ||
          failure is ChameleonCommandResponseUncertainException ||
          failure is TimeoutException;
      await _disarm(
        message: failure is _RelayPolicyRejected
            ? 'Apple Transit GPO was rejected locally: '
                  '${failure.failure.message}. No backend APDU was sent; the '
                  'terminal ${delivered ? 'received' : 'did not receive'} relay '
                  'fallback 6400.'
            : uncertainty
            ? failure == null
                  ? 'Backend/card state is uncertain because the terminal did '
                        'not accept the response after the backend APDU. The session '
                        'was reset; do not retry this APDU.'
                  : 'Backend/card state is uncertain after $failure. The session '
                        'was reset; do not retry this APDU.'
            : failure == null
            ? 'Terminal deadline expired before the response'
            : failure is IsoDepReaderSessionExchangeException
            ? '$failure during ${authorizedRelayApduSummary(command)}. '
                  'The terminal ${delivered ? 'received' : 'did not receive'} '
                  'relay fallback 6400; the APDU was not retried.'
            : 'Backend exchange failed: $failure',
      );
      return;
    }
    _hasForwardedApdu = true;
    _sessionDeliveredApdus++;
    if (mounted) {
      setState(() {
        _busy = _rendezvous?.phase == AuthorizedRelayRendezvousPhase.exchanging;
      });
    }
  }

  Future<void> _disarm({
    String? message,
    String? notice,
    bool updateUi = true,
  }) async {
    if (_disarming) {
      final completion = _disarmCompletion;
      if (completion != null) await completion.future;
      return;
    }
    _disarming = true;
    final completion = Completer<void>();
    _disarmCompletion = completion;
    _operationGeneration++;
    _backendPollDelay.reset();
    final token = _armToken;
    final backend = _rendezvous?.close();
    final preparedBackend = _preparedCapability?.invalidate();
    final cleanupCommunicator =
        backend?.communicator ??
        preparedBackend?.communicator ??
        _armedCommunicator ??
        _preparingCommunicator;
    final cleanupBarrier = cleanupCommunicator == null
        ? null
        : _connectionRegistry.beginCleanup(cleanupCommunicator);
    _preparedCapability = null;
    _preparedCoordinator = null;
    _rendezvous = null;
    _preparedBackendMode = null;
    _preparedCard = null;
    if (updateUi && mounted) {
      setState(() {
        _armed = false;
        _arming = false;
        _busy = true;
        if (message != null) {
          _error = message;
          _notice = null;
        } else if (notice != null) {
          _error = null;
          _notice = notice;
        }
      });
    }
    final cleanupErrors = <String>[];
    var backendResetFailed = false;
    try {
      await cleanupBarrier?.predecessor;
      if (token != null) {
        try {
          await _platform.setEnabled(false, armToken: token);
        } catch (error) {
          cleanupErrors.add('native disable failed: $error');
        }
      }

      final sessions = <_AuthorizedRelayBackend>{?backend, ?preparedBackend};
      for (final activeBackend in sessions) {
        activeBackend.policy.clear();
        try {
          await activeBackend.communicator.hf14a4ReaderSessionReset(
            activeBackend.session.sessionId,
          );
          activeBackend.firmwareSessionClosed = true;
        } catch (error) {
          backendResetFailed = true;
          _poisonConnection(
            activeBackend.communicator,
            'Backend session reset failed: $error',
          );
          cleanupErrors.add(
            'backend session ${activeBackend.session.sessionId} reset failed: '
            '$error',
          );
        }
      }
      await _refreshReadiness();
    } finally {
      if (_armToken == token) _armToken = null;
      _armedDeadlineMs = null;
      _armedCommunicator = null;
      _armedCoordinator = null;
      _armedBackendMode = null;
      _backendApdusInFlight.clear();
      _resumeMonitor();
      _disarming = false;
      if (updateUi && mounted) {
        setState(() {
          _busy = false;
          if (cleanupErrors.isNotEmpty) {
            final summary = message ?? notice;
            final prefix = summary == null ? '' : '$summary. ';
            _error =
                '${prefix}Relay cleanup incomplete: '
                '${cleanupErrors.join('; ')}. '
                '${backendResetFailed ? 'Reconnect before arming again' : 'Restart CU GUI before arming again'}; '
                'the Android payment service remains registered but disarmed.';
            _notice = null;
          }
        });
      }
      if (!completion.isCompleted) completion.complete();
      if (identical(_disarmCompletion, completion)) {
        _disarmCompletion = null;
      }
      cleanupBarrier?.complete();
    }
  }

  bool _isCurrentArm(
    int generation,
    int token,
    ChameleonCommunicator communicator,
  ) =>
      mounted &&
      generation == _operationGeneration &&
      token == _armToken &&
      _rendezvous?.armToken == token &&
      identical(communicator, _armedCommunicator) &&
      identical(communicator, _app?.communicator) &&
      _armedCoordinator?.connected == true &&
      _connected;

  void _ensureArmCurrent(
    int generation,
    int token,
    ChameleonCommunicator communicator,
  ) {
    if (!_isCurrentArm(generation, token, communicator)) {
      throw const _RelayOperationCancelled();
    }
  }

  void _ensurePreparedCurrent(
    AuthorizedRelaySessionCapability<
      _AuthorizedRelayBackend,
      ChameleonCommunicator
    >
    capability,
    int generation,
    ChameleonCommunicator communicator,
    AuthorizedRelayBackendMode mode,
    AuthorizedRelayConnectionCoordinator coordinator,
  ) {
    if (!mounted ||
        generation != _operationGeneration ||
        !identical(_preparedCapability, capability) ||
        !capability.available ||
        !capability.binding.matches(
          communicator: communicator,
          generation: coordinator.generation,
          mode: mode,
          sessionId: capability.binding.sessionId,
        ) ||
        !identical(_preparedCoordinator, coordinator) ||
        !coordinator.connected ||
        coordinator.poisoned ||
        !identical(communicator, _app?.communicator) ||
        !_connected) {
      throw const _RelayOperationCancelled();
    }
  }

  void _poisonConnection(ChameleonCommunicator communicator, String reason) {
    _connectionRegistry
        .forCommunicator(communicator)
        .poison('$reason. Reconnect the Chameleon before arming.');
  }

  Future<void> _pauseMonitor() async {
    if (_monitorPaused) return;
    _monitorPaused = true;
    await _app?.pauseEmulationChangeMonitor();
  }

  void _resumeMonitor() {
    if (!_monitorPaused) return;
    _monitorPaused = false;
    _app?.resumeEmulationChangeMonitor();
  }

  void _ensureCurrentOperation(int generation) {
    if (!mounted || generation != _operationGeneration) {
      throw const _RelayOperationCancelled();
    }
  }

  Future<void> _copyDebugLog() async {
    final communicator = _app?.communicator;
    final coordinator = communicator == null
        ? null
        : _connectionRegistry.forCommunicator(communicator);
    final card = _preparedCard;
    final report = <String, Object?>{
      'protocol': 'chameleon-authorized-relay-debug',
      'version': 3,
      'generatedAt': DateTime.now().toUtc().toIso8601String(),
      'state': <String, Object?>{
        'connected': _connected,
        'transport': communicator == null
            ? null
            : communicator.usesBleTransport
            ? 'BLE'
            : 'USB',
        'prepared': _prepared,
        'selectedBackendMode': _backendMode.name,
        'preparedBackendMode': _preparedBackendMode?.name,
        'armedBackendMode': _armedBackendMode?.name,
        'liveBackendSessionId':
            _preparedCapability?.binding.sessionId ??
            _rendezvous?.backend?.session.sessionId,
        'identityMetadataIsDiagnosticOnly': true,
        'reconnectRequired': coordinator?.poisoned ?? false,
        'connectionGeneration': coordinator?.generation,
        'armed': _armed,
        'arming': _arming,
        'busy': _busy,
        'relayPhase': _relayStateLabel,
        'armToken': _armToken,
        'armExpiry': 'none',
        'terminalDeadlineMs': _armedDeadlineMs ?? int.tryParse(_deadline.text),
        'deliveredApdus': _sessionDeliveredApdus,
        'backendApduInFlight': _backendApduInFlight,
        'error': _error,
        'notice': _notice,
      },
      'readiness': <String, Object?>{
        'hceSupported': _readiness.hceSupported,
        'nfcEnabled': _readiness.nfcEnabled,
        'deviceLocked': _readiness.deviceLocked,
        'isDefaultPaymentService': _readiness.isDefaultPaymentService,
        'registeredAids': _readiness.registeredAids,
      },
      'backend': card == null
          ? null
          : <String, Object?>{
              'uid': bytesToHex(card.uid).toUpperCase(),
              'atqa': bytesToHex(card.atqa).toUpperCase(),
              'sak': card.sak,
              'ats': bytesToHex(card.ats).toUpperCase(),
              'paymentAids': _paymentAids,
            },
      'records': [for (final record in _records) record.toJson()],
    };
    final text = const JsonEncoder.withIndent('  ').convert(report);
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Relay debug log copied')));
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context)!;
    final card = _preparedCard;
    final liveSessionId =
        _preparedCapability?.binding.sessionId ??
        _rendezvous?.backend?.session.sessionId;
    return Scaffold(
      appBar: AppBar(title: Text(localizations.authorized_relay_title)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            color: Theme.of(context).colorScheme.errorContainer,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Text(
                _backendMode == AuthorizedRelayBackendMode.appleTransit
                    ? localizations.authorized_relay_apple_warning
                    : localizations.authorized_relay_warning,
              ),
            ),
          ),
          const Card(
            child: Padding(
              padding: EdgeInsets.all(14),
              child: Text(
                'SETUP ORDER\n'
                '1. Open Payment settings and select "CU GUI Authorized Relay".\n'
                '2. Connect the Ultra and place the backend card on it.\n'
                '3. Turn on Arm. CU GUI acquires the backend and starts HCE '
                'without a separate preparation or approval prompt.\n\n'
                'The payment service and its latest payment AIDs stay registered '
                'after the test. While disarmed, terminal APDUs are rejected.',
              ),
            ),
          ),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'READINESS',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  _statusRow('Chameleon Ultra connected', _connected),
                  _statusRow('Android payment HCE', _readiness.hceSupported),
                  _statusRow('NFC enabled', _readiness.nfcEnabled),
                  _statusRow('Device unlocked', !_readiness.deviceLocked),
                  _statusRow(
                    'CU GUI is contactless default',
                    _readiness.isDefaultPaymentService,
                  ),
                  _statusRow('Backend card prepared', _prepared),
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text('Backend profile: $_backendModeLabel'),
                  ),
                  if (_app?.communicator?.usesBleTransport == true)
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Text(
                        'BLE adds latency. Validate with USB first.',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                ],
              ),
            ),
          ),
          if (card != null)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      localizations.authorized_relay_identity_diagnostic,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 8),
                    if (liveSessionId != null)
                      Text('Firmware session: $liveSessionId'),
                    Text('Backend UID: ${bytesToHex(card.uid).toUpperCase()}'),
                    Text('ATQA: ${bytesToHex(card.atqa).toUpperCase()}'),
                    Text(
                      'SAK: ${card.sak.toRadixString(16).padLeft(2, '0').toUpperCase()}',
                    ),
                    Text('ATS: ${bytesToHex(card.ats).toUpperCase()}'),
                    const SizedBox(height: 6),
                    const Text('Registered payment AIDs:'),
                    for (final aid in _paymentAids)
                      SelectableText(
                        aid,
                        style: const TextStyle(fontFamily: 'RobotoMono'),
                      ),
                  ],
                ),
              ),
            ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _backendMode == AuthorizedRelayBackendMode.appleTransit,
            onChanged: _busy || _armActive
                ? null
                : (enabled) => unawaited(
                    _setBackendMode(
                      enabled
                          ? AuthorizedRelayBackendMode.appleTransit
                          : AuthorizedRelayBackendMode.transparent,
                    ),
                  ),
            title: const Text('Apple Transit backend profile'),
            subtitle: const Text(
              'Remains selected until disabled: firmware ECP2 activation plus strict GPO '
              'rewriting of TTQ 33804000, terminal type 14 and capabilities '
              'E00800. Missing or malformed PDOL stops the relay.',
            ),
          ),
          TextField(
            controller: _deadline,
            enabled: !_armed && !_busy,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Terminal response deadline',
              suffixText: 'ms',
              border: OutlineInputBorder(),
            ),
          ),
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text(
              'Android cannot force terminal WTX. If the phone arrives first, '
              'card acquisition and exchange must finish inside the terminal '
              'and native deadline.',
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (_waitingForCard)
                OutlinedButton.icon(
                  onPressed: _cancelCardWaitRequested ? null : _cancelCardWait,
                  icon: const Icon(Icons.cancel),
                  label: Text(
                    _cancelCardWaitRequested
                        ? 'Cancelling...'
                        : 'Cancel waiting',
                  ),
                ),
              OutlinedButton.icon(
                onPressed: _openPaymentSettings,
                icon: const Icon(Icons.account_balance_wallet),
                label: const Text('1. Select payment service'),
              ),
            ],
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _armed,
            onChanged: _busy || (!_connected && !_armed) ? null : _setArmed,
            title: Text(localizations.authorized_relay_arm),
            subtitle: Text(
              _relayStateLabel ??
                  (_prepared
                      ? localizations.authorized_relay_prepared_hint
                      : localizations.authorized_relay_arm_hint),
            ),
          ),
          if (_relayStateLabel != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                _relayStateLabel!,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          if (_busy) const LinearProgressIndicator(),
          if (_waitingForCard)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                'Waiting for a backend card. Once detected, CU GUI will acquire '
                'the live firmware session and arm HCE automatically.',
              ),
            ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          if (_notice != null)
            Card(
              color: Theme.of(context).colorScheme.primaryContainer,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(_notice!),
              ),
            ),
          const Divider(),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Relayed APDUs (${_records.length})',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              IconButton(
                onPressed: _copyDebugLog,
                tooltip: 'Copy relay debug log',
                icon: const Icon(Icons.copy),
              ),
            ],
          ),
          const Text(
            'Only APDU headers and status words are retained in memory.',
          ),
          for (final record in _records)
            ListTile(
              dense: true,
              leading: Icon(
                record.delivered && record.error == null
                    ? Icons.check_circle
                    : Icons.cancel,
                color: record.delivered && record.error == null
                    ? Colors.green
                    : Colors.red,
              ),
              title: Text(
                '${record.command} -> ${record.status} | '
                '${(record.elapsedUs / 1000).toStringAsFixed(2)} ms'
                '${record.transitRewrite == null ? '' : ' | Apple Transit GPO'}'
                '${record.syntheticFallback ? ' | relay fallback' : ''}'
                '${record.prefetchedBackendResponse ? ' | prefetched backend' : ''}',
              ),
              subtitle:
                  record.error == null && record.transitPolicyFailure == null
                  ? null
                  : Text(
                      [
                        if (record.transitPolicyFailure != null)
                          'Transit policy: '
                              '${record.transitPolicyFailure!.message}',
                        if (record.error != null) record.error!,
                      ].join('\n'),
                    ),
            ),
        ],
      ),
    );
  }

  Widget _statusRow(String label, bool ready) => Row(
    children: [
      Icon(
        ready ? Icons.check_circle : Icons.cancel,
        color: ready ? Colors.green : Colors.red,
        size: 18,
      ),
      const SizedBox(width: 8),
      Expanded(child: Text(label)),
    ],
  );
}

class _AuthorizedRelayRecord {
  const _AuthorizedRelayRecord({
    required this.armToken,
    required this.requestId,
    required this.receivedUs,
    required this.expiresAtUs,
    required this.backendSessionId,
    required this.terminalBudgetUs,
    required this.backendMode,
    required this.command,
    required this.status,
    required this.elapsedUs,
    required this.backendExchangeUs,
    required this.nativeDeliveryUs,
    required this.delivered,
    required this.syntheticFallback,
    required this.prefetchedBackendResponse,
    required this.deviceStatus,
    required this.isoDepError,
    required this.rfStatus,
    required this.wtxCount,
    required this.firmwareSessionClosed,
    required this.transitRewrite,
    required this.transitPolicyFailure,
    required this.error,
  });

  final int armToken;
  final int requestId;
  final int? receivedUs;
  final int? expiresAtUs;
  final int backendSessionId;
  final int? terminalBudgetUs;
  final AuthorizedRelayBackendMode backendMode;
  final String command;
  final String status;
  final int elapsedUs;
  final int? backendExchangeUs;
  final int? nativeDeliveryUs;
  final bool delivered;
  final bool syntheticFallback;
  final bool prefetchedBackendResponse;
  final int? deviceStatus;
  final int? isoDepError;
  final int? rfStatus;
  final int? wtxCount;
  final bool firmwareSessionClosed;
  final AuthorizedRelayGpoRewriteEvidence? transitRewrite;
  final AuthorizedRelayPolicyFailure? transitPolicyFailure;
  final String? error;

  Map<String, Object?> toJson() => {
    'armToken': armToken,
    'requestId': requestId,
    'receivedUs': receivedUs,
    'expiresAtUs': expiresAtUs,
    'backendSessionId': backendSessionId,
    'terminalBudgetUs': terminalBudgetUs,
    'backendMode': backendMode.name,
    'command': command,
    'status': status,
    'elapsedUs': elapsedUs,
    'backendExchangeUs': backendExchangeUs,
    'nativeDeliveryUs': nativeDeliveryUs,
    'delivered': delivered,
    'responseSource': syntheticFallback
        ? 'relayFallback'
        : prefetchedBackendResponse
        ? 'backendPrefetch'
        : 'backend',
    'deviceStatus': deviceStatus,
    'isoDepError': isoDepError,
    'rfStatus': rfStatus,
    'wtxCount': wtxCount,
    'firmwareSessionClosed': firmwareSessionClosed,
    'transitRewrite': transitRewrite?.toJson(),
    'transitPolicy': transitPolicyFailure?.toJson(),
    'error': error,
  };
}

class _AuthorizedRelayBackend {
  _AuthorizedRelayBackend(
    this.communicator,
    this.session,
    this.mode, {
    this._prefetchedResponse,
  }) : policy = AuthorizedRelaySessionPolicy(mode: mode);

  final ChameleonCommunicator communicator;
  final IsoDepReaderSessionInfo session;
  final AuthorizedRelayBackendMode mode;
  final AuthorizedRelaySessionPolicy policy;
  final AuthorizedRelayPrefetchedResponse? _prefetchedResponse;
  bool firmwareSessionClosed = false;

  Uint8List? takePrefetchedResponse(Uint8List command) =>
      _prefetchedResponse?.takeFor(command);
}

class _RelayOperationCancelled implements Exception {
  const _RelayOperationCancelled();
}

class _RelayReconnectRequired implements Exception {
  const _RelayReconnectRequired(this.message);

  final String message;
}

class _RelayPolicyRejected implements Exception {
  const _RelayPolicyRejected(this.failure);

  final AuthorizedRelayPolicyFailure failure;

  @override
  String toString() => failure.message;
}

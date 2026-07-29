import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:chameleonultragui/helpers/data_sync.dart';
import 'package:chameleonultragui/helpers/data_sync_transport.dart';
import 'package:chameleonultragui/sharedprefsprovider.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  SyncSnapshot snapshot(String owner) =>
      SyncSnapshot(settings: {'owner': owner, 'revision': 1});

  group('encrypted bundle v1', () {
    test('round trips and rejects a wrong password', () async {
      final encoded = await DataSyncBundleCodec.encode(
        snapshot('local'),
        'secret',
      );
      final decoded = await DataSyncBundleCodec.decode(encoded, 'secret');

      expect(DataSyncBundleCodec.version, 1);
      expect(decoded.settings, {'owner': 'local', 'revision': 1});
      await expectLater(
        DataSyncBundleCodec.decode(encoded, 'wrong'),
        throwsFormatException,
      );
    });

    test('rejects authenticated metadata and ciphertext tampering', () async {
      final encoded = await DataSyncBundleCodec.encode(
        snapshot('local'),
        'secret',
      );
      final metadataTamper = Uint8List.fromList(encoded)..[9] = 15;
      final cipherTamper = Uint8List.fromList(encoded)
        ..[encoded.length - 17] ^= 1;

      await expectLater(
        DataSyncBundleCodec.decode(metadataTamper, 'secret'),
        throwsFormatException,
      );
      await expectLater(
        DataSyncBundleCodec.decode(cipherTamper, 'secret'),
        throwsFormatException,
      );
    });
  });

  test('pairing parser requires explicit peer protocol v2', () async {
    final participant = _MemoryParticipant(snapshot('host'));
    final host = await DataSyncPeerHost.start(
      localState: participant.state,
      participant: participant,
      onApprove: (_) => true,
      addressOverride: InternetAddress.loopbackIPv4,
    );
    addTearDown(host.dispose);

    final pairing = DataSyncPairingCode.parse(host.pairingCode);
    expect(pairing.address.address, '127.0.0.1');
    expect(pairing.port, host.port);
    expect(pairing.key, hasLength(32));
    expect(pairing.encode(), host.pairingCode);
    expect(host.pairingCode, contains('/v2?'));
    expect(
      () => DataSyncPairingCode.parse(
        host.pairingCode.replaceFirst('/v2?', '/v1?'),
      ),
      throwsFormatException,
    );
    expect(
      () => DataSyncPairingCode.parse(
        host.pairingCode.replaceFirst('cusync:', 'https:'),
      ),
      throwsFormatException,
    );
    expect(
      () => DataSyncPairingCode.parse('${host.pairingCode}&port=2'),
      throwsFormatException,
    );
  });

  for (final accepted in [true, false]) {
    test(
      'v2 loopback transaction is ${accepted ? 'committed' : 'rejected'}',
      () async {
        final hostParticipant = _MemoryParticipant(snapshot('host'));
        final clientParticipant = _MemoryParticipant(snapshot('client'));
        final statuses = <DataSyncHostStatus>[];
        final host = await DataSyncPeerHost.start(
          localState: hostParticipant.state,
          participant: hostParticipant,
          onApprove: (_) => accepted,
          onStatus: statuses.add,
          addressOverride: InternetAddress.loopbackIPv4,
        );
        addTearDown(host.dispose);

        final exchange = await DataSyncPeerClient.connect(
          pairingCode: host.pairingCode,
          localState: clientParticipant.state,
          participant: clientParticipant,
        );
        expect(exchange.remoteSnapshot.settings['owner'], 'host');
        expect(await exchange.complete(snapshot('merged')), accepted);
        await host.done;

        expect(
          hostParticipant.applied?.settings['owner'],
          accepted ? 'merged' : isNull,
        );
        expect(
          clientParticipant.applied?.settings['owner'],
          accepted ? 'merged' : isNull,
        );
        expect(statuses, contains(DataSyncHostStatus.receivedSnapshot));
        expect(
          statuses,
          contains(
            accepted
                ? DataSyncHostStatus.accepted
                : DataSyncHostStatus.rejected,
          ),
        );
      },
    );
  }

  test('human conflict review may outlive the network I/O timeout', () async {
    final hostParticipant = _MemoryParticipant(snapshot('host'));
    final clientParticipant = _MemoryParticipant(snapshot('client'));
    final host = await DataSyncPeerHost.start(
      localState: hostParticipant.state,
      participant: hostParticipant,
      onApprove: (_) async {
        await Future<void>.delayed(const Duration(milliseconds: 100));
        return true;
      },
      addressOverride: InternetAddress.loopbackIPv4,
      timeout: const Duration(milliseconds: 50),
      interactionTimeout: const Duration(seconds: 1),
    );
    addTearDown(host.dispose);

    final exchange = await DataSyncPeerClient.connect(
      pairingCode: host.pairingCode,
      localState: clientParticipant.state,
      participant: clientParticipant,
      timeout: const Duration(milliseconds: 50),
      interactionTimeout: const Duration(seconds: 1),
    );
    await Future<void>.delayed(const Duration(milliseconds: 100));

    expect(await exchange.complete(snapshot('merged')), isTrue);
  });

  test('lost ACK is recovered by QUERY without duplicate commit', () async {
    final hostParticipant = _MemoryParticipant(snapshot('host'));
    final clientParticipant = _MemoryParticipant(snapshot('client'));
    final host = await DataSyncPeerHost.start(
      localState: hostParticipant.state,
      participant: hostParticipant,
      onApprove: (_) => true,
      addressOverride: InternetAddress.loopbackIPv4,
      interactionTimeout: const Duration(seconds: 2),
      debugDisconnectAfterCommit: true,
    );
    addTearDown(host.dispose);
    final exchange = await DataSyncPeerClient.connect(
      pairingCode: host.pairingCode,
      localState: clientParticipant.state,
      participant: clientParticipant,
      interactionTimeout: const Duration(seconds: 2),
    );

    expect(await exchange.complete(snapshot('merged')), isTrue);
    await host.done;

    expect(hostParticipant.commitCalls, 1);
    expect(clientParticipant.commitCalls, 1);
    expect(hostParticipant.applied?.settings['owner'], 'merged');
  });

  test(
    'pre-auth oversized frame closes only attacker and host still works',
    () async {
      final participant = _MemoryParticipant(snapshot('host'));
      final clientParticipant = _MemoryParticipant(snapshot('client'));
      final statuses = <DataSyncHostStatus>[];
      final host = await DataSyncPeerHost.start(
        localState: participant.state,
        participant: participant,
        onApprove: (_) => true,
        onStatus: statuses.add,
        addressOverride: InternetAddress.loopbackIPv4,
        timeout: const Duration(seconds: 2),
      );
      final pairing = DataSyncPairingCode.parse(host.pairingCode);
      final socket = await Socket.connect(pairing.address, pairing.port);
      socket.add(
        Uint8List(4)..buffer.asByteData().setUint32(0, 0xffffffff, Endian.big),
      );
      await socket.flush();
      await Future<void>.delayed(const Duration(milliseconds: 30));

      expect(statuses, contains(DataSyncHostStatus.listening));
      final exchange = await DataSyncPeerClient.connect(
        pairingCode: host.pairingCode,
        localState: clientParticipant.state,
        participant: clientParticipant,
      );
      expect(await exchange.complete(snapshot('merged')), isTrue);
      await host.done;
      expect(statuses, contains(DataSyncHostStatus.accepted));
      socket.destroy();
      await host.dispose();
    },
  );

  test('pre-auth failures apply bounded temporary admission backoff', () async {
    final hostParticipant = _MemoryParticipant(snapshot('host'));
    final host = await DataSyncPeerHost.start(
      localState: hostParticipant.state,
      participant: hostParticipant,
      onApprove: (_) => true,
      addressOverride: InternetAddress.loopbackIPv4,
      timeout: const Duration(milliseconds: 200),
      debugMaxPreAuthFailures: 2,
      debugPreAuthBackoff: const Duration(milliseconds: 100),
    );
    addTearDown(host.dispose);
    final pairing = DataSyncPairingCode.parse(host.pairingCode);

    for (var attempt = 0; attempt < 2; attempt++) {
      final attacker = await Socket.connect(pairing.address, pairing.port);
      attacker.add(
        Uint8List(4)..buffer.asByteData().setUint32(0, 0xffffffff, Endian.big),
      );
      await attacker.flush();
      attacker.destroy();
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }

    final blocked = _MemoryParticipant(snapshot('blocked'));
    await expectLater(
      DataSyncPeerClient.connect(
        pairingCode: host.pairingCode,
        localState: blocked.state,
        participant: blocked,
        timeout: const Duration(milliseconds: 100),
      ),
      throwsA(anything),
    );
    await Future<void>.delayed(const Duration(milliseconds: 120));
    final client = _MemoryParticipant(snapshot('client'));
    final exchange = await DataSyncPeerClient.connect(
      pairingCode: host.pairingCode,
      localState: client.state,
      participant: client,
    );
    expect(await exchange.complete(snapshot('merged')), isTrue);
  });

  test('decided coordinator resumes through an explicit new pairing', () async {
    final merged = snapshot('merged');
    final hostParticipant = _MemoryParticipant(snapshot('host'));
    final clientParticipant = _MemoryParticipant(snapshot('client'));
    const transactionId = 'restart-resume';
    final targetHash = _snapshotHash(merged);
    await hostParticipant.prepare(
      transactionId,
      merged,
      hostParticipant.state.checkpoint,
      claimedTargetHash: targetHash,
    );
    await clientParticipant.prepare(
      transactionId,
      merged,
      clientParticipant.state.checkpoint,
      role: SyncTransactionRole.coordinator,
      peerCheckpoint: hostParticipant.state.checkpoint,
    );
    await clientParticipant.commit(transactionId);
    final recovery = (await clientParticipant.coordinatorRecovery())!;

    final restartedHost = await DataSyncPeerHost.start(
      localState: hostParticipant.state,
      participant: hostParticipant,
      onApprove: (_) => fail('resume must not request approval again'),
      addressOverride: InternetAddress.loopbackIPv4,
    );
    addTearDown(restartedHost.dispose);
    expect(restartedHost.status, DataSyncHostStatus.awaitingApproval);

    await DataSyncPeerClient.resumeCommitted(
      pairingCode: restartedHost.pairingCode,
      recovery: recovery,
      participant: clientParticipant,
    );
    await restartedHost.done;

    expect(hostParticipant.applied?.settings['owner'], 'merged');
    expect(hostParticipant.commitCalls, 1);
    expect(await clientParticipant.coordinatorRecovery(), isNull);
  });

  test('lost ABORT survives restart and resumes through new pairing', () async {
    final merged = snapshot('merged');
    final hostParticipant = _MemoryParticipant(snapshot('host'));
    final clientParticipant = _MemoryParticipant(snapshot('client'));
    const transactionId = 'restart-abort';
    final targetHash = _snapshotHash(merged);
    await hostParticipant.prepare(
      transactionId,
      merged,
      hostParticipant.state.checkpoint,
      claimedTargetHash: targetHash,
    );
    await clientParticipant.prepare(
      transactionId,
      merged,
      clientParticipant.state.checkpoint,
      role: SyncTransactionRole.coordinator,
      peerCheckpoint: hostParticipant.state.checkpoint,
    );
    final recovery = await clientParticipant.decideCoordinatorAbort(
      transactionId,
    );

    final restartedHost = await DataSyncPeerHost.start(
      localState: hostParticipant.state,
      participant: hostParticipant,
      onApprove: (_) => fail('abort resume must not request approval'),
      addressOverride: InternetAddress.loopbackIPv4,
    );
    addTearDown(restartedHost.dispose);

    await DataSyncPeerClient.resumePending(
      pairingCode: restartedHost.pairingCode,
      recovery: recovery,
      participant: clientParticipant,
    );
    await restartedHost.done;

    expect(
      (await hostParticipant.query(transactionId))?.outcome,
      SyncTransactionOutcome.aborted,
    );
    expect(hostParticipant.applied, isNull);
    expect(await clientParticipant.coordinatorRecovery(), isNull);
  });

  test(
    'host ABORT of an already committed transaction returns committed ACK',
    () async {
      final hostParticipant = _MemoryParticipant(
        snapshot('host'),
        commitOnAbort: true,
      );
      final clientParticipant = _MemoryParticipant(
        snapshot('client'),
        failCommitBeforeDecision: true,
      );
      final host = await DataSyncPeerHost.start(
        localState: hostParticipant.state,
        participant: hostParticipant,
        onApprove: (_) => true,
        addressOverride: InternetAddress.loopbackIPv4,
      );
      addTearDown(host.dispose);
      final exchange = await DataSyncPeerClient.connect(
        pairingCode: host.pairingCode,
        localState: clientParticipant.state,
        participant: clientParticipant,
      );

      await expectLater(
        exchange.complete(snapshot('merged')),
        throwsA(anything),
      );
      await host.done;

      expect(host.status, DataSyncHostStatus.accepted);
      expect(hostParticipant.applied?.settings['owner'], 'merged');
    },
  );

  test('host binds claimed hash before durable PREPARE', () async {
    final hostParticipant = _MemoryParticipant(snapshot('host'));
    final clientParticipant = _MemoryParticipant(
      snapshot('client'),
      targetHashOverride: '0' * 64,
    );
    final host = await DataSyncPeerHost.start(
      localState: hostParticipant.state,
      participant: hostParticipant,
      onApprove: (_) => true,
      addressOverride: InternetAddress.loopbackIPv4,
      timeout: const Duration(milliseconds: 100),
    );
    addTearDown(host.dispose);
    final exchange = await DataSyncPeerClient.connect(
      pairingCode: host.pairingCode,
      localState: clientParticipant.state,
      participant: clientParticipant,
      timeout: const Duration(milliseconds: 100),
      interactionTimeout: const Duration(milliseconds: 200),
    );

    await expectLater(exchange.complete(snapshot('merged')), throwsA(anything));

    expect(hostParticipant.preparedWrites, 0);
  });

  test('stop closes a listening host and is idempotent', () async {
    final participant = _MemoryParticipant(snapshot('host'));
    final host = await DataSyncPeerHost.start(
      localState: participant.state,
      participant: participant,
      onApprove: (_) => true,
      addressOverride: InternetAddress.loopbackIPv4,
    );
    final pairing = DataSyncPairingCode.parse(host.pairingCode);

    await host.stop();
    await host.stop();
    await host.done;
    await expectLater(
      Socket.connect(pairing.address, pairing.port),
      throwsA(isA<SocketException>()),
    );
  });
}

class _MemoryParticipant implements DataSyncTransactionParticipant {
  final Map<String, SyncTransactionReceipt> _receipts = {};
  final Map<String, SyncSnapshot> _staged = {};
  final Map<String, SyncTransactionRole> _roles = {};
  late SyncCheckpoint _checkpoint;
  SyncCoordinatorRecovery? _coordinator;
  final SyncSnapshot initialSnapshot;
  final bool commitOnAbort;
  final bool failCommitBeforeDecision;
  final String? targetHashOverride;
  SyncSnapshot? applied;
  int commitCalls = 0;
  int preparedWrites = 0;
  bool _commitFailureInjected = false;

  _MemoryParticipant(
    this.initialSnapshot, {
    this.commitOnAbort = false,
    this.failCommitBeforeDecision = false,
    this.targetHashOverride,
  }) {
    _checkpoint = SyncCheckpoint(
      revision: 0,
      stateHash: _snapshotHash(initialSnapshot),
    );
  }

  SyncState get state =>
      SyncState(snapshot: initialSnapshot, checkpoint: _checkpoint);

  @override
  Future<SyncTransactionReceipt> prepare(
    String transactionId,
    SyncSnapshot snapshot,
    SyncCheckpoint expectedCheckpoint, {
    SyncTransactionRole role = SyncTransactionRole.participant,
    SyncCheckpoint? peerCheckpoint,
    String? claimedTargetHash,
  }) async {
    final existing = _receipts[transactionId];
    final actualTargetHash = _snapshotHash(snapshot);
    if (claimedTargetHash != null && claimedTargetHash != actualTargetHash) {
      throw const FormatException('claimed target hash mismatch');
    }
    final targetHash = targetHashOverride ?? actualTargetHash;
    if (existing != null) {
      if (existing.targetHash != targetHash) {
        throw StateError('transaction ID reused');
      }
      return existing;
    }
    if (expectedCheckpoint != _checkpoint) {
      throw SyncCheckpointConflict(expectedCheckpoint, _checkpoint);
    }
    preparedWrites++;
    _staged[transactionId] = snapshot;
    _roles[transactionId] = role;
    if (role == SyncTransactionRole.coordinator) {
      _coordinator = SyncCoordinatorRecovery(
        transactionId: transactionId,
        targetHash: targetHash,
        decision: SyncCoordinatorDecision.prepared,
        peerCheckpoint: peerCheckpoint!,
      );
    }
    return _receipts[transactionId] = SyncTransactionReceipt(
      transactionId: transactionId,
      outcome: SyncTransactionOutcome.prepared,
      targetHash: targetHash,
      checkpoint: _checkpoint,
    );
  }

  @override
  Future<SyncTransactionReceipt> commit(String transactionId) async {
    final receipt = _receipts[transactionId];
    if (receipt == null) throw StateError('transaction is not prepared');
    if (receipt.outcome == SyncTransactionOutcome.committed) return receipt;
    if (receipt.outcome == SyncTransactionOutcome.aborted) return receipt;
    if (failCommitBeforeDecision && !_commitFailureInjected) {
      _commitFailureInjected = true;
      throw StateError('simulated local commit failure');
    }
    if (_roles[transactionId] == SyncTransactionRole.coordinator) {
      _coordinator = _coordinator!.withDecision(
        SyncCoordinatorDecision.commitDecided,
      );
    }
    commitCalls++;
    applied = _staged.remove(transactionId);
    _checkpoint = SyncCheckpoint(
      revision: _checkpoint.revision + 1,
      stateHash: receipt.targetHash,
    );
    return _receipts[transactionId] = SyncTransactionReceipt(
      transactionId: transactionId,
      outcome: SyncTransactionOutcome.committed,
      targetHash: receipt.targetHash,
      checkpoint: _checkpoint,
    );
  }

  @override
  Future<SyncTransactionReceipt> abortFromCoordinator(
    String transactionId,
    String targetHash,
  ) async {
    final receipt = _receipts[transactionId];
    if (receipt == null) throw StateError('transaction is not prepared');
    if (receipt.targetHash != targetHash) {
      throw StateError('transaction target does not match');
    }
    if (commitOnAbort) return commit(transactionId);
    if (_coordinator?.transactionId == transactionId &&
        _coordinator?.decision == SyncCoordinatorDecision.commitDecided) {
      return commit(transactionId);
    }
    if (receipt.outcome != SyncTransactionOutcome.prepared) return receipt;
    _staged.remove(transactionId);
    return _receipts[transactionId] = SyncTransactionReceipt(
      transactionId: transactionId,
      outcome: SyncTransactionOutcome.aborted,
      targetHash: receipt.targetHash,
      checkpoint: _checkpoint,
    );
  }

  @override
  Future<SyncTransactionReceipt> reject(
    String transactionId,
    String targetHash,
  ) async {
    final existing = _receipts[transactionId];
    if (existing != null) return existing;
    return _receipts[transactionId] = SyncTransactionReceipt(
      transactionId: transactionId,
      outcome: SyncTransactionOutcome.aborted,
      targetHash: targetHash,
      checkpoint: _checkpoint,
    );
  }

  @override
  Future<SyncTransactionReceipt?> query(String transactionId) async =>
      _receipts[transactionId];

  @override
  Future<SyncCoordinatorRecovery?> coordinatorRecovery() async => _coordinator;

  @override
  Future<SyncCoordinatorRecovery> decideCoordinatorAbort(
    String transactionId,
  ) async {
    final coordinator = _coordinator;
    if (coordinator == null || coordinator.transactionId != transactionId) {
      throw StateError('coordinator transaction is missing');
    }
    if (coordinator.decision == SyncCoordinatorDecision.commitDecided) {
      throw StateError('commit is already decided');
    }
    final recovery = coordinator.withDecision(
      SyncCoordinatorDecision.abortDecided,
    );
    _coordinator = recovery;
    await abortFromCoordinator(transactionId, recovery.targetHash);
    return recovery;
  }

  @override
  Future<void> completeCoordinator(String transactionId) async {
    if (_coordinator?.transactionId == transactionId) _coordinator = null;
  }

  @override
  Future<SyncTransactionReceipt?> pendingParticipant() async {
    for (final entry in _receipts.entries) {
      if (_roles[entry.key] == SyncTransactionRole.participant &&
          entry.value.outcome == SyncTransactionOutcome.prepared) {
        return entry.value;
      }
    }
    return null;
  }
}

String _snapshotHash(SyncSnapshot snapshot) =>
    sha256.convert(utf8.encode(snapshot.toJson())).toString();

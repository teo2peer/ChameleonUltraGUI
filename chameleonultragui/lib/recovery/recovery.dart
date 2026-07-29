import 'dart:async';
import 'dart:core';
import 'dart:ffi';
import 'dart:io' as io;
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:chameleonultragui/helpers/general.dart';
import 'package:dylib/dylib.dart';
import 'bindings.dart';
import 'package:ffi/ffi.dart';
import 'dart:ffi' as ffi;
import 'package:logger/logger.dart';

class DarksideItemDart {
  int nt1;
  int ks1;
  int par;
  int nr;
  int ar;

  DarksideItemDart(
      {required this.nt1,
      required this.ks1,
      required this.par,
      required this.nr,
      required this.ar});
}

class DarksideDart {
  int uid;
  List<DarksideItemDart> items;

  DarksideDart({required this.uid, required this.items});
}

class NestedDart {
  int uid;
  int distance;
  int nt0;
  int nt0Enc;
  int par0;
  int nt1;
  int nt1Enc;
  int par1;

  NestedDart(
      {required this.uid,
      required this.distance,
      required this.nt0,
      required this.nt0Enc,
      required this.par0,
      required this.nt1,
      required this.nt1Enc,
      required this.par1});
}

class StaticNestedDart {
  int uid;
  int keyType;
  int nt0;
  int nt0Enc;
  int nt1;
  int nt1Enc;

  StaticNestedDart(
      {required this.uid,
      required this.keyType,
      required this.nt0,
      required this.nt0Enc,
      required this.nt1,
      required this.nt1Enc});
}

class StaticEncryptedNestedDart {
  int uid;
  int nt;
  int ntEnc;
  int ntParEnc;

  StaticEncryptedNestedDart(
      {required this.uid,
      required this.nt,
      required this.ntEnc,
      required this.ntParEnc});
}

class HardNestedDart {
  Uint8List nonces;

  HardNestedDart({required this.nonces});
}

class Mfkey32Dart {
  int uid;
  int nt0;
  int nt1;
  int nr0Enc;
  int ar0Enc;
  int nr1Enc;
  int ar1Enc;

  Mfkey32Dart(
      {required this.uid,
      required this.nt0,
      required this.nt1,
      required this.nr0Enc,
      required this.ar0Enc,
      required this.nr1Enc,
      required this.ar1Enc});
}

class Mfkey64Dart {
  int uid;
  int nt;
  int nrEnc;
  int arEnc;
  int atEnc;

  Mfkey64Dart(
      {required this.uid,
      required this.nt,
      required this.nrEnc,
      required this.arEnc,
      required this.atEnc});
}

Future<List<int>> darkside(DarksideDart darkside) async {
  return _sendRecoveryRequest(
      (int requestId) => DarksideRequest(requestId, darkside));
}

Future<List<int>> nested(NestedDart nested) async {
  return _sendRecoveryRequest(
      (int requestId) => NestedRequest(requestId, nested));
}

Future<List<int>> hardNested(HardNestedDart nested) async {
  return _sendRecoveryRequest(
    (int requestId) => HardNestedRequest(requestId, nested),
    timeout: const Duration(minutes: 30),
  );
}

Future<List<int>> staticNested(StaticNestedDart nested) async {
  return _sendRecoveryRequest(
      (int requestId) => StaticNestedRequest(requestId, nested));
}

Future<List<int>> staticEncryptedNested(
    StaticEncryptedNestedDart nested) async {
  return _sendRecoveryRequest(
      (int requestId) => StaticEncryptedNestedRequest(requestId, nested));
}

Future<List<int>> mfkey32(Mfkey32Dart mfkey) async {
  return _sendRecoveryRequest(
      (int requestId) => Mfkey32Request(requestId, mfkey));
}

Future<List<int>> mfkey64(Mfkey64Dart mfkey) async {
  return _sendRecoveryRequest(
      (int requestId) => Mfkey64Request(requestId, mfkey));
}

String resolvePath() {
  String path = resolveDylibPath(
    'recovery',
    dartDefine: 'LIBRECOVERY_PATH',
    environmentVariable: 'LIBRECOVERY_PATH',
  );
  if (!io.File(path).existsSync() &&
      Platform.environment.containsKey('FLUTTER_TEST')) {
    Logger log = Logger();
    log.d("Library test hotfix: Library not exists");
    Directory dir = Directory('build/${platformToPath()}');
    for (var f in dir.listSync(recursive: true).toList()) {
      if (f.path.endsWith(path)) {
        log.e(
            "THIS HOTFIX IS ONLY FOR TESTS. IF YOU SEE THIS LINE ON DEBUG/RELEASE BUILDS REPORT IT IMMEDIATELY.");
        log.e("THIS WILL LEAD TO HIGH SECURITY VULNERABILITY.");
        log.e("Library test hotfix: found at ${f.path}");
        path = f.path;
        break;
      }
    }
  } else if (!io.File(path).existsSync() &&
      (Platform.isMacOS || Platform.isIOS)) {
    return 'recovery.framework/recovery';
  }
  return path;
}

/// The bindings to the native functions in [_dylib].
final Recovery _bindings = Recovery(ffi.DynamicLibrary.open(resolvePath()));

class DarksideRequest {
  final int id;
  final DarksideDart darkside;

  const DarksideRequest(this.id, this.darkside);
}

class NestedRequest {
  final int id;
  final NestedDart nested;

  const NestedRequest(this.id, this.nested);
}

class StaticNestedRequest {
  final int id;
  final StaticNestedDart nested;

  const StaticNestedRequest(this.id, this.nested);
}

class HardNestedRequest {
  final int id;
  final HardNestedDart nested;

  const HardNestedRequest(this.id, this.nested);
}

class StaticEncryptedNestedRequest {
  final int id;
  final StaticEncryptedNestedDart nested;

  const StaticEncryptedNestedRequest(this.id, this.nested);
}

class Mfkey32Request {
  final int id;
  final Mfkey32Dart mfkey32;

  const Mfkey32Request(this.id, this.mfkey32);
}

class Mfkey64Request {
  final int id;
  final Mfkey64Dart mfkey64;

  const Mfkey64Request(this.id, this.mfkey64);
}

/// A response with the result of `sum`.
///
/// Typically sent from one isolate to another.
class KeyResponse {
  final int id;
  final List<int> result;

  const KeyResponse(this.id, this.result);
}

/// Counter to identify requests and [Response]s.
int _nextSumRequestId = 0;

/// Mapping from request `id`s to the completers corresponding to the correct future of the pending request.
final Map<int, Completer<List<int>>> requests = <int, Completer<List<int>>>{};
final Map<int, Timer> _requestTimeouts = <int, Timer>{};
const Duration _recoveryRequestTimeout = Duration(minutes: 5);
const Duration _workerStartupTimeout = Duration(seconds: 10);
Object? _helperIsolateFailure;
Isolate? _recoveryWorkerIsolate;
void Function(Object, [StackTrace?])? _failRecoveryWorker;
Future<SendPort>? _helperIsolateSendPort;
int _recoveryWorkerGeneration = 0;

Future<List<int>> _sendRecoveryRequest(
  Object Function(int requestId) createRequest, {
  Duration timeout = _recoveryRequestTimeout,
}) async {
  final SendPort helperIsolateSendPort = await _getRecoveryWorker();
  if (_helperIsolateFailure case final Object failure) {
    throw failure;
  }
  if (requests.isNotEmpty) {
    throw StateError('Another recovery operation is already in progress');
  }

  final int requestId = _nextSumRequestId++;
  final Completer<List<int>> completer = Completer<List<int>>();
  requests[requestId] = completer;
  _requestTimeouts[requestId] = Timer(timeout, () {
    final TimeoutException error =
        TimeoutException('Recovery request $requestId timed out', timeout);
    _recoveryWorkerIsolate?.kill(priority: Isolate.immediate);
    _failRecoveryWorker?.call(error);
  });

  try {
    helperIsolateSendPort.send(createRequest(requestId));
  } catch (_) {
    requests.remove(requestId);
    _requestTimeouts.remove(requestId)?.cancel();
    rethrow;
  }
  return completer.future;
}

void _failPendingRecoveryRequests(Object error, [StackTrace? stackTrace]) {
  final List<MapEntry<int, Completer<List<int>>>> pending =
      requests.entries.toList(growable: false);
  requests.clear();
  for (final MapEntry<int, Completer<List<int>>> request in pending) {
    _requestTimeouts.remove(request.key)?.cancel();
    if (!request.value.isCompleted) {
      request.value.completeError(error, stackTrace);
    }
  }
}

Future<SendPort> _getRecoveryWorker() {
  final current = _helperIsolateSendPort;
  if (current != null) return current;
  _helperIsolateFailure = null;
  final generation = ++_recoveryWorkerGeneration;
  final worker = _startRecoveryWorker(generation);
  _helperIsolateSendPort = worker;
  return worker;
}

/// Starts one generation of the native recovery isolate.
Future<SendPort> _startRecoveryWorker(int generation) async {
  final Completer<SendPort> completer = Completer<SendPort>();
  final ReceivePort receivePort = ReceivePort();
  final ReceivePort errorPort = ReceivePort();
  final ReceivePort exitPort = ReceivePort();
  bool outputPortsClosed = false;
  bool workerFailed = false;

  void closeOutputPorts() {
    if (outputPortsClosed) return;
    outputPortsClosed = true;
    receivePort.close();
    errorPort.close();
  }

  void failWorker(Object error, [StackTrace? stackTrace]) {
    if (generation != _recoveryWorkerGeneration || workerFailed) return;
    workerFailed = true;
    _helperIsolateFailure = error;
    if (!completer.isCompleted) {
      completer.completeError(error, stackTrace);
    }
    _failPendingRecoveryRequests(error, stackTrace);
    closeOutputPorts();
  }

  _failRecoveryWorker = failWorker;

  receivePort.listen((dynamic data) {
    if (data is SendPort) {
      if (!completer.isCompleted) {
        completer.complete(data);
      }
      return;
    }
    if (data is KeyResponse) {
      final Completer<List<int>>? request = requests.remove(data.id);
      _requestTimeouts.remove(data.id)?.cancel();
      if (request != null && !request.isCompleted) {
        request.complete(data.result);
      }
      return;
    }
    _recoveryWorkerIsolate?.kill(priority: Isolate.immediate);
    failWorker(
        UnsupportedError('Unsupported message type: ${data.runtimeType}'));
  });
  errorPort.listen((dynamic data) {
    final Object error = data is List && data.isNotEmpty
        ? StateError('Recovery isolate error: ${data.first}')
        : StateError('Recovery isolate error: $data');
    final StackTrace? stackTrace = data is List && data.length > 1
        ? StackTrace.fromString(data[1].toString())
        : null;
    failWorker(error, stackTrace);
  });
  exitPort.listen((dynamic _) {
    if (generation != _recoveryWorkerGeneration) {
      exitPort.close();
      return;
    }
    if (!workerFailed) failWorker(StateError('Recovery isolate exited'));
    _helperIsolateSendPort = null;
    _recoveryWorkerIsolate = null;
    _failRecoveryWorker = null;
    exitPort.close();
  });

  Isolate helperIsolate;
  try {
    helperIsolate = await Isolate.spawn(
      _runRecoveryWorker,
      receivePort.sendPort,
      onError: errorPort.sendPort,
      onExit: exitPort.sendPort,
      errorsAreFatal: true,
    );
    _recoveryWorkerIsolate = helperIsolate;
  } catch (error, stackTrace) {
    failWorker(error, stackTrace);
    _helperIsolateSendPort = null;
    _recoveryWorkerIsolate = null;
    _failRecoveryWorker = null;
    exitPort.close();
    return completer.future;
  }

  try {
    return await completer.future.timeout(_workerStartupTimeout);
  } on TimeoutException catch (error, stackTrace) {
    helperIsolate.kill(priority: Isolate.immediate);
    failWorker(error, stackTrace);
    rethrow;
  }
}

void _runRecoveryWorker(SendPort sendPort) {
  final ReceivePort helperReceivePort = ReceivePort()
    ..listen((dynamic data) {
      if (data is DarksideRequest) {
        final Pointer<Darkside> pointer = calloc<Darkside>();
        Pointer<DarksideItem>? itemPointer;
        Pointer<Uint32>? count;
        Pointer<Uint64>? result;
        try {
          itemPointer = calloc<DarksideItem>(data.darkside.items.length);
          pointer.ref.uid = data.darkside.uid;
          int i = 0;
          for (final DarksideItemDart item in data.darkside.items) {
            final DarksideItem value = itemPointer[i];
            value.ar = item.ar;
            value.ks1 = item.ks1;
            value.nr = item.nr;
            value.nt1 = item.nt1;
            value.par = item.par;
            i++;
          }
          pointer.ref.items = itemPointer;
          pointer.ref.count = i;

          count = calloc<Uint32>();
          result = _bindings.darkside(pointer, count);
          final List<int> keys = <int>[];
          for (int i = 0; i < count.value; i++) {
            keys.add(result[i]);
          }
          sendPort.send(KeyResponse(data.id, keys));
        } finally {
          if (result != null) {
            _bindings.recovery_free(result.cast<Void>());
          }
          if (count != null) {
            calloc.free(count);
          }
          if (itemPointer != null) {
            calloc.free(itemPointer);
          }
          calloc.free(pointer);
        }
        return;
      } else if (data is NestedRequest) {
        final Pointer<Nested> pointer = calloc<Nested>();
        Pointer<Uint32>? count;
        Pointer<Uint64>? result;
        try {
          pointer.ref.uid = data.nested.uid;
          pointer.ref.dist = data.nested.distance;
          pointer.ref.nt0 = data.nested.nt0;
          pointer.ref.nt0_enc = data.nested.nt0Enc;
          pointer.ref.par0 = data.nested.par0;
          pointer.ref.nt1 = data.nested.nt1;
          pointer.ref.nt1_enc = data.nested.nt1Enc;
          pointer.ref.par1 = data.nested.par1;

          count = calloc<Uint32>();
          result = _bindings.nested(pointer, count);
          final List<int> keys = <int>[];
          for (int i = 0; i < count.value; i++) {
            keys.add(result[i]);
          }
          sendPort.send(KeyResponse(data.id, keys));
        } finally {
          if (result != null) {
            _bindings.recovery_free(result.cast<Void>());
          }
          if (count != null) {
            calloc.free(count);
          }
          calloc.free(pointer);
        }
        return;
      } else if (data is Mfkey32Request) {
        final Pointer<Mfkey32> pointer = calloc<Mfkey32>();
        try {
          pointer.ref.uid = data.mfkey32.uid;
          pointer.ref.nt0 = data.mfkey32.nt0;
          pointer.ref.nt1 = data.mfkey32.nt1;
          pointer.ref.nr0_enc = data.mfkey32.nr0Enc;
          pointer.ref.ar0_enc = data.mfkey32.ar0Enc;
          pointer.ref.nr1_enc = data.mfkey32.nr1Enc;
          pointer.ref.ar1_enc = data.mfkey32.ar1Enc;

          final int result = _bindings.mfkey32(pointer);
          sendPort.send(KeyResponse(data.id, <int>[result]));
        } finally {
          calloc.free(pointer);
        }
        return;
      } else if (data is Mfkey64Request) {
        final Pointer<Mfkey64> pointer = calloc<Mfkey64>();
        try {
          pointer.ref.uid = data.mfkey64.uid;
          pointer.ref.nt = data.mfkey64.nt;
          pointer.ref.nr_enc = data.mfkey64.nrEnc;
          pointer.ref.ar_enc = data.mfkey64.arEnc;
          pointer.ref.at_enc = data.mfkey64.atEnc;

          final int result = _bindings.mfkey64(pointer);
          sendPort.send(KeyResponse(data.id, <int>[result]));
        } finally {
          calloc.free(pointer);
        }
        return;
      } else if (data is StaticNestedRequest) {
        final Pointer<StaticNested> pointer = calloc<StaticNested>();
        Pointer<Uint32>? count;
        Pointer<Uint64>? result;
        try {
          pointer.ref.uid = data.nested.uid;
          pointer.ref.key_type = data.nested.keyType;
          pointer.ref.nt0 = data.nested.nt0;
          pointer.ref.nt0_enc = data.nested.nt0Enc;
          pointer.ref.nt1 = data.nested.nt1;
          pointer.ref.nt1_enc = data.nested.nt1Enc;

          count = calloc<Uint32>();
          result = _bindings.static_nested(pointer, count);
          final List<int> keys = <int>[];
          for (int i = 0; i < count.value; i++) {
            keys.add(result[i]);
          }
          sendPort.send(KeyResponse(data.id, keys));
        } finally {
          if (result != null) {
            _bindings.recovery_free(result.cast<Void>());
          }
          if (count != null) {
            calloc.free(count);
          }
          calloc.free(pointer);
        }
        return;
      } else if (data is StaticEncryptedNestedRequest) {
        final Pointer<StaticEncryptedNested> pointer =
            calloc<StaticEncryptedNested>();
        Pointer<Uint32>? count;
        Pointer<Uint64>? result;
        try {
          pointer.ref.uid = data.nested.uid;
          pointer.ref.nt = data.nested.nt;
          pointer.ref.nt_enc = data.nested.ntEnc;
          pointer.ref.nt_par_enc = data.nested.ntParEnc;

          count = calloc<Uint32>();
          result = _bindings.static_encrypted_nested(pointer, count);
          final List<int> keys = <int>[];
          for (int i = 0; i < count.value; i++) {
            keys.add(result[i]);
          }
          sendPort.send(KeyResponse(data.id, keys));
        } finally {
          if (result != null) {
            _bindings.recovery_free(result.cast<Void>());
          }
          if (count != null) {
            calloc.free(count);
          }
          calloc.free(pointer);
        }
        return;
      } else if (data is HardNestedRequest) {
        final Pointer<HardNested> pointer = calloc<HardNested>();
        Pointer<Uint8>? nonces;
        try {
          nonces = calloc<Uint8>(data.nested.nonces.length);
          nonces
              .asTypedList(data.nested.nonces.length)
              .setAll(0, data.nested.nonces);
          pointer.ref.nonces = nonces.cast<Char>();
          pointer.ref.length = data.nested.nonces.length;

          final int result = _bindings.hardnested(pointer);
          sendPort.send(KeyResponse(data.id, <int>[result]));
        } finally {
          if (nonces != null) {
            calloc.free(nonces);
          }
          calloc.free(pointer);
        }
        return;
      }
      throw UnsupportedError('Unsupported message type: ${data.runtimeType}');
    });

  sendPort.send(helperReceivePort.sendPort);
}

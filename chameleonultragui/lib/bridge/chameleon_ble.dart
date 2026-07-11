import 'dart:async';
import 'dart:typed_data';

import 'package:chameleonultragui/helpers/definitions.dart';

import 'chameleon.dart';

export 'chameleon.dart';

extension ChameleonBle on ChameleonCommunicator {
  // -----------------------------------------------------------------------
  // BLE — passive scanner (listen-only) and directed GATT fuzzing harness.
  // The scanner never transmits; the fuzzer only ever talks to the single
  // target you connect to by address. Neither broadcasts to the environment.
  // -----------------------------------------------------------------------

  ChameleonMessage _requireBleSuccess(
      ChameleonCommand command, ChameleonMessage? response,
      {int? exactDataLength, int minimumDataLength = 0}) {
    if (response == null) {
      throw StateError('BLE command ${command.name} returned no response');
    }
    if (response.status != chameleonStatusSuccess) {
      throw ChameleonCommandException(command, response.status);
    }
    final actual = response.data.length;
    if ((exactDataLength != null && actual != exactDataLength) ||
        actual < minimumDataLength) {
      final expected = exactDataLength != null
          ? 'exactly $exactDataLength'
          : 'at least $minimumDataLength';
      throw FormatException(
          'BLE command ${command.name} returned $actual data bytes; expected $expected');
    }
    return response;
  }

  // Start a scan. Passive (default) is listen-only; active also sends scan
  // requests to collect scan responses (e.g. full device names).
  Future<void> blePassiveScanStart({bool active = false}) async {
    _requireBleSuccess(
        ChameleonCommand.bleScanStart,
        await sendCmd(ChameleonCommand.bleScanStart,
            data: Uint8List.fromList([active ? 1 : 0])));
  }

  Future<void> blePassiveScanStop() async {
    _requireBleSuccess(ChameleonCommand.bleScanStop,
        await sendCmd(ChameleonCommand.bleScanStop));
  }

  Future<int> blePassiveScanCount() async {
    final resp = _requireBleSuccess(ChameleonCommand.bleScanGetCount,
        await sendCmd(ChameleonCommand.bleScanGetCount),
        exactDataLength: 1);
    return resp.data[0];
  }

  // Fetch discovered devices. Wire per record:
  // addr[6] | addr_type[1] | rssi[1 signed] | adv_len[1] | adv[adv_len].
  Future<List<BleScanResult>> blePassiveScanResults(
      {int startIndex = 0}) async {
    final resp = _requireBleSuccess(
        ChameleonCommand.bleScanGetResults,
        await sendCmd(ChameleonCommand.bleScanGetResults,
            data: Uint8List.fromList([startIndex & 0xFF])));
    List<BleScanResult> out = [];
    var d = resp.data;
    int o = 0;
    while (o < d.length) {
      if (d.length - o < 9) {
        throw const FormatException('Truncated BLE scan record header');
      }
      var addr = d.sublist(o, o + 6);
      o += 6;
      int addrType = d[o];
      int rssi = d[o + 1].toSigned(8);
      int advLen = d[o + 2];
      o += 3;
      if (o + advLen > d.length) {
        throw const FormatException('Truncated BLE advertising data');
      }
      var adv = d.sublist(o, o + advLen);
      o += advLen;
      out.add(BleScanResult(
          addr: Uint8List.fromList(addr),
          addrType: addrType,
          rssi: rssi,
          adv: Uint8List.fromList(adv)));
    }
    return out;
  }

  // Query whether the device's own BLE advertising (discoverable) is on.
  Future<bool> bleAdvertisingGet() async {
    final resp = _requireBleSuccess(ChameleonCommand.bleAdvertisingGet,
        await sendCmd(ChameleonCommand.bleAdvertisingGet),
        exactDataLength: 1);
    return resp.data[0] != 0;
  }

  // Enable/disable the device's own BLE advertising. Returns the new state.
  Future<bool> bleAdvertisingSet(bool on, {bool eraseBonds = false}) async {
    final resp = _requireBleSuccess(
        ChameleonCommand.bleAdvertisingSet,
        await sendCmd(ChameleonCommand.bleAdvertisingSet,
            data: Uint8List.fromList([on ? 1 : 0, eraseBonds ? 1 : 0])),
        exactDataLength: 1);
    return resp.data[0] != 0;
  }

  // ---- Own-radio identity / radio power (cybersecurity fork additions) ----
  // These mutate only OUR radio (local settings — no scope selector). The
// environment-wide / scan-buffer-wide tools live further down in this file.

  // Set the device's own BLE GAP address.
  //   mode 0 = restore original (FICR-derived)
  //   mode 1 = static-random (host-provided 6 bytes LE in [addr])
  //   mode 2 = firmware-generated random private resolvable (RPA)
  //   mode 3 = firmware-generated random private non-resolvable
  // Throws if a link is active (DEVICE_MODE_ERROR).
  Future<int> bleSetAddr(int mode, {Uint8List? addr}) async {
    if (mode == 1) {
      if (addr == null || addr.length != 6) {
        throw ArgumentError('mode 1 requires a 6-byte addr');
      }
      var payload = Uint8List(7);
      payload[0] = mode & 0xFF;
      payload.setRange(1, 7, addr);
      final resp = _requireBleSuccess(ChameleonCommand.bleSetAddr,
          await sendCmd(ChameleonCommand.bleSetAddr, data: payload));
      return resp.status;
    }
    if (mode < 0 || mode > 3) {
      throw ArgumentError('mode must be 0..3 (got $mode)');
    }
    final resp = _requireBleSuccess(
        ChameleonCommand.bleSetAddr,
        await sendCmd(ChameleonCommand.bleSetAddr,
            data: Uint8List.fromList([mode & 0xFF])));
    return resp.status;
  }

  // Read the device's currently-active BLE GAP address.
  // Returns {'addrType': int, 'addr': Uint8List(6 LE)} on success.
  Future<Map<String, dynamic>> bleGetAddr() async {
    final resp = _requireBleSuccess(
        ChameleonCommand.bleGetAddr, await sendCmd(ChameleonCommand.bleGetAddr),
        exactDataLength: 7);
    return {
      'addrType': resp.data[0],
      'addr': resp.data.sublist(1, 7),
    };
  }

  // Turn the device's own BLE radio on/off. Off = stealth (stop adv + scan +
  // drop central link). On = resume.
  Future<int> bleRadioSet(bool on) async {
    final resp = _requireBleSuccess(
        ChameleonCommand.bleRadioSet,
        await sendCmd(ChameleonCommand.bleRadioSet,
            data: Uint8List.fromList([on ? 1 : 0])));
    return resp.status;
  }

  // Snapshot of the device's own radio state. Returns
  // {'on': bool, 'advertising': bool, 'scanning': bool, 'centralLink': bool}.
  Future<Map<String, bool>> bleRadioGet() async {
    final resp = _requireBleSuccess(ChameleonCommand.bleRadioGet,
        await sendCmd(ChameleonCommand.bleRadioGet),
        exactDataLength: 4);
    return {
      'on': resp.data[0] != 0,
      'advertising': resp.data[1] != 0,
      'scanning': resp.data[2] != 0,
      'centralLink': resp.data[3] != 0,
    };
  }

  // ---- Stress / broadcast (cybersecurity fork, operator-authorised) -----
  // Per-call scope selectable:
  //   0 = single target (already-connected central link / host-picked addr)
  //   1 = scan-buffer-wide (every address cached by the passive scanner)
  //   2 = full environment-wide broadcast on the 2.4 GHz BLE spectrum

  // Start a rapid WRITE_CMD flood.
  //   scope=0 → payloadSize bytes per write to the connected target's
  //             valueHandle, maxIterations 0=∞, intervalMs floor 1.
  //   scope=1 → iterate the scan buffer; same valueHandle / payloadSize /
  //             maxIterations / intervalMs contract.
  //   scope=2 → ignored, use bleAdvFloodStart() instead.
  // Throws DEVICE_MODE_ERROR (0x66) if scope=0 and no central link is up.
  Future<int> bleFloodStart(int scope, int valueHandle, int payloadSize,
      {int maxIterations = 0, int intervalMs = 5}) async {
    if (scope < 0 || scope > 2) {
      throw ArgumentError('scope must be 0/1/2 (got $scope)');
    }
    if (scope == 0 || scope == 1) {
      if (valueHandle < 1 || valueHandle > 0xFFFF) {
        throw ArgumentError('valueHandle must be 1..0xffff');
      }
      if (payloadSize < 1 || payloadSize > 20) {
        throw ArgumentError('payloadSize must be 1..20');
      }
    } else {
      if (valueHandle < 0 || valueHandle > 0xFF) {
        throw ArgumentError('broadcast fill byte must be 0..255');
      }
      if (payloadSize < 0 || payloadSize > 0xFF) {
        throw ArgumentError('payloadSize must be 0..255 for scope=2');
      }
    }
    if (maxIterations < 0 || maxIterations > 0xFFFF) {
      throw ArgumentError('maxIterations must be 0..65535');
    }
    if (intervalMs < 1 || intervalMs > 0xFFFF) {
      throw ArgumentError('intervalMs must be 1..65535');
    }
    final p = ByteData(8);
    p.setUint8(0, scope);
    p.setUint16(1, valueHandle, Endian.big);
    p.setUint8(3, payloadSize);
    p.setUint16(4, maxIterations, Endian.big);
    p.setUint16(6, intervalMs, Endian.big);
    final resp = _requireBleSuccess(
        ChameleonCommand.bleFloodStart,
        await sendCmd(ChameleonCommand.bleFloodStart,
            data: p.buffer.asUint8List()));
    return resp.status;
  }

  Future<void> bleFloodStop() async {
    // Stops both the WRITE_CMD flood AND the environment-wide adv flood.
    _requireBleSuccess(ChameleonCommand.bleFloodStop,
        await sendCmd(ChameleonCommand.bleFloodStop));
  }

  // Total WRITE_CMDs accepted by the SoftDevice since the flood started.
  Future<int> bleFloodCount() async {
    final resp = _requireBleSuccess(ChameleonCommand.bleFloodCount,
        await sendCmd(ChameleonCommand.bleFloodCount),
        exactDataLength: 4);
    return (resp.data[0] << 24) |
        (resp.data[1] << 16) |
        (resp.data[2] << 8) |
        resp.data[3];
  }

  // Force-disconnect the central link(s) `cycles` times (1..10).
  //   scope=0 = current central link only.
  //   scope=1 = scan-buffer-wide churn (connect → kick → next, for every
  //             cached address).
  Future<int> bleKick(int cycles, {int scope = 0}) async {
    if (cycles < 1 || cycles > 10) {
      throw ArgumentError('cycles must be 1..10 (got $cycles)');
    }
    if (scope != 0 && scope != 1) {
      throw ArgumentError('scope must be 0 or 1 (got $scope)');
    }
    if (scope == 0 && cycles != 1) {
      throw ArgumentError('scope=single supports exactly one disconnect cycle');
    }
    final resp = _requireBleSuccess(
        ChameleonCommand.bleKick,
        await sendCmd(ChameleonCommand.bleKick,
            data: Uint8List.fromList([scope & 0xFF, cycles & 0xFF])));
    return resp.status;
  }

  // Full environment-wide broadcast on the 2.4 GHz BLE spectrum —
  // non-connectable advertising spam, max payload, regulatory-minimum interval.
  // fillByte fills the 26-byte manufacturer-data field; intervalUnits is in
  // 100ms multiples, 1..102 (1 = 100ms, 102 = 10.2s).
  Future<int> bleAdvFloodStart(int fillByte, {int intervalUnits = 1}) async {
    if (fillByte < 0 || fillByte > 0xFF) {
      throw ArgumentError('fillByte must be 0..255');
    }
    if (intervalUnits < 1 || intervalUnits > 102) {
      throw ArgumentError('intervalUnits must be 1..102');
    }
    final resp = _requireBleSuccess(
        ChameleonCommand.bleAdvFloodStart,
        await sendCmd(ChameleonCommand.bleAdvFloodStart,
            data: Uint8List.fromList([2, fillByte, intervalUnits])));
    return resp.status;
  }

  Future<void> bleAdvFloodStop() async {
    _requireBleSuccess(ChameleonCommand.bleAdvFloodStop,
        await sendCmd(ChameleonCommand.bleAdvFloodStop));
  }

  // Connect to ONE target. addrLe is 6 bytes little-endian (as the scanner
  // reports). Returns the firmware status byte (0x68 = success/initiated).
  Future<int> bleConnect(Uint8List addrLe, {int addrType = 0}) async {
    if (addrLe.length != 6) {
      throw ArgumentError.value(addrLe.length, 'addrLe.length', 'must be 6');
    }
    var payload = Uint8List.fromList([addrType & 0xFF, ...addrLe]);
    final resp = _requireBleSuccess(ChameleonCommand.bleConnect,
        await sendCmd(ChameleonCommand.bleConnect, data: payload));
    return resp.status;
  }

  Future<void> bleDisconnect() async {
    _requireBleSuccess(ChameleonCommand.bleDisconnect,
        await sendCmd(ChameleonCommand.bleDisconnect));
  }

  Future<BleCentralState> bleCentralState() async {
    final resp = _requireBleSuccess(ChameleonCommand.bleCentralState,
        await sendCmd(ChameleonCommand.bleCentralState),
        minimumDataLength: 10);
    var d = resp.data;
    if (d.length != 10 && d.length != 12 && d.length < 21) {
      throw FormatException(
          'BLE central state returned ${d.length} bytes; expected 10, 12, or at least 21');
    }
    return BleCentralState(
        connState: d[0],
        discState: d[1],
        charCount: d[2],
        fuzzState: d[3],
        fuzzSent: (d[4] << 8) | d[5],
        targetAlive: d[6] != 0,
        lastReason: d[7],
        probeState: d[8],
        probeResult: d[9],
        probeIndex: d.length >= 12 ? d[10] : 0,
        probeTotal: d.length >= 12 ? d[11] : 0,
        floodState: d.length >= 21 ? d[12] : 0,
        floodSent: d.length >= 21
            ? (d[13] << 24) | (d[14] << 16) | (d[15] << 8) | d[16]
            : 0,
        readState: d.length >= 21 ? d[17] : 0,
        writeState: d.length >= 21 ? d[18] : 0,
        notificationCount: d.length >= 21 ? (d[19] << 8) | d[20] : 0,
        hasOperationState: d.length >= 21);
  }

  Future<int> bleGattDiscover() async {
    final resp = _requireBleSuccess(ChameleonCommand.bleGattDiscover,
        await sendCmd(ChameleonCommand.bleGattDiscover));
    return resp.status;
  }

  // Fetch discovered characteristics. Wire per char:
  // value_handle[2] | props[1] | uuid_type[1] | uuid[2] (big-endian).
  Future<List<BleCharacteristic>> bleGattChars({int startIndex = 0}) async {
    final resp = _requireBleSuccess(
        ChameleonCommand.bleGattGetChars,
        await sendCmd(ChameleonCommand.bleGattGetChars,
            data: Uint8List.fromList([startIndex & 0xFF])));
    List<BleCharacteristic> out = [];
    var d = resp.data;
    if (d.length % 6 != 0) {
      throw const FormatException('Partial BLE characteristic record');
    }
    int o = 0;
    while (o + 6 <= d.length) {
      out.add(BleCharacteristic(
          handle: (d[o] << 8) | d[o + 1],
          props: d[o + 2],
          uuidType: d[o + 3],
          uuid: (d[o + 4] << 8) | d[o + 5]));
      o += 6;
    }
    return out;
  }

  // Discover the target's primary services. Each map: uuidType, uuid, start, end.
  Future<List<Map<String, int>>> bleServices(
      {Duration timeout = const Duration(seconds: 3)}) async {
    _requireBleSuccess(ChameleonCommand.bleSvcDiscover,
        await sendCmd(ChameleonCommand.bleSvcDiscover));
    var deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      await Future.delayed(const Duration(milliseconds: 100));
      final resp = _requireBleSuccess(
          ChameleonCommand.bleSvcGet,
          await sendCmd(ChameleonCommand.bleSvcGet,
              data: Uint8List.fromList([0])),
          minimumDataLength: 1);
      var d = resp.data;
      if (d.isEmpty) continue;
      if (d[0] == 3) {
        throw StateError('BLE primary-service discovery failed');
      }
      if (d[0] == 2) {
        if ((d.length - 1) % 7 != 0) {
          throw const FormatException('Partial BLE service record');
        }
        List<Map<String, int>> out = [];
        int o = 1;
        while (o + 7 <= d.length) {
          out.add({
            'uuidType': d[o],
            'uuid': (d[o + 1] << 8) | d[o + 2],
            'start': (d[o + 3] << 8) | d[o + 4],
            'end': (d[o + 5] << 8) | d[o + 6],
          });
          o += 7;
        }
        return out;
      }
    }
    throw TimeoutException('BLE service discovery did not finish', timeout);
  }

  // Enumerate all descriptors of the connected target. Each map: handle, uuidType, uuid.
  Future<List<Map<String, int>>> bleDescriptors(
      {Duration timeout = const Duration(seconds: 5)}) async {
    _requireBleSuccess(ChameleonCommand.bleDescDiscover,
        await sendCmd(ChameleonCommand.bleDescDiscover));
    var deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      await Future.delayed(const Duration(milliseconds: 100));
      final resp = _requireBleSuccess(
          ChameleonCommand.bleDescGet,
          await sendCmd(ChameleonCommand.bleDescGet,
              data: Uint8List.fromList([0])),
          minimumDataLength: 1);
      var d = resp.data;
      if (d.isEmpty) continue;
      if (d[0] == 3) {
        throw StateError('BLE descriptor discovery failed');
      }
      if (d[0] == 2) {
        if ((d.length - 1) % 5 != 0) {
          throw const FormatException('Partial BLE descriptor record');
        }
        List<Map<String, int>> out = [];
        int o = 1;
        while (o + 5 <= d.length) {
          out.add({
            'handle': (d[o] << 8) | d[o + 1],
            'uuidType': d[o + 2],
            'uuid': (d[o + 3] << 8) | d[o + 4],
          });
          o += 5;
        }
        return out;
      }
    }
    throw TimeoutException('BLE descriptor discovery did not finish', timeout);
  }

  // Read the connected target's standard device information (Generic Access
  // name/appearance, Device Information Service, battery level) via read-only
  // GATT reads. Run after discover (handles come from the char table). Each map:
  // uuid, status, data. status 0xFF = characteristic absent, else the ATT read
  // status (0 = ok). Wire: state[1] | count[1] then uuid[2] | status[1] | len[1] | data[len].
  Future<List<Map<String, dynamic>>> bleDeviceInfo(
      {Duration timeout = const Duration(seconds: 3)}) async {
    _requireBleSuccess(ChameleonCommand.bleDeviceInfo,
        await sendCmd(ChameleonCommand.bleDeviceInfo));
    var deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      await Future.delayed(const Duration(milliseconds: 50));
      final resp = _requireBleSuccess(ChameleonCommand.bleGetDeviceInfo,
          await sendCmd(ChameleonCommand.bleGetDeviceInfo));
      var d = resp.data;
      if (d.length < 2) continue;
      if (d[0] == 3) {
        throw StateError('BLE device-information read failed');
      }
      if (d[0] == 2) {
        List<Map<String, dynamic>> out = [];
        final count = d[1];
        int o = 2; // skip state + count
        for (var i = 0; i < count; i++) {
          if (d.length - o < 4) {
            throw const FormatException('Truncated BLE device-info header');
          }
          int uuid = (d[o] << 8) | d[o + 1];
          int status = d[o + 2];
          int len = d[o + 3];
          o += 4;
          if (o + len > d.length) {
            throw const FormatException('Truncated BLE device-info value');
          }
          out.add({
            'uuid': uuid,
            'status': status,
            'data': Uint8List.fromList(d.sublist(o, o + len)),
          });
          o += len;
        }
        if (o != d.length) {
          throw const FormatException('Trailing BLE device-info data');
        }
        return out;
      }
    }
    throw TimeoutException('BLE device-info read did not finish', timeout);
  }

  // Start fuzzing value_handle: mutated writes every intervalMs, up to
  // maxIterations (0 = until stopped). Returns the firmware status byte.
  Future<int> bleFuzzStart(int valueHandle,
      {int maxIterations = 0, int intervalMs = 50}) async {
    if (valueHandle < 1 || valueHandle > 0xFFFF) {
      throw ArgumentError('valueHandle must be 1..0xffff');
    }
    if (maxIterations < 0 || maxIterations > 0xFFFF) {
      throw ArgumentError('maxIterations must be 0..65535');
    }
    if (intervalMs < 1 || intervalMs > 0xFFFF) {
      throw ArgumentError('intervalMs must be 1..65535');
    }
    var payload = Uint8List.fromList([
      valueHandle >> 8,
      valueHandle & 0xFF,
      maxIterations >> 8,
      maxIterations & 0xFF,
      intervalMs >> 8,
      intervalMs & 0xFF,
    ]);
    final resp = _requireBleSuccess(ChameleonCommand.bleFuzzStart,
        await sendCmd(ChameleonCommand.bleFuzzStart, data: payload));
    return resp.status;
  }

  Future<void> bleFuzzStop() async {
    _requireBleSuccess(ChameleonCommand.bleFuzzStop,
        await sendCmd(ChameleonCommand.bleFuzzStop));
  }

  Future<int> bleLinkProbe({bool globalMode = false}) async {
    final resp = _requireBleSuccess(
        ChameleonCommand.bleLinkProbe,
        await sendCmd(ChameleonCommand.bleLinkProbe,
            data: globalMode ? Uint8List.fromList([1]) : null));
    return resp.status;
  }

  // Fetch the fuzz log. Wire per entry:
  // index[2] | payload_len[1] | write_status[1] | data[min(payload_len,16)].
  Future<List<BleFuzzLogEntry>> bleFuzzLog({int startIndex = 0}) async {
    final resp = _requireBleSuccess(
        ChameleonCommand.bleFuzzGetLog,
        await sendCmd(ChameleonCommand.bleFuzzGetLog,
            data: Uint8List.fromList(
                [(startIndex >> 8) & 0xFF, startIndex & 0xFF])));
    List<BleFuzzLogEntry> out = [];
    var d = resp.data;
    int o = 0;
    while (o < d.length) {
      if (d.length - o < 4) {
        throw const FormatException('Truncated BLE fuzz-log header');
      }
      int index = (d[o] << 8) | d[o + 1];
      int plen = d[o + 2];
      int status = d[o + 3];
      o += 4;
      int dlen = plen < 16 ? plen : 16;
      if (o + dlen > d.length) {
        throw const FormatException('Truncated BLE fuzz-log payload');
      }
      var data = d.sublist(o, o + dlen);
      o += dlen;
      out.add(BleFuzzLogEntry(
          index: index,
          length: plen,
          status: status,
          data: Uint8List.fromList(data)));
    }
    return out;
  }

  // Read a characteristic value from the connected target. Returns
  // (gattStatus, value): gattStatus 0 = success, >0 = ATT error, -1 = timeout.
  Future<(int, Uint8List)> bleGattRead(int valueHandle,
      {Duration timeout = const Duration(seconds: 2)}) async {
    _requireBleSuccess(
        ChameleonCommand.bleGattRead,
        await sendCmd(ChameleonCommand.bleGattRead,
            data: Uint8List.fromList(
                [(valueHandle >> 8) & 0xFF, valueHandle & 0xFF])));
    var deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      await Future.delayed(const Duration(milliseconds: 50));
      final resp = _requireBleSuccess(ChameleonCommand.bleGattGetRead,
          await sendCmd(ChameleonCommand.bleGattGetRead),
          minimumDataLength: 3);
      var d = resp.data;
      if (d.length != 3 + d[2]) {
        throw const FormatException('Invalid BLE GATT read value length');
      }
      if (d[0] == 2 || d[0] == 3) {
        int len = d[2];
        var value = d.sublist(3, 3 + len);
        return (d[1], Uint8List.fromList(value));
      }
    }
    return (-1, Uint8List(0)); // timed out
  }

  // Write a value to a characteristic on the connected target (write-with-
  // response). Returns the target's ATT status: 0 = success, >0 = ATT error,
  // -1 = timeout / rejected.
  Future<int> bleGattWrite(int valueHandle, Uint8List data,
      {Duration timeout = const Duration(seconds: 2)}) async {
    var payload = Uint8List.fromList(
        [(valueHandle >> 8) & 0xFF, valueHandle & 0xFF, ...data]);
    _requireBleSuccess(ChameleonCommand.bleGattWrite,
        await sendCmd(ChameleonCommand.bleGattWrite, data: payload));
    var deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      await Future.delayed(const Duration(milliseconds: 50));
      final resp = _requireBleSuccess(ChameleonCommand.bleGetWrite,
          await sendCmd(ChameleonCommand.bleGetWrite),
          exactDataLength: 2);
      var d = resp.data;
      if (d[0] == 2 || d[0] == 3) {
        return d[1]; // done: gatt_status
      }
    }
    return -1; // timed out
  }

  // Effective ATT MTU of the connected target link (23 until negotiated).
  Future<int> bleGetMtu() async {
    final resp = _requireBleSuccess(
        ChameleonCommand.bleGetMtu, await sendCmd(ChameleonCommand.bleGetMtu),
        exactDataLength: 2);
    return (resp.data[0] << 8) | resp.data[1];
  }

  // Subscribe to notifications/indications on the connected target by writing its
  // CCCD. mode: 0 = off, 1 = notifications, 2 = indications. Returns the status.
  Future<int> bleSubscribe(int cccdHandle, int mode) async {
    final resp = _requireBleSuccess(
        ChameleonCommand.bleSubscribe,
        await sendCmd(ChameleonCommand.bleSubscribe,
            data: Uint8List.fromList(
                [(cccdHandle >> 8) & 0xFF, cccdHandle & 0xFF, mode & 0xFF])));
    return resp.status;
  }

  // Fetch received notifications. Wire per entry: handle[2] | len[1] | data[len].
  Future<List<Map<String, dynamic>>> bleGetNotifications(
      {int startIndex = 0}) async {
    final resp = _requireBleSuccess(
        ChameleonCommand.bleGetNotifications,
        await sendCmd(ChameleonCommand.bleGetNotifications,
            data: Uint8List.fromList(
                [(startIndex >> 8) & 0xFF, startIndex & 0xFF])));
    List<Map<String, dynamic>> out = [];
    var d = resp.data;
    int o = 0;
    while (o < d.length) {
      if (d.length - o < 3) {
        throw const FormatException('Truncated BLE notification header');
      }
      int handle = (d[o] << 8) | d[o + 1];
      int len = d[o + 2];
      o += 3;
      if (o + len > d.length) {
        throw const FormatException('Truncated BLE notification value');
      }
      out.add({
        'handle': handle,
        'data': Uint8List.fromList(d.sublist(o, o + len))
      });
      o += len;
    }
    return out;
  }

  // Discover a characteristic's CCCD descriptor handle. Falls back to
  // valueHandle + 1 (the common layout) if none is found or on timeout.
  Future<int> bleFindCccd(int valueHandle,
      {Duration timeout = const Duration(seconds: 2)}) async {
    _requireBleSuccess(
        ChameleonCommand.bleFindCccd,
        await sendCmd(ChameleonCommand.bleFindCccd,
            data: Uint8List.fromList(
                [(valueHandle >> 8) & 0xFF, valueHandle & 0xFF])));
    var deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      await Future.delayed(const Duration(milliseconds: 50));
      final resp = _requireBleSuccess(ChameleonCommand.bleGetCccd,
          await sendCmd(ChameleonCommand.bleGetCccd),
          exactDataLength: 3);
      var d = resp.data;
      if (d[0] == 2) return (d[1] << 8) | d[2]; // found
      if (d[0] == 3) break; // not found
    }
    return valueHandle + 1;
  }
}

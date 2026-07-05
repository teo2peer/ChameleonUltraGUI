import 'dart:typed_data';

import 'package:chameleonultragui/connector/serial_abstract.dart';
import 'package:chameleonultragui/generated/i18n/app_localizations.dart';
import 'package:chameleonultragui/helpers/definitions.dart';
import 'package:chameleonultragui/helpers/general.dart';
import 'package:chameleonultragui/helpers/mifare_classic/general.dart';
import 'package:chameleonultragui/main.dart';
import 'package:chameleonultragui/recovery/recovery.dart';
import 'package:chameleonultragui/sharedprefsprovider.dart';

// Recovery
import 'package:chameleonultragui/recovery/recovery.dart' as recovery;

extension PartitionList<E> on List<E> {
  List<List<E>> partition(int size) {
    assert(size > 0);
    final out = <List<E>>[];
    for (var i = 0; i < length; i += size) {
      final end = i + size < length ? i + size : length;
      out.add(sublist(i, end));
    }
    return out;
  }
}

enum ChameleonKeyCheckmark { none, found, checking, disabled }

class MifareClassicRecovery {
  late ChameleonGUIState appState;
  late AppLocalizations localizations;
  String error;
  String state;
  bool allKeysExists;
  List<Dictionary> dictionaries;
  Dictionary? selectedDictionary;
  List<ChameleonKeyCheckmark> checkMarks;
  List<Uint8List> validKeys;
  List<Uint8List> cardData;
  double dumpProgress;
  double? hardnestedProgress;
  double? keyCheckProgress;
  void Function() update;
  MifareClassicType mifareClassicType;
  bool isMifareClassicEV1;

  MifareClassicRecovery(
      {required this.appState,
      required this.update,
      required this.localizations,
      this.error = '',
      this.state = '',
      this.allKeysExists = false,
      this.dictionaries = const [],
      this.dumpProgress = 0,
      this.selectedDictionary,
      this.mifareClassicType = MifareClassicType.none,
      this.isMifareClassicEV1 = false,
      List<ChameleonKeyCheckmark>? checkMarks,
      List<Uint8List>? validKeys,
      List<Uint8List>? cardData})
      : checkMarks =
            checkMarks ?? List.generate(80, (_) => ChameleonKeyCheckmark.none),
        validKeys = validKeys ?? List.generate(80, (_) => Uint8List(0)),
        cardData = cardData ?? List.generate(256, (_) => Uint8List(0)) {
    initializeEV1();
  }

  // Reorder a large candidate list so the most likely keys are tried first —
  // checkKeysOnSector breaks on the first hit, so this turns an average
  // half-list scan into an early hit on the common cases (default keys, and
  // keys already recovered on other sectors = key reuse). Order-only.
  List<Uint8List> _prioritiseCandidates(List<Uint8List> keys) {
    if (keys.length < 64) return keys; // not worth it for short lists
    final likely = <String>{...gMifareClassicKeys.map(bytesToHex)};
    for (final k in validKeys) {
      if (k.isNotEmpty) likely.add(bytesToHex(k));
    }
    final pri = <Uint8List>[];
    final rest = <Uint8List>[];
    for (final k in keys) {
      (likely.contains(bytesToHex(k)) ? pri : rest).add(k);
    }
    return pri.isEmpty ? keys : [...pri, ...rest];
  }

  Future<bool> checkKeysOnSector(
      List<Uint8List> keys, int keyType, int sector) async {
    keys = _prioritiseCandidates(keys);
    state = localizations.checking_keys(keys.length);
    Uint8List? key;
    keyCheckProgress = null;
    int chunkSize =
        appState.connector!.connectionType == ConnectionType.ble ? 32 : 64;

    if (getSectorState(sector, keyType) != ChameleonKeyCheckmark.found &&
        getSectorState(sector, keyType) != ChameleonKeyCheckmark.disabled) {
      setCheckingSector(sector, keyType);
      int totalChunks = keys.partition(chunkSize).length;

      for (var chunk in keys.partition(chunkSize)) {
        key = await appState.communicator!.mf1AuthMultipleKeys(
            mfClassicGetSectorTrailerBlockBySector(sector),
            0x60 + keyType,
            chunk);
        if (key != null) {
          setKeyAsFound(sector, keyType, key);
          keyCheckProgress = null;
          await recheckKey(key, sector);
          return true;
        } else if (totalChunks > 10) {
          keyCheckProgress = (keyCheckProgress ?? 0) + 1 / totalChunks;
          update();
        }
      }

      if (key == null) {
        setMissingSector(sector, keyType);
      }
    }

    if (keyType == 0 &&
        getSectorState(sector, 0) == ChameleonKeyCheckmark.found &&
        getSectorState(sector, 1) != ChameleonKeyCheckmark.found &&
        getSectorState(sector, 1) != ChameleonKeyCheckmark.disabled &&
        key != null) {
      Uint8List block = await appState.communicator!.mf1ReadBlock(
          mfClassicGetSectorTrailerBlockBySector(sector), 0x60 + keyType, key);
      if (block.length == 16) {
        Uint8List bKey = block.sublist(10);
        if (bytesToHex(bKey) != bytesToHex(Uint8List(6))) {
          keyCheckProgress = null;
          await recheckKey(key, sector);
          return true;
        }
      }
    }

    setMissingSector(sector, keyType);
    keyCheckProgress = null;
    return false;
  }

  Future<void> initialize() async {
    if (!await appState.communicator!.isReaderDeviceMode()) {
      await appState.communicator!.setReaderDeviceMode(true);
    }

    var mifare = await appState.communicator!.detectMf1Support();

    if (mifare) {
      mifareClassicType = await mfClassicGetType(appState.communicator!);
    } else {
      appState.log!.e("Not Mifare Classic tag!");
    }

    isMifareClassicEV1 =
        await appState.communicator!.mf1Auth(0x45, 0x61, gMifareClassicKeys[3]);
    initializeEV1();
  }

  Future<void> recheckKey(Uint8List key, int startingSector) async {
    // Scan ALL sectors (not just from startingSector): keys are frequently
    // reused across sectors, and a key found late is often the missing key of
    // an earlier, still-unresolved sector. Trying it there is one cheap auth
    // that can avoid an expensive nested/darkside attack. Only sectors still in
    // the `none` state are probed, so resolved sectors are skipped.
    for (var sector = 0;
        sector <
            mfClassicGetSectorCount(mifareClassicType,
                isEV1: isMifareClassicEV1);
        sector++) {
      for (var keyType = 0; keyType < 2; keyType++) {
        if (getSectorState(sector, keyType) == ChameleonKeyCheckmark.none) {
          state = localizations.checking_keys(1);
          appState.log!.d(
              "Checking found key ${bytesToHex(key)} on sector $sector, key type $keyType");
          setCheckingSector(sector, keyType);

          if (await appState.communicator!.mf1Auth(
              mfClassicGetSectorTrailerBlockBySector(sector),
              0x60 + keyType,
              key)) {
            // Found valid key
            setKeyAsFound(sector, keyType, key);
          } else {
            setMissingSector(sector, keyType);
          }

          update();
        }
      }
    }
  }

  void initializeEV1() {
    if (isMifareClassicEV1) {
      setKeyAsFound(16, 0, gMifareClassicKeys[4]); // MFC EV1 SIGNATURE 16 A
      setKeyAsFound(16, 1, gMifareClassicKeys[5]); // MFC EV1 SIGNATURE 16 B
      setKeyAsFound(17, 0, gMifareClassicKeys[6]); // MFC EV1 SIGNATURE 17 A
      setKeyAsFound(17, 1, gMifareClassicKeys[3]); // MFC EV1 SIGNATURE 17 B
    }
  }

  Future<void> checkKeys({bool skipDefaultDictionary = false}) async {
    initializeEV1();

    // Build the candidate list ONCE, de-duplicated by value (dictionary first,
    // then default keys minus overlaps). Previously it was rebuilt every sector
    // with an O(dict*defaults) `contains` filter, and duplicate dictionary keys
    // were re-tested on every sector.
    final seen = <String>{};
    final keyList = <Uint8List>[];
    for (final k in selectedDictionary!.keys) {
      if (seen.add(bytesToHex(k))) keyList.add(k);
    }
    if (!skipDefaultDictionary) {
      for (final k in gMifareClassicKeys) {
        if (seen.add(bytesToHex(k))) keyList.add(k);
      }
    }

    for (var sector = 0;
        sector <
            mfClassicGetSectorCount(mifareClassicType,
                isEV1: isMifareClassicEV1);
        sector++) {
      for (var keyType = 0; keyType < 2; keyType++) {
        await checkKeysOnSector(keyList, keyType, sector);
      }
    }

    // Key check part competed, checking found keys
    allKeysExists = true;
    for (var sector = 0;
        sector <
            mfClassicGetSectorCount(mifareClassicType,
                isEV1: isMifareClassicEV1);
        sector++) {
      for (var keyType = 0; keyType < 2; keyType++) {
        if (getSectorState(sector, keyType) != ChameleonKeyCheckmark.found &&
            getSectorState(sector, keyType) != ChameleonKeyCheckmark.disabled) {
          allKeysExists = false;
        }
      }
    }

    state = "";
    update();
  }

  // Standalone Darkside: recover sector 0 key B from a card with no known key
  // (weak-PRNG cards). Returns true if a key was found.
  Future<bool> recoverDarkside() async {
    state = localizations.checking_or_running_darkside;
    update();
    DarksideResult darkside;
    try {
      setCheckingSector(0, 1);
      darkside = await appState.communicator!.checkMf1Darkside();
    } catch (_) {
      setMissingSector(0, 1);
      state = "";
      update();
      return false;
    }
    if (darkside != DarksideResult.vulnerable) {
      setMissingSector(0, 1);
      error = localizations.recovery_error_no_keys_darkside;
      state = "";
      update();
      return false;
    }
    var data = await appState.communicator!.getMf1Darkside(0x03, 0x61, true, 15);
    var ds = DarksideDart(uid: data.uid, items: []);
    update();
    for (var tries = 0; tries < 5; tries++) {
      ds.items.add(DarksideItemDart(
          nt1: data.nt1, ks1: data.ks1, par: data.par, nr: data.nr, ar: data.ar));
      var keys = await recovery.darkside(ds);
      if (keys.isNotEmpty &&
          await checkKeysOnSector(mfClassicConvertKeys(keys), 1, 0)) {
        state = "";
        update();
        return true;
      }
      data = await appState.communicator!.getMf1Darkside(0x03, 0x61, false, 15);
    }
    setMissingSector(0, 1);
    error = localizations.recovery_error_no_keys_darkside;
    state = "";
    update();
    return false;
  }

  // Standalone weak-PRNG Nested: recover a target sector/keyType key from a
  // known key. Returns true if a key was found.
  Future<bool> recoverNestedSingle(Uint8List knownKey, int knownSector,
      int knownKeyType, int targetSector, int targetKeyType) async {
    int knownBlock = mfClassicGetSectorTrailerBlockBySector(knownSector);
    int targetBlock = mfClassicGetSectorTrailerBlockBySector(targetSector);
    state = localizations.collecting_nonces("Nested");
    setCheckingSector(targetSector, targetKeyType);
    update();
    try {
      NTDistance distance = await appState.communicator!
          .getMf1NTDistance(knownBlock, 0x60 + knownKeyType, knownKey);
      for (var i = 0; i < 5; i++) {
        NestedNonces nonces = await appState.communicator!.getMf1NestedNonces(
            knownBlock, 0x60 + knownKeyType, knownKey, targetBlock,
            0x60 + targetKeyType,
            level: NTLevel.weak);
        var nested = NestedDart(
            uid: distance.uid,
            distance: distance.distance,
            nt0: nonces.nonces[0].nt,
            nt0Enc: nonces.nonces[0].ntEnc,
            par0: nonces.nonces[0].parity,
            nt1: nonces.nonces[1].nt,
            nt1Enc: nonces.nonces[1].ntEnc,
            par1: nonces.nonces[1].parity);
        var keys = await recovery.nested(nested);
        if (keys.isNotEmpty &&
            await checkKeysOnSector(
                mfClassicConvertKeys(keys), targetKeyType, targetSector)) {
          state = "";
          update();
          return true;
        }
      }
    } catch (e) {
      error = e.toString();
    }
    setMissingSector(targetSector, targetKeyType);
    state = "";
    update();
    return false;
  }

  // Standalone Static-Nested: recover a target key from a known key on a
  // static-nonce card. Returns true if a key was found.
  Future<bool> recoverStaticNestedSingle(Uint8List knownKey, int knownSector,
      int knownKeyType, int targetSector, int targetKeyType) async {
    int knownBlock = mfClassicGetSectorTrailerBlockBySector(knownSector);
    int targetBlock = mfClassicGetSectorTrailerBlockBySector(targetSector);
    state = localizations.collecting_nonces("Static Nested");
    setCheckingSector(targetSector, targetKeyType);
    update();
    try {
      NTDistance distance = await appState.communicator!
          .getMf1NTDistance(knownBlock, 0x60 + knownKeyType, knownKey);
      NestedNonces nonces = await appState.communicator!.getMf1NestedNonces(
          knownBlock, 0x60 + knownKeyType, knownKey, targetBlock,
          0x60 + targetKeyType,
          level: NTLevel.static);
      var nested = StaticNestedDart(
        uid: distance.uid,
        keyType: 0x60 + knownKeyType,
        nt0: nonces.nonces[0].nt,
        nt0Enc: nonces.nonces[0].ntEnc,
        nt1: nonces.nonces[1].nt,
        nt1Enc: nonces.nonces[1].ntEnc,
      );
      var keys = await recovery.staticNested(nested);
      if (keys.isNotEmpty &&
          await checkKeysOnSector(
              mfClassicConvertKeys(keys), targetKeyType, targetSector)) {
        state = "";
        update();
        return true;
      }
    } catch (e) {
      error = e.toString();
    }
    setMissingSector(targetSector, targetKeyType);
    state = "";
    update();
    return false;
  }

  // Standalone Hardnested: recover a target key from a known key on a
  // hard-PRNG card (e.g. EV1). Returns true if a key was found.
  Future<bool> recoverHardnestedSingle(Uint8List knownKey, int knownSector,
      int knownKeyType, int targetSector, int targetKeyType) async {
    int knownBlock = mfClassicGetSectorTrailerBlockBySector(knownSector);
    int targetBlock = mfClassicGetSectorTrailerBlockBySector(targetSector);
    state = localizations.collecting_nonces("Hard Nested");
    setCheckingSector(targetSector, targetKeyType);
    hardnestedProgress = 0;
    update();
    try {
      NTDistance distance = await appState.communicator!
          .getMf1NTDistance(knownBlock, 0x60 + knownKeyType, knownKey);
      var result = await collectHardnestedNonces(
          knownBlock, 0x60 + knownKeyType, knownKey, targetBlock,
          0x60 + targetKeyType);
      if (result is String) {
        error = result;
        setMissingSector(targetSector, targetKeyType);
        hardnestedProgress = null;
        state = "";
        update();
        return false;
      }
      NestedNonces nonces = result as NestedNonces;
      var nested = HardNestedDart(nonces: nonces.getHardNested(distance.uid));
      var keys = await recovery.hardNested(nested);
      hardnestedProgress = null;
      if (keys.isNotEmpty &&
          await checkKeysOnSector(
              mfClassicConvertKeys(keys), targetKeyType, targetSector)) {
        state = "";
        update();
        return true;
      }
    } catch (e) {
      error = e.toString();
    }
    hardnestedProgress = null;
    setMissingSector(targetSector, targetKeyType);
    state = "";
    update();
    return false;
  }

  // Standalone Static-Encrypted Nested (Fudan FM11RF08S backdoor, eprint
  // 2024/1275). Reuses the FFI staticEncryptedNested + StaticEncryptedKeysFilter
  // like recoverKeys(), but adds the Proxmark3 staticnested orchestration
  // speedups: cross-sector key-reuse prioritisation, default-key prioritisation
  // and the nt(A)==nt(B) => keyA==keyB shortcut. Ordering-only: every candidate
  // is still confirmed on-card by checkKeysOnSector, so it can only be faster,
  // never wrong. Returns true if any key was found.
  Future<bool> recoverBackdoor() async {
    error = ""; // clear any stale error from a previous run
    final keyKnownAtEntry = validKeys.map((k) => k.isNotEmpty).toList();
    state = localizations.checking_card_info;
    update();
    if (!await mfClassicHasBackdoor(appState.communicator!)) {
      error = localizations.no_backdoor_support;
      state = "";
      update();
      return false;
    }
    final sectors =
        mfClassicGetSectorCount(mifareClassicType, isEV1: isMifareClassicEV1);
    final backdoorInfo = await appState.communicator!
        .getMf1StaticEncryptedNestedAcquire(sectorCount: sectors);
    if (backdoorInfo == null) {
      error = localizations.no_backdoor_support;
      state = "";
      update();
      return false;
    }

    // ---- Phase 1: collect filtered A/B candidate lists for every sector ----
    final candA = <int, List<Uint8List>>{};
    final candB = <int, List<Uint8List>>{};
    final rawA = <int, List<int>>{}; // unfiltered A candidates for findMatchingKeys
    final sameNt = <int, bool>{};
    for (var sector = 0; sector < sectors; sector++) {
      // Phase 1 is a collect-all pass: show ONLY global progress so we don't
      // light up every block as "checking" at once (blocks keep their state;
      // phase 3 animates each block as it is confirmed).
      state = "${localizations.collecting_nonces("Backdoor")} ${sector + 1}/$sectors";
      keyCheckProgress = sectors == 0 ? null : sector / sectors;
      update();

      // Skip sectors already resolved (e.g. by the dictionary pass), and guard
      // against an acquire that returned fewer nonces than sectors (would throw
      // a RangeError on nonces[sector]).
      final aDone = getSectorState(sector, 0) == ChameleonKeyCheckmark.found ||
          getSectorState(sector, 0) == ChameleonKeyCheckmark.disabled;
      final bDone = getSectorState(sector, 1) == ChameleonKeyCheckmark.found ||
          getSectorState(sector, 1) == ChameleonKeyCheckmark.disabled;
      if ((aDone && bDone) ||
          sector >= backdoorInfo.$2.nonces.length ||
          sector >= backdoorInfo.$3.nonces.length) {
        candA[sector] = [];
        candB[sector] = [];
        rawA[sector] = [];
        sameNt[sector] = false;
        continue;
      }

      final aN = backdoorInfo.$2.nonces[sector];
      final bN = backdoorInfo.$3.nonces[sector];
      sameNt[sector] = aN.nt == bN.nt;
      try {
        final possibleAKeys = await recovery.staticEncryptedNested(
            StaticEncryptedNestedDart(
                uid: backdoorInfo.$1,
                nt: aN.nt,
                ntEnc: aN.ntEnc,
                ntParEnc: aN.parity));
        final possibleBKeys = await recovery.staticEncryptedNested(
            StaticEncryptedNestedDart(
                uid: backdoorInfo.$1,
                nt: bN.nt,
                ntEnc: bN.ntEnc,
                ntParEnc: bN.parity));
        rawA[sector] = possibleAKeys;
        final filtered = await StaticEncryptedKeysFilterAsync.filterKeys(
            possibleAKeys, possibleBKeys, aN.nt, bN.nt);
        candA[sector] = mfClassicConvertKeys(filtered.$1.reversed.toList());
        candB[sector] = mfClassicConvertKeys(filtered.$2.reversed.toList());
      } catch (_) {
        // Non-fatal: skip this sector, keep going (don't surface as error).
        candA[sector] = [];
        candB[sector] = [];
        rawA[sector] = [];
      }
    }
    keyCheckProgress = null;

    // ---- Phase 2: build priority set (cross-sector duplicates + defaults) ---
    final counts = <String, int>{};
    void tally(List<Uint8List> l) {
      for (final k in l) {
        final h = bytesToHex(k);
        counts[h] = (counts[h] ?? 0) + 1;
      }
    }
    for (var s = 0; s < sectors; s++) {
      tally(candA[s]!);
      tally(candB[s]!);
    }
    final defaultSet = gMifareClassicKeys.map(bytesToHex).toSet();
    List<Uint8List> prioritise(List<Uint8List> list) {
      final pri = <Uint8List>[];
      final rest = <Uint8List>[];
      for (final k in list) {
        final h = bytesToHex(k);
        if ((counts[h] ?? 0) >= 2 || defaultSet.contains(h)) {
          pri.add(k);
        } else {
          rest.add(k);
        }
      }
      // Most-reused candidates first (the more sectors a key appears in, the
      // likelier it is the real reused key) so the on-card hit comes sooner.
      pri.sort((a, b) =>
          (counts[bytesToHex(b)] ?? 0).compareTo(counts[bytesToHex(a)] ?? 0));
      return [...pri, ...rest];
    }

    // ---- Phase 3: confirm keys on card, priority candidates first ----------
    for (var sector = 0; sector < sectors; sector++) {
      if (sector >= backdoorInfo.$2.nonces.length ||
          sector >= backdoorInfo.$3.nonces.length) {
        continue; // no nonces collected for this sector (guarded in phase 1)
      }
      final aN = backdoorInfo.$2.nonces[sector];
      final bN = backdoorInfo.$3.nonces[sector];
      try {
        // Key B
        if (getSectorState(sector, 1) != ChameleonKeyCheckmark.found &&
            getSectorState(sector, 1) != ChameleonKeyCheckmark.disabled) {
          await checkKeysOnSector(prioritise(candB[sector]!), 1, sector);
        }
        // nt(A)==nt(B) => same key: reuse the recovered B key for A
        if (sameNt[sector]! &&
            getSectorState(sector, 1) == ChameleonKeyCheckmark.found &&
            getSectorState(sector, 0) != ChameleonKeyCheckmark.found) {
          await checkKeysOnSector([getSectorKey(sector, 1)], 0, sector);
        }
        // Key A (direct candidates, then derived from the recovered B key)
        if (getSectorState(sector, 0) != ChameleonKeyCheckmark.found &&
            getSectorState(sector, 0) != ChameleonKeyCheckmark.disabled) {
          final aFound =
              await checkKeysOnSector(prioritise(candA[sector]!), 0, sector);
          if (!aFound &&
              getSectorState(sector, 1) == ChameleonKeyCheckmark.found) {
            final matching =
                await StaticEncryptedKeysFilterAsync.findMatchingKeys(
                    bN.nt,
                    bytesToU64(
                        Uint8List.fromList([0, 0, ...validKeys[sector + 40]])),
                    aN.nt,
                    rawA[sector]!);
            await checkKeysOnSector(mfClassicConvertKeys(matching), 0, sector);
          }
        }
      } catch (_) {
        // Non-fatal: this sector failed to confirm; continue with the rest.
      }
      setMissingSector(sector, 0);
      setMissingSector(sector, 1);
    }
    state = "";
    update();
    // Success = a key recovered THIS call (ignore pre-seeded EV1 keys).
    for (var idx = 0; idx < validKeys.length; idx++) {
      if (validKeys[idx].isNotEmpty && !keyKnownAtEntry[idx]) return true;
    }
    return false;
  }

  Future<void> recoverKeys() async {
    state = localizations.checking_card_info;
    update();

    error = "";
    bool hasKey = false;
    bool hasBackdoor = await mfClassicHasBackdoor(appState.communicator!);
    (int, NestedNonces, NestedNonces, Uint8List)? backdoorInfo;
    if (hasBackdoor) {
      backdoorInfo = await appState.communicator!
          .getMf1StaticEncryptedNestedAcquire(
              sectorCount: mfClassicGetSectorCount(mifareClassicType,
                  isEV1: isMifareClassicEV1));
    }

    DarksideResult darkside = DarksideResult.fixed;
    for (var sector = 0;
        sector <
                mfClassicGetSectorCount(mifareClassicType,
                    isEV1: isMifareClassicEV1) &&
            !hasKey;
        sector++) {
      for (var keyType = 0; keyType < 2; keyType++) {
        if (getSectorState(sector, keyType) == ChameleonKeyCheckmark.found) {
          hasKey = true;
          break;
        }
      }
    }

    update();

    bool isStaticEncrypted = false;

    if (hasBackdoor) {
      isStaticEncrypted = await mfClassicIsStaticEncrypted(
          appState.communicator!, 0, 4, backdoorInfo!.$4);
    }

    NTLevel prng = await appState.communicator!.getMf1NTLevel();
    update();

    if (!hasKey && !isStaticEncrypted && prng != NTLevel.static) {
      state = localizations.checking_or_running_darkside;
      update();

      try {
        setCheckingSector(0, 1);
        darkside = await appState.communicator!.checkMf1Darkside();
      } catch (_) {
        setMissingSector(0, 1);
      }

      if (darkside == DarksideResult.vulnerable) {
        // recover with darkside
        var data =
            await appState.communicator!.getMf1Darkside(0x03, 0x61, true, 15);
        var darkside = DarksideDart(uid: data.uid, items: []);
        bool found = false;
        update();

        for (var tries = 0; tries < 5 && !found; tries++) {
          darkside.items.add(DarksideItemDart(
              nt1: data.nt1,
              ks1: data.ks1,
              par: data.par,
              nr: data.nr,
              ar: data.ar));

          var keys = await recovery.darkside(darkside);
          if (keys.isNotEmpty) {
            appState.log!.d("Darkside: Found keys: $keys. Checking them...");

            if (await checkKeysOnSector(mfClassicConvertKeys(keys), 1, 0)) {
              found = true;
              hasKey = true;

              break;
            }
          } else {
            appState.log!.d("Can't find keys, retrying...");
            data = await appState.communicator!
                .getMf1Darkside(0x03, 0x61, false, 15);
          }
        }

        if (!found) {
          setMissingSector(0, 1);
        }
      }
    }

    update();

    if (!hasKey && hasBackdoor && prng == NTLevel.weak && !isStaticEncrypted) {
      state = localizations.backdoor_recovery_of_non_static_encrypted;
      setCheckingSector(0, 0);

      for (var i = 0; i < 3; i++) {
        NTDistance distance = await appState.communicator!
            .getMf1NTDistance(0, 0x64, backdoorInfo!.$4);

        NestedNonces nonces = await appState.communicator!
            .getMf1NestedNonces(0, 0x64, backdoorInfo.$4, 0, 0x60, level: prng);

        var nested = NestedDart(
            uid: distance.uid,
            distance: distance.distance,
            nt0: nonces.nonces[0].nt,
            nt0Enc: nonces.nonces[0].ntEnc,
            par0: nonces.nonces[0].parity,
            nt1: nonces.nonces[1].nt,
            nt1Enc: nonces.nonces[1].ntEnc,
            par1: nonces.nonces[1].parity);

        List<int> keys = await recovery.nested(nested);

        if (keys.isNotEmpty) {
          appState.log!.d("Found keys: $keys. Checking them...");
          if (await checkKeysOnSector(mfClassicConvertKeys(keys), 0, 0)) {
            break;
          }
        }
      }
    }

    Uint8List validKey = Uint8List(0);
    int validKeyBlock = 0;
    int validKeyType = -1;

    for (var sector = 0;
        sector <
            mfClassicGetSectorCount(mifareClassicType,
                isEV1: isMifareClassicEV1);
        sector++) {
      for (var keyType = 0; keyType < 2; keyType++) {
        if (getSectorState(sector, keyType) == ChameleonKeyCheckmark.found) {
          validKey = getSectorKey(sector, keyType);
          validKeyBlock = mfClassicGetSectorTrailerBlockBySector(sector);
          validKeyType = keyType;
          if (!isStaticEncrypted) {
            isStaticEncrypted = await mfClassicIsStaticEncrypted(
                appState.communicator!, validKeyBlock, validKeyType, validKey);
          }
          break;
        }
      }
    }

    if ((isStaticEncrypted || (validKeyType == -1 && hasBackdoor)) &&
        backdoorInfo != null) {
      prng = NTLevel.backdoor;
    }

    if (validKeyType == -1 && prng != NTLevel.backdoor) {
      error = localizations.recovery_error_no_keys_darkside;
      state = "";
      return;
    }

    int tries = [NTLevel.backdoor, NTLevel.static].contains(prng) ? 1 : 5;

    // RF08S backdoor: delegate to the optimized standalone recovery — it collects
    // every sector's candidates (global progress bar, no all-blocks flash),
    // prioritises cross-sector duplicate + default keys, and confirms each block
    // per-sector (animation). The per-sector loop below is skipped for this case.
    if (prng == NTLevel.backdoor) {
      await recoverBackdoor();
    }

    for (var sector = 0;
        prng != NTLevel.backdoor &&
            sector <
                mfClassicGetSectorCount(mifareClassicType,
                    isEV1: isMifareClassicEV1);
        sector++) {
      for (var keyType = 0; keyType < 2; keyType++) {
        if (getSectorState(sector, keyType) == ChameleonKeyCheckmark.none) {
          String attackType;

          switch (prng) {
            case NTLevel.static:
              attackType = "Static Nested";
            case NTLevel.weak:
              attackType = "Nested";
            case NTLevel.hard:
              attackType = "Hard Nested";
            case NTLevel.backdoor:
              attackType = localizations.has_backdoor_support;
            case NTLevel.unknown:
              attackType = "";
          }

          state = localizations.collecting_nonces(attackType);
          setCheckingSector(sector, keyType);

          NTDistance? distance;
          NestedNonces? nonces;

          if (prng != NTLevel.backdoor) {
            distance = await appState.communicator!
                .getMf1NTDistance(validKeyBlock, 0x60 + validKeyType, validKey);
          }

          bool found = false;
          // Weak nested: candidate sets from successive nonce collections are
          // intersected here so we test a handful on-card instead of ~26000.
          Set<int>? weakCandidates;
          for (var i = 0; i < tries && !found; i++) {
            List<int> keys = [];

            if (prng == NTLevel.hard) {
              hardnestedProgress = 0;
              update();

              var result = await collectHardnestedNonces(
                  validKeyBlock,
                  0x60 + validKeyType,
                  validKey,
                  mfClassicGetSectorTrailerBlockBySector(sector),
                  0x60 + keyType);

              if (result is String) {
                setMissingSector(sector, keyType);
                error = result;
                return;
              } else {
                nonces = result as NestedNonces;
              }
            } else if (prng != NTLevel.backdoor) {
              nonces = await appState.communicator!.getMf1NestedNonces(
                  validKeyBlock,
                  0x60 + validKeyType,
                  validKey,
                  mfClassicGetSectorTrailerBlockBySector(sector),
                  0x60 + keyType,
                  level: prng);
            }

            state = localizations.recovering_key(attackType);
            update();

            if (prng == NTLevel.weak) {
              var nested = NestedDart(
                  uid: distance!.uid,
                  distance: distance.distance,
                  nt0: nonces!.nonces[0].nt,
                  nt0Enc: nonces.nonces[0].ntEnc,
                  par0: nonces.nonces[0].parity,
                  nt1: nonces.nonces[1].nt,
                  nt1Enc: nonces.nonces[1].ntEnc,
                  par1: nonces.nonces[1].parity);

              // Intersect candidate sets across collections. The real key is in
              // every set, so a few rounds shrink ~26000 candidates to a handful
              // — avoiding thousands of on-card auths. Never empty the set (keep
              // the latest), so the worst case is the old single-pass behaviour.
              final set = (await recovery.nested(nested)).toSet();
              if (weakCandidates == null) {
                weakCandidates = set;
              } else {
                final inter = weakCandidates.intersection(set);
                weakCandidates = inter.isEmpty ? set : inter;
              }
              // Still large and tries remain -> collect another pair to narrow
              // further before spending time testing on-card.
              if (weakCandidates.length > 20 && i < tries - 1) {
                continue;
              }
              keys = weakCandidates.toList();
            } else if (prng == NTLevel.static) {
              var nested = StaticNestedDart(
                uid: distance!.uid,
                keyType: 0x60 + validKeyType,
                nt0: nonces!.nonces[0].nt,
                nt0Enc: nonces.nonces[0].ntEnc,
                nt1: nonces.nonces[1].nt,
                nt1Enc: nonces.nonces[1].ntEnc,
              );

              keys = await recovery.staticNested(nested);
            } else if (prng == NTLevel.hard) {
              var nested =
                  HardNestedDart(nonces: nonces!.getHardNested(distance!.uid));
              keys = await recovery.hardNested(nested);
            } else if (prng == NTLevel.backdoor) {
              setCheckingSector(sector, 1);

              var possibleAKeys = await recovery.staticEncryptedNested(
                  StaticEncryptedNestedDart(
                      uid: backdoorInfo!.$1,
                      nt: backdoorInfo.$2.nonces[sector].nt,
                      ntEnc: backdoorInfo.$2.nonces[sector].ntEnc,
                      ntParEnc: backdoorInfo.$2.nonces[sector].parity));

              var possibleBKeys = await recovery.staticEncryptedNested(
                  StaticEncryptedNestedDart(
                      uid: backdoorInfo.$1,
                      nt: backdoorInfo.$3.nonces[sector].nt,
                      ntEnc: backdoorInfo.$3.nonces[sector].ntEnc,
                      ntParEnc: backdoorInfo.$3.nonces[sector].parity));

              var filtered = await StaticEncryptedKeysFilterAsync.filterKeys(
                  possibleAKeys,
                  possibleBKeys,
                  backdoorInfo.$2.nonces[sector].nt,
                  backdoorInfo.$3.nonces[sector].nt);

              if (checkMarks[sector + 40] != ChameleonKeyCheckmark.found &&
                  checkMarks[sector + 40] != ChameleonKeyCheckmark.disabled &&
                  await checkKeysOnSector(
                      mfClassicConvertKeys(filtered.$2.reversed.toList()),
                      1,
                      sector)) {
                checkMarks[sector + 40] = ChameleonKeyCheckmark.found;
              }

              if (checkMarks[sector] == ChameleonKeyCheckmark.found ||
                  checkMarks[sector] == ChameleonKeyCheckmark.disabled) {
                found = true;
                break;
              } else if (await checkKeysOnSector(
                  mfClassicConvertKeys(
                      await StaticEncryptedKeysFilterAsync.findMatchingKeys(
                          backdoorInfo.$3.nonces[sector].nt,
                          bytesToU64(Uint8List.fromList(
                              [0, 0, ...validKeys[sector + 40]])),
                          backdoorInfo.$2.nonces[sector].nt,
                          possibleAKeys)),
                  0,
                  sector)) {
                found = true;
                break;
              } else if (await checkKeysOnSector(
                  mfClassicConvertKeys(filtered.$1.reversed.toList()),
                  0,
                  sector)) {
                found = true;
                break;
              }

              setMissingSector(sector, 0);
              setMissingSector(sector, 1);
            }

            if (keys.isNotEmpty) {
              appState.log!.d("Found keys: $keys. Checking them...");

              if (await checkKeysOnSector(
                  mfClassicConvertKeys(keys), keyType, sector)) {
                found = true;

                break;
              }
            } else {
              appState.log!.e("Can't find keys, retrying...");
            }
          }
        }
      }
    }

    state = "";
    allKeysExists = true;
    for (var sector = 0;
        sector <
            mfClassicGetSectorCount(mifareClassicType,
                isEV1: isMifareClassicEV1);
        sector++) {
      for (var keyType = 0; keyType < 2; keyType++) {
        if (getSectorState(sector, keyType) != ChameleonKeyCheckmark.found &&
            getSectorState(sector, keyType) != ChameleonKeyCheckmark.disabled) {
          allKeysExists = false;
        }
      }
    }
    update();
  }

  Future<void> dumpData() async {
    cardData = List.generate(256, (_) => Uint8List(0));

    for (var sector = 0;
        sector <
            mfClassicGetSectorCount(mifareClassicType,
                isEV1: isMifareClassicEV1);
        sector++) {
      for (var block = 0;
          block < mfClassicGetBlockCountBySector(sector);
          block++) {
        for (var keyType = 0; keyType < 2; keyType++) {
          appState.log!
              .d("Dumping sector $sector, block $block with key $keyType");

          if (getSectorKey(sector, keyType).isEmpty) {
            appState.log!.w("Skipping missing key");
            cardData[block + mfClassicGetFirstBlockCountBySector(sector)] =
                Uint8List(16);
            continue;
          }

          var blockData = await appState.communicator!.mf1ReadBlock(
              block + mfClassicGetFirstBlockCountBySector(sector),
              0x60 + keyType,
              getSectorKey(sector, keyType));

          if (blockData.isEmpty) {
            if (keyType == 1) {
              blockData = Uint8List(16);
            } else {
              continue;
            }
          }

          if (mfClassicGetSectorTrailerBlockBySector(sector) ==
              block + mfClassicGetFirstBlockCountBySector(sector)) {
            // set keys in sector trailer
            if (getSectorKey(sector, 0).isNotEmpty) {
              blockData.setRange(0, 6, getSectorKey(sector, 0));
            }

            if (getSectorKey(sector, 1).isNotEmpty) {
              blockData.setRange(10, 16, getSectorKey(sector, 1));
            }
          }

          cardData[block + mfClassicGetFirstBlockCountBySector(sector)] =
              blockData;

          dumpProgress = (block + mfClassicGetFirstBlockCountBySector(sector)) /
              (mfClassicGetBlockCount(mifareClassicType,
                  isEV1: isMifareClassicEV1));

          update();

          break;
        }
      }
    }
  }

  Future<dynamic> collectHardnestedNonces(int block, int keyType,
      Uint8List knownKey, int targetBlock, int targetKeyType) async {
    NestedNonces nonces = NestedNonces(nonces: []);
    while (true) {
      var collectedNonces = await appState.communicator!.getMf1NestedNonces(
          block, keyType, knownKey, targetBlock, targetKeyType,
          level: NTLevel.hard);
      nonces.nonces.addAll(collectedNonces.nonces);
      List info = nonces.getNoncesInfo();
      appState.log!.d(
          "Collected ${nonces.nonces.length} nonces, sum ${info[0]}, num ${info[1]}");

      if (nonces.nonces.isEmpty) {
        return localizations.recovery_old_firmware;
      }

      hardnestedProgress = info[1] / 256;
      state = localizations.hardnested_collecting_nonces(
          (hardnestedProgress! * 256).toInt().toString());
      update();
      if (info[1] == 256) {
        if ([
          0,
          32,
          56,
          64,
          80,
          96,
          104,
          112,
          120,
          128,
          136,
          144,
          152,
          160,
          176,
          192,
          200,
          224,
          256
        ].contains(info[0])) {
          break;
        }

        appState.log!.e("Got wrong sum, trying to collect nonces again...");
        nonces.nonces = [];
      }
    }

    hardnestedProgress = null;
    return nonces;
  }

  void setKeyAsFound(int sector, int keyType, Uint8List key) {
    checkMarks[sector + (keyType * 40)] = ChameleonKeyCheckmark.found;
    validKeys[sector + (keyType * 40)] = key;
    update();
  }

  void setCheckingSector(int sector, int keyType) {
    if (getSectorState(sector, keyType) == ChameleonKeyCheckmark.none) {
      checkMarks[sector + (keyType * 40)] = ChameleonKeyCheckmark.checking;
    }
    update();
  }

  void setMissingSector(int sector, int keyType) {
    if (getSectorState(sector, keyType) == ChameleonKeyCheckmark.checking) {
      checkMarks[sector + (keyType * 40)] = ChameleonKeyCheckmark.none;
      update();
    }
  }

  Uint8List getSectorKey(int sector, int keyType) {
    return validKeys[sector + (keyType * 40)];
  }

  ChameleonKeyCheckmark getSectorState(int sector, int keyType) {
    return checkMarks[sector + (keyType * 40)];
  }
}

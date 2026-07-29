import 'dart:typed_data';

import 'package:chameleonultragui/generated/i18n/app_localizations.dart';
import 'package:chameleonultragui/gui/menu/hacking/autopwn_plus.dart';
import 'package:chameleonultragui/helpers/general.dart';
import 'package:chameleonultragui/helpers/mifare_classic/autopwn_plus.dart';
import 'package:chameleonultragui/helpers/mifare_classic/recovery.dart';
import 'package:chameleonultragui/main.dart';
import 'package:chameleonultragui/sharedprefsprovider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('Autopwn+ ETA', () {
    test('estimates remaining time from elapsed time and progress', () {
      expect(
        estimateAutopwnPlusEta(const Duration(seconds: 10), 0.25),
        const Duration(seconds: 30),
      );
      expect(
        estimateAutopwnPlusEta(const Duration(seconds: 10), 0.5),
        const Duration(seconds: 10),
      );
    });

    test('returns no estimate without measurable progress', () {
      expect(estimateAutopwnPlusEta(const Duration(seconds: 10), null), isNull);
      expect(estimateAutopwnPlusEta(const Duration(seconds: 10), 0), isNull);
      expect(estimateAutopwnPlusEta(Duration.zero, 0.5), isNull);
    });

    test('returns zero when the phase is complete', () {
      expect(
        estimateAutopwnPlusEta(const Duration(seconds: 10), 1),
        Duration.zero,
      );
    });
  });

  group('Autopwn+ candidate planner', () {
    test('deduplicates, validates, and prioritizes verified/default keys', () {
      final verified = Uint8List.fromList([1, 2, 3, 4, 5, 6]);
      final dictionary = Dictionary(
        name: 'test',
        keys: [
          Uint8List.fromList([0xA0, 0xA1, 0xA2, 0xA3, 0xA4, 0xA5]),
          verified,
          Uint8List(5),
        ],
      );

      final candidates = buildAutopwnPlusCandidates(
        profile: AutopwnPlusProfile.balanced,
        dictionaries: [dictionary],
        verifiedKeys: [verified],
      );

      expect(bytesToHex(candidates.first), bytesToHex(verified));
      expect(candidates.every((key) => key.length == 6), isTrue);
      expect(candidates.map(bytesToHex).toSet().length, candidates.length);
      expect(
        candidates.map(bytesToHex),
        contains('a0a1a2a3a4a5'),
      );
    });

    test('waves preserve every candidate exactly once', () {
      final candidates = [
        for (var i = 0; i < 90; i++)
          Uint8List.fromList([0, 0, 0, 0, i >> 8, i & 0xFF]),
      ];

      final waves = buildAutopwnPlusWaves(AutopwnPlusProfile.deep, candidates);
      final flattened = waves.expand((wave) => wave).toList();

      expect(waves.map((wave) => wave.length), [16, 48, 26]);
      expect(flattened.map(bytesToHex), candidates.map(bytesToHex));
    });

    test('quick profile caps expensive dictionary breadth', () {
      final dictionary = Dictionary(
        keys: [
          for (var i = 0; i < 100; i++)
            Uint8List.fromList([1, 2, 3, 4, i >> 8, i & 0xFF]),
        ],
      );
      final candidates = buildAutopwnPlusCandidates(
        profile: AutopwnPlusProfile.quick,
        dictionaries: [dictionary],
        verifiedKeys: const [],
        includeDefaults: false,
      );
      expect(candidates, hasLength(64));
    });
  });

  group('Autopwn+ runner', () {
    test('uses adaptive waves, skips attacks in quick mode, and partial dumps',
        () async {
      final port = _FakePort(resolveOnCheck: true);
      final phases = <AutopwnPlusPhase>[];
      final result = await const AutopwnPlusRunner().run(
        recovery: port,
        options: AutopwnPlusOptions(
          profile: AutopwnPlusProfile.quick,
          sectors: const {0},
          dictionaries: [
            Dictionary(keys: [
              Uint8List.fromList([1, 2, 3, 4, 5, 6])
            ]),
          ],
          includeDefaults: false,
          recoverMissing: false,
        ),
        onProgress: (progress) => phases.add(progress.phase),
      );

      expect(port.calls, ['prepare', 'verify', 'check:0:0:1', 'dump']);
      expect(port.recoveryCalled, isFalse);
      expect(result.selectedKeysRecovered, isTrue);
      expect(result.blocks.single.readable, isFalse);
      expect(
          phases,
          containsAllInOrder([
            AutopwnPlusPhase.verifying,
            AutopwnPlusPhase.dictionary,
            AutopwnPlusPhase.dump,
            AutopwnPlusPhase.complete,
          ]));
    });

    test('runs card-adaptive recovery only while selected keys are unresolved',
        () async {
      final port = _FakePort(resolveOnCheck: false, resolveOnRecovery: true);
      final result = await const AutopwnPlusRunner().run(
        recovery: port,
        options: const AutopwnPlusOptions(
          profile: AutopwnPlusProfile.balanced,
          sectors: {0},
          dictionaries: [],
          includeDefaults: false,
          recoverMissing: true,
          partialDump: false,
        ),
      );

      expect(port.recoveryCalled, isTrue);
      expect(port.dumpCalled, isFalse);
      expect(result.selectedKeysRecovered, isTrue);
    });

    test('cooperative cancellation queues no recovery or dump after a check',
        () async {
      final port = _FakePort(cancelOnCheck: true);
      final result = await const AutopwnPlusRunner().run(
        recovery: port,
        options: AutopwnPlusOptions(
          profile: AutopwnPlusProfile.balanced,
          sectors: const {0},
          dictionaries: [
            Dictionary(keys: [
              Uint8List.fromList([1, 2, 3, 4, 5, 6])
            ]),
          ],
          includeDefaults: false,
        ),
      );

      expect(result.cancelled, isTrue);
      expect(port.recoveryCalled, isFalse);
      expect(port.dumpCalled, isFalse);
    });

    test('card guard aborts before results can mix two cards', () async {
      final port = _FakePort();
      var checks = 0;

      await expectLater(
        const AutopwnPlusRunner().run(
          recovery: port,
          options: AutopwnPlusOptions(
            profile: AutopwnPlusProfile.quick,
            sectors: const {0},
            dictionaries: [
              Dictionary(keys: [
                Uint8List.fromList([1, 2, 3, 4, 5, 6])
              ]),
            ],
            includeDefaults: false,
            recoverMissing: false,
          ),
          cardGuard: () async => ++checks < 3,
        ),
        throwsA(isA<AutopwnPlusCardChanged>()),
      );
      expect(port.recoveryCalled, isFalse);
      expect(port.dumpCalled, isFalse);
    });

    test('cancelled dump retains blocks completed before cancellation',
        () async {
      final port = _FakePort(resolveOnCheck: true, cancelOnDump: true);
      final result = await const AutopwnPlusRunner().run(
        recovery: port,
        options: AutopwnPlusOptions(
          profile: AutopwnPlusProfile.quick,
          sectors: const {0},
          dictionaries: [
            Dictionary(keys: [
              Uint8List.fromList([1, 2, 3, 4, 5, 6])
            ]),
          ],
          includeDefaults: false,
          recoverMissing: false,
        ),
      );

      expect(result.cancelled, isTrue);
      expect(result.blocks, hasLength(1));
      expect(result.toJson()['verifiedKeys'], isNotEmpty);
    });
  });

  testWidgets('new page is responsive before a card is scanned',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final preferences = SharedPreferencesProvider();
    await preferences.load();
    final appState = ChameleonGUIState(preferences);
    addTearDown(appState.dispose);
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ChangeNotifierProvider<ChameleonGUIState>.value(
        value: appState,
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: const TextScaler.linear(1.8),
            ),
            child: child!,
          ),
          home: const AutopwnPlusPage(),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Autopwn+'), findsOneWidget);
    expect(find.text('Scan card'), findsOneWidget);
    expect(find.text('Run Autopwn+'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

class _FakePort implements AutopwnPlusRecoveryPort {
  final bool resolveOnCheck;
  final bool resolveOnRecovery;
  final bool cancelOnCheck;
  final bool cancelOnDump;
  final List<String> calls = [];
  bool recoveryCalled = false;
  bool dumpCalled = false;
  bool _cancelled = false;
  bool _resolved = false;
  final List<Uint8List> _keys = [Uint8List(0), Uint8List(0)];
  final List<AutopwnPlusBlock> _dumpedBlocks = [];

  _FakePort({
    this.resolveOnCheck = false,
    this.resolveOnRecovery = false,
    this.cancelOnCheck = false,
    this.cancelOnDump = false,
  });

  @override
  int get sectorCount => 1;

  @override
  bool get isCancelled => _cancelled;

  @override
  String get error => '';

  @override
  List<Uint8List> get validKeys => _keys;

  @override
  List<AutopwnPlusBlock> get dumpedBlocks => List.unmodifiable(_dumpedBlocks);

  @override
  void cancel() => _cancelled = true;

  @override
  Future<void> prepare(Set<int> sectors) async => calls.add('prepare');

  @override
  Future<int> reverifySeededKeys(Set<int> sectors) async {
    calls.add('verify');
    return 0;
  }

  @override
  List<AutopwnPlusTarget> unresolvedTargets(Set<int> sectors) =>
      _resolved ? [] : const [AutopwnPlusTarget(0, 0)];

  @override
  Future<bool> checkTarget(
      AutopwnPlusTarget target, List<Uint8List> candidates) async {
    calls.add('check:${target.sector}:${target.keyType}:${candidates.length}');
    if (cancelOnCheck) _cancelled = true;
    if (resolveOnCheck) {
      _resolved = true;
      _keys[0] = Uint8List.fromList(candidates.first);
    }
    return _resolved;
  }

  @override
  Future<void> recoverMissing() async {
    recoveryCalled = true;
    calls.add('recover');
    _resolved = resolveOnRecovery;
  }

  @override
  bool selectedComplete(Set<int> sectors) => _resolved;

  @override
  int verifiedSlots(Set<int> sectors) => _resolved ? 1 : 0;

  @override
  List<AutopwnPlusVerifiedKey> verifiedKeys(Set<int> sectors) => _resolved
      ? [AutopwnPlusVerifiedKey(sector: 0, keyType: 0, key: _keys[0])]
      : [];

  @override
  Future<List<AutopwnPlusBlock>> dumpSelected(
    Set<int> sectors,
    void Function(int completed, int total) onProgress, {
    Future<bool> Function()? cardGuard,
  }) async {
    dumpCalled = true;
    calls.add('dump');
    onProgress(1, 1);
    _dumpedBlocks
      ..clear()
      ..add(const AutopwnPlusBlock(
        sector: 0,
        block: 0,
        data: null,
        syntheticKeys: false,
      ));
    if (cancelOnDump) {
      _cancelled = true;
      throw MifareClassicRecoveryCancelled();
    }
    return List.unmodifiable(_dumpedBlocks);
  }
}

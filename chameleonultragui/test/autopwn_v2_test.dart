import 'dart:typed_data';

import 'package:chameleonultragui/generated/i18n/app_localizations.dart';
import 'package:chameleonultragui/gui/menu/hacking/autopwn_v2.dart';
import 'package:chameleonultragui/helpers/definitions.dart';
import 'package:chameleonultragui/helpers/general.dart';
import 'package:chameleonultragui/helpers/mifare_classic/autopwn_v2.dart';
import 'package:chameleonultragui/main.dart';
import 'package:chameleonultragui/sharedprefsprovider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('Autopwn v2 candidate ledger', () {
    test('prioritizes selected dictionaries and retains every unique key', () {
      final dictionaryKeys = [
        for (var i = 0; i < 130; i++)
          Uint8List.fromList([1, 2, 3, 4, i >> 8, i & 0xFF]),
      ];
      final waves = buildAutopwnV2CandidateWaves(
        dictionaries: [Dictionary(name: 'all', keys: dictionaryKeys)],
        waveSize: 32,
      );
      final flattened = waves.expand((wave) => wave).toList();

      expect(waves.every((wave) => wave.length <= 32), isTrue);
      expect(
        flattened.take(dictionaryKeys.length).map(bytesToHex),
        dictionaryKeys.map(bytesToHex),
      );
      expect(flattened.map(bytesToHex).toSet().length, flattened.length);
      expect(flattened.length, greaterThanOrEqualTo(dictionaryKeys.length));
    });

    test('records duplicate support without duplicating verification', () {
      final key = Uint8List.fromList([1, 2, 3, 4, 5, 6]);
      final ledger = AutopwnV2CandidateLedger()
        ..addAll([key], AutopwnV2CandidateOrigin.defaultKey)
        ..addAll([key, key], AutopwnV2CandidateOrigin.selectedDictionary);

      final evidence = ledger.ranked.single;
      expect(evidence.support, 3);
      expect(
        evidence.origins,
        containsAll([
          AutopwnV2CandidateOrigin.selectedDictionary,
          AutopwnV2CandidateOrigin.defaultKey,
        ]),
      );
    });
  });

  group('Autopwn v2 runner', () {
    test(
      'plans attacks per target, verifies the result, and creates a dump',
      () async {
        final dictionaryKey = Uint8List.fromList([1, 2, 3, 4, 5, 6]);
        final port = _FakeV2Port(
          resolveDictionaryTarget: const AutopwnV2Target(0, 0),
          dictionaryKey: dictionaryKey,
          outcomes: {
            const AutopwnV2Target(0, 1): {
              AutopwnV2Attack.nested: AutopwnV2AttemptOutcome.found,
            },
            const AutopwnV2Target(1, 0): {
              AutopwnV2Attack.nested: AutopwnV2AttemptOutcome.noKey,
              AutopwnV2Attack.staticNested: AutopwnV2AttemptOutcome.found,
            },
            const AutopwnV2Target(1, 1): {
              AutopwnV2Attack.nested: AutopwnV2AttemptOutcome.found,
            },
          },
        );
        final phases = <AutopwnV2Phase>[];

        final result = await const AutopwnV2Runner().run(
          recovery: port,
          options: AutopwnV2Options(
            dictionaries: [
              Dictionary(keys: [dictionaryKey]),
            ],
            includeDefaults: false,
          ),
          onProgress: (progress) => phases.add(progress.phase),
        );

        expect(result.complete, isTrue);
        expect(result.verifiedKeySlots, 4);
        expect(result.blocks, hasLength(8));
        expect(result.attacks, hasLength(4));
        expect(
          result.attacks.map((record) => record.attack),
          contains(AutopwnV2Attack.staticNested),
        );
        final attackOrder = result.attacks
            .map((record) => record.attack)
            .toList();
        expect(
          attackOrder.lastIndexOf(AutopwnV2Attack.nested),
          lessThan(attackOrder.indexOf(AutopwnV2Attack.staticNested)),
        );
        expect(port.verifyCalled, isTrue);
        expect(port.dumpCalled, isTrue);
        expect(
          phases,
          containsAllInOrder([
            AutopwnV2Phase.preflight,
            AutopwnV2Phase.seeds,
            AutopwnV2Phase.classify,
            AutopwnV2Phase.nested,
            AutopwnV2Phase.staticNested,
            AutopwnV2Phase.verify,
            AutopwnV2Phase.dump,
            AutopwnV2Phase.complete,
          ]),
        );
        expect(result.toJson()['format'], 'chameleon-autopwn-v2');
      },
    );

    test(
      'stops static fallback globally after an incompatible signature',
      () async {
        final port = _FakeV2Port(
          seededTargets: {const AutopwnV2Target(0, 0)},
          outcomes: {
            const AutopwnV2Target(0, 1): {
              AutopwnV2Attack.nested: AutopwnV2AttemptOutcome.noKey,
              AutopwnV2Attack.staticNested:
                  AutopwnV2AttemptOutcome.incompatible,
            },
            const AutopwnV2Target(1, 0): {
              AutopwnV2Attack.nested: AutopwnV2AttemptOutcome.noKey,
            },
            const AutopwnV2Target(1, 1): {
              AutopwnV2Attack.nested: AutopwnV2AttemptOutcome.noKey,
            },
          },
        );

        final result = await const AutopwnV2Runner().run(
          recovery: port,
          options: const AutopwnV2Options(
            includeDefaults: false,
            createPartialDump: false,
          ),
        );

        expect(result.complete, isFalse);
        expect(
          port.attackCalls.where(
            (call) => call.$2 == AutopwnV2Attack.staticNested,
          ),
          hasLength(1),
        );
        expect(
          port.attackCalls.where((call) => call.$2 == AutopwnV2Attack.nested),
          hasLength(3),
        );
        expect(port.dumpCalled, isFalse);
      },
    );

    test(
      'uses backdoor before Darkside and skips bootstrap when it yields a key',
      () async {
        final port = _FakeV2Port(
          profile: const AutopwnV2CardProfile(
            ntLevel: NTLevel.weak,
            hasBackdoor: true,
          ),
          backdoorTarget: const AutopwnV2Target(0, 0),
          outcomes: {
            const AutopwnV2Target(0, 1): {
              AutopwnV2Attack.nested: AutopwnV2AttemptOutcome.found,
            },
            const AutopwnV2Target(1, 0): {
              AutopwnV2Attack.nested: AutopwnV2AttemptOutcome.found,
            },
            const AutopwnV2Target(1, 1): {
              AutopwnV2Attack.nested: AutopwnV2AttemptOutcome.found,
            },
          },
        );

        final result = await const AutopwnV2Runner().run(
          recovery: port,
          options: const AutopwnV2Options(
            includeDefaults: false,
            createPartialDump: false,
          ),
        );

        expect(port.backdoorCalled, isTrue);
        expect(port.darksideCalled, isFalse);
        expect(result.complete, isTrue);
      },
    );

    test('card guard prevents results from mixing two cards', () async {
      final port = _FakeV2Port();
      var checks = 0;

      await expectLater(
        const AutopwnV2Runner().run(
          recovery: port,
          options: const AutopwnV2Options(
            includeDefaults: false,
            createPartialDump: false,
          ),
          cardGuard: () async => ++checks < 2,
        ),
        throwsA(isA<AutopwnV2CardChanged>()),
      );
      expect(port.attackCalls, isEmpty);
      expect(port.dumpCalled, isFalse);
    });

    test('card guard also rejects a change after final verification', () async {
      final port = _FakeV2Port(
        seededTargets: {
          const AutopwnV2Target(0, 0),
          const AutopwnV2Target(0, 1),
          const AutopwnV2Target(1, 0),
          const AutopwnV2Target(1, 1),
        },
      );
      var checks = 0;

      await expectLater(
        const AutopwnV2Runner().run(
          recovery: port,
          options: const AutopwnV2Options(
            includeDefaults: false,
            createPartialDump: false,
          ),
          cardGuard: () async => ++checks < 4,
        ),
        throwsA(isA<AutopwnV2CardChanged>()),
      );
      expect(port.verifyCalled, isTrue);
      expect(port.dumpCalled, isFalse);
    });

    test('cooperative cancellation queues no verification or dump', () async {
      final port = _FakeV2Port(cancelOnClassify: true);
      final result = await const AutopwnV2Runner().run(
        recovery: port,
        options: const AutopwnV2Options(includeDefaults: false),
      );

      expect(result.cancelled, isTrue);
      expect(port.verifyCalled, isFalse);
      expect(port.dumpCalled, isFalse);
    });
  });

  testWidgets('Autopwn v2 page is responsive before recovery starts', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final preferences = SharedPreferencesProvider();
    await preferences.load();
    final appState = ChameleonGUIState(preferences);
    addTearDown(appState.dispose);
    tester.view.physicalSize = const Size(320, 850);
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
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(1.6)),
            child: child!,
          ),
          home: const AutopwnV2Page(),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Autopwn v2'), findsOneWidget);
    expect(find.text('Start full recovery'), findsOneWidget);
    expect(find.text('No candidate truncation'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

class _FakeV2Port implements AutopwnV2RecoveryPort {
  final AutopwnV2CardProfile profile;
  final AutopwnV2Target? resolveDictionaryTarget;
  final Uint8List? dictionaryKey;
  final AutopwnV2Target? backdoorTarget;
  final Map<AutopwnV2Target, Map<AutopwnV2Attack, AutopwnV2AttemptOutcome>>
  outcomes;
  final Set<AutopwnV2Target> _resolved;
  final bool cancelOnClassify;
  final List<(AutopwnV2Target, AutopwnV2Attack)> attackCalls = [];
  final List<AutopwnV2Block> _blocks = [];
  bool backdoorCalled = false;
  bool darksideCalled = false;
  bool verifyCalled = false;
  bool dumpCalled = false;
  bool _cancelled = false;

  _FakeV2Port({
    this.profile = const AutopwnV2CardProfile(
      ntLevel: NTLevel.weak,
      hasBackdoor: false,
    ),
    this.resolveDictionaryTarget,
    this.dictionaryKey,
    this.backdoorTarget,
    this.outcomes = const {},
    Set<AutopwnV2Target> seededTargets = const {},
    this.cancelOnClassify = false,
  }) : _resolved = {...seededTargets};

  @override
  int get sectorCount => 2;

  @override
  bool get isCancelled => _cancelled;

  @override
  String get error => '';

  @override
  List<AutopwnV2Block> get dumpedBlocks => List.unmodifiable(_blocks);

  @override
  void cancel() => _cancelled = true;

  @override
  Future<void> prepare({required bool exhaustiveEvidence}) async {}

  @override
  Future<int> reverifyKnownKeys() async => verifiedSlots;

  @override
  Future<AutopwnV2CardProfile> classify() async {
    if (cancelOnClassify) _cancelled = true;
    return profile;
  }

  @override
  List<AutopwnV2Target> unresolvedTargets() => [
    for (var sector = 0; sector < sectorCount; sector++)
      for (var keyType = 0; keyType < 2; keyType++)
        if (!_resolved.contains(AutopwnV2Target(sector, keyType)))
          AutopwnV2Target(sector, keyType),
  ];

  @override
  int get verifiedSlots => _resolved.length;

  @override
  List<AutopwnV2VerifiedKey> get verifiedKeys => [
    for (final target in _resolved)
      AutopwnV2VerifiedKey(
        sector: target.sector,
        keyType: target.keyType,
        key: dictionaryKey ?? Uint8List.fromList([1, 2, 3, 4, 5, 6]),
      ),
  ];

  @override
  Future<bool> checkTarget(
    AutopwnV2Target target,
    List<Uint8List> candidates,
  ) async {
    if (target == resolveDictionaryTarget &&
        dictionaryKey != null &&
        candidates.any(
          (key) => bytesToHex(key) == bytesToHex(dictionaryKey!),
        )) {
      _resolved.add(target);
      return true;
    }
    return false;
  }

  @override
  Future<bool> recoverBackdoor() async {
    backdoorCalled = true;
    if (backdoorTarget != null) _resolved.add(backdoorTarget!);
    return backdoorTarget != null;
  }

  @override
  Future<bool> bootstrapDarkside() async {
    darksideCalled = true;
    _resolved.add(const AutopwnV2Target(0, 1));
    return true;
  }

  @override
  Future<AutopwnV2AttemptOutcome> recoverTarget(
    AutopwnV2Target target,
    AutopwnV2Attack attack,
  ) async {
    attackCalls.add((target, attack));
    final outcome = outcomes[target]?[attack] ?? AutopwnV2AttemptOutcome.noKey;
    if (outcome == AutopwnV2AttemptOutcome.found) _resolved.add(target);
    return outcome;
  }

  @override
  Future<int> verifyRecoveredKeys() async {
    verifyCalled = true;
    return verifiedSlots;
  }

  @override
  Future<List<AutopwnV2Block>> dump(
    void Function(int completed, int total) onProgress, {
    Future<bool> Function()? cardGuard,
  }) async {
    dumpCalled = true;
    _blocks.clear();
    for (var block = 0; block < 8; block++) {
      _blocks.add(
        AutopwnV2Block(
          sector: block ~/ 4,
          block: block,
          data: Uint8List(16),
          syntheticKeys: block == 3 || block == 7,
        ),
      );
      onProgress(block + 1, 8);
    }
    return List.unmodifiable(_blocks);
  }
}

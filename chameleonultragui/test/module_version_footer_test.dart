import 'package:chameleonultragui/gui/component/module_version_footer.dart';
import 'package:chameleonultragui/gui/component/module_version_navigation.dart';
import 'package:chameleonultragui/helpers/module_versions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('module registry keeps complete SemVer and ISO date metadata', () {
    expect(moduleVersions.keys.toSet(), ModuleId.values.toSet());

    for (final module in moduleVersions.values) {
      expect(module.version, matches(RegExp(r'^\d+\.\d+\.\d+$')));
      expect(module.updatedAt, matches(RegExp(r'^\d{4}-\d{2}-\d{2}$')));
      expect(DateTime.tryParse(module.updatedAt), isNotNull);
    }
  });

  testWidgets('footer renders the selected module release', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ModuleVersionFooter(moduleId: ModuleId.readerKeys),
        ),
      ),
    );

    expect(find.text('Reader Keys'), findsOneWidget);
    expect(find.text('Version 1.0.0 / Updated 2026-07-30'), findsOneWidget);
  });

  testWidgets('navigation observer restores the root module after pop', (
    tester,
  ) async {
    final activeModule = ValueNotifier(ModuleId.device);
    addTearDown(activeModule.dispose);
    final observer = ModuleNavigationObserver(
      activeModule: activeModule,
      rootModule: ModuleId.device,
    );

    await tester.pumpWidget(
      MaterialApp(
        navigatorObservers: [observer],
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => Navigator.push(
                context,
                ModulePageRoute<void>(
                  moduleId: ModuleId.tools,
                  builder: (_) => const Scaffold(body: Text('Tools page')),
                ),
              ),
              child: const Text('Open tools'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open tools'));
    await tester.pumpAndSettle();
    expect(activeModule.value, ModuleId.tools);

    Navigator.of(tester.element(find.text('Tools page'))).pop();
    await tester.pumpAndSettle();
    expect(activeModule.value, ModuleId.device);
  });

  testWidgets('navigation overlays preserve the active module', (tester) async {
    final activeModule = ValueNotifier(ModuleId.device);
    addTearDown(activeModule.dispose);
    final observer = ModuleNavigationObserver(
      activeModule: activeModule,
      rootModule: ModuleId.device,
    );

    await tester.pumpWidget(
      MaterialApp(
        navigatorObservers: [observer],
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                await Navigator.push<void>(
                  context,
                  ModulePageRoute<void>(
                    moduleId: ModuleId.pm3Catalog,
                    builder: (routeContext) => Scaffold(
                      body: TextButton(
                        onPressed: () => showDialog<void>(
                          context: routeContext,
                          builder: (_) =>
                              const AlertDialog(title: Text('Overlay')),
                        ),
                        child: const Text('Open overlay'),
                      ),
                    ),
                  ),
                );
              },
              child: const Text('Open PM3'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open PM3'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open overlay'));
    await tester.pumpAndSettle();

    expect(find.text('Overlay'), findsOneWidget);
    expect(activeModule.value, ModuleId.pm3Catalog);
  });
}

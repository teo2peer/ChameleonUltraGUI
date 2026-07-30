import 'package:chameleonultragui/helpers/pm3_command_inventory.dart';
import 'package:chameleonultragui/helpers/pm3_tool_catalog.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('indexes every unique non-help command from the audited PM3 dump', () {
    final counts = {
      for (final section in pm3CatalogSections)
        section.id: section.tools.length,
    };

    expect(counts['data'], 47);
    expect(counts['hf'], 482);
    expect(counts['lf'], 213);
    expect(counts['hardware'], 22);
    expect(counts['memory'], 18);
    expect(counts['client'], 105);
    expect(pm3CatalogEntries.length, pm3CommandCount);
    expect(pm3CommandCount, 893);
    expect(pm3CatalogCount(Pm3ToolSupport.mapped), 45);
    expect(pm3CatalogCount(Pm3ToolSupport.portable), 230);
    expect(pm3CatalogCount(Pm3ToolSupport.unsupported), 618);
    expect(pm3UpstreamCommit, '8b65feaba36ecc6d58d8aeef96cdc7c5a04381bc');
    expect(
      pm3CatalogEntries.map((entry) => entry.command).toSet(),
      hasLength(pm3CatalogEntries.length),
    );
    expect(pm3CatalogEntries.any((entry) => entry.command == 'auto'), isTrue);
    expect(
      pm3CatalogEntries.any((entry) => entry.command == 'lf config'),
      isTrue,
    );
    expect(
      pm3CatalogEntries.any(
        (entry) => entry.command == 'help' || entry.command.endsWith(' help'),
      ),
      isFalse,
    );
  });

  test('keeps PM3-only hardware disabled and mapped tools actionable', () {
    Pm3Tool byCommand(String command) =>
        pm3CatalogEntries.singleWhere((entry) => entry.command == command);

    expect(byCommand('hw fpgaoff').support, Pm3ToolSupport.unsupported);
    expect(byCommand('mem spiffs wipe').target, isNull);
    expect(byCommand('hf mf hardnested').target, Pm3ToolTarget.hardnested);
    expect(byCommand('hf mf restore').target, Pm3ToolTarget.writeCard);
    expect(byCommand('hf mf sim').target, Pm3ToolTarget.slotManager);
    expect(byCommand('hf mf wrbl').target, isNull);
    expect(byCommand('lf t55xx chk').target, isNull);
    expect(byCommand('lf idteck reader').target, isNull);
    expect(byCommand('trace load').target, isNull);
    expect(
      pm3CatalogEntries
          .where((entry) => entry.support == Pm3ToolSupport.mapped)
          .every((entry) => entry.target != null),
      isTrue,
    );
  });

  test('filters by command text and support state', () {
    final sections = filterPm3Catalog('spiffs', Pm3ToolSupport.unsupported);

    expect(sections, hasLength(1));
    expect(sections.single.id, 'memory');
    expect(sections.single.tools, hasLength(13));
  });
}

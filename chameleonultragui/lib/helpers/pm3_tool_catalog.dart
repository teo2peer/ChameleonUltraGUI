import 'package:chameleonultragui/helpers/pm3_command_inventory.dart';

enum Pm3ToolSupport { mapped, portable, unsupported }

enum Pm3ToolTarget {
  device,
  readCard,
  writeCard,
  slotManager,
  hfSniffing,
  lfSniffing,
  apduTerminal,
  emvReader,
  desfireReader,
  autopwn,
  darkside,
  nested,
  staticNested,
  hardnested,
  valueBlock,
  wiegand,
}

class Pm3Tool {
  final String id;
  final String command;
  final String summary;
  final Pm3ToolSupport support;
  final String reason;
  final Pm3ToolTarget? target;
  final bool requiresDevice;

  const Pm3Tool({
    required this.id,
    required this.command,
    required this.summary,
    required this.support,
    required this.reason,
    this.target,
    this.requiresDevice = false,
  });
}

class Pm3ToolSection {
  final String id;
  final String title;
  final String description;
  final List<Pm3Tool> tools;

  const Pm3ToolSection({
    required this.id,
    required this.title,
    required this.description,
    required this.tools,
  });
}

class _SectionDefinition {
  final String id;
  final String title;
  final String description;
  final bool Function(String command) matches;

  const _SectionDefinition({
    required this.id,
    required this.title,
    required this.description,
    required this.matches,
  });
}

class _MappedTarget {
  final Pm3ToolTarget target;
  final bool requiresDevice;

  const _MappedTarget(this.target, {this.requiresDevice = true});
}

const _mappedCommandTargets = <String, _MappedTarget>{
  'auto': _MappedTarget(Pm3ToolTarget.readCard),
  'emv reader': _MappedTarget(Pm3ToolTarget.emvReader),
  'emv scan': _MappedTarget(Pm3ToolTarget.emvReader),
  'emv search': _MappedTarget(Pm3ToolTarget.emvReader),
  'hf 14a apdu': _MappedTarget(Pm3ToolTarget.apduTerminal),
  'hf 14a info': _MappedTarget(Pm3ToolTarget.readCard),
  'hf 14a reader': _MappedTarget(Pm3ToolTarget.readCard),
  'hf 14a sniff': _MappedTarget(Pm3ToolTarget.hfSniffing),
  'hf mf autopwn': _MappedTarget(Pm3ToolTarget.autopwn),
  'hf mf darkside': _MappedTarget(Pm3ToolTarget.darkside),
  'hf mf dump': _MappedTarget(Pm3ToolTarget.readCard),
  'hf mf hardnested': _MappedTarget(Pm3ToolTarget.hardnested),
  'hf mf info': _MappedTarget(Pm3ToolTarget.readCard),
  'hf mf nested': _MappedTarget(Pm3ToolTarget.nested),
  'hf mf rdbl': _MappedTarget(Pm3ToolTarget.readCard),
  'hf mf rdsc': _MappedTarget(Pm3ToolTarget.readCard),
  'hf mf restore': _MappedTarget(Pm3ToolTarget.writeCard),
  'hf mf sim': _MappedTarget(Pm3ToolTarget.slotManager),
  'hf mf staticnested': _MappedTarget(Pm3ToolTarget.staticNested),
  'hf mf value': _MappedTarget(Pm3ToolTarget.valueBlock),
  'hf mfdes getversion': _MappedTarget(Pm3ToolTarget.desfireReader),
  'hf mfdes info': _MappedTarget(Pm3ToolTarget.desfireReader),
  'hf mfu dump': _MappedTarget(Pm3ToolTarget.readCard),
  'hf mfu info': _MappedTarget(Pm3ToolTarget.readCard),
  'hf mfu rdbl': _MappedTarget(Pm3ToolTarget.readCard),
  'hf mfu restore': _MappedTarget(Pm3ToolTarget.writeCard),
  'hf mfu sim': _MappedTarget(Pm3ToolTarget.slotManager),
  'hf search': _MappedTarget(Pm3ToolTarget.readCard),
  'hf sniff': _MappedTarget(Pm3ToolTarget.hfSniffing),
  'hw connect': _MappedTarget(Pm3ToolTarget.device, requiresDevice: false),
  'lf read': _MappedTarget(Pm3ToolTarget.readCard),
  'lf search': _MappedTarget(Pm3ToolTarget.readCard),
  'lf sniff': _MappedTarget(Pm3ToolTarget.lfSniffing),
  'wiegand decode': _MappedTarget(Pm3ToolTarget.wiegand, requiresDevice: false),
  'wiegand list': _MappedTarget(Pm3ToolTarget.wiegand, requiresDevice: false),
};

const _mappedLfFamilies = [
  'lf em 410x',
  'lf hid',
  'lf io',
  'lf pac',
  'lf viking',
];

final _sectionDefinitions = <_SectionDefinition>[
  _SectionDefinition(
    id: 'data',
    title: 'Data and signal processing',
    description:
        'GraphBuffer, demodulation, conversion, crypto, and debug commands.',
    matches: (command) => command.startsWith('data '),
  ),
  _SectionDefinition(
    id: 'hf',
    title: 'High frequency',
    description: 'Every leaf command in the current PM3 HF protocol tree.',
    matches: (command) => command.startsWith('hf '),
  ),
  _SectionDefinition(
    id: 'lf',
    title: 'Low frequency',
    description: 'Every leaf command in the current PM3 LF protocol tree.',
    matches: (command) => command.startsWith('lf '),
  ),
  _SectionDefinition(
    id: 'hardware',
    title: 'Hardware',
    description:
        'Client connection and PM3-specific MCU, FPGA, ADC, LCD, and antenna operations.',
    matches: (command) => command.startsWith('hw '),
  ),
  _SectionDefinition(
    id: 'memory',
    title: 'Flash and SPIFFS',
    description:
        'External flash and SPIFFS commands retained for completeness.',
    matches: (command) => command.startsWith('mem '),
  ),
  _SectionDefinition(
    id: 'trace',
    title: 'Trace',
    description: 'Load, save, list, and extract captured protocol data.',
    matches: (command) => command.startsWith('trace '),
  ),
  _SectionDefinition(
    id: 'scripting',
    title: 'Scripting',
    description: 'PM3 Lua, Python, and command-script discovery and execution.',
    matches: (command) => command.startsWith('script '),
  ),
  _SectionDefinition(
    id: 'client',
    title: 'Client and protocol utilities',
    description:
        'Top-level shell, preferences, analysis, smart-card, NFC, and host integration commands.',
    matches: (_) => true,
  ),
];

const _portableReason =
    'This command runs offline in the PM3 client, but no bounded Chameleon host port is wired yet.';
const _unsupportedReason =
    'This command requires PM3 firmware, radio, FPGA, memory, ADC, or peripheral behavior that Chameleon does not expose.';

_MappedTarget? _targetForCommand(String command) {
  final exactTarget = _mappedCommandTargets[command];
  if (exactTarget != null) return exactTarget;

  if ((command.endsWith(' reader') || command.endsWith(' sim')) &&
      _mappedLfFamilies.any((family) => command.startsWith('$family '))) {
    return _MappedTarget(
      command.endsWith(' reader')
          ? Pm3ToolTarget.readCard
          : Pm3ToolTarget.slotManager,
    );
  }

  return null;
}

Pm3Tool _createTool(String section, Pm3CommandInventoryEntry entry) {
  final target = _targetForCommand(entry.command);
  final support = target != null
      ? Pm3ToolSupport.mapped
      : entry.offline
      ? Pm3ToolSupport.portable
      : Pm3ToolSupport.unsupported;
  return Pm3Tool(
    id: '$section:${entry.command}'.replaceAll(' ', '-'),
    command: entry.command,
    summary: entry.description,
    support: support,
    reason: target != null
        ? 'Opens the existing Chameleon equivalent without replacing it.'
        : entry.offline
        ? _portableReason
        : _unsupportedReason,
    target: target?.target,
    requiresDevice: target?.requiresDevice ?? false,
  );
}

final pm3CatalogSections = _sectionDefinitions
    .map((definition) {
      final tools = pm3CommandInventory
          .where((entry) {
            final owner = _sectionDefinitions.firstWhere(
              (candidate) => candidate.matches(entry.command),
            );
            return owner.id == definition.id;
          })
          .map((entry) => _createTool(definition.id, entry))
          .toList(growable: false);
      return Pm3ToolSection(
        id: definition.id,
        title: definition.title,
        description: definition.description,
        tools: tools,
      );
    })
    .toList(growable: false);

final pm3CatalogEntries = pm3CatalogSections
    .expand((section) => section.tools)
    .toList(growable: false);

int pm3CatalogCount(Pm3ToolSupport support) =>
    pm3CatalogEntries.where((entry) => entry.support == support).length;

List<Pm3ToolSection> filterPm3Catalog(String query, Pm3ToolSupport? support) {
  final normalized = query.trim().toLowerCase();
  return pm3CatalogSections
      .map(
        (section) => Pm3ToolSection(
          id: section.id,
          title: section.title,
          description: section.description,
          tools: section.tools
              .where((entry) {
                final matchesSupport =
                    support == null || entry.support == support;
                final searchable =
                    '${entry.command} ${entry.summary} ${entry.reason}'
                        .toLowerCase();
                return matchesSupport &&
                    (normalized.isEmpty || searchable.contains(normalized));
              })
              .toList(growable: false),
        ),
      )
      .where((section) => section.tools.isNotEmpty)
      .toList(growable: false);
}

import 'package:chameleonultragui/generated/i18n/app_localizations.dart';
import 'package:chameleonultragui/gui/component/module_version_navigation.dart';
import 'package:chameleonultragui/gui/menu/hacking/apdu_terminal.dart';
import 'package:chameleonultragui/gui/menu/hacking/autopwn.dart';
import 'package:chameleonultragui/gui/menu/hacking/darkside.dart';
import 'package:chameleonultragui/gui/menu/hacking/desfire_reader.dart';
import 'package:chameleonultragui/gui/menu/hacking/emv_reader.dart';
import 'package:chameleonultragui/gui/menu/hacking/emv_transaction.dart';
import 'package:chameleonultragui/gui/menu/hacking/nested.dart';
import 'package:chameleonultragui/gui/menu/hacking/value_block.dart';
import 'package:chameleonultragui/gui/menu/hacking/wiegand.dart';
import 'package:chameleonultragui/gui/menu/tools/hf_sniffing.dart';
import 'package:chameleonultragui/gui/menu/tools/lf_sniffing.dart';
import 'package:chameleonultragui/gui/menu/tools/pm3_hf14a_tools.dart';
import 'package:chameleonultragui/gui/menu/tools/pm3_lf_tools.dart';
import 'package:chameleonultragui/gui/menu/tools/pm3_offline_tools.dart';
import 'package:chameleonultragui/gui/page/read_card.dart';
import 'package:chameleonultragui/helpers/module_versions.dart';
import 'package:chameleonultragui/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:provider/provider.dart';

const int pm3ToolCategoryCount = 5;
const int pm3OperationalToolCount = 29;

class Pm3ToolsPage extends StatelessWidget {
  const Pm3ToolsPage({super.key});

  List<_Pm3Category> _categories() => [
    _Pm3Category(
      title: 'ISO14443-A',
      description: 'Reader, raw frames, ISO-DEP, and live card capture.',
      icon: Icons.nfc,
      tools: [
        _Pm3Tool(
          'hf 14a info',
          'Inspect UID, ATQA, SAK, ATS, cascade handling, and RATS.',
          Icons.contactless,
          (context) => _push(context, const Pm3Hf14aInspectorPage()),
        ),
        _Pm3Tool(
          'hf 14a raw',
          'Transmit a bounded ISO14443-A frame with PM3-compatible flags.',
          Icons.terminal,
          (context) => _push(context, const Pm3Hf14aRawPage()),
        ),
        _Pm3Tool(
          'hf 14a apdu',
          'Send an ISO14443-4 APDU and inspect the response.',
          Icons.send,
          (context) =>
              _push(context, const ApduTerminalPage(), ModuleId.apduTerminal),
        ),
        _Pm3Tool(
          'hf 14a sniff',
          'Capture the reader/card exchange while the device emulates a card.',
          Icons.radar,
          (context) =>
              _dialog(context, const HfSniffingMenu(), ModuleId.hfSniffing),
        ),
      ],
    ),
    _Pm3Category(
      title: 'MIFARE Classic',
      description: 'Recover, read, write, trace, and emulate Classic cards.',
      icon: Icons.key,
      tools: [
        _Pm3Tool(
          'hf mf info / dump',
          'Inspect a MIFARE Classic card, recover keys, and dump readable blocks.',
          Icons.credit_card,
          (context) => _push(context, const ReadCardPage(), ModuleId.readCard),
        ),
        _Pm3Tool(
          'hf mf autopwn',
          'Run dictionary, Darkside, Nested, Hardnested, static, and backdoor recovery.',
          Icons.bolt,
          (context) => _push(context, const AutopwnPage(), ModuleId.autopwn),
        ),
        _Pm3Tool(
          'hf mf darkside',
          'Acquire and solve a first key from a weak-PRNG card.',
          Icons.dark_mode,
          (context) => _push(context, const DarksidePage(), ModuleId.darkside),
        ),
        _Pm3Tool(
          'hf mf nested',
          'Recover a target key from a known key on weak-PRNG cards.',
          Icons.layers,
          (context) => _push(context, const NestedPage(), ModuleId.nested),
        ),
        _Pm3Tool(
          'hf mf staticnested',
          'Run the static-nonce variant against compatible Classic cards.',
          Icons.lock_clock,
          (context) => _push(
            context,
            const NestedPage(variant: NestedVariant.staticNonce),
            ModuleId.staticNested,
          ),
        ),
        _Pm3Tool(
          'hf mf hardnested',
          'Acquire nonces and run hardened nested recovery.',
          Icons.memory,
          (context) => _push(
            context,
            const NestedPage(variant: NestedVariant.hard),
            ModuleId.hardnested,
          ),
        ),
        _Pm3Tool(
          'hf mf value',
          'Increment, decrement, restore, and transfer a value block.',
          Icons.exposure,
          (context) =>
              _dialog(context, const ValueBlockMenu(), ModuleId.valueBlock),
        ),
      ],
    ),
    _Pm3Category(
      title: 'Low frequency',
      description:
          'LF discovery, signal capture, ioProx, and T55xx operations.',
      icon: Icons.sensors,
      tools: [
        _Pm3Tool(
          'lf search',
          'Run each supported LF reader and report every recognized protocol.',
          Icons.radar,
          (context) => _push(context, const Pm3LfDiscoveryPage()),
        ),
        _Pm3Tool(
          'lf read ADC',
          'Capture the direct LF ADC window for signal analysis.',
          Icons.graphic_eq,
          (context) => _push(context, const Pm3LfAdcPage()),
        ),
        _Pm3Tool(
          'lf sniff',
          'Capture an LF waveform, inspect it, and decode Manchester candidates.',
          Icons.timeline,
          (context) =>
              _dialog(context, const LfSniffingMenu(), ModuleId.lfSniffing),
        ),
        _Pm3Tool(
          'lf ioProx codec',
          'Decode raw ioProx bytes or compose the device card structure.',
          Icons.account_tree,
          (context) => _push(context, const Pm3IoProxCodecPage()),
        ),
        _Pm3Tool(
          'lf t55xx write',
          'Write an explicit 32-bit T55xx block, with optional password and page.',
          Icons.edit_note,
          (context) => _push(context, const Pm3T55xxBlockWriterPage()),
        ),
        _Pm3Tool(
          'lf jablotron clone',
          'Read a Jablotron UID and write it to a password-protected T55xx tag.',
          Icons.copy,
          (context) => _push(context, const Pm3JablotronClonePage()),
        ),
      ],
    ),
    _Pm3Category(
      title: 'Smart cards',
      description:
          'Read ISO-DEP applications through dedicated EMV and DESFire workflows.',
      icon: Icons.sim_card,
      tools: [
        _Pm3Tool(
          'emv reader',
          'Read contactless EMV application data and decoded APDUs.',
          Icons.contactless,
          (context) =>
              _push(context, const EmvReaderPage(), ModuleId.emvReader),
        ),
        _Pm3Tool(
          'emv transaction',
          'Perform an offline EMV GENERATE AC simulation without bank authorisation.',
          Icons.point_of_sale,
          (context) => _push(
            context,
            const EmvTransactionPage(),
            ModuleId.emvTransaction,
          ),
        ),
        _Pm3Tool(
          'hf mfdes info',
          'Enumerate DESFire version, applications, and accessible file IDs.',
          Icons.storage,
          (context) =>
              _push(context, const DesfireReaderPage(), ModuleId.desfireReader),
        ),
        _Pm3Tool(
          'hf 14a apdu terminal',
          'Issue an arbitrary ISO-DEP APDU to a card you control.',
          Icons.code,
          (context) =>
              _push(context, const ApduTerminalPage(), ModuleId.apduTerminal),
        ),
      ],
    ),
    _Pm3Category(
      title: 'Offline analysis',
      description: 'Host-side decoders that do not need a connected reader.',
      icon: Icons.analytics,
      tools: [
        _Pm3Tool(
          'data num',
          'Convert arbitrary-precision decimal, hexadecimal, and binary values.',
          Icons.calculate,
          (context) => _push(
            context,
            const Pm3OfflineToolPage(tool: Pm3OfflineTool.number),
          ),
          deviceRequired: false,
        ),
        _Pm3Tool(
          'data xor',
          'XOR byte strings with an explicit or automatically selected mask.',
          Icons.compare_arrows,
          (context) => _push(
            context,
            const Pm3OfflineToolPage(tool: Pm3OfflineTool.xor),
          ),
          deviceRequired: false,
        ),
        _Pm3Tool(
          'analyse lrc',
          'Calculate the PM3 rolling-XOR LRC byte.',
          Icons.functions,
          (context) => _push(
            context,
            const Pm3OfflineToolPage(tool: Pm3OfflineTool.lrc),
          ),
          deviceRequired: false,
        ),
        _Pm3Tool(
          'analyse nuid',
          'Generate a four-byte NUID from a seven-byte UID.',
          Icons.fingerprint,
          (context) => _push(
            context,
            const Pm3OfflineToolPage(tool: Pm3OfflineTool.nuid),
          ),
          deviceRequired: false,
        ),
        _Pm3Tool(
          'analyse chksum',
          'Calculate PM3 byte, nibble, crumb, complement, XOR, and BSD checksums.',
          Icons.rule,
          (context) => _push(
            context,
            const Pm3OfflineToolPage(tool: Pm3OfflineTool.checksum),
          ),
          deviceRequired: false,
        ),
        _Pm3Tool(
          'analyse freq',
          'Calculate RFID wavelengths, near-field ranges, and LC resonance.',
          Icons.waves,
          (context) => _push(context, const Pm3FrequencyPage()),
          deviceRequired: false,
        ),
        _Pm3Tool(
          'analyse units',
          'Convert ISO14443-A ETU, microseconds, and 3.39 MHz SSP cycles.',
          Icons.straighten,
          (context) => _push(context, const Pm3UnitsPage()),
          deviceRequired: false,
        ),
        _Pm3Tool(
          'wiegand decode',
          'Decode an access-control value into facility code and card number.',
          Icons.numbers,
          (context) => _dialog(context, const WiegandMenu(), ModuleId.wiegand),
          deviceRequired: false,
        ),
      ],
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final app = context.watch<ChameleonGUIState>();
    final localizations = AppLocalizations.of(context)!;
    final acknowledged = app.sharedPreferencesProvider.getEthicalHackingAck();
    final categories = _categories();

    return Scaffold(
      appBar: AppBar(title: Text(localizations.pm3_tools)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Operational PM3-compatible workflows for Chameleon Ultra. Each entry invokes a device command or a host implementation; this is not a command catalogue.',
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          const SizedBox(height: 12),
          Chip(
            label: Text(
              '$pm3OperationalToolCount operational tools in $pm3ToolCategoryCount categories',
            ),
          ),
          if (!acknowledged) ...[
            const SizedBox(height: 12),
            Card(
              color: Theme.of(context).colorScheme.errorContainer,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Authorisation required',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Use these RF operations only on hardware and systems you own or are explicitly authorised to test.',
                    ),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: () => app.sharedPreferencesProvider
                          .setEthicalHackingAck(true),
                      child: Text(localizations.accept),
                    ),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 16),
          AlignedGridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: MediaQuery.of(context).size.width >= 700 ? 2 : 1,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            itemCount: categories.length,
            itemBuilder: (context, index) {
              final category = categories[index];
              return Card(
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  key: ValueKey('pm3-category-${category.title}'),
                  onTap: acknowledged
                      ? () =>
                            _push(context, _Pm3CategoryPage(category: category))
                      : null,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          category.icon,
                          size: 32,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                category.title,
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              const SizedBox(height: 4),
                              Text(category.description),
                              const SizedBox(height: 10),
                              Chip(
                                label: Text('${category.tools.length} tools'),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _Pm3CategoryPage extends StatelessWidget {
  final _Pm3Category category;

  const _Pm3CategoryPage({required this.category});

  @override
  Widget build(BuildContext context) {
    final connected =
        context.watch<ChameleonGUIState>().connector?.connected ?? false;
    return Scaffold(
      appBar: AppBar(title: Text('PM3 Tools / ${category.title}')),
      body: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: category.tools.length + 1,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (context, index) {
          if (index == 0) {
            return Text(
              category.description,
              style: Theme.of(context).textTheme.bodyLarge,
            );
          }
          final tool = category.tools[index - 1];
          final unavailable = tool.deviceRequired && !connected;
          return Card(
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              key: ValueKey('pm3-tool-${tool.title}'),
              onTap: unavailable ? null : () => tool.open(context),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Opacity(
                  opacity: unavailable ? 0.55 : 1,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        tool.icon,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              tool.title,
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(fontFamily: 'RobotoMono'),
                            ),
                            const SizedBox(height: 5),
                            Text(tool.description),
                            if (unavailable) ...[
                              const SizedBox(height: 8),
                              const Text('Connect a device to use this tool.'),
                            ],
                          ],
                        ),
                      ),
                      const Icon(Icons.chevron_right),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _Pm3Category {
  final String title;
  final String description;
  final IconData icon;
  final List<_Pm3Tool> tools;

  const _Pm3Category({
    required this.title,
    required this.description,
    required this.icon,
    required this.tools,
  });
}

class _Pm3Tool {
  final String title;
  final String description;
  final IconData icon;
  final bool deviceRequired;
  final void Function(BuildContext) open;

  const _Pm3Tool(
    this.title,
    this.description,
    this.icon,
    this.open, {
    this.deviceRequired = true,
  });
}

void _push(
  BuildContext context,
  Widget page, [
  ModuleId moduleId = ModuleId.pm3Catalog,
]) {
  Navigator.of(
    context,
  ).push(ModulePageRoute(moduleId: moduleId, builder: (_) => page));
}

void _dialog(
  BuildContext context,
  Widget dialog, [
  ModuleId moduleId = ModuleId.pm3Catalog,
]) {
  showDialog<void>(
    context: context,
    routeSettings: RouteSettings(arguments: moduleId),
    builder: (_) => dialog,
  );
}

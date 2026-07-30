import 'package:chameleonultragui/generated/i18n/app_localizations.dart';
import 'package:chameleonultragui/gui/component/module_version_navigation.dart';
import 'package:chameleonultragui/gui/menu/hacking/apdu_terminal.dart';
import 'package:chameleonultragui/gui/menu/hacking/autopwn.dart';
import 'package:chameleonultragui/gui/menu/hacking/darkside.dart';
import 'package:chameleonultragui/gui/menu/hacking/desfire_reader.dart';
import 'package:chameleonultragui/gui/menu/hacking/emv_reader.dart';
import 'package:chameleonultragui/gui/menu/hacking/nested.dart';
import 'package:chameleonultragui/gui/menu/hacking/value_block.dart';
import 'package:chameleonultragui/gui/menu/hacking/wiegand.dart';
import 'package:chameleonultragui/gui/menu/tools/hf_sniffing.dart';
import 'package:chameleonultragui/gui/menu/tools/lf_sniffing.dart';
import 'package:chameleonultragui/gui/page/connect.dart';
import 'package:chameleonultragui/gui/page/read_card.dart';
import 'package:chameleonultragui/gui/page/slot_manager.dart';
import 'package:chameleonultragui/gui/page/write_card.dart';
import 'package:chameleonultragui/helpers/pm3_tool_catalog.dart';
import 'package:chameleonultragui/helpers/module_versions.dart';
import 'package:chameleonultragui/main.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class Pm3ToolsPage extends StatefulWidget {
  const Pm3ToolsPage({super.key});

  @override
  State<Pm3ToolsPage> createState() => _Pm3ToolsPageState();
}

class _Pm3ToolsPageState extends State<Pm3ToolsPage> {
  final _searchController = TextEditingController();
  Pm3ToolSupport? _supportFilter;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<ChameleonGUIState>();
    final localizations = AppLocalizations.of(context)!;
    final acknowledged = appState.sharedPreferencesProvider
        .getEthicalHackingAck();
    final connected = appState.connector?.connected ?? false;
    final sections = filterPm3Catalog(_searchController.text, _supportFilter);
    final rows = <Object>[
      for (final section in sections) ...[section, ...section.tools],
    ];

    return Scaffold(
      appBar: AppBar(title: Text(localizations.pm3_tools)),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final horizontalPadding = constraints.maxWidth >= 700 ? 24.0 : 12.0;
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1000),
              child: ListView.builder(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: EdgeInsets.fromLTRB(
                  horizontalPadding,
                  16,
                  horizontalPadding,
                  32,
                ),
                itemCount: rows.isEmpty ? 2 : rows.length + 1,
                itemBuilder: (context, index) {
                  if (index == 0) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            localizations.pm3_tools_description,
                            style: Theme.of(context).textTheme.bodyLarge,
                          ),
                          const SizedBox(height: 12),
                          if (!acknowledged)
                            Card(
                              color: Theme.of(
                                context,
                              ).colorScheme.errorContainer,
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      localizations
                                          .pm3_tools_authorization_required,
                                      style: Theme.of(
                                        context,
                                      ).textTheme.titleMedium,
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      localizations
                                          .pm3_tools_authorization_description,
                                    ),
                                    const SizedBox(height: 12),
                                    FilledButton(
                                      onPressed: () {
                                        appState.sharedPreferencesProvider
                                            .setEthicalHackingAck(true);
                                        setState(() {});
                                      },
                                      child: Text(localizations.accept),
                                    ),
                                  ],
                                ),
                              ),
                            )
                          else
                            Align(
                              alignment: Alignment.centerLeft,
                              child: Chip(
                                avatar: const Icon(
                                  Icons.verified_user,
                                  size: 18,
                                ),
                                label: Text(localizations.pm3_tools_authorized),
                              ),
                            ),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              Chip(
                                label: Text(
                                  localizations.pm3_tools_indexed(
                                    pm3CatalogEntries.length,
                                  ),
                                ),
                              ),
                              _SupportChip(
                                label: localizations.pm3_tools_mapped,
                                support: Pm3ToolSupport.mapped,
                                count: pm3CatalogCount(Pm3ToolSupport.mapped),
                              ),
                              _SupportChip(
                                label: localizations.pm3_tools_portable,
                                support: Pm3ToolSupport.portable,
                                count: pm3CatalogCount(Pm3ToolSupport.portable),
                              ),
                              _SupportChip(
                                label: localizations.pm3_tools_unsupported,
                                support: Pm3ToolSupport.unsupported,
                                count: pm3CatalogCount(
                                  Pm3ToolSupport.unsupported,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _searchController,
                            decoration: InputDecoration(
                              border: const OutlineInputBorder(),
                              hintText: localizations.pm3_tools_search,
                              prefixIcon: const Icon(Icons.search),
                              suffixIcon: _searchController.text.isEmpty
                                  ? null
                                  : IconButton(
                                      tooltip: localizations.clear,
                                      onPressed: () {
                                        _searchController.clear();
                                        setState(() {});
                                      },
                                      icon: const Icon(Icons.clear),
                                    ),
                            ),
                            onChanged: (_) => setState(() {}),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              _filterChip(localizations.pm3_tools_all, null),
                              _filterChip(
                                localizations.pm3_tools_mapped,
                                Pm3ToolSupport.mapped,
                              ),
                              _filterChip(
                                localizations.pm3_tools_portable,
                                Pm3ToolSupport.portable,
                              ),
                              _filterChip(
                                localizations.pm3_tools_unsupported,
                                Pm3ToolSupport.unsupported,
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  }

                  if (rows.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 32),
                      child: Center(
                        child: Text(localizations.pm3_tools_no_results),
                      ),
                    );
                  }

                  final row = rows[index - 1];
                  if (row is Pm3ToolSection) {
                    return _SectionHeader(section: row);
                  }
                  final entry = row as Pm3Tool;
                  final deviceMissing = entry.requiresDevice && !connected;
                  final enabled =
                      entry.support == Pm3ToolSupport.mapped &&
                      acknowledged &&
                      !deviceMissing;
                  return _ToolCard(
                    entry: entry,
                    deviceMissing: deviceMissing,
                    enabled: enabled,
                    onTap: enabled ? () => _open(entry.target!) : null,
                  );
                },
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _filterChip(String label, Pm3ToolSupport? support) {
    return FilterChip(
      label: Text(label),
      selected: _supportFilter == support,
      onSelected: (_) => setState(() => _supportFilter = support),
    );
  }

  void _open(Pm3ToolTarget target) {
    switch (target) {
      case Pm3ToolTarget.device:
        _push(const ConnectPage());
      case Pm3ToolTarget.readCard:
        _push(const ReadCardPage());
      case Pm3ToolTarget.writeCard:
        _push(const WriteCardPage());
      case Pm3ToolTarget.slotManager:
        _push(const SlotManagerPage());
      case Pm3ToolTarget.hfSniffing:
        _dialog(const HfSniffingMenu());
      case Pm3ToolTarget.lfSniffing:
        _dialog(const LfSniffingMenu());
      case Pm3ToolTarget.apduTerminal:
        _push(const ApduTerminalPage());
      case Pm3ToolTarget.emvReader:
        _push(const EmvReaderPage());
      case Pm3ToolTarget.desfireReader:
        _push(const DesfireReaderPage());
      case Pm3ToolTarget.autopwn:
        _push(const AutopwnPage());
      case Pm3ToolTarget.darkside:
        _push(const DarksidePage());
      case Pm3ToolTarget.nested:
        _push(const NestedPage());
      case Pm3ToolTarget.staticNested:
        _push(const NestedPage(variant: NestedVariant.staticNonce));
      case Pm3ToolTarget.hardnested:
        _push(const NestedPage(variant: NestedVariant.hard));
      case Pm3ToolTarget.valueBlock:
        _dialog(const ValueBlockMenu());
      case Pm3ToolTarget.wiegand:
        _dialog(const WiegandMenu());
    }
  }

  void _push(Widget page) {
    Navigator.push(
      context,
      ModulePageRoute(moduleId: ModuleId.pm3Catalog, builder: (_) => page),
    );
  }

  void _dialog(Widget dialog) {
    showDialog(context: context, builder: (_) => dialog);
  }
}

class _SectionHeader extends StatelessWidget {
  final Pm3ToolSection section;

  const _SectionHeader({required this.section});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  section.title,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              Chip(label: Text('${section.tools.length}')),
            ],
          ),
          Text(
            section.description,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _ToolCard extends StatelessWidget {
  final Pm3Tool entry;
  final bool deviceMissing;
  final bool enabled;
  final VoidCallback? onTap;

  const _ToolCard({
    required this.entry,
    required this.deviceMissing,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context)!;
    final status = deviceMissing
        ? localizations.device_required
        : switch (entry.support) {
            Pm3ToolSupport.mapped => localizations.pm3_tools_mapped,
            Pm3ToolSupport.portable => localizations.pm3_tools_portable,
            Pm3ToolSupport.unsupported => localizations.pm3_tools_unsupported,
          };
    final reason = deviceMissing ? localizations.device_required : entry.reason;

    return Semantics(
      button: true,
      enabled: enabled,
      label: '${entry.command}. $status. $reason',
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: ValueKey('pm3-tool-${entry.id}'),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Opacity(
              opacity: enabled ? 1 : 0.62,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      SelectableText(
                        entry.command,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              fontFamily: 'monospace',
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                      _SupportChip(
                        label: status,
                        support: entry.support,
                        count: null,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(entry.summary),
                  const SizedBox(height: 4),
                  Text(reason, style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SupportChip extends StatelessWidget {
  final String label;
  final Pm3ToolSupport support;
  final int? count;

  const _SupportChip({
    required this.label,
    required this.support,
    required this.count,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final (icon, color) = switch (support) {
      Pm3ToolSupport.mapped => (Icons.link, colorScheme.primary),
      Pm3ToolSupport.portable => (Icons.construction, colorScheme.tertiary),
      Pm3ToolSupport.unsupported => (Icons.block, colorScheme.error),
    };
    return Chip(
      avatar: Icon(icon, color: color, size: 18),
      label: Text(count == null ? label : '$label: $count'),
      side: BorderSide(color: color),
    );
  }
}

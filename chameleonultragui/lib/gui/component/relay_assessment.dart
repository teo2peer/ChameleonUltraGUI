import 'package:chameleonultragui/helpers/emv.dart';
import 'package:flutter/material.dart';

// Localizations
import 'package:chameleonultragui/generated/i18n/app_localizations.dart';

// Defensive relay-resistance readout from the AIP (tag 82): tells you whether a
// card would block a relay attack (RRP) and whether it resists cloning
// (DDA/CDA), plus remediation guidance. Shared by the EMV reader and the
// purchase-simulation pages.
Widget relayAssessmentCard(BuildContext context, EmvAip? aip) {
  final l = AppLocalizations.of(context)!;
  if (aip == null) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text(l.relay_no_aip,
          style: TextStyle(color: Theme.of(context).colorScheme.outline)),
    );
  }
  final scheme = Theme.of(context).colorScheme;
  final protected = aip.rrp;
  final bg = protected ? scheme.primaryContainer : scheme.errorContainer;
  final fg = protected ? scheme.onPrimaryContainer : scheme.onErrorContainer;
  return Container(
    margin: const EdgeInsets.symmetric(vertical: 10),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10)),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Icon(protected ? Icons.verified_user : Icons.gpp_bad, color: fg),
          const SizedBox(width: 8),
          Expanded(
              child: Text(l.relay_assessment,
                  style: TextStyle(fontWeight: FontWeight.bold, color: fg))),
        ]),
        const SizedBox(height: 6),
        Text(protected ? l.relay_protected : l.relay_exposed,
            style: TextStyle(color: fg)),
        const SizedBox(height: 6),
        Text(aip.dda || aip.cda ? l.relay_clone_ok : l.relay_clone_weak,
            style: TextStyle(color: fg, fontSize: 12)),
        const SizedBox(height: 8),
        SelectableText("AIP ${aip.raw}: ${aip.features.join(', ')}",
            style:
                TextStyle(color: fg, fontSize: 11, fontFamily: 'RobotoMono')),
        const SizedBox(height: 8),
        Text(l.relay_remediation,
            style: TextStyle(
                color: fg, fontSize: 12, fontStyle: FontStyle.italic)),
      ],
    ),
  );
}

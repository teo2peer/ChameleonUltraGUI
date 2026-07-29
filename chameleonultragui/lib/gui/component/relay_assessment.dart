import 'package:chameleonultragui/helpers/emv.dart';
import 'package:flutter/material.dart';

// Localizations
import 'package:chameleonultragui/generated/i18n/app_localizations.dart';

// Scheme-aware AIP readout. Mastercard Kernel 2 defines its RRP support bit in
// AIP byte 2; applying that bit to another scheme would produce a false finding.
Widget relayAssessmentCard(BuildContext context, EmvAip? aip, {String? aid}) {
  final l = AppLocalizations.of(context)!;
  if (aip == null) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text(l.relay_no_aip,
          style: TextStyle(color: Theme.of(context).colorScheme.outline)),
    );
  }
  final scheme = Theme.of(context).colorScheme;
  final assessment = emvAssessRrp(aip, aid);
  final protected = assessment == EmvRrpAssessment.advertised;
  final missing = assessment == EmvRrpAssessment.notAdvertised;
  final bg = protected
      ? scheme.primaryContainer
      : missing
          ? scheme.tertiaryContainer
          : scheme.secondaryContainer;
  final fg = protected
      ? scheme.onPrimaryContainer
      : missing
          ? scheme.onTertiaryContainer
          : scheme.onSecondaryContainer;
  final message = switch (assessment) {
    EmvRrpAssessment.advertised => l.relay_protected,
    EmvRrpAssessment.notAdvertised => l.relay_exposed,
    EmvRrpAssessment.notApplicable => l.relay_rrp_not_applicable,
    EmvRrpAssessment.unknownScheme => l.relay_rrp_unknown,
  };
  return Container(
    margin: const EdgeInsets.symmetric(vertical: 10),
    padding: const EdgeInsets.all(12),
    decoration:
        BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10)),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Icon(
              protected
                  ? Icons.verified_user
                  : missing
                      ? Icons.gpp_maybe
                      : Icons.info_outline,
              color: fg),
          const SizedBox(width: 8),
          Expanded(
              child: Text(l.relay_assessment,
                  style: TextStyle(fontWeight: FontWeight.bold, color: fg))),
        ]),
        const SizedBox(height: 6),
        Text(message, style: TextStyle(color: fg)),
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

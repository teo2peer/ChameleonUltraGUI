enum ReaderKeyGuidanceStep {
  unavailable,
  ready,
  preparing,
  approach,
  remove,
  processing,
  repeat,
  complete,
}

enum ReaderKeyGuidanceTone { neutral, success, warning, danger }

class ReaderKeyGuidance {
  final ReaderKeyGuidanceStep step;
  final ReaderKeyGuidanceTone tone;
  final String title;
  final String description;

  const ReaderKeyGuidance({
    required this.step,
    required this.tone,
    required this.title,
    required this.description,
  });
}

ReaderKeyGuidance readerKeyGuidanceFor({
  required bool connected,
  required bool armed,
  required bool busy,
  required bool recovering,
  required bool randomUid,
  required int detectionCount,
  required int resultCount,
  required int appliedTargetCount,
}) {
  if (!connected) {
    return const ReaderKeyGuidance(
      step: ReaderKeyGuidanceStep.unavailable,
      tone: ReaderKeyGuidanceTone.danger,
      title: 'Conecta el Chameleon',
      description: 'Reader Keys necesita un dispositivo compatible conectado.',
    );
  }
  if (recovering) {
    return const ReaderKeyGuidance(
      step: ReaderKeyGuidanceStep.processing,
      tone: ReaderKeyGuidanceTone.warning,
      title: 'Procesando capturas...',
      description:
          'Aleja el Chameleon del lector mientras se recuperan, guardan y aplican las claves.',
    );
  }
  if (busy && armed) {
    return const ReaderKeyGuidance(
      step: ReaderKeyGuidanceStep.remove,
      tone: ReaderKeyGuidanceTone.warning,
      title: 'Aleja del lector',
      description:
          'Finalizando la captura y procesando el último conjunto de autenticaciones...',
    );
  }
  if (busy) {
    return const ReaderKeyGuidance(
      step: ReaderKeyGuidanceStep.preparing,
      tone: ReaderKeyGuidanceTone.warning,
      title: 'Preparando captura...',
      description:
          'Mantén el Chameleon alejado del lector mientras se prepara el slot.',
    );
  }
  if (!armed) {
    if (resultCount > 0) {
      return const ReaderKeyGuidance(
        step: ReaderKeyGuidanceStep.complete,
        tone: ReaderKeyGuidanceTone.success,
        title: 'Captura completada',
        description:
            'Revisa los resultados o arma otra captura para continuar aprendiendo claves.',
      );
    }
    return const ReaderKeyGuidance(
      step: ReaderKeyGuidanceStep.ready,
      tone: ReaderKeyGuidanceTone.neutral,
      title: 'Configura y arma la captura',
      description:
          'Selecciona la identidad y el slot de trabajo; después pulsa el botón para armar.',
    );
  }
  if (appliedTargetCount > 0 && detectionCount > 0) {
    return ReaderKeyGuidance(
      step: ReaderKeyGuidanceStep.repeat,
      tone: ReaderKeyGuidanceTone.success,
      title: 'Aleja y vuelve a acercar',
      description:
          '$appliedTargetCount clave(s) aplicada(s). Aleja completamente el Chameleon y vuelve a acercarlo para que el lector avance al siguiente sector.',
    );
  }
  if (resultCount > 0 && randomUid) {
    return const ReaderKeyGuidance(
      step: ReaderKeyGuidanceStep.remove,
      tone: ReaderKeyGuidanceTone.success,
      title: 'Aleja del lector',
      description:
          'Captura procesada. Con UID aleatorio las claves se guardan, pero no se aplican automáticamente.',
    );
  }
  if (detectionCount > 0) {
    return const ReaderKeyGuidance(
      step: ReaderKeyGuidanceStep.remove,
      tone: ReaderKeyGuidanceTone.warning,
      title: 'Aleja del lector',
      description:
          'Autenticación detectada. El procesamiento automático comenzará al reunir datos suficientes.',
    );
  }
  return const ReaderKeyGuidance(
    step: ReaderKeyGuidanceStep.approach,
    tone: ReaderKeyGuidanceTone.warning,
    title: 'Acerca al lector',
    description:
        'Mantén el Chameleon cerca hasta que el lector intente autenticar; después aléjalo.',
  );
}

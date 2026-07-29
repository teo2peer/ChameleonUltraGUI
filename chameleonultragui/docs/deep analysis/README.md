# Deep analysis

Auditoría técnica de rendimiento, arquitectura y reutilización de
ChameleonUltraGUI.

Documentos previstos:

- [`00-suspicion-ledger.md`](00-suspicion-ledger.md): registro vivo de todo hallazgo o sospecha antes de
  validarlo.
- [`01-codebase-metrics.md`](01-codebase-metrics.md): tamaño, hotspots y métricas estáticas.
- [`02-function-signatures.md`](02-function-signatures.md): índice de firmas, descripción mínima y ubicación.
- [`02-generated-code-summary.md`](02-generated-code-summary.md): conteos separados de localización/protobuf/FFI.
- [`03-performance-report.md`](03-performance-report.md): análisis validado y priorizado.
- [`04-reuse-map.md`](04-reuse-map.md): duplicaciones y oportunidades de componentes/servicios.
- [`05-optimization-roadmap.md`](05-optimization-roadmap.md): plan incremental, medición y riesgos.
- [`06-validation-playbook.md`](06-validation-playbook.md): escenarios, datasets y herramientas de profiling.
- [`07-dependency-size-audit.md`](07-dependency-size-audit.md): dependencias, assets, startup y binario.
- [`08-implementation-log.md`](08-implementation-log.md): cambios aplicados y evidencia de regresión.

Los documentos distinguen entre **confirmado**, **probable**, **sospecha** y
**descartado**. Ninguna propuesta se considera válida solo por similitud visual:
debe conservar semántica de protocolo, lifecycle, errores y seguridad.

Las correcciones de framing/polling, connector/BLE/DFU lifecycle, recovery,
slots, imports, Authorized Relay y release gates se registran en
`08-implementation-log.md`. Los límites que requieren HIL, credenciales de release
o garantías físicas superiores a SharedPreferences permanecen explícitos, no se
consideran cerrados por análisis estático.

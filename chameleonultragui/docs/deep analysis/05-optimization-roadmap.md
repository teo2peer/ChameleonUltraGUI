# Roadmap de optimización

## Objetivo

Reducir latencia, jank, consumo y deuda sin cambiar protocolo, recovery
correctness, formatos persistidos o seguridad. El orden minimiza riesgo: primero
instrumentar y cerrar fugas/corrupción; después reducir trabajo; al final extraer
reutilización y tamaño.

## Métricas de aceptación

No se fijan porcentajes finales hasta capturar baseline profile/release. Cada PR
debe informar, al menos:

- p50/p95 frame build/raster y número de frames >16.7/33 ms.
- p50/p95 command latency y queue wait por transport.
- command count por workflow.
- Dart heap y native RSS antes/después de loops repetidos.
- rebuild count de root y página activa.
- startup-to-first-frame y time-to-first-device-list.
- release size por plataforma/ABI cuando aplique.
- battery/radio duty para discovery/monitor.

## Fase 0: observabilidad y characterization

### Entregables

1. Instrumentar `notifyListeners` con reason en debug/profile.
2. Exponer queue depth, enqueue time, write time y response time.
3. Contadores debug de `_MainPageState.build`, Saved Cards, Dump Editor y BLE.
4. Fake-clock/communicator para poll overlap y deadlines.
5. Fixtures grandes reproducibles: cards, 100k keys, 4K dump, max EMV trace,
   16 MiB sync, 500 BLE notifications.
6. Capturar release/profile baselines según `06-validation-playbook.md`.

### Gate

No iniciar migración de estado/storage sin baseline y fixtures de compatibilidad.

## Fase 1: correctness, leaks y lifecycle

### 1A. Decoder serial

- **Corregido:** unsigned lengths, bounded buffer y resync.
- Tests de corrupción/split/coalesce están presentes; typed active-request error
  y su interacción con late response permanecen pendientes.

### 1B. Native recovery ownership

- **Corregido:** `recovery_free`, `try/finally`, ownership C/FFI y edge count cero.
- **Corregido:** último candidato nested y target key type static.
- **Corregido en source:** worker single-active con onError/onExit, fail pending,
  deadlines y restart solo tras exit real.
- Pendiente: oracle exacto, fault injection y ASan/LeakSanitizer CI reproducible.

### 1C. Connector resources

- **Corregido:** cerrar native probes siempre.
- **Corregido:** guardar/cancelar USB subscriptions.
- **Corregido en source:** clear callback/generations y disconnect en dispose;
  falta regression de connect/capability init bloqueado y late notifications.
- **Corregido:** BLE scan/connect deadline, MTU fragmentation, retry cancellation
  y native reader callbacks generation-bound. HIL sigue pendiente.

### 1D. DFU streaming/single-flight

- **Corregido:** SLIP persistente single-flight, response checks y cleanup.
- **Corregido:** discovery deadline, un único target, connect result y ranges de
  `maxSize`/MTU/chunk.

### 1E. Controller/route cleanup

- Camera/controller dispose.
- Operation tokens/mounted checks para dialogs y long loops.
- NTAG/Reader Keys cleanup best-effort al salir.

### 1F. Inputs fail-closed antes de materializar

- **Corregido:** QR index/count/byte caps y digest obligatorio.
- **Corregido:** Settings version/allowlist/atomic validation y migración segura.
- **Corregido:** Firmware ZIP central directory, input/output caps, CRC, nombres
  únicos y ejecución off-isolate.
- Cards/dictionaries: file byte cap y schema/count/dump-size antes de persistir.
- HTTP firmware/dictionaries: status/content-length/stream byte cap y timeout.

### 1G. Integridad de slot chunks

- **Corregido:** upload Classic sparse y export bounded Mini/1K/2K/4K con tests.

### 1H. Static-encrypted O(n+m)

- **Corregido:** sets lineales O(n+m), orden/duplicados preservados e
  `Isolate.run` supervisado.
- Pendiente: benchmark persistido y characterization adversarial.

### 1I. Integridad transaccional de Data Sync

- Prevalidar el snapshot y construir un plan antes de cualquier setter.
- Hacer commit/rollback awaited o usar storage transaccional comprobable.
- **Corregido:** preservar índices en conflictos unequal-length y rechazar lados
  sin bloque.
- Fault injection por write y fixtures de selección mixta.

### Gate

- Cero crecimiento native significativo en recovery repeats.
- Un frame corrupto no invalida siguientes frames.
- 20 reconnects no aumentan listeners/callbacks.
- Full suite y transport fault tests verdes.
- Static filter equivalente y sin coste cuadrático.
- QR/settings/ZIP/cards/dictionaries/downloads oversized o corruptos fallan antes
  de apply/decompress/materialización grande.
- Data Sync deja snapshot previo exacto o commit completo ante cualquier fallo.

## Fase 2: eliminar trabajo duplicado de alta frecuencia

### 2A. NonOverlappingPoller

- **Corregido:** migrar Read Card HF/LF y NTAG.
- Migrar bridge deadline loops simples.
- Después Reader Keys/BLE Stress; BLE Audit al final.

### 2B. End-to-end deadlines

- Deadline antes de enqueue; remaining time para open/write/response/poll.
- Queue cancellation y depth cap.
- Retry policies tipadas por error/status.

### 2C. State split

- Appearance por separado del device state.
- Connection/discovery/DFU/storage revisions separados.
- Root usa `select`; MaterialApp no escucha progress/device logs.
- Remover `changesMade()` gradualmente.

### 2D. Side effects fuera de build

- Sidebar breakpoint, scan ownership, wakelock coordinator, snackbars/listeners.
- Futures de hardware estables y refresh explícito.
- Eliminar rail measurement sin consumidores.

### 2E. Progress local/throttled

- DFU y slot upload con `ValueNotifier`/scope local.
- Notificar solo cambio porcentual visible o una vez por frame.

### Gate

- Máximo una operación por poller.
- Queue vuelve a cero al detener/salir.
- 4K upload no reconstruye root por bloque.
- Harmless local setState no emite comandos de Home/Slot Manager.

## Fase 3: datos y listas

### 3A. Repository cache sin migration

- `CardRepository`/`DictionaryRepository` sobre formato actual.
- Immutable snapshot, revisions y mutation-by-ID.
- Tests exactos de JSON y order.

### 3B. Lazy UI

- Saved Cards grids directos y lazy.
- Search materializa resultados una vez.
- Dictionary/hex/compare rows lazy.
- EMV trace body solo al expandir.
- BLE notifications cursor incremental.

### 3C. Storage migration

- Versioned atomic repository para cards/dicts/history/logs.
- Migration idempotente + backup/rollback probado.
- SharedPreferences solo escalares.

### 3D. Logging

- Lazy/capped/redacted message.
- In-memory ring + batch append/rotation.

### 3E. Archivos temporales

- Eliminar `.cusync` tras share completion cuando sea seguro.
- Sweep por edad al iniciar Data Sync para leftovers tras crash.
- Test de exports repetidos sin crecimiento ilimitado.

### Gate

- Un unrelated notifier no decodifica ninguna biblioteca.
- Update de una card no serializa todos los dumps en UI isolate.
- 1000 cards y 100k keys permanecen scrollables en profile.
- Migración sobre fixtures históricos es byte/data equivalent.

## Fase 4: CPU, memoria y operaciones grandes

### 4A. Recovery CPU restante

- Perfilar static/nested/hardnested después del fix lineal y ownership.
- Optimizar solo hotspots medidos; packed typed data/worker persistente si aplica.

### 4B. Dump Editor

- Sector widgets stateful/lazy, cached font/highlight.
- Dirty transition local.

### 4C. Data sync

- `toMap/fromMap`, encode once, direct ByteData views.
- Fingerprints indexados, resolve al submit, conflicts lazy.
- Isolate boundary para encode/decode/crypto/merge grandes.
- Semántica delete/tombstone decidida sobre el commit atómico de Fase 1I.

### 4D. Rendimiento de import después del fail-closed

- Mover ZIP hash/decompression y parse de JSON/modelos grandes a isolate.
- Leer cada input una vez y reducir buffers/copias intermedias.
- Mantener los caps, schemas y digest ya implementados en Fase 1F.

### 4E. Waveforms/traces

- LF min/max envelope por pixel, decode debounce, cached geometry.
- Host caps EMV y evitar representaciones raw duplicadas.

### Gate

- Dump typing 4K no excede frame budget de forma sostenida.
- Sync 16 MiB no bloquea UI; memory peak medido y acotado.
- Import de inputs válidos grandes no bloquea UI ni duplica memoria sin límite.

## Fase 5: reutilización estructural

Orden recomendado:

1. Pure codecs/CRC/DumpBytes/CardData.
2. Response specs del bridge.
3. FileExportService.
4. SlotEmulationService.
5. Card/dictionary repository API final.
6. Form/dialog/search/responsive components.
7. Recovery run shell.
8. EMV projection/presentation.
9. HF/LF capture shell.
10. BLE operation lifecycle.
11. CompositeSerial e import finalizer.

### Gate por extracción

- Reducir al menos dos call sites reales.
- Characterization test antes y después.
- No cambiar command transcript ni accepted statuses.
- No introducir `dynamic` o flags para ocultar diferencias domain-specific.

## Fase 6: tamaño, startup y energía

### Dependencias/assets seguros

- Quitar `async`, `convert`, direct `cross_file`.
- Mover `ffigen` a dev dependency.
- Quitar runtime `assets/logo.png`.
- Pin git dependencies y actualizar file_picker cuando sea estable.

### Decisiones de producto medibles

- Mobile Scanner bundled vs unbundled/offline requirement.
- Path provider por un único temp export.
- Locales soportados.
- Imágenes fuente no referenciadas.

### Startup/energía

- App lifecycle observer.
- Pausar scan/monitor al background.
- Backoff y scan mode menos agresivo tras discovery inicial.
- Solicitar permisos al entrar en una feature cuando sea viable.

### Gate

- Comparativa `--analyze-size` por ABI/plataforma.
- Startup trace y Energy Log/Battery Historian.
- Cero regresión de QR offline, BLE discovery y export.

## División sugerida de PRs

Mantener PRs pequeñas y reversibles:

1. Parser tests + decoder fix. **Completado.**
2. Static filter O(n+m) + characterization.
3. Native recovery ownership/count/worker lifecycle.
4. QR/settings/ZIP/cards/dictionaries/downloads fail-closed limits.
5. Slot sparse/Mini correctness.
6. Data Sync atomic apply + block-shape integrity.
7. DFU streaming/selection/progress bounds.
8. USB/native connector cleanup. **Completado; stress/HIL pendiente.**
9. Poll primitive + Read Card/NTAG. **Completado.**
10. Stable futures Home/Slot.
11. State split DFU progress.
12. Repository cache.
13. Saved Cards lazy grids/search.
14. Dump Editor sector isolation.
15. Data sync serialization/worker/temp cleanup.
16. SlotEmulationService.
17. EMV lazy projection/view.
18. Logging batch/redaction.
19. Dependency/assets cleanup.

No mezclar en una sola PR parser, storage migration, state architecture y visual
refactor: dificulta bisect, profiling y rollback.

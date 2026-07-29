# Informe detallado de rendimiento y arquitectura

## Resumen ejecutivo

La sensación de pesadez no viene de una sola causa. El análisis estático muestra
cuatro multiplicadores que se combinan:

1. **Un evento pequeño invalida demasiado UI.** El notifier global reconstruye
   el shell, themes y páginas, y algunos builds ejecutan I/O o persistencia.
2. **Datos grandes se reprocesan de forma eager.** Cards/dictionaries, dumps,
   traces y sync serializan, formatean o construyen árboles completos.
3. **La cola de dispositivo absorbe trabajo duplicado.** Pollers solapables,
   futures recreados y monitores generan comandos aunque el usuario no haya
   pedido una actualización nueva.
4. **Hay deuda de lifecycle/memoria.** Streams, puertos, controllers y recovery
   native pueden sobrevivir a su operación, elevando coste con el tiempo.

Los problemas con mejor relación impacto/riesgo son: arreglar parser/resources,
eliminar fugas native, hacer lineal el filtro static-encrypted, separar estado
global, cachear repositorios y evitar polling/futures solapados. Extraer widgets
visuales antes de estas correcciones reduciría líneas, pero no resolvería la
lentitud principal.

## Metodología y límites

- Auditoría estática de todo `lib/`, `src/recovery.c`, pubspec, plugins y tests.
- Inventario AST repo-wide de 2,721 declaraciones mantenidas; 2,495 pertenecen
  al código productivo bajo `lib/`.
- Conteos de líneas/patrones y revisión de todos los timers/FutureBuilders.
- No se ejecutó profiling en hardware móvil ni Chameleon físico.
- `Confirmado` significa que el mecanismo existe en código; el coste exacto
  todavía debe medirse en profile/release.
- `Probable` requiere confirmar frecuencia o impacto de plataforma.
- P0/P1/P2 expresa impacto, no un orden lineal de implementación. Las fases de
  `05-optimization-roadmap.md` son la fuente canónica de ejecución y respetan
  dependencias/characterization; los P0 de integridad/liveness están en Fase 1.

## Prioridad P0: impacto crítico o alto

### P0.1 Parser serial recuperable y acotado

**Estado:** Corregido el 2026-07-15. **Impacto original:** crítico de fiabilidad y memoria.

Antes de la corrección, el parser dentro de `lib/bridge/chameleon.dart` conservaba
posición/buffer al lanzar por SOF/LRC inválido y leía length signed. `FFFF` se
volvía -1, evitaba el límite y podía hacer crecer el buffer indefinidamente.

**Efecto percibido:** comandos que empiezan a expirar, app aparentemente
congelada y crecimiento de memoria tras ruido o framing parcial.

**Cambio mínimo:** decoder streaming con `u16` unsigned, cap duro y reset/resync
buscando el siguiente SOF. Error tipado para la request activa permanece
pendiente: hoy el frame malformed se registra y la request espera su deadline.

**Validación:** inyectar byte inválido, header LRC malo y length `FFFF`, seguidos
de una trama válida; la trama válida debe recuperarse y memoria permanecer
acotada.

**Implementado:** `ChameleonFrameDecoder` procesa chunks fragmentados o
coalesced, usa UInt16 big-endian, limita payload a 4,096 bytes y descarta hasta
el siguiente SOF tras LRC/length inválido. El communicator despacha solo frames
válidos. Tests cubren noise, LRCs, `FFFF`, resync y límites outbound.

### P0.2 Liberar todas las asignaciones native recovery

**Estado:** Corregido en source y smoke/leak local. **Impacto previo:** crítico.

Inputs Dart se liberan con `calloc.free`, outputs C con `recovery_free`, y los
temporales/early returns C tienen cleanup allocator-matched. También se corrigió
el edge `nonce2key()` con lista no nula y count cero.

**Validación:** 50 repeticiones por algoritmo bajo ASan/LeakSanitizer o
Instruments; RSS native debe estabilizarse.

### P0.2b Corregir pérdida del último candidato nested

**Estado:** Corregido en source; oracle exacto pendiente. **Impacto previo:** alto.

`nested_recover` asigna el `kcount` completo y no considera error un `realloc`
válido sin movimiento. Los tests aún verifican presencia, no set/count completo.

**Cambio mínimo:** construir un oracle independiente (upstream/test vector o
verificación criptográfica), demostrar el set/count correcto y actualizar el
golden después del fix. No tratar el output truncado actual como authoritative.

### P0.2c Hacer observable y reiniciable el worker recovery

**Estado:** Corregido en source; fault injection pendiente. **Impacto previo:** alto.

El worker acepta una operación activa, usa deadline específico (hardnested 30
min), registra `onError`/`onExit`, falla pending y solo queda reiniciable tras el
exit real del isolate, evitando workers FFI solapados.

### P0.3 Hacer lineal StaticEncryptedKeysFilter

**Estado:** Corregido en source. **Impacto previo:** crítico de CPU.

Cada lista calcula seeds una vez y filtra por membership de `Set`, O(n+m),
preservando orden y duplicados. `Isolate.run` aporta lifecycle/error propagation
y timeout sin receive ports manuales.

**Validación:** benchmark del test static encrypted actual, igualdad exacta de
orden/duplicados/resultados y perfil CPU antes/después.

### P0.4 Separar el notifier global y sacar side effects de build

**Estado:** Confirmado. **Impacto:** alto y frecuente.

`ChameleonGUIState` mezcla conexión, scan, DFU, librerías y eventos. El root usa
`context.watch` (`lib/main.dart:711-872`) y recrea `MaterialApp`, themes y navigation.
Dentro de build también asigna callbacks, guarda sidebar, inicia/detiene scan,
invoca wakelock y programa snackbars (`lib/main.dart:713-817`). `changesMade()` no
expresa qué cambió y aparece en decenas de call sites.

**Efecto percibido:** progreso DFU, upload de un bloque o cambio de count provoca
trabajo visual/plataforma no relacionado.

**Cambio mínimo:** mover `MaterialApp` fuera del listener de dispositivo;
separar connection, discovery, DFU progress, appearance y library revisions.
Usar `context.select`/`Selector` alrededor del subtree mínimo.

**No hacer:** reemplazar todo por otro notifier monolítico o extraer métodos de
build sin cambiar boundaries; eso no reduce rebuilds.

**Validación:** `debugPrintRebuildDirtyWidgets` y DevTools durante DFU, upload 4K,
auto-scan y edición de card. Contar builds de root/página antes/después.

### P0.5 Repositorios cacheados para cards/dictionaries/logs

**Estado:** Confirmado. **Impacto:** alto con bibliotecas medianas/grandes.

`getCards` y `getDictionaries` decodifican JSON completo en cada llamada;
setters serializan/reemplazan la colección completa
(`lib/sharedprefsprovider.dart:321-359`). Saved Cards hace ambos reads en build y
construye grids completos usando scroll externo + `shrinkWrap`.

SharedPreferences también almacena hasta 5,000 logs y reescribe la lista completa
por cada línea (`lib/sharedprefsprovider.dart:478-488`). No es un database adecuado
para dumps, diccionarios o logs grandes.

**Cambio mínimo en dos fases:**

1. Cache in-memory + immutable snapshots + revisions + mutations por ID, sin
   cambiar formato persistido.
2. Migrar payloads grandes a archivo/database atómico; SharedPreferences solo
   para escalares y migration marker.

**UI:** hacer los grids scrollables directos/lazy; no `SingleChildScrollView` +
`NeverScrollable` + `shrinkWrap`.

**Validación:** 100/500/1000 cards, diccionario 100k keys y unrelated notifier.
Medir JSON decodes, allocations, first-open y update por ID.

### P0.6 Unificar polling no solapable y acotar la cola

**Estado:** Corregido el 2026-07-15 para Read Card HF/LF y NTAG. **Impacto original:** alto en BLE lento.

Antes de la corrección, Read Card HF/LF y NTAG usaban `Timer.periodic` con callback
async sin guard. Timer no esperaba el callback; un scan lento podía encolar
operaciones y cancelar Timer no eliminaba callbacks ya en cola.

**Cambio mínimo:** `NonOverlappingPoller` que agenda una vez tras completar,
generation cancellation y `inFlight`; aplicarlo primero a Read Card/NTAG. Queue
depth, enqueue timestamp y deadline total siguen pendientes.

**Validación:** fake communicator con 3 s de latencia y poll 2 s; concurrencia
high-level y backlog deben quedar en 1/0 respectivamente tras cancelación.

**Implementado:** `NonOverlappingPoller` agenda el siguiente tick solo tras
completion, invalida callbacks por generación y soporta stop/restart durante una
tarea. Los tres poll loops iniciales comparten esta primitive y sus tests prueban
concurrencia máxima uno, cancelación y restart sin solapamiento.

### P0.7 Cerrar puertos, streams y callbacks de lifecycle

**Estado:** Corregido para S-014/S-015/S-016 el 2026-07-15. **Impacto original:** alto acumulativo.

- Antes de la corrección, native probes no-Chameleon no cerraban port en
  false/error.
- Android USB no almacenaba/cancelaba input y global event subscriptions.
- Dispose global no invalidaba scan activo, limpiaba callback ni desconectaba
  connector.
- Manual connect puede competir con scan compartido.

**Cambio mínimo:** `try/finally` para probes, ownership explícito de toda
subscription, connection/scan generation y un coordinador único para manual/auto.

**Validación:** 100 scans de puerto ajeno; 20 reconnects Android y un detach;
dispose mientras `availableChameleons` está bloqueado.

**Implementado:** probes native se cierran y disponen en todos los paths; el
puerto transferido se dispone exactamente una vez al disconnect. Android USB
posee ambas subscriptions, usa generation guards y await de close. Dispose global
invalida scans/connect pendientes, limpia `connectionStateCallback` y arranca
teardown contenido. Los tests actuales usan 20 probes, cinco reconnects y blocked
scan; faltan los stress counts documentados, connect/capability init bloqueado y
demostrar que disconnect/progress no notifican tarde. La coordinación manual/auto
y el retry BLE están generation-bound; faltan HIL/stress y coordinación manual/auto.

### P0.8 Arreglar FutureBuilder/I-O y setState durante build

**Estado:** Confirmado. **Impacto:** alto.

Home, Slot Changer y Slot Edit todavía crean futures de hardware desde build.
Slot Manager ya conserva `_loadFuture` y solo lo reemplaza por refresh explícito.
En los restantes, un setState visual repite batería, slot info, version o capabilities.
`SlotExportMenu` llama setState desde build. La preparación MFC inicia una función
async que ejecuta parent setState antes del primer await mientras el padre se
construye.

**Cambio mínimo:** futures estables creados en init/refresh explícito, con
generation/device identity. Build solo representa loading/data/error. No usar
builders genéricos que oculten un future recreado.

**Validación:** fake communicator cuenta comandos ante theme notification,
dropdown, selección visual y rebuild padre; debe haber cero I/O sin refresh.

### P0.8b Corregir corrupción concreta de upload/export de slots

**Estado:** Corregido. **Impacto previo:** alto de integridad de datos.

`slot_transfer.dart` produce chunks contiguos sparse y planes de lectura bounded
para Mini/1K/2K/4K. Slot Manager/Export los consumen y los fixtures cubren gaps,
remainder y límites.

### P0.9 Optimizar Dump Editor por sector

**Estado:** Confirmado. **Impacto:** muy alto al editar dumps grandes.

Cada cambio de controller llama parent setState. `_guessOptimalFontSize` prueba
61 tamaños y hace dos layouts por tamaño, hasta ~122 `TextPainter.layout` por
editor visible, además de highlight y spans. `List.generate` crea todos los
editores.

**Cambio mínimo:** dirty state solo false->true, state por sector, font size
analítico/cache `(width, format, textScale)`, lazy builder y highlight cache.

**Validación:** typing 4K, frame time, layouts y builds por carácter.

### P0.10 Sacar data sync pesado del UI isolate

**Estado:** Confirmado. **Impacto:** alto cerca de límites.

Snapshots hacen map->JSON->model varias veces, validación serializa de nuevo,
merge recalcula fingerprints y `plan.resolve()` se ejecuta desde build.
`_readUint32` copia el bundle completo para leer 4 bytes.

La detección de cambios actual compara dos strings JSON completos, no Maps por
identidad (`lib/gui/page/data_sync.dart:112-117`): es correcta estructuralmente
pero duplica serialización pesada.

**Cambio mínimo:** canonical `toMap/fromMap`, una única codificación boundary,
fingerprints/revision precomputados, resolve solo al confirmar,
conflicts lazy y `Isolate.run`/TransferableTypedData para 1+ MiB.

**Validación:** 1/8/16 MiB, peak RSS/event-loop gaps; test no-change debe quedar
false; cambiar una elección no debe resolver/copiar snapshot completo.

### P0.10b Hacer atómico el apply y preservar forma de bloques

**Estado:** Corregido. **Impacto previo:** alto de integridad.

Apply y setters sincronizados son awaited. El provider mantiene revision/hash CAS,
WAL staged con PREPARED/commit-decided, receipts idempotentes, vista committed
atómica durante writes físicos parciales e intents locales durables. Peer v2 usa
PREPARE/COMMIT/ACK/QUERY y conserva decisiones COMMIT/ABORT para re-pair/restart.

SharedPreferences no ofrece fsync, transacción multi-key ni CAS multiproceso; el
protocolo garantiza recovery a nivel de aplicación, no más durabilidad física que
el backend de cada plataforma.

**Validación:** fault injection en cada stage/target/meta/receipt/cleanup,
restart, intents concurrentes y fixtures de geometría/card/script; la vista del
provider expone snapshot previo exacto o commit nuevo completo, nunca mezcla.

### P0.11 Rehacer DFU como decoder streaming single-flight

**Estado:** Corregido en source. **Impacto previo:** alto durante actualización.

DFU usa SLIP incremental, single-flight con
cleanup en setup/write/response, lengths y rangos semánticos. Discovery tiene 30
s de deadline, exige un único candidato compatible, conecta ese port y valida
bool/state. MTU/maxSize/chunk progress inválidos fallan antes del loop.

**Validación:** split en cada byte, dos packets en un callback, responses 0..3
bytes, dos requests concurrentes, discovery timeout, `maxSize` cero y MTU 0..4,
y discovery mixto BLE/wired con orden invertido.

### P0.12 Fail-closed y límites antes de materializar imports

**Estado:** Parcialmente corregido. **Impacto:** alto de integridad/OOM.

- QR import exige digest, índices, count y byte caps.
- Legacy settings usa formato versionado/allowlist y migra solo escalares seguros.
- Firmware ZIP valida directorio central, nombres únicos, método/encryption,
  input/output/entry caps y CRC en isolate bounded.
- Cards/dictionaries leen archivos arbitrarios completos antes de validar schema.
- Firmware/dictionary downloads se acumulan completos sin response byte cap.

Cards/dictionaries/downloads todavía necesitan caps antes de materializar; esa
parte permanece en Fase 1.

## Prioridad P1: siguiente ciclo

### P1.1 Logging lazy, redactado y batch

Full frame/payload se convierte a hex antes de que logger decida nivel. Un
response 4 KiB crea miles de strings pequeños. Persistent logger reescribe hasta
5,000 filas por línea.

Agregar lazy message/cap de prefix, metadata de sensibilidad por comando y ring
buffer con flush batch a archivo. Medir comandos pequeños y payloads máximos.

### P1.2 Deadline end-to-end y retries tipados

El timeout actual empieza después de queue/open/write y `Future.timeout` no
cancela write. Poll BLE de 2 s puede tardar mucho más porque cada status call
tiene 5 s. Algunos writers reintentan cualquier exception; hardnested tiene
deadline de 30 min pero no cancelación/no-progress cooperativo.

Crear deadline monotónico desde enqueue y pasar remaining time. Retry solo
statuses transitorios con backoff/cancel. Hardnested: max rounds/time/nonces y
dedup/no-progress.

### P1.3 Lazy EMV/transit trace explorer

Transit, EMV Reader y Transaction construyen/hex-formatean todos los records aun
cuando ExpansionTiles están cerrados. Crear projection al recibir capture y un
`EmvTraceExplorer` lazy/paginado; no unificar las adquisiciones read-only y
state-changing.

### P1.4 Controllers y route-operation ownership

Hay controllers recreados en build y muchos no dispuestos; QR camera no libera
explícitamente. Varias operaciones siguen tras pop y hacen setState sin mounted.

Regla: controller creado una vez por owner State y dispose simétrico. Operaciones
largas usan communicator snapshot, generation/cancel y cleanup best-effort.

### P1.5 Cursor incremental para BLE notifications/logs

BLE Audit pide notificaciones desde índice 0 cada 300 ms, haciendo bytes y parse
aproximadamente cuadráticos. Usar `startIndex=seen`, append bounded y subtree
independiente para status/log.

### P1.6 Monitor de emulación adaptativo

Un MFC 4K requiere ~20 comandos cada 3 s. Stop invalida resultados pero no corta
el snapshot entre chunks. Comprobar generation antes de cada comando y sustituir
polling de 10 ms para pause por completion Future. Idealmente firmware expone
dirty revision/blocks; mientras tanto pausar ante operaciones foreground.

### P1.7 Imports off-isolate después de hacerlos fail-closed

Tras P0.12, mover ZIP hash/decode y JSON/model parsing grande fuera del UI
isolate, leer firmware una vez y evitar buffers duplicados. Los límites y digest
no deben depender de esta optimización posterior.

### P1.8 Response schemas compartidos

BLE/keyboard validan mejor que bridge core. Introducir response specs explícitos
por comando: accepted statuses, exact/min/max length y decoders tipados. No asumir
`0x68` global: RF usa `0x00`, algunas operaciones admiten `0x01/0x66` con semántica
propia.

### P1.9 Navegación con estado, pero pausa explícita

El switch top-level destruye páginas y repite I/O/scroll/form state. Un
IndexedStack ciego mantendría timers activos, por lo que la solución debe ser
route-aware: cache selectivo y `onActive/onInactive` para scans/pollers.

### P1.10 Wakelock con ownership único

Root y MIFARE llaman `WakelockPlus.toggle` desde build y pueden competir. Crear
coordinador reference-counted y acquire/release en start/finally/dispose.

## Prioridad P2: tamaño, polish y deuda de bajo riesgo

### Dependencias y assets

- Retirar direct deps no usadas `async`, `convert` y `cross_file`.
- Mover `ffigen` a dev dependency.
- Quitar `assets/logo.png` solo de runtime assets.
- Decidir si las 19 imágenes no referenciadas son design masters antes de borrar.
- Medir Mobile Scanner bundled vs unbundled, no eliminar QR sin decisión de producto.
- Pin git dependencies y abandonar file_picker beta cuando haya alternativa estable.
- Ajustar SDK constraint a Dart realmente requerido.

### Responsive/layout

NavigationRail fijo, Home/Flashing no scrollables y Connect siempre dos columnas
requieren golden tests 320x568, landscape, split-screen y textScale 2. El patrón
`BleResponsiveFieldGroup` es una base buena para primitives neutrales.

### Startup

Esperar SharedPreferences antes de runApp es un tradeoff coherente para evitar
flicker. Medir antes de cambiar. Auto-scan inmediato/permissions y side effects de
build son candidatos más fuertes que la espera de preferencias.

## Patrones positivos a preservar

- Command queue single-flight y active response armado antes del write.
- Capability initialization compartida y command gating.
- Late response quarantine.
- Scanner principal y emulation monitor se autoagendan tras completar.
- Generation/in-flight guards en BLE, emulation monitor, Reader Keys y BLE Stress.
- Authorized Relay tiene tokens, deadline terminal por APDU, cleanup `6013`
  ordenado y monitor pause sólidos; no tiene lease firmware, timer de reciclado
  GUI ni expiry global nativo;
  el servicio payment permanece seleccionable mientras el APDU path desarmado
  responde fail-closed. Arm mantiene monitor pause desde adquisición automática
  hasta enable HCE atómico, sin poll intermedio.
- Parsers nuevos de EMV trace, keyboard y BLE validan framing/length/status.
- Data sync ya tiene limits, AEAD y allowlist de settings, aunque su ejecución
  necesita optimización.
- ListView lazy en logs/changelog/emulation history.

## Qué no optimizar a ciegas

- No agregar `useMemo/useCallback` por defecto: este es Flutter, y el problema es
  scope/ownership, no identidad de closures aisladas.
- No fusionar transports físicos ni DFU con communicator normal.
- No fusionar Gen1/Gen2/Gen3 writers, EMV read/transaction o strict/tolerant BLE AD.
- No mantener todas las páginas vivas sin lifecycle pause.
- No migrar persistence y modelos inmutables en el mismo paso sin fixtures de
  compatibilidad; separar cache/repository de storage migration.

# Registro de implementación

## 2026-07-16: monitor MFC sobre snapshot atómico firmware

- El monitor exige capability 1050 explícita; firmware legacy/unknown o lista que
  omite 1050 no usa fallback optimista.
- BEGIN v2 devuelve slot/tipo/owner-generation/revision; identidad no usa UID
  random. Versiones previas fallan cerrado. Cada anticollision/chunk comprueba
  generation del monitor, communicator/connector exactos y conexión antes/después.
- Baseline nueva o dump sin cambios ejecutan ABORT. Un diff usa timeout SAVE de
  55 s; timeout invalida/desconecta. Tras SAVE, historia local se espera/verifica
  y solo entonces avanzan baseline/notificación. Fallo local queda pending y se
  reintenta antes de otro poll sin repetir SAVE. El monitor no envía 1009.
- BEGIN success malformado extrae revision primero para ABORT best-effort; sin
  revision v2 o cleanup confirmado se invalida y desconecta el communicator.
- Fake serial prueba framing v2, random UID, ABORT/poison malformado, timeout,
  persistencia pending y cancelación sin iniciar chunks posteriores.
- Permanece HIL Ultra/Lite para latencia BLE/USB, RF real, expiry tras disconnect y
  fallo/power-loss FDS. La cancelación cooperativa se observa entre comandos; una
  respuesta serial ya en vuelo no puede ser retirada.

## 2026-07-15: framing, polling y settings v6

### Alcance

- S-013: parser serial no recuperable y longitud signed sin límite efectivo.
- S-002: polling async periódico solapable en Read Card HF/LF y NTAG password.
- Contrato coordinado de `GET_DEVICE_SETTINGS` v6 con firmware y CLI.

### Implementación

- `lib/bridge/chameleon_frame_decoder.dart` separa framing del communicator,
  decodifica UInt16 big-endian, limita payload a 4,096 bytes y recupera el
  siguiente frame tras noise, SOF/header/final LRC inválido o length oversized.
- La construcción outbound valida command/status de 16 bits y payload antes de
  escribir. `ChameleonCommunicator` recibe frames válidos del decoder y descarta
  errores sin dejar el buffer permanentemente bloqueado.
- `lib/helpers/non_overlapping_poller.dart` agenda una ejecución después de que
  termine la anterior, con cancelación por generación y restart explícito.
- Read Card HF/LF y NTAG password capture migraron desde `Timer.periodic` a la
  primitive no solapable.
- Settings v6 acepta el payload canónico de 14 bytes y conserva lectura de los
  payloads legacy v5/v6 de 13 bytes; el nuevo byte final expone sleep timeout.
- Battery voltage se interpreta como UInt16 big-endian, igual que el contrato
  firmware.

### Regression tests

- `test/chameleon_frame_decoder_test.dart`: split/coalesced frames, noise,
  corrupción de LRC, length `FFFF`, cap, resync y validación outbound.
- `test/chameleon_command_queue_test.dart`: integración del decoder y settings
  v6/legacy sin romper serialización/quarantine existente.
- `test/non_overlapping_poller_test.dart`: máximo una tarea concurrente,
  completion-scheduled polling y stop/restart durante in-flight.

### Validación completa

- `flutter analyze`: cero issues.
- `flutter test` con `LIBRECOVERY_PATH` arm64: 278/278 tests pasaron.
- El inventario reproducible se regeneró: 184 archivos mantenidos y 2,443
  declaraciones.

USB/BLE real, lifecycle de connectors y consumo móvil siguen requiriendo
HIL/profile.

## 2026-07-15: ownership de connectors y dispose global

### Implementación

- Native serial usa candidates locales: rejected/error/discovery-only siempre
  close+dispose; un puerto seleccionado transfiere ownership y se dispone una vez
  al disconnect.
- Android USB conserva y cancela input + detach subscriptions, invalida callbacks
  stale por generation, espera configuración/cierre asíncronos y continúa el
  teardown aunque una cancelación falle.
- `saveSlotData()` convierte flash status fallido en excepción; Slot Manager
  libera su progress state también en ese path y el selector conserva el
  `ScaffoldMessenger` padre para mostrar el error tras cerrar la ruta de búsqueda.
- `ChameleonGUIState.dispose()` invalida scans/connects pendientes, detiene el
  monitor, limpia communicator/`connectionStateCallback` y lanza teardown con
  error logging.

### Validación

- 11 lifecycle regressions cubren probes, transfer/dispose, reconnects, detach,
  open/config/cancel failure y dispose durante scan success/error bloqueado.
- Pending connect/capability init, late disconnect/progress notifications y los
  stress counts de 100 probes/20 reconnects todavía no tienen regression.
- Snapshot+save del emulation monitor sigue sin una transacción que excluya
  uploads/edits concurrentes del mismo slot (S-094).
- `flutter analyze`: cero issues.
- Full suite arm64 native recovery: 278/278 tests pasaron.

## 2026-07-16: cierre de auditoría GUI profunda

### Transporte y lifecycle

- BLE fragmenta por ATT MTU-3, aplica deadlines de scan/connect, cancela el retry
  loop por generation y completa teardown de subscriptions/characteristics.
- Native serial conserva la subscription del reader y descarta callbacks stale
  por reader/generation. Connector demo/real hace teardown y revierte preferencia
  si falla.
- Communicator invalida/disconnect ante write failure o timeout con frame parcial;
  la quarantine por command ID sigue cubriendo late responses completas.
- DFU usa SLIP incremental, single-flight con cleanup en todos los paths,
  response/range checks, discovery deadline y selección no ambigua.

### Recovery, slots y persistencia

- `recovery_free`, cleanup C/Dart y el candidato nested final corrigen ownership y
  truncación. El worker acepta una operación, tiene deadlines por algoritmo,
  fail-pending, error/exit y restart solo después del exit real.
- Static-encrypted pasó del cross-product de ~1.22B comparaciones a sets O(n+m)
  dentro de `Isolate.run`; static nested usa el tipo de key atacado.
- Planner Classic sparse y export bounded preservan offsets Mini/1K/2K/4K.
- Mutex de slot generation-bound serializa monitor/upload/edit/export/Reader
  Keys/EMV/settings; writes GUI invalidan baseline y failed save no la avanza.
- Data Sync no compacta bloques ausentes. Settings/scripts validan todo antes de
  mutar; backups flat previos migran solo escalares allowlisted.

### Seguridad y release

- Authorized Relay adquiere automáticamente una sesión ISO-DEP viva al activar
  Arm, sin Prepare previo ni popup de review. El enable HCE nativo es atómico y
  liga token, Activity resumed, AID exactas y deadline terminal por APDU;
  EventChannel es compartido entre routes y Android backup está deshabilitado.
  No hay lease de inactividad firmware, reciclado temporizado GUI ni expiry global
  nativo. Cleanup armado/preparación usa reset `6013` ordenado y conserva la misma
  conexión tras status confirmado `0x68`, `0x60` o `0x66`.
  El `HostApduService` payment permanece visible como `CU GUI Authorized Relay`
  al pausar/reiniciar/actualizar y conserva las últimas AID tras cada test; Android
  15 usa wallet role y versiones previas el selector directo. Sin arm token, el
  servicio persistente responde `6400`. La ruta y Payment settings son accesibles
  sin Ultra conectado; abrir settings cancela y espera adquisición en curso.
- QR settings exige digest/index/count/caps. Firmware ZIP valida central
  directory, nombres únicos, método/encryption, tamaños observados y CRC fuera
  del UI isolate.
- T55xx envía la nueva password una vez; mutators core propagan status firmware.
- Publish/Build gatean analyzer/tests/build, native ASan/UBSan, semver exacto,
  ancestry de `main` y attestation HIL ligada al SHA/evidence; falta activarlos
  desde un commit protegido y configurar el environment `hardware-validated`.

### Cierre de los límites arquitectónicos

- Data Sync usa checkpoint revision/hash CAS, WAL staged, PREPARED irrevocable,
  COMMIT/ABORT durable, receipts idempotentes y peer v2 reanudable por re-pair.
  Intents locales concurrentes se journalizan y la vista committed del provider
  no expone writes físicos parciales.
- Command 1050 v2 congela sensing/owner por transporte y añade generation estable,
  lease/deadline coordinado y SAVE exacto; random UID ya no pierde cambios RF.
- Recovery incluye smoke C reproducible con ASan/UBSan y Linux CI ejecuta además
  la suite Dart FFI contra la librería instrumentada.
- Android quedó en Gradle 8.14.3, AGP 8.12.2, KGP 2.3.20 y JVM 17. AGP 9 fue
  probado y queda bloqueado por plugins upstream todavía no migrados a built-in
  Kotlin (`reactive_ble_mobile`, `wakelock_plus` y detección de `mobile_scanner`).

### Evidencia local final

- `flutter analyze`: cero issues.
- Suite completa con recovery native arm64: 410/410 tests.
- `flutter build apk --debug`: correcto; queda el warning KGP de plugins upstream.
- Native recovery arm64 fue relinkado tras el último cleanup C.
- YAML de ambos workflows parsea y `git diff --check` pasa.
- Native recovery sanitizer smoke: correcto en macOS; Linux CI añade Dart FFI.
- Firmware host ASan/UBSan: 11/11 binaries; Python hardware-free: correcto.
- Firmware ARM Ultra/Lite: 358,660/290,532 bytes de texto.
- Inventario reconciliado: 191 archivos mantenidos y 2,721 declaraciones.

### Límites externos

- SharedPreferences no ofrece fsync/CAS multiproceso; WAL garantiza recovery de la
  aplicación, no durabilidad física superior al backend de cada plataforma.
- Authorized Relay evita sustitución dentro de la sesión viva, pero autenticación
  criptográfica de credencial requiere CAPK y DDA/fDDA/CDA verificadas.
- HIL físico BLE/USB/DFU/HCE sigue siendo obligatorio; el release falla cerrado
  hasta que `HIL_APPROVED_SHA` y `HIL_EVIDENCE_SHA256` estén aprobados para ese SHA.
- El warning built-in Kotlin depende de releases upstream compatibles con AGP 9.

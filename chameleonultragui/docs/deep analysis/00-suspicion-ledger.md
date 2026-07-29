# Ledger de hallazgos y sospechas

Este archivo se actualiza durante la exploración. Primero registra indicios;
después enlaza su validación profunda en los informes finales.

## Estados

- `Sospecha`: indicio pendiente de lectura/medición.
- `Probable`: evidencia estática fuerte, falta perfilado en dispositivo.
- `Confirmado`: mecanismo demostrado por el código o pruebas.
- `Descartado`: la investigación no sostuvo la hipótesis.
- `Corregido`: el mecanismo fue reemplazado y tiene regression automatizada.

## Registro inicial

| ID | Estado | Área | Indicio inicial | Validación pendiente |
|---|---|---|---|---|
| S-001 | Confirmado | Estado global | `ChameleonGUIState` invalida `MaterialApp`, themes y páginas por cambios no relacionados | `lib/main.dart:72-105,767-1049`; medir rebuilds y dividir listenables |
| S-002 | Corregido | Polling | Read Card y NTAG usaban callbacks async periódicos sin guard y podían acumular cola | `NonOverlappingPoller` agenda solo tras completion; integrado en ambos flujos y cubierto por `test/non_overlapping_poller_test.dart` |
| S-003 | Confirmado | Build | Hay I/O, preferencias, wakelock, parsing y mutaciones de modelo dentro de builds | `lib/main.dart:769-794,857-874`, `lib/gui/component/mifare/classic.dart:95-108` |
| S-004 | Confirmado | Listas | Saved Cards usa scroll externo + grids no scrollables `shrinkWrap`, construyendo todo | `lib/gui/page/saved_cards.dart:611-726,788-876` |
| S-005 | Confirmado | Persistencia | `getCards/getDictionaries` decodifican JSON completo en cada llamada/build | `lib/sharedprefsprovider.dart:321-358` |
| S-006 | Confirmado | Transporte | Framing, BLE y parsers crean copias/listas/sublistas y hex strings evitables | `lib/bridge/chameleon.dart:179-260,401-411` |
| S-007 | Confirmado | Async | Numerosos flujos hacen `setState` tras awaits sin mounted/generation y siguen tras pop | Slot dialogs, write/read card y hacking pages; ampliar pruebas de cancelación |
| S-008 | Confirmado | Recuperación | Hardnested no tiene límite de tiempo/no-progress; FFI/isolate se detalla en S-048/S-050/S-066 | `lib/helpers/mifare_classic/recovery.dart:1212-1263` |
| S-009 | Confirmado | Reutilización | Polling, carga de dispositivo, parsing y cleanup tienen implementaciones divergentes | Diseñar primitives pequeñas, no un controlador universal |
| S-010 | Probable | Responsive | NavigationRail fijo y columnas no scrollables pueden desbordar en móvil/landscape | `lib/main.dart:884-959`, `lib/gui/page/home.dart:226-566` |
| S-011 | Confirmado | Assets/dependencias | Auditoría completada; resultados detallados en S-068..S-075 y `07-dependency-size-audit.md` | Separar higiene de deps de ahorro AOT medido |
| S-012 | Confirmado | Logging | Interpolación crea hex completo antes del filtro; persistencia reescribe hasta 5000 filas | `lib/bridge/chameleon.dart:401-411`, `lib/sharedprefsprovider.dart:478-487` |

## Primera ronda de auditoría

| ID | Estado | Área | Hallazgo o sospecha | Evidencia/seguimiento |
|---|---|---|---|---|
| S-013 | Corregido | Parser serial | Una trama corrupta dejaba el parser atascado y la longitud signed permitía crecimiento sin límite | Decoder streaming unsigned, cap 4,096 y resync en `lib/bridge/chameleon_frame_decoder.dart`; regressions en `test/chameleon_frame_decoder_test.dart` |
| S-014 | Corregido | Serial desktop | Probes y puertos activos no cerraban/disponían `SerialPort` en todos los paths | Ownership local/transfer explícito, `try/finally`, close+dispose idempotente y `native_serial_lifecycle_test.dart` |
| S-015 | Corregido | Android USB | Input y `usbEventStream` subscriptions no se guardaban/cancelaban al reconectar | Dos subscriptions owned, generation guards, close awaited y reconnect/detach/error tests en `mobile_serial_lifecycle_test.dart` |
| S-016 | Corregido | Lifecycle global | Dispose no invalidaba scan activo, limpiaba callback ni desconectaba connector | Source generation-invalida scans/connect y limpia callback; tests cubren blocked scan success/error, pero falta regression de connect/capability init pendiente |
| S-017 | Corregido | DFU | Decoder SLIP incremental, single-flight, cleanup de setup/write y validación de response | `lib/bridge/dfu.dart`; split y concurrencia en `test/dfu_timeout_test.dart` |
| S-018 | Confirmado | Timeouts | Timeout no incluye espera en cola/open/write total y no cancela Future subyacente | `lib/bridge/chameleon.dart:359-447` |
| S-019 | Corregido | BLE discovery | Scan/connect tienen generation, ownership, deadlines y cancelación del retry loop | `lib/connector/serial_ble.dart`; regressions BLE reliability |
| S-020 | Confirmado | BLE notifications | Poll cada 300 ms vuelve a descargar historial desde índice 0 | `lib/gui/menu/hacking/ble_audit.dart:742-760` |
| S-021 | Confirmado | Retries | DFU discovery, algunos magic writes y hardnested tienen retries/loops demasiado amplios | `lib/helpers/flash.dart:154-194`; write gen1/2/3; recovery hardnested |
| S-022 | Confirmado | Parsing | Wrappers core indexan respuestas sin schema/status uniforme; errores viran a `RangeError` | `lib/bridge/chameleon.dart:523-700,1578-1776` |
| S-023 | Confirmado | Bytes/GC | Receive buffer boxed, `sublist`+copy y conversiones BLE duplican payloads | `lib/bridge/chameleon.dart:179-260`; `lib/connector/serial_ble.dart:222-275` |
| S-024 | Confirmado | Biblioteca | Saved Cards/Dictionaries hacen decode, allocate, serialize y layout O(total) | `lib/gui/page/saved_cards.dart`, `lib/sharedprefsprovider.dart:321-358` |
| S-025 | Confirmado | Dump editor | Un keystroke reconstruye dumps y ejecuta hasta ~122 layouts de texto por editor visible | `lib/gui/menu/pages/dump_editor.dart:125-134,934-1017,1416-1525` |
| S-026 | Confirmado | EMV traces | Transit/EMV construyen y hex-formatean records aun en secciones colapsadas | `lib/gui/menu/hacking/transit_gate_test.dart:555-825,1153`; EMV reader/transaction |
| S-027 | Confirmado | FutureBuilder | Home, Slot Manager/Changer/Edit crean futures de hardware desde `build` | `lib/gui/page/home.dart:33-50,198`; `lib/gui/page/slot_manager.dart:47-63,348` |
| S-028 | Confirmado | Build correctness | `SlotExportMenu` y preparación MFC pueden llamar `setState` durante build | `lib/gui/menu/dialogs/slot/export.dart:219-233`; `lib/helpers/mifare_classic/write/base.dart:183-215` |
| S-029 | Confirmado | Data sync | Compara dos serializaciones JSON completas y resuelve snapshots grandes en UI/build | `lib/gui/page/data_sync.dart:112-118,665-705` |
| S-030 | Confirmado | Controllers | Muchos controllers, incluido camera, no se disponen o se recrean en build | `lib/gui/component/qrcode_scanner.dart:14-16`; dialogs y `lib/gui/component/hex_editor.dart` |
| S-031 | Confirmado | QR | Slider regenera payload denso y QR completo en cada tick | `lib/gui/menu/dialogs/qr/settings.dart:26-35,78-140` |
| S-032 | Probable | LF waveform | Pintado/decoding escala con todas las muestras y se repite al hacer zoom/edit | `lib/gui/menu/tools/lf_sniffing.dart:763-890,1381-1561` |
| S-033 | Confirmado | Changelog | `TapGestureRecognizer` creados en build no tienen dispose ownership | `lib/gui/menu/pages/changelog_view.dart:205-283` |
| S-034 | Confirmado | Widget state | `ToggleButtonsWrapper` no sincroniza props tras `initState` | `lib/gui/component/toggle_buttons.dart:18-31` |
| S-035 | Confirmado | Navegación | Switch top-level destruye páginas y repite inicialización/I/O al volver | `lib/main.dart:739-798,953-958` |
| S-036 | Confirmado | Error builders | Varios `FutureBuilder.error` desconectan hardware durante construcción | Home, slot manager/changer/settings/edit y about dialog |
| S-037 | Probable | Energía | Auto-scan hace BLE lowLatency 2 s cada ~5 s sin app lifecycle policy | `lib/main.dart:367-486`, `lib/connector/serial_ble.dart:76-121` |
| S-038 | Probable | Wakelock | Root y MIFARE compiten como owners y llaman platform channel desde build | `lib/main.dart:800-802`, `lib/gui/component/mifare/classic.dart:103-108` |
| S-039 | Confirmado | Search | `WhereIterable.length` + `elementAt(index)` produce recorridos O(n²) | card list y dictionary search delegates |
| S-040 | Confirmado | Persistent logs | Cada línea reescribe toda la lista de hasta 5000 logs en SharedPreferences | `lib/sharedprefsprovider.dart:478-487` |
| S-041 | Probable | Layout | Rail fijo, Home/Flashing no scrollables y Connect 2 columnas fallan en constraints pequeñas | Validar golden 320x568, landscape y textScale 2 |
| S-042 | Confirmado | Startup | `runApp` espera SharedPreferences; tradeoff consistente pero retrasa first frame | `lib/main.dart:46-51` |
| S-043 | Probable | Emulation monitor | Poll MFC 4K usa ~20 comandos cada 3 s y solo cancela tras snapshot completo | `lib/main.dart:197-340` |
| S-044 | Confirmado | Rail metrics | Medición retrasada de NavigationRail no tiene consumidores y fuerza rebuild global | `lib/helpers/general.dart:426-433` |
| S-045 | Corregido | BLE framing | Write NUS fragmenta en ATT MTU-3 y espera cada chunk en orden | `lib/connector/serial_ble.dart`; `test/serial_ble_reliability_test.dart` |
| S-046 | Corregido | Timeout recovery | Timeout con frame parcial o write incierto invalida/disconnect; response timeout completo queda quarantined por command ID | `lib/bridge/chameleon.dart`; queue regressions |
| S-047 | Sospecha | Stream reentry | Listeners async BLE/USB/HCE pueden reentrar porque Stream no await callback | Probar bursts y ordenar explícitamente donde aplique |

## Segunda ronda: almacenamiento, recovery, reuse y dependencias

| ID | Estado | Área | Hallazgo o sospecha | Evidencia/seguimiento |
|---|---|---|---|---|
| S-048 | Corregido | Native recovery | Inputs/outputs/temporales tienen allocator-matched cleanup y `recovery_free`; smoke/leaks locales pasan | `src/recovery.c`, `src/recovery.h`, `lib/recovery/recovery.dart`; ASan/Instruments multiplataforma pendiente |
| S-049 | Corregido | Static encrypted | Seeds se indexan con sets preservando orden/duplicados en O(n+m) | `lib/helpers/mifare_classic/general.dart`; fixture recovery pasa |
| S-050 | Corregido | Isolates | Filtros usan `Isolate.run` con error propagation/timeout; worker native tiene generation, exit/error y restart solo tras exit | `lib/helpers/mifare_classic/general.dart`, `lib/recovery/recovery.dart` |
| S-051 | Confirmado | Sync encoding | Snapshots hacen múltiples map->JSON->model y buffers completos en UI isolate | `lib/helpers/data_sync.dart:31-161,445-676` |
| S-052 | Confirmado | Sync bytes | `_readUint32` copia el bundle completo para leer cuatro bytes, dos veces | `lib/helpers/data_sync_transport.dart:585-587` |
| S-053 | Confirmado | Sync merge | Dedup/fingerprints/conflicts son cuadráticos y `plan.resolve()` corre en build | `lib/helpers/data_sync.dart:178-184,592-668`; `lib/gui/page/data_sync.dart:665-718` |
| S-054 | Confirmado | Durabilidad | Apply/rollback usa setters no awaited; fallos async no entran al catch y permiten persistencia parcial | `lib/helpers/data_sync_storage.dart:41-78`, `lib/sharedprefsprovider.dart:260-318,333-405,519-550` |
| S-055 | Corregido | Firmware import | ZIP se lee una vez, directorio/entradas/CRC/output se validan con caps y decode/hash corre off-isolate | `lib/helpers/flash.dart`; `test/firmware_archive_test.dart` |
| S-056 | Probable | Legacy import | Settings ya usa allowlist/version/cap/migración; cards/dictionaries/downloads aún necesitan caps previos a materializar | `lib/sharedprefsprovider.dart`; imports de Saved Cards pendientes |
| S-057 | Corregido | QR import | Header/chunks tienen digest, índice, count y byte caps; finish exige SHA exacto | `lib/gui/menu/dialogs/qr/import.dart`, export en Settings |
| S-058 | Confirmado | Sync semantics | Merge union no representa deletes y mezcla metadata de diccionarios silenciosamente | `lib/helpers/data_sync.dart:274-363,592-629` |
| S-059 | Confirmado | Domain models | Modelos mutables aliasan listas/bytes; writers pueden mutar `CardSave` guardado | `lib/sharedprefsprovider.dart:15-186`, MFC write helpers |
| S-060 | Confirmado | Algorithms | Hay 3 CRC32, byte equality, ASCII/value-block y scheme tables duplicados/divergentes | `lib/helpers/general.dart`, `lib/helpers/emv_trace.dart`, `lib/bridge/chameleon_keyboard.dart`, dump analyzers |
| S-061 | Confirmado | Validation | Regex Ultralight contiene `\$` literal y TLV EMV permisivo trunca longitudes declaradas | `lib/helpers/mifare_ultralight/dump_analyzer.dart:30-36`, `lib/helpers/emv.dart:100-140` |
| S-062 | Confirmado | Write helpers | Controllers sin disposal contract y preparación Classic puede repetir scans desde build | write helper bases |
| S-063 | Sospecha | Crypto UI | PBKDF2 600k + AES parecen pure Dart en UI isolate | `lib/helpers/data_sync_transport.dart:21-129`; perf low-end Android |
| S-064 | Sospecha | EMV trace memory | Metadata firmware puede provocar fetch/retención excesiva sin caps host totales | `lib/helpers/emv_trace.dart:388-875` |
| S-065 | Confirmado | Temp files | Export data sync crea `.cusync` únicos y no los elimina | `lib/gui/page/data_sync.dart:266-280` |
| S-066 | Corregido | Recovery worker | Single active request, deadlines por algoritmo, fail-pending, onError/onExit y restart posterior a exit | `lib/recovery/recovery.dart`; fault injection nativo pendiente |
| S-067 | Confirmado | HTTP | Helpers GitHub/OpenCollective carecen de client reuse, timeout/status/size uniforme | `lib/helpers/github.dart`, `lib/helpers/open_collective.dart` |
| S-068 | Confirmado | Dependencies | `async`/`convert` no se importan; `ffigen` está en runtime; `cross_file` directo no se importa y seguiría transitive | Higiene de manifest, no ahorro AOT asumido |
| S-069 | Confirmado | Assets | `assets/logo.png` se empaqueta sin uso runtime (~97 KB comprimido) | Mantener como launcher source, quitar solo de `flutter.assets` |
| S-070 | Confirmado | Source assets | 19 imágenes no referenciadas ocupan ~73.7 MB de repo, no binario | Revisar si son design masters antes de borrar |
| S-071 | Confirmado | Binary size | Mobile Scanner bundled añade ~4.95 MB native + modelos para QR | Medir release con `--analyze-size`; evaluar ML Kit unbundled |
| S-072 | Confirmado | Startup permissions | Auto-scan Android solicita location+scan+advertise+connect al inicio | `lib/connector/serial_android.dart:55-79`; revisar advertise/location por SDK |
| S-073 | Probable | Binary size | `path_provider` se usa una vez pero arrastra JNI/native; retirar requiere otro export temp probado | `lib/gui/page/data_sync.dart:266` |
| S-074 | Confirmado | Build reproducibility | Dos git deps siguen ramas mutables y file_picker es beta | Pin commits/tags tras pruebas |
| S-075 | Confirmado | SDK contract | `sdk: >3.0.0` promete un mínimo inferior al toolchain efectivo Dart 3.11 | Ajustar constraint a compatibilidad realmente probada |
| S-076 | Confirmado | Reuse bridge | Validación/status/scalar codecs del bridge están duplicados e inconsistentes | Alto valor de consolidación; ejecutar en Fase 5 tras fixes P0/P1 |
| S-077 | Confirmado | Reuse slots | Upload/snapshot de cards aparece en Slot Manager, Reader Keys, Export y Edit | Extraer `SlotEmulationService` por codecs de familia |
| S-078 | Confirmado | Reuse repository | Card/dictionary read-modify-write se repite y omite campos en algunas copias | Repositorios + `copyWith`, preservando formato primero |
| S-079 | Confirmado | Reuse forms | Create/Edit/Slot repiten identity/anticollision/UL/HID fields | Compartir secciones, no submit/hardware side effects |
| S-080 | Confirmado | Reuse EMV | Reader/Transaction duplican projection/export/UI de traces | Compartir projection/presentation; no adquisición state-changing |
| S-081 | Confirmado | Reuse recovery UI | Autopwn/darkside/nested/backdoor repiten bootstrap/cancel/results | Controller de shell, algoritmos separados |
| S-082 | Confirmado | Reuse hex | Normalización/parse hex tiene políticas locales inconsistentes | `HexCodec` con policy explícita por dominio |
| S-083 | Confirmado | Reuse exports | FilePicker/timestamp/UTF8/feedback se repite en múltiples features | `FileExportService`, construcción domain-specific afuera |
| S-084 | Confirmado | Reuse BLE AD | Cuatro walkers AD duplicados; display tolera truncation, config debe ser strict | Walker común con mode explícito |
| S-085 | Confirmado | Reuse responsive | Action/field/key-value rows tienen varias implementaciones | Extraer primitives pequeñas, evitar mega-widget con flags |
| S-086 | Confirmado | Reuse composite serial | Android/macOS duplican forwarding/state precedence | Base `CompositeSerial`, permisos/selección en subclasses |
| S-087 | Corregido | Nested correctness | `keyCount` conserva el candidato final y realloc no trunca success | `src/recovery.c`; oracle exacto independiente pendiente |
| S-088 | Corregido | Slot upload | Planner sparse conserva índices y gaps con chunks contiguos bounded | `helpers/mifare_classic/slot_transfer.dart`; `test/slot_transfer_test.dart` |
| S-089 | Corregido | Slot export | Planner bounded cubre Mini/1K/2K/4K sin remainder duplicado | `slot_transfer.dart`, Slot Export y regressions |
| S-090 | Corregido | DFU selection | Discovery tiene deadline, exige un único device compatible, conecta el seleccionado y valida bool/state | `lib/helpers/flash.dart` |
| S-091 | Corregido | Sync merge integrity | Defaults eligen lado disponible; override ausente falla y UI no ofrece esa opción | `lib/helpers/data_sync.dart`; unequal-length regression |
| S-092 | Corregido | DFU progress | `maxSize`, MTU, response lengths y chunk progress se validan antes de loops | `lib/bridge/dfu.dart`; DFU regressions |
| S-093 | Confirmado | Import/download caps | Cards/dictionaries y downloads materializan inputs arbitrarios antes de validar | `lib/gui/page/saved_cards.dart:127-169,750-779`, `lib/gui/menu/tools/dictionary_download.dart:37-57`, `lib/helpers/github.dart:85-142` |
| S-094 | Corregido | Emulation monitor | Command 1050 v2 congela owner por transporte/slot/type/generation/revision; UID random no cambia identidad, SAVE tiene deadline coordinado y baseline/notificación esperan historia durable con retry pending | `lib/main.dart`, `lib/bridge/chameleon.dart`, firmware `app_cmd.c`/`tag_emulation.c`, fake-serial + host C |
| S-095 | Corregido | Connector replacement | Cambio demo/real hace teardown, revierte preferencia ante fallo e invalida scan/slot queue stale | `lib/main.dart`, `lib/gui/page/settings.dart`; lifecycle regression |
| S-096 | Corregido | Authorized Relay | El servicio payment y últimas AID quedan persistentes; Arm adquiere backend e inicia HCE sin Prepare/review popup; enable nativo es atómico, ligado a Activity resumed, AID exactas y sesión ISO-DEP viva | Dart relay + Kotlin service/MainActivity/upgrade receiver; HIL payment pendiente |
| S-097 | Corregido | Command boundary | Write failure/partial timeout invalidan stream; mutators core/T55/slot/settings validan status y payload | `lib/bridge/chameleon.dart`; queue regressions |
| S-098 | Corregido | Data Sync durability | WAL staged, revision/hash CAS, vista committed atómica, intents diferidos durables y 2PC v2 recuperan COMMIT/ABORT tras restart | provider, storage, transport, UI y fault injection; la durabilidad física máxima sigue limitada por SharedPreferences |
| S-099 | Corregido en source | Release gates | Analyzer/tests/build, native ASan/UBSan, semver/ancestry y attestation HIL exacta por SHA/evidence | workflows correctos localmente; activar mediante commit/merge, environments y CI protegido |

## Regla de actualización

Cada nueva observación recibe un ID. Al validarla se conserva el ID, cambia el
estado y se añade evidencia `archivo:línea`, mecanismo, impacto y enlace al
informe. Los falsos positivos no se borran: se marcan `Descartado` para evitar
repetir la investigación.

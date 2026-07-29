# Mapa de reutilización y duplicación

## Principio

Se prioriza reutilizar **contratos estables y funciones puras**, no crear una
abstracción universal. Dos flujos visualmente parecidos pueden tener estados,
timeouts, seguridad o efectos RF distintos.

Las etiquetas P0/P1/P2 de este documento expresan **valor de consolidación**, no
orden de ejecución. Los bugs de parser, recovery, slot chunks y lifecycle se
corrigen antes de extraer estas abstracciones, siguiendo `05-optimization-roadmap.md`.

## Clusters prioritarios

### R-01 Response contracts y codecs del bridge (P0)

**Duplicado:** `_requireBleSuccess`, `_requireKeyboardResponse`, validaciones
manuales en `chameleon.dart`, getters/setters escalares, CardData y write-mode.

**Ubicaciones:**

- `lib/bridge/chameleon.dart:502-535,797-867,1215-1527,1647-2145`
- `lib/bridge/chameleon_ble.dart:18-40`
- `lib/bridge/chameleon_keyboard.dart:225-259,374-393`

**Extraer:** `CommandResponseSpec`, `requireResponse`, decoders u8/u16/u32/bool,
`_parseCardData`, `_getBoolCommand`, `_setBoolCommand`.

**Riesgo:** statuses correctos no son uniformes. Cada command mantiene spec
explícita; RF `00`, system `68` y secure BLE `66` no se globalizan.

### R-02 SlotEmulationService y codecs por familia (P0)

**Duplicado:** load CardSave -> slot en Slot Manager y Reader Keys; dispatch HF/LF
en Slot Edit; inverse snapshot en Slot Export.

**Ubicaciones:**

- `lib/gui/page/slot_manager.dart:81-316`
- `lib/gui/page/reader_keys.dart:198-243`
- `lib/gui/menu/dialogs/slot/export.dart:36-177`
- `lib/gui/menu/dialogs/slot/edit.dart:79-270`

**Extraer:** `loadCard(slot, card, progress)`, `snapshotCard(slot, frequency)`,
chunker contiguo probado y codecs Classic/Ultralight/LF separados.

**Beneficio:** una secuencia mode/enable/activate/type/default/data/name/save y
elimina drift como `lastSend` frente a `chunkStart`.

### R-03 Polling no solapable (P0)

**Duplicado:** loops BLE bridge, Read Card, Reader Keys, NTAG, BLE Stress/Audit,
scan principal y emulation monitor.

**Estado:** `NonOverlappingPoller` ya fue extraído y adoptado por Read Card HF/LF
y NTAG. Quedan migraciones de los demás loops después de characterization.

**Mantener/completar dos primitives:**

1. `pollUntil<T>` finito con deadline/interval/terminal/error predicates.
2. `NonOverlappingPoller` periódico con auto-schedule, generation y no-overlap.

**Riesgo:** no imponer un timeout result único. Algunas operaciones lanzan,
otras devuelven estado y notifications requieren cleanup.

### R-04 CardRepository y DictionaryRepository (P0)

**Duplicado:** get-list/mutate/set-list en create/edit/view/read/recovery/export.

**Extraer:** list/find/add/upsert/remove/duplicate/mergeKeysByValue, immutable
snapshots y revisiones. Añadir deep `copyWith` a modelos.

**Migración segura:** primero preservar JSON exacto y semántica detached-list;
después cambiar backend de SharedPreferences.

### R-05 Card identity form sections (P1)

**Duplicado:** Create/Edit/Slot Edit repiten name/color/tag/UID/SAK/ATQA/ATS,
UL version/signature/counters y HID fields.

**Extraer:** `TagTypeField`, `AntiCollisionFields`, `UltralightMetadataFields`,
`HidProxFields`, `ColorNameField` y form model.

**No compartir:** submit, creación de dump o hardware save.

### R-06 EMV projection/presentation/export (P1)

**Duplicado:** EMV Reader y Transaction agrupan apps, formatean metadata,
renderizan TLV/APDU/RF y exportan evidencia.

**Extraer:** `EmvTraceProjection`, `EmvTraceView`, `EmvTlvView`,
`CopyableFieldRow`, `EmvReportExporter`.

**No compartir:** adquisición. Transaction puede ejecutar GPO/GENERATE AC y debe
mantener confirmaciones más fuertes.

### R-07 MIFARE recovery shell (P1)

**Duplicado:** Autopwn, Darkside, Nested, Backdoor y Autopwn+ repiten scan,
validation, cancellation, errors, progress, results y export.

**Extraer:** `MifareRecoveryRunController.bootstrap`, `RecoveryResultPanel` y
`_dumpAndTransition` interno común.

**No compartir:** algoritmo, required input ni fallbacks.

### R-08 CaptureDialogScaffold HF/LF (P1)

**Duplicado:** capability load, busy/error, unsupported status, export/copy y
responsive header en HF/LF sniff.

**Extraer:** `CaptureDialogScaffold`, `CapabilityBanner`, `CaptureHeader`,
`ExportCopyActions`, `InlineOperationStatus`.

**No compartir:** nonce recovery HF, waveform/Manchester LF.

### R-09 BLE operation lifecycle (P1)

**Duplicado:** communicator snapshot, capabilities, generation, guarded setState,
busy/error y cleanup en Audit/Stress/Identity/Advertising Lab.

**Extraer:** mixin/objeto pequeño `BleDeviceOperationState` con `isCurrent`, token
y cleanup; `supportsAllSync` y body de conexión.

**No crear:** un controller BLE universal que mezcle scan/GATT/flood/identity/AD.

### R-10 HexCodec con policies (P1)

**Duplicado:** `hexToBytes`, limpieza de separators, validators, APDU/MIFARE/BLE
formatters y parsers locales.

**Policy explícita:** separators, empty, exact/min/max bytes, output case/separator.
BLE address, raw AD, APDU y dumps no comparten grammar global.

### R-11 FileExportService y CardSave factories (P1)

**Duplicado:** FilePicker, UTF-8, pretty JSON, timestamp, filenames y feedback.

**Extraer:** `saveBytes`, `saveUtf8`, `savePrettyJson`, sanitizer y timestamp;
`CardSave.fromHfInfo/fromLfCard` para metadata común.

**Límite:** construcción de formato permanece en el domain owner.

### R-12 BLE AD walker (P1)

**Duplicado:** name, summary, details y strict validator recorren AD structures.

**Extraer:** `walkBleAdStructures(data, strict|tolerant)` que entrega offset,
type, declared length, value y truncation. Display tolera paquetes truncados;
config los rechaza.

### R-13 LF codecs y T55xx payload/verification (P1)

**Duplicado:** readers, setters, payloads y write-delay-read-compare por familia.

**Extraer:** `LfTagCodec<T>` con scan/get/set/write IDs, sizes, parser y capacidad
de verificación; builder T55xx común.

**Riesgo:** Electra, Idteck y protocolos sin readback mantienen propiedades
explícitas, no branches ocultos.

### R-14 SearchDelegate mechanics (P1)

**Duplicado:** buildResults/buildSuggestions y tres delegates. Hoy hay paths no-op
y `WhereIterable.elementAt` O(n²).

**Extraer primero:** `_buildMatches` local por delegate, materializando una vez.
Después evaluar `FilteredSearchDelegate<T>` typed con row/action callbacks.

### R-15 DeviceRequestState<T> (P2)

**Duplicado:** FutureBuilder shells en Home, Slot Manager/Changer/Edit/Settings.

**Extraer:** owner de future fuera de build con reload, generation y communicator
identity. Un simple wrapper de FutureBuilder no corrige ownership.

### R-16 Dump byte utilities (P2)

**Exact clones:** ASCII, spaced hex, value-block validation, nibble diff y XOR
popcount entre Classic/UL analyzer/highlighter, Compare y Dump Editor.

**Extraer:** pure `DumpBytes` utilities con tests. Semántica de highlighting
Classic/UL permanece separada.

### R-17 Responsive components neutrales (P2)

**Duplicado:** BLE responsive groups, MIFARE button groups, sniff headers,
key/value/copy rows de BLE/EMV/Card.

**Extraer:** `ResponsiveFieldGroup`, `ResponsiveActionGroup`,
`ResponsiveKeyValueRow`, `CopyableValueRow` en `lib/gui/component`.

**Diseño:** components separados; evitar uno con docenas de flags.

### R-18 Dialog primitives (P2)

**Duplicado:** color pickers, prompts de nombre y row HF/LF de slot settings.

**Extraer:** `showColorPickerDialog`, `promptForName`,
`SlotFrequencySettingsRow`. No crear un universal AlertDialog builder.

### R-19 CompositeSerial (P2)

**Duplicado:** Android/macOS forwardean state, callbacks, writes y disconnect con
85-95% de similitud.

**Extraer:** base de multiplexado primary/secondary; permisos Android y reglas de
selección quedan en subclasses.

### R-20 Card import finalizer (P2)

**Duplicado:** PM3/Flipper/MCT convierten blocks, infieren tag y construyen CardSave.

**Extraer:** `ImportedHfDump` + `buildImportedCard`; parsers fuente separados.

## Casos que no deben unificarse

| Casos parecidos | Por qué deben permanecer separados |
|---|---|
| DFU y Chameleon communicator | SLIP, statuses, response lifecycle y invalidación son distintos |
| Relay lab y Authorized Relay platform | El segundo valida tokens/deadlines/APDUs con fail-closed |
| MIFARE Gen1/Gen2/Gen3 writers | Timing, unlock y key semantics son protocol-specific |
| `createBlock0FromSave` y `mfClassicGenerateFirstBlock` | SAK/filler behavior no coincide |
| EMV reader y transaction acquisition | Una es read-oriented y otra state-changing |
| HF y LF sniff decoders | Framing, recovery, waveform y decode son dominios distintos |
| BLE AD strict/tolerant | Config debe rechazar; presentation debe sobrevivir truncation |
| Classic y Ultralight state machines | Blocks/keys frente a pages/protection |
| Serial USB/native/BLE físicos | Ownership y stream lifecycle difieren |
| Todos los dialogs/busy flows | Un framework universal escondería cleanup domain-specific |

## Secuencia de extracción

1. Añadir characterization tests: response status/length, slot transcripts,
   polling fake-time, exports, search actions y EMV snapshots.
2. Extraer pure utilities: hex, dump bytes, CRC, enum decoding, CardData parser.
3. Normalizar response handling de bridge, empezando BLE/keyboard.
4. Introducir poll primitives y migrar loops simples antes de BLE Audit complejo.
5. Introducir repositories conservando serialization exacta.
6. Extraer SlotEmulationService por familia.
7. Extraer form/dialog/responsive/search components.
8. Extraer recovery shell y dump transition.
9. Extraer EMV projection, sniff shell y BLE operation lifecycle.
10. Terminar con CompositeSerial e import finalizer.

Cada extracción debe reducir call sites duplicados sin alterar command sequence,
status accepted, persistence timing ni cancelación.

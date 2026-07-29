# Métricas estáticas del codebase

Fecha de captura: 2026-07-16. Estas métricas son una baseline para comparar
refactors; no sustituyen profiling en dispositivo.

## Alcance

- 216 archivos Dart físicos en `lib/`, `test/` y `tool/` si se incluyen
  localizaciones y otros archivos generados.
- 191 archivos Dart mantenidos analizados en el índice de firmas.
- De ellos, 148 archivos y 2,495 declaraciones son código productivo bajo `lib/`;
  los 43 restantes y 226 declaraciones corresponden a tests/herramientas.
- Dentro de `lib/`, 152 archivos son visibles por `rg --files`: los 148
  mantenidos, protobuf y FFI; las localizaciones generadas están ignoradas por
  Git. Repo-wide, ese perfil ve 195 archivos Dart.
- 63,838 líneas en los 152 archivos visibles de `lib/`; 62,517 pertenecen al
  perfil mantenido.
- 2,721 declaraciones mantenidas en todo el repositorio.
- 23,762 declaraciones adicionales pertenecen solo a localización generada y
  no deben usarse para priorizar arquitectura.

## Indicadores globales

| Indicador textual | Conteo | Interpretación |
|---|---:|---|
| `context.watch`/listeners equivalentes | 38 | Muchos listeners dependen del notifier global completo |
| Constructores `Timer` | 13 | Deben auditarse ownership, overlap y lifecycle |
| `FutureBuilder` | 10 | Varios crean I/O de dispositivo desde `build` |
| `StreamBuilder` | 0 | Streams se consumen con listeners/controladores manuales |
| `shrinkWrap: true` | 6 | Solo 2 grids de bibliotecas son hotspots claros |
| `TextEditingController(` | 120 | Ownership/disposal inconsistente en formularios y dialogs |
| `setState(` | 568 | Señal de estado muy distribuido; no es un problema por sí sola |
| `changesMade`/`notifyListeners` | 99 | El canal global no expresa qué cambió |

## Archivos más grandes

| Líneas | Archivo | Riesgo dominante |
|---:|---|---|
| 2,903 | `lib/sharedprefsprovider.dart` | Persistencia general más WAL/CAS/2PC y vista committed de Data Sync |
| 2,765 | `lib/bridge/chameleon.dart` | Queue, codecs y cientos de wrappers mezclados; framing ya está separado |
| 1,881 | `lib/gui/menu/hacking/authorized_relay_lab.dart` | State machine sensible; buena cancelación pero gran superficie |
| 1,571 | `lib/gui/menu/tools/lf_sniffing.dart` | Decode/waveform/UI en una unidad |
| 1,526 | `lib/gui/menu/pages/dump_editor.dart` | Rebuild y text layout por keystroke |
| 1,524 | `lib/gui/menu/hacking/ble_audit.dart` | Polling, logs, scan y GATT UI combinados |
| 1,415 | `lib/helpers/authorized_relay.dart` | Protocol policy/timing/validation |
| 1,351 | `lib/main.dart` | MaterialApp, scanning, monitor atómico y estado global |
| 1,296 | `lib/helpers/mifare_classic/recovery.dart` | Recovery, loops, estado y hardware |
| 1,270 | `lib/helpers/data_sync_transport.dart` | Peer v2 cifrado, 2PC y recovery decisions |
| 1,206 | `lib/gui/menu/hacking/transit_gate_test.dart` | Captura, trace y presentación eager |
| 1,197 | `lib/gui/page/saved_cards.dart` | Bibliotecas, grids, search y merges |
| 1,139 | `lib/gui/page/read_card.dart` | Scan HF/LF, poller y múltiples readers |
| 1,103 | `lib/gui/menu/tools/hf_sniffing.dart` | Capture/recovery/export/UI |
| 1,005 | `lib/gui/page/data_sync.dart` | Host/client, merge, recovery y export |
| 938 | `lib/helpers/emv_trace.dart` | Parsing e integridad retained trace |
| 931 | `lib/gui/menu/dialogs/slot/edit.dart` | I/O, forms y protocolos HF/LF |
| 930 | `lib/gui/menu/hacking/keyboard_payload.dart` | Compiler/upload/status/UI |
| 849 | `lib/helpers/definitions.dart` | Enums/modelos wire compartidos |
| 846 | `lib/gui/page/reader_keys.dart` | Capture, polling, recovery y export |
| 840 | `lib/gui/menu/hacking/ble_stress.dart` | Operaciones y status polling |
| 795 | `lib/gui/menu/hacking/emv_transaction.dart` | Acquisition state-changing + trace UI |

El tamaño no implica lentitud automáticamente. Los hotspots reales combinan
tamaño con rebuild frecuente, loops, parsing, I/O o colecciones grandes.

## Declaraciones por subsistema

| Subsistema | Archivos | Declaraciones |
|---|---:|---:|
| `bridge` | 7 | 304 |
| `connector` | 7 | 96 |
| `gui/component` | 19 | 78 |
| `gui/menu/dialogs` | 14 | 82 |
| `gui/menu/hacking` | 29 | 407 |
| `gui/menu/pages` | 4 | 66 |
| `gui/menu/tools` | 6 | 117 |
| `gui/page` | 14 | 164 |
| `helpers/ble` | 3 | 30 |
| `helpers/mifare_classic` | 12 | 183 |
| `helpers/mifare_ultralight` | 4 | 43 |
| helpers raíz | 25 | 657 |
| `helpers/t55xx` | 1 | 13 |
| wrapper recovery | 1 | 24 |
| `main.dart` + preferencias | 2 | 229 |

## Concentración de API

- `bridge/chameleon.dart`: 190 declaraciones.
- `sharedprefsprovider.dart`: 175.
- `helpers/authorized_relay.dart`: 101.
- `helpers/emv_trace.dart`: 58.
- `helpers/mifare_classic/autopwn_plus.dart`: 49.
- `dump_editor.dart`: 46.
- `main.dart`: 54.
- Data sync completo, incluyendo UI: 189.
- Authorized relay completo, incluyendo bridge/UI: 167.

Estas concentraciones son candidatas a separación por responsabilidad, no a
fragmentación arbitraria. En state machines de seguridad, extraer pure helpers y
presentation suele ser más seguro que repartir el estado entre muchos objetos.

## Tamaño y assets

- Directorio `assets/`: aproximadamente 71.6 MiB (`du`: 73,364 KiB).
- Runner iOS release inspeccionado: aproximadamente 32.0 MiB (`du`: 32,784 KiB).
- 19 imágenes no referenciadas suman aproximadamente 73.7 MB de fuente, pero no
  están empaquetadas y no afectan el binario.
- `assets/logo.png` sí está empaquetado sin uso runtime: unos 97 KB comprimidos.
- Mobile Scanner bundled aporta 4,946,720 bytes en el artifact debug arm64
  stripped `build/app/intermediates/stripped_native_libs/debug/`
  `stripDebugDebugSymbols/out/lib/arm64-v8a/libbarhopper_v3.so`, más modelos y
  CameraX/ML Kit. Medir release antes de atribuir tamaño final.
- Recovery native aporta aproximadamente 1.0 MB por ABI.

El APK debug de 216 MB no sirve como baseline de release. Las comparaciones deben
usar `--release --analyze-size` y una única ABI Android.

## Baselines de medición recomendadas

1. Startup con auto-scan on/off y permisos preconcedidos/denegados.
2. 4K slot upload: notifications, rebuilds y command count.
3. Saved Cards con 100/500/1000 cards y diccionario de 100k keys.
4. Dump Editor 4K: frame time y `TextPainter.layout` por keystroke.
5. EMV trace al límite: widgets/strings antes de expandir secciones.
6. Recovery static-encrypted: CPU, native RSS e isolate count por sector.
7. 20 ciclos Android USB connect/disconnect y un detach.
8. BLE notification stream de 10/100/500 registros.
9. Data sync de 1/8/16 MiB: event-loop gaps y peak RSS.
10. Energy Log/Battery Historian durante un minuto desconectado.

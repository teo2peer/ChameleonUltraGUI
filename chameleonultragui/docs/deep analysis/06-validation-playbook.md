# Playbook de validación y profiling

## Builds correctos

Usar profile/release para rendimiento; debug sirve para assertions/rebuilds, no
para cifras de frame o tamaño.

```bash
flutter analyze
LIBRECOVERY_PATH="$PWD/build/macos/recovery_test_arm64/librecovery.dylib" flutter test
flutter run --profile --trace-startup
flutter build apk --release --target-platform=android-arm64 --analyze-size
flutter build ipa --release --analyze-size
flutter build macos --release --analyze-size
git diff --check
```

## Matriz de escenarios

| Escenario | Dataset/fallo | Medir | Criterio funcional |
|---|---|---|---|
| Startup | auto-scan on/off, permisos granted/denied | first frame, device list, radio | No cold-start HTTP |
| Discovery | 1 puerto ajeno + BLE | FD count, duty, rebuilds | Sin port/listener leak |
| USB reconnect | 20 ciclos + detach | callbacks, heap | Un detach -> un cleanup |
| Framing | SOF/LRC/length corruptos | buffer, recovery | Próxima trama válida funciona |
| Command queue | queue/write/response bloqueados | deadline real, depth | Timeout end-to-end acotado |
| DFU | SLIP split/coalesced/short, maxSize 0, MTU 0..4 | completion/progress | Single-flight, decoder correcto, fail fast |
| DFU selection | BLE/wired en órdenes distintos | port/transport elegido | Conecta exactamente `toFlash` y valida bool |
| Slot upload | MFC 4K/NTAG216 | commands, rebuilds, frames | Datos/offsets exactos |
| Slot sparse/Mini | gaps Classic y 20 bloques | chunk plan/ranges | Sin desplazamiento, overread ni overflow |
| Saved Cards | 100/500/1000 cards | open/edit alloc/frame | UI lazy y estable |
| Dictionary | 10k/100k keys | open/search/export | Sin O(n²) ni monolithic text |
| Dump Editor | MFC 4K, typing continuo | layouts/builds/frame | Sin rebuild de sectores intactos |
| EMV trace | max APDU/RF records | pre-expand widgets/RSS | Collapsed sections lazy |
| BLE notify | 10/100/500 records | cumulative bytes | Cursor incremental |
| Read Card poll | command delay 3 s | concurrency/backlog | Máximo 1 in-flight |
| Emulation monitor | MFC Mini/1K/2K/4K | commands/p95 latency | Cancel entre chunks |
| Static encrypted | fixtures actuales | CPU/RSS/result | Output idéntico, O(n+m) |
| Recovery repeats | 50 por algoritmo | native RSS | Plateau sin leak |
| Recovery worker | exit/error/hang inyectado | pending requests | Todos completan con error y worker se recupera |
| Nested candidates | fixture completo | set/count exacto | No se descarta último candidato |
| Hardnested | nonce repetido/no-progress | time/list size | Abort bounded/cancellable |
| Data sync | 1/8/16 MiB + unequal blocks | gaps/RSS/indexes | UI responsive, AEAD intacto, sin compactar |
| Data sync commit | fallo por setter/write | persisted snapshot | Estado previo exacto o commit completo |
| Data sync export | 50 shares + restart | temp directory size | Cleanup/sweep bounded |
| QR import | bad digest/order/count | memory/result | Fail closed antes de JSON apply |
| Firmware ZIP | huge/bomb/duplicates | frame/RSS | Rechazo por límites |
| Cards/download | oversized/schema/status inválido | bytes antes de rechazo | Cap antes de materializar |
| Responsive | 320x568, landscape, text 2x | overflows/goldens | Navigation/forms utilizables |

## Instrumentación Flutter

- DevTools Performance y CPU profiler.
- Track widget builds/repaints.
- `debugPrintRebuildDirtyWidgets` solo en debug.
- `Timeline.timeSync` para repository decode, parser, dump layout y sync.
- Allocation profile con filtros `Uint8List`, `List<int>`, `String`, controllers.
- `FrameTiming` para percentiles, no solo promedio.

## Plataforma

### Android

- Perfetto/Android Studio CPU + Memory.
- Battery Historian para scan duty/background.
- `adb shell am start -W` para startup.
- FD/listeners durante USB reconnect.

### iOS/macOS

- Instruments App Launch, Time Profiler, Allocations, Leaks y Energy Log.
- ASan/LeakSanitizer para recovery dylib en tests/build de diagnóstico.
- Link map o `--analyze-size` para atribución Swift/BLE.

## Pruebas implementadas y pendientes antes de optimizar

1. Streaming decoder corrupt/split/coalesce. **Implementada.**
2. DFU SLIP streaming, concurrencia, discovery deadline y progress bounds.
   **Implementada en source y tests focalizados; HIL pendiente.**
3. Connector subscription/port ownership. **Implementada:** probes, USB/BLE,
   native reader generations y connector reset; faltan stress/HIL.
4. Non-overlap poller. **Implementada con timers reales de 1-2 ms;** fake-time
   sigue pendiente.
5. Stable Future/device request counts. **Slot Manager corregido; resto pendiente.**
6. Card/dictionary persistence fixtures y repository mutations.
7. Slot command transcript por tag family.
8. Static filter output characterization. **Complejidad corregida; benchmark pendiente.**
9. Native allocation ownership smoke test. **Implementado local y gateado en CI
   con ASan/UBSan; Linux añade los tests Dart FFI.**
10. Recovery worker exit/error y nested candidate count. **Lifecycle source
    corregido; fault injection/oracle exacto pendientes.**
11. Slot sparse upload y Mini bounded export. **Implementada.**
12. Data sync atomic fault injection, 2PC/restart, intents concurrentes, unequal
    blocks, deletion y cleanup. **Implementada.**
13. QR/settings/ZIP caps y schemas. **Implementados.** Cards/dictionaries/downloads
    siguen pendientes.
14. Large-list lazy widget tests.
15. Route pop durante cada operación larga.
16. Narrow-screen/large-text goldens.

## Gate de release HIL

Tras ejecutar BLE/USB/DFU/HCE sobre Ultra y Lite físicos, conservar el informe y
configurar el environment protegido `hardware-validated` con:

- `HIL_APPROVED_SHA`: SHA Git completo de 40 hex del commit probado.
- `HIL_EVIDENCE_SHA256`: SHA-256 de 64 hex del informe retenido.

Los workflows de tag comparan `HIL_APPROVED_SHA` con `GITHUB_SHA` y fallan si
alguna evidencia falta. Una aprobación de otro commit no es reutilizable.

## Formato para resultados

Cada optimización debe guardar:

```text
Commit/PR:
Plataforma/device:
Build mode:
Dataset:
Métrica antes:
Métrica después:
Resultado funcional/tests:
Tradeoffs:
```

Sin dataset/build mode, una cifra de rendimiento no es comparable.

# Auditoría de dependencias, startup y tamaño

## Limpiezas confirmadas y seguras

| Elemento | Evidencia | Acción |
|---|---|---|
| `async` | Sin imports `package:async` | Retirar direct dependency |
| `convert` | Sin imports `package:convert` | Retirar direct dependency |
| `ffigen` | Solo generación, sin runtime import | Mover a `dev_dependencies` |
| `cross_file` | Sin import directo; llega vía `share_plus` | Retirar direct dependency |
| `assets/logo.png` runtime | Sin referencia Dart; solo source launcher | Quitar de `flutter.assets`, conservar archivo |

Estas acciones deben hacerse en un PR separado con `pub get`, full tests y
builds de todas las plataformas soportadas. Retirar `async`/`convert`, mover
`ffigen` y retirar el direct `cross_file` son principalmente **higiene del
manifest**: al no importarse en runtime, no se asume ahorro AOT. `cross_file`
seguiría llegando transitivamente por `share_plus`.

## Assets fuente

Hay 19 imágenes no referenciadas ni empaquetadas que suman aproximadamente
73.7 MB. No afectan el binario. Antes de borrarlas, confirmar si son masters de
diseño. Conservar:

- Cuatro WebP usados por la app.
- `background-color.png`, `foreground-color.png`, `foreground-bw.png`,
  `logo-color-desktop.png` y `logo.png` para launcher generation.
- Licencias de fuentes hasta revisar attribution.

## Principales contribuyentes opcionales

### Mobile Scanner

- Artifact debug arm64 stripped
  `build/app/intermediates/stripped_native_libs/debug/stripDebugDebugSymbols/`
  `out/lib/arm64-v8a/libbarhopper_v3.so`: 4,946,720 bytes. Repetir en release.
- Modelos barcode: aproximadamente 0.88 MB.
- Añade CameraX/ML Kit/Kotlin/Dex.
- Solo se usa para QR.

Opción unbundled reduce install pero requiere descarga de modelo/Play Services y
rompe la garantía offline inicial. Es una decisión de producto, no una limpieza
automática.

### Native recovery

Alrededor de 1.0 MB por ABI/plataforma. Es requisito para darkside,
nested/hardnested y MFKey. No retirar mientras esas funciones existan.

### Path provider

Se usa una vez para export temporal de data sync. En Android arrastra JNI/native
y en Darwin Objective-C support. Solo se puede retirar después de probar un
export alternativo que funcione en todas las plataformas.

### Localizaciones

24 locales, aproximadamente 2.1 MB de Dart generado y 836 KB ARB fuente. Todos
son alcanzables. Medir AOT real antes de reducir idiomas.

## Startup

1. `SharedPreferences.getInstance` bloquea antes de `runApp`.
2. Auto-scan default true empieza desde el primer build.
3. BLE lowLatency dura 2 s y se repite después de un intervalo de 3 s.
4. Android solicita location, scan, advertise y connect durante ese flujo.
5. Home puede repetir un batch de comandos si rebuild recrea su Future.
6. Root build repite wakelock/sidebar/theme work.

No hay HTTP automático confirmado en cold startup. Network se dispara al abrir
About/Changelog, descargar firmware/diccionarios o iniciar sync.

## HTTP

GitHub/OpenCollective/download helpers carecen de una política uniforme de:

- `http.Client` reutilizable.
- Timeout explícito.
- Validación de status.
- Límite de bytes streaming.
- Cache/ETag.

About espera OpenCollective, GitHub y package info secuencialmente. Ejecutar
independientes en paralelo y cachear por lifetime del dialog.

## Plugins

No se encontraron registrations huérfanos: todos proceden de deps directas o
transitivas. Algunos plugins se registran en plataformas donde la feature se
deshabilita (por ejemplo Mobile Scanner en macOS), pero eliminar ese registro
requiere un plugin/fork con declaración de plataforma distinta.

## Riesgos de build reproducible

- `flutter_libserialport` sigue `main` y `usb_serial` una rama fix mutable; lock
  fija commits actuales, pero actualizar resolución puede cambiar código.
- `file_picker` es beta y está muy extendido en la app.
- RxAndroidBle tiene override de versión; no quitar sin BLE regression suite.
- Constraint SDK `>3.0.0` declara un mínimo demasiado bajo respecto al
  lock/toolchain efectivo (Dart 3.11); no es una contradicción formal, pero sí
  una promesa de compatibilidad engañosa.
- APK debug de ~216 MB no representa release; contiene engines/ABIs/kernel/debug.

## Comandos de medición

```bash
flutter build apk --release --target-platform=android-arm64 --analyze-size
flutter build ipa --release --analyze-size
flutter build macos --release --analyze-size
flutter run --profile --trace-startup
```

Comparar una modificación cada vez y guardar el JSON de analyze-size. No atribuir
tamaño Swift/BLE sin link map o build comparativo.

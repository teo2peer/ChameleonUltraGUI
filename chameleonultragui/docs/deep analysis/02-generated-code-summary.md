# Resumen de firmas generadas excluidas

El índice principal contiene todas las declaraciones ejecutables **mantenidas a
mano** de `lib/`, `test/` y `tool/`: funciones, métodos, constructores y
accessors. No pretende catalogar clases, fields, enum constants o typedefs. El
código generado se separa porque repetir decenas de miles de getters de idiomas
no ayuda a encontrar reutilización y cambia al ejecutar generators.

| Partición | Archivos | Funciones | Métodos | Constructores | Getters | Setters | Total |
|---|---:|---:|---:|---:|---:|---:|---:|
| `lib/generated/i18n/` | 21 | 1 | 3,472 | 26 | 20,263 | 0 | 23,762 |
| `lib/protobuf/` | 3 | 0 | 88 | 33 | 30 | 21 | 172 |
| `lib/recovery/bindings.dart` | 1 | 0 | 7 | 2 | 0 | 0 | 9 |

## Política

- Localización: regenerar desde ARB; no refactorizar getters manualmente.
- Protobuf: regenerar desde `.proto`; no editar las clases resultantes.
- FFI: regenerar con ffigen al cambiar headers.
- El generador de firmas recorre archivos físicos, no solo Git, pero omite estas
  rutas del catálogo mantenido.

## Perfiles de conteo

| Perfil | Archivos | Declaraciones |
|---|---:|---:|
| Todo Dart físico del repositorio | 216 | 26,664 |
| Mantenido + FFI generado | 192 | 2,730 |
| Mantenido recomendado | 191 | 2,721 |

Las métricas arquitectónicas deben usar el último perfil. Los conteos completos
solo sirven para verificar que generators no perdieron API.

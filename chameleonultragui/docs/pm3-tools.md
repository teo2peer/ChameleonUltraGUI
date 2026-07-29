# PM3 Tools compatibility catalog

`PM3 Tools` is an additive menu. It does not replace or fork existing Chameleon workflows.

The catalog was audited against `RfidResearchGroup/proxmark3` commit
`8b65feaba36ecc6d58d8aeef96cdc7c5a04381bc`. The canonical `doc/commands.md` dump contains 990 command rows. Excluding 96 help rows and deduplicating its repeated `lf awid brute` row produces 893 unique executable commands across the client, data, HF, LF, hardware, flash/SPIFFS, trace, and scripting surfaces.

The generated snapshot preserves each upstream command, short description, and offline flag. Regenerate it with:

```sh
dart run tool/generate_pm3_command_inventory.dart <proxmark3/doc/commands.md>
```

## Compatibility states

- `Mapped`: opens an existing Chameleon page or dialog. Existing authorization, connection, capability, and cleanup gates remain authoritative.
- `Host port pending`: the host algorithm or protocol workflow may be adapted, but no bounded implementation is connected yet. The entry is disabled.
- `Unsupported`: the operation depends on PM3-specific FPGA, ADC, antenna, external flash, SPIFFS, LCD, FPC USART, radio protocol, or timing behavior. The entry is disabled.

Catalog visibility never implies device support or authorization. The menu accepts no arbitrary PM3 command strings and adds no firmware command IDs.

At the audited commit, Flutter exposes 45 mapped commands, 230 disabled host-port candidates, and 618 disabled PM3-specific commands. Expo keeps all execution disabled until its corresponding feature screens are implemented.

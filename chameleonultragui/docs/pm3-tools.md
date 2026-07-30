# PM3-compatible workflows

`PM3 Tools` is an operational compatibility layer, not a Proxmark3 command
console. Navigation follows this structure:

`Ethical Hacking > PM3 Tools > category > tool > dedicated interface`

The upstream inventory was audited against `RfidResearchGroup/proxmark3`
commit `8b65feaba36ecc6d58d8aeef96cdc7c5a04381bc`. Its 893 command names remain in
`lib/helpers/pm3_command_inventory.dart` as an audit snapshot only. They are
not presented as Chameleon features.

## Operational categories

| Category | Implemented workflows | Device primitives |
| --- | --- | --- |
| ISO14443-A | card inspection, persistent select, raw frames, APDU, sniff | 2000, 2010, 2016, 2020, 2100-2101, 2200-2201, 6004 |
| MIFARE Classic | info/dump, Autopwn, Darkside, Nested, Static Nested, Hardnested, value blocks | 2001-2015, 2018 |
| Low frequency | protocol search, ADC window, sniff, ioProx codec, T55xx block write, Jablotron clone | 3000, 3002, 3004, 3009-3010, 3012-3014, 3016, 3019-3020, 3031 |
| Smart cards | EMV scan/transaction, DESFire enumeration, APDU terminal | 6004-6006 |
| Offline analysis | number conversion, XOR, LRC, checksum matrix, NUID, frequency, HF units, Wiegand decode | host implementation |

Every device-backed tool uses the advertised firmware capabilities and the
same USB/BLE command protocol as the rest of the application. Raw operations
use typed, bounded payloads; arbitrary PM3 command strings are not accepted.

The previous catalogue labelled 230 commands as `Host port pending` solely
because Proxmark3 marks them as available without a connected device. That flag
is not a portability guarantee: most depend on PM3 `GraphBuffer` state, trace
files, client preferences, scripting runtimes, or PM3-only capture formats.
This menu exposes only bounded RFID workflows with a direct Chameleon command
or a stateless host implementation.

## Hardware boundaries

Commands remain unavailable when the Chameleon hardware has no corresponding
physical capability. Examples include PM3 FPGA image control, PM3 SPIFFS and
external flash, LCD/FPC USART, antenna tuning/decay measurement, and protocols
that require unsupported analogue front-end or modulation paths such as
ISO14443-B, ISO15693, FeliCa, iCLASS/Picopass, LEGIC, and Hitag.

EM4x05 is intentionally not exposed. Firmware command 3030 currently returns
`STATUS_NOT_IMPLEMENTED` because its framing produced false UIDs and has not
been verified against hardware captures or golden vectors.

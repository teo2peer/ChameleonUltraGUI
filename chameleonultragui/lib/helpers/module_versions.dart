enum ModuleId {
  appShell,
  undercover,
  device,
  library,
  slotManager,
  readCard,
  writeCard,
  tools,
  settings,
  readerKeysCapture,
  ethicalHacking,
  debug,
  dataSync,
  dumpEditor,
  logsViewer,
  compareCards,
  dictionaryDownload,
  emulationHistory,
  pm3Catalog,
  t55xxPasswordCleaner,
  lfSniffing,
  hfSniffing,
  hfContinuousCapture,
  mifareClassicGen4,
  mifareClassicAttacks,
  captureAndSniffing,
  emulationAndMagic,
  protocolDiagnostics,
  bluetoothLab,
  autopwn,
  autopwnPlus,
  autopwnV2,
  mifareClassicNonceHistory,
  dictionaryCheck,
  darkside,
  nested,
  staticNested,
  hardnested,
  backdoorRf08s,
  mfkeyManual,
  ntagPasswordCapture,
  mfkey32,
  valueBlock,
  wiegand,
  emvEmulator,
  keyboardPayload,
  authorizedRelay,
  relayResistance,
  authTrace,
  apduTerminal,
  emvReader,
  emvTransaction,
  transitGate,
  desfireReader,
  bleAudit,
  bleRadioIdentity,
  bleAdvertisingLab,
  bleStressBroadcast,
}

class ModuleRelease {
  final String name;
  final String version;
  final String updatedAt;

  const ModuleRelease({
    required this.name,
    required this.version,
    required this.updatedAt,
  });
}

const _initialReleaseDate = '2026-07-30';

const moduleVersions = <ModuleId, ModuleRelease>{
  ModuleId.appShell: ModuleRelease(
    name: 'App Shell',
    version: '1.1.0',
    updatedAt: '2026-08-02',
  ),
  ModuleId.undercover: ModuleRelease(
    name: 'Undercover',
    version: '1.0.1',
    updatedAt: '2026-08-02',
  ),
  ModuleId.device: ModuleRelease(
    name: 'Device',
    version: '1.1.0',
    updatedAt: '2026-08-02',
  ),
  ModuleId.library: ModuleRelease(
    name: 'Library',
    version: '1.0.0',
    updatedAt: _initialReleaseDate,
  ),
  ModuleId.slotManager: ModuleRelease(
    name: 'Slot Manager',
    version: '1.1.0',
    updatedAt: '2026-08-02',
  ),
  ModuleId.readCard: ModuleRelease(
    name: 'Read Card',
    version: '1.0.0',
    updatedAt: _initialReleaseDate,
  ),
  ModuleId.writeCard: ModuleRelease(
    name: 'Write Card',
    version: '1.0.0',
    updatedAt: _initialReleaseDate,
  ),
  ModuleId.tools: ModuleRelease(
    name: 'Tools',
    version: '1.0.0',
    updatedAt: _initialReleaseDate,
  ),
  ModuleId.settings: ModuleRelease(
    name: 'Settings',
    version: '1.1.0',
    updatedAt: '2026-08-02',
  ),
  ModuleId.readerKeysCapture: ModuleRelease(
    name: 'Reader Keys Capture',
    version: '1.0.0',
    updatedAt: _initialReleaseDate,
  ),
  ModuleId.ethicalHacking: ModuleRelease(
    name: 'Ethical Hacking',
    version: '1.1.0',
    updatedAt: '2026-08-02',
  ),
  ModuleId.debug: ModuleRelease(
    name: 'Debug',
    version: '1.0.0',
    updatedAt: _initialReleaseDate,
  ),
  ModuleId.dataSync: ModuleRelease(
    name: 'Data Sync',
    version: '1.2.0',
    updatedAt: '2026-08-02',
  ),
  ModuleId.dumpEditor: ModuleRelease(
    name: 'Dump Editor',
    version: '1.0.0',
    updatedAt: _initialReleaseDate,
  ),
  ModuleId.logsViewer: ModuleRelease(
    name: 'Logs Viewer',
    version: '1.0.0',
    updatedAt: _initialReleaseDate,
  ),
  ModuleId.compareCards: ModuleRelease(
    name: 'Compare Cards',
    version: '1.0.0',
    updatedAt: _initialReleaseDate,
  ),
  ModuleId.dictionaryDownload: ModuleRelease(
    name: 'Dictionary Download',
    version: '1.0.0',
    updatedAt: _initialReleaseDate,
  ),
  ModuleId.emulationHistory: ModuleRelease(
    name: 'Emulation History',
    version: '1.0.0',
    updatedAt: _initialReleaseDate,
  ),
  ModuleId.pm3Catalog: ModuleRelease(
    name: 'PM3 Tools',
    version: '1.0.0',
    updatedAt: _initialReleaseDate,
  ),
  ModuleId.t55xxPasswordCleaner: ModuleRelease(
    name: 'T55xx Password Cleaner',
    version: '1.0.0',
    updatedAt: _initialReleaseDate,
  ),
  ModuleId.lfSniffing: ModuleRelease(
    name: 'LF Sniffing',
    version: '1.0.0',
    updatedAt: _initialReleaseDate,
  ),
  ModuleId.hfSniffing: ModuleRelease(
    name: 'HF Sniffing',
    version: '1.1.0',
    updatedAt: '2026-08-02',
  ),
  ModuleId.hfContinuousCapture: ModuleRelease(
    name: 'Continuous HF Capture',
    version: '1.2.0',
    updatedAt: '2026-08-02',
  ),
  ModuleId.mifareClassicGen4: ModuleRelease(
    name: 'MIFARE Classic Gen4',
    version: '1.0.0',
    updatedAt: _initialReleaseDate,
  ),
  ModuleId.mifareClassicAttacks: ModuleRelease(
    name: 'MIFARE Classic Attacks',
    version: '1.1.0',
    updatedAt: '2026-08-02',
  ),
  ModuleId.captureAndSniffing: ModuleRelease(
    name: 'Capture & Sniffing',
    version: '1.1.0',
    updatedAt: '2026-08-02',
  ),
  ModuleId.emulationAndMagic: ModuleRelease(
    name: 'Emulation & Magic',
    version: '1.0.0',
    updatedAt: _initialReleaseDate,
  ),
  ModuleId.protocolDiagnostics: ModuleRelease(
    name: 'Protocol Diagnostics',
    version: '1.0.0',
    updatedAt: _initialReleaseDate,
  ),
  ModuleId.bluetoothLab: ModuleRelease(
    name: 'Bluetooth Lab',
    version: '1.0.0',
    updatedAt: _initialReleaseDate,
  ),
  ModuleId.autopwn: ModuleRelease(
    name: 'Autopwn',
    version: '1.2.0',
    updatedAt: '2026-08-02',
  ),
  ModuleId.autopwnPlus: ModuleRelease(
    name: 'Autopwn Plus',
    version: '1.1.0',
    updatedAt: '2026-08-02',
  ),
  ModuleId.autopwnV2: ModuleRelease(
    name: 'Autopwn v2',
    version: '1.1.0',
    updatedAt: '2026-08-02',
  ),
  ModuleId.mifareClassicNonceHistory: ModuleRelease(
    name: 'MIFARE Classic Nonce History',
    version: '1.0.0',
    updatedAt: _initialReleaseDate,
  ),
  ModuleId.dictionaryCheck: ModuleRelease(
    name: 'Dictionary Check',
    version: '1.1.0',
    updatedAt: '2026-08-02',
  ),
  ModuleId.darkside: ModuleRelease(
    name: 'Darkside',
    version: '1.0.0',
    updatedAt: _initialReleaseDate,
  ),
  ModuleId.nested: ModuleRelease(
    name: 'Nested',
    version: '1.0.0',
    updatedAt: _initialReleaseDate,
  ),
  ModuleId.staticNested: ModuleRelease(
    name: 'Static Nested',
    version: '1.0.0',
    updatedAt: _initialReleaseDate,
  ),
  ModuleId.hardnested: ModuleRelease(
    name: 'Hardnested',
    version: '1.0.0',
    updatedAt: _initialReleaseDate,
  ),
  ModuleId.backdoorRf08s: ModuleRelease(
    name: 'RF08S Backdoor',
    version: '1.0.0',
    updatedAt: _initialReleaseDate,
  ),
  ModuleId.mfkeyManual: ModuleRelease(
    name: 'MFKey Manual',
    version: '1.0.0',
    updatedAt: _initialReleaseDate,
  ),
  ModuleId.ntagPasswordCapture: ModuleRelease(
    name: 'NTAG Password Capture',
    version: '1.0.0',
    updatedAt: _initialReleaseDate,
  ),
  ModuleId.mfkey32: ModuleRelease(
    name: 'MFKey32',
    version: '1.0.0',
    updatedAt: _initialReleaseDate,
  ),
  ModuleId.valueBlock: ModuleRelease(
    name: 'Value Block Tool',
    version: '1.0.0',
    updatedAt: _initialReleaseDate,
  ),
  ModuleId.wiegand: ModuleRelease(
    name: 'Wiegand Decoder',
    version: '1.0.0',
    updatedAt: _initialReleaseDate,
  ),
  ModuleId.emvEmulator: ModuleRelease(
    name: 'EMV Emulator',
    version: '1.0.0',
    updatedAt: _initialReleaseDate,
  ),
  ModuleId.keyboardPayload: ModuleRelease(
    name: 'Keyboard Payload',
    version: '1.0.0',
    updatedAt: _initialReleaseDate,
  ),
  ModuleId.authorizedRelay: ModuleRelease(
    name: 'Authorized Relay',
    version: '1.0.0',
    updatedAt: _initialReleaseDate,
  ),
  ModuleId.relayResistance: ModuleRelease(
    name: 'Relay Resistance Lab',
    version: '1.0.0',
    updatedAt: _initialReleaseDate,
  ),
  ModuleId.authTrace: ModuleRelease(
    name: 'Authentication Trace',
    version: '1.0.0',
    updatedAt: _initialReleaseDate,
  ),
  ModuleId.apduTerminal: ModuleRelease(
    name: 'APDU Terminal',
    version: '1.0.0',
    updatedAt: _initialReleaseDate,
  ),
  ModuleId.emvReader: ModuleRelease(
    name: 'EMV Reader',
    version: '1.0.0',
    updatedAt: _initialReleaseDate,
  ),
  ModuleId.emvTransaction: ModuleRelease(
    name: 'Purchase Simulation',
    version: '1.0.0',
    updatedAt: _initialReleaseDate,
  ),
  ModuleId.transitGate: ModuleRelease(
    name: 'Transit Gate Lab',
    version: '1.0.0',
    updatedAt: _initialReleaseDate,
  ),
  ModuleId.desfireReader: ModuleRelease(
    name: 'DESFire Reader',
    version: '1.0.0',
    updatedAt: _initialReleaseDate,
  ),
  ModuleId.bleAudit: ModuleRelease(
    name: 'BLE Audit',
    version: '1.0.0',
    updatedAt: _initialReleaseDate,
  ),
  ModuleId.bleRadioIdentity: ModuleRelease(
    name: 'Radio & Identity',
    version: '1.0.0',
    updatedAt: _initialReleaseDate,
  ),
  ModuleId.bleAdvertisingLab: ModuleRelease(
    name: 'Advertising Lab',
    version: '1.0.0',
    updatedAt: _initialReleaseDate,
  ),
  ModuleId.bleStressBroadcast: ModuleRelease(
    name: 'Stress & Broadcast',
    version: '1.0.0',
    updatedAt: _initialReleaseDate,
  ),
};

ModuleRelease moduleReleaseFor(ModuleId moduleId) => moduleVersions[moduleId]!;

enum ModuleId {
  appShell,
  device,
  library,
  slotManager,
  reader,
  writer,
  tools,
  settings,
  readerKeys,
  ethicalHacking,
  debug,
  pm3Catalog,
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

const moduleVersions = <ModuleId, ModuleRelease>{
  ModuleId.appShell: ModuleRelease(
    name: 'App Shell',
    version: '1.0.0',
    updatedAt: '2026-07-30',
  ),
  ModuleId.device: ModuleRelease(
    name: 'Device',
    version: '1.0.0',
    updatedAt: '2026-07-30',
  ),
  ModuleId.library: ModuleRelease(
    name: 'Library',
    version: '1.0.0',
    updatedAt: '2026-07-30',
  ),
  ModuleId.slotManager: ModuleRelease(
    name: 'Slot Manager',
    version: '1.0.0',
    updatedAt: '2026-07-30',
  ),
  ModuleId.reader: ModuleRelease(
    name: 'Reader',
    version: '1.0.0',
    updatedAt: '2026-07-30',
  ),
  ModuleId.writer: ModuleRelease(
    name: 'Writer',
    version: '1.0.0',
    updatedAt: '2026-07-30',
  ),
  ModuleId.tools: ModuleRelease(
    name: 'Tools',
    version: '1.0.0',
    updatedAt: '2026-07-30',
  ),
  ModuleId.settings: ModuleRelease(
    name: 'Settings',
    version: '1.0.0',
    updatedAt: '2026-07-30',
  ),
  ModuleId.readerKeys: ModuleRelease(
    name: 'Reader Keys',
    version: '1.0.0',
    updatedAt: '2026-07-30',
  ),
  ModuleId.ethicalHacking: ModuleRelease(
    name: 'Ethical Hacking',
    version: '1.0.0',
    updatedAt: '2026-07-30',
  ),
  ModuleId.debug: ModuleRelease(
    name: 'Debug',
    version: '1.0.0',
    updatedAt: '2026-07-30',
  ),
  ModuleId.pm3Catalog: ModuleRelease(
    name: 'PM3 Catalog',
    version: '1.0.0',
    updatedAt: '2026-07-30',
  ),
};

ModuleRelease moduleReleaseFor(ModuleId moduleId) => moduleVersions[moduleId]!;

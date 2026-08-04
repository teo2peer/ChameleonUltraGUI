# Project Instructions

## Feature Versioning

- Every function or feature that is created or modified must update the version of its owning module in `chameleonultragui/lib/helpers/module_versions.dart` in the same change.
- Register every new user-facing function or feature with its own `ModuleId` and `ModuleRelease` when it is independently exposed in the UI.
- Update `updatedAt` together with the version and keep `chameleonultragui/test/module_version_footer_test.dart` synchronized.
- A function or feature change is incomplete while its module version is stale.

## Configuration Export

- Whenever a setting, configuration option, or function that introduces, uses, or persists configuration is created or modified, update the configuration exporter and importer in the same change.
- Keep `SharedPreferencesProvider.dumpSettingsToJson()` and `SharedPreferencesProvider.restoreSettingsFromJson()` synchronized, including their allowlists, schema version, migrations, validation, and tests.
- Export every safe, portable configuration value required to reproduce the function's behavior. Never export secrets, credentials, device captures, logs, card data, nonce history, or other sensitive runtime data.
- A setting or configurable function is incomplete until export and restore round-trip tests cover it.

# IMPORTANT
NEVER USE WORKTREES USE DIRECTLY THE FOLDER
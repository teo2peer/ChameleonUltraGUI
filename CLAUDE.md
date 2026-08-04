@AGENTS.md

# Versioning And Configuration Export

- Every function or feature created or modified must update the version of its owning module in `chameleonultragui/lib/helpers/module_versions.dart` in the same change.
- Every setting or function that introduces, uses, or persists configuration must update both `SharedPreferencesProvider.dumpSettingsToJson()` and `SharedPreferencesProvider.restoreSettingsFromJson()`, including schema, migration, validation, and round-trip tests.
- Do not consider the change complete while its module version or safe configuration export/import coverage is stale.

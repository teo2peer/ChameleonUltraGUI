# Índice de firmas mantenidas

Generado por `tool/generate_deep_analysis_signatures.dart`.
Incluye `lib/`, `test/` y `tool/`: funciones top-level, métodos,
constructores, getters y
setters explícitos. Excluye closures/local functions y código
generado de localización, protobuf y FFI.

- Archivos: 191
- Declaraciones: 2721
- Regenerar:
  `dart run tool/generate_deep_analysis_signatures.dart`

## `lib/bridge/authorized_relay_platform.dart`

| Línea | Tipo | Owner | Firma | Descripción |
|---:|---|---|---|---|
| 6 | constructor | AuthorizedRelayEvent | `const AuthorizedRelayEvent({ required this.type, required this.armToken, this.id, this.apdu, this.receivedUs, this.expiresAtUs, this.reason, })` | Construye AuthorizedRelayEvent. |
| 24 | método | AuthorizedRelayEvent | `bool isPendingAt(int monotonicUs)` | Operación `isPendingAt`. |
| 31 | factory | AuthorizedRelayEvent | `factory AuthorizedRelayEvent.fromMap(Map<Object?, Object?> value)` | Construye AuthorizedRelayEvent. |
| 83 | función | - | `int? _exactInteger(Object? value)` | Función `_exactInteger`. |
| 90 | constructor | AuthorizedRelayReadiness | `const AuthorizedRelayReadiness({ required this.hceSupported, required this.nfcEnabled, required this.deviceLocked, required this.isDefaultPaymentService, required this.registeredAids, })` | Construye AuthorizedRelayReadiness. |
| 104 | getter | AuthorizedRelayReadiness | `bool get platformReady` | Obtiene `platformReady`. |
| 106 | factory | AuthorizedRelayReadiness | `factory AuthorizedRelayReadiness.fromMap(Map<Object?, Object?> value)` | Construye AuthorizedRelayReadiness. |
| 121 | constructor | AuthorizedRelayArmToken | `const AuthorizedRelayArmToken({ required this.armToken, required this.nativeMonotonicUs, })` | Construye AuthorizedRelayArmToken. |
| 129 | factory | AuthorizedRelayArmToken | `factory AuthorizedRelayArmToken.fromMap(Map<Object?, Object?> value)` | Construye AuthorizedRelayArmToken. |
| 161 | método | AuthorizedRelayPlatform | `Future<AuthorizedRelayArmToken> allocateArmToken()` | Operación `allocateArmToken`. |
| 173 | getter | AuthorizedRelayPlatform | `Stream<AuthorizedRelayEvent> get events` | Obtiene `events`. |
| 175 | método | AuthorizedRelayPlatform | `Future<AuthorizedRelayReadiness> getReadiness()` | Operación `getReadiness`. |
| 195 | método | AuthorizedRelayPlatform | `Future<void> registerAids(Iterable<String> aids)` | Operación `registerAids`. |
| 208 | método | AuthorizedRelayPlatform | `Future<void> authorizeAndEnable( int armToken, { required Iterable<String> aids, int deadlineMs = 1000, })` | Autoriza y arma HCE atómicamente. |
| 248 | método | AuthorizedRelayPlatform | `Future<void> setEnabled(bool enabled, {int? armToken})` | Desarma HCE con token. |
| 268 | método | AuthorizedRelayPlatform | `Future<bool> respond(int armToken, int id, Uint8List response)` | Operación `respond`. |
| 286 | método | AuthorizedRelayPlatform | `Future<bool> isPending(int armToken, int id)` | Operación `isPending`. |
| 300 | método | AuthorizedRelayPlatform | `Future<void> openPaymentSettings()` | Operación `openPaymentSettings`. |
## `lib/bridge/chameleon.dart`

| Línea | Tipo | Owner | Firma | Descripción |
|---:|---|---|---|---|
| 22 | función | - | `String _chameleonStatusDescription(int status)` | Función `_chameleonStatusDescription`. |
| 43 | constructor | ChameleonCommandException | `const ChameleonCommandException(this.command, this.status)` | Construye ChameleonCommandException. |
| 45 | método | ChameleonCommandException | `@override String toString()` | Operación `toString`. |
| 54 | constructor | ChameleonSecureBleLinkException | `const ChameleonSecureBleLinkException(ChameleonCommand command) : super(command, 0x66)` | Construye ChameleonSecureBleLinkException. |
| 57 | método | ChameleonSecureBleLinkException | `@override String toString()` | Operación `toString`. |
| 64 | constructor | IsoDepReaderSessionExchangeException | `const IsoDepReaderSessionExchangeException( int status, { this.isoDepError, this.rfStatus, this.wtxCount, }) : super(ChameleonCommand.hf14a4ReaderSessionExchange, status)` | Construye IsoDepReaderSessionExchangeException. |
| 75 | getter | IsoDepReaderSessionExchangeException | `bool get hasDiagnostics` | Obtiene `hasDiagnostics`. |
| 78 | getter | IsoDepReaderSessionExchangeException | `bool get firmwareSessionClosed` | Obtiene `firmwareSessionClosed`. |
| 81 | getter | IsoDepReaderSessionExchangeException | `String get isoDepErrorDescription` | Obtiene `isoDepErrorDescription`. |
| 93 | método | IsoDepReaderSessionExchangeException | `@override String toString()` | Operación `toString`. |
| 105 | constructor | IsoDepReaderSessionStartMetadataException | `const IsoDepReaderSessionStartMetadataException({ required this.command, required this.formatError, required this.sessionId, required this.cleanupConfirmed, this.cleanupError, })` | Construye IsoDepReaderSessionStartMetadataException. |
| 119 | getter | IsoDepReaderSessionStartMetadataException | `bool get sessionStateUncertain` | Obtiene `sessionStateUncertain`. |
| 121 | método | IsoDepReaderSessionStartMetadataException | `@override String toString()` | Operación `toString`. |
| 141 | constructor | ChameleonUnsupportedCommandException | `const ChameleonUnsupportedCommandException(this.command)` | Construye ChameleonUnsupportedCommandException. |
| 143 | método | ChameleonUnsupportedCommandException | `@override String toString()` | Operación `toString`. |
| 152 | constructor | ChameleonResponseTimeoutException | `const ChameleonResponseTimeoutException(this.command, this.timeout)` | Construye ChameleonResponseTimeoutException. |
| 154 | método | ChameleonResponseTimeoutException | `@override String toString()` | Operación `toString`. |
| 162 | constructor | ChameleonCommandResponseUncertainException | `const ChameleonCommandResponseUncertainException(this.command)` | Construye ChameleonCommandResponseUncertainException. |
| 164 | método | ChameleonCommandResponseUncertainException | `@override String toString()` | Operación `toString`. |
| 172 | constructor | ChameleonCommunicatorClosedException | `const ChameleonCommunicatorClosedException([this.cause])` | Construye ChameleonCommunicatorClosedException. |
| 174 | método | ChameleonCommunicatorClosedException | `@override String toString()` | Operación `toString`. |
| 186 | constructor | MifareClassicActiveSlotSnapshot | `const MifareClassicActiveSlotSnapshot({ required this.slot, required this.tagType, required this.ownerGeneration, required this.revision, })` | Construye MifareClassicActiveSlotSnapshot. |
| 217 | constructor | ChameleonCommunicator | `ChameleonCommunicator( this.log, { AbstractSerial? port, this.writeTimeout = const Duration(seconds: 5), this.snapshotSaveTimeout = activeSlotSnapshotSaveTimeout, })` | Construye ChameleonCommunicator. |
| 228 | método | ChameleonCommunicator | `dynamic open(AbstractSerial port)` | Operación `open`. |
| 232 | método | ChameleonCommunicator | `Uint8List makeDataFrameBytes( ChameleonCommand cmd, int status, Uint8List? data, )` | Operación `makeDataFrameBytes`. |
| 238 | método | ChameleonCommunicator | `Future<void> onSerialMessage(List<int> message)` | Operación `onSerialMessage`. |
| 262 | método | ChameleonCommunicator | `void _dispatchResponse(ChameleonMessage message)` | Operación `_dispatchResponse`. |
| 278 | getter | ChameleonCommunicator | `Set<int>? get cachedDeviceCapabilities` | Obtiene `cachedDeviceCapabilities`. |
| 283 | getter | ChameleonCommunicator | `bool get usesBleTransport` | Obtiene `usesBleTransport`. |
| 286 | método | ChameleonCommunicator | `bool? supportsCommandSync(ChameleonCommand command)` | Operación `supportsCommandSync`. |
| 295 | método | ChameleonCommunicator | `Future<bool?> supportsCommand(ChameleonCommand command)` | Operación `supportsCommand`. |
| 300 | método | ChameleonCommunicator | `Future<void> initializeCapabilities()` | Operación `initializeCapabilities`. |
| 304 | método | ChameleonCommunicator | `Future<void> _initializeCapabilities()` | Operación `_initializeCapabilities`. |
| 357 | método | ChameleonCommunicator | `Future<ChameleonMessage?> sendCmd( ChameleonCommand cmd, { Uint8List? data, Duration timeout = const Duration(seconds: 5), bool skipReceive = false, bool firstRun = false, })` | Operación `sendCmd`. |
| 376 | método | ChameleonCommunicator | `Future<ChameleonMessage> _sendChecked( ChameleonCommand cmd, { Uint8List? data, Duration timeout = const Duration(seconds: 5), Set<int> allowedStatuses = const {chameleonStatusSuccess}, })` | Operación `_sendChecked`. |
| 389 | método | ChameleonCommunicator | `Future<ChameleonMessage?> _enqueueCommand( ChameleonCommand cmd, { Uint8List? data, Duration timeout = const Duration(seconds: 5), bool skipReceive = false, required bool checkCapabilities, })` | Operación `_enqueueCommand`. |
| 423 | método | ChameleonCommunicator | `Future<ChameleonMessage?> _sendCommand( ChameleonCommand cmd, { Uint8List? data, required Duration timeout, required bool skipReceive, })` | Operación `_sendCommand`. |
| 485 | método | ChameleonCommunicator | `Future<void> _writeFrame(AbstractSerial serial, Uint8List frame)` | Operación `_writeFrame`. |
| 501 | método | ChameleonCommunicator | `void _ensureOpen()` | Operación `_ensureOpen`. |
| 507 | método | ChameleonCommunicator | `void dispose([Object? cause])` | Libera recursos de ChameleonCommunicator. |
| 522 | método | ChameleonCommunicator | `Future<void> _invalidateAndDisconnect(Object cause)` | Operación `_invalidateAndDisconnect`. |
| 532 | método | ChameleonCommunicator | `Future<FirmwareVersion> getFirmwareVersion()` | Operación `getFirmwareVersion`. |
| 549 | método | ChameleonCommunicator | `Future<String> getDeviceChipID()` | Operación `getDeviceChipID`. |
| 554 | método | ChameleonCommunicator | `Future<String> getDeviceBLEAddress()` | Operación `getDeviceBLEAddress`. |
| 559 | método | ChameleonCommunicator | `Future<bool> isReaderDeviceMode()` | Operación `isReaderDeviceMode`. |
| 571 | método | ChameleonCommunicator | `Future<void> setReaderDeviceMode(bool readerMode)` | Operación `setReaderDeviceMode`. |
| 582 | método | ChameleonCommunicator | `Future<CardData?> scan14443aTag()` | Operación `scan14443aTag`. |
| 614 | método | ChameleonCommunicator | `Future<bool> detectMf1Support()` | Operación `detectMf1Support`. |
| 621 | método | ChameleonCommunicator | `Future<NTLevel> getMf1NTLevel()` | Operación `getMf1NTLevel`. |
| 635 | método | ChameleonCommunicator | `Future<DarksideResult> checkMf1Darkside()` | Operación `checkMf1Darkside`. |
| 662 | método | ChameleonCommunicator | `Future<NTDistance> getMf1NTDistance( int block, int keyType, Uint8List keyKnown, )` | Operación `getMf1NTDistance`. |
| 680 | método | ChameleonCommunicator | `Future<NestedNonces> getMf1NestedNonces( int block, int keyType, Uint8List knownKey, int targetBlock, int targetKeyType, { NTLevel level = NTLevel.weak, bool slow = false, })` | Operación `getMf1NestedNonces`. |
| 742 | método | ChameleonCommunicator | `Future<Darkside> getMf1Darkside( int targetBlock, int targetKeyType, bool firstRecover, int syncMax, )` | Operación `getMf1Darkside`. |
| 777 | método | ChameleonCommunicator | `Future<(int, NestedNonces, NestedNonces, Uint8List)?> getMf1StaticEncryptedNestedAcquire({ int sectorCount = 16, int startingSector = 0, })` | Operación `getMf1StaticEncryptedNestedAcquire`. |
| 818 | método | ChameleonCommunicator | `Future<bool> mf1Auth(int block, int keyType, Uint8List key)` | Operación `mf1Auth`. |
| 829 | método | ChameleonCommunicator | `Future<Uint8List?> mf1AuthMultipleKeys( int block, int keyType, List<Uint8List> keys, )` | Operación `mf1AuthMultipleKeys`. |
| 848 | método | ChameleonCommunicator | `Future<Uint8List> mf1ReadBlock(int block, int keyType, Uint8List key)` | Operación `mf1ReadBlock`. |
| 860 | método | ChameleonCommunicator | `Future<List<Uint8List>> mf1ReadBlocks( int startBlock, int count, int keyType, Uint8List key, )` | Operación `mf1ReadBlocks`. |
| 888 | método | ChameleonCommunicator | `Future<Map<int, Uint8List>?> mf1CheckKeysOfSectors( Uint8List mask, List<Uint8List> keys, )` | Operación `mf1CheckKeysOfSectors`. |
| 923 | método | ChameleonCommunicator | `Future<bool> mf1WriteBlock( int block, int keyType, Uint8List key, Uint8List data, )` | Operación `mf1WriteBlock`. |
| 938 | método | ChameleonCommunicator | `Future<void> activateSlot(int slot)` | Operación `activateSlot`. |
| 947 | método | ChameleonCommunicator | `Future<void> setSlotType(int slot, TagType type)` | Operación `setSlotType`. |
| 958 | método | ChameleonCommunicator | `Future<void> setDefaultDataToSlot(int slot, TagType type)` | Operación `setDefaultDataToSlot`. |
| 969 | método | ChameleonCommunicator | `Future<void> enableSlot(int slot, TagFrequency frequency, bool status)` | Operación `enableSlot`. |
| 980 | método | ChameleonCommunicator | `Future<bool> isMf1DetectionMode()` | Operación `isMf1DetectionMode`. |
| 992 | método | ChameleonCommunicator | `Future<void> setMf1DetectionStatus(bool status)` | Operación `setMf1DetectionStatus`. |
| 1003 | método | ChameleonCommunicator | `Future<int> getMf1DetectionCount()` | Operación `getMf1DetectionCount`. |
| 1019 | método | ChameleonCommunicator | `Future<void> setMf1RandomUidMode(bool enabled)` | Operación `setMf1RandomUidMode`. |
| 1032 | método | ChameleonCommunicator | `Future<bool> getMf1RandomUidMode()` | Operación `getMf1RandomUidMode`. |
| 1037 | método | ChameleonCommunicator | `Future<void> setMf1ReaderKeysAnim(bool enabled)` | Operación `setMf1ReaderKeysAnim`. |
| 1049 | método | ChameleonCommunicator | `Future<List<DetectionResult>> getMf1DetectionRecords(int count)` | Operación `getMf1DetectionRecords`. |
| 1088 | método | ChameleonCommunicator | `Future<Map<int, Map<int, Map<String, List<DetectionResult>>>>> getMf1DetectionResult(int count)` | Operación `getMf1DetectionResult`. |
| 1115 | método | ChameleonCommunicator | `Future<void> setMf1BlockData(int startBlock, Uint8List blocks)` | Operación `setMf1BlockData`. |
| 1124 | método | ChameleonCommunicator | `Future<void> setMf1AntiCollision(CardData card)` | Operación `setMf1AntiCollision`. |
| 1138 | método | ChameleonCommunicator | `Future<EM410XCard?> readEM410X()` | Operación `readEM410X`. |
| 1148 | método | ChameleonCommunicator | `Future<HIDCard?> readHIDProx()` | Operación `readHIDProx`. |
| 1158 | método | ChameleonCommunicator | `Future<VikingCard?> readViking()` | Operación `readViking`. |
| 1168 | método | ChameleonCommunicator | `Future<PacCard?> readPac()` | Operación `readPac`. |
| 1178 | método | ChameleonCommunicator | `Future<IoProxCard?> readIoProx()` | Operación `readIoProx`. |
| 1188 | método | ChameleonCommunicator | `Future<void> setEM410XEmulatorID(Uint8List uid)` | Operación `setEM410XEmulatorID`. |
| 1195 | método | ChameleonCommunicator | `Future<void> setHIDProxEmulatorID(Uint8List uid)` | Operación `setHIDProxEmulatorID`. |
| 1203 | método | ChameleonCommunicator | `Future<void> setVikingEmulatorID(Uint8List uid)` | Operación `setVikingEmulatorID`. |
| 1211 | método | ChameleonCommunicator | `Future<void> setPacEmulatorID(Uint8List uid)` | Operación `setPacEmulatorID`. |
| 1219 | método | ChameleonCommunicator | `Future<void> setIoProxEmulatorID(Uint8List uid)` | Operación `setIoProxEmulatorID`. |
| 1227 | método | ChameleonCommunicator | `Future<void> setIdteckEmulatorID(Uint8List uid)` | Operación `setIdteckEmulatorID`. |
| 1235 | método | ChameleonCommunicator | `Future<void> _setLfEmulatorId( ChameleonCommand command, Uint8List uid, { int? expectedLength, })` | Operación `_setLfEmulatorId`. |
| 1256 | método | ChameleonCommunicator | `Future<void> writeEM410XtoT55XX( Uint8List uid, Uint8List newKey, List<Uint8List> oldKeys, )` | Operación `writeEM410XtoT55XX`. |
| 1282 | método | ChameleonCommunicator | `Future<void> writeHIDProxToT55XX( Uint8List uid, Uint8List newKey, List<Uint8List> oldKeys, )` | Operación `writeHIDProxToT55XX`. |
| 1295 | método | ChameleonCommunicator | `Future<void> writeVikingToT55XX( Uint8List uid, Uint8List newKey, List<Uint8List> oldKeys, )` | Operación `writeVikingToT55XX`. |
| 1308 | método | ChameleonCommunicator | `Future<void> writePacToT55XX( Uint8List uid, Uint8List newKey, List<Uint8List> oldKeys, )` | Operación `writePacToT55XX`. |
| 1316 | método | ChameleonCommunicator | `Future<void> writeIoProxToT55XX( Uint8List uid, Uint8List newKey, List<Uint8List> oldKeys, )` | Operación `writeIoProxToT55XX`. |
| 1329 | método | ChameleonCommunicator | `Future<void> _writeT55xx( ChameleonCommand command, Uint8List uid, Uint8List newKey, List<Uint8List> oldKeys, )` | Operación `_writeT55xx`. |
| 1359 | método | ChameleonCommunicator | `Future<Uint8List> lfSniff({int timeoutMs = 2000})` | Operación `lfSniff`. |
| 1385 | método | ChameleonCommunicator | `Future<Uint8List> hf14aAuthTrace( int block, int keyType, Uint8List key, { int timeoutMs = 5000, })` | Operación `hf14aAuthTrace`. |
| 1411 | método | ChameleonCommunicator | `Future<Uint8List> hf14a4ReaderApdu(Uint8List apdu)` | Operación `hf14a4ReaderApdu`. |
| 1429 | método | ChameleonCommunicator | `Future<IsoDepReaderSessionInfo> hf14a4ReaderSessionStart()` | Operación `hf14a4ReaderSessionStart`. |
| 1432 | método | ChameleonCommunicator | `Future<IsoDepReaderSessionInfo> hf14a4ReaderSessionStartAppleTransit()` | Operación `hf14a4ReaderSessionStartAppleTransit`. |
| 1437 | método | ChameleonCommunicator | `Future<IsoDepReaderSessionInfo> _hf14a4ReaderSessionStart( ChameleonCommand command, )` | Operación `_hf14a4ReaderSessionStart`. |
| 1506 | método | ChameleonCommunicator | `Future<Uint8List> hf14a4ReaderSessionExchange( int sessionId, Uint8List apdu, )` | Operación `hf14a4ReaderSessionExchange`. |
| 1544 | método | ChameleonCommunicator | `Future<void> hf14a4ReaderSessionStop(int sessionId)` | Operación `hf14a4ReaderSessionStop`. |
| 1570 | método | ChameleonCommunicator | `Future<void> hf14a4ReaderSessionReset(int sessionId)` | Cierra idempotentemente un backend relay tras un exchange incierto. |
| 1571 | método | ChameleonCommunicator | `Future<Uint8List> hf14a4EmvScan({Uint8List? amount})` | Operación `hf14a4EmvScan`. |
| 1601 | método | ChameleonCommunicator | `Future<Uint8List> hf14a4DesfireScan()` | Operación `hf14a4DesfireScan`. |
| 1626 | método | ChameleonCommunicator | `Future<EmvTraceStartResponse> hf14a4EmvTraceStart( EmvTraceRequest request, )` | Operación `hf14a4EmvTraceStart`. |
| 1649 | método | ChameleonCommunicator | `Future<EmvTraceMeta> hf14a4EmvTraceMeta(int scanId)` | Operación `hf14a4EmvTraceMeta`. |
| 1670 | método | ChameleonCommunicator | `Future<EmvTracePage> hf14a4EmvTraceGet( int scanId, int startRecord, { int maxPayload = 4096, })` | Operación `hf14a4EmvTraceGet`. |
| 1700 | método | ChameleonCommunicator | `Future<EmvTraceCapture> hf14a4EmvTrace( EmvTraceRequest request, { int maxPayload = 4096, })` | Operación `hf14a4EmvTrace`. |
| 1734 | método | ChameleonCommunicator | `Future<IsoDepDebugCounters> hf14a4DebugCounters()` | Operación `hf14a4DebugCounters`. |
| 1760 | método | ChameleonCommunicator | `Future<void> hf14a4SetAntiColl( Uint8List uid, Uint8List atqa, int sak, Uint8List ats, )` | Operación `hf14a4SetAntiColl`. |
| 1792 | método | ChameleonCommunicator | `Future<void> hf14a4ClearStaticResponses()` | Operación `hf14a4ClearStaticResponses`. |
| 1806 | método | ChameleonCommunicator | `Future<void> hf14a4AddStaticResponse( Uint8List command, Uint8List response, )` | Operación `hf14a4AddStaticResponse`. |
| 1831 | método | ChameleonCommunicator | `Future<Uint8List> hf14aSniff({int timeoutMs = 5000})` | Operación `hf14aSniff`. |
| 1854 | método | ChameleonCommunicator | `Future<void> writeIdteckToT55XX( Uint8List uid, Uint8List newKey, List<Uint8List> oldKeys, )` | Operación `writeIdteckToT55XX`. |
| 1867 | método | ChameleonCommunicator | `Future<void> setSlotTagName( int index, String name, TagFrequency frequency, )` | Operación `setSlotTagName`. |
| 1878 | método | ChameleonCommunicator | `Future<String> getSlotTagName(int index, TagFrequency frequency)` | Operación `getSlotTagName`. |
| 1889 | método | ChameleonCommunicator | `Future<List<SlotNames>> getSlotTagNames()` | Operación `getSlotTagNames`. |
| 1941 | método | ChameleonCommunicator | `Future<void> deleteSlotInfo(int index, TagFrequency frequency)` | Operación `deleteSlotInfo`. |
| 1948 | método | ChameleonCommunicator | `Future<void> saveSlotData()` | Operación `saveSlotData`. |
| 1958 | método | ChameleonCommunicator | `Future<MifareClassicActiveSlotSnapshot> beginActiveSlotSnapshot()` | Operación `beginActiveSlotSnapshot`. |
| 2011 | método | ChameleonCommunicator | `Future<void> saveReleaseActiveSlotSnapshot( MifareClassicActiveSlotSnapshot snapshot, )` | Operación `saveReleaseActiveSlotSnapshot`. |
| 2038 | método | ChameleonCommunicator | `Future<void> abortActiveSlotSnapshot( MifareClassicActiveSlotSnapshot snapshot, )` | Operación `abortActiveSlotSnapshot`. |
| 2044 | método | ChameleonCommunicator | `Future<void> _abortActiveSlotSnapshotRevision(int revision)` | Operación `_abortActiveSlotSnapshotRevision`. |
| 2060 | método | ChameleonCommunicator | `void _validateActiveSlotSnapshotEnd( Uint8List data, int operation, int revision, )` | Operación `_validateActiveSlotSnapshotEnd`. |
| 2075 | método | ChameleonCommunicator | `Future<void> enterDFUMode()` | Operación `enterDFUMode`. |
| 2079 | método | ChameleonCommunicator | `Future<void> factoryReset()` | Operación `factoryReset`. |
| 2083 | método | ChameleonCommunicator | `Future<void> saveSettings()` | Operación `saveSettings`. |
| 2087 | método | ChameleonCommunicator | `Future<void> resetSettings()` | Operación `resetSettings`. |
| 2091 | método | ChameleonCommunicator | `Future<void> setAnimationMode(AnimationSetting animation)` | Operación `setAnimationMode`. |
| 2098 | método | ChameleonCommunicator | `Future<AnimationSetting> getAnimationMode()` | Operación `getAnimationMode`. |
| 2106 | método | ChameleonCommunicator | `Future<String> getGitCommitHash()` | Operación `getGitCommitHash`. |
| 2111 | método | ChameleonCommunicator | `Future<int> getActiveSlot()` | Operación `getActiveSlot`. |
| 2120 | método | ChameleonCommunicator | `Future<List<SlotTypes>> getSlotTagTypes()` | Operación `getSlotTagTypes`. |
| 2144 | método | ChameleonCommunicator | `Future<EmulatorSettings> getMf1EmulatorSettings()` | Operación `getMf1EmulatorSettings`. |
| 2172 | método | ChameleonCommunicator | `Future<bool> isMf1Gen1aMode()` | Operación `isMf1Gen1aMode`. |
| 2180 | método | ChameleonCommunicator | `Future<void> setMf1Gen1aMode(bool gen1aMode)` | Operación `setMf1Gen1aMode`. |
| 2187 | método | ChameleonCommunicator | `Future<bool> isMf1Gen2Mode()` | Operación `isMf1Gen2Mode`. |
| 2195 | método | ChameleonCommunicator | `Future<void> setMf1Gen2Mode(bool gen2Mode)` | Operación `setMf1Gen2Mode`. |
| 2202 | método | ChameleonCommunicator | `Future<bool> isMf1UseFirstBlockColl()` | Operación `isMf1UseFirstBlockColl`. |
| 2210 | método | ChameleonCommunicator | `Future<void> setMf1UseFirstBlockColl(bool useColl)` | Operación `setMf1UseFirstBlockColl`. |
| 2217 | método | ChameleonCommunicator | `Future<MifareWriteMode> getMf1WriteMode()` | Operación `getMf1WriteMode`. |
| 2233 | método | ChameleonCommunicator | `Future<void> setMf1WriteMode(MifareWriteMode mode)` | Operación `setMf1WriteMode`. |
| 2240 | método | ChameleonCommunicator | `Future<Mf1PrngType> getMf1PrngType()` | Operación `getMf1PrngType`. |
| 2252 | método | ChameleonCommunicator | `Future<void> setMf1PrngType(Mf1PrngType type)` | Operación `setMf1PrngType`. |
| 2259 | método | ChameleonCommunicator | `Future<List<EnabledSlotInfo>> getEnabledSlots()` | Operación `getEnabledSlots`. |
| 2273 | método | ChameleonCommunicator | `Future<BatteryCharge> getBatteryCharge()` | Operación `getBatteryCharge`. |
| 2281 | método | ChameleonCommunicator | `Future<ButtonConfig> getButtonConfig(ButtonType type)` | Operación `getButtonConfig`. |
| 2289 | método | ChameleonCommunicator | `Future<void> setButtonConfig(ButtonType type, ButtonConfig mode)` | Operación `setButtonConfig`. |
| 2296 | método | ChameleonCommunicator | `Future<ButtonConfig> getLongButtonConfig(ButtonType type)` | Operación `getLongButtonConfig`. |
| 2304 | método | ChameleonCommunicator | `Future<void> setLongButtonConfig(ButtonType type, ButtonConfig mode)` | Operación `setLongButtonConfig`. |
| 2311 | método | ChameleonCommunicator | `Future<int> getSleepTimeout()` | Operación `getSleepTimeout`. |
| 2316 | método | ChameleonCommunicator | `Future<void> setSleepTimeout(int seconds)` | Operación `setSleepTimeout`. |
| 2326 | método | ChameleonCommunicator | `Future<void> clearBLEBoundedDevices()` | Operación `clearBLEBoundedDevices`. |
| 2330 | método | ChameleonCommunicator | `Future<String> getBLEConnectionKey()` | Operación `getBLEConnectionKey`. |
| 2335 | método | ChameleonCommunicator | `Future<void> setBLEConnectKey(String key)` | Operación `setBLEConnectKey`. |
| 2342 | método | ChameleonCommunicator | `Future<bool> isBLEPairEnabled()` | Operación `isBLEPairEnabled`. |
| 2347 | método | ChameleonCommunicator | `Future<void> setBLEPairEnabled(bool status)` | Operación `setBLEPairEnabled`. |
| 2354 | método | ChameleonCommunicator | `Future<ChameleonDevice> getDeviceType()` | Operación `getDeviceType`. |
| 2360 | método | ChameleonCommunicator | `Future<Uint8List> mf1GetEmulatorBlock(int startBlock, int blockCount)` | Operación `mf1GetEmulatorBlock`. |
| 2367 | método | ChameleonCommunicator | `Future<Uint8List> mf1GetSnapshotBlocks( MifareClassicActiveSlotSnapshot snapshot, int startBlock, int blockCount, )` | Operación `mf1GetSnapshotBlocks`. |
| 2394 | método | ChameleonCommunicator | `Future<CardData> mf1GetSnapshotAntiColl( MifareClassicActiveSlotSnapshot snapshot, )` | Operación `mf1GetSnapshotAntiColl`. |
| 2403 | método | ChameleonCommunicator | `Future<CardData> mf1GetAntiCollData()` | Operación `mf1GetAntiCollData`. |
| 2429 | método | ChameleonCommunicator | `Future<Uint8List> getEM410XEmulatorID()` | Operación `getEM410XEmulatorID`. |
| 2465 | método | ChameleonCommunicator | `Future<HIDCard> getHIDProxEmulatorID()` | Operación `getHIDProxEmulatorID`. |
| 2471 | método | ChameleonCommunicator | `Future<VikingCard> getVikingEmulatorID()` | Operación `getVikingEmulatorID`. |
| 2477 | método | ChameleonCommunicator | `Future<PacCard> getPacEmulatorID()` | Operación `getPacEmulatorID`. |
| 2483 | método | ChameleonCommunicator | `Future<IoProxCard> getIoProxEmulatorID()` | Operación `getIoProxEmulatorID`. |
| 2489 | método | ChameleonCommunicator | `Future<IdteckCard> getIdteckEmulatorID()` | Operación `getIdteckEmulatorID`. |
| 2495 | método | ChameleonCommunicator | `Future<DeviceSettings> getDeviceSettings()` | Operación `getDeviceSettings`. |
| 2530 | método | ChameleonCommunicator | `Future<List<int>> getDeviceCapabilities()` | Operación `getDeviceCapabilities`. |
| 2535 | método | ChameleonCommunicator | `Future<void> manipulateValueBlock( int srcBlock, int srcKeyType, Uint8List srcKey, MifareClassicValueBlockOperator op, int value, int dstBlock, int dstKeyType, Uint8List dstKey, )` | Operación `manipulateValueBlock`. |
| 2563 | método | ChameleonCommunicator | `Future<Uint8List> send14ARaw( Uint8List data, { int respTimeoutMs = 100, int? bitLen, bool activateRfField = true, bool waitResponse = true, bool appendCrc = true, bool autoSelect = true, bool keepRfField = false, bool checkResponseCrc = true, })` | Operación `send14ARaw`. |
| 2607 | método | ChameleonCommunicator | `Future<bool> mf0GetMagicMode()` | Operación `mf0GetMagicMode`. |
| 2612 | método | ChameleonCommunicator | `Future<void> mf0SetMagicMode(bool enabled)` | Operación `mf0SetMagicMode`. |
| 2619 | método | ChameleonCommunicator | `Future<Uint8List> mf0EmulatorReadPages(int from, int count)` | Operación `mf0EmulatorReadPages`. |
| 2626 | método | ChameleonCommunicator | `Future<void> mf0EmulatorWritePages(int from, Uint8List data)` | Operación `mf0EmulatorWritePages`. |
| 2633 | método | ChameleonCommunicator | `Future<Uint8List> mf0EmulatorGetVersionData()` | Operación `mf0EmulatorGetVersionData`. |
| 2637 | método | ChameleonCommunicator | `Future<void> mf0EmulatorSetVersionData(Uint8List data)` | Operación `mf0EmulatorSetVersionData`. |
| 2644 | método | ChameleonCommunicator | `Future<Uint8List> mf0EmulatorGetSignatureData()` | Operación `mf0EmulatorGetSignatureData`. |
| 2648 | método | ChameleonCommunicator | `Future<void> mf0EmulatorSetSignatureData(Uint8List data)` | Operación `mf0EmulatorSetSignatureData`. |
| 2655 | método | ChameleonCommunicator | `Future<int> mf0ResetAuthCount()` | Operación `mf0ResetAuthCount`. |
| 2663 | método | ChameleonCommunicator | `Future<int> mf0EmulatorGetPageCount()` | Operación `mf0EmulatorGetPageCount`. |
| 2667 | método | ChameleonCommunicator | `Future<(int, bool)> mf0EmulatorGetCounterData(int index)` | Operación `mf0EmulatorGetCounterData`. |
| 2675 | método | ChameleonCommunicator | `Future<void> mf0EmulatorSetCounterData( int index, int value, bool resetTearing, )` | Operación `mf0EmulatorSetCounterData`. |
| 2691 | método | ChameleonCommunicator | `Future<MifareWriteMode> mf0NtagGetWriteMode()` | Operación `mf0NtagGetWriteMode`. |
| 2704 | método | ChameleonCommunicator | `Future<void> mf0NtagSetWriteMode(MifareWriteMode mode)` | Operación `mf0NtagSetWriteMode`. |
| 2711 | método | ChameleonCommunicator | `Future<bool> mf0NtagGetDetectionEnable()` | Operación `mf0NtagGetDetectionEnable`. |
| 2716 | método | ChameleonCommunicator | `Future<void> mf0NtagSetDetectionEnable(bool enabled)` | Operación `mf0NtagSetDetectionEnable`. |
| 2723 | método | ChameleonCommunicator | `Future<int> mf0NtagGetDetectionCount()` | Operación `mf0NtagGetDetectionCount`. |
| 2728 | método | ChameleonCommunicator | `Future<List<String>> mf0NtagGetDetectionLog(int index)` | Operación `mf0NtagGetDetectionLog`. |
| 2745 | método | ChameleonCommunicator | `Future<EmulatorSettings> mf0NtagGetEmulatorConfig()` | Operación `mf0NtagGetEmulatorConfig`. |
## `lib/bridge/chameleon_ble.dart`

| Línea | Tipo | Owner | Firma | Descripción |
|---:|---|---|---|---|
| 18 | método | ChameleonBle | `ChameleonMessage _requireBleSuccess( ChameleonCommand command, ChameleonMessage? response, {int? exactDataLength, int minimumDataLength = 0})` | Operación `_requireBleSuccess`. |
| 44 | método | ChameleonBle | `Future<void> blePassiveScanStart({bool active = false})` | Operación `blePassiveScanStart`. |
| 51 | método | ChameleonBle | `Future<void> blePassiveScanStop()` | Operación `blePassiveScanStop`. |
| 56 | método | ChameleonBle | `Future<int> blePassiveScanCount()` | Operación `blePassiveScanCount`. |
| 65 | método | ChameleonBle | `Future<List<BleScanResult>> blePassiveScanResults( {int startIndex = 0})` | Operación `blePassiveScanResults`. |
| 102 | método | ChameleonBle | `Future<bool> bleAdvertisingGet()` | Operación `bleAdvertisingGet`. |
| 110 | método | ChameleonBle | `Future<bool> bleAdvertisingSet(bool on, {bool eraseBonds = false})` | Operación `bleAdvertisingSet`. |
| 129 | método | ChameleonBle | `Future<int> bleSetAddr(int mode, {Uint8List? addr})` | Operación `bleSetAddr`. |
| 153 | método | ChameleonBle | `Future<Map<String, dynamic>> bleGetAddr()` | Operación `bleGetAddr`. |
| 165 | método | ChameleonBle | `Future<int> bleRadioSet(bool on)` | Operación `bleRadioSet`. |
| 175 | método | ChameleonBle | `Future<Map<String, bool>> bleRadioGet()` | Operación `bleRadioGet`. |
| 200 | método | ChameleonBle | `Future<int> bleFloodStart(int scope, int valueHandle, int payloadSize, {int maxIterations = 0, int intervalMs = 10})` | Operación `bleFloodStart`. |
| 239 | método | ChameleonBle | `Future<void> bleFloodStop()` | Operación `bleFloodStop`. |
| 246 | método | ChameleonBle | `Future<int> bleFloodCount()` | Operación `bleFloodCount`. |
| 260 | método | ChameleonBle | `Future<int> bleKick(int cycles, {int scope = 0})` | Operación `bleKick`. |
| 281 | método | ChameleonBle | `Future<int> bleAdvFloodStart(int fillByte, {int intervalUnits = 1})` | Operación `bleAdvFloodStart`. |
| 295 | método | ChameleonBle | `Future<void> bleAdvFloodStop()` | Operación `bleAdvFloodStop`. |
| 300 | método | ChameleonBle | `Future<BleAdvertisingLabStatus> bleAdvLabStart( BleAdvertisingLabConfig config)` | Operación `bleAdvLabStart`. |
| 308 | método | ChameleonBle | `Future<BleAdvertisingLabStatus> bleAdvLabStatus()` | Operación `bleAdvLabStatus`. |
| 315 | método | ChameleonBle | `Future<BleAdvertisingLabStatus> bleAdvLabStop()` | Operación `bleAdvLabStop`. |
| 324 | método | ChameleonBle | `Future<int> bleConnect(Uint8List addrLe, {int addrType = 0})` | Operación `bleConnect`. |
| 337 | método | ChameleonBle | `Future<void> bleDisconnect()` | Operación `bleDisconnect`. |
| 342 | método | ChameleonBle | `Future<BleCentralState> bleCentralState()` | Operación `bleCentralState`. |
| 381 | método | ChameleonBle | `Future<int> bleGattDiscover()` | Operación `bleGattDiscover`. |
| 389 | método | ChameleonBle | `Future<List<BleCharacteristic>> bleGattChars({int startIndex = 0})` | Operación `bleGattChars`. |
| 415 | método | ChameleonBle | `Future<List<Map<String, int>>> bleServices( {Duration timeout = const Duration(seconds: 3)})` | Operación `bleServices`. |
| 454 | método | ChameleonBle | `Future<List<Map<String, int>>> bleDescriptors( {Duration timeout = const Duration(seconds: 5)})` | Operación `bleDescriptors`. |
| 496 | método | ChameleonBle | `Future<List<Map<String, dynamic>>> bleDeviceInfo( {Duration timeout = const Duration(seconds: 3)})` | Operación `bleDeviceInfo`. |
| 546 | método | ChameleonBle | `Future<int> bleFuzzStart(int valueHandle, {int maxIterations = 0, int intervalMs = 50})` | Operación `bleFuzzStart`. |
| 570 | método | ChameleonBle | `Future<void> bleFuzzStop()` | Operación `bleFuzzStop`. |
| 575 | método | ChameleonBle | `Future<int> bleLinkProbe({bool globalMode = false})` | Operación `bleLinkProbe`. |
| 585 | método | ChameleonBle | `Future<List<BleFuzzLogEntry>> bleFuzzLog({int startIndex = 0})` | Operación `bleFuzzLog`. |
| 622 | método | ChameleonBle | `Future<(int, Uint8List)> bleGattRead(int valueHandle, {Duration timeout = const Duration(seconds: 2)})` | Operación `bleGattRead`. |
| 654 | método | ChameleonBle | `Future<int> bleGattWrite(int valueHandle, Uint8List data, {Duration timeout = const Duration(seconds: 2)})` | Operación `bleGattWrite`. |
| 681 | método | ChameleonBle | `Future<int> bleGetMtu()` | Operación `bleGetMtu`. |
| 690 | método | ChameleonBle | `Future<int> bleSubscribe(int cccdHandle, int mode)` | Operación `bleSubscribe`. |
| 706 | método | ChameleonBle | `Future<List<Map<String, dynamic>>> bleGetNotifications( {int startIndex = 0})` | Operación `bleGetNotifications`. |
| 740 | método | ChameleonBle | `Future<int> bleFindCccd(int valueHandle, {Duration timeout = const Duration(seconds: 2)})` | Operación `bleFindCccd`. |
## `lib/bridge/chameleon_frame_decoder.dart`

| Línea | Tipo | Owner | Firma | Descripción |
|---:|---|---|---|---|
| 16 | constructor | ChameleonFrameDecodeError | `const ChameleonFrameDecodeError( this.kind, { required this.discardedBytes, this.advertisedLength, })` | Construye ChameleonFrameDecodeError. |
| 26 | método | ChameleonFrameDecodeError | `@override String toString()` | Operación `toString`. |
| 36 | constructor | ChameleonDecodedFrame | `const ChameleonDecodedFrame({ required this.command, required this.status, required this.data, })` | Construye ChameleonDecodedFrame. |
| 48 | constructor | ChameleonFrameDecodeResult | `const ChameleonFrameDecodeResult({ required this.frames, required this.errors, })` | Construye ChameleonFrameDecodeResult. |
| 57 | función | - | `int chameleonLrc(Iterable<int> bytes)` | Función `chameleonLrc`. |
| 65 | función | - | `Uint8List buildChameleonFrame({ required int command, required int status, Uint8List? data, })` | Función `buildChameleonFrame`. |
| 98 | getter | ChameleonFrameDecoder | `int get retainedByteCount` | Obtiene `retainedByteCount`. |
| 100 | método | ChameleonFrameDecoder | `void reset()` | Operación `reset`. |
| 102 | método | ChameleonFrameDecoder | `ChameleonFrameDecodeResult add(Iterable<int> bytes)` | Operación `add`. |
## `lib/bridge/chameleon_keyboard.dart`

| Línea | Tipo | Owner | Firma | Descripción |
|---:|---|---|---|---|
| 17 | constructor | KeyboardOutput | `const KeyboardOutput(this.value)` | Construye KeyboardOutput. |
| 37 | constructor | KeyboardUploadBeginResult | `const KeyboardUploadBeginResult({ required this.uploadId, required this.nextOffset, required this.maximumChunkLength, })` | Construye KeyboardUploadBeginResult. |
| 48 | constructor | KeyboardUploadChunkResult | `const KeyboardUploadChunkResult({ required this.uploadId, required this.nextOffset, })` | Construye KeyboardUploadChunkResult. |
| 59 | constructor | KeyboardUploadCommitResult | `const KeyboardUploadCommitResult({ required this.commitId, required this.totalLength, required this.crc32, })` | Construye KeyboardUploadCommitResult. |
| 65 | método | KeyboardUploadCommitResult | `bool matchesProgram(List<int> program)` | Operación `matchesProgram`. |
| 72 | constructor | KeyboardRunResult | `const KeyboardRunResult(this.runId)` | Construye KeyboardRunResult. |
| 88 | constructor | KeyboardStatus | `const KeyboardStatus({ required this.state, required this.error, required this.outputs, required this.uploadId, required this.commitId, required this.runId, required this.expected, required this.received, required this.programCounter, required this.length, required this.crc32, })` | Construye KeyboardStatus. |
| 104 | método | ChameleonKeyboard | `Future<KeyboardUploadBeginResult> keyboardUploadBegin( int totalLength, int crc32)` | Operación `keyboardUploadBegin`. |
| 140 | método | ChameleonKeyboard | `Future<KeyboardUploadChunkResult> keyboardUploadChunk( int uploadId, int offset, Uint8List chunk)` | Operación `keyboardUploadChunk`. |
| 177 | método | ChameleonKeyboard | `Future<KeyboardUploadCommitResult> keyboardUploadCommit(int uploadId)` | Operación `keyboardUploadCommit`. |
| 204 | método | ChameleonKeyboard | `Future<KeyboardRunResult> keyboardRun( int commitId, KeyboardOutput output)` | Operación `keyboardRun`. |
| 225 | método | ChameleonKeyboard | `Future<String> keyboardSetTemporaryBleName([String? name])` | Operación `keyboardSetTemporaryBleName`. |
| 262 | método | ChameleonKeyboard | `Future<KeyboardRunResult> keyboardArmBle(int commitId)` | Operación `keyboardArmBle`. |
| 281 | método | ChameleonKeyboard | `Future<void> keyboardCancel()` | Operación `keyboardCancel`. |
| 289 | método | ChameleonKeyboard | `Future<KeyboardStatus> keyboardStatus()` | Operación `keyboardStatus`. |
| 332 | método | ChameleonKeyboard | `Future<void> keyboardClear()` | Operación `keyboardClear`. |
| 340 | método | ChameleonKeyboard | `Future<KeyboardUploadCommitResult> keyboardUpload(Uint8List program)` | Operación `keyboardUpload`. |
| 374 | función | - | `ChameleonMessage _requireKeyboardResponse( ChameleonCommand command, ChameleonMessage? response, int exactDataLength)` | Función `_requireKeyboardResponse`. |
| 389 | función | - | `void _requireRange(String name, int value, int minimum, int maximum)` | Función `_requireRange`. |
| 395 | función | - | `int keyboardProgramCrc32(List<int> bytes)` | Función `keyboardProgramCrc32`. |
## `lib/bridge/dfu.dart`

| Línea | Tipo | Owner | Firma | Descripción |
|---:|---|---|---|---|
| 22 | constructor | DFUCommand | `const DFUCommand(this.value)` | Construye DFUCommand. |
| 39 | constructor | DFUResponseCode | `const DFUResponseCode(this.value)` | Construye DFUResponseCode. |
| 42 | método | DFUResponseCode | `static DFUResponseCode fromValue(int value)` | Operación `fromValue`. |
| 59 | método | Slip | `static Uint8List encode(Uint8List data)` | Operación `encode`. |
| 76 | método | Slip | `static Uint8List decode(Uint8List data)` | Operación `decode`. |
| 90 | método | Slip | `static (bool, int, List<int>) decodeAddByte( int byte, List<int> previous, int currentState)` | Operación `decodeAddByte`. |
| 128 | constructor | SlipDecoder | `SlipDecoder({this.maxPacketLength = 4096})` | Construye SlipDecoder. |
| 130 | método | SlipDecoder | `List<Uint8List> add(Uint8List data)` | Operación `add`. |
| 169 | método | SlipDecoder | `void reset()` | Operación `reset`. |
| 177 | constructor | DFUTransferError | `DFUTransferError(this.cause)` | Construye DFUTransferError. |
| 196 | constructor | DFUCommunicator | `DFUCommunicator(this.log, {AbstractSerial? port, bool viaBLE = false, this.writeTimeout = const Duration(seconds: 5), this.responseTimeout = const Duration(seconds: 10)})` | Construye DFUCommunicator. |
| 207 | método | DFUCommunicator | `dynamic open(AbstractSerial port)` | Operación `open`. |
| 211 | método | DFUCommunicator | `Future<void> _onSerialData(Uint8List data)` | Operación `_onSerialData`. |
| 223 | método | DFUCommunicator | `Future<Uint8List?> sendCmd(DFUCommand cmd, Uint8List data)` | Operación `sendCmd`. |
| 238 | método | DFUCommunicator | `Future<Uint8List?> _sendCmd(DFUCommand cmd, Uint8List data)` | Operación `_sendCmd`. |
| 299 | método | DFUCommunicator | `Future<dynamic> selectObject(int objectType)` | Operación `selectObject`. |
| 314 | método | DFUCommunicator | `Future<void> createObject(int objectType, int objectSize)` | Operación `createObject`. |
| 321 | método | DFUCommunicator | `Future<void> execute()` | Operación `execute`. |
| 325 | método | DFUCommunicator | `Future<void> setPRN()` | Operación `setPRN`. |
| 329 | método | DFUCommunicator | `Future<int> getMTU()` | Operación `getMTU`. |
| 342 | método | DFUCommunicator | `Future<Map<String, int>> calculateChecksum()` | Operación `calculateChecksum`. |
| 353 | método | DFUCommunicator | `Future<void> flashFirmware(int objectType, Uint8List firmwareBytes, void Function(int progress) callback)` | Operación `flashFirmware`. |
| 392 | método | DFUCommunicator | `Future<int> sendFirmware(List<int> data, {int crc = 0, int offset = 0})` | Operación `sendFirmware`. |
| 446 | método | DFUCommunicator | `Future<void> delayedSend(Uint8List packet)` | Operación `delayedSend`. |
## `lib/bridge/relay_lab_platform.dart`

| Línea | Tipo | Owner | Firma | Descripción |
|---:|---|---|---|---|
| 7 | getter | RelayLabPlatform | `Stream<Map<String, Object?>> get apduEvents` | Obtiene `apduEvents`. |
| 12 | método | RelayLabPlatform | `Future<bool> isAvailable()` | Operación `isAvailable`. |
| 20 | método | RelayLabPlatform | `Future<bool> setEnabled(bool enabled)` | Operación `setEnabled`. |
| 32 | método | RelayLabPlatform | `Future<bool> respond(int id, String responseHex)` | Operación `respond`. |
## `lib/connector/serial_abstract.dart`

| Línea | Tipo | Owner | Firma | Descripción |
|---:|---|---|---|---|
| 16 | constructor | Chameleon | `const Chameleon( {required this.port, required this.device, required this.type, required this.dfu})` | Construye Chameleon. |
| 36 | constructor | AbstractSerial | `AbstractSerial({required this.log})` | Construye AbstractSerial. |
| 38 | método | AbstractSerial | `Future<bool> performConnect()` | Operación `performConnect`. |
| 42 | método | AbstractSerial | `Future<bool> performDisconnect()` | Operación `performDisconnect`. |
| 46 | método | AbstractSerial | `bool isManualConnectionSupported()` | Operación `isManualConnectionSupported`. |
| 48 | método | AbstractSerial | `Future<bool> connectSpecificDevice(dynamic devicePort)` | Operación `connectSpecificDevice`. |
| 50 | método | AbstractSerial | `Future<List<Chameleon>> availableChameleons(bool onlyDFU)` | Operación `availableChameleons`. |
| 52 | método | AbstractSerial | `Future<void> open()` | Operación `open`. |
| 54 | método | AbstractSerial | `Future<bool> write(Uint8List command, {bool firmware = false})` | Operación `write`. |
| 56 | método | AbstractSerial | `Future<bool> writeWithTimeout(Uint8List command, {bool firmware = false, Duration timeout = const Duration(seconds: 5)})` | Operación `writeWithTimeout`. |
| 63 | método | AbstractSerial | `Future<void> registerCallback(dynamic callback)` | Operación `registerCallback`. |
| 67 | método | AbstractSerial | `@protected void resetConnectionState()` | Operación `resetConnectionState`. |
| 80 | getter | AbstractSerial | `@protected bool get hasConnectionState` | Obtiene `hasConnectionState`. |
| 91 | método | AbstractSerial | `@protected void notifyConnectionStateChanged()` | Operación `notifyConnectionStateChanged`. |
## `lib/connector/serial_android.dart`

| Línea | Tipo | Owner | Firma | Descripción |
|---:|---|---|---|---|
| 16 | constructor | AndroidSerial | `AndroidSerial({required super.log})` | Construye AndroidSerial. |
| 21 | método | AndroidSerial | `@override Future<bool> performDisconnect()` | Operación `performDisconnect`. |
| 28 | método | AndroidSerial | `@override bool isManualConnectionSupported()` | Operación `isManualConnectionSupported`. |
| 33 | método | AndroidSerial | `@override Future<List<Chameleon>> availableChameleons(bool onlyDFU)` | Operación `availableChameleons`. |
| 46 | método | AndroidSerial | `@override Future<bool> connectSpecificDevice(dynamic devicePort)` | Operación `connectSpecificDevice`. |
| 55 | método | AndroidSerial | `Future<bool> checkPermissions()` | Operación `checkPermissions`. |
| 82 | método | AndroidSerial | `@override Future<bool> write(Uint8List command, {bool firmware = false})` | Operación `write`. |
| 91 | método | AndroidSerial | `@override Future<void> registerCallback(dynamic callback)` | Operación `registerCallback`. |
| 97 | getter | AndroidSerial | `@override dynamic get activeDevicePort` | Obtiene `activeDevicePort`. |
| 102 | getter | AndroidSerial | `@override ChameleonDevice get device` | Obtiene `device`. |
| 106 | getter | AndroidSerial | `@override bool get connected` | Obtiene `connected`. |
| 109 | getter | AndroidSerial | `@override String get portName` | Obtiene `portName`. |
| 113 | getter | AndroidSerial | `@override ConnectionType get connectionType` | Obtiene `connectionType`. |
| 118 | getter | AndroidSerial | `@override bool get isOpen` | Obtiene `isOpen`. |
| 121 | setter | AndroidSerial | `@override set isOpen(open)` | Actualiza `isOpen`. |
| 124 | getter | AndroidSerial | `@override bool get isDFU` | Obtiene `isDFU`. |
| 127 | getter | AndroidSerial | `@override bool get pendingConnection` | Obtiene `pendingConnection`. |
| 130 | setter | AndroidSerial | `@override set pendingConnection(pendingConnection)` | Actualiza `pendingConnection`. |
## `lib/connector/serial_ble.dart`

| Línea | Tipo | Owner | Firma | Descripción |
|---:|---|---|---|---|
| 50 | constructor | BLESerial | `BLESerial({ required super.log, FlutterReactiveBle? reactiveBle, this.connectionPriorityRequester, this.mtuRequester, this.writeRequester, this.connectionAttemptTimeout = const Duration(seconds: 10), this.scanDuration = const Duration(seconds: 2), }) : _flutterReactiveBle = reactiveBle` | Construye BLESerial. |
| 60 | getter | BLESerial | `FlutterReactiveBle get flutterReactiveBle` | Obtiene `flutterReactiveBle`. |
| 63 | método | BLESerial | `Future<void> optimizeConnection( String deviceId, { bool? isAndroid, })` | Operación `optimizeConnection`. |
| 96 | método | BLESerial | `Future<List> availableDevices({bool? isIOS})` | Operación `availableDevices`. |
| 195 | método | BLESerial | `@override bool isManualConnectionSupported()` | Operación `isManualConnectionSupported`. |
| 200 | método | BLESerial | `@override Future<List<Chameleon>> availableChameleons(bool onlyDFU)` | Operación `availableChameleons`. |
| 241 | método | BLESerial | `@override Future<bool> connectSpecificDevice(dynamic devicePort)` | Operación `connectSpecificDevice`. |
| 259 | método | BLESerial | `Future<bool> connectSpecificInternal(dynamic devicePort)` | Operación `connectSpecificInternal`. |
| 451 | método | BLESerial | `Future<void> _disconnectGeneration( int generation, { Object? error, StackTrace? stackTrace, })` | Operación `_disconnectGeneration`. |
| 471 | método | BLESerial | `@override Future<bool> performDisconnect()` | Operación `performDisconnect`. |
| 474 | método | BLESerial | `Future<bool> _performDisconnect({required bool cancelRetryLoop})` | Operación `_performDisconnect`. |
| 509 | método | BLESerial | `@override Future<bool> write(Uint8List command, {bool firmware = false})` | Operación `write`. |
| 546 | método | BLESerial | `Future<Characteristic> _resolveRxCharacteristic()` | Operación `_resolveRxCharacteristic`. |
| 561 | método | BLESerial | `Future<Characteristic> _resolveFirmwareCharacteristic()` | Operación `_resolveFirmwareCharacteristic`. |
## `lib/connector/serial_emulator.dart`

| Línea | Tipo | Owner | Firma | Descripción |
|---:|---|---|---|---|
| 12 | constructor | EmulatorSerial | `EmulatorSerial({required super.log})` | Construye EmulatorSerial. |
| 14 | método | EmulatorSerial | `@override Future<bool> performConnect()` | Operación `performConnect`. |
| 19 | método | EmulatorSerial | `@override Future<bool> performDisconnect()` | Operación `performDisconnect`. |
| 29 | método | EmulatorSerial | `@override Future<List<Chameleon>> availableChameleons(bool onlyDFU)` | Operación `availableChameleons`. |
| 40 | método | EmulatorSerial | `Future<bool> connectDevice(String address, bool setPort)` | Operación `connectDevice`. |
| 44 | método | EmulatorSerial | `@override Future<bool> write(Uint8List command, {bool firmware = false})` | Operación `write`. |
| 55 | método | EmulatorSerial | `@override Future<bool> connectSpecificDevice(dynamic devicePort)` | Operación `connectSpecificDevice`. |
| 65 | método | EmulatorSerial | `@override bool isManualConnectionSupported()` | Operación `isManualConnectionSupported`. |
## `lib/connector/serial_macos.dart`

| Línea | Tipo | Owner | Firma | Descripción |
|---:|---|---|---|---|
| 12 | constructor | MacOSSerial | `MacOSSerial({required super.log})` | Construye MacOSSerial. |
| 17 | método | MacOSSerial | `@override Future<bool> performDisconnect()` | Operación `performDisconnect`. |
| 24 | método | MacOSSerial | `@override bool isManualConnectionSupported()` | Operación `isManualConnectionSupported`. |
| 29 | método | MacOSSerial | `@override Future<List<Chameleon>> availableChameleons(bool onlyDFU)` | Operación `availableChameleons`. |
| 39 | método | MacOSSerial | `@override Future<bool> connectSpecificDevice(dynamic devicePort)` | Operación `connectSpecificDevice`. |
| 48 | método | MacOSSerial | `@override Future<bool> write(Uint8List command, {bool firmware = false})` | Operación `write`. |
| 57 | método | MacOSSerial | `@override Future<void> registerCallback(dynamic callback)` | Operación `registerCallback`. |
| 63 | getter | MacOSSerial | `@override dynamic get activeDevicePort` | Obtiene `activeDevicePort`. |
| 68 | getter | MacOSSerial | `@override ChameleonDevice get device` | Obtiene `device`. |
| 72 | getter | MacOSSerial | `@override bool get connected` | Obtiene `connected`. |
| 75 | getter | MacOSSerial | `@override String get portName` | Obtiene `portName`. |
| 79 | getter | MacOSSerial | `@override ConnectionType get connectionType` | Obtiene `connectionType`. |
| 84 | getter | MacOSSerial | `@override bool get isOpen` | Obtiene `isOpen`. |
| 87 | setter | MacOSSerial | `@override set isOpen(open)` | Actualiza `isOpen`. |
| 90 | getter | MacOSSerial | `@override bool get isDFU` | Obtiene `isDFU`. |
| 93 | getter | MacOSSerial | `@override bool get pendingConnection` | Obtiene `pendingConnection`. |
| 96 | setter | MacOSSerial | `@override set pendingConnection(pendingConnection)` | Actualiza `pendingConnection`. |
| 100 | método | MacOSSerial | `@override Future<void> open()` | Operación `open`. |
## `lib/connector/serial_mobile.dart`

| Línea | Tipo | Owner | Firma | Descripción |
|---:|---|---|---|---|
| 15 | constructor | MobileSerial | `MobileSerial({required super.log})` | Construye MobileSerial. |
| 17 | método | MobileSerial | `@override bool isManualConnectionSupported()` | Operación `isManualConnectionSupported`. |
| 22 | método | MobileSerial | `@override Future<bool> performDisconnect()` | Operación `performDisconnect`. |
| 52 | método | MobileSerial | `@protected Future<List<UsbDevice>> listUsbDevices()` | Operación `listUsbDevices`. |
| 55 | método | MobileSerial | `@protected Future<UsbPort?> createUsbPort(UsbDevice device)` | Operación `createUsbPort`. |
| 58 | getter | MobileSerial | `@protected Stream<UsbEvent>? get usbEvents` | Obtiene `usbEvents`. |
| 61 | método | MobileSerial | `Future<List> availableDevices()` | Operación `availableDevices`. |
| 76 | método | MobileSerial | `@override Future<List<Chameleon>> availableChameleons(bool onlyDFU)` | Operación `availableChameleons`. |
| 112 | método | MobileSerial | `@override Future<bool> connectSpecificDevice(dynamic devicePort)` | Operación `connectSpecificDevice`. |
| 187 | método | MobileSerial | `Future<void> _disconnectGeneration(int generation)` | Operación `_disconnectGeneration`. |
| 192 | método | MobileSerial | `@override Future<bool> write(Uint8List command, {bool firmware = false})` | Operación `write`. |
## `lib/connector/serial_native.dart`

| Línea | Tipo | Owner | Firma | Descripción |
|---:|---|---|---|---|
| 16 | constructor | NativeSerial | `NativeSerial({required super.log})` | Construye NativeSerial. |
| 18 | método | NativeSerial | `@override bool isManualConnectionSupported()` | Operación `isManualConnectionSupported`. |
| 23 | método | NativeSerial | `Future<List> availableDevices()` | Operación `availableDevices`. |
| 27 | método | NativeSerial | `@override Future<bool> performConnect()` | Operación `performConnect`. |
| 39 | método | NativeSerial | `@override Future<bool> performDisconnect()` | Operación `performDisconnect`. |
| 69 | método | NativeSerial | `@override Future<List<Chameleon>> availableChameleons(bool onlyDFU)` | Operación `availableChameleons`. |
| 92 | método | NativeSerial | `@override Future<bool> connectSpecificDevice(dynamic devicePort)` | Operación `connectSpecificDevice`. |
| 106 | método | NativeSerial | `@protected SerialPort createSerialPort(String address)` | Operación `createSerialPort`. |
| 109 | método | NativeSerial | `@protected void configureSerialPort(SerialPort candidate)` | Operación `configureSerialPort`. |
| 123 | método | NativeSerial | `Future<bool> connectDevice(String address, bool setPort)` | Operación `connectDevice`. |
| 180 | método | NativeSerial | `@override Future<void> open()` | Operación `open`. |
| 208 | método | NativeSerial | `@override Future<bool> write(Uint8List command, {bool firmware = false})` | Operación `write`. |
| 213 | método | NativeSerial | `@override Future<bool> writeWithTimeout(Uint8List command, {bool firmware = false, Duration timeout = const Duration(seconds: 5)})` | Operación `writeWithTimeout`. |
## `lib/gui/component/apdu_cheatsheet.dart`

| Línea | Tipo | Owner | Firma | Descripción |
|---:|---|---|---|---|
| 4 | constructor | ApduCheatSheet | `const ApduCheatSheet({ super.key, this.showEmv = true, this.showRelayLab = true, this.onExampleSelected, })` | Construye ApduCheatSheet. |
| 15 | método | ApduCheatSheet | `@override Widget build(BuildContext context)` | Construye la interfaz de ApduCheatSheet. |
| 109 | método | ApduCheatSheet | `Widget _section(String title)` | Operación `_section`. |
| 119 | método | ApduCheatSheet | `Widget _entry(String name, String syntax, String meaning, {String? example})` | Operación `_entry`. |
| 147 | método | ApduCheatSheet | `Widget _status(String status, String meaning)` | Operación `_status`. |
## `lib/gui/component/card_button.dart`

| Línea | Tipo | Owner | Firma | Descripción |
|---:|---|---|---|---|
| 4 | función | - | `ButtonStyle customCardButtonStyle(ChameleonGUIState appState)` | Función `customCardButtonStyle`. |
## `lib/gui/component/card_list.dart`

| Línea | Tipo | Owner | Firma | Descripción |
|---:|---|---|---|---|
| 16 | constructor | CardSearchDelegate | `CardSearchDelegate( {required this.cards, required this.onTap, this.filter = SearchFilter.all})` | Construye CardSearchDelegate. |
| 21 | método | CardSearchDelegate | `@override List<Widget> buildActions(BuildContext context)` | Operación `buildActions`. |
| 75 | método | CardSearchDelegate | `@override Widget buildLeading(BuildContext context)` | Operación `buildLeading`. |
| 85 | método | CardSearchDelegate | `@override Widget buildResults(BuildContext context)` | Operación `buildResults`. |
| 136 | método | CardSearchDelegate | `@override Widget buildSuggestions(BuildContext context)` | Operación `buildSuggestions`. |
## `lib/gui/component/developer_list.dart`

| Línea | Tipo | Owner | Firma | Descripción |
|---:|---|---|---|---|
| 7 | constructor | DeveloperList | `const DeveloperList({super.key, required this.avatars})` | Construye DeveloperList. |
| 9 | método | DeveloperList | `@override Widget build(BuildContext context)` | Construye la interfaz de DeveloperList. |
## `lib/gui/component/device_found_banner.dart`

| Línea | Tipo | Owner | Firma | Descripción |
|---:|---|---|---|---|
| 18 | constructor | DeviceFoundBanner | `const DeviceFoundBanner({ super.key, required this.device, required this.onConnect, required this.onDismiss, })` | Construye DeviceFoundBanner. |
| 25 | método | DeviceFoundBanner | `@override Widget build(BuildContext context)` | Construye la interfaz de DeviceFoundBanner. |
## `lib/gui/component/element_button.dart`

| Línea | Tipo | Owner | Firma | Descripción |
|---:|---|---|---|---|
| 18 | constructor | ElementButton | `const ElementButton( {super.key, required this.icon, required this.iconColor, required this.firstLine, required this.secondLine, required this.children, required this.itemIndex, required this.onPressed, this.maxLineLines = 1})` | Construye ElementButton. |
| 29 | método | ElementButton | `@override ElementButtonState createState()` | Operación `createState`. |
| 38 | método | ElementButtonState | `@override void initState()` | Inicializa el estado de ElementButtonState. |
| 43 | método | ElementButtonState | `double _getIconButtonWidth(BuildContext context)` | Operación `_getIconButtonWidth`. |
| 50 | método | ElementButtonState | `bool _shouldMoveIcons(BuildContext context, double availableWidth)` | Operación `_shouldMoveIcons`. |
| 84 | método | ElementButtonState | `@override Widget build(BuildContext context)` | Construye la interfaz de ElementButtonState. |
## `lib/gui/component/error_message.dart`

| Línea | Tipo | Owner | Firma | Descripción |
|---:|---|---|---|---|
| 11 | constructor | ErrorMessage | `const ErrorMessage({ super.key, required this.errorMessage, this.minHeight = 60.0, this.boxWidth = double.infinity, this.iconColor = Colors.white, this.iconSize = 24.0, this.borderRadius = const BorderRadius.all(Radius.circular(8.0)), })` | Construye ErrorMessage. |
| 21 | método | ErrorMessage | `@override Widget build(BuildContext context)` | Construye la interfaz de ErrorMessage. |
## `lib/gui/component/error_page.dart`

| Línea | Tipo | Owner | Firma | Descripción |
|---:|---|---|---|---|
| 7 | constructor | ErrorPage | `const ErrorPage({ super.key, required this.errorMessage, })` | Construye ErrorPage. |
| 12 | método | ErrorPage | `@override Widget build(BuildContext context)` | Construye la interfaz de ErrorPage. |
## `lib/gui/component/hex_editor.dart`

| Línea | Tipo | Owner | Firma | Descripción |
|---:|---|---|---|---|
| 11 | constructor | HexEdit | `const HexEdit({super.key, required this.data})` | Construye HexEdit. |
| 13 | método | HexEdit | `@override HexEditState createState()` | Operación `createState`. |
| 18 | método | HexEditState | `@override void initState()` | Inicializa el estado de HexEditState. |
| 23 | método | HexEditState | `@override Widget build(BuildContext context)` | Construye la interfaz de HexEditState. |
## `lib/gui/component/hex_viewer.dart`

| Línea | Tipo | Owner | Firma | Descripción |
|---:|---|---|---|---|
| 16 | constructor | HexViewer | `const HexViewer({ super.key, required this.data, this.bytesPerRow = 16, this.scrollVertically = true, this.style, this.addressColor, this.dividerColor, this.byteColorBuilder, this.indexedByteColorBuilder, this.trailingTextBuilder, })` | Construye HexViewer. |
| 29 | método | HexViewer | `@override State<HexViewer> createState()` | Operación `createState`. |
| 37 | método | _HexViewerState | `@override void initState()` | Inicializa el estado de _HexViewerState. |
| 44 | método | _HexViewerState | `@override void dispose()` | Libera recursos de _HexViewerState. |
| 51 | método | _HexViewerState | `@override Widget build(BuildContext context)` | Construye la interfaz de _HexViewerState. |
## `lib/gui/component/key_check_marks.dart`

| Línea | Tipo | Owner | Firma | Descripción |
|---:|---|---|---|---|
| 19 | constructor | KeyCheckMarks | `const KeyCheckMarks( {super.key, required this.checkMarks, required this.validKeys, this.checkmarkCount = 16, this.checkmarkPerRow = 16, this.checkmarkSize = 20, this.fontSize = 16, this.onCheckmarkChanged})` | Construye KeyCheckMarks. |
| 29 | método | KeyCheckMarks | `@override State<KeyCheckMarks> createState()` | Operación `createState`. |
| 38 | método | _KeyCheckMarksState | `GlobalKey _checkmarkKey(int index)` | Operación `_checkmarkKey`. |
| 42 | método | _KeyCheckMarksState | `void _startCheckmarkDrag(int index)` | Operación `_startCheckmarkDrag`. |
| 60 | método | _KeyCheckMarksState | `void _applyDragValue(int index)` | Operación `_applyDragValue`. |
| 75 | método | _KeyCheckMarksState | `void _continueCheckmarkDrag(Offset globalPosition)` | Operación `_continueCheckmarkDrag`. |
| 92 | método | _KeyCheckMarksState | `void _endCheckmarkDrag()` | Operación `_endCheckmarkDrag`. |
| 97 | método | _KeyCheckMarksState | `Widget _buildDraggableIcon(int index, IconData icon)` | Operación `_buildDraggableIcon`. |
| 109 | método | _KeyCheckMarksState | `Widget buildCheckmark(BuildContext context, int index, {bool tooltipBelow = true})` | Operación `buildCheckmark`. |
| 155 | método | _KeyCheckMarksState | `List<Widget> buildCheckmarkRow(int checkmarkIndex, int count)` | Operación `buildCheckmarkRow`. |
| 179 | método | _KeyCheckMarksState | `Widget buildContent(int checkmarkIndex, int count)` | Operación `buildContent`. |
| 255 | método | _KeyCheckMarksState | `@override Widget build(BuildContext context)` | Construye la interfaz de _KeyCheckMarksState. |
## `lib/gui/component/mifare/classic.dart`

| Línea | Tipo | Owner | Firma | Descripción |
|---:|---|---|---|---|
| 27 | constructor | MifareClassicHelper | `const MifareClassicHelper({ super.key, required this.hfInfo, required this.mfcInfo, this.allowSave = true, })` | Construye MifareClassicHelper. |
| 34 | método | MifareClassicHelper | `@override State<StatefulWidget> createState()` | Operación `createState`. |
| 42 | método | CardReaderState | `Future<void> exportFoundKeys()` | Operación `exportFoundKeys`. |
| 51 | método | CardReaderState | `Future<void> saveCard({bool bin = false, bool skipDump = false})` | Operación `saveCard`. |
| 91 | método | CardReaderState | `@override Widget build(BuildContext context)` | Construye la interfaz de CardReaderState. |
| 470 | constructor | _ResponsiveButtonGroup | `const _ResponsiveButtonGroup({ required this.children, this.centerOnly = false, })` | Construye _ResponsiveButtonGroup. |
| 475 | método | _ResponsiveButtonGroup | `@override Widget build(BuildContext context)` | Construye la interfaz de _ResponsiveButtonGroup. |
## `lib/gui/component/mifare/ultralight.dart`

| Línea | Tipo | Owner | Firma | Descripción |
|---:|---|---|---|---|
| 24 | constructor | MifareUltralightHelper | `const MifareUltralightHelper({ super.key, required this.hfInfo, this.allowSave = true, })` | Construye MifareUltralightHelper. |
| 30 | método | MifareUltralightHelper | `@override State<StatefulWidget> createState()` | Operación `createState`. |
| 46 | método | CardReaderState | `Future<void> readCard({bool withPassword = false})` | Operación `readCard`. |
| 136 | método | CardReaderState | `Future<void> saveCard({bool bin = false})` | Operación `saveCard`. |
| 183 | método | CardReaderState | `@override Widget build(BuildContext context)` | Construye la interfaz de CardReaderState. |
## `lib/gui/component/qrcode_scanner.dart`

| Línea | Tipo | Owner | Firma | Descripción |
|---:|---|---|---|---|
| 8 | constructor | QrCodeScanner | `const QrCodeScanner({super.key})` | Construye QrCodeScanner. |
| 10 | método | QrCodeScanner | `@override State<StatefulWidget> createState()` | Operación `createState`. |
| 19 | método | QrCodeScannerState | `@override Widget build(BuildContext context)` | Construye la interfaz de QrCodeScannerState. |
## `lib/gui/component/qrcode_viewer.dart`

| Línea | Tipo | Owner | Firma | Descripción |
|---:|---|---|---|---|
| 7 | función | - | `List<String> splitStringIntoQrChunks(String str, int chunkSize)` | Función `splitStringIntoQrChunks`. |
| 20 | constructor | QrCodeViewer | `const QrCodeViewer( {required this.qrChunks, this.errorCorrection = 0, super.key})` | Construye QrCodeViewer. |
| 23 | método | QrCodeViewer | `@override QrCodeViewerState createState()` | Operación `createState`. |
| 30 | método | QrCodeViewerState | `@override Widget build(BuildContext context)` | Construye la interfaz de QrCodeViewerState. |
## `lib/gui/component/relay_assessment.dart`

| Línea | Tipo | Owner | Firma | Descripción |
|---:|---|---|---|---|
| 9 | función | - | `Widget relayAssessmentCard(BuildContext context, EmvAip? aip, {String? aid})` | Función `relayAssessmentCard`. |
## `lib/gui/component/slot_changer.dart`

| Línea | Tipo | Owner | Firma | Descripción |
|---:|---|---|---|---|
| 8 | constructor | SlotChanger | `const SlotChanger({super.key})` | Construye SlotChanger. |
| 10 | método | SlotChanger | `@override SlotChangerState createState()` | Operación `createState`. |
| 17 | método | SlotChangerState | `@override void initState()` | Inicializa el estado de SlotChangerState. |
| 22 | método | SlotChangerState | `Future<List<Icon>> getFutureData()` | Operación `getFutureData`. |
| 35 | método | SlotChangerState | `Future<List<Icon>> getSlotIcons(List<SlotTypes> usedSlots)` | Operación `getSlotIcons`. |
| 75 | método | SlotChangerState | `@override Widget build(BuildContext context)` | Construye la interfaz de SlotChangerState. |
## `lib/gui/component/status_badge.dart`

| Línea | Tipo | Owner | Firma | Descripción |
|---:|---|---|---|---|
| 10 | constructor | StatusBadge | `const StatusBadge(this.text, {super.key})` | Construye StatusBadge. |
| 12 | método | StatusBadge | `@override Widget build(BuildContext context)` | Construye la interfaz de StatusBadge. |
## `lib/gui/component/toggle_buttons.dart`

| Línea | Tipo | Owner | Firma | Descripción |
|---:|---|---|---|---|
| 8 | constructor | ToggleButtonsWrapper | `const ToggleButtonsWrapper( {super.key, required this.items, required this.selectedValue, required this.onChange})` | Construye ToggleButtonsWrapper. |
| 14 | método | ToggleButtonsWrapper | `@override ToggleButtonsState createState()` | Operación `createState`. |
| 22 | método | ToggleButtonsState | `@override void initState()` | Inicializa el estado de ToggleButtonsState. |
| 33 | método | ToggleButtonsState | `@override Widget build(BuildContext context)` | Construye la interfaz de ToggleButtonsState. |
## `lib/gui/menu/dialogs/card/create.dart`

| Línea | Tipo | Owner | Firma | Descripción |
|---:|---|---|---|---|
| 17 | constructor | CardCreateMenu | `const CardCreateMenu({super.key})` | Construye CardCreateMenu. |
| 19 | método | CardCreateMenu | `@override CardCreateMenuState createState()` | Operación `createState`. |
| 43 | método | CardCreateMenuState | `List<Uint8List> generateMifareClassicBlocks()` | Operación `generateMifareClassicBlocks`. |
| 93 | método | CardCreateMenuState | `List<Uint8List> generateMifareUltralightBlocks()` | Operación `generateMifareUltralightBlocks`. |
| 116 | método | CardCreateMenuState | `@override Widget build(BuildContext context)` | Construye la interfaz de CardCreateMenuState. |
## `lib/gui/menu/dialogs/card/edit.dart`

| Línea | Tipo | Owner | Firma | Descripción |
|---:|---|---|---|---|
| 20 | constructor | CardEditMenu | `const CardEditMenu({super.key, required this.tagSave, this.isNew = false})` | Construye CardEditMenu. |
| 22 | método | CardEditMenu | `@override CardEditMenuState createState()` | Operación `createState`. |
| 51 | método | CardEditMenuState | `@override void initState()` | Inicializa el estado de CardEditMenuState. |
| 81 | método | CardEditMenuState | `bool hasDataChanged()` | Operación `hasDataChanged`. |
| 87 | método | CardEditMenuState | `Future<bool> showUpdateDataDialog(BuildContext context)` | Operación `showUpdateDataDialog`. |
| 112 | método | CardEditMenuState | `List<Uint8List> updateSavedCardData({ required TagType selectedType, required String uid, required String sak, required String atqa, required List<Uint8List> originalData, })` | Operación `updateSavedCardData`. |
| 145 | método | CardEditMenuState | `bool canUpdateSavedCardData(CardSave tagSave, TagType selectedType)` | Operación `canUpdateSavedCardData`. |
| 153 | método | CardEditMenuState | `void initCounterControllers()` | Operación `initCounterControllers`. |
| 169 | método | CardEditMenuState | `void initHIDFields()` | Operación `initHIDFields`. |
| 178 | método | CardEditMenuState | `@override Widget build(BuildContext context)` | Construye la interfaz de CardEditMenuState. |
## `lib/gui/menu/dialogs/card/view.dart`

| Línea | Tipo | Owner | Firma | Descripción |
|---:|---|---|---|---|
| 22 | constructor | CardViewMenu | `const CardViewMenu({super.key, required this.tagSave})` | Construye CardViewMenu. |
| 24 | método | CardViewMenu | `@override CardViewMenuState createState()` | Operación `createState`. |
| 32 | método | CardViewMenuState | `@override void initState()` | Inicializa el estado de CardViewMenuState. |
| 47 | método | CardViewMenuState | `void _refreshCardData()` | Operación `_refreshCardData`. |
| 67 | método | CardViewMenuState | `@override Widget build(BuildContext context)` | Construye la interfaz de CardViewMenuState. |
## `lib/gui/menu/dialogs/chameleon_settings.dart`

| Línea | Tipo | Owner | Firma | Descripción |
|---:|---|---|---|---|
| 17 | constructor | ChameleonSettings | `const ChameleonSettings({super.key})` | Construye ChameleonSettings. |
| 19 | método | ChameleonSettings | `@override ChameleonSettingsState createState()` | Operación `createState`. |
| 26 | método | ChameleonSettingsState | `@override void initState()` | Inicializa el estado de ChameleonSettingsState. |
| 32 | método | ChameleonSettingsState | `Future<DeviceSettings> getSettingsData()` | Operación `getSettingsData`. |
| 41 | método | ChameleonSettingsState | `@override Widget build(BuildContext context)` | Construye la interfaz de ChameleonSettingsState. |
## `lib/gui/menu/dialogs/confirm_delete.dart`

| Línea | Tipo | Owner | Firma | Descripción |
|---:|---|---|---|---|
| 9 | constructor | ConfirmDeletionMenu | `const ConfirmDeletionMenu({super.key, required this.thingBeingDeleted})` | Construye ConfirmDeletionMenu. |
| 11 | método | ConfirmDeletionMenu | `@override ConfirmDeletionMenuState createState()` | Operación `createState`. |
| 16 | método | ConfirmDeletionMenuState | `@override Widget build(BuildContext context)` | Construye la interfaz de ConfirmDeletionMenuState. |
## `lib/gui/menu/dialogs/dictionary/edit.dart`

| Línea | Tipo | Owner | Firma | Descripción |
|---:|---|---|---|---|
| 16 | constructor | DictionaryEditMenu | `const DictionaryEditMenu({ super.key, required this.dictionary, this.isNew = false, })` | Construye DictionaryEditMenu. |
| 22 | método | DictionaryEditMenu | `@override DictionaryEditMenuState createState()` | Operación `createState`. |
| 33 | método | DictionaryEditMenuState | `@override void initState()` | Inicializa el estado de DictionaryEditMenuState. |
| 42 | método | DictionaryEditMenuState | `@override Widget build(BuildContext context)` | Construye la interfaz de DictionaryEditMenuState. |
## `lib/gui/menu/dialogs/dictionary/export.dart`

| Línea | Tipo | Owner | Firma | Descripción |
|---:|---|---|---|---|
| 18 | constructor | DictionaryExportMenu | `const DictionaryExportMenu({ super.key, this.defaultName = "", required this.keys, })` | Construye DictionaryExportMenu. |
| 24 | método | DictionaryExportMenu | `@override DictionaryExportMenuState createState()` | Operación `createState`. |
| 29 | método | DictionaryExportMenuState | `List<Uint8List> deduplicateKeys(List<Uint8List> keys)` | Operación `deduplicateKeys`. |
| 37 | método | DictionaryExportMenuState | `String convertKeysToDictionaryFile(List<Uint8List> keys)` | Operación `convertKeysToDictionaryFile`. |
| 48 | método | DictionaryExportMenuState | `Future<String?> dictionarySelectDialog( BuildContext context, List<Uint8List> keys, )` | Operación `dictionarySelectDialog`. |
| 63 | método | DictionaryExportMenuState | `Future<String> getDictionaryName()` | Operación `getDictionaryName`. |
| 101 | método | DictionaryExportMenuState | `@override Widget build(BuildContext context)` | Construye la interfaz de DictionaryExportMenuState. |
| 187 | constructor | DictSearchDelegate | `DictSearchDelegate(this.dicts, this.keys)` | Construye DictSearchDelegate. |
| 191 | método | DictSearchDelegate | `Future<void> _mergeInto(BuildContext context, Dictionary dict)` | Operación `_mergeInto`. |
| 203 | método | DictSearchDelegate | `@override List<Widget> buildActions(BuildContext context)` | Operación `buildActions`. |
| 215 | método | DictSearchDelegate | `@override Widget buildLeading(BuildContext context)` | Operación `buildLeading`. |
| 225 | método | DictSearchDelegate | `@override Widget buildResults(BuildContext context)` | Operación `buildResults`. |
| 245 | método | DictSearchDelegate | `@override Widget buildSuggestions(BuildContext context)` | Operación `buildSuggestions`. |
## `lib/gui/menu/dialogs/dictionary/view.dart`

| Línea | Tipo | Owner | Firma | Descripción |
|---:|---|---|---|---|
| 15 | constructor | DictionaryViewMenu | `const DictionaryViewMenu({super.key, required this.dictionary})` | Construye DictionaryViewMenu. |
| 17 | método | DictionaryViewMenu | `@override DictionaryViewMenuState createState()` | Operación `createState`. |
| 25 | método | DictionaryViewMenuState | `@override void initState()` | Inicializa el estado de DictionaryViewMenuState. |
| 32 | método | DictionaryViewMenuState | `void _refreshDictionaryData()` | Operación `_refreshDictionaryData`. |
| 44 | método | DictionaryViewMenuState | `@override void dispose()` | Libera recursos de DictionaryViewMenuState. |
| 50 | método | DictionaryViewMenuState | `@override Widget build(BuildContext context)` | Construye la interfaz de DictionaryViewMenuState. |
## `lib/gui/menu/dialogs/manual_connect.dart`

| Línea | Tipo | Owner | Firma | Descripción |
|---:|---|---|---|---|
| 10 | constructor | ManualConnect | `const ManualConnect({super.key})` | Construye ManualConnect. |
| 12 | método | ManualConnect | `@override State<ManualConnect> createState()` | Operación `createState`. |
| 20 | método | ManualConnectState | `@override Widget build(BuildContext context)` | Construye la interfaz de ManualConnectState. |
## `lib/gui/menu/dialogs/qr/import.dart`

| Línea | Tipo | Owner | Firma | Descripción |
|---:|---|---|---|---|
| 10 | constructor | QrCodeImport | `const QrCodeImport({super.key})` | Construye QrCodeImport. |
| 12 | método | QrCodeImport | `@override State<StatefulWidget> createState()` | Operación `createState`. |
| 24 | getter | QrCodeImportState | `int get currentChunk` | Obtiene `currentChunk`. |
| 25 | getter | QrCodeImportState | `String get resultingJson` | Obtiene `resultingJson`. |
| 26 | getter | QrCodeImportState | `bool get checksumMatches` | Obtiene `checksumMatches`. |
| 29 | getter | QrCodeImportState | `bool get isComplete` | Obtiene `isComplete`. |
| 32 | método | QrCodeImportState | `@override Widget build(BuildContext context)` | Construye la interfaz de QrCodeImportState. |
## `lib/gui/menu/dialogs/qr/settings.dart`

| Línea | Tipo | Owner | Firma | Descripción |
|---:|---|---|---|---|
| 9 | constructor | QRCodeSettings | `const QRCodeSettings({super.key})` | Construye QRCodeSettings. |
| 11 | método | QRCodeSettings | `@override QRCodeSettingsState createState()` | Operación `createState`. |
| 22 | método | QRCodeSettingsState | `@override Widget build(BuildContext context)` | Construye la interfaz de QRCodeSettingsState. |
## `lib/gui/menu/dialogs/slot/edit.dart`

| Línea | Tipo | Owner | Firma | Descripción |
|---:|---|---|---|---|
| 25 | constructor | SlotEditMenu | `const SlotEditMenu( {super.key, required this.name, required this.isEnabled, required this.slotType, required this.frequency, required this.slot, required this.update})` | Construye SlotEditMenu. |
| 34 | método | SlotEditMenu | `@override SlotEditMenuState createState()` | Operación `createState`. |
| 61 | método | SlotEditMenuState | `@override void initState()` | Inicializa el estado de SlotEditMenuState. |
| 68 | método | SlotEditMenuState | `String getMf1PrngLabel(Mf1PrngType type, AppLocalizations localizations)` | Operación `getMf1PrngLabel`. |
| 79 | método | SlotEditMenuState | `Future<void> updateInfo()` | Operación `updateInfo`. |
| 190 | método | SlotEditMenuState | `Future<void> save()` | Operación `save`. |
| 278 | método | SlotEditMenuState | `@override Widget build(BuildContext context)` | Construye la interfaz de SlotEditMenuState. |
## `lib/gui/menu/dialogs/slot/export.dart`

| Línea | Tipo | Owner | Firma | Descripción |
|---:|---|---|---|---|
| 25 | constructor | SlotExportMenu | `const SlotExportMenu({ super.key, required this.slot, required this.names, required this.enabledSlotInfo, required this.slotTypes, })` | Construye SlotExportMenu. |
| 33 | método | SlotExportMenu | `@override SlotExportMenuState createState()` | Operación `createState`. |
| 40 | método | SlotExportMenuState | `Future<CardSave?> rebuildCardSaveFromSlot(TagFrequency frequency)` | Operación `rebuildCardSaveFromSlot`. |
| 200 | método | SlotExportMenuState | `Future<void> onTap( CardSave card, dynamic close, AppLocalizations localizations, )` | Operación `onTap`. |
| 239 | método | SlotExportMenuState | `@override Widget build(BuildContext context)` | Construye la interfaz de SlotExportMenuState. |
## `lib/gui/menu/dialogs/slot/settings.dart`

| Línea | Tipo | Owner | Firma | Descripción |
|---:|---|---|---|---|
| 17 | constructor | SlotSettings | `const SlotSettings({super.key, required this.slot, required this.refresh})` | Construye SlotSettings. |
| 19 | método | SlotSettings | `@override SlotSettingsState createState()` | Operación `createState`. |
| 29 | método | SlotSettingsState | `@override void initState()` | Inicializa el estado de SlotSettingsState. |
| 34 | método | SlotSettingsState | `Future<void> fetchInfo()` | Operación `fetchInfo`. |
| 71 | método | SlotSettingsState | `void updateSlot(String name, TagFrequency frequency, TagType type)` | Operación `updateSlot`. |
| 85 | método | SlotSettingsState | `@override Widget build(BuildContext context)` | Construye la interfaz de SlotSettingsState. |
## `lib/gui/menu/hacking/apdu_terminal.dart`

| Línea | Tipo | Owner | Firma | Descripción |
|---:|---|---|---|---|
| 15 | constructor | ApduTerminalPage | `const ApduTerminalPage({super.key})` | Construye ApduTerminalPage. |
| 17 | método | ApduTerminalPage | `@override ApduTerminalPageState createState()` | Operación `createState`. |
| 31 | getter | ApduTerminalPageState | `ChameleonGUIState get _app` | Obtiene `_app`. |
| 32 | getter | ApduTerminalPageState | `bool get _connected` | Obtiene `_connected`. |
| 34 | método | ApduTerminalPageState | `@override void dispose()` | Libera recursos de ApduTerminalPageState. |
| 40 | método | ApduTerminalPageState | `Future<void> _send()` | Operación `_send`. |
| 77 | método | ApduTerminalPageState | `Widget _tlvRow(EmvTlv t)` | Operación `_tlvRow`. |
| 100 | método | ApduTerminalPageState | `@override Widget build(BuildContext context)` | Construye la interfaz de ApduTerminalPageState. |
## `lib/gui/menu/hacking/auth_trace.dart`

| Línea | Tipo | Owner | Firma | Descripción |
|---:|---|---|---|---|
| 15 | constructor | AuthTracePage | `const AuthTracePage({super.key})` | Construye AuthTracePage. |
| 17 | método | AuthTracePage | `@override AuthTracePageState createState()` | Operación `createState`. |
| 29 | getter | AuthTracePageState | `ChameleonGUIState get _app` | Obtiene `_app`. |
| 30 | getter | AuthTracePageState | `bool get _connected` | Obtiene `_connected`. |
| 32 | método | AuthTracePageState | `@override void dispose()` | Libera recursos de AuthTracePageState. |
| 39 | método | AuthTracePageState | `Future<void> _run()` | Operación `_run`. |
| 72 | método | AuthTracePageState | `@override Widget build(BuildContext context)` | Construye la interfaz de AuthTracePageState. |
## `lib/gui/menu/hacking/authorized_relay_lab.dart`

| Línea | Tipo | Owner | Firma | Descripción |
|---:|---|---|---|---|
| 16 | constructor | AuthorizedRelayLabPage | `const AuthorizedRelayLabPage({super.key})` | Construye AuthorizedRelayLabPage. |
| 18 | método | AuthorizedRelayLabPage | `@override State<AuthorizedRelayLabPage> createState()` | Operación `createState`. |
| 80 | getter | _AuthorizedRelayLabPageState | `bool get _connected` | Obtiene `_connected`. |
| 83 | getter | _AuthorizedRelayLabPageState | `bool get _prepared` | Obtiene `_prepared`. |
| 85 | getter | _AuthorizedRelayLabPageState | `bool get _armActive` | Obtiene `_armActive`. |
| 87 | getter | _AuthorizedRelayLabPageState | `bool get _backendApduInFlight` | Obtiene `_backendApduInFlight`. |
| 89 | getter | _AuthorizedRelayLabPageState | `String get _backendModeLabel` | Obtiene `_backendModeLabel`. |
| 94 | método | _AuthorizedRelayLabPageState | `ChameleonCommand _startCommand(AuthorizedRelayBackendMode mode)` | Operación `_startCommand`. |
| 97 | método | _AuthorizedRelayLabPageState | `Future<IsoDepReaderSessionInfo> _startBackendSession( ChameleonCommunicator communicator, AuthorizedRelayBackendMode mode, )` | Operación `_startBackendSession`. |
| 107 | getter | _AuthorizedRelayLabPageState | `String? get _relayStateLabel` | Obtiene `_relayStateLabel`. |
| 121 | método | _AuthorizedRelayLabPageState | `@override void initState()` | Inicializa el estado de _AuthorizedRelayLabPageState. |
| 140 | método | _AuthorizedRelayLabPageState | `@override void didChangeDependencies()` | Operación `didChangeDependencies`. |
| 158 | método | _AuthorizedRelayLabPageState | `@override void didChangeAppLifecycleState(AppLifecycleState state)` | Operación `didChangeAppLifecycleState`. |
| 178 | método | _AuthorizedRelayLabPageState | `void _onAppStateChanged()` | Operación `_onAppStateChanged`. |
| 210 | método | _AuthorizedRelayLabPageState | `@override void dispose()` | Libera recursos de _AuthorizedRelayLabPageState. |
| 221 | método | _AuthorizedRelayLabPageState | `Future<void> _refreshReadiness()` | Operación `_refreshReadiness`. |
| 230 | método | _AuthorizedRelayLabPageState | `Future<void> _setBackendMode(AuthorizedRelayBackendMode mode)` | Operación `_setBackendMode`. |
| 281 | método | _AuthorizedRelayLabPageState | `Future<void> _prepare()` | Adquiere automáticamente el backend para Arm. |
| 526 | método | _AuthorizedRelayLabPageState | `void _cancelCardWait()` | Operación `_cancelCardWait`. |
| 534 | método | _AuthorizedRelayLabPageState | `Future<void> _openPaymentSettings()` | Operación `_openPaymentSettings`. |
| 556 | método | _AuthorizedRelayLabPageState | `Future<void> _arm()` | Operación `_arm`. |
| 697 | método | _AuthorizedRelayLabPageState | `Future<void> _requireRelayCapabilities( ChameleonCommunicator communicator, AuthorizedRelayBackendMode mode, )` | Operación `_requireRelayCapabilities`. |
| 715 | método | _AuthorizedRelayLabPageState | `Future<void> _setArmed(bool value)` | Adquiere backend y arma HCE sin review previo. |
| 727 | método | _AuthorizedRelayLabPageState | `Future<void> _handlePlatformEvent(AuthorizedRelayEvent event)` | Operación `_handlePlatformEvent`. |
| 788 | método | _AuthorizedRelayLabPageState | `Future<void> _tryExchange(int generation, int token)` | Operación `_tryExchange`. |
| 989 | método | _AuthorizedRelayLabPageState | `Future<void> _disarm({ String? message, String? notice, bool updateUi = true, })` | Desarma sin eliminar AID persistentes. |
| 1100 | método | _AuthorizedRelayLabPageState | `bool _isCurrentArm( int generation, int token, ChameleonCommunicator communicator, )` | Operación `_isCurrentArm`. |
| 1114 | método | _AuthorizedRelayLabPageState | `void _ensureArmCurrent( int generation, int token, ChameleonCommunicator communicator, )` | Operación `_ensureArmCurrent`. |
| 1124 | método | _AuthorizedRelayLabPageState | `void _ensurePreparedCurrent( AuthorizedRelaySessionCapability< _AuthorizedRelayBackend, ChameleonCommunicator > capability, int generation, ChameleonCommunicator communicator, AuthorizedRelayBackendMode mode, AuthorizedRelayConnectionCoordinator coordinator, )` | Operación `_ensurePreparedCurrent`. |
| 1154 | método | _AuthorizedRelayLabPageState | `void _poisonConnection(ChameleonCommunicator communicator, String reason)` | Operación `_poisonConnection`. |
| 1160 | método | _AuthorizedRelayLabPageState | `Future<void> _pauseMonitor()` | Operación `_pauseMonitor`. |
| 1166 | método | _AuthorizedRelayLabPageState | `void _resumeMonitor()` | Operación `_resumeMonitor`. |
| 1172 | método | _AuthorizedRelayLabPageState | `void _ensureCurrentOperation(int generation)` | Operación `_ensureCurrentOperation`. |
| 1178 | método | _AuthorizedRelayLabPageState | `Future<void> _copyDebugLog()` | Operación `_copyDebugLog`. |
| 1243 | método | _AuthorizedRelayLabPageState | `@override Widget build(BuildContext context)` | Construye la interfaz de _AuthorizedRelayLabPageState. |
| 1504 | método | _AuthorizedRelayLabPageState | `Widget _statusRow(String label, bool ready)` | Operación `_statusRow`. |
| 1518 | constructor | _AuthorizedRelayRecord | `const _AuthorizedRelayRecord({ required this.armToken, required this.requestId, required this.receivedUs, required this.expiresAtUs, required this.backendSessionId, required this.terminalBudgetUs, required this.backendMode, required this.command, required this.status, required this.elapsedUs, required this.backendExchangeUs, required this.nativeDeliveryUs, required this.delivered, required this.syntheticFallback, required this.prefetchedBackendResponse, required this.deviceStatus, required this.isoDepError, required this.rfStatus, required this.wtxCount, required this.firmwareSessionClosed, required this.transitRewrite, required this.transitPolicyFailure, required this.error, })` | Construye _AuthorizedRelayRecord. |
| 1568 | método | _AuthorizedRelayRecord | `Map<String, Object?> toJson()` | Serializa _AuthorizedRelayRecord. |
| 1599 | constructor | _AuthorizedRelayBackend | `_AuthorizedRelayBackend( this.communicator, this.session, this.mode, { this._prefetchedResponse, }) : policy = AuthorizedRelaySessionPolicy(mode: mode)` | Construye _AuthorizedRelayBackend. |
| 1613 | método | _AuthorizedRelayBackend | `Uint8List? takePrefetchedResponse(Uint8List command)` | Operación `takePrefetchedResponse`. |
| 1618 | constructor | _RelayOperationCancelled | `const _RelayOperationCancelled()` | Construye _RelayOperationCancelled. |
| 1622 | constructor | _RelayReconnectRequired | `const _RelayReconnectRequired(this.message)` | Construye _RelayReconnectRequired. |
| 1628 | constructor | _RelayPolicyRejected | `const _RelayPolicyRejected(this.failure)` | Construye _RelayPolicyRejected. |
| 1632 | método | _RelayPolicyRejected | `@override String toString()` | Operación `toString`. |
## `lib/gui/menu/hacking/autopwn.dart`

| Línea | Tipo | Owner | Firma | Descripción |
|---:|---|---|---|---|
| 22 | constructor | AutopwnPage | `const AutopwnPage({super.key, this.dictionaryOnly = false})` | Construye AutopwnPage. |
| 24 | método | AutopwnPage | `@override AutopwnPageState createState()` | Operación `createState`. |
| 39 | método | AutopwnPageState | `@override void didChangeDependencies()` | Operación `didChangeDependencies`. |
| 53 | método | AutopwnPageState | `@override void dispose()` | Libera recursos de AutopwnPageState. |
| 59 | método | AutopwnPageState | `void _refresh()` | Operación `_refresh`. |
| 63 | método | AutopwnPageState | `Future<void> _run()` | Operación `_run`. |
| 112 | getter | AutopwnPageState | `bool get _hasAnyKey` | Obtiene `_hasAnyKey`. |
| 115 | método | AutopwnPageState | `@override Widget build(BuildContext context)` | Construye la interfaz de AutopwnPageState. |
## `lib/gui/menu/hacking/autopwn_plus.dart`

| Línea | Tipo | Owner | Firma | Descripción |
|---:|---|---|---|---|
| 23 | constructor | AutopwnPlusPage | `const AutopwnPlusPage({super.key})` | Construye AutopwnPlusPage. |
| 25 | método | AutopwnPlusPage | `@override State<AutopwnPlusPage> createState()` | Operación `createState`. |
| 50 | método | _AutopwnPlusPageState | `@override void didChangeDependencies()` | Operación `didChangeDependencies`. |
| 61 | método | _AutopwnPlusPageState | `@override void dispose()` | Libera recursos de _AutopwnPlusPageState. |
| 68 | método | _AutopwnPlusPageState | `void _refreshRecovery()` | Operación `_refreshRecovery`. |
| 72 | método | _AutopwnPlusPageState | `Future<void> _scan()` | Operación `_scan`. |
| 112 | getter | _AutopwnPlusPageState | `Set<int> get _selectedSectors` | Obtiene `_selectedSectors`. |
| 120 | getter | _AutopwnPlusPageState | `List<Dictionary> get _selectedDictionaries` | Obtiene `_selectedDictionaries`. |
| 127 | método | _AutopwnPlusPageState | `Future<bool> _sameCardStillPresent()` | Operación `_sameCardStillPresent`. |
| 143 | método | _AutopwnPlusPageState | `Future<void> _run()` | Operación `_run`. |
| 197 | método | _AutopwnPlusPageState | `void _cancel()` | Operación `_cancel`. |
| 209 | método | _AutopwnPlusPageState | `Future<void> _exportResult()` | Operación `_exportResult`. |
| 224 | getter | _AutopwnPlusPageState | `String get _strategySummary` | Obtiene `_strategySummary`. |
| 238 | getter | _AutopwnPlusPageState | `String get _nestedDurationHint` | Obtiene `_nestedDurationHint`. |
| 251 | método | _AutopwnPlusPageState | `String _formatDuration(Duration duration)` | Operación `_formatDuration`. |
| 259 | método | _AutopwnPlusPageState | `Widget _profileSelector()` | Operación `_profileSelector`. |
| 288 | método | _AutopwnPlusPageState | `Widget _configurationCard()` | Operación `_configurationCard`. |
| 389 | método | _AutopwnPlusPageState | `Widget _progressCard()` | Operación `_progressCard`. |
| 436 | método | _AutopwnPlusPageState | `Widget _resultCard()` | Operación `_resultCard`. |
| 500 | método | _AutopwnPlusPageState | `@override Widget build(BuildContext context)` | Construye la interfaz de _AutopwnPlusPageState. |
## `lib/gui/menu/hacking/backdoor.dart`

| Línea | Tipo | Owner | Firma | Descripción |
|---:|---|---|---|---|
| 17 | constructor | BackdoorPage | `const BackdoorPage({super.key})` | Construye BackdoorPage. |
| 19 | método | BackdoorPage | `@override BackdoorPageState createState()` | Operación `createState`. |
| 28 | método | BackdoorPageState | `void _refresh()` | Operación `_refresh`. |
| 32 | método | BackdoorPageState | `Future<void> _run()` | Operación `_run`. |
| 59 | getter | BackdoorPageState | `bool get _hasAnyKey` | Obtiene `_hasAnyKey`. |
| 62 | método | BackdoorPageState | `@override Widget build(BuildContext context)` | Construye la interfaz de BackdoorPageState. |
## `lib/gui/menu/hacking/ble_advertising_lab.dart`

| Línea | Tipo | Owner | Firma | Descripción |
|---:|---|---|---|---|
| 19 | constructor | BleAdvertisingLabPage | `const BleAdvertisingLabPage({super.key, this.embedded = false})` | Construye BleAdvertisingLabPage. |
| 21 | método | BleAdvertisingLabPage | `@override State<BleAdvertisingLabPage> createState()` | Operación `createState`. |
| 53 | getter | _BleAdvertisingLabPageState | `ChameleonGUIState get _app` | Obtiene `_app`. |
| 54 | getter | _BleAdvertisingLabPageState | `ChameleonCommunicator get _device` | Obtiene `_device`. |
| 55 | getter | _BleAdvertisingLabPageState | `bool get _usingBle` | Obtiene `_usingBle`. |
| 57 | método | _BleAdvertisingLabPageState | `@override void dispose()` | Libera recursos de _BleAdvertisingLabPageState. |
| 79 | método | _BleAdvertisingLabPageState | `int _integer(String value, String field)` | Operación `_integer`. |
| 89 | método | _BleAdvertisingLabPageState | `int? _optionalInteger(String value, String field)` | Operación `_optionalInteger`. |
| 92 | método | _BleAdvertisingLabPageState | `List<String> _nameList()` | Operación `_nameList`. |
| 100 | método | _BleAdvertisingLabPageState | `void _applyTemplate(_AdvertisingLabTemplate template)` | Operación `_applyTemplate`. |
| 126 | método | _BleAdvertisingLabPageState | `BleAdvertisingLabConfig _config()` | Operación `_config`. |
| 177 | método | _BleAdvertisingLabPageState | `Future<void> _refresh()` | Operación `_refresh`. |
| 196 | método | _BleAdvertisingLabPageState | `Future<void> _start()` | Operación `_start`. |
| 221 | método | _BleAdvertisingLabPageState | `Future<void> _stop()` | Operación `_stop`. |
| 245 | método | _BleAdvertisingLabPageState | `String _stateLabel(AppLocalizations localizations)` | Operación `_stateLabel`. |
| 253 | método | _BleAdvertisingLabPageState | `String _reasonLabel(AppLocalizations localizations)` | Operación `_reasonLabel`. |
| 263 | método | _BleAdvertisingLabPageState | `Widget _numberField(TextEditingController controller, String label, {double width = 220})` | Operación `_numberField`. |
| 281 | método | _BleAdvertisingLabPageState | `Widget _editor(AppLocalizations localizations)` | Operación `_editor`. |
| 561 | método | _BleAdvertisingLabPageState | `Widget _preview(AppLocalizations localizations)` | Operación `_preview`. |
| 581 | método | _BleAdvertisingLabPageState | `Widget _statusCard(AppLocalizations localizations)` | Operación `_statusCard`. |
| 599 | método | _BleAdvertisingLabPageState | `@override Widget build(BuildContext context)` | Construye la interfaz de _BleAdvertisingLabPageState. |
## `lib/gui/menu/hacking/ble_app.dart`

| Línea | Tipo | Owner | Firma | Descripción |
|---:|---|---|---|---|
| 21 | constructor | BleAppPage | `const BleAppPage({ super.key, required this.auditTab, required this.radioIdentityTab, required this.advertisingLabTab, required this.stressBroadcastTab, })` | Construye BleAppPage. |
| 29 | método | BleAppPage | `@override State<BleAppPage> createState()` | Operación `createState`. |
| 37 | método | _BleAppPageState | `@override void initState()` | Inicializa el estado de _BleAppPageState. |
| 43 | método | _BleAppPageState | `@override void dispose()` | Libera recursos de _BleAppPageState. |
| 49 | método | _BleAppPageState | `@override Widget build(BuildContext context)` | Construye la interfaz de _BleAppPageState. |
## `lib/gui/menu/hacking/ble_audit.dart`

| Línea | Tipo | Owner | Firma | Descripción |
|---:|---|---|---|---|
| 30 | constructor | BleAuditPage | `const BleAuditPage({super.key, this.embedded = false})` | Construye BleAuditPage. |
| 32 | método | BleAuditPage | `@override BleAuditPageState createState()` | Operación `createState`. |
| 73 | getter | BleAuditPageState | `bool get _connected` | Obtiene `_connected`. |
| 74 | método | BleAuditPageState | `bool _supportsCommands(List<ChameleonCommand> commands)` | Operación `_supportsCommands`. |
| 81 | método | BleAuditPageState | `@override void didChangeDependencies()` | Operación `didChangeDependencies`. |
| 87 | método | BleAuditPageState | `@override void initState()` | Inicializa el estado de BleAuditPageState. |
| 102 | método | BleAuditPageState | `@override void dispose()` | Libera recursos de BleAuditPageState. |
| 130 | método | BleAuditPageState | `Future<void> _cleanupDisposedRoute( ChameleonCommunicator communicator, int? cccd)` | Operación `_cleanupDisposedRoute`. |
| 140 | método | BleAuditPageState | `Future<void> _bestEffortStopDeviceActivity(ChameleonCommunicator communicator, {required bool stopScan, required bool stopFuzz, required int? cccd})` | Operación `_bestEffortStopDeviceActivity`. |
| 161 | método | BleAuditPageState | `void _clearLocalActivity({bool clearCentralState = false})` | Operación `_clearLocalActivity`. |
| 179 | método | BleAuditPageState | `Future<void> _runScan()` | Operación `_runScan`. |
| 208 | método | BleAuditPageState | `List<BleScanResult> _visibleResults()` | Operación `_visibleResults`. |
| 221 | método | BleAuditPageState | `void _useAsTarget(BleScanResult r)` | Operación `_useAsTarget`. |
| 232 | método | BleAuditPageState | `String _localizedAdvertisingDetail( AppLocalizations localizations, String detail)` | Operación `_localizedAdvertisingDetail`. |
| 266 | método | BleAuditPageState | `void _showDeviceDetails(BleScanResult r)` | Operación `_showDeviceDetails`. |
| 316 | método | BleAuditPageState | `Future<void> _refreshState()` | Operación `_refreshState`. |
| 342 | método | BleAuditPageState | `Future<void> _toggleAdvertising()` | Operación `_toggleAdvertising`. |
| 360 | método | BleAuditPageState | `Future<void> _probeLink({bool globalMode = false})` | Operación `_probeLink`. |
| 416 | método | BleAuditPageState | `Future<void> _connect()` | Operación `_connect`. |
| 450 | método | BleAuditPageState | `Future<void> _discover()` | Operación `_discover`. |
| 501 | método | BleAuditPageState | `Future<void> _readChar(int handle)` | Operación `_readChar`. |
| 528 | método | BleAuditPageState | `Future<void> _writeChar(BleCharacteristic c)` | Operación `_writeChar`. |
| 589 | método | BleAuditPageState | `Future<void> _showDescriptors()` | Operación `_showDescriptors`. |
| 640 | método | BleAuditPageState | `String _localizedDeviceInfoValue( AppLocalizations localizations, int uuid, int status, Uint8List data)` | Operación `_localizedDeviceInfoValue`. |
| 650 | método | BleAuditPageState | `Future<void> _showDeviceInfo()` | Operación `_showDeviceInfo`. |
| 697 | método | BleAuditPageState | `Future<void> _toggleNotify(BleCharacteristic c)` | Operación `_toggleNotify`. |
| 779 | método | BleAuditPageState | `Future<void> _startFuzz()` | Operación `_startFuzz`. |
| 865 | método | BleAuditPageState | `Future<void> _finishFuzz( {required bool stopDevice, bool disconnect = true})` | Operación `_finishFuzz`. |
| 884 | método | BleAuditPageState | `Future<void> _stopFuzz()` | Operación `_stopFuzz`. |
| 890 | método | BleAuditPageState | `Future<void> _disconnect({bool stopFuzz = true})` | Operación `_disconnect`. |
| 931 | método | BleAuditPageState | `@override Widget build(BuildContext context)` | Construye la interfaz de BleAuditPageState. |
| 1022 | método | BleAuditPageState | `Widget _scanTab(BuildContext context)` | Operación `_scanTab`. |
| 1156 | método | BleAuditPageState | `Widget _fuzzTab(BuildContext context)` | Operación `_fuzzTab`. |
## `lib/gui/menu/hacking/ble_audit_status.dart`

| Línea | Tipo | Owner | Firma | Descripción |
|---:|---|---|---|---|
| 9 | constructor | BleAuditStatus | `const BleAuditStatus({ super.key, required this.state, required this.mtu, })` | Construye BleAuditStatus. |
| 15 | método | BleAuditStatus | `@override Widget build(BuildContext context)` | Construye la interfaz de BleAuditStatus. |
## `lib/gui/menu/hacking/ble_capability_gate.dart`

| Línea | Tipo | Owner | Firma | Descripción |
|---:|---|---|---|---|
| 12 | constructor | BleCapabilityGate | `const BleCapabilityGate({ super.key, required this.child, required this.feature, required this.requiredCommands, })` | Construye BleCapabilityGate. |
| 19 | método | BleCapabilityGate | `@override Widget build(BuildContext context)` | Construye la interfaz de BleCapabilityGate. |
## `lib/gui/menu/hacking/ble_characteristic_tile.dart`

| Línea | Tipo | Owner | Firma | Descripción |
|---:|---|---|---|---|
| 19 | constructor | BleCharacteristicTile | `const BleCharacteristicTile({ super.key, required this.characteristic, required this.readValue, required this.notifying, this.readSupported = true, this.writeSupported = true, this.fuzzSupported = true, this.notifySupported = true, required this.onRead, required this.onWrite, required this.onSelectFuzz, required this.onToggleNotify, })` | Construye BleCharacteristicTile. |
| 34 | método | BleCharacteristicTile | `@override Widget build(BuildContext context)` | Construye la interfaz de BleCharacteristicTile. |
## `lib/gui/menu/hacking/ble_radio_identity.dart`

| Línea | Tipo | Owner | Firma | Descripción |
|---:|---|---|---|---|
| 21 | constructor | BleRadioIdentityPage | `const BleRadioIdentityPage({super.key, this.embedded = false})` | Construye BleRadioIdentityPage. |
| 23 | método | BleRadioIdentityPage | `@override BleRadioIdentityPageState createState()` | Operación `createState`. |
| 41 | getter | BleRadioIdentityPageState | `ChameleonGUIState get _app` | Obtiene `_app`. |
| 42 | getter | BleRadioIdentityPageState | `ChameleonCommunicator get _dev` | Obtiene `_dev`. |
| 43 | getter | BleRadioIdentityPageState | `bool get _usingBleTransport` | Obtiene `_usingBleTransport`. |
| 46 | método | BleRadioIdentityPageState | `String _addressTypeName(AppLocalizations localizations, int type)` | Operación `_addressTypeName`. |
| 55 | método | BleRadioIdentityPageState | `@override void dispose()` | Libera recursos de BleRadioIdentityPageState. |
| 61 | método | BleRadioIdentityPageState | `Future<void> _refreshRadio()` | Operación `_refreshRadio`. |
| 77 | método | BleRadioIdentityPageState | `Future<void> _refreshAddr()` | Operación `_refreshAddr`. |
| 93 | método | BleRadioIdentityPageState | `Future<void> _toggleRadio(bool target)` | Operación `_toggleRadio`. |
| 110 | método | BleRadioIdentityPageState | `Future<void> _applyAddr()` | Operación `_applyAddr`. |
| 133 | método | BleRadioIdentityPageState | `@override Widget build(BuildContext context)` | Construye la interfaz de BleRadioIdentityPageState. |
| 187 | método | BleRadioIdentityPageState | `Widget _radioCard()` | Operación `_radioCard`. |
| 269 | método | BleRadioIdentityPageState | `Widget _identityCard()` | Operación `_identityCard`. |
| 371 | método | BleRadioIdentityPageState | `Widget _kv(String k, String v)` | Operación `_kv`. |
| 381 | constructor | BleResponsiveKeyValueRow | `const BleResponsiveKeyValueRow({ super.key, required this.label, required this.value, })` | Construye BleResponsiveKeyValueRow. |
| 387 | método | BleResponsiveKeyValueRow | `@override Widget build(BuildContext context)` | Construye la interfaz de BleResponsiveKeyValueRow. |
## `lib/gui/menu/hacking/ble_responsive.dart`

| Línea | Tipo | Owner | Firma | Descripción |
|---:|---|---|---|---|
| 8 | constructor | BleResponsiveFieldGroup | `const BleResponsiveFieldGroup({ super.key, required this.children, this.breakpoint = 560, this.spacing = 8, })` | Construye BleResponsiveFieldGroup. |
| 15 | método | BleResponsiveFieldGroup | `@override Widget build(BuildContext context)` | Construye la interfaz de BleResponsiveFieldGroup. |
## `lib/gui/menu/hacking/ble_stress.dart`

| Línea | Tipo | Owner | Firma | Descripción |
|---:|---|---|---|---|
| 28 | constructor | BleStressPage | `const BleStressPage({super.key, this.embedded = false})` | Construye BleStressPage. |
| 30 | método | BleStressPage | `@override BleStressPageState createState()` | Operación `createState`. |
| 65 | getter | BleStressPageState | `ChameleonCommunicator get _dev` | Obtiene `_dev`. |
| 66 | método | BleStressPageState | `bool _supportsCommands(List<ChameleonCommand> commands)` | Operación `_supportsCommands`. |
| 73 | método | BleStressPageState | `@override void didChangeDependencies()` | Operación `didChangeDependencies`. |
| 79 | método | BleStressPageState | `@override void initState()` | Inicializa el estado de BleStressPageState. |
| 104 | método | BleStressPageState | `@override void dispose()` | Libera recursos de BleStressPageState. |
| 121 | método | BleStressPageState | `void _clearLocalActivity()` | Operación `_clearLocalActivity`. |
| 131 | método | BleStressPageState | `Future<void> _startFlood()` | Operación `_startFlood`. |
| 141 | método | BleStressPageState | `Future<void> _startFloodUnchecked()` | Operación `_startFloodUnchecked`. |
| 267 | método | BleStressPageState | `Future<void> _refreshFloodCount()` | Operación `_refreshFloodCount`. |
| 300 | método | BleStressPageState | `String _floodStartError(int status)` | Operación `_floodStartError`. |
| 313 | método | BleStressPageState | `Future<void> _startBroadcast()` | Operación `_startBroadcast`. |
| 323 | método | BleStressPageState | `Future<void> _startBroadcastUnchecked()` | Operación `_startBroadcastUnchecked`. |
| 358 | método | BleStressPageState | `Future<void> _startBroadcastValues(int fill, int units, {required _BroadcastErrorTarget errorTarget})` | Operación `_startBroadcastValues`. |
| 374 | método | BleStressPageState | `Future<void> _stopFlood()` | Operación `_stopFlood`. |
| 402 | método | BleStressPageState | `Future<void> _stopBroadcast()` | Operación `_stopBroadcast`. |
| 420 | método | BleStressPageState | `Future<void> _kick()` | Operación `_kick`. |
| 463 | método | BleStressPageState | `@override Widget build(BuildContext context)` | Construye la interfaz de BleStressPageState. |
| 525 | método | BleStressPageState | `Widget _floodCard()` | Operación `_floodCard`. |
| 697 | método | BleStressPageState | `Widget _kickCard()` | Operación `_kickCard`. |
| 777 | método | BleStressPageState | `Widget _broadcastCard()` | Operación `_broadcastCard`. |
## `lib/gui/menu/hacking/category_page.dart`

| Línea | Tipo | Owner | Firma | Descripción |
|---:|---|---|---|---|
| 20 | constructor | HackingAttack | `const HackingAttack(this.name, this.description, this.icon, this.open, {this.deviceRequired = false})` | Construye HackingAttack. |
| 31 | constructor | HackingToolGrid | `const HackingToolGrid({super.key, required this.attacks})` | Construye HackingToolGrid. |
| 33 | método | HackingToolGrid | `@override Widget build(BuildContext context)` | Construye la interfaz de HackingToolGrid. |
| 82 | constructor | HackingCategoryPage | `const HackingCategoryPage( {super.key, required this.title, required this.attacks})` | Construye HackingCategoryPage. |
| 85 | método | HackingCategoryPage | `@override Widget build(BuildContext context)` | Construye la interfaz de HackingCategoryPage. |
## `lib/gui/menu/hacking/darkside.dart`

| Línea | Tipo | Owner | Firma | Descripción |
|---:|---|---|---|---|
| 17 | constructor | DarksidePage | `const DarksidePage({super.key})` | Construye DarksidePage. |
| 19 | método | DarksidePage | `@override DarksidePageState createState()` | Operación `createState`. |
| 29 | método | DarksidePageState | `@override void dispose()` | Libera recursos de DarksidePageState. |
| 35 | método | DarksidePageState | `void _refresh()` | Operación `_refresh`. |
| 39 | método | DarksidePageState | `Future<void> _run()` | Operación `_run`. |
| 72 | getter | DarksidePageState | `bool get _hasAnyKey` | Obtiene `_hasAnyKey`. |
| 75 | método | DarksidePageState | `@override Widget build(BuildContext context)` | Construye la interfaz de DarksidePageState. |
## `lib/gui/menu/hacking/desfire_reader.dart`

| Línea | Tipo | Owner | Firma | Descripción |
|---:|---|---|---|---|
| 16 | constructor | _DesfireApp | `_DesfireApp(this.aid, this.fileIds, [this.keySettings])` | Construye _DesfireApp. |
| 24 | constructor | _DesfireResult | `_DesfireResult(this.uid, this.info, this.apps, this.apdus)` | Construye _DesfireResult. |
| 30 | constructor | DesfireReaderPage | `const DesfireReaderPage({super.key})` | Construye DesfireReaderPage. |
| 32 | método | DesfireReaderPage | `@override DesfireReaderPageState createState()` | Operación `createState`. |
| 41 | getter | DesfireReaderPageState | `ChameleonGUIState get _app` | Obtiene `_app`. |
| 42 | getter | DesfireReaderPageState | `bool get _connected` | Obtiene `_connected`. |
| 44 | método | DesfireReaderPageState | `String _storageLabel(int code)` | Operación `_storageLabel`. |
| 54 | método | DesfireReaderPageState | `String _decodeFileSettings(List<int> b)` | Operación `_decodeFileSettings`. |
| 76 | método | DesfireReaderPageState | `_DesfireResult _parse(Uint8List d)` | Operación `_parse`. |
| 157 | método | DesfireReaderPageState | `Future<void> _scan()` | Operación `_scan`. |
| 182 | método | DesfireReaderPageState | `Widget _row(String k, String v)` | Operación `_row`. |
| 208 | método | DesfireReaderPageState | `@override Widget build(BuildContext context)` | Construye la interfaz de DesfireReaderPageState. |
## `lib/gui/menu/hacking/emv_emulator.dart`

| Línea | Tipo | Owner | Firma | Descripción |
|---:|---|---|---|---|
| 16 | constructor | _Rule | `const _Rule(this.label, this.cmd, this.resp)` | Construye _Rule. |
| 23 | constructor | _Preset | `const _Preset(this.label, this.icon, this.rules)` | Construye _Preset. |
| 31 | constructor | EmvEmulatorPage | `const EmvEmulatorPage({super.key})` | Construye EmvEmulatorPage. |
| 33 | método | EmvEmulatorPage | `@override EmvEmulatorPageState createState()` | Operación `createState`. |
| 45 | getter | EmvEmulatorPageState | `ChameleonGUIState get _app` | Obtiene `_app`. |
| 46 | getter | EmvEmulatorPageState | `bool get _connected` | Obtiene `_connected`. |
| 53 | método | EmvEmulatorPageState | `static String _hexFill(int value, int count)` | Operación `_hexFill`. |
| 56 | método | EmvEmulatorPageState | `@override void dispose()` | Libera recursos de EmvEmulatorPageState. |
| 136 | método | EmvEmulatorPageState | `void _show(String m)` | Operación `_show`. |
| 142 | método | EmvEmulatorPageState | `bool _isHex(String s)` | Operación `_isHex`. |
| 145 | método | EmvEmulatorPageState | `void _loadRules(List<_Rule> rules)` | Operación `_loadRules`. |
| 154 | método | EmvEmulatorPageState | `Widget _presetButton(_Preset preset)` | Operación `_presetButton`. |
| 162 | método | EmvEmulatorPageState | `Future<void> _arm()` | Operación `_arm`. |
| 212 | método | EmvEmulatorPageState | `Future<void> _clear()` | Operación `_clear`. |
| 228 | método | EmvEmulatorPageState | `@override Widget build(BuildContext context)` | Construye la interfaz de EmvEmulatorPageState. |
## `lib/gui/menu/hacking/emv_reader.dart`

| Línea | Tipo | Owner | Firma | Descripción |
|---:|---|---|---|---|
| 33 | constructor | _EmvResult | `_EmvResult( this.uid, this.protocol, this.sak, this.atqa, this.ats, this.traces, this.fields, this.tlvs, this.aip, { this.capture, this.applicationAids = const {}, this.applicationTraces = const {}, this.applicationFields = const {}, })` | Construye _EmvResult. |
| 53 | constructor | EmvReaderPage | `const EmvReaderPage({super.key})` | Construye EmvReaderPage. |
| 55 | método | EmvReaderPage | `@override EmvReaderPageState createState()` | Operación `createState`. |
| 67 | getter | EmvReaderPageState | `ChameleonGUIState get _app` | Obtiene `_app`. |
| 68 | getter | EmvReaderPageState | `bool get _connected` | Obtiene `_connected`. |
| 70 | método | EmvReaderPageState | `@override void initState()` | Inicializa el estado de EmvReaderPageState. |
| 76 | método | EmvReaderPageState | `Future<void> _loadCapabilities()` | Operación `_loadCapabilities`. |
| 92 | método | EmvReaderPageState | `_EmvResult _parseLegacy(Uint8List d)` | Operación `_parseLegacy`. |
| 110 | método | EmvReaderPageState | `_EmvResult _parseTrace(EmvTraceCapture capture)` | Operación `_parseTrace`. |
| 158 | método | EmvReaderPageState | `Future<void> _scan()` | Operación `_scan`. |
| 209 | método | EmvReaderPageState | `Future<_EmvResult> _legacyScan(AppLocalizations localizations)` | Operación `_legacyScan`. |
| 219 | método | EmvReaderPageState | `Future<void> _setMaximumProcessing(bool enabled)` | Operación `_setMaximumProcessing`. |
| 251 | método | EmvReaderPageState | `void _toast(String m)` | Operación `_toast`. |
| 257 | método | EmvReaderPageState | `void _copy(String v)` | Operación `_copy`. |
| 262 | método | EmvReaderPageState | `String? _captureJson()` | Operación `_captureJson`. |
| 268 | método | EmvReaderPageState | `Future<void> _copyJson()` | Operación `_copyJson`. |
| 276 | método | EmvReaderPageState | `Future<void> _exportJson()` | Operación `_exportJson`. |
| 290 | método | EmvReaderPageState | `Widget _field(String k, String v)` | Operación `_field`. |
| 319 | método | EmvReaderPageState | `Widget _tlvRow(EmvTlv t)` | Operación `_tlvRow`. |
| 344 | método | EmvReaderPageState | `Widget _traceTile(EmvApduTrace t)` | Operación `_traceTile`. |
| 371 | método | EmvReaderPageState | `Widget _rfTile(EmvTraceRecord record)` | Operación `_rfTile`. |
| 393 | método | EmvReaderPageState | `Widget _captureStatus(EmvTraceCapture capture)` | Operación `_captureStatus`. |
| 445 | método | EmvReaderPageState | `List<int> _applicationScopes(_EmvResult result)` | Operación `_applicationScopes`. |
| 454 | método | EmvReaderPageState | `String _scopeLabel(_EmvResult result, int index)` | Operación `_scopeLabel`. |
| 461 | método | EmvReaderPageState | `Widget _partialScanHint(_EmvResult r)` | Operación `_partialScanHint`. |
| 478 | método | EmvReaderPageState | `@override Widget build(BuildContext context)` | Construye la interfaz de EmvReaderPageState. |
## `lib/gui/menu/hacking/emv_transaction.dart`

| Línea | Tipo | Owner | Firma | Descripción |
|---:|---|---|---|---|
| 23 | constructor | EmvTransactionPage | `const EmvTransactionPage({super.key})` | Construye EmvTransactionPage. |
| 25 | método | EmvTransactionPage | `@override EmvTransactionPageState createState()` | Operación `createState`. |
| 50 | getter | EmvTransactionPageState | `ChameleonGUIState get _app` | Obtiene `_app`. |
| 51 | getter | EmvTransactionPageState | `bool get _connected` | Obtiene `_connected`. |
| 53 | método | EmvTransactionPageState | `@override void initState()` | Inicializa el estado de EmvTransactionPageState. |
| 59 | método | EmvTransactionPageState | `Future<void> _loadCapabilities()` | Operación `_loadCapabilities`. |
| 75 | método | EmvTransactionPageState | `@override void dispose()` | Libera recursos de EmvTransactionPageState. |
| 82 | método | EmvTransactionPageState | `Uint8List _amountBcd(String s)` | Operación `_amountBcd`. |
| 102 | método | EmvTransactionPageState | `Future<void> _simulate()` | Operación `_simulate`. |
| 251 | método | EmvTransactionPageState | `Future<(Uint8List, Uint8List, int, Uint8List, List<(Uint8List, Uint8List)>)> _legacyTransaction( Uint8List amount, AppLocalizations localizations)` | Operación `_legacyTransaction`. |
| 260 | método | EmvTransactionPageState | `Future<void> _setMaximumProcessing(bool enabled)` | Operación `_setMaximumProcessing`. |
| 290 | método | EmvTransactionPageState | `void _toast(String message)` | Operación `_toast`. |
| 297 | método | EmvTransactionPageState | `void _copy(String value)` | Operación `_copy`. |
| 302 | método | EmvTransactionPageState | `String? _captureJson()` | Operación `_captureJson`. |
| 334 | método | EmvTransactionPageState | `Future<void> _copyJson()` | Operación `_copyJson`. |
| 341 | método | EmvTransactionPageState | `Future<void> _exportJson()` | Operación `_exportJson`. |
| 355 | método | EmvTransactionPageState | `Widget _row(String k, String v, {Color? color})` | Operación `_row`. |
| 386 | método | EmvTransactionPageState | `Widget _tlvRow(EmvTlv t)` | Operación `_tlvRow`. |
| 424 | método | EmvTransactionPageState | `Widget _traceTile(EmvApduTrace t)` | Operación `_traceTile`. |
| 462 | método | EmvTransactionPageState | `Widget _rfTile(EmvTraceRecord record)` | Operación `_rfTile`. |
| 494 | método | EmvTransactionPageState | `Widget _captureStatus(EmvTraceCapture capture)` | Operación `_captureStatus`. |
| 547 | método | EmvTransactionPageState | `List<int> _applicationScopes()` | Operación `_applicationScopes`. |
| 556 | método | EmvTransactionPageState | `String _scopeLabel(int index)` | Operación `_scopeLabel`. |
| 563 | método | EmvTransactionPageState | `String _cryptogramHint( AppLocalizations localizations, List<EmvApduTrace> traces)` | Operación `_cryptogramHint`. |
| 580 | método | EmvTransactionPageState | `Widget _partialScanHint(List<EmvApduTrace> traces)` | Operación `_partialScanHint`. |
| 597 | método | EmvTransactionPageState | `@override Widget build(BuildContext context)` | Construye la interfaz de EmvTransactionPageState. |
## `lib/gui/menu/hacking/keyboard_payload.dart`

| Línea | Tipo | Owner | Firma | Descripción |
|---:|---|---|---|---|
| 27 | constructor | KeyboardPayloadPage | `const KeyboardPayloadPage({super.key})` | Construye KeyboardPayloadPage. |
| 29 | método | KeyboardPayloadPage | `@override State<KeyboardPayloadPage> createState()` | Operación `createState`. |
| 52 | método | _KeyboardPayloadPageState | `@override void dispose()` | Libera recursos de _KeyboardPayloadPageState. |
| 59 | método | _KeyboardPayloadPageState | `void _compile()` | Operación `_compile`. |
| 80 | método | _KeyboardPayloadPageState | `Future<void> _perform(Future<void> Function() operation)` | Operación `_perform`. |
| 98 | método | _KeyboardPayloadPageState | `Future<void> _upload()` | Operación `_upload`. |
| 116 | método | _KeyboardPayloadPageState | `Future<void> _refreshStatus()` | Operación `_refreshStatus`. |
| 124 | método | _KeyboardPayloadPageState | `Future<void> _run()` | Operación `_run`. |
| 140 | método | _KeyboardPayloadPageState | `Future<KeyboardRunResult> _startKeyboardRun( ChameleonCommunicator communicator, int commitId, KeyboardOutput output, )` | Operación `_startKeyboardRun`. |
| 157 | método | _KeyboardPayloadPageState | `Future<void> _setTemporaryBleName({required bool restore})` | Operación `_setTemporaryBleName`. |
| 173 | método | _KeyboardPayloadPageState | `Future<void> _armBle()` | Operación `_armBle`. |
| 202 | método | _KeyboardPayloadPageState | `Future<void> _saveScript()` | Operación `_saveScript`. |
| 282 | método | _KeyboardPayloadPageState | `Future<void> _showScriptLibrary()` | Operación `_showScriptLibrary`. |
| 415 | método | _KeyboardPayloadPageState | `void _loadSavedScript(SavedKeyboardScript script)` | Operación `_loadSavedScript`. |
| 429 | método | _KeyboardPayloadPageState | `Future<void> _quickLaunch(SavedKeyboardScript script)` | Operación `_quickLaunch`. |
| 450 | método | _KeyboardPayloadPageState | `Future<void> _showBlePairingMenu()` | Operación `_showBlePairingMenu`. |
| 560 | método | _KeyboardPayloadPageState | `Uri _bluetoothSettingsUri()` | Operación `_bluetoothSettingsUri`. |
| 572 | método | _KeyboardPayloadPageState | `Future<void> _cancel()` | Operación `_cancel`. |
| 583 | método | _KeyboardPayloadPageState | `Future<void> _clear()` | Operación `_clear`. |
| 595 | método | _KeyboardPayloadPageState | `@override Widget build(BuildContext context)` | Construye la interfaz de _KeyboardPayloadPageState. |
| 694 | método | _KeyboardPayloadPageState | `Widget _editorCard(BuildContext context)` | Operación `_editorCard`. |
| 786 | método | _KeyboardPayloadPageState | `String _layoutName(AppLocalizations localizations, KeyboardLayout layout)` | Operación `_layoutName`. |
| 797 | método | _KeyboardPayloadPageState | `String _outputName(AppLocalizations localizations, KeyboardOutput output)` | Operación `_outputName`. |
| 804 | método | _KeyboardPayloadPageState | `Widget _controlsCard( BuildContext context, { required bool uploadEnabled, required bool runEnabled, required bool armEnabled, required bool armSupported, required bool armed, })` | Operación `_controlsCard`. |
## `lib/gui/menu/hacking/mfkey_manual.dart`

| Línea | Tipo | Owner | Firma | Descripción |
|---:|---|---|---|---|
| 15 | constructor | MfkeyManualMenu | `const MfkeyManualMenu({super.key})` | Construye MfkeyManualMenu. |
| 17 | método | MfkeyManualMenu | `@override MfkeyManualMenuState createState()` | Operación `createState`. |
| 44 | método | MfkeyManualMenuState | `@override void dispose()` | Libera recursos de MfkeyManualMenuState. |
| 52 | método | MfkeyManualMenuState | `int _hex(String key)` | Operación `_hex`. |
| 57 | método | MfkeyManualMenuState | `Future<void> _recover()` | Operación `_recover`. |
| 98 | método | MfkeyManualMenuState | `Widget _field(String key, String label)` | Operación `_field`. |
| 110 | método | MfkeyManualMenuState | `@override Widget build(BuildContext context)` | Construye la interfaz de MfkeyManualMenuState. |
## `lib/gui/menu/hacking/nested.dart`

| Línea | Tipo | Owner | Firma | Descripción |
|---:|---|---|---|---|
| 21 | constructor | NestedPage | `const NestedPage({super.key, this.variant = NestedVariant.weak})` | Construye NestedPage. |
| 23 | método | NestedPage | `@override NestedPageState createState()` | Operación `createState`. |
| 39 | método | NestedPageState | `@override void dispose()` | Libera recursos de NestedPageState. |
| 48 | método | NestedPageState | `void _refresh()` | Operación `_refresh`. |
| 52 | método | NestedPageState | `Future<void> _run()` | Operación `_run`. |
| 105 | getter | NestedPageState | `bool get _hasAnyKey` | Obtiene `_hasAnyKey`. |
| 108 | método | NestedPageState | `Widget _keyTypeToggle(int value, ValueChanged<int> onChanged)` | Operación `_keyTypeToggle`. |
| 118 | getter | NestedPageState | `String get _title` | Obtiene `_title`. |
| 124 | método | NestedPageState | `@override Widget build(BuildContext context)` | Construye la interfaz de NestedPageState. |
## `lib/gui/menu/hacking/ntag_password_capture.dart`

| Línea | Tipo | Owner | Firma | Descripción |
|---:|---|---|---|---|
| 14 | constructor | NtagPasswordCapturePage | `const NtagPasswordCapturePage({super.key})` | Construye NtagPasswordCapturePage. |
| 16 | método | NtagPasswordCapturePage | `@override NtagPasswordCapturePageState createState()` | Operación `createState`. |
| 27 | getter | NtagPasswordCapturePageState | `ChameleonGUIState get _app` | Obtiene `_app`. |
| 28 | getter | NtagPasswordCapturePageState | `bool get _connected` | Obtiene `_connected`. |
| 30 | método | NtagPasswordCapturePageState | `@override void initState()` | Inicializa el estado de NtagPasswordCapturePageState. |
| 39 | método | NtagPasswordCapturePageState | `@override void dispose()` | Libera recursos de NtagPasswordCapturePageState. |
| 45 | método | NtagPasswordCapturePageState | `void _startPolling()` | Operación `_startPolling`. |
| 49 | método | NtagPasswordCapturePageState | `Future<void> _refreshCount()` | Operación `_refreshCount`. |
| 59 | método | NtagPasswordCapturePageState | `Future<void> _arm()` | Operación `_arm`. |
| 77 | método | NtagPasswordCapturePageState | `Future<void> _stop()` | Operación `_stop`. |
| 94 | método | NtagPasswordCapturePageState | `Future<void> _download()` | Operación `_download`. |
| 114 | método | NtagPasswordCapturePageState | `void _show(String m)` | Operación `_show`. |
| 120 | método | NtagPasswordCapturePageState | `@override Widget build(BuildContext context)` | Construye la interfaz de NtagPasswordCapturePageState. |
## `lib/gui/menu/hacking/relay_resistance_lab.dart`

| Línea | Tipo | Owner | Firma | Descripción |
|---:|---|---|---|---|
| 15 | constructor | RelayResistanceLabPage | `const RelayResistanceLabPage({super.key})` | Construye RelayResistanceLabPage. |
| 17 | método | RelayResistanceLabPage | `@override State<RelayResistanceLabPage> createState()` | Operación `createState`. |
| 33 | getter | _RelayResistanceLabPageState | `ChameleonGUIState get _app` | Obtiene `_app`. |
| 34 | getter | _RelayResistanceLabPageState | `bool get _connected` | Obtiene `_connected`. |
| 36 | método | _RelayResistanceLabPageState | `@override void initState()` | Inicializa el estado de _RelayResistanceLabPageState. |
| 42 | método | _RelayResistanceLabPageState | `Future<void> _initialize()` | Operación `_initialize`. |
| 53 | método | _RelayResistanceLabPageState | `@override void dispose()` | Libera recursos de _RelayResistanceLabPageState. |
| 62 | método | _RelayResistanceLabPageState | `Future<void> _setArmed(bool value)` | Operación `_setArmed`. |
| 97 | método | _RelayResistanceLabPageState | `Future<void> _handleApdu(Map<String, Object?> event)` | Operación `_handleApdu`. |
| 159 | método | _RelayResistanceLabPageState | `Future<void> _runBaseline()` | Operación `_runBaseline`. |
| 213 | método | _RelayResistanceLabPageState | `RelayLabExchange _baselineExchange( Uint8List command, Uint8List response, int elapsedUs)` | Operación `_baselineExchange`. |
| 233 | método | _RelayResistanceLabPageState | `void _clearDemo()` | Operación `_clearDemo`. |
| 241 | método | _RelayResistanceLabPageState | `Future<void> _copyReport()` | Operación `_copyReport`. |
| 256 | método | _RelayResistanceLabPageState | `@override Widget build(BuildContext context)` | Construye la interfaz de _RelayResistanceLabPageState. |
| 426 | método | _RelayResistanceLabPageState | `Widget _exchangeTile(RelayLabExchange exchange, {bool direct = false})` | Operación `_exchangeTile`. |
| 443 | método | _RelayResistanceLabPageState | `String _formatUs(int value)` | Operación `_formatUs`. |
## `lib/gui/menu/hacking/transit_gate_test.dart`

| Línea | Tipo | Owner | Firma | Descripción |
|---:|---|---|---|---|
| 15 | constructor | TransitGateTestPage | `const TransitGateTestPage({super.key})` | Construye TransitGateTestPage. |
| 17 | método | TransitGateTestPage | `@override State<TransitGateTestPage> createState()` | Operación `createState`. |
| 22 | constructor | _TransitSessionResult | `const _TransitSessionResult( this.profile, this.requestBytes, this.capture, this.assessment)` | Construye _TransitSessionResult. |
| 30 | método | _TransitSessionResult | `Map<String, Object?> toJson()` | Serializa _TransitSessionResult. |
| 62 | getter | _TransitGateTestPageState | `ChameleonGUIState get _app` | Obtiene `_app`. |
| 63 | getter | _TransitGateTestPageState | `bool get _connected` | Obtiene `_connected`. |
| 65 | método | _TransitGateTestPageState | `@override void initState()` | Inicializa el estado de _TransitGateTestPageState. |
| 71 | método | _TransitGateTestPageState | `@override void dispose()` | Libera recursos de _TransitGateTestPageState. |
| 78 | método | _TransitGateTestPageState | `Future<void> _loadCapabilities()` | Operación `_loadCapabilities`. |
| 94 | método | _TransitGateTestPageState | `Future<void> _ensureReaderMode()` | Operación `_ensureReaderMode`. |
| 100 | método | _TransitGateTestPageState | `Future<void> _runLockedDiscovery()` | Operación `_runLockedDiscovery`. |
| 155 | método | _TransitGateTestPageState | `Future<void> _runTransaction()` | Operación `_runTransaction`. |
| 281 | método | _TransitGateTestPageState | `Future<void> _copyReport()` | Operación `_copyReport`. |
| 357 | método | _TransitGateTestPageState | `Future<void> _replayCopiedReport()` | Operación `_replayCopiedReport`. |
| 379 | método | _TransitGateTestPageState | `Color _gateColor(TransitGateAssessment assessment)` | Operación `_gateColor`. |
| 385 | método | _TransitGateTestPageState | `Widget _gateStatus(TransitGateAssessment assessment)` | Operación `_gateStatus`. |
| 452 | método | _TransitGateTestPageState | `Widget _applicationCard(TransitApplicationEvidence application)` | Operación `_applicationCard`. |
| 525 | método | _TransitGateTestPageState | `List< ({ String label, Uint8List? requestBytes, EmvTraceCapture capture, })> _visibleCaptures()` | Operación `_visibleCaptures`. |
| 555 | método | _TransitGateTestPageState | `Widget _fullRawTrace( List< ({ String label, Uint8List? requestBytes, EmvTraceCapture capture, })> sessions)` | Operación `_fullRawTrace`. |
| 599 | método | _TransitGateTestPageState | `Widget _controlTrace(Uint8List? requestBytes, EmvTraceCapture capture)` | Operación `_controlTrace`. |
| 628 | método | _TransitGateTestPageState | `Widget _rawRecord(EmvTraceRecord record)` | Operación `_rawRecord`. |
| 680 | método | _TransitGateTestPageState | `Widget _decodeTrace( List< ({ String label, Uint8List? requestBytes, EmvTraceCapture capture, })> sessions)` | Operación `_decodeTrace`. |
| 736 | método | _TransitGateTestPageState | `Widget _decodedApplications(EmvTraceCapture capture)` | Operación `_decodedApplications`. |
| 780 | método | _TransitGateTestPageState | `Widget _decodedMap(String title, Map<String, String> values)` | Operación `_decodedMap`. |
| 793 | método | _TransitGateTestPageState | `Widget _decodedApdu(EmvTraceRecord record)` | Operación `_decodedApdu`. |
| 828 | método | _TransitGateTestPageState | `Widget _instructions()` | Operación `_instructions`. |
| 862 | método | _TransitGateTestPageState | `@override Widget build(BuildContext context)` | Construye la interfaz de _TransitGateTestPageState. |
| 1166 | función | - | `int _ecpFrameCount(EmvTraceCapture capture)` | Función `_ecpFrameCount`. |
| 1198 | función | - | `String _hexBytes(List<int> bytes)` | Función `_hexBytes`. |
| 1202 | función | - | `String _hexByte(int value)` | Función `_hexByte`. |
| 1205 | función | - | `String _hexWord(int value)` | Función `_hexWord`. |
## `lib/gui/menu/hacking/value_block.dart`

| Línea | Tipo | Owner | Firma | Descripción |
|---:|---|---|---|---|
| 13 | constructor | ValueBlockMenu | `const ValueBlockMenu({super.key})` | Construye ValueBlockMenu. |
| 15 | método | ValueBlockMenu | `@override ValueBlockMenuState createState()` | Operación `createState`. |
| 29 | getter | ValueBlockMenuState | `ChameleonGUIState get _app` | Obtiene `_app`. |
| 30 | getter | ValueBlockMenuState | `bool get _connected` | Obtiene `_connected`. |
| 32 | método | ValueBlockMenuState | `@override void dispose()` | Libera recursos de ValueBlockMenuState. |
| 41 | método | ValueBlockMenuState | `Future<void> _run()` | Operación `_run`. |
| 71 | método | ValueBlockMenuState | `void _show(String m)` | Operación `_show`. |
| 77 | método | ValueBlockMenuState | `@override Widget build(BuildContext context)` | Construye la interfaz de ValueBlockMenuState. |
## `lib/gui/menu/hacking/wiegand.dart`

| Línea | Tipo | Owner | Firma | Descripción |
|---:|---|---|---|---|
| 14 | constructor | _WiegandFormat | `const _WiegandFormat(this.name, this.bits, this.fcShift, this.fcMask, this.cnShift, this.cnMask)` | Construye _WiegandFormat. |
| 30 | constructor | WiegandMenu | `const WiegandMenu({super.key})` | Construye WiegandMenu. |
| 32 | método | WiegandMenu | `@override WiegandMenuState createState()` | Operación `createState`. |
| 43 | método | WiegandMenuState | `@override void dispose()` | Libera recursos de WiegandMenuState. |
| 49 | método | WiegandMenuState | `void _decode()` | Operación `_decode`. |
| 68 | método | WiegandMenuState | `Widget _result(String label, String value)` | Operación `_result`. |
| 90 | método | WiegandMenuState | `@override Widget build(BuildContext context)` | Construye la interfaz de WiegandMenuState. |
## `lib/gui/menu/pages/changelog_view.dart`

| Línea | Tipo | Owner | Firma | Descripción |
|---:|---|---|---|---|
| 12 | constructor | ChangelogView | `const ChangelogView({super.key})` | Construye ChangelogView. |
| 14 | método | ChangelogView | `@override ChangelogViewState createState()` | Operación `createState`. |
| 21 | método | ChangelogViewState | `@override void initState()` | Inicializa el estado de ChangelogViewState. |
| 27 | método | ChangelogViewState | `Future<List<ChangelogEntry>> _fetchChangelogsWithBuildNumber()` | Operación `_fetchChangelogsWithBuildNumber`. |
| 36 | método | ChangelogViewState | `@override Widget build(BuildContext context)` | Construye la interfaz de ChangelogViewState. |
| 79 | método | ChangelogViewState | `Widget _buildChangelogCard( ChangelogEntry changelog, AppLocalizations localizations)` | Operación `_buildChangelogCard`. |
| 211 | método | ChangelogViewState | `String _formatDate(DateTime date)` | Operación `_formatDate`. |
| 215 | método | ChangelogViewState | `Widget _buildRichText(String text)` | Operación `_buildRichText`. |
## `lib/gui/menu/pages/dump_editor.dart`

| Línea | Tipo | Owner | Firma | Descripción |
|---:|---|---|---|---|
| 21 | constructor | DumpEditor | `const DumpEditor({ super.key, required this.cardSave, required this.onSave, })` | Construye DumpEditor. |
| 27 | método | DumpEditor | `@override DumpEditorState createState()` | Operación `createState`. |
| 45 | método | DumpEditorState | `@override void initState()` | Inicializa el estado de DumpEditorState. |
| 54 | método | DumpEditorState | `@override void dispose()` | Libera recursos de DumpEditorState. |
| 63 | método | DumpEditorState | `void initEditor()` | Operación `initEditor`. |
| 76 | método | DumpEditorState | `void _initUltralightEditor()` | Operación `_initUltralightEditor`. |
| 89 | método | DumpEditorState | `void _initClassicEditor()` | Operación `_initClassicEditor`. |
| 115 | método | DumpEditorState | `String _formatHexData(Uint8List data)` | Operación `_formatHexData`. |
| 125 | método | DumpEditorState | `void _onDataChanged(int index)` | Operación `_onDataChanged`. |
| 138 | método | DumpEditorState | `TextEditingValue _handleTextInput( TextEditingValue oldValue, TextEditingValue newValue)` | Operación `_handleTextInput`. |
| 147 | método | DumpEditorState | `TextEditingValue _handleInsertMode( TextEditingValue oldValue, TextEditingValue newValue)` | Operación `_handleInsertMode`. |
| 241 | método | DumpEditorState | `TextEditingValue _handleOverwriteMode( TextEditingValue oldValue, TextEditingValue newValue)` | Operación `_handleOverwriteMode`. |
| 350 | método | DumpEditorState | `TextEditingValue _handleDeletion( TextEditingValue oldValue, TextEditingValue newValue)` | Operación `_handleDeletion`. |
| 359 | método | DumpEditorState | `TextEditingValue _processTextWithSpacing(TextEditingValue value)` | Operación `_processTextWithSpacing`. |
| 424 | método | DumpEditorState | `bool _validateDataForSave(String data, int controllerIndex)` | Operación `_validateDataForSave`. |
| 452 | método | DumpEditorState | `void _showErrorDialog(String message)` | Operación `_showErrorDialog`. |
| 469 | método | DumpEditorState | `void _saveDump()` | Operación `_saveDump`. |
| 517 | método | DumpEditorState | `void _cancelEdit()` | Operación `_cancelEdit`. |
| 545 | método | DumpEditorState | `void _showAsciiView()` | Operación `_showAsciiView`. |
| 597 | método | DumpEditorState | `void _showAccessConditions()` | Operación `_showAccessConditions`. |
| 650 | método | DumpEditorState | `void _showValueBlocks()` | Operación `_showValueBlocks`. |
| 700 | método | DumpEditorState | `List<TextSpan> _buildHighlightedTextOnly(int controllerIndex)` | Operación `_buildHighlightedTextOnly`. |
| 726 | método | DumpEditorState | `List<TextSpan> _buildBlockNumbers(int controllerIndex)` | Operación `_buildBlockNumbers`. |
| 753 | método | DumpEditorState | `List<TextSpan> _getHighlightedLineSpans( String line, int controllerIndex, int lineIndex)` | Operación `_getHighlightedLineSpans`. |
| 780 | método | DumpEditorState | `Color _getDefaultHighlightColor()` | Operación `_getDefaultHighlightColor`. |
| 786 | método | DumpEditorState | `Color _getDiffColor()` | Operación `_getDiffColor`. |
| 792 | método | DumpEditorState | `int _blockIndexFor(int controllerIndex, int lineIndex)` | Operación `_blockIndexFor`. |
| 798 | método | DumpEditorState | `Uint8List? _compareBytesFor(int controllerIndex, int lineIndex)` | Operación `_compareBytesFor`. |
| 809 | método | DumpEditorState | `String _byteAt(String cleanHex, int byteIndex)` | Operación `_byteAt`. |
| 820 | método | DumpEditorState | `String _spaceHex(String cleanHex)` | Operación `_spaceHex`. |
| 832 | método | DumpEditorState | `List<TextSpan> _byteSpans(String cleanHex, String otherHex, int byteCount)` | Operación `_byteSpans`. |
| 857 | método | DumpEditorState | `int _bitDiffCount(String a, String b, int byteCount)` | Operación `_bitDiffCount`. |
| 872 | método | DumpEditorState | `Future<void> _startCompare()` | Operación `_startCompare`. |
| 926 | método | DumpEditorState | `void _exitCompare()` | Operación `_exitCompare`. |
| 934 | método | DumpEditorState | `Widget _buildAdaptiveEditor(int controllerIndex)` | Operación `_buildAdaptiveEditor`. |
| 947 | método | DumpEditorState | `double _guessOptimalFontSize( int controllerIndex, BoxConstraints constraints)` | Operación `_guessOptimalFontSize`. |
| 961 | método | DumpEditorState | `double _calculateLeftPadding(BuildContext context, double fontSize)` | Operación `_calculateLeftPadding`. |
| 980 | método | DumpEditorState | `String _getLongestLine(int controllerIndex)` | Operación `_getLongestLine`. |
| 996 | método | DumpEditorState | `bool _doesTextFitOnOneLine( String text, double fontSize, double availableWidth)` | Operación `_doesTextFitOnOneLine`. |
| 1020 | método | DumpEditorState | `Widget _buildOriginalEditor(int controllerIndex, {double fontSize = 14.0})` | Operación `_buildOriginalEditor`. |
| 1100 | método | DumpEditorState | `Widget _buildCompareView(int controllerIndex, {double fontSize = 14.0})` | Operación `_buildCompareView`. |
| 1206 | método | DumpEditorState | `Widget _buildEditor(int controllerIndex)` | Operación `_buildEditor`. |
| 1248 | método | DumpEditorState | `Widget _buildColorLegend()` | Operación `_buildColorLegend`. |
| 1346 | método | DumpEditorState | `Widget _buildCompareLegend()` | Operación `_buildCompareLegend`. |
| 1394 | método | DumpEditorState | `Widget _buildLegendItem(String label, Color color)` | Operación `_buildLegendItem`. |
| 1415 | método | DumpEditorState | `@override Widget build(BuildContext context)` | Construye la interfaz de DumpEditorState. |
## `lib/gui/menu/pages/logs_viewer.dart`

| Línea | Tipo | Owner | Firma | Descripción |
|---:|---|---|---|---|
| 9 | constructor | LogsViewerPage | `const LogsViewerPage({super.key})` | Construye LogsViewerPage. |
| 11 | método | LogsViewerPage | `@override State<LogsViewerPage> createState()` | Operación `createState`. |
| 18 | método | LogsViewerPageState | `@override void dispose()` | Libera recursos de LogsViewerPageState. |
| 24 | método | LogsViewerPageState | `@override Widget build(BuildContext context)` | Construye la interfaz de LogsViewerPageState. |
## `lib/gui/menu/pages/mfkey32.dart`

| Línea | Tipo | Owner | Firma | Descripción |
|---:|---|---|---|---|
| 15 | constructor | Mfkey32Menu | `const Mfkey32Menu({super.key})` | Construye Mfkey32Menu. |
| 17 | método | Mfkey32Menu | `@override Mfkey32MenuState createState()` | Operación `createState`. |
| 33 | método | Mfkey32MenuState | `@override void initState()` | Inicializa el estado de Mfkey32MenuState. |
| 39 | método | Mfkey32MenuState | `Future<(bool, int)> getMf1DetectionStatus()` | Operación `getMf1DetectionStatus`. |
| 48 | método | Mfkey32MenuState | `Future<void> updateDetectionStatus()` | Operación `updateDetectionStatus`. |
| 57 | método | Mfkey32MenuState | `Future<void> handleMfkeyCalculation()` | Operación `handleMfkeyCalculation`. |
| 114 | método | Mfkey32MenuState | `@override void dispose()` | Libera recursos de Mfkey32MenuState. |
| 120 | método | Mfkey32MenuState | `@override Widget build(BuildContext context)` | Construye la interfaz de Mfkey32MenuState. |
## `lib/gui/menu/tools/compare_cards.dart`

| Línea | Tipo | Owner | Firma | Descripción |
|---:|---|---|---|---|
| 18 | constructor | CompareCardsMenu | `const CompareCardsMenu({super.key})` | Construye CompareCardsMenu. |
| 20 | método | CompareCardsMenu | `@override CompareCardsMenuState createState()` | Operación `createState`. |
| 29 | método | CompareCardsMenuState | `Color _diffColor(BuildContext context)` | Operación `_diffColor`. |
| 34 | método | CompareCardsMenuState | `Color _matchColor(BuildContext context)` | Operación `_matchColor`. |
| 39 | método | CompareCardsMenuState | `Color _mutedColor(BuildContext context)` | Operación `_mutedColor`. |
| 44 | método | CompareCardsMenuState | `Color _defaultColor(BuildContext context)` | Operación `_defaultColor`. |
| 47 | método | CompareCardsMenuState | `int _bitDiff(Uint8List? a, Uint8List? b)` | Operación `_bitDiff`. |
| 61 | método | CompareCardsMenuState | `Uint8List? _block(CardSave card, int block)` | Operación `_block`. |
| 69 | método | CompareCardsMenuState | `List<TextSpan> _hexSpans(Uint8List? value, Uint8List? other)` | Operación `_hexSpans`. |
| 99 | método | CompareCardsMenuState | `CardSave? _cardById(ChameleonGUIState appState, String? id)` | Operación `_cardById`. |
| 110 | método | CompareCardsMenuState | `Widget _buildKeysView(CardSave a, CardSave b)` | Operación `_buildKeysView`. |
| 189 | método | CompareCardsMenuState | `Widget _cell(String text, {bool bold = false})` | Operación `_cell`. |
| 196 | método | CompareCardsMenuState | `Widget _keyCell(String label, Uint8List? key, Color color)` | Operación `_keyCell`. |
| 205 | método | CompareCardsMenuState | `Widget _buildDataView(CardSave a, CardSave b)` | Operación `_buildDataView`. |
| 250 | método | CompareCardsMenuState | `bool _listEquals(Uint8List a, Uint8List b)` | Operación `_listEquals`. |
| 258 | método | CompareCardsMenuState | `@override Widget build(BuildContext context)` | Construye la interfaz de CompareCardsMenuState. |
| 325 | método | CompareCardsMenuState | `Widget _cardDropdown(List<CardSave> cards, String? value, String label, ValueChanged<String?> onChanged)` | Operación `_cardDropdown`. |
## `lib/gui/menu/tools/dictionary_download.dart`

| Línea | Tipo | Owner | Firma | Descripción |
|---:|---|---|---|---|
| 14 | constructor | DictionaryLocation | `DictionaryLocation({required this.name, required this.url})` | Construye DictionaryLocation. |
| 18 | constructor | DictionaryDownloadMenu | `const DictionaryDownloadMenu({super.key})` | Construye DictionaryDownloadMenu. |
| 20 | método | DictionaryDownloadMenu | `@override State<DictionaryDownloadMenu> createState()` | Operación `createState`. |
| 28 | método | DictionaryDownloadMenuState | `@override void dispose()` | Libera recursos de DictionaryDownloadMenuState. |
| 34 | método | DictionaryDownloadMenuState | `Future<void> _downloadDictionary( ChameleonGUIState appState, DictionaryLocation dictLocation, AppLocalizations localizations, )` | Operación `_downloadDictionary`. |
| 81 | método | DictionaryDownloadMenuState | `@override Widget build(BuildContext context)` | Construye la interfaz de DictionaryDownloadMenuState. |
## `lib/gui/menu/tools/emulation_change_history.dart`

| Línea | Tipo | Owner | Firma | Descripción |
|---:|---|---|---|---|
| 9 | constructor | EmulationChangeHistoryMenu | `const EmulationChangeHistoryMenu({super.key})` | Construye EmulationChangeHistoryMenu. |
| 11 | método | EmulationChangeHistoryMenu | `@override State<EmulationChangeHistoryMenu> createState()` | Operación `createState`. |
| 18 | método | _EmulationChangeHistoryMenuState | `@override Widget build(BuildContext context)` | Construye la interfaz de _EmulationChangeHistoryMenuState. |
| 90 | constructor | _HistoryEntry | `const _HistoryEntry({required this.entry})` | Construye _HistoryEntry. |
| 92 | método | _HistoryEntry | `String _timestamp(DateTime timestamp)` | Operación `_timestamp`. |
| 99 | método | _HistoryEntry | `@override Widget build(BuildContext context)` | Construye la interfaz de _HistoryEntry. |
## `lib/gui/menu/tools/hf_sniffing.dart`

| Línea | Tipo | Owner | Firma | Descripción |
|---:|---|---|---|---|
| 18 | constructor | HfSniffingMenu | `const HfSniffingMenu({super.key})` | Construye HfSniffingMenu. |
| 20 | método | HfSniffingMenu | `@override State<HfSniffingMenu> createState()` | Operación `createState`. |
| 30 | constructor | _HfSniffRecoveryState | `const _HfSniffRecoveryState({ this.isLoading = false, this.key, this.method, this.error, })` | Construye _HfSniffRecoveryState. |
| 53 | método | _HfSniffingMenuState | `@override void initState()` | Inicializa el estado de _HfSniffingMenuState. |
| 61 | método | _HfSniffingMenuState | `@override void dispose()` | Libera recursos de _HfSniffingMenuState. |
| 67 | método | _HfSniffingMenuState | `Future<void> _loadCapabilities()` | Operación `_loadCapabilities`. |
| 89 | método | _HfSniffingMenuState | `Future<void> _captureFrames()` | Operación `_captureFrames`. |
| 157 | método | _HfSniffingMenuState | `bool _isFirmwareUnsupportedError(String errorText)` | Operación `_isFirmwareUnsupportedError`. |
| 161 | método | _HfSniffingMenuState | `Future<void> _exportCapture()` | Operación `_exportCapture`. |
| 182 | método | _HfSniffingMenuState | `Future<void> _copyText(String text, String successMessage)` | Operación `_copyText`. |
| 189 | método | _HfSniffingMenuState | `Future<void> _recoverGroup(HfSniffNonceGroup group)` | Operación `_recoverGroup`. |
| 269 | método | _HfSniffingMenuState | `Future<void> _recoverAll()` | Operación `_recoverAll`. |
| 297 | método | _HfSniffingMenuState | `void _showSnack(String message)` | Operación `_showSnack`. |
| 303 | método | _HfSniffingMenuState | `String _formatKey(int key)` | Operación `_formatKey`. |
| 307 | método | _HfSniffingMenuState | `Uint8List _keyBytes(int key)` | Operación `_keyBytes`. |
| 311 | método | _HfSniffingMenuState | `Future<void> _saveRecoveredKey(HfSniffNonceGroup group, int key)` | Operación `_saveRecoveredKey`. |
| 325 | método | _HfSniffingMenuState | `String _rawHexDump({int? maxBytes})` | Operación `_rawHexDump`. |
| 336 | método | _HfSniffingMenuState | `@override Widget build(BuildContext context)` | Construye la interfaz de _HfSniffingMenuState. |
| 400 | método | _HfSniffingMenuState | `Widget _buildHeaderControls(AppLocalizations localizations)` | Operación `_buildHeaderControls`. |
| 478 | método | _HfSniffingMenuState | `Widget _buildCapabilityBanner(AppLocalizations localizations)` | Operación `_buildCapabilityBanner`. |
| 507 | método | _HfSniffingMenuState | `Widget _buildStatusBlock()` | Operación `_buildStatusBlock`. |
| 531 | método | _HfSniffingMenuState | `Widget _buildSummaryTab(AppLocalizations localizations)` | Operación `_buildSummaryTab`. |
| 627 | método | _HfSniffingMenuState | `Widget _buildFramesTab(AppLocalizations localizations)` | Operación `_buildFramesTab`. |
| 653 | método | _HfSniffingMenuState | `Widget _buildNoncesTab(AppLocalizations localizations)` | Operación `_buildNoncesTab`. |
| 736 | método | _HfSniffingMenuState | `Widget _buildRecoveryTab(AppLocalizations localizations)` | Operación `_buildRecoveryTab`. |
| 779 | método | _HfSniffingMenuState | `Widget _buildRecoveryGroup( AppLocalizations localizations, HfSniffNonceGroup group, )` | Operación `_buildRecoveryGroup`. |
| 890 | método | _HfSniffingMenuState | `Widget _buildRawTab(AppLocalizations localizations)` | Operación `_buildRawTab`. |
| 927 | método | _HfSniffingMenuState | `Widget _buildFrameTranscriptEntry( AppLocalizations localizations, int index, HfSniffFrame frame, String label, )` | Operación `_buildFrameTranscriptEntry`. |
| 1048 | método | _HfSniffingMenuState | `Widget _buildEmptyState(String message)` | Operación `_buildEmptyState`. |
| 1057 | método | _HfSniffingMenuState | `Widget _summaryCard(String title, String value, String subtitle)` | Operación `_summaryCard`. |
| 1075 | método | _HfSniffingMenuState | `Widget _buildPanel({ required Widget child, EdgeInsetsGeometry padding = const EdgeInsets.all(16), })` | Operación `_buildPanel`. |
| 1088 | método | _HfSniffingMenuState | `Widget _infoRow(String label, String value)` | Operación `_infoRow`. |
## `lib/gui/menu/tools/lf_sniffing.dart`

| Línea | Tipo | Owner | Firma | Descripción |
|---:|---|---|---|---|
| 15 | constructor | LfSniffingMenu | `const LfSniffingMenu({super.key})` | Construye LfSniffingMenu. |
| 17 | método | LfSniffingMenu | `@override State<LfSniffingMenu> createState()` | Operación `createState`. |
| 38 | método | _LfSniffingMenuState | `@override void initState()` | Inicializa el estado de _LfSniffingMenuState. |
| 46 | método | _LfSniffingMenuState | `@override void dispose()` | Libera recursos de _LfSniffingMenuState. |
| 54 | método | _LfSniffingMenuState | `Future<void> _loadCapabilities()` | Operación `_loadCapabilities`. |
| 75 | método | _LfSniffingMenuState | `Future<void> _captureLfSamples()` | Operación `_captureLfSamples`. |
| 146 | método | _LfSniffingMenuState | `bool _isFirmwareUnsupportedError(String errorText)` | Operación `_isFirmwareUnsupportedError`. |
| 150 | método | _LfSniffingMenuState | `({LfManchesterDecodeResult? result, String? error}) _buildDecodeResult( Uint8List samples)` | Operación `_buildDecodeResult`. |
| 170 | método | _LfSniffingMenuState | `void _refreshDecode()` | Operación `_refreshDecode`. |
| 182 | método | _LfSniffingMenuState | `Future<void> _exportCapture()` | Operación `_exportCapture`. |
| 203 | método | _LfSniffingMenuState | `Future<void> _copyText(String text, String successMessage)` | Operación `_copyText`. |
| 210 | método | _LfSniffingMenuState | `void _showSnack(String message)` | Operación `_showSnack`. |
| 216 | método | _LfSniffingMenuState | `String _hexPreview({int maxBytes = 512})` | Operación `_hexPreview`. |
| 234 | método | _LfSniffingMenuState | `String _groupBits(String bitString, {int width = 64})` | Operación `_groupBits`. |
| 247 | método | _LfSniffingMenuState | `String _modulationLabel( AppLocalizations localizations, LfSniffModulationResult modulation)` | Operación `_modulationLabel`. |
| 265 | método | _LfSniffingMenuState | `Color _lfSampleColor( BuildContext context, LfSniffSummary summary, int offset, int value, )` | Operación `_lfSampleColor`. |
| 297 | método | _LfSniffingMenuState | `Future<double?> _showWaveformDialog(LfSniffCapture capture)` | Operación `_showWaveformDialog`. |
| 393 | método | _LfSniffingMenuState | `Future<void> _openWaveformViewer(LfSniffCapture capture)` | Operación `_openWaveformViewer`. |
| 418 | método | _LfSniffingMenuState | `@override Widget build(BuildContext context)` | Construye la interfaz de _LfSniffingMenuState. |
| 498 | método | _LfSniffingMenuState | `Widget _buildCaptureField(AppLocalizations localizations)` | Operación `_buildCaptureField`. |
| 518 | método | _LfSniffingMenuState | `Widget _buildHeaderControls(AppLocalizations localizations, bool isWide)` | Operación `_buildHeaderControls`. |
| 547 | método | _LfSniffingMenuState | `Widget _buildActionButtons( AppLocalizations localizations, { required bool centerToField, })` | Operación `_buildActionButtons`. |
| 593 | método | _LfSniffingMenuState | `Widget _buildStatusBlock()` | Operación `_buildStatusBlock`. |
| 618 | método | _LfSniffingMenuState | `Widget _buildCapabilityBanner(AppLocalizations localizations)` | Operación `_buildCapabilityBanner`. |
| 647 | método | _LfSniffingMenuState | `Widget _buildSummaryTab(AppLocalizations localizations)` | Operación `_buildSummaryTab`. |
| 753 | método | _LfSniffingMenuState | `Widget _buildWaveformTab(AppLocalizations localizations)` | Operación `_buildWaveformTab`. |
| 836 | método | _LfSniffingMenuState | `Widget _buildDecodeTab(AppLocalizations localizations)` | Operación `_buildDecodeTab`. |
| 994 | método | _LfSniffingMenuState | `Widget _buildHexTab(AppLocalizations localizations)` | Operación `_buildHexTab`. |
| 1026 | método | _LfSniffingMenuState | `Widget _buildEmptyState(String message)` | Operación `_buildEmptyState`. |
| 1038 | método | _LfSniffingMenuState | `Widget _summaryCard( BuildContext context, String title, String value, String subtitle, {required double width})` | Operación `_summaryCard`. |
| 1058 | método | _LfSniffingMenuState | `Widget _buildPanel({ required Widget child, EdgeInsetsGeometry padding = const EdgeInsets.all(16), })` | Operación `_buildPanel`. |
| 1074 | método | _LfSniffingMenuState | `Widget _compactInfoColumn(String label, String value)` | Operación `_compactInfoColumn`. |
| 1094 | método | _LfSniffingMenuState | `Widget _buildHexLegend( AppLocalizations localizations, LfSniffSummary summary)` | Operación `_buildHexLegend`. |
| 1225 | método | _LfSniffingMenuState | `Widget _buildHexColorLegendItem({ required Color color, required String label, })` | Operación `_buildHexColorLegendItem`. |
| 1246 | método | _LfSniffingMenuState | `Widget _buildHexGlyphLegendItem({ required String glyph, required String label, })` | Operación `_buildHexGlyphLegendItem`. |
| 1276 | constructor | _LfWaveformSurface | `const _LfWaveformSurface({ required this.capture, required this.plotWidth, required this.plotHeight, required this.controller, this.scrollbarThickness = 8, })` | Construye _LfWaveformSurface. |
| 1284 | método | _LfWaveformSurface | `@override Widget build(BuildContext context)` | Construye la interfaz de _LfWaveformSurface. |
| 1323 | constructor | _LfWaveformFullscreenPage | `const _LfWaveformFullscreenPage({ required this.capture, required this.initialZoom, })` | Construye _LfWaveformFullscreenPage. |
| 1328 | método | _LfWaveformFullscreenPage | `@override State<_LfWaveformFullscreenPage> createState()` | Operación `createState`. |
| 1337 | método | _LfWaveformFullscreenPageState | `@override void initState()` | Inicializa el estado de _LfWaveformFullscreenPageState. |
| 1344 | método | _LfWaveformFullscreenPageState | `@override void dispose()` | Libera recursos de _LfWaveformFullscreenPageState. |
| 1350 | método | _LfWaveformFullscreenPageState | `@override Widget build(BuildContext context)` | Construye la interfaz de _LfWaveformFullscreenPageState. |
| 1430 | constructor | _LfWaveformZoomControls | `const _LfWaveformZoomControls({ required this.label, required this.zoom, required this.compact, required this.onChanged, })` | Construye _LfWaveformZoomControls. |
| 1437 | método | _LfWaveformZoomControls | `@override Widget build(BuildContext context)` | Construye la interfaz de _LfWaveformZoomControls. |
| 1484 | constructor | _LfWaveformPainter | `const _LfWaveformPainter({ required this.samples, required this.mean, required this.threshold, required this.colorScheme, })` | Construye _LfWaveformPainter. |
| 1491 | método | _LfWaveformPainter | `@override void paint(Canvas canvas, Size size)` | Operación `paint`. |
| 1564 | método | _LfWaveformPainter | `@override bool shouldRepaint(covariant _LfWaveformPainter oldDelegate)` | Operación `shouldRepaint`. |
## `lib/gui/menu/tools/t55xx_password_cleaner.dart`

| Línea | Tipo | Owner | Firma | Descripción |
|---:|---|---|---|---|
| 13 | constructor | T55XXPasswordCleanerMenu | `const T55XXPasswordCleanerMenu({super.key})` | Construye T55XXPasswordCleanerMenu. |
| 15 | método | T55XXPasswordCleanerMenu | `@override T55XXPasswordCleanerMenuState createState()` | Operación `createState`. |
| 29 | método | T55XXPasswordCleanerMenuState | `@override void initState()` | Inicializa el estado de T55XXPasswordCleanerMenuState. |
| 35 | método | T55XXPasswordCleanerMenuState | `@override void dispose()` | Libera recursos de T55XXPasswordCleanerMenuState. |
| 41 | método | T55XXPasswordCleanerMenuState | `Future<void> _startPasswordReset()` | Operación `_startPasswordReset`. |
| 113 | método | T55XXPasswordCleanerMenuState | `void showSuccessDialog(AppLocalizations localizations, String password)` | Operación `showSuccessDialog`. |
| 131 | método | T55XXPasswordCleanerMenuState | `void showFailureDialog(AppLocalizations localizations)` | Operación `showFailureDialog`. |
| 149 | método | T55XXPasswordCleanerMenuState | `void showErrorDialog(String error)` | Operación `showErrorDialog`. |
| 158 | método | T55XXPasswordCleanerMenuState | `@override Widget build(BuildContext context)` | Construye la interfaz de T55XXPasswordCleanerMenuState. |
## `lib/gui/page/connect.dart`

| Línea | Tipo | Owner | Firma | Descripción |
|---:|---|---|---|---|
| 15 | constructor | ConnectPage | `const ConnectPage({super.key})` | Construye ConnectPage. |
| 17 | método | ConnectPage | `@override State<ConnectPage> createState()` | Operación `createState`. |
| 24 | getter | _ConnectPageState | `ChameleonGUIState get _appState` | Obtiene `_appState`. |
| 27 | método | _ConnectPageState | `@override void initState()` | Inicializa el estado de _ConnectPageState. |
| 40 | método | _ConnectPageState | `void _showPermissionsWarningIfNeeded(List<Chameleon> devices)` | Operación `_showPermissionsWarningIfNeeded`. |
| 76 | método | _ConnectPageState | `Future<void> _onDeviceTap(Chameleon chameleonDevice)` | Operación `_onDeviceTap`. |
| 84 | método | _ConnectPageState | `void _showDfuDialog(Chameleon chameleonDevice)` | Operación `_showDfuDialog`. |
| 138 | método | _ConnectPageState | `Widget _buildDeviceGrid( AppLocalizations localizations, List<Chameleon> devices, )` | Operación `_buildDeviceGrid`. |
| 221 | método | _ConnectPageState | `@override Widget build(BuildContext context)` | Construye la interfaz de _ConnectPageState. |
## `lib/gui/page/data_sync.dart`

| Línea | Tipo | Owner | Firma | Descripción |
|---:|---|---|---|---|
| 21 | función | - | `String? validateDataSyncPassword(String? value, AppLocalizations strings)` | Función `validateDataSyncPassword`. |
| 30 | constructor | DataSyncPage | `const DataSyncPage({super.key})` | Construye DataSyncPage. |
| 32 | método | DataSyncPage | `@override State<DataSyncPage> createState()` | Operación `createState`. |
| 46 | getter | _DataSyncPageState | `ChameleonGUIState get _app` | Obtiene `_app`. |
| 47 | getter | _DataSyncPageState | `AppLocalizations get _strings` | Obtiene `_strings`. |
| 49 | método | _DataSyncPageState | `@override void didChangeDependencies()` | Operación `didChangeDependencies`. |
| 57 | método | _DataSyncPageState | `Future<void> _loadPendingRecovery()` | Operación `_loadPendingRecovery`. |
| 68 | método | _DataSyncPageState | `@override void dispose()` | Libera recursos de _DataSyncPageState. |
| 78 | método | _DataSyncPageState | `Future<void> _run(Future<void> Function() action)` | Operación `_run`. |
| 90 | método | _DataSyncPageState | `void _message(String message, {bool error = false})` | Operación `_message`. |
| 101 | método | _DataSyncPageState | `Future<void> _startHost()` | Operación `_startHost`. |
| 153 | método | _DataSyncPageState | `Future<bool> _approveHostedSnapshot(SyncSnapshot snapshot)` | Operación `_approveHostedSnapshot`. |
| 192 | método | _DataSyncPageState | `Future<void> _stopHost()` | Operación `_stopHost`. |
| 202 | método | _DataSyncPageState | `Future<void> _joinNearby()` | Operación `_joinNearby`. |
| 259 | getter | _DataSyncPageState | `bool get _canScanQr` | Obtiene `_canScanQr`. |
| 261 | método | _DataSyncPageState | `Future<void> _connectAndMerge(String pairingCode)` | Operación `_connectAndMerge`. |
| 310 | método | _DataSyncPageState | `Future<void> _exportFile()` | Operación `_exportFile`. |
| 336 | método | _DataSyncPageState | `Future<void> _importFile()` | Operación `_importFile`. |
| 380 | método | _DataSyncPageState | `Future<String?> _passwordDialog({required bool confirm})` | Operación `_passwordDialog`. |
| 448 | método | _DataSyncPageState | `String _statusText(DataSyncHostStatus status)` | Operación `_statusText`. |
| 459 | método | _DataSyncPageState | `@override Widget build(BuildContext context)` | Construye la interfaz de _DataSyncPageState. |
| 621 | constructor | _SectionTitle | `const _SectionTitle({ required this.icon, required this.title, required this.description, })` | Construye _SectionTitle. |
| 631 | método | _SectionTitle | `@override Widget build(BuildContext context)` | Construye la interfaz de _SectionTitle. |
| 652 | constructor | _ActionCard | `const _ActionCard({ required this.icon, required this.title, required this.description, required this.action, required this.actionLabel, this.child, })` | Construye _ActionCard. |
| 668 | método | _ActionCard | `@override Widget build(BuildContext context)` | Construye la interfaz de _ActionCard. |
| 700 | constructor | _HostDetails | `const _HostDetails({ required this.host, required this.status, required this.copyLabel, required this.onCopy, })` | Construye _HostDetails. |
| 712 | método | _HostDetails | `@override Widget build(BuildContext context)` | Construye la interfaz de _HostDetails. |
| 739 | función | - | `Future<SyncSnapshot?> showDataSyncConflictDialog( BuildContext context, SyncMergePlan plan, { required String actionLabel, })` | Función `showDataSyncConflictDialog`. |
| 752 | constructor | _ConflictDialog | `const _ConflictDialog({required this.plan, required this.actionLabel})` | Construye _ConflictDialog. |
| 757 | método | _ConflictDialog | `@override State<_ConflictDialog> createState()` | Operación `createState`. |
| 762 | método | _ConflictDialogState | `@override Widget build(BuildContext context)` | Construye la interfaz de _ConflictDialogState. |
| 818 | método | _ConflictDialogState | `Widget _cardConflict(CardConflict conflict, AppLocalizations strings)` | Operación `_cardConflict`. |
| 859 | método | _ConflictDialogState | `Widget _scriptConflict(ScriptConflict conflict, AppLocalizations strings)` | Operación `_scriptConflict`. |
| 889 | método | _ConflictDialogState | `Widget _settingConflict(SettingConflict conflict, AppLocalizations strings)` | Operación `_settingConflict`. |
| 913 | constructor | _ConflictHeading | `const _ConflictHeading(this.text)` | Construye _ConflictHeading. |
| 916 | método | _ConflictHeading | `@override Widget build(BuildContext context)` | Construye la interfaz de _ConflictHeading. |
| 924 | constructor | _ChoiceRow | `const _ChoiceRow({ required this.label, required this.value, required this.choices, required this.choiceLabel, required this.onChanged, })` | Construye _ChoiceRow. |
| 938 | método | _ChoiceRow | `@override Widget build(BuildContext context)` | Construye la interfaz de _ChoiceRow. |
| 964 | constructor | _SourceText | `const _SourceText({required this.label, required this.source})` | Construye _SourceText. |
| 968 | método | _SourceText | `@override Widget build(BuildContext context)` | Construye la interfaz de _SourceText. |
| 994 | función | - | `String _snapshotSummary(SyncSnapshot snapshot, AppLocalizations strings)` | Función `_snapshotSummary`. |
| 1002 | función | - | `String _hex(List<int> bytes)` | Función `_hex`. |
## `lib/gui/page/debug.dart`

| Línea | Tipo | Owner | Firma | Descripción |
|---:|---|---|---|---|
| 21 | constructor | DebugPage | `const DebugPage({super.key})` | Construye DebugPage. |
| 23 | método | DebugPage | `@override Widget build(BuildContext context)` | Construye la interfaz de DebugPage. |
## `lib/gui/page/ethical_hacking.dart`

| Línea | Tipo | Owner | Firma | Descripción |
|---:|---|---|---|---|
| 49 | constructor | _Category | `_Category(this.name, this.icon, this.open, {required this.count})` | Construye _Category. |
| 53 | constructor | EthicalHackingPage | `const EthicalHackingPage({super.key})` | Construye EthicalHackingPage. |
| 55 | método | EthicalHackingPage | `@override EthicalHackingPageState createState()` | Operación `createState`. |
| 60 | método | EthicalHackingPageState | `void _push(BuildContext context, Widget page)` | Operación `_push`. |
| 64 | método | EthicalHackingPageState | `void _dialog(BuildContext context, Widget dialog)` | Operación `_dialog`. |
| 68 | método | EthicalHackingPageState | `Widget _disclaimer(BuildContext context)` | Operación `_disclaimer`. |
| 100 | método | EthicalHackingPageState | `@override Widget build(BuildContext context)` | Construye la interfaz de EthicalHackingPageState. |
## `lib/gui/page/flashing.dart`

| Línea | Tipo | Owner | Firma | Descripción |
|---:|---|---|---|---|
| 11 | constructor | FlashingPage | `const FlashingPage({super.key})` | Construye FlashingPage. |
| 13 | método | FlashingPage | `@override Widget build(BuildContext context)` | Construye la interfaz de FlashingPage. |
## `lib/gui/page/home.dart`

| Línea | Tipo | Owner | Firma | Descripción |
|---:|---|---|---|---|
| 18 | constructor | HomePage | `const HomePage({super.key})` | Construye HomePage. |
| 20 | método | HomePage | `@override HomePageState createState()` | Operación `createState`. |
| 28 | método | HomePageState | `@override void initState()` | Inicializa el estado de HomePageState. |
| 33 | método | HomePageState | `Future<((Icon, BatteryCharge), String, List<String>, bool, bool)> getFutureData()` | Operación `getFutureData`. |
| 52 | método | HomePageState | `Future<bool> areCapabilitiesSupported()` | Operación `areCapabilitiesSupported`. |
| 66 | método | HomePageState | `Future<(Icon, BatteryCharge)> getBatteryInfo()` | Operación `getBatteryInfo`. |
| 98 | método | HomePageState | `Future<String> getUsedSlotsOut8(List<SlotTypes> slotTypes)` | Operación `getUsedSlotsOut8`. |
| 113 | método | HomePageState | `Future<List<String>> getVersion()` | Operación `getVersion`. |
| 188 | método | HomePageState | `Future<bool> isReaderDeviceMode()` | Operación `isReaderDeviceMode`. |
| 193 | método | HomePageState | `@override Widget build(BuildContext context)` | Construye la interfaz de HomePageState. |
## `lib/gui/page/pending_connection.dart`

| Línea | Tipo | Owner | Firma | Descripción |
|---:|---|---|---|---|
| 9 | constructor | PendingConnectionPage | `const PendingConnectionPage({super.key})` | Construye PendingConnectionPage. |
| 11 | método | PendingConnectionPage | `@override Widget build(BuildContext context)` | Construye la interfaz de PendingConnectionPage. |
## `lib/gui/page/read_card.dart`

| Línea | Tipo | Owner | Firma | Descripción |
|---:|---|---|---|---|
| 42 | constructor | HFCardInfo | `HFCardInfo({ this.uid = '', this.sak = '', this.atqa = '', this.tech = '', this.ats = '', this.type = TagType.unknown, this.cardExist = true, })` | Construye HFCardInfo. |
| 57 | constructor | LFCardInfo | `LFCardInfo({this.cardExist = true})` | Construye LFCardInfo. |
| 68 | constructor | MifareClassicInfo | `MifareClassicInfo({ MifareClassicRecovery? recovery, this.isEV1 = false, this.type = MifareClassicType.none, this.state = MifareClassicState.none, NTLevel? ntLevel, bool? hasBackdoor, })` | Construye MifareClassicInfo. |
| 82 | constructor | MifareUltralightInfo | `MifareUltralightInfo()` | Construye MifareUltralightInfo. |
| 86 | constructor | ReadCardPage | `const ReadCardPage({super.key})` | Construye ReadCardPage. |
| 88 | método | ReadCardPage | `@override ReadCardPageState createState()` | Operación `createState`. |
| 110 | método | ReadCardPageState | `@override void initState()` | Inicializa el estado de ReadCardPageState. |
| 139 | método | ReadCardPageState | `void updateMifareClassicRecovery()` | Operación `updateMifareClassicRecovery`. |
| 146 | método | ReadCardPageState | `void updateMifareClassicInfo()` | Operación `updateMifareClassicInfo`. |
| 153 | método | ReadCardPageState | `Future<void> readLFInfo({bool Function()? shouldApply})` | Operación `readLFInfo`. |
| 191 | método | ReadCardPageState | `Future<void> startContinuousHFScan()` | Operación `startContinuousHFScan`. |
| 201 | método | ReadCardPageState | `Future<void> _pollHF()` | Operación `_pollHF`. |
| 223 | método | ReadCardPageState | `void stopContinuousHFScan()` | Operación `stopContinuousHFScan`. |
| 233 | método | ReadCardPageState | `Future<void> startContinuousLFScan()` | Operación `startContinuousLFScan`. |
| 243 | método | ReadCardPageState | `Future<void> _pollLF()` | Operación `_pollLF`. |
| 261 | método | ReadCardPageState | `void stopContinuousLFScan()` | Operación `stopContinuousLFScan`. |
| 271 | método | ReadCardPageState | `@override void dispose()` | Libera recursos de ReadCardPageState. |
| 279 | método | ReadCardPageState | `Future<void> saveHFCard()` | Operación `saveHFCard`. |
| 306 | método | ReadCardPageState | `Future<void> saveLFCard()` | Operación `saveLFCard`. |
| 320 | método | ReadCardPageState | `Widget buildFieldRow(String label, String value, double fontSize)` | Operación `buildFieldRow`. |
| 333 | método | ReadCardPageState | `@override Widget build(BuildContext context)` | Construye la interfaz de ReadCardPageState. |
## `lib/gui/page/reader_keys.dart`

| Línea | Tipo | Owner | Firma | Descripción |
|---:|---|---|---|---|
| 24 | constructor | _SlotEntry | `_SlotEntry(this.index, this.label)` | Construye _SlotEntry. |
| 31 | constructor | ReaderKeysPage | `const ReaderKeysPage({super.key})` | Construye ReaderKeysPage. |
| 33 | método | ReaderKeysPage | `@override ReaderKeysPageState createState()` | Operación `createState`. |
| 66 | método | ReaderKeysPageState | `@override void initState()` | Inicializa el estado de ReaderKeysPageState. |
| 77 | método | ReaderKeysPageState | `@override void dispose()` | Libera recursos de ReaderKeysPageState. |
| 101 | getter | ReaderKeysPageState | `ChameleonGUIState get _app` | Obtiene `_app`. |
| 102 | getter | ReaderKeysPageState | `bool get _connected` | Obtiene `_connected`. |
| 104 | método | ReaderKeysPageState | `void _startPolling()` | Operación `_startPolling`. |
| 112 | método | ReaderKeysPageState | `Future<void> _refreshStatus()` | Operación `_refreshStatus`. |
| 126 | método | ReaderKeysPageState | `Future<void> _refreshCount()` | Operación `_refreshCount`. |
| 150 | método | ReaderKeysPageState | `Future<void> _loadSlots()` | Operación `_loadSlots`. |
| 169 | método | ReaderKeysPageState | `void _showMessage(String message)` | Operación `_showMessage`. |
| 176 | método | ReaderKeysPageState | `String _randomUidHex([int bytes = 4])` | Operación `_randomUidHex`. |
| 186 | método | ReaderKeysPageState | `Future<void> _onSlotSelected(int index)` | Operación `_onSlotSelected`. |
| 203 | método | ReaderKeysPageState | `Future<void> _loadDumpIntoActiveSlot(CardSave card)` | Operación `_loadDumpIntoActiveSlot`. |
| 259 | método | ReaderKeysPageState | `Future<void> _arm()` | Operación `_arm`. |
| 381 | método | ReaderKeysPageState | `Future<void> _stop()` | Operación `_stop`. |
| 415 | método | ReaderKeysPageState | `Future<void> _recoverKeys()` | Operación `_recoverKeys`. |
| 483 | método | ReaderKeysPageState | `Future<void> _saveRecoveredKeysDialog()` | Operación `_saveRecoveredKeysDialog`. |
| 562 | método | ReaderKeysPageState | `Widget _buildCardConfig()` | Operación `_buildCardConfig`. |
| 652 | método | ReaderKeysPageState | `Widget _buildFixedUidConfig()` | Operación `_buildFixedUidConfig`. |
| 684 | método | ReaderKeysPageState | `Widget _buildRandomConfig()` | Operación `_buildRandomConfig`. |
| 709 | método | ReaderKeysPageState | `List<Widget> _buildRecoveryResults()` | Operación `_buildRecoveryResults`. |
| 790 | método | ReaderKeysPageState | `Widget _buildCaptureSection()` | Operación `_buildCaptureSection`. |
| 850 | método | ReaderKeysPageState | `@override Widget build(BuildContext context)` | Construye la interfaz de ReaderKeysPageState. |
## `lib/gui/page/saved_cards.dart`

| Línea | Tipo | Owner | Firma | Descripción |
|---:|---|---|---|---|
| 32 | constructor | SavedCardsPage | `const SavedCardsPage({super.key})` | Construye SavedCardsPage. |
| 34 | método | SavedCardsPage | `@override SavedCardsPageState createState()` | Operación `createState`. |
| 41 | método | SavedCardsPageState | `@override Widget build(BuildContext context)` | Construye la interfaz de SavedCardsPageState. |
| 1055 | método | SavedCardsPageState | `Future<String?> dictMergeDialog(BuildContext context, Dictionary mergeDict)` | Operación `dictMergeDialog`. |
| 1073 | constructor | DictMergeDelegate | `DictMergeDelegate(this.dicts, this.mergeDict)` | Construye DictMergeDelegate. |
| 1077 | método | DictMergeDelegate | `@override List<Widget> buildActions(BuildContext context)` | Operación `buildActions`. |
| 1130 | método | DictMergeDelegate | `@override Widget buildLeading(BuildContext context)` | Operación `buildLeading`. |
| 1140 | método | DictMergeDelegate | `@override Widget buildResults(BuildContext context)` | Operación `buildResults`. |
| 1167 | método | DictMergeDelegate | `@override Widget buildSuggestions(BuildContext context)` | Operación `buildSuggestions`. |
## `lib/gui/page/settings.dart`

| Línea | Tipo | Owner | Firma | Descripción |
|---:|---|---|---|---|
| 27 | función | - | `Future<String> loadLicense(String license)` | Función `loadLicense`. |
| 32 | constructor | SettingsMainPage | `const SettingsMainPage({super.key})` | Construye SettingsMainPage. |
| 34 | método | SettingsMainPage | `@override SettingsMainPageState createState()` | Operación `createState`. |
| 39 | método | SettingsMainPageState | `@override void initState()` | Inicializa el estado de SettingsMainPageState. |
| 44 | método | SettingsMainPageState | `Future<(String, List<Map<String, String>>, PackageInfo)> getFutureData()` | Operación `getFutureData`. |
| 53 | método | SettingsMainPageState | `Future<String> fetchOCnames()` | Operación `fetchOCnames`. |
| 67 | método | SettingsMainPageState | `Future<List<Map<String, String>>> fetchContributors()` | Operación `fetchContributors`. |
| 71 | método | SettingsMainPageState | `@override Widget build(BuildContext context)` | Construye la interfaz de SettingsMainPageState. |
## `lib/gui/page/slot_manager.dart`

| Línea | Tipo | Owner | Firma | Descripción |
|---:|---|---|---|---|
| 19 | constructor | SlotManagerPage | `const SlotManagerPage({super.key})` | Construye SlotManagerPage. |
| 21 | método | SlotManagerPage | `@override SlotManagerPageState createState()` | Operación `createState`. |
| 46 | método | SlotManagerPageState | `@override void didChangeDependencies()` | Operación `didChangeDependencies`. |
| 52 | método | SlotManagerPageState | `Future<void> loadSlotData()` | Operación `loadSlotData`. |
| 70 | método | SlotManagerPageState | `void refreshSlot()` | Operación `refreshSlot`. |
| 79 | método | SlotManagerPageState | `void setUploadState(int progressBar)` | Operación `setUploadState`. |
| 93 | método | SlotManagerPageState | `Future<void> onTap( CardSave card, dynamic close, AppLocalizations localizations)` | Operación `onTap`. |
| 317 | método | SlotManagerPageState | `Future<String?> cardSelectDialog(BuildContext context)` | Operación `cardSelectDialog`. |
| 334 | método | SlotManagerPageState | `@override Widget build(BuildContext context)` | Construye la interfaz de SlotManagerPageState. |
## `lib/gui/page/tools.dart`

| Línea | Tipo | Owner | Firma | Descripción |
|---:|---|---|---|---|
| 23 | constructor | ToolItem | `ToolItem({ required this.name, required this.description, required this.icon, this.isDeviceRequired = false, this.showWipBadge = false, this.onPressed, })` | Construye ToolItem. |
| 34 | constructor | ToolsPage | `const ToolsPage({super.key})` | Construye ToolsPage. |
| 36 | método | ToolsPage | `@override ToolsPageState createState()` | Operación `createState`. |
| 41 | método | ToolsPageState | `@override Widget build(BuildContext context)` | Construye la interfaz de ToolsPageState. |
## `lib/gui/page/write_card.dart`

| Línea | Tipo | Owner | Firma | Descripción |
|---:|---|---|---|---|
| 15 | constructor | WriteCardPage | `const WriteCardPage({super.key})` | Construye WriteCardPage. |
| 17 | método | WriteCardPage | `@override WriteCardPageState createState()` | Operación `createState`. |
| 29 | método | WriteCardPageState | `Future<String?> cardSelectDialog(BuildContext context)` | Operación `cardSelectDialog`. |
| 41 | método | WriteCardPageState | `Future<void> onTap(CardSave selectedCard, dynamic close, AppLocalizations localizations)` | Operación `onTap`. |
| 63 | método | WriteCardPageState | `Future<void> detectMagicType()` | Operación `detectMagicType`. |
| 111 | método | WriteCardPageState | `void updateState()` | Operación `updateState`. |
| 117 | método | WriteCardPageState | `void updateProgress(int writeProgress)` | Operación `updateProgress`. |
| 123 | método | WriteCardPageState | `Future<void> writeCard()` | Operación `writeCard`. |
| 162 | método | WriteCardPageState | `void onStepContinue()` | Operación `onStepContinue`. |
| 218 | método | WriteCardPageState | `void onStepBack()` | Operación `onStepBack`. |
| 229 | método | WriteCardPageState | `void onStepReset()` | Operación `onStepReset`. |
| 236 | método | WriteCardPageState | `List<Widget> createButtonsForStep(ControlsDetails details, int step)` | Operación `createButtonsForStep`. |
| 281 | método | WriteCardPageState | `@override void initState()` | Inicializa el estado de WriteCardPageState. |
| 286 | método | WriteCardPageState | `@override Widget build(BuildContext context)` | Construye la interfaz de WriteCardPageState. |
## `lib/helpers/authorized_relay.dart`

| Línea | Tipo | Owner | Firma | Descripción |
|---:|---|---|---|---|
| 23 | método | AuthorizedRelayPollDelay | `Future<void> wait(Duration duration)` | Operación `wait`. |
| 42 | método | AuthorizedRelayPollDelay | `void wake()` | Operación `wake`. |
| 51 | método | AuthorizedRelayPollDelay | `void reset()` | Operación `reset`. |
| 62 | constructor | AuthorizedRelayBackendModeMapping | `const AuthorizedRelayBackendModeMapping({ required this.transparent, required this.appleTransit, })` | Construye AuthorizedRelayBackendModeMapping. |
| 70 | método | AuthorizedRelayBackendModeMapping | `T resolve(AuthorizedRelayBackendMode mode)` | Operación `resolve`. |
| 81 | constructor | AuthorizedRelayPrefetchedResponse | `AuthorizedRelayPrefetchedResponse({ required Uint8List command, required Uint8List response, }) : _command = Uint8List.fromList(command), _response = Uint8List.fromList(response)` | Construye AuthorizedRelayPrefetchedResponse. |
| 97 | getter | AuthorizedRelayPrefetchedResponse | `bool get available` | Obtiene `available`. |
| 99 | método | AuthorizedRelayPrefetchedResponse | `Uint8List? takeFor(Uint8List command)` | Operación `takeFor`. |
| 106 | método | AuthorizedRelayPrefetchedResponse | `static bool _sameBytes(Uint8List left, Uint8List right)` | Operación `_sameBytes`. |
| 139 | constructor | AuthorizedRelayPolicyFailure | `const AuthorizedRelayPolicyFailure(this.reason)` | Construye AuthorizedRelayPolicyFailure. |
| 143 | getter | AuthorizedRelayPolicyFailure | `String get message` | Obtiene `message`. |
| 186 | método | AuthorizedRelayPolicyFailure | `Map<String, String> toJson()` | Serializa AuthorizedRelayPolicyFailure. |
| 188 | método | AuthorizedRelayPolicyFailure | `@override String toString()` | Operación `toString`. |
| 195 | constructor | AuthorizedRelayApduDecision | `AuthorizedRelayApduDecision._({ required this.disposition, Uint8List? apdu, this.failure, this.evidence, }) : apdu = apdu == null ? null : Uint8List.fromList(apdu)` | Construye AuthorizedRelayApduDecision. |
| 207 | getter | AuthorizedRelayApduDecision | `bool get shouldForward` | Obtiene `shouldForward`. |
| 209 | factory | AuthorizedRelayApduDecision | `factory AuthorizedRelayApduDecision.passThrough(Uint8List apdu)` | Construye AuthorizedRelayApduDecision. |
| 215 | factory | AuthorizedRelayApduDecision | `factory AuthorizedRelayApduDecision.rewritten( Uint8List apdu, AuthorizedRelayGpoRewriteEvidence evidence, )` | Construye AuthorizedRelayApduDecision. |
| 224 | factory | AuthorizedRelayApduDecision | `factory AuthorizedRelayApduDecision.rejected( AuthorizedRelayPolicyFailureReason reason, )` | Construye AuthorizedRelayApduDecision. |
| 239 | constructor | AuthorizedRelayBackendObservation | `const AuthorizedRelayBackendObservation._({ required this.disposition, this.failure, })` | Construye AuthorizedRelayBackendObservation. |
| 254 | factory | AuthorizedRelayBackendObservation | `factory AuthorizedRelayBackendObservation.rejected( AuthorizedRelayPolicyFailureReason reason, )` | Construye AuthorizedRelayBackendObservation. |
| 267 | constructor | AuthorizedRelayApprovedPdolField | `const AuthorizedRelayApprovedPdolField(this.tagHex)` | Construye AuthorizedRelayApprovedPdolField. |
| 273 | constructor | AuthorizedRelayApprovedFieldRewrite | `const AuthorizedRelayApprovedFieldRewrite({ required this.field, required this.beforeHex, required this.afterHex, })` | Construye AuthorizedRelayApprovedFieldRewrite. |
| 283 | método | AuthorizedRelayApprovedFieldRewrite | `Map<String, String> toJson()` | Serializa AuthorizedRelayApprovedFieldRewrite. |
| 291 | constructor | AuthorizedRelayGpoRewriteEvidence | `AuthorizedRelayGpoRewriteEvidence({ required this.aidHex, required this.pdolDefinitionHex, required this.pdolDefinitionLength, required this.pdolValueLength, required this.apduLength, required this.leLength, required List<AuthorizedRelayApprovedFieldRewrite> fields, }) : fields = List.unmodifiable(fields)` | Construye AuthorizedRelayGpoRewriteEvidence. |
| 309 | método | AuthorizedRelayGpoRewriteEvidence | `Map<String, Object> toJson()` | Serializa AuthorizedRelayGpoRewriteEvidence. |
| 323 | constructor | AuthorizedRelaySessionPolicy | `AuthorizedRelaySessionPolicy({ this.mode = AuthorizedRelayBackendMode.transparent, })` | Construye AuthorizedRelaySessionPolicy. |
| 331 | getter | AuthorizedRelaySessionPolicy | `bool get hasActivePdol` | Obtiene `hasActivePdol`. |
| 333 | método | AuthorizedRelaySessionPolicy | `void clear()` | Operación `clear`. |
| 339 | método | AuthorizedRelaySessionPolicy | `AuthorizedRelayApduDecision prepareTerminalApdu(Uint8List apdu)` | Must run before the APDU is sent to the backend. |
| 356 | método | AuthorizedRelaySessionPolicy | `AuthorizedRelayBackendObservation observeBackendResponse({ required Uint8List terminalApdu, required Uint8List backendResponse, })` | Observes the exact backend response after a SELECT has been forwarded. |
| 391 | método | AuthorizedRelaySessionPolicy | `AuthorizedRelayApduDecision _rewriteGpo(Uint8List apdu)` | Operación `_rewriteGpo`. |
| 445 | constructor | _AuthorizedRelayPdolFieldLocation | `const _AuthorizedRelayPdolFieldLocation(this.offset, this.length)` | Construye _AuthorizedRelayPdolFieldLocation. |
| 452 | constructor | _AuthorizedRelayPdolLayout | `_AuthorizedRelayPdolLayout({ required Uint8List aid, required Uint8List definition, required this.valueLength, required Map< AuthorizedRelayApprovedPdolField, _AuthorizedRelayPdolFieldLocation > fields, }) : aid = Uint8List.fromList(aid), definition = Uint8List.fromList(definition), fields = Map.unmodifiable(fields)` | Construye _AuthorizedRelayPdolLayout. |
| 473 | constructor | _AuthorizedRelayPdolParseResult | `const _AuthorizedRelayPdolParseResult._({this.layout, this.failure})` | Construye _AuthorizedRelayPdolParseResult. |
| 478 | factory | _AuthorizedRelayPdolParseResult | `factory _AuthorizedRelayPdolParseResult.success( _AuthorizedRelayPdolLayout layout, )` | Construye _AuthorizedRelayPdolParseResult. |
| 482 | factory | _AuthorizedRelayPdolParseResult | `factory _AuthorizedRelayPdolParseResult.failure( AuthorizedRelayPolicyFailureReason failure, )` | Construye _AuthorizedRelayPdolParseResult. |
| 488 | constructor | _AuthorizedRelayGpoLayout | `const _AuthorizedRelayGpoLayout({ required this.valueOffset, required this.valueLength, required this.leLength, })` | Construye _AuthorizedRelayGpoLayout. |
| 500 | constructor | _AuthorizedRelayGpoParseResult | `const _AuthorizedRelayGpoParseResult._({this.layout, this.failure})` | Construye _AuthorizedRelayGpoParseResult. |
| 505 | factory | _AuthorizedRelayGpoParseResult | `factory _AuthorizedRelayGpoParseResult.success( _AuthorizedRelayGpoLayout layout, )` | Construye _AuthorizedRelayGpoParseResult. |
| 509 | factory | _AuthorizedRelayGpoParseResult | `factory _AuthorizedRelayGpoParseResult.failure( AuthorizedRelayPolicyFailureReason failure, )` | Construye _AuthorizedRelayGpoParseResult. |
| 514 | función | - | `bool _isAuthorizedRelaySelect(Uint8List apdu)` | Función `_isAuthorizedRelaySelect`. |
| 517 | función | - | `bool _isAuthorizedRelayGpo(Uint8List apdu)` | Función `_isAuthorizedRelayGpo`. |
| 520 | función | - | `Uint8List? _authorizedRelaySelectAid(Uint8List apdu)` | Función `_authorizedRelaySelectAid`. |
| 535 | función | - | `bool _isAuthorizedRelayPpseAid(Uint8List aid)` | Función `_isAuthorizedRelayPpseAid`. |
| 538 | función | - | `_AuthorizedRelayPdolParseResult _parseAuthorizedRelayFci( Uint8List selectedAid, Uint8List response, )` | Función `_parseAuthorizedRelayFci`. |
| 623 | función | - | `_AuthorizedRelayPdolParseResult _parseAuthorizedRelayPdol( Uint8List selectedAid, Uint8List definition, )` | Función `_parseAuthorizedRelayPdol`. |
| 710 | función | - | `_AuthorizedRelayGpoParseResult _parseAuthorizedRelayGpo(Uint8List apdu)` | Función `_parseAuthorizedRelayGpo`. |
| 766 | función | - | `AuthorizedRelayApprovedPdolField? _authorizedRelayApprovedField( Uint8List data, int start, int end, )` | Función `_authorizedRelayApprovedField`. |
| 780 | función | - | `Uint8List _authorizedRelayAppleValue(AuthorizedRelayApprovedPdolField field)` | Función `_authorizedRelayAppleValue`. |
| 791 | función | - | `String _authorizedRelayHex(Uint8List bytes)` | Función `_authorizedRelayHex`. |
| 797 | constructor | _AuthorizedRelayBerNode | `_AuthorizedRelayBerNode({ required this.tagHex, required this.constructed, required Uint8List value, required List<_AuthorizedRelayBerNode> children, }) : value = Uint8List.fromList(value), children = List.unmodifiable(children)` | Construye _AuthorizedRelayBerNode. |
| 812 | constructor | _AuthorizedRelayBerParser | `_AuthorizedRelayBerParser(this.data)` | Construye _AuthorizedRelayBerParser. |
| 820 | método | _AuthorizedRelayBerParser | `List<_AuthorizedRelayBerNode> parse()` | Operación `parse`. |
| 825 | método | _AuthorizedRelayBerParser | `List<_AuthorizedRelayBerNode> _parseRange(int start, int end, int depth)` | Operación `_parseRange`. |
| 886 | función | - | `int _authorizedRelayReadTagEnd(Uint8List data, int start, int end)` | Función `_authorizedRelayReadTagEnd`. |
| 905 | constructor | _AuthorizedRelayBerParseException | `const _AuthorizedRelayBerParseException()` | Construye _AuthorizedRelayBerParseException. |
| 917 | constructor | AuthorizedRelayTerminalApdu | `const AuthorizedRelayTerminalApdu({ required this.armToken, required this.id, required this.apdu, this.receivedUs, this.expiresAtUs, })` | Construye AuthorizedRelayTerminalApdu. |
| 933 | constructor | AuthorizedRelayExchange | `const AuthorizedRelayExchange({ required this.backend, required this.terminal, })` | Construye AuthorizedRelayExchange. |
| 947 | constructor | AuthorizedRelayRendezvous | `AuthorizedRelayRendezvous(this.armToken)` | Construye AuthorizedRelayRendezvous. |
| 959 | getter | AuthorizedRelayRendezvous | `T? get backend` | Obtiene `backend`. |
| 960 | getter | AuthorizedRelayRendezvous | `AuthorizedRelayTerminalApdu? get terminal` | Obtiene `terminal`. |
| 962 | getter | AuthorizedRelayRendezvous | `AuthorizedRelayRendezvousPhase get phase` | Obtiene `phase`. |
| 974 | método | AuthorizedRelayRendezvous | `bool acceptBackend(int token, T backend)` | Operación `acceptBackend`. |
| 982 | método | AuthorizedRelayRendezvous | `bool acceptTerminal(AuthorizedRelayTerminalApdu terminal)` | Operación `acceptTerminal`. |
| 994 | método | AuthorizedRelayRendezvous | `AuthorizedRelayExchange<T>? beginExchange(int token)` | Operación `beginExchange`. |
| 1003 | método | AuthorizedRelayRendezvous | `bool completeExchange(int token)` | Operación `completeExchange`. |
| 1010 | método | AuthorizedRelayRendezvous | `T? close()` | Operación `close`. |
| 1043 | constructor | AuthorizedRelaySessionBinding | `const AuthorizedRelaySessionBinding({ required this.communicator, required this.generation, required this.mode, required this.sessionId, }) : assert(generation > 0), assert(sessionId > 0)` | Construye AuthorizedRelaySessionBinding. |
| 1056 | método | AuthorizedRelaySessionBinding | `bool matches({ required C communicator, required int generation, required AuthorizedRelayBackendMode mode, required int sessionId, })` | Operación `matches`. |
| 1071 | factory | AuthorizedRelaySessionCapability | `factory AuthorizedRelaySessionCapability({ required AuthorizedRelaySessionBinding<C> binding, required B backend, })` | Construye AuthorizedRelaySessionCapability. |
| 1076 | constructor | AuthorizedRelaySessionCapability | `AuthorizedRelaySessionCapability._(this.binding, this._backend)` | Construye AuthorizedRelaySessionCapability. |
| 1081 | getter | AuthorizedRelaySessionCapability | `bool get available` | Obtiene `available`. |
| 1083 | método | AuthorizedRelaySessionCapability | `B? consume({ required C communicator, required int generation, required AuthorizedRelayBackendMode mode, required int sessionId, })` | Operación `consume`. |
| 1100 | método | AuthorizedRelaySessionCapability | `B? invalidate()` | Operación `invalidate`. |
| 1108 | constructor | AuthorizedRelayCleanupBarrier | `AuthorizedRelayCleanupBarrier._(this.predecessor, this._completions)` | Construye AuthorizedRelayCleanupBarrier. |
| 1113 | getter | AuthorizedRelayCleanupBarrier | `bool get completed` | Obtiene `completed`. |
| 1115 | método | AuthorizedRelayCleanupBarrier | `void complete()` | Operación `complete`. |
| 1131 | getter | AuthorizedRelayConnectionCoordinator | `bool get connected` | Obtiene `connected`. |
| 1132 | getter | AuthorizedRelayConnectionCoordinator | `bool get poisoned` | Obtiene `poisoned`. |
| 1133 | getter | AuthorizedRelayConnectionCoordinator | `int get generation` | Obtiene `generation`. |
| 1134 | getter | AuthorizedRelayConnectionCoordinator | `String? get poisonReason` | Obtiene `poisonReason`. |
| 1136 | método | AuthorizedRelayConnectionCoordinator | `Future<void> awaitCleanup()` | Operación `awaitCleanup`. |
| 1138 | método | AuthorizedRelayConnectionCoordinator | `AuthorizedRelayCleanupBarrier beginCleanup()` | Operación `beginCleanup`. |
| 1145 | método | AuthorizedRelayConnectionCoordinator | `void poison(String reason)` | Operación `poison`. |
| 1150 | método | AuthorizedRelayConnectionCoordinator | `void observeConnected()` | Operación `observeConnected`. |
| 1160 | método | AuthorizedRelayConnectionCoordinator | `void observeDisconnected()` | Operación `observeDisconnected`. |
| 1168 | método | AuthorizedRelayConnectionCoordinator | `void observeReplacement()` | Operación `observeReplacement`. |
| 1187 | método | AuthorizedRelayConnectionRegistry | `AuthorizedRelayConnectionCoordinator forCommunicator(C communicator)` | Operación `forCommunicator`. |
| 1190 | método | AuthorizedRelayConnectionRegistry | `Future<void> awaitCleanup(C communicator)` | Operación `awaitCleanup`. |
| 1195 | método | AuthorizedRelayConnectionRegistry | `AuthorizedRelayCleanupBarrier beginCleanup(C communicator)` | Operación `beginCleanup`. |
| 1207 | método | AuthorizedRelayConnectionRegistry | `AuthorizedRelayConnectionCoordinator? observeConnection({ required bool connected, required C? communicator, })` | Operación `observeConnection`. |
| 1229 | función | - | `bool isAuthorizedRelaySessionUncertainError(Object error)` | Función `isAuthorizedRelaySessionUncertainError`. |
| 1245 | función | - | `String authorizedRelayDeactivationFailure({ required Object? reason, required bool hasForwardedApdu, })` | Función `authorizedRelayDeactivationFailure`. |
| 1264 | función | - | `String authorizedRelayDeactivationNotice({ required Object? reason, required int deliveredApdus, })` | Función `authorizedRelayDeactivationNotice`. |
| 1282 | función | - | `bool _authorizedRelayBytesMatch(Uint8List first, Uint8List second)` | Función `_authorizedRelayBytesMatch`. |
| 1290 | función | - | `bool isAuthorizedRelayCardAbsentError(Object error)` | Función `isAuthorizedRelayCardAbsentError`. |
| 1297 | función | - | `Future<T?> waitForAuthorizedRelayBackendCard<T>({ required Future<T> Function() attempt, required bool Function() isCancelled, void Function()? onWaiting, Future<void> Function(Duration)? delay, })` | Función `waitForAuthorizedRelayBackendCard`. |
| 1320 | función | - | `List<String> extractAuthorizedRelayAids(Uint8List ppseResponse)` | Función `extractAuthorizedRelayAids`. |
| 1337 | función | - | `void _collectPaymentAids( Uint8List data, Set<String> aids, { required bool inApplicationTemplate, required int depth, })` | Función `_collectPaymentAids`. |
| 1402 | función | - | `String authorizedRelayApduSummary(Uint8List apdu)` | Función `authorizedRelayApduSummary`. |
| 1410 | función | - | `String authorizedRelayStatusSummary(Uint8List response)` | Función `authorizedRelayStatusSummary`. |
## `lib/helpers/ble/ble_address.dart`

| Línea | Tipo | Owner | Firma | Descripción |
|---:|---|---|---|---|
| 3 | función | - | `Uint8List bleAddressToLittleEndian(String address, {bool requireStaticRandom = false})` | Función `bleAddressToLittleEndian`. |
| 20 | función | - | `String bleAddressFromLittleEndian(Uint8List address)` | Función `bleAddressFromLittleEndian`. |
## `lib/helpers/ble/ble_advertising.dart`

| Línea | Tipo | Owner | Firma | Descripción |
|---:|---|---|---|---|
| 14 | constructor | BleAdStructure | `const BleAdStructure(this.type, this.value)` | Construye BleAdStructure. |
| 17 | función | - | `List<BleAdStructure> bleValidateAdvertisingData(Uint8List data, {bool scanResponse = false})` | Función `bleValidateAdvertisingData`. |
| 48 | función | - | `Uint8List bleParseAdvertisingHex(String value)` | Función `bleParseAdvertisingHex`. |
| 62 | función | - | `String bleFormatAdvertisingHex(Uint8List data)` | Función `bleFormatAdvertisingHex`. |
| 65 | función | - | `({Uint8List advertising, Uint8List scanResponse}) bleBuildAdvertisingProfile({ int flags = 0x06, int? serviceUuid, int? serviceDataUuid, Uint8List? serviceData, int? companyId, Uint8List? manufacturerData, })` | Función `bleBuildAdvertisingProfile`. |
| 130 | función | - | `({Uint8List advertising, Uint8List scanResponse}) bleBuildAppleProximityProfile( {int modelCode = 0x0e20})` | Función `bleBuildAppleProximityProfile`. |
| 172 | función | - | `({Uint8List advertising, Uint8List scanResponse}) bleBuildFastPairProfile({ int modelId = 0x2d7a23, int txPower = -20, })` | Función `bleBuildFastPairProfile`. |
| 217 | constructor | BleAdvertisingLabConfig | `const BleAdvertisingLabConfig({ required this.profile, required this.mode, required this.advertisingData, required this.scanResponseData, this.nameTarget = BleAdvertisingNameTarget.none, this.names = const [], this.intervalMs = 250, this.rotationMs = 0, this.durationMs = 0, this.maxAdvertisingEvents = 0, })` | Construye BleAdvertisingLabConfig. |
| 230 | método | BleAdvertisingLabConfig | `Uint8List toWire()` | Operación `toWire`. |
| 332 | método | BleAdvertisingLabConfig | `({Uint8List advertising, Uint8List scanResponse}) previewPackets()` | Operación `previewPackets`. |
| 367 | constructor | BleAdvertisingLabStatus | `const BleAdvertisingLabStatus({ required this.state, required this.profile, required this.mode, required this.reason, required this.activeNameIndex, required this.nameCount, required this.advertisingLength, required this.scanResponseLength, required this.intervalUnits, required this.rotationMs, required this.durationUnits, required this.maxAdvertisingEvents, required this.rotationCount, })` | Construye BleAdvertisingLabStatus. |
| 383 | getter | BleAdvertisingLabStatus | `bool get running` | Obtiene `running`. |
| 384 | getter | BleAdvertisingLabStatus | `bool get connected` | Obtiene `connected`. |
| 386 | factory | BleAdvertisingLabStatus | `factory BleAdvertisingLabStatus.fromWire(Uint8List data)` | Construye BleAdvertisingLabStatus. |
## `lib/helpers/ble/ble_presentation.dart`

| Línea | Tipo | Owner | Firma | Descripción |
|---:|---|---|---|---|
| 100 | función | - | `String? bleAdvertisingName(Uint8List advertisingData)` | Función `bleAdvertisingName`. |
| 121 | función | - | `String bleAdvertisingSummary(Uint8List advertisingData, {String serviceAbbreviation = 'svc'})` | Función `bleAdvertisingSummary`. |
| 153 | función | - | `List<String> bleAdvertisingDetails(Uint8List advertisingData)` | Función `bleAdvertisingDetails`. |
| 207 | función | - | `String bleUuidName(int uuid)` | Función `bleUuidName`. |
| 209 | función | - | `String bleAppearanceName(int appearance)` | Función `bleAppearanceName`. |
| 214 | función | - | `String bleCharacteristicPropertiesString(int properties)` | Función `bleCharacteristicPropertiesString`. |
| 224 | función | - | `bool bleCanWriteWithResponse(int properties)` | Función `bleCanWriteWithResponse`. |
| 226 | función | - | `bool bleCanFuzzWithoutResponse(int properties)` | Función `bleCanFuzzWithoutResponse`. |
| 228 | función | - | `String bleAttStatusDescription(int status)` | Función `bleAttStatusDescription`. |
| 239 | función | - | `Uint8List bleParseHexBytes(String value)` | Función `bleParseHexBytes`. |
| 249 | función | - | `String bleFormatHexBytes(Uint8List bytes)` | Función `bleFormatHexBytes`. |
| 254 | función | - | `String bleDeviceInfoLabel(int uuid)` | Función `bleDeviceInfoLabel`. |
| 259 | función | - | `String bleDeviceInfoValue(int uuid, int status, Uint8List data)` | Función `bleDeviceInfoValue`. |
| 279 | función | - | `int bleParseHexOrDecimal(String value)` | Función `bleParseHexOrDecimal`. |
## `lib/helpers/card_save_converters.dart`

| Línea | Tipo | Owner | Firma | Descripción |
|---:|---|---|---|---|
| 10 | función | - | `CardSave pm3JsonToCardSave(String json)` | Función `pm3JsonToCardSave`. |
| 58 | función | - | `CardSave flipperNfcToCardSave(String data)` | Función `flipperNfcToCardSave`. |
| 106 | función | - | `CardSave mctToCardSave(String data)` | Función `mctToCardSave`. |
| 151 | función | - | `CardSave flipperRfidToCardSave(String data)` | Función `flipperRfidToCardSave`. |
## `lib/helpers/colors.dart`

| Línea | Tipo | Owner | Firma | Descripción |
|---:|---|---|---|---|
| 37 | función | - | `int clampTheme(int theme)` | Función `clampTheme`. |
| 44 | función | - | `MaterialColor getThemeColor(int theme)` | Función `getThemeColor`. |
| 48 | función | - | `Color getThemeComplementary(int themeMode, int theme)` | Función `getThemeComplementary`. |
## `lib/helpers/data_sync.dart`

| Línea | Tipo | Owner | Firma | Descripción |
|---:|---|---|---|---|
| 26 | constructor | SyncState | `const SyncState({required this.snapshot, required this.checkpoint})` | Construye SyncState. |
| 28 | factory | SyncState | `factory SyncState.fromJsonMap(Object? value)` | Construye SyncState. |
| 44 | método | SyncState | `Map<String, Object> toJsonMap()` | Serializa SyncState. |
| 60 | factory | SyncSnapshot | `factory SyncSnapshot({ int version = currentVersion, Iterable<CardSave> cards = const [], Iterable<Dictionary> dictionaries = const [], Iterable<SavedKeyboardScript> keyboardScripts = const [], Map<String, Object> settings = const {}, })` | Construye SyncSnapshot. |
| 78 | constructor | SyncSnapshot | `const SyncSnapshot._({ required this.version, required this.cards, required this.dictionaries, required this.keyboardScripts, required this.settings, })` | Construye SyncSnapshot. |
| 86 | factory | SyncSnapshot | `factory SyncSnapshot.fromJson(String encoded)` | Construye SyncSnapshot. |
| 128 | método | SyncSnapshot | `Map<String, Object> toJsonMap()` | Serializa SyncSnapshot. |
| 140 | método | SyncSnapshot | `String toJson()` | Serializa SyncSnapshot. |
| 148 | método | SyncSnapshot | `void _validate()` | Operación `_validate`. |
| 207 | constructor | CardConflict | `CardConflict._(this.local, this.remote) : id = local.id, differingBlocks = List.unmodifiable(_differingBlocks(local, remote)), blockSelections = { for (final index in _differingBlocks(local, remote)) index: index < local.data.length ? SyncChoice.local : SyncChoice.remote, }, metadataSelection = SyncChoice.local` | Construye CardConflict. |
| 218 | método | CardConflict | `bool isBlockAvailable(int index, SyncChoice choice)` | Operación `isBlockAvailable`. |
| 223 | método | CardConflict | `CardSave resolve({ Map<int, SyncChoice> blockOverrides = const {}, SyncChoice? metadataOverride, })` | Operación `resolve`. |
| 264 | constructor | ScriptConflict | `ScriptConflict._(this.local, this.remote) : id = local.id, selection = ScriptChoice.local` | Construye ScriptConflict. |
| 275 | constructor | SettingConflict | `SettingConflict._(this.key, this.local, this.remote) : selection = SyncChoice.local` | Construye SettingConflict. |
| 286 | constructor | SyncResolution | `const SyncResolution({ this.cardBlocks = const {}, this.cardMetadata = const {}, this.scripts = const {}, this.settings = const {}, })` | Construye SyncResolution. |
| 303 | constructor | SyncMergePlan | `SyncMergePlan._({ required this.cards, required this.dictionaries, required this.keyboardScripts, required this.settings, required this.cardConflicts, required this.scriptConflicts, required this.settingConflicts, })` | Construye SyncMergePlan. |
| 313 | factory | SyncMergePlan | `factory SyncMergePlan.merge(SyncSnapshot local, SyncSnapshot remote)` | Construye SyncMergePlan. |
| 411 | método | SyncMergePlan | `SyncSnapshot resolve([SyncResolution resolution = const SyncResolution()])` | Operación `resolve`. |
| 476 | método | SyncMergePlan | `void _validateWorstCaseResolution()` | Operación `_validateWorstCaseResolution`. |
| 488 | función | - | `List<Uint8List> _extractConflictCardKeys(List<CardConflict> conflicts)` | Función `_extractConflictCardKeys`. |
| 505 | función | - | `bool _isMifareClassic(TagType tag)` | Función `_isMifareClassic`. |
| 511 | función | - | `bool _isSectorTrailer(TagType tag, int block)` | Función `_isSectorTrailer`. |
| 518 | función | - | `CardSave _decodeCard(Object? value)` | Función `_decodeCard`. |
| 573 | función | - | `Dictionary _decodeDictionary(Object? value)` | Función `_decodeDictionary`. |
| 596 | función | - | `SavedKeyboardScript _decodeScript(Object? value)` | Función `_decodeScript`. |
| 612 | función | - | `Map<String, Object> _decodeSettings(Map<String, dynamic> source)` | Función `_decodeSettings`. |
| 624 | función | - | `void _validateSettingValue(Object? value, int depth)` | Función `_validateSettingValue`. |
| 664 | función | - | `Object _copySettingValue(Object value)` | Función `_copySettingValue`. |
| 679 | función | - | `Map<String, Object> _copySettings(Map<String, Object> settings)` | Función `_copySettings`. |
| 684 | función | - | `List<Dictionary> _mergeDictionaries(List<Dictionary> dictionaries)` | Función `_mergeDictionaries`. |
| 728 | función | - | `void _addUniqueCard( List<CardSave> cards, Set<String> fingerprints, CardSave candidate, )` | Función `_addUniqueCard`. |
| 739 | función | - | `void _ensureCompatibleCardGeometry(CardSave local, CardSave remote)` | Función `_ensureCompatibleCardGeometry`. |
| 756 | función | - | `void _validateCardSemantics(CardSave card)` | Función `_validateCardSemantics`. |
| 760 | función | - | `String _normalizedUid(String value)` | Función `_normalizedUid`. |
| 763 | función | - | `void _validateDictionarySemantics(Dictionary dictionary)` | Función `_validateDictionarySemantics`. |
| 771 | función | - | `List<int> _differingBlocks(CardSave local, CardSave remote)` | Función `_differingBlocks`. |
| 786 | función | - | `String _cardFingerprint(CardSave card, {required bool includeId})` | Función `_cardFingerprint`. |
| 792 | función | - | `String _scriptFingerprint( SavedKeyboardScript script, { required bool includeId, })` | Función `_scriptFingerprint`. |
| 801 | función | - | `CardSave _copyCard(CardSave card)` | Función `_copyCard`. |
| 803 | función | - | `Dictionary _copyDictionary(Dictionary dictionary)` | Función `_copyDictionary`. |
| 806 | función | - | `SavedKeyboardScript _copyScript(SavedKeyboardScript script)` | Función `_copyScript`. |
| 809 | función | - | `SavedKeyboardScript _recreateScript( SavedKeyboardScript script, { required String id, required String name, })` | Función `_recreateScript`. |
| 822 | función | - | `String _uniqueScriptName(String original, Set<String> used)` | Función `_uniqueScriptName`. |
| 837 | función | - | `String _uniqueValue(String preferred, Set<String> used)` | Función `_uniqueValue`. |
| 847 | función | - | `bool _jsonEqual(Object? left, Object? right)` | Función `_jsonEqual`. |
| 869 | función | - | `Map<String, dynamic> _modelMap(String encoded)` | Función `_modelMap`. |
| 872 | función | - | `Map<String, dynamic> _stringMap(Object? value, String label)` | Función `_stringMap`. |
| 884 | función | - | `List<dynamic> _list(Object? value, String label)` | Función `_list`. |
| 889 | función | - | `void _byteList(Object? value, String label)` | Función `_byteList`. |
| 896 | función | - | `void _requireKeys(Map<String, dynamic> value, Set<String> keys, String label)` | Función `_requireKeys`. |
| 903 | función | - | `void _ensureUniqueIds(Iterable<String> ids, String label)` | Función `_ensureUniqueIds`. |
## `lib/helpers/data_sync_storage.dart`

| Línea | Tipo | Owner | Firma | Descripción |
|---:|---|---|---|---|
| 26 | método | DataSyncStorage | `Future<SyncState> createSyncState()` | Operación `createSyncState`. |
| 33 | método | DataSyncStorage | `SyncSnapshot _createSyncSnapshot()` | Operación `_createSyncSnapshot`. |
| 51 | método | DataSyncStorage | `Future<SyncTransactionReceipt> applySyncSnapshot( SyncSnapshot snapshot, { required SyncCheckpoint expectedCheckpoint, String? transactionId, })` | Operación `applySyncSnapshot`. |
| 68 | método | DataSyncStorage | `Future<SyncTransactionReceipt> prepareSyncSnapshot( String transactionId, SyncSnapshot snapshot, { required SyncCheckpoint expectedCheckpoint, SyncTransactionRole role = SyncTransactionRole.participant, SyncCheckpoint? peerCheckpoint, String? claimedTargetHash, })` | Operación `prepareSyncSnapshot`. |
| 86 | método | DataSyncStorage | `Future<SyncTransactionReceipt> commitSyncSnapshot( String transactionId, )` | Operación `commitSyncSnapshot`. |
| 96 | método | DataSyncStorage | `Map<String, Object> _validatedSyncValues(SyncSnapshot snapshot)` | Operación `_validatedSyncValues`. |
| 151 | constructor | SharedPreferencesDataSyncParticipant | `const SharedPreferencesDataSyncParticipant(this.preferences)` | Construye SharedPreferencesDataSyncParticipant. |
| 153 | método | SharedPreferencesDataSyncParticipant | `@override Future<SyncTransactionReceipt> prepare( String transactionId, SyncSnapshot snapshot, SyncCheckpoint expectedCheckpoint, { SyncTransactionRole role = SyncTransactionRole.participant, SyncCheckpoint? peerCheckpoint, String? claimedTargetHash, })` | Operación `prepare`. |
| 170 | método | SharedPreferencesDataSyncParticipant | `@override Future<SyncTransactionReceipt> commit(String transactionId)` | Operación `commit`. |
| 174 | método | SharedPreferencesDataSyncParticipant | `@override Future<SyncTransactionReceipt> abortFromCoordinator( String transactionId, String targetHash, )` | Operación `abortFromCoordinator`. |
| 183 | método | SharedPreferencesDataSyncParticipant | `@override Future<SyncTransactionReceipt> reject( String transactionId, String targetHash, )` | Operación `reject`. |
| 189 | método | SharedPreferencesDataSyncParticipant | `@override Future<SyncTransactionReceipt?> query(String transactionId)` | Operación `query`. |
| 193 | método | SharedPreferencesDataSyncParticipant | `@override Future<SyncCoordinatorRecovery?> coordinatorRecovery()` | Operación `coordinatorRecovery`. |
| 197 | método | SharedPreferencesDataSyncParticipant | `@override Future<SyncCoordinatorRecovery> decideCoordinatorAbort( String transactionId, )` | Operación `decideCoordinatorAbort`. |
| 202 | método | SharedPreferencesDataSyncParticipant | `@override Future<void> completeCoordinator(String transactionId)` | Operación `completeCoordinator`. |
| 206 | método | SharedPreferencesDataSyncParticipant | `@override Future<SyncTransactionReceipt?> pendingParticipant()` | Operación `pendingParticipant`. |
| 211 | función | - | `bool _syncBool(Map<String, Object> settings, String key)` | Función `_syncBool`. |
| 217 | función | - | `int _syncInt(Map<String, Object> settings, String key, int min, int max)` | Función `_syncInt`. |
| 225 | función | - | `String _syncString(Map<String, Object> settings, String key, int maxLength)` | Función `_syncString`. |
| 233 | función | - | `Locale _parseLocale(String value)` | Función `_parseLocale`. |
| 240 | función | - | `List<CardSave> _uniqueCards(List<CardSave> cards)` | Función `_uniqueCards`. |
| 261 | función | - | `List<Dictionary> _uniqueDictionaries(List<Dictionary> dictionaries)` | Función `_uniqueDictionaries`. |
| 282 | función | - | `List<SavedKeyboardScript> _uniqueScripts(List<SavedKeyboardScript> scripts)` | Función `_uniqueScripts`. |
| 308 | función | - | `String _stableDuplicateId(String base, String encoded)` | Función `_stableDuplicateId`. |
## `lib/helpers/data_sync_transport.dart`

| Línea | Tipo | Owner | Firma | Descripción |
|---:|---|---|---|---|
| 23 | método | DataSyncBundleCodec | `static Future<Uint8List> encode( SyncSnapshot snapshot, String password, )` | Operación `encode`. |
| 70 | método | DataSyncBundleCodec | `static Future<SyncSnapshot> decode(List<int> bundle, String password)` | Operación `decode`. |
| 125 | método | DataSyncBundleCodec | `static Future<SecretKey> _bundleKey(String password, List<int> salt)` | Operación `_bundleKey`. |
| 142 | constructor | DataSyncPairingCode | `DataSyncPairingCode._(this.address, this.port, this.key)` | Construye DataSyncPairingCode. |
| 144 | factory | DataSyncPairingCode | `factory DataSyncPairingCode.parse(String encoded)` | Construye DataSyncPairingCode. |
| 191 | método | DataSyncPairingCode | `String encode()` | Operación `encode`. |
| 220 | método | DataSyncTransactionParticipant | `Future<SyncTransactionReceipt> prepare( String transactionId, SyncSnapshot snapshot, SyncCheckpoint expectedCheckpoint, { SyncTransactionRole role = SyncTransactionRole.participant, SyncCheckpoint? peerCheckpoint, String? claimedTargetHash, })` | Operación `prepare`. |
| 229 | método | DataSyncTransactionParticipant | `Future<SyncTransactionReceipt> commit(String transactionId)` | Operación `commit`. |
| 231 | método | DataSyncTransactionParticipant | `Future<SyncTransactionReceipt> abortFromCoordinator( String transactionId, String targetHash, )` | Operación `abortFromCoordinator`. |
| 236 | método | DataSyncTransactionParticipant | `Future<SyncTransactionReceipt> reject( String transactionId, String targetHash, )` | Operación `reject`. |
| 241 | método | DataSyncTransactionParticipant | `Future<SyncTransactionReceipt?> query(String transactionId)` | Operación `query`. |
| 243 | método | DataSyncTransactionParticipant | `Future<SyncCoordinatorRecovery?> coordinatorRecovery()` | Operación `coordinatorRecovery`. |
| 245 | método | DataSyncTransactionParticipant | `Future<SyncCoordinatorRecovery> decideCoordinatorAbort(String transactionId)` | Operación `decideCoordinatorAbort`. |
| 247 | método | DataSyncTransactionParticipant | `Future<void> completeCoordinator(String transactionId)` | Operación `completeCoordinator`. |
| 249 | método | DataSyncTransactionParticipant | `Future<SyncTransactionReceipt?> pendingParticipant()` | Operación `pendingParticipant`. |
| 282 | constructor | DataSyncPeerHost | `DataSyncPeerHost._( this._localState, this._participant, this._onApprove, this._onCommitted, this._timeout, this._interactionTimeout, this._onStatus, this._server, this._key, this.displayAddress, this.pairingCode, this._debugDisconnectAfterCommit, this._maxPreAuthFailures, this._preAuthBackoff, )` | Construye DataSyncPeerHost. |
| 299 | getter | DataSyncPeerHost | `int get port` | Obtiene `port`. |
| 300 | getter | DataSyncPeerHost | `DataSyncHostStatus get status` | Obtiene `status`. |
| 301 | getter | DataSyncPeerHost | `Stream<DataSyncHostStatus> get statusStream` | Obtiene `statusStream`. |
| 302 | getter | DataSyncPeerHost | `Future<void> get done` | Obtiene `done`. |
| 304 | método | DataSyncPeerHost | `static Future<DataSyncPeerHost> start({ required SyncState localState, required DataSyncTransactionParticipant participant, required DataSyncApproval onApprove, DataSyncCommitted? onCommitted, InternetAddress? addressOverride, Duration timeout = defaultTimeout, Duration interactionTimeout = defaultInteractionTimeout, DataSyncStatusCallback? onStatus, @visibleForTesting bool debugDisconnectAfterCommit = false, @visibleForTesting int debugMaxPreAuthFailures = 8, @visibleForTesting Duration debugPreAuthBackoff = const Duration(seconds: 5), })` | Operación `start`. |
| 362 | método | DataSyncPeerHost | `void _accept(Socket socket)` | Operación `_accept`. |
| 375 | método | DataSyncPeerHost | `Future<void> _runConnection(Socket socket)` | Operación `_runConnection`. |
| 407 | método | DataSyncPeerHost | `Future<void> _handleInitialExchange( _EncryptedChannel channel, Uint8List payload, )` | Operación `_handleInitialExchange`. |
| 421 | método | DataSyncPeerHost | `Future<void> _handlePrepare( _EncryptedChannel channel, Uint8List payload, )` | Operación `_handlePrepare`. |
| 464 | método | DataSyncPeerHost | `Future<void> _handleQuery( _EncryptedChannel channel, Uint8List payload, )` | Operación `_handleQuery`. |
| 484 | método | DataSyncPeerHost | `Future<void> _respondFromReceipt( _EncryptedChannel channel, SyncTransactionReceipt receipt, )` | Operación `_respondFromReceipt`. |
| 505 | método | DataSyncPeerHost | `Future<void> _awaitDecision( _EncryptedChannel channel, String transactionId, String targetHash, )` | Operación `_awaitDecision`. |
| 544 | método | DataSyncPeerHost | `void _serverError(Object _)` | Operación `_serverError`. |
| 548 | método | DataSyncPeerHost | `void _recordPreAuthFailure()` | Operación `_recordPreAuthFailure`. |
| 560 | método | DataSyncPeerHost | `Future<void> _fail()` | Operación `_fail`. |
| 570 | método | DataSyncPeerHost | `Future<void> _finishTerminal(DataSyncHostStatus status)` | Operación `_finishTerminal`. |
| 578 | método | DataSyncPeerHost | `void _emit(DataSyncHostStatus status)` | Operación `_emit`. |
| 584 | método | DataSyncPeerHost | `Future<void> stop()` | Operación `stop`. |
| 594 | método | DataSyncPeerHost | `Future<void> dispose()` | Libera recursos de DataSyncPeerHost. |
| 596 | método | DataSyncPeerHost | `Future<void> _finish()` | Operación `_finish`. |
| 612 | constructor | DataSyncClientExchange | `DataSyncClientExchange._( this.remoteState, this._localState, this._participant, this._pairing, this._channel, this._timeout, this._interactionTimeout, )` | Construye DataSyncClientExchange. |
| 622 | getter | DataSyncClientExchange | `SyncSnapshot get remoteSnapshot` | Obtiene `remoteSnapshot`. |
| 624 | método | DataSyncClientExchange | `Future<bool> complete(SyncSnapshot mergedSnapshot)` | Operación `complete`. |
| 718 | método | DataSyncClientExchange | `Future<bool> _recoverCommitted(SyncCoordinatorRecovery recovery)` | Operación `_recoverCommitted`. |
| 733 | método | DataSyncClientExchange | `void close()` | Operación `close`. |
| 740 | método | DataSyncPeerClient | `static Future<void> resumePending({ required String pairingCode, required SyncCoordinatorRecovery recovery, required DataSyncTransactionParticipant participant, Duration timeout = DataSyncPeerHost.defaultTimeout, Duration interactionTimeout = DataSyncPeerHost.defaultInteractionTimeout, })` | Operación `resumePending`. |
| 779 | método | DataSyncPeerClient | `static Future<void> resumeCommitted({ required String pairingCode, required SyncCoordinatorRecovery recovery, required DataSyncTransactionParticipant participant, Duration timeout = DataSyncPeerHost.defaultTimeout, Duration interactionTimeout = DataSyncPeerHost.defaultInteractionTimeout, })` | Operación `resumeCommitted`. |
| 798 | método | DataSyncPeerClient | `static Future<DataSyncClientExchange> connect({ required String pairingCode, required SyncState localState, required DataSyncTransactionParticipant participant, Duration timeout = DataSyncPeerHost.defaultTimeout, Duration interactionTimeout = DataSyncPeerHost.defaultInteractionTimeout, })` | Operación `connect`. |
| 835 | función | - | `Future<void> _recoverRemoteCommit({ required DataSyncPairingCode pairing, required SyncCoordinatorRecovery recovery, required Duration timeout, required Duration interactionTimeout, })` | Función `_recoverRemoteCommit`. |
| 887 | función | - | `Future<void> _recoverRemoteAbort({ required DataSyncPairingCode pairing, required SyncCoordinatorRecovery recovery, required Duration timeout, })` | Función `_recoverRemoteAbort`. |
| 966 | constructor | _Message | `const _Message(this.type, this.payload)` | Construye _Message. |
| 984 | constructor | _EncryptedChannel | `_EncryptedChannel(this._socket, this._key, this._timeout)` | Construye _EncryptedChannel. |
| 986 | método | _EncryptedChannel | `Future<void> writeJson(_MessageType type, Map<String, Object> value)` | Operación `writeJson`. |
| 990 | método | _EncryptedChannel | `Future<void> writeReceipt( _MessageType type, SyncTransactionReceipt receipt, )` | Operación `writeReceipt`. |
| 995 | método | _EncryptedChannel | `Future<void> writeMessage(_MessageType type, List<int> payload)` | Operación `writeMessage`. |
| 1022 | método | _EncryptedChannel | `Future<_Message> readMessage({Duration? timeout})` | Operación `readMessage`. |
| 1055 | método | _EncryptedChannel | `Future<Uint8List> _readExactly(int count, Duration timeout)` | Operación `_readExactly`. |
| 1083 | método | _EncryptedChannel | `void close()` | Operación `close`. |
| 1096 | constructor | _PrepareRequest | `const _PrepareRequest({ required this.transactionId, required this.snapshot, required this.expectedCheckpoint, required this.targetHash, })` | Construye _PrepareRequest. |
| 1108 | constructor | _TransactionReference | `const _TransactionReference(this.transactionId, this.targetHash)` | Construye _TransactionReference. |
| 1111 | función | - | `_PrepareRequest _decodePrepare(Uint8List payload)` | Función `_decodePrepare`. |
| 1141 | función | - | `_TransactionReference _decodeTransactionReference( Uint8List payload, String label, )` | Función `_decodeTransactionReference`. |
| 1162 | función | - | `Map<String, Object> _transactionReference( String transactionId, String targetHash, )` | Función `_transactionReference`. |
| 1167 | función | - | `SyncTransactionReceipt _decodeReceipt(Uint8List payload)` | Función `_decodeReceipt`. |
| 1175 | función | - | `SyncTransactionReceipt _decodeReceiptFor( _Message message, SyncTransactionOutcome expected, )` | Función `_decodeReceiptFor`. |
| 1191 | función | - | `void _verifyReceipt( SyncTransactionReceipt receipt, String transactionId, String targetHash, )` | Función `_verifyReceipt`. |
| 1202 | función | - | `Object? _decodeObject(Uint8List payload, String label)` | Función `_decodeObject`. |
| 1210 | función | - | `Map<String, dynamic> _decodeMap(Uint8List payload, String label)` | Función `_decodeMap`. |
| 1218 | función | - | `Future<_EncryptedChannel> _connectChannel( DataSyncPairingCode pairing, Duration timeout, )` | Función `_connectChannel`. |
| 1230 | función | - | `String _newTransactionId()` | Función `_newTransactionId`. |
| 1233 | función | - | `bool _isHash(String value)` | Función `_isHash`. |
| 1236 | función | - | `Future<InternetAddress> _lanIPv4()` | Función `_lanIPv4`. |
| 1249 | función | - | `Uint8List _randomBytes(int length)` | Función `_randomBytes`. |
| 1254 | función | - | `Uint8List _uint32(int value)` | Función `_uint32`. |
| 1257 | función | - | `int _readUint32(List<int> bytes, int offset)` | Función `_readUint32`. |
| 1263 | función | - | `bool _equal(List<int> left, List<int> right)` | Función `_equal`. |
## `lib/helpers/definitions.dart`

| Línea | Tipo | Owner | Firma | Descripción |
|---:|---|---|---|---|
| 245 | constructor | ChameleonCommand | `const ChameleonCommand(this.value)` | Construye ChameleonCommand. |
| 276 | constructor | TagType | `const TagType(this.value)` | Construye TagType. |
| 285 | constructor | TagFrequency | `const TagFrequency(this.value)` | Construye TagFrequency. |
| 295 | constructor | AnimationSetting | `const AnimationSetting(this.value)` | Construye AnimationSetting. |
| 305 | constructor | MifareWriteMode | `const MifareWriteMode(this.value)` | Construye MifareWriteMode. |
| 314 | constructor | Mf1PrngType | `const Mf1PrngType(this.value)` | Construye Mf1PrngType. |
| 322 | constructor | ButtonType | `const ButtonType(this.value)` | Construye ButtonType. |
| 335 | constructor | ButtonConfig | `const ButtonConfig(this.value)` | Construye ButtonConfig. |
| 345 | constructor | CardData | `CardData( {required this.uid, required this.sak, required this.atqa, required this.ats})` | Construye CardData. |
| 356 | constructor | IsoDepReaderSessionInfo | `const IsoDepReaderSessionInfo({ required this.sessionId, required this.card, })` | Construye IsoDepReaderSessionInfo. |
| 367 | constructor | ChameleonMessage | `ChameleonMessage( {required this.command, required this.status, required this.data})` | Construye ChameleonMessage. |
| 378 | constructor | BleScanResult | `BleScanResult( {required this.addr, required this.addrType, required this.rssi, required this.adv})` | Construye BleScanResult. |
| 392 | constructor | BleCharacteristic | `BleCharacteristic( {required this.handle, required this.props, required this.uuidType, required this.uuid})` | Construye BleCharacteristic. |
| 419 | constructor | BleCentralState | `BleCentralState( {required this.connState, required this.discState, required this.charCount, required this.fuzzState, required this.fuzzSent, required this.targetAlive, required this.lastReason, this.probeState = 0, this.probeResult = 0, this.probeIndex = 0, this.probeTotal = 0, this.floodState = 0, this.floodSent = 0, this.readState = 0, this.writeState = 0, this.notificationCount = 0, this.hasOperationState = false})` | Construye BleCentralState. |
| 445 | constructor | IsoDepDebugCounters | `const IsoDepDebugCounters({ required this.receivedIBlocks, required this.transmittedIBlocks, required this.lastReceivedPcb, required this.lastStaticResponseMatch, })` | Construye IsoDepDebugCounters. |
| 460 | constructor | BleFuzzLogEntry | `BleFuzzLogEntry( {required this.index, required this.length, required this.status, required this.data})` | Construye BleFuzzLogEntry. |
| 482 | constructor | NTDistance | `NTDistance({required this.uid, required this.distance})` | Construye NTDistance. |
| 490 | constructor | NestedNonce | `NestedNonce({required this.nt, required this.ntEnc, required this.parity})` | Construye NestedNonce. |
| 497 | constructor | SlotNames | `SlotNames({this.hf = '', this.lf = ''})` | Construye SlotNames. |
| 503 | método | NestedNonces | `List<int> getNoncesInfo()` | Operación `getNoncesInfo`. |
| 525 | método | NestedNonces | `Uint8List getHardNested(int uid)` | Operación `getHardNested`. |
| 547 | constructor | NestedNonces | `NestedNonces({required this.nonces})` | Construye NestedNonces. |
| 558 | constructor | Darkside | `Darkside( {required this.uid, required this.nt1, required this.par, required this.ks1, required this.nr, required this.ar})` | Construye Darkside. |
| 576 | constructor | DetectionResult | `DetectionResult( {required this.block, required this.type, required this.isNested, required this.uid, required this.nt, required this.nr, required this.ar})` | Construye DetectionResult. |
| 590 | constructor | FirmwareVersion | `FirmwareVersion({required this.legacyProtocol, required this.version})` | Construye FirmwareVersion. |
| 597 | método | SlotTypes | `bool match({TagType type = TagType.unknown})` | Operación `match`. |
| 601 | método | SlotTypes | `bool notMatch({TagType type = TagType.unknown})` | Operación `notMatch`. |
| 605 | constructor | SlotTypes | `SlotTypes({this.hf = TagType.unknown, this.lf = TagType.unknown})` | Construye SlotTypes. |
| 612 | método | EnabledSlotInfo | `bool any()` | Operación `any`. |
| 616 | constructor | EnabledSlotInfo | `EnabledSlotInfo({this.hf = false, this.lf = false})` | Construye EnabledSlotInfo. |
| 623 | constructor | BatteryCharge | `BatteryCharge({required this.voltage, required this.percent})` | Construye BatteryCharge. |
| 633 | constructor | EmulatorSettings | `EmulatorSettings( {required this.isDetectionEnabled, required this.isGen1a, required this.isGen2, required this.isAntiColl, required this.writeMode})` | Construye EmulatorSettings. |
| 651 | constructor | DeviceSettings | `DeviceSettings( {this.animation = AnimationSetting.none, this.aPress = ButtonConfig.disable, this.bPress = ButtonConfig.disable, this.aLongPress = ButtonConfig.disable, this.bLongPress = ButtonConfig.disable, this.pairingEnabled = false, this.key = "", this.wakeTimeSeconds})` | Construye DeviceSettings. |
| 667 | constructor | MifareClassicValueBlockOperator | `const MifareClassicValueBlockOperator(this.value)` | Construye MifareClassicValueBlockOperator. |
| 675 | método | LFCard | `@override String toString()` | Operación `toString`. |
| 680 | método | LFCard | `String toViewableString()` | Operación `toViewableString`. |
| 684 | constructor | LFCard | `LFCard({required this.type, required this.uid})` | Construye LFCard. |
| 688 | factory | EM410XCard | `factory EM410XCard.fromBytes(Uint8List bytes)` | Construye EM410XCard. |
| 719 | factory | EM410XCard | `factory EM410XCard.fromUID(String uid, {TagType type = TagType.em410X})` | Construye EM410XCard. |
| 723 | constructor | EM410XCard | `EM410XCard({required super.type, required super.uid})` | Construye EM410XCard. |
| 732 | factory | HIDCard | `factory HIDCard.fromBytes(Uint8List bytes)` | Construye HIDCard. |
| 741 | factory | HIDCard | `factory HIDCard.fromUID(String uid)` | Construye HIDCard. |
| 745 | método | HIDCard | `@override String toString()` | Operación `toString`. |
| 756 | método | HIDCard | `@override String toViewableString()` | Operación `toViewableString`. |
| 783 | constructor | HIDCard | `HIDCard( {super.type = TagType.hidProx, required this.hidType, required this.facilityCode, required super.uid, required this.issueLevel, required this.oem})` | Construye HIDCard. |
| 793 | factory | VikingCard | `factory VikingCard.fromBytes(Uint8List bytes)` | Construye VikingCard. |
| 797 | factory | VikingCard | `factory VikingCard.fromUID(String uid)` | Construye VikingCard. |
| 801 | constructor | VikingCard | `VikingCard({ super.type = TagType.viking, required super.uid, })` | Construye VikingCard. |
| 808 | factory | PacCard | `factory PacCard.fromBytes(Uint8List bytes)` | Construye PacCard. |
| 812 | factory | PacCard | `factory PacCard.fromUID(String uid)` | Construye PacCard. |
| 816 | constructor | PacCard | `PacCard({ super.type = TagType.pac, required super.uid, })` | Construye PacCard. |
| 823 | factory | IoProxCard | `factory IoProxCard.fromBytes(Uint8List bytes)` | Construye IoProxCard. |
| 827 | factory | IoProxCard | `factory IoProxCard.fromUID(String uid)` | Construye IoProxCard. |
| 831 | constructor | IoProxCard | `IoProxCard({ super.type = TagType.ioProx, required super.uid, })` | Construye IoProxCard. |
| 838 | factory | IdteckCard | `factory IdteckCard.fromBytes(Uint8List bytes)` | Construye IdteckCard. |
| 842 | factory | IdteckCard | `factory IdteckCard.fromUID(String uid)` | Construye IdteckCard. |
| 846 | constructor | IdteckCard | `IdteckCard({ super.type = TagType.idteck, required super.uid, })` | Construye IdteckCard. |
## `lib/helpers/emulation_change.dart`

| Línea | Tipo | Owner | Firma | Descripción |
|---:|---|---|---|---|
| 13 | constructor | EmulationBlockChange | `EmulationBlockChange({ required this.block, required Uint8List before, required Uint8List after, }) : before = Uint8List.fromList(before), after = Uint8List.fromList(after)` | Construye EmulationBlockChange. |
| 20 | factory | EmulationBlockChange | `factory EmulationBlockChange.fromMap(Map<String, dynamic> data)` | Construye EmulationBlockChange. |
| 28 | método | EmulationBlockChange | `Map<String, dynamic> toMap()` | Operación `toMap`. |
| 42 | constructor | EmulationChangeEntry | `EmulationChangeEntry({ required this.timestamp, required this.slot, required this.tagType, required this.uid, required List<EmulationBlockChange> changes, }) : changes = List.unmodifiable(changes)` | Construye EmulationChangeEntry. |
| 50 | factory | EmulationChangeEntry | `factory EmulationChangeEntry.fromJson(String encoded)` | Construye EmulationChangeEntry. |
| 68 | método | EmulationChangeEntry | `String toJson()` | Serializa EmulationChangeEntry. |
| 78 | función | - | `List<EmulationBlockChange> diffEmulationBlocks( Uint8List before, Uint8List after, )` | Función `diffEmulationBlocks`. |
## `lib/helpers/emv.dart`

| Línea | Tipo | Owner | Firma | Descripción |
|---:|---|---|---|---|
| 11 | constructor | EmvTlv | `EmvTlv(this.tag, this.value, this.constructed, this.depth)` | Construye EmvTlv. |
| 98 | función | - | `String emvTagName(String tag)` | Función `emvTagName`. |
| 101 | función | - | `List<EmvTlv> parseEmvTlv(Uint8List data, {int depth = 0})` | Función `parseEmvTlv`. |
| 150 | constructor | EmvScan | `EmvScan(this.uid, this.atqa, this.sak, this.ats, this.apdus)` | Construye EmvScan. |
| 164 | constructor | EmvApduTrace | `EmvApduTrace({ required this.index, required this.command, required this.response, required this.name, required this.commandDetails, required this.statusWord, required this.statusText, required this.responseBody, required this.responseTlvs, })` | Construye EmvApduTrace. |
| 178 | constructor | EmvOdaAssessment | `const EmvOdaAssessment({ required this.advertisedMethods, required this.presentTags, required this.missingTags, required this.caPublicKeyIndex, required this.cryptographicallyVerified, required this.status, })` | Construye EmvOdaAssessment. |
| 194 | método | EmvOdaAssessment | `Map<String, Object?> toJson()` | Serializa EmvOdaAssessment. |
| 204 | función | - | `EmvOdaAssessment emvAssessOda(Map<String, Uint8List> leaf)` | Función `emvAssessOda`. |
| 238 | función | - | `String _hex(Uint8List b)` | Función `_hex`. |
| 240 | función | - | `String _asciiPrintable(Uint8List b)` | Función `_asciiPrintable`. |
| 245 | función | - | `String emvStatusText(int? sw)` | Función `emvStatusText`. |
| 283 | función | - | `String emvDescribeCommand(Uint8List cmd)` | Función `emvDescribeCommand`. |
| 302 | función | - | `List<String> emvCommandDetails(Uint8List cmd)` | Función `emvCommandDetails`. |
| 340 | función | - | `Uint8List _apduData(Uint8List cmd)` | Función `_apduData`. |
| 347 | función | - | `Uint8List? _unwrap83(Uint8List data)` | Función `_unwrap83`. |
| 354 | función | - | `List<EmvApduTrace> emvBuildTrace(List<(Uint8List, Uint8List)> apdus)` | Función `emvBuildTrace`. |
| 381 | función | - | `EmvScan parseEmvScanBuffer(Uint8List d)` | Función `parseEmvScanBuffer`. |
| 424 | función | - | `String emvProtocolSummary( Uint8List uid, Uint8List atqa, int sak, Uint8List ats)` | Función `emvProtocolSummary`. |
| 451 | función | - | `Map<String, Uint8List> emvLeafMap(List<EmvTlv> tlvs)` | Función `emvLeafMap`. |
| 464 | función | - | `Map<String, Uint8List> emvLeafMapFromTrace(List<EmvApduTrace> traces)` | Función `emvLeafMapFromTrace`. |
| 482 | función | - | `void _addGpoFormat1Leaves(Map<String, Uint8List> leaf, Uint8List value)` | Función `_addGpoFormat1Leaves`. |
| 492 | función | - | `void _addGenerateAcFormat1Leaves(Map<String, Uint8List> leaf, Uint8List value)` | Función `_addGenerateAcFormat1Leaves`. |
| 503 | función | - | `int _bytesToInt(Uint8List b)` | Función `_bytesToInt`. |
| 511 | función | - | `String _ascii(Uint8List b)` | Función `_ascii`. |
| 514 | función | - | `String _bcd(Uint8List b)` | Función `_bcd`. |
| 568 | función | - | `String _fmtExpiry(String yymmdd)` | Función `_fmtExpiry`. |
| 576 | función | - | `String _fmtPan(String pan)` | Función `_fmtPan`. |
| 586 | función | - | `String? emvScheme(String? aid, String? pan)` | Función `emvScheme`. |
| 618 | función | - | `Map<String, String> emvExtractFields(Map<String, Uint8List> leaf)` | Función `emvExtractFields`. |
| 729 | constructor | EmvAip | `EmvAip(this.features, this.rrp, this.dda, this.cda, this.raw)` | Construye EmvAip. |
| 739 | función | - | `EmvRrpAssessment emvAssessRrp(EmvAip aip, String? aid)` | Función `emvAssessRrp`. |
| 749 | función | - | `EmvAip? emvDecodeAip(Map<String, Uint8List> leaf)` | Función `emvDecodeAip`. |
| 769 | función | - | `Map<String, String> emvExtractCryptogram(Map<String, Uint8List> leaf)` | Función `emvExtractCryptogram`. |
## `lib/helpers/emv_trace.dart`

| Línea | Tipo | Owner | Firma | Descripción |
|---:|---|---|---|---|
| 25 | constructor | EmvTraceState | `const EmvTraceState(this.value, this.label)` | Construye EmvTraceState. |
| 30 | método | EmvTraceState | `static EmvTraceState fromValue(int value)` | Operación `fromValue`. |
| 44 | constructor | EmvTraceRecordType | `const EmvTraceRecordType(this.value, this.label)` | Construye EmvTraceRecordType. |
| 49 | método | EmvTraceRecordType | `static EmvTraceRecordType fromValue(int value)` | Operación `fromValue`. |
| 83 | constructor | EmvTerminalProfile | `const EmvTerminalProfile(this.value, this.label, this.ttqHex)` | Construye EmvTerminalProfile. |
| 96 | constructor | EmvPollingProfile | `const EmvPollingProfile(this.value, this.label)` | Construye EmvPollingProfile. |
| 103 | constructor | EmvTraceRequest | `const EmvTraceRequest({ this.maximumProcessing = false, this.includeRf = true, this.includeTiming = true, this.scanRecordGrid = false, this.readTransactionLogs = false, this.usePdolFallback = true, this.expressTransit = false, this.terminalProfile = EmvTerminalProfile.automatic, this.customTtq = const [0, 0, 0, 0], this.pollingProfile = EmvPollingProfile.automatic, this.directAidFallback = false, this.adaptiveProfiles = false, this.reacquireBetweenProfiles = false, this.pollRetries = 0, this.pollDelayMs = 0, this.pollTimeoutMs = 0, this.maxAids = 8, this.maxRecords = 32, this.maxApdus = 128, this.budgetMs = 12000, required this.amount, required this.country, required this.currency, required this.date, this.transactionType = 0, this.cryptogramType = 0xff, })` | Construye EmvTraceRequest. |
| 132 | factory | EmvTraceRequest | `factory EmvTraceRequest.readOnly({ bool maximumProcessing = false, bool includeRf = true, bool scanRecordGrid = false, bool readTransactionLogs = false, bool expressTransit = false, EmvTerminalProfile terminalProfile = EmvTerminalProfile.automatic, EmvPollingProfile pollingProfile = EmvPollingProfile.automatic, bool directAidFallback = false, int maxAids = 8, int maxRecords = 32, int maxApdus = 128, int budgetMs = 12000, Uint8List? country, Uint8List? currency, Uint8List? date, })` | Construye EmvTraceRequest. |
| 196 | getter | EmvTraceRequest | `int get behavior` | Obtiene `behavior`. |
| 201 | getter | EmvTraceRequest | `bool get hasBehavior` | Obtiene `hasBehavior`. |
| 208 | getter | EmvTraceRequest | `bool get hasTerminalProfile` | Obtiene `hasTerminalProfile`. |
| 213 | getter | EmvTraceRequest | `int get flags` | Obtiene `flags`. |
| 223 | método | EmvTraceRequest | `Uint8List encode()` | Operación `encode`. |
| 296 | función | - | `Uint8List emvTraceDate(DateTime value)` | Función `emvTraceDate`. |
| 303 | constructor | EmvTraceStartResponse | `const EmvTraceStartResponse({ required this.state, required this.scanId, required this.flags, required this.rawBytes, })` | Construye EmvTraceStartResponse. |
| 315 | factory | EmvTraceStartResponse | `factory EmvTraceStartResponse.parse(Uint8List bytes)` | Construye EmvTraceStartResponse. |
| 337 | constructor | EmvTraceMeta | `const EmvTraceMeta({ required this.state, required this.resultStatus, required this.flags, required this.scanId, required this.storedRecords, required this.observedRecords, required this.storedBytes, required this.requiredBytes, required this.firstDropped, required this.crc32, required this.applicationCount, required this.elapsedMs, required this.uid, required this.atqa, required this.sak, required this.ats, required this.rawBytes, })` | Construye EmvTraceMeta. |
| 375 | getter | EmvTraceMeta | `bool get isComplete` | Obtiene `isComplete`. |
| 377 | getter | EmvTraceMeta | `bool get isTruncated` | Obtiene `isTruncated`. |
| 385 | getter | EmvTraceMeta | `bool get maximumProcessing` | Obtiene `maximumProcessing`. |
| 386 | getter | EmvTraceMeta | `bool get expressTransit` | Obtiene `expressTransit`. |
| 388 | factory | EmvTraceMeta | `factory EmvTraceMeta.parse(Uint8List bytes)` | Construye EmvTraceMeta. |
| 450 | método | EmvTraceMeta | `Map<String, Object?> toJson()` | Serializa EmvTraceMeta. |
| 474 | constructor | EmvTraceRecordPayload | `const EmvTraceRecordPayload()` | Construye EmvTraceRecordPayload. |
| 476 | método | EmvTraceRecordPayload | `Map<String, Object?> toJson()` | Serializa EmvTraceRecordPayload. |
| 480 | constructor | EmvTraceRfPayload | `const EmvTraceRfPayload({ required this.direction, required this.bitLength, required this.data, })` | Construye EmvTraceRfPayload. |
| 490 | getter | EmvTraceRfPayload | `bool get readerToCard` | Obtiene `readerToCard`. |
| 492 | método | EmvTraceRfPayload | `@override Map<String, Object?> toJson()` | Serializa EmvTraceRfPayload. |
| 502 | constructor | EmvTraceApduPayload | `const EmvTraceApduPayload({ required this.statusWord, required this.command, required this.response, })` | Construye EmvTraceApduPayload. |
| 512 | método | EmvTraceApduPayload | `@override Map<String, Object?> toJson()` | Serializa EmvTraceApduPayload. |
| 521 | constructor | EmvTraceApplicationPayload | `const EmvTraceApplicationPayload({ required this.aid, required this.priority, })` | Construye EmvTraceApplicationPayload. |
| 529 | método | EmvTraceApplicationPayload | `@override Map<String, Object?> toJson()` | Serializa EmvTraceApplicationPayload. |
| 537 | constructor | EmvTraceSummaryPayload | `const EmvTraceSummaryPayload({ required this.storedRecordsBeforeSummary, required this.observedRecordsBeforeSummary, required this.flags, })` | Construye EmvTraceSummaryPayload. |
| 547 | método | EmvTraceSummaryPayload | `@override Map<String, Object?> toJson()` | Serializa EmvTraceSummaryPayload. |
| 556 | constructor | EmvTraceRecord | `const EmvTraceRecord({ required this.type, required this.sequence, required this.stage, required this.applicationIndex, required this.attempt, required this.flags, required this.status, required this.timestampMs, required this.payloadBytes, required this.payload, required this.rawBytes, })` | Construye EmvTraceRecord. |
| 582 | getter | EmvTraceRecord | `String get stageName` | Obtiene `stageName`. |
| 584 | método | EmvTraceRecord | `static EmvTraceRecord parse(Uint8List bytes)` | Operación `parse`. |
| 618 | método | EmvTraceRecord | `static EmvTraceRecordPayload _parsePayload( EmvTraceRecordType type, Uint8List bytes)` | Operación `_parsePayload`. |
| 683 | método | EmvTraceRecord | `Map<String, Object?> toJson()` | Serializa EmvTraceRecord. |
| 702 | constructor | EmvTracePage | `const EmvTracePage({ required this.flags, required this.scanId, required this.startRecord, required this.nextRecord, required this.recordBytes, required this.records, required this.rawBytes, })` | Construye EmvTracePage. |
| 720 | getter | EmvTracePage | `bool get hasMore` | Obtiene `hasMore`. |
| 721 | getter | EmvTracePage | `bool get isEnd` | Obtiene `isEnd`. |
| 722 | getter | EmvTracePage | `bool get logTruncated` | Obtiene `logTruncated`. |
| 724 | factory | EmvTracePage | `factory EmvTracePage.parse(Uint8List bytes)` | Construye EmvTracePage. |
| 779 | constructor | EmvTraceCapture | `const EmvTraceCapture._({ required this.meta, required this.pages, required this.records, required this.recordBytes, required this.start, })` | Construye EmvTraceCapture. |
| 793 | getter | EmvTraceCapture | `Iterable<EmvTraceRecord> get apduRecords` | Obtiene `apduRecords`. |
| 795 | getter | EmvTraceCapture | `Iterable<EmvTraceRecord> get rfRecords` | Obtiene `rfRecords`. |
| 797 | getter | EmvTraceCapture | `Iterable<EmvTraceRecord> get applicationRecords` | Obtiene `applicationRecords`. |
| 800 | factory | EmvTraceCapture | `factory EmvTraceCapture.assemble(EmvTraceMeta meta, List<EmvTracePage> pages, {EmvTraceStartResponse? start})` | Construye EmvTraceCapture. |
| 858 | método | EmvTraceCapture | `Map<String, Object?> toJson()` | Serializa EmvTraceCapture. |
| 879 | función | - | `int emvTraceCrc32(List<int> bytes)` | Función `emvTraceCrc32`. |
| 890 | función | - | `Uint8List encodeEmvTraceSessionRequest(int scanId)` | Función `encodeEmvTraceSessionRequest`. |
| 899 | función | - | `Uint8List encodeEmvTraceGetRequest( int scanId, int startRecord, int maxPayload)` | Función `encodeEmvTraceGetRequest`. |
| 916 | función | - | `void _requireVersion(int version)` | Función `_requireVersion`. |
| 922 | función | - | `void _requireKnownFlags(int flags)` | Función `_requireKnownFlags`. |
| 929 | función | - | `void _requireLength(Uint8List bytes, int length, String name)` | Función `_requireLength`. |
| 935 | función | - | `int _bcd(int value)` | Función `_bcd`. |
| 937 | función | - | `String _hex(List<int> bytes)` | Función `_hex`. |
## `lib/helpers/flash.dart`

| Línea | Tipo | Owner | Firma | Descripción |
|---:|---|---|---|---|
| 22 | función | - | `Future<Uint8List> fetchFirmware(ChameleonDevice device)` | Función `fetchFirmware`. |
| 32 | función | - | `Future<(Uint8List, Uint8List)> unpackFirmware(Uint8List content)` | Función `unpackFirmware`. |
| 35 | función | - | `(Uint8List, Uint8List) _unpackFirmware(Uint8List content)` | Función `_unpackFirmware`. |
| 84 | función | - | `void _validateZipDirectory(Uint8List content)` | Función `_validateZipDirectory`. |
| 161 | función | - | `Uint8List _readFirmwareEntry(ArchiveFile file, int maxBytes)` | Función `_readFirmwareEntry`. |
| 185 | constructor | _BoundedOutputMemoryStream | `_BoundedOutputMemoryStream(this.maxBytes) : super( size: maxBytes < OutputMemoryStream.defaultBufferSize ? maxBytes : OutputMemoryStream.defaultBufferSize)` | Construye _BoundedOutputMemoryStream. |
| 191 | método | _BoundedOutputMemoryStream | `void _ensureCapacity(int additional)` | Operación `_ensureCapacity`. |
| 197 | método | _BoundedOutputMemoryStream | `@override void writeByte(int value)` | Operación `writeByte`. |
| 203 | método | _BoundedOutputMemoryStream | `@override void writeBytes(List<int> bytes, {int? length})` | Operación `writeBytes`. |
| 209 | método | _BoundedOutputMemoryStream | `@override void writeStream(InputStream stream)` | Operación `writeStream`. |
| 216 | función | - | `Future<File> createTempFile()` | Función `createTempFile`. |
| 222 | función | - | `void validateFiles(Uint8List dat, Uint8List bin)` | Función `validateFiles`. |
| 253 | función | - | `Future<void> flashFirmware(ChameleonGUIState appState, {ScaffoldMessengerState? scaffoldMessenger, ChameleonDevice? device, bool enterDFU = true})` | Función `flashFirmware`. |
| 271 | función | - | `Future<void> flashFirmwareZip(ChameleonGUIState appState, {ScaffoldMessengerState? scaffoldMessenger, bool enterDFU = true})` | Función `flashFirmwareZip`. |
| 294 | función | - | `Future<void> flashFile( ChameleonCommunicator? connection, ChameleonGUIState appState, Uint8List applicationDat, Uint8List applicationBin, void Function(int progress) callback, {bool enterDFU = true, List<int> firmwareZip = const [], ScaffoldMessengerState? scaffoldMessenger})` | Función `flashFile`. |
## `lib/helpers/font.dart`

| Línea | Tipo | Owner | Firma | Descripción |
|---:|---|---|---|---|
| 24 | constructor | DynamicFont | `DynamicFont.file({required this.fontFamily, required String filepath}) : uri = filepath` | Construye DynamicFont. |
| 27 | método | DynamicFont | `Future<bool> load()` | Operación `load`. |
| 42 | constructor | SystemChineseFont | `const SystemChineseFont._()` | Construye SystemChineseFont. |
| 79 | getter | SystemChineseFont | `static List<String> get fontFamilyFallback` | Chinese font family fallback, for most platforms |
| 103 | getter | SystemChineseFont | `static TextStyle get textStyle` | Text style with updated fontFamilyFallback & fontVariations |
| 108 | método | SystemChineseFont | `static TextTheme textTheme(Brightness brightness)` | Text theme with updated fontFamilyFallback & fontVariations |
| 124 | método | TextStyleUseCustomSystemFont | `TextStyle useCustomSystemFont()` | Add fontFamilyFallback & fontVariation to original font style |
| 141 | método | TextThemeUseCustomSystemFont | `TextTheme useCustomSystemFont(Brightness brightness)` | Add fontFamilyFallback & fontVariation to original text theme |
| 148 | método | ThemeDataUseCustomSystemFont | `ThemeData useCustomSystemFont(Brightness brightness)` | Add fontFamilyFallback & fontVariation to original theme data |
## `lib/helpers/general.dart`

| Línea | Tipo | Owner | Firma | Descripción |
|---:|---|---|---|---|
| 19 | función | - | `Future<void> asyncSleep(int milliseconds)` | Función `asyncSleep`. |
| 23 | función | - | `String bytesToHex(Uint8List bytes)` | Función `bytesToHex`. |
| 27 | función | - | `String bytesToHexSpace(Uint8List bytes)` | Función `bytesToHexSpace`. |
| 34 | función | - | `Uint8List hexToBytes(String hex)` | Función `hexToBytes`. |
| 44 | función | - | `int bytesToU8(Uint8List byteArray)` | Función `bytesToU8`. |
| 48 | función | - | `int bytesToU16(Uint8List byteArray)` | Función `bytesToU16`. |
| 52 | función | - | `int bytesToU32(Uint8List byteArray)` | Función `bytesToU32`. |
| 56 | función | - | `int bytesToU64(Uint8List byteArray)` | Función `bytesToU64`. |
| 60 | función | - | `int parityToInt(int ntParErr)` | Función `parityToInt`. |
| 69 | función | - | `int _swapEndian(int x)` | Función `_swapEndian`. |
| 75 | función | - | `int prngSuccessor(int x, int n)` | Función `prngSuccessor`. |
| 87 | función | - | `int reconstructFullNt(Uint8List responseData, int offset)` | Función `reconstructFullNt`. |
| 93 | función | - | `Uint8List u8ToBytes(int u8)` | Función `u8ToBytes`. |
| 98 | función | - | `Uint8List u16ToBytes(int u16)` | Función `u16ToBytes`. |
| 103 | función | - | `Uint8List u32ToBytes(int u32)` | Función `u32ToBytes`. |
| 108 | función | - | `Uint8List u64ToBytes(int u64)` | Función `u64ToBytes`. |
| 113 | función | - | `bool isValidHexString(String hexString)` | Función `isValidHexString`. |
| 118 | función | - | `int calculateCRC32(List<int> toTransmit, int crc)` | Función `calculateCRC32`. |
| 144 | función | - | `String chameleonTagToString(TagType tag, AppLocalizations localizations)` | Función `chameleonTagToString`. |
| 196 | función | - | `String chameleonCardToString(CardSave card, AppLocalizations localizations)` | Función `chameleonCardToString`. |
| 206 | función | - | `TagType numberToChameleonTag(int type)` | Función `numberToChameleonTag`. |
| 216 | función | - | `List<TagType> getTagTypes()` | Función `getTagTypes`. |
| 220 | función | - | `TagType getTagTypeByValue(int value)` | Función `getTagTypeByValue`. |
| 225 | función | - | `String colorToHex(Color color)` | Función `colorToHex`. |
| 229 | función | - | `Color hexToColor(String hex)` | Función `hexToColor`. |
| 233 | función | - | `String platformToPath()` | Función `platformToPath`. |
| 249 | función | - | `String numToVerCode(int versionCode)` | Función `numToVerCode`. |
| 255 | función | - | `TagFrequency chameleonTagToFrequency(TagType tag)` | Función `chameleonTagToFrequency`. |
| 263 | función | - | `int calculateBcc(Uint8List data)` | Función `calculateBcc`. |
| 271 | función | - | `int getBlockCountForTagType(TagType tagType)` | Función `getBlockCountForTagType`. |
| 302 | función | - | `int getMemorySizeForTagType(TagType tagType)` | Función `getMemorySizeForTagType`. |
| 328 | constructor | SharedPreferencesLogger | `SharedPreferencesLogger(this.provider)` | Construye SharedPreferencesLogger. |
| 330 | método | SharedPreferencesLogger | `@override void output(OutputEvent event)` | Operación `output`. |
| 338 | función | - | `String chameleonDeviceName(ChameleonDevice device)` | Función `chameleonDeviceName`. |
| 343 | método | ChameleonLogFilter | `@override bool shouldLog(LogEvent event)` | Operación `shouldLog`. |
| 349 | función | - | `ButtonConfig getButtonConfigType(int value)` | Función `getButtonConfigType`. |
| 367 | función | - | `AnimationSetting getAnimationModeType(int value)` | Función `getAnimationModeType`. |
| 381 | función | - | `Future<void> saveTag(CardSave tag, BuildContext context, bool bin)` | Función `saveTag`. |
| 426 | función | - | `void updateNavigationRailWidth(BuildContext context)` | Función `updateNavigationRailWidth`. |
| 436 | función | - | `List<TagType> getTagTypesByFrequency(TagFrequency frequency)` | Función `getTagTypesByFrequency`. |
| 471 | función | - | `int evenParity32(int n)` | Función `evenParity32`. |
| 481 | función | - | `TagType getTagTypeByDumpSize(int size)` | Función `getTagTypeByDumpSize`. |
| 516 | función | - | `String getNameForHIDProxType(int type)` | Función `getNameForHIDProxType`. |
| 551 | función | - | `LFCard getLFCardFromUID(TagType type, String uid)` | Función `getLFCardFromUID`. |
| 575 | función | - | `int uidSizeForLfTag(TagType type)` | Función `uidSizeForLfTag`. |
| 595 | función | - | `bool isEM410X(TagType type)` | Función `isEM410X`. |
| 605 | función | - | `Future<(HFCardInfo, MifareClassicInfo, MifareUltralightInfo)> readHFInfo( BuildContext context, dynamic updateMifareClassicRecovery)` | Función `readHFInfo`. |
## `lib/helpers/github.dart`

| Línea | Tipo | Owner | Firma | Descripción |
|---:|---|---|---|---|
| 54 | función | - | `Future<List<Map<String, String>>> fetchGitHubContributors()` | Función `fetchGitHubContributors`. |
| 85 | función | - | `Future<Uint8List> fetchFirmwareFromReleases(ChameleonDevice device)` | Función `fetchFirmwareFromReleases`. |
| 121 | función | - | `Future<Uint8List> fetchFirmwareFromActions(ChameleonDevice device)` | Función `fetchFirmwareFromActions`. |
| 155 | función | - | `Future<String> latestAvailableCommit(ChameleonDevice device)` | Función `latestAvailableCommit`. |
| 205 | función | - | `Future<String> resolveCommit(String commitHash)` | Función `resolveCommit`. |
| 235 | constructor | ChangelogEntry | `ChangelogEntry({ required this.version, this.tagName, required this.publishedAt, required this.url, required this.changes, required this.isPrerelease, this.currentVersionCommit, this.commitHashes, })` | Construye ChangelogEntry. |
| 246 | factory | ChangelogEntry | `factory ChangelogEntry.fromGitHubRelease(Map<String, dynamic> release)` | Construye ChangelogEntry. |
| 261 | método | ChangelogEntry | `static List<String> _parseChangelogFromBody(String body)` | Operación `_parseChangelogFromBody`. |
| 290 | función | - | `Future<List<dynamic>?> _fetchReleases()` | Función `_fetchReleases`. |
| 306 | función | - | `Future<List<ChangelogEntry>> fetchChangelogs([String? buildNumber])` | Función `fetchChangelogs`. |
| 342 | función | - | `Future<ChangelogEntry?> fetchUnreleasedChanges( [List<dynamic>? releases, String? currentVersionCommit])` | Función `fetchUnreleasedChanges`. |
| 422 | función | - | `Future<String?> findCurrentVersionCommit(String buildNumber)` | Función `findCurrentVersionCommit`. |
## `lib/helpers/hf_sniff.dart`

| Línea | Tipo | Owner | Firma | Descripción |
|---:|---|---|---|---|
| 11 | constructor | HfSniffFrame | `const HfSniffFrame({ required this.rawBitLength, required this.bitLength, required this.data, required this.direction, })` | Construye HfSniffFrame. |
| 18 | getter | HfSniffFrame | `bool get isReaderToCard` | Obtiene `isReaderToCard`. |
| 20 | getter | HfSniffFrame | `bool get isCardToReader` | Obtiene `isCardToReader`. |
| 22 | getter | HfSniffFrame | `String get hexString` | Obtiene `hexString`. |
| 29 | constructor | HfSniffAnnotatedFrame | `const HfSniffAnnotatedFrame({ required this.frame, required this.label, })` | Construye HfSniffAnnotatedFrame. |
| 39 | constructor | HfSniffAuthRequest | `const HfSniffAuthRequest({ required this.keyType, required this.block, })` | Construye HfSniffAuthRequest. |
| 59 | constructor | HfSniffSummary | `const HfSniffSummary({ required this.frameCount, required this.readerFrameCount, required this.cardFrameCount, required this.uid, required this.ratsSeen, required this.aids, required this.authRequests, required this.arqcSeen, required this.tcSeen, required this.halted, required this.atcLabel, required this.amountMinorUnits, })` | Construye HfSniffSummary. |
| 83 | constructor | HfSniffNonceExchange | `const HfSniffNonceExchange({ required this.uid, required this.block, required this.keyType, required this.nt, required this.nr, required this.ar, })` | Construye HfSniffNonceExchange. |
| 92 | getter | HfSniffNonceExchange | `String get ntHex` | Obtiene `ntHex`. |
| 94 | getter | HfSniffNonceExchange | `String get nrHex` | Obtiene `nrHex`. |
| 96 | getter | HfSniffNonceExchange | `String get arHex` | Obtiene `arHex`. |
| 105 | constructor | HfSniffNonceGroup | `const HfSniffNonceGroup({ required this.uid, required this.block, required this.keyType, required this.exchanges, })` | Construye HfSniffNonceGroup. |
| 112 | getter | HfSniffNonceGroup | `bool get canRecover` | Obtiene `canRecover`. |
| 114 | getter | HfSniffNonceGroup | `String get id` | Obtiene `id`. |
| 125 | constructor | HfSniffCapture | `const HfSniffCapture({ required this.rawBytes, required this.frames, required this.annotatedFrames, required this.summary, required this.nonces, required this.nonceGroups, })` | Construye HfSniffCapture. |
| 134 | factory | HfSniffCapture | `factory HfSniffCapture.fromRawBytes(Uint8List rawBytes)` | Construye HfSniffCapture. |
| 148 | función | - | `List<HfSniffFrame> parseHf14aSniffFrames(Uint8List buffer)` | Función `parseHf14aSniffFrames`. |
| 183 | función | - | `List<HfSniffAnnotatedFrame> annotateHf14aSniffFrames( List<HfSniffFrame> frames)` | Función `annotateHf14aSniffFrames`. |
| 232 | función | - | `HfSniffSummary summarizeHf14aSniff(List<HfSniffFrame> frames)` | Función `summarizeHf14aSniff`. |
| 352 | función | - | `List<HfSniffNonceExchange> extractHf14aSniffNonces(List<HfSniffFrame> frames)` | Función `extractHf14aSniffNonces`. |
| 405 | función | - | `List<HfSniffNonceGroup> groupHf14aSniffNonces( List<HfSniffNonceExchange> nonces)` | Función `groupHf14aSniffNonces`. |
| 425 | función | - | `String buildMfkey64Command(HfSniffNonceGroup group)` | Función `buildMfkey64Command`. |
| 436 | función | - | `String buildMfkey32Command(HfSniffNonceGroup group)` | Función `buildMfkey32Command`. |
| 446 | función | - | `String buildHfSniffRawHexPreview(Uint8List data, {int maxBytes = 1024})` | Función `buildHfSniffRawHexPreview`. |
| 461 | función | - | `(int, Uint8List) _stripParityBits(Uint8List rawBytes, int rawBitLength)` | Función `_stripParityBits`. |
| 486 | función | - | `String _decodeHf14aFrame(HfSniffFrame frame)` | Función `_decodeHf14aFrame`. |
| 668 | función | - | `String _hex(Uint8List data, {bool spaced = true})` | Función `_hex`. |
| 675 | función | - | `int _bytesToInt(Uint8List bytes)` | Función `_bytesToInt`. |
| 683 | función | - | `String _u32Hex(int value)` | Función `_u32Hex`. |
| 686 | función | - | `String _knownAidName(Uint8List aid)` | Función `_knownAidName`. |
| 703 | función | - | `String? _knownBerTag(int tag)` | Función `_knownBerTag`. |
| 714 | función | - | `String? _sakType(int sak)` | Función `_sakType`. |
| 731 | función | - | `String? _decodeSw(int sw1, int sw2)` | Función `_decodeSw`. |
| 790 | función | - | `int _min(int a, int b)` | Función `_min`. |
## `lib/helpers/keyboard_layout.dart`

| Línea | Tipo | Owner | Firma | Descripción |
|---:|---|---|---|---|
| 16 | función | - | `KeyboardTap _tap(int usage, [int modifier = 0])` | Función `_tap`. |
| 19 | función | - | `List<KeyboardTap> _taps(KeyboardTap tap)` | Función `_taps`. |
| 21 | función | - | `Map<String, List<KeyboardTap>> _layout({ Map<String, int> letterUsages = const {}, required Map<String, KeyboardTap> direct, Map<String, List<KeyboardTap>> sequences = const {}, })` | Función `_layout`. |
| 48 | función | - | `void _addCompositions( Map<String, List<KeyboardTap>> map, KeyboardTap deadKey, Map<String, String> compositions, )` | Función `_addCompositions`. |
| 145 | función | - | `Map<String, List<KeyboardTap>> _buildUk()` | Función `_buildUk`. |
| 159 | función | - | `Map<String, List<KeyboardTap>> _buildSpanish()` | Función `_buildSpanish`. |
| 217 | función | - | `Map<String, List<KeyboardTap>> _buildGerman()` | Función `_buildGerman`. |
| 276 | función | - | `Map<String, List<KeyboardTap>> _buildFrench()` | Función `_buildFrench`. |
| 348 | función | - | `Map<String, List<KeyboardTap>> _buildItalian()` | Función `_buildItalian`. |
| 396 | función | - | `Map<String, List<KeyboardTap>> _buildPortuguese()` | Función `_buildPortuguese`. |
| 518 | función | - | `String normalizeKeyboardText(String text)` | Función `normalizeKeyboardText`. |
| 526 | función | - | `List<KeyboardTap>? keyboardCharacterToTaps( String character, KeyboardLayout layout, )` | Función `keyboardCharacterToTaps`. |
| 532 | función | - | `KeyboardTap? keyboardLogicalKeyTap( String character, KeyboardLayout layout, )` | Función `keyboardLogicalKeyTap`. |
## `lib/helpers/keyboard_script.dart`

| Línea | Tipo | Owner | Firma | Descripción |
|---:|---|---|---|---|
| 17 | constructor | KeyboardScriptError | `const KeyboardScriptError(this.message)` | Construye KeyboardScriptError. |
| 19 | método | KeyboardScriptError | `@override String toString()` | Operación `toString`. |
| 116 | función | - | `(int, int) keyboardKeyToHid( String key, [ KeyboardLayout layout = KeyboardLayout.us, ])` | Función `keyboardKeyToHid`. |
| 144 | función | - | `(int, int) _parseChord(String value, KeyboardLayout layout)` | Función `_parseChord`. |
| 169 | función | - | `(int, int) _parseDuckyChord(List<String> parts, KeyboardLayout layout)` | Función `_parseDuckyChord`. |
| 191 | función | - | `Uint8List compileKeyboardScript( String source, { KeyboardLayout layout = KeyboardLayout.us, })` | Función `compileKeyboardScript`. |
| 319 | función | - | `bool _isWhitespace(int rune)` | Función `_isWhitespace`. |
## `lib/helpers/lf_sniff.dart`

| Línea | Tipo | Owner | Firma | Descripción |
|---:|---|---|---|---|
| 13 | constructor | LfSniffSummary | `const LfSniffSummary({ required this.sampleCount, required this.durationUs, required this.min, required this.max, required this.mean, required this.gapThreshold, required this.gapCount, required this.dynamicRange, })` | Construye LfSniffSummary. |
| 24 | getter | LfSniffSummary | `double get durationMs` | Obtiene `durationMs`. |
| 36 | constructor | LfSniffModulationResult | `const LfSniffModulationResult({ required this.hasSignal, required this.label, required this.dynamicRange, this.nearestClockDivisor, this.mostCommonRunSamples, this.halfPeriodUs, this.fullPeriodUs, })` | Construye LfSniffModulationResult. |
| 53 | constructor | LfManchesterDecodeResult | `const LfManchesterDecodeResult({ required this.clockDivisor, required this.invert, required this.threshold, required this.bits, })` | Construye LfManchesterDecodeResult. |
| 60 | getter | LfManchesterDecodeResult | `bool get hasData` | Obtiene `hasData`. |
| 62 | getter | LfManchesterDecodeResult | `String get bitString` | Obtiene `bitString`. |
| 64 | getter | LfManchesterDecodeResult | `String get hexString` | Obtiene `hexString`. |
| 89 | constructor | LfHexSampleRow | `const LfHexSampleRow({ required this.offset, required this.bytes, required this.levels, })` | Construye LfHexSampleRow. |
| 101 | constructor | LfSniffCapture | `const LfSniffCapture({ required this.samples, required this.summary, required this.modulation, })` | Construye LfSniffCapture. |
| 107 | factory | LfSniffCapture | `factory LfSniffCapture.fromSamples(Uint8List samples)` | Construye LfSniffCapture. |
| 119 | función | - | `LfSniffSummary summarizeLfSniff(Uint8List samples)` | Función `summarizeLfSniff`. |
| 169 | función | - | `LfSniffModulationResult detectLfSniffModulation( Uint8List samples, { LfSniffSummary? summary, })` | Función `detectLfSniffModulation`. |
| 235 | función | - | `LfManchesterDecodeResult decodeLfManchester( Uint8List samples, { int clockDivisor = 64, bool invert = false, })` | Función `decodeLfManchester`. |
| 289 | función | - | `List<LfHexSampleRow> buildLfHexRows( Uint8List samples, { int maxBytes = 512, int bytesPerRow = 16, })` | Función `buildLfHexRows`. |
| 310 | función | - | `List<int> _binarize( Uint8List samples, int threshold, { bool invert = false, })` | Función `_binarize`. |
| 324 | función | - | `List<int> _measureRuns(List<int> bits)` | Función `_measureRuns`. |
| 347 | función | - | `List<(int, int)> _measureBitRuns(List<int> bits)` | Función `_measureBitRuns`. |
| 370 | función | - | `String levelGlyph(int value)` | Función `levelGlyph`. |
| 392 | función | - | `String _levelBar(Uint8List row)` | Función `_levelBar`. |
| 400 | función | - | `int _minInt(int a, int b)` | Función `_minInt`. |
| 402 | función | - | `int _maxInt(int a, int b)` | Función `_maxInt`. |
## `lib/helpers/mifare_classic/autopwn_plus.dart`

| Línea | Tipo | Owner | Firma | Descripción |
|---:|---|---|---|---|
| 25 | constructor | AutopwnPlusTarget | `const AutopwnPlusTarget(this.sector, this.keyType)` | Construye AutopwnPlusTarget. |
| 33 | constructor | AutopwnPlusVerifiedKey | `AutopwnPlusVerifiedKey({ required this.sector, required this.keyType, required Uint8List key, }) : key = Uint8List.fromList(key)` | Construye AutopwnPlusVerifiedKey. |
| 39 | método | AutopwnPlusVerifiedKey | `Map<String, Object> toJson()` | Serializa AutopwnPlusVerifiedKey. |
| 48 | método | AutopwnPlusCardChanged | `@override String toString()` | Operación `toString`. |
| 59 | constructor | AutopwnPlusProgress | `const AutopwnPlusProgress({ required this.phase, required this.operation, required this.value, required this.elapsed, })` | Construye AutopwnPlusProgress. |
| 73 | constructor | AutopwnPlusBlock | `const AutopwnPlusBlock({ required this.sector, required this.block, required this.data, required this.syntheticKeys, })` | Construye AutopwnPlusBlock. |
| 80 | getter | AutopwnPlusBlock | `bool get readable` | Obtiene `readable`. |
| 82 | método | AutopwnPlusBlock | `Map<String, Object?> toJson()` | Serializa AutopwnPlusBlock. |
| 99 | constructor | AutopwnPlusOptions | `const AutopwnPlusOptions({ required this.profile, required this.sectors, required this.dictionaries, this.includeDefaults = true, this.recoverMissing = true, this.partialDump = true, })` | Construye AutopwnPlusOptions. |
| 119 | constructor | AutopwnPlusResult | `const AutopwnPlusResult({ required this.cancelled, required this.selectedKeysRecovered, required this.verifiedKeySlots, required this.selectedKeySlots, required this.verifiedKeys, required this.blocks, required this.timings, required this.error, })` | Construye AutopwnPlusResult. |
| 130 | getter | AutopwnPlusResult | `List<Uint8List> get keys` | Obtiene `keys`. |
| 133 | método | AutopwnPlusResult | `Map<String, Object?> toJson()` | Serializa AutopwnPlusResult. |
| 151 | getter | AutopwnPlusRecoveryPort | `int get sectorCount` | Obtiene `sectorCount`. |
| 152 | getter | AutopwnPlusRecoveryPort | `bool get isCancelled` | Obtiene `isCancelled`. |
| 153 | getter | AutopwnPlusRecoveryPort | `String get error` | Obtiene `error`. |
| 154 | getter | AutopwnPlusRecoveryPort | `List<Uint8List> get validKeys` | Obtiene `validKeys`. |
| 155 | getter | AutopwnPlusRecoveryPort | `List<AutopwnPlusBlock> get dumpedBlocks` | Obtiene `dumpedBlocks`. |
| 157 | método | AutopwnPlusRecoveryPort | `void cancel()` | Operación `cancel`. |
| 158 | método | AutopwnPlusRecoveryPort | `Future<void> prepare(Set<int> sectors)` | Operación `prepare`. |
| 159 | método | AutopwnPlusRecoveryPort | `Future<int> reverifySeededKeys(Set<int> sectors)` | Operación `reverifySeededKeys`. |
| 160 | método | AutopwnPlusRecoveryPort | `List<AutopwnPlusTarget> unresolvedTargets(Set<int> sectors)` | Operación `unresolvedTargets`. |
| 161 | método | AutopwnPlusRecoveryPort | `Future<bool> checkTarget( AutopwnPlusTarget target, List<Uint8List> candidates)` | Operación `checkTarget`. |
| 163 | método | AutopwnPlusRecoveryPort | `Future<void> recoverMissing()` | Operación `recoverMissing`. |
| 164 | método | AutopwnPlusRecoveryPort | `bool selectedComplete(Set<int> sectors)` | Operación `selectedComplete`. |
| 165 | método | AutopwnPlusRecoveryPort | `int verifiedSlots(Set<int> sectors)` | Operación `verifiedSlots`. |
| 166 | método | AutopwnPlusRecoveryPort | `List<AutopwnPlusVerifiedKey> verifiedKeys(Set<int> sectors)` | Operación `verifiedKeys`. |
| 167 | método | AutopwnPlusRecoveryPort | `Future<List<AutopwnPlusBlock>> dumpSelected( Set<int> sectors, void Function(int completed, int total) onProgress, { Future<bool> Function()? cardGuard, })` | Operación `dumpSelected`. |
| 174 | función | - | `List<Uint8List> buildAutopwnPlusCandidates({ required AutopwnPlusProfile profile, required List<Dictionary> dictionaries, required Iterable<Uint8List> verifiedKeys, bool includeDefaults = true, })` | Función `buildAutopwnPlusCandidates`. |
| 203 | función | - | `List<List<Uint8List>> buildAutopwnPlusWaves( AutopwnPlusProfile profile, List<Uint8List> candidates)` | Función `buildAutopwnPlusWaves`. |
| 221 | función | - | `Duration? estimateAutopwnPlusEta(Duration elapsed, double? progress)` | Función `estimateAutopwnPlusEta`. |
| 232 | constructor | AutopwnPlusRunner | `const AutopwnPlusRunner()` | Construye AutopwnPlusRunner. |
| 234 | método | AutopwnPlusRunner | `Future<AutopwnPlusResult> run({ required AutopwnPlusRecoveryPort recovery, required AutopwnPlusOptions options, void Function(AutopwnPlusProgress progress)? onProgress, Future<bool> Function()? cardGuard, })` | Operación `run`. |
| 363 | constructor | MifareClassicAutopwnPlusPort | `MifareClassicAutopwnPlusPort(this.recovery)` | Construye MifareClassicAutopwnPlusPort. |
| 365 | getter | MifareClassicAutopwnPlusPort | `@override int get sectorCount` | Obtiene `sectorCount`. |
| 369 | getter | MifareClassicAutopwnPlusPort | `@override bool get isCancelled` | Obtiene `isCancelled`. |
| 372 | getter | MifareClassicAutopwnPlusPort | `@override String get error` | Obtiene `error`. |
| 375 | getter | MifareClassicAutopwnPlusPort | `@override List<Uint8List> get validKeys` | Obtiene `validKeys`. |
| 378 | getter | MifareClassicAutopwnPlusPort | `@override List<AutopwnPlusBlock> get dumpedBlocks` | Obtiene `dumpedBlocks`. |
| 381 | método | MifareClassicAutopwnPlusPort | `@override void cancel()` | Operación `cancel`. |
| 384 | método | MifareClassicAutopwnPlusPort | `@override Future<void> prepare(Set<int> sectors)` | Operación `prepare`. |
| 414 | método | MifareClassicAutopwnPlusPort | `@override Future<int> reverifySeededKeys(Set<int> sectors)` | Operación `reverifySeededKeys`. |
| 457 | método | MifareClassicAutopwnPlusPort | `@override List<AutopwnPlusTarget> unresolvedTargets(Set<int> sectors)` | Operación `unresolvedTargets`. |
| 468 | método | MifareClassicAutopwnPlusPort | `@override Future<bool> checkTarget( AutopwnPlusTarget target, List<Uint8List> candidates)` | Operación `checkTarget`. |
| 478 | método | MifareClassicAutopwnPlusPort | `@override Future<void> recoverMissing()` | Operación `recoverMissing`. |
| 499 | método | MifareClassicAutopwnPlusPort | `@override bool selectedComplete(Set<int> sectors)` | Operación `selectedComplete`. |
| 502 | método | MifareClassicAutopwnPlusPort | `@override int verifiedSlots(Set<int> sectors)` | Operación `verifiedSlots`. |
| 516 | método | MifareClassicAutopwnPlusPort | `@override List<AutopwnPlusVerifiedKey> verifiedKeys(Set<int> sectors)` | Operación `verifiedKeys`. |
| 530 | método | MifareClassicAutopwnPlusPort | `void _recalculateComplete()` | Operación `_recalculateComplete`. |
| 543 | método | MifareClassicAutopwnPlusPort | `@override Future<List<AutopwnPlusBlock>> dumpSelected( Set<int> sectors, void Function(int completed, int total) onProgress, { Future<bool> Function()? cardGuard, })` | Operación `dumpSelected`. |
## `lib/helpers/mifare_classic/candidate_priority.dart`

| Línea | Tipo | Owner | Firma | Descripción |
|---:|---|---|---|---|
| 18 | función | - | `List<Uint8List> prioritiseCandidates(List<Uint8List> keys, Set<String> likely, {int minLength = 64})` | Reorder [keys] so the ones whose hex is in [likely] come first (stable), leaving everything else in original order. |
| 34 | función | - | `Set<int> narrowCandidates(Set<int>? current, Set<int> next)` | Intersect [current] with [next]. |
| 44 | función | - | `List<Uint8List> prioritiseByFrequency( List<Uint8List> list, Map<String, int> counts, Set<String> defaults)` | Reorder [list] putting cross-sector duplicates (a hex appearing in [counts] with count >= 2) and [defaults] first, most-frequent first within that priority group. |
## `lib/helpers/mifare_classic/dump_analyzer.dart`

| Línea | Tipo | Owner | Firma | Descripción |
|---:|---|---|---|---|
| 6 | método | MifareClassicDumpAnalyzer | `static String hexToAscii(String hex)` | Operación `hexToAscii`. |
| 30 | método | MifareClassicDumpAnalyzer | `static List<String> hexBlocksToAscii(List<String> hexBlocks)` | Operación `hexBlocksToAscii`. |
| 34 | método | MifareClassicDumpAnalyzer | `static Map<String, dynamic> decodeAccessConditions( String accessConditions, BuildContext context)` | Operación `decodeAccessConditions`. |
| 88 | método | MifareClassicDumpAnalyzer | `static String _decodeDataBlockAccess(int bits, BuildContext context)` | Operación `_decodeDataBlockAccess`. |
| 113 | método | MifareClassicDumpAnalyzer | `static String _decodeSectorTrailerAccess(int bits, BuildContext context)` | Operación `_decodeSectorTrailerAccess`. |
| 138 | método | MifareClassicDumpAnalyzer | `static int? valueBlockToInt(String valueBlock)` | Operación `valueBlockToInt`. |
| 162 | método | MifareClassicDumpAnalyzer | `static bool _isValidValueBlock(Uint8List bytes)` | Operación `_isValidValueBlock`. |
| 180 | método | MifareClassicDumpAnalyzer | `static bool isValidHex(String text)` | Operación `isValidHex`. |
| 184 | método | MifareClassicDumpAnalyzer | `static bool isValidBlock(String text)` | Operación `isValidBlock`. |
## `lib/helpers/mifare_classic/dump_highlighter.dart`

| Línea | Tipo | Owner | Firma | Descripción |
|---:|---|---|---|---|
| 5 | método | MifareClassicDumpHighlighter | `static Color getUidColor(BuildContext context)` | Operación `getUidColor`. |
| 11 | método | MifareClassicDumpHighlighter | `static Color getKeyAColor(BuildContext context)` | Operación `getKeyAColor`. |
| 17 | método | MifareClassicDumpHighlighter | `static Color getKeyBColor(BuildContext context)` | Operación `getKeyBColor`. |
| 23 | método | MifareClassicDumpHighlighter | `static Color getAccessConditionsColor(BuildContext context)` | Operación `getAccessConditionsColor`. |
| 29 | método | MifareClassicDumpHighlighter | `static Color getValueBlockColor(BuildContext context)` | Operación `getValueBlockColor`. |
| 35 | método | MifareClassicDumpHighlighter | `static Color getDefaultColor(BuildContext context)` | Operación `getDefaultColor`. |
| 45 | método | MifareClassicDumpHighlighter | `static List<TextSpan> highlightSector( String sectorData, int sector, BuildContext context)` | Operación `highlightSector`. |
| 81 | método | MifareClassicDumpHighlighter | `static List<TextSpan> highlightSectorTrailer( String trailerData, BuildContext context)` | Operación `highlightSectorTrailer`. |
| 141 | método | MifareClassicDumpHighlighter | `static List<TextSpan> highlightFirstBlock( String blockData, BuildContext context)` | Operación `highlightFirstBlock`. |
| 182 | método | MifareClassicDumpHighlighter | `static List<TextSpan> highlightDataBlock( String blockData, BuildContext context)` | Operación `highlightDataBlock`. |
| 213 | método | MifareClassicDumpHighlighter | `static bool isValueBlock(String blockData)` | Operación `isValueBlock`. |
| 240 | método | MifareClassicDumpHighlighter | `static TextSpan colorText(String text, Color color, {bool bold = false})` | Operación `colorText`. |
| 250 | método | MifareClassicDumpHighlighter | `static Widget createHighlightedText( String text, int sector, BuildContext context)` | Operación `createHighlightedText`. |
| 265 | método | MifareClassicDumpHighlighter | `static String _addSpacesToHex(String hex)` | Operación `_addSpacesToHex`. |
## `lib/helpers/mifare_classic/general.dart`

| Línea | Tipo | Owner | Firma | Descripción |
|---:|---|---|---|---|
| 105 | función | - | `Future<MifareClassicType> mfClassicGetType( ChameleonCommunicator communicator)` | Función `mfClassicGetType`. |
| 131 | función | - | `Future<bool> mfClassicHasBackdoor(ChameleonCommunicator communicator)` | Función `mfClassicHasBackdoor`. |
| 147 | función | - | `String mfClassicGetPrngType(NTLevel ntLevel, AppLocalizations localizations)` | Función `mfClassicGetPrngType`. |
| 159 | función | - | `Future<bool> mfClassicIsStaticEncrypted(ChameleonCommunicator communicator, int block, int keyType, Uint8List knownKey)` | Función `mfClassicIsStaticEncrypted`. |
| 169 | función | - | `List<Uint8List> mfClassicConvertKeys(List<int> keys)` | Función `mfClassicConvertKeys`. |
| 179 | función | - | `String mfClassicGetName( MifareClassicType type, AppLocalizations localizations)` | Función `mfClassicGetName`. |
| 194 | función | - | `int mfClassicGetSectorCount(MifareClassicType type, {bool isEV1 = false})` | Función `mfClassicGetSectorCount`. |
| 208 | función | - | `int mfClassicGetBlockCount(MifareClassicType type, {bool isEV1 = false})` | Función `mfClassicGetBlockCount`. |
| 222 | función | - | `MifareClassicType mfClassicGetCardTypeByBlockCount(int blockCount)` | Función `mfClassicGetCardTypeByBlockCount`. |
| 236 | función | - | `int mfClassicGetSectorTrailerBlockBySector(int sector)` | Función `mfClassicGetSectorTrailerBlockBySector`. |
| 244 | función | - | `int mfClassicGetSectorTrailerBlockInSector(int sector)` | Función `mfClassicGetSectorTrailerBlockInSector`. |
| 248 | función | - | `int mfClassicGetBlockCountBySector(int sector)` | Función `mfClassicGetBlockCountBySector`. |
| 252 | función | - | `int mfClassicGetFirstBlockCountBySector(int sector)` | Función `mfClassicGetFirstBlockCountBySector`. |
| 260 | función | - | `int mfClassicGetSectorByBlock(int block)` | Función `mfClassicGetSectorByBlock`. |
| 268 | función | - | `TagType mfClassicGetChameleonTagType(MifareClassicType type)` | Función `mfClassicGetChameleonTagType`. |
| 282 | función | - | `MifareClassicType chameleonTagTypeGetMfClassicType(TagType type)` | Función `chameleonTagTypeGetMfClassicType`. |
| 296 | función | - | `bool chameleonTagSaveCheckForMifareClassicEV1(CardSave tag)` | Función `chameleonTagSaveCheckForMifareClassicEV1`. |
| 310 | función | - | `List<Uint8List> mfClassicGetExportBlocks( MifareClassicType type, List<Uint8List> data, {bool isEV1 = false})` | Función `mfClassicGetExportBlocks`. |
| 323 | función | - | `Uint8List mfClassicGetExportBytes(MifareClassicType type, List<Uint8List> data, {bool isEV1 = false})` | Función `mfClassicGetExportBytes`. |
| 333 | función | - | `bool isMifareClassic(TagType type)` | Función `isMifareClassic`. |
| 342 | función | - | `List<Uint8List> mfClassicGetKeysFromDump(List<Uint8List> dump)` | Función `mfClassicGetKeysFromDump`. |
| 363 | método | StaticEncryptedKeysFilter | `static void _initLfsr16Table()` | Operación `_initLfsr16Table`. |
| 376 | método | StaticEncryptedKeysFilter | `static int _prevLfsr16(int nonce)` | Operación `_prevLfsr16`. |
| 386 | método | StaticEncryptedKeysFilter | `static int _computeSeednt16Nt32(int nt32, int key)` | Operación `_computeSeednt16Nt32`. |
| 421 | método | StaticEncryptedKeysFilter | `static (List<int>, List<int>) filterKeys( List<int> keys1, List<int> keys2, int nt1, int nt2)` | Operación `filterKeys`. |
| 447 | método | StaticEncryptedKeysFilter | `static List<int> findMatchingKeys( int nt1, int key1, int nt2, List<int> keys2)` | Operación `findMatchingKeys`. |
| 465 | método | StaticEncryptedKeysFilterAsync | `static Future<FilterResult> filterKeys( List<int> keys1, List<int> keys2, int nt1, int nt2, )` | Operación `filterKeys`. |
| 482 | método | StaticEncryptedKeysFilterAsync | `static Future<List<int>> findMatchingKeys( int nt1, int key1, int nt2, List<int> keys2, )` | Operación `findMatchingKeys`. |
| 500 | función | - | `Uint8List mfClassicGenerateFirstBlock(Uint8List uid, int sak, Uint8List atqa)` | Función `mfClassicGenerateFirstBlock`. |
| 517 | función | - | `Future<(TagType, MifareClassicInfo)> performMifareClassicScan( ChameleonCommunicator communicator, MifareClassicInfo mfcInfo, BuildContext context, dynamic updateMifareClassicRecovery, {TagType? override})` | Función `performMifareClassicScan`. |
## `lib/helpers/mifare_classic/reader_key_recovery.dart`

| Línea | Tipo | Owner | Firma | Descripción |
|---:|---|---|---|---|
| 14 | constructor | ReaderKeyTarget | `const ReaderKeyTarget({ required this.uid, required this.sector, required this.keyB, })` | Construye ReaderKeyTarget. |
| 20 | getter | ReaderKeyTarget | `String get keyType` | Obtiene `keyType`. |
| 22 | operador | ReaderKeyTarget | `@override bool operator ==(Object other)` | Operación `==`. |
| 29 | getter | ReaderKeyTarget | `@override int get hashCode` | Obtiene `hashCode`. |
| 38 | constructor | ReaderKeyTargetRecords | `const ReaderKeyTargetRecords({ required this.target, required this.records, required this.blocks, })` | Construye ReaderKeyTargetRecords. |
| 61 | constructor | ReaderKeyRecoveryResult | `ReaderKeyRecoveryResult({ required this.target, required this.key, required this.blocks, required this.transcriptCount, required this.attemptedPairs, this.failure, this.error, })` | Construye ReaderKeyRecoveryResult. |
| 74 | función | - | `List<ReaderKeyTargetRecords> groupReaderKeyRecords( Iterable<DetectionResult> detections, )` | Función `groupReaderKeyRecords`. |
| 112 | función | - | `Future<List<ReaderKeyRecoveryResult>> recoverReaderKeys({ required Iterable<DetectionResult> detections, required ReaderMfkey32Solver solver, int maxPairsPerTarget = 256, int maxCrossTargetPairs = 512, bool Function()? isCancelled, void Function(int completed, int total, ReaderKeyTarget target)? onProgress, })` | Función `recoverReaderKeys`. |
| 283 | función | - | `Uint8List? _mfkey32Bytes(int? raw)` | Función `_mfkey32Bytes`. |
| 291 | función | - | `bool _sameKey(Uint8List left, Uint8List right)` | Función `_sameKey`. |
| 299 | función | - | `ReaderKeyRecoveryResult _recoveredResult( ReaderKeyTargetRecords group, Uint8List key, { required int attemptedPairs, })` | Función `_recoveredResult`. |
| 313 | función | - | `ReaderKeyRecoveryResult _failureResult( ReaderKeyTargetRecords group, ReaderKeyRecoveryFailure failure, { required int attemptedPairs, })` | Función `_failureResult`. |
## `lib/helpers/mifare_classic/recovery.dart`

| Línea | Tipo | Owner | Firma | Descripción |
|---:|---|---|---|---|
| 17 | método | PartitionList | `List<List<E>> partition(int size)` | Operación `partition`. |
| 51 | constructor | MifareClassicRecovery | `MifareClassicRecovery( {required this.appState, required this.update, required this.localizations, this.error = '', this.state = '', this.allKeysExists = false, this.dictionaries = const [], this.dumpProgress = 0, this.selectedDictionary, this.mifareClassicType = MifareClassicType.none, this.isMifareClassicEV1 = false, List<ChameleonKeyCheckmark>? checkMarks, List<Uint8List>? validKeys, List<Uint8List>? cardData}) : checkMarks = checkMarks ?? List.generate(80, (_) => ChameleonKeyCheckmark.none), validKeys = validKeys ?? List.generate(80, (_) => Uint8List(0)), cardData = cardData ?? List.generate(256, (_) => Uint8List(0))` | Construye MifareClassicRecovery. |
| 73 | método | MifareClassicRecovery | `void cancel()` | Operación `cancel`. |
| 77 | getter | MifareClassicRecovery | `bool get isCancelled` | Obtiene `isCancelled`. |
| 79 | método | MifareClassicRecovery | `void _throwIfCancelled()` | Operación `_throwIfCancelled`. |
| 87 | método | MifareClassicRecovery | `List<Uint8List> _prioritiseCandidates(List<Uint8List> keys)` | Operación `_prioritiseCandidates`. |
| 98 | método | MifareClassicRecovery | `Future<bool> checkKeysOnSector( List<Uint8List> keys, int keyType, int sector)` | Operación `checkKeysOnSector`. |
| 151 | método | MifareClassicRecovery | `Future<bool> _tryReadableKeyB(int sector, Uint8List keyA)` | Operación `_tryReadableKeyB`. |
| 183 | método | MifareClassicRecovery | `Future<void> initialize()` | Operación `initialize`. |
| 205 | método | MifareClassicRecovery | `Future<void> recheckKey(Uint8List key, int startingSector)` | Operación `recheckKey`. |
| 243 | método | MifareClassicRecovery | `void initializeEV1()` | Operación `initializeEV1`. |
| 252 | método | MifareClassicRecovery | `Future<void> checkKeys({bool skipDefaultDictionary = false})` | Operación `checkKeys`. |
| 306 | método | MifareClassicRecovery | `Future<bool> recoverDarkside()` | Operación `recoverDarkside`. |
| 362 | método | MifareClassicRecovery | `Future<bool> recoverNestedSingle(Uint8List knownKey, int knownSector, int knownKeyType, int targetSector, int targetKeyType)` | Operación `recoverNestedSingle`. |
| 415 | método | MifareClassicRecovery | `Future<bool> recoverStaticNestedSingle(Uint8List knownKey, int knownSector, int knownKeyType, int targetSector, int targetKeyType)` | Operación `recoverStaticNestedSingle`. |
| 464 | método | MifareClassicRecovery | `Future<bool> recoverHardnestedSingle(Uint8List knownKey, int knownSector, int knownKeyType, int targetSector, int targetKeyType)` | Operación `recoverHardnestedSingle`. |
| 518 | método | MifareClassicRecovery | `Future<bool> recoverBackdoor()` | Operación `recoverBackdoor`. |
| 685 | método | MifareClassicRecovery | `Future<void> recoverKeys()` | Operación `recoverKeys`. |
| 1125 | método | MifareClassicRecovery | `Future<List<Uint8List>> _readSectorBlocks( int sector, int firstBlock, int blocks)` | Operación `_readSectorBlocks`. |
| 1170 | método | MifareClassicRecovery | `Future<void> dumpData()` | Operación `dumpData`. |
| 1212 | método | MifareClassicRecovery | `Future<dynamic> collectHardnestedNonces(int block, int keyType, Uint8List knownKey, int targetBlock, int targetKeyType)` | Operación `collectHardnestedNonces`. |
| 1269 | método | MifareClassicRecovery | `void setKeyAsFound(int sector, int keyType, Uint8List key)` | Operación `setKeyAsFound`. |
| 1275 | método | MifareClassicRecovery | `void setCheckingSector(int sector, int keyType)` | Operación `setCheckingSector`. |
| 1282 | método | MifareClassicRecovery | `void setMissingSector(int sector, int keyType)` | Operación `setMissingSector`. |
| 1289 | método | MifareClassicRecovery | `Uint8List getSectorKey(int sector, int keyType)` | Operación `getSectorKey`. |
| 1293 | método | MifareClassicRecovery | `ChameleonKeyCheckmark getSectorState(int sector, int keyType)` | Operación `getSectorState`. |
## `lib/helpers/mifare_classic/slot_transfer.dart`

| Línea | Tipo | Owner | Firma | Descripción |
|---:|---|---|---|---|
| 10 | función | - | `List<MifareClassicUploadChunk> planMifareClassicUpload( List<Uint8List> blocks, int blockCount)` | Función `planMifareClassicUpload`. |
| 46 | función | - | `List<MifareClassicRead> planMifareClassicReads(int blockCount)` | Función `planMifareClassicReads`. |
## `lib/helpers/mifare_classic/write/base.dart`

| Línea | Tipo | Owner | Firma | Descripción |
|---:|---|---|---|---|
| 27 | getter | BaseMifareClassicWriteHelper | `@override bool get autoDetect` | Obtiene `autoDetect`. |
| 30 | constructor | BaseMifareClassicWriteHelper | `BaseMifareClassicWriteHelper(super.communicator, {required this.recovery, this.type = MifareClassicType.m1k, this.isEV1 = false})` | Construye BaseMifareClassicWriteHelper. |
| 35 | método | BaseMifareClassicWriteHelper | `@override List<AbstractWriteHelper> getAvailableMethods()` | Operación `getAvailableMethods`. |
| 44 | método | BaseMifareClassicWriteHelper | `@override List<AbstractWriteHelper> getAvailableMethodsByPriority()` | Operación `getAvailableMethodsByPriority`. |
| 53 | método | BaseMifareClassicWriteHelper | `@override List<dynamic> getExtraData()` | Operación `getExtraData`. |
| 58 | método | BaseMifareClassicWriteHelper | `@override Future<void> getCardType()` | Operación `getCardType`. |
| 74 | método | BaseMifareClassicWriteHelper | `Future<Uint8List> readBlock(int block)` | Operación `readBlock`. |
| 78 | método | BaseMifareClassicWriteHelper | `Future<bool> writeBlock(int block, Uint8List data)` | Operación `writeBlock`. |
| 82 | método | BaseMifareClassicWriteHelper | `@override Future<bool> isMagic(dynamic data)` | Operación `isMagic`. |
| 87 | método | BaseMifareClassicWriteHelper | `@override bool isReady()` | Operación `isReady`. |
| 92 | método | BaseMifareClassicWriteHelper | `@override Future<bool> writeData( CardSave card, Function(int writeProgress) update)` | Operación `writeData`. |
| 128 | método | BaseMifareClassicWriteHelper | `Uint8List createBlock0FromSave(CardSave card)` | Operación `createBlock0FromSave`. |
| 149 | método | BaseMifareClassicWriteHelper | `@override Future<bool> isCompatible(CardSave card)` | Operación `isCompatible`. |
| 176 | método | BaseMifareClassicWriteHelper | `@override Future<void> reset()` | Operación `reset`. |
| 182 | método | BaseMifareClassicWriteHelper | `@override Widget getWriteWidget(BuildContext context, dynamic setState)` | Operación `getWriteWidget`. |
## `lib/helpers/mifare_classic/write/gen1.dart`

| Línea | Tipo | Owner | Firma | Descripción |
|---:|---|---|---|---|
| 6 | constructor | MifareClassicGen1WriteHelper | `MifareClassicGen1WriteHelper(super.communicator, {required super.recovery})` | Construye MifareClassicGen1WriteHelper. |
| 8 | getter | MifareClassicGen1WriteHelper | `@override String get name` | Obtiene `name`. |
| 11 | getter | MifareClassicGen1WriteHelper | `static String get staticName` | Obtiene `staticName`. |
| 13 | método | MifareClassicGen1WriteHelper | `@override Future<bool> isMagic(dynamic data)` | Operación `isMagic`. |
| 37 | método | MifareClassicGen1WriteHelper | `@override bool isReady()` | Operación `isReady`. |
| 42 | método | MifareClassicGen1WriteHelper | `@override Future<bool> writeBlock(int block, Uint8List data)` | Operación `writeBlock`. |
## `lib/helpers/mifare_classic/write/gen2.dart`

| Línea | Tipo | Owner | Firma | Descripción |
|---:|---|---|---|---|
| 12 | constructor | MifareClassicGen2WriteHelper | `MifareClassicGen2WriteHelper(super.communicator, {required super.recovery})` | Construye MifareClassicGen2WriteHelper. |
| 14 | getter | MifareClassicGen2WriteHelper | `@override String get name` | Obtiene `name`. |
| 17 | getter | MifareClassicGen2WriteHelper | `static String get staticName` | Obtiene `staticName`. |
| 19 | método | MifareClassicGen2WriteHelper | `@override Future<bool> isMagic(dynamic data)` | Operación `isMagic`. |
| 34 | método | MifareClassicGen2WriteHelper | `@override bool isReady()` | Operación `isReady`. |
| 50 | método | MifareClassicGen2WriteHelper | `Future<bool> writeBlockModifier(CardSave card, int block, Uint8List data, {bool tryBothKeys = false, bool useGenericKey = false})` | Operación `writeBlockModifier`. |
| 67 | método | MifareClassicGen2WriteHelper | `@override Future<bool> writeBlock(int block, Uint8List data, {bool tryBothKeys = false, bool useGenericKey = false})` | Operación `writeBlock`. |
| 109 | método | MifareClassicGen2WriteHelper | `@override Future<bool> writeData( CardSave card, Function(int writeProgress) update)` | Operación `writeData`. |
| 184 | método | MifareClassicGen2WriteHelper | `@override List<int> getFailedBlocks()` | Operación `getFailedBlocks`. |
| 189 | método | MifareClassicGen2WriteHelper | `@override bool writeWidgetSupported()` | Operación `writeWidgetSupported`. |
## `lib/helpers/mifare_classic/write/gen3.dart`

| Línea | Tipo | Owner | Firma | Descripción |
|---:|---|---|---|---|
| 11 | constructor | MifareClassicGen3WriteHelper | `MifareClassicGen3WriteHelper(super.communicator, {required super.recovery})` | Construye MifareClassicGen3WriteHelper. |
| 13 | getter | MifareClassicGen3WriteHelper | `@override String get name` | Obtiene `name`. |
| 16 | getter | MifareClassicGen3WriteHelper | `static String get staticName` | Obtiene `staticName`. |
| 18 | método | MifareClassicGen3WriteHelper | `@override Future<bool> isMagic(dynamic data)` | Operación `isMagic`. |
| 35 | método | MifareClassicGen3WriteHelper | `@override bool isReady()` | Operación `isReady`. |
| 51 | método | MifareClassicGen3WriteHelper | `@override Future<bool> writeBlockModifier(CardSave card, int block, Uint8List data, {bool tryBothKeys = false, bool useGenericKey = false})` | Operación `writeBlockModifier`. |
| 73 | método | MifareClassicGen3WriteHelper | `Future<bool> writeGen3Block(CardSave dump, Uint8List data)` | Operación `writeGen3Block`. |
## `lib/helpers/mifare_ultralight/dump_analyzer.dart`

| Línea | Tipo | Owner | Firma | Descripción |
|---:|---|---|---|---|
| 2 | método | MifareUltralightDumpAnalyzer | `static String hexToAscii(String hex)` | Operación `hexToAscii`. |
| 26 | método | MifareUltralightDumpAnalyzer | `static List<String> hexBlocksToAscii(List<String> hexBlocks)` | Operación `hexBlocksToAscii`. |
| 30 | método | MifareUltralightDumpAnalyzer | `static bool isValidHex(String text)` | Operación `isValidHex`. |
| 34 | método | MifareUltralightDumpAnalyzer | `static bool isValidBlock(String text)` | Operación `isValidBlock`. |
## `lib/helpers/mifare_ultralight/dump_highlighter.dart`

| Línea | Tipo | Owner | Firma | Descripción |
|---:|---|---|---|---|
| 6 | método | MifareUltralightDumpHighlighter | `static Color getUidColor(BuildContext context)` | Operación `getUidColor`. |
| 12 | método | MifareUltralightDumpHighlighter | `static Color getBccColor(BuildContext context)` | Operación `getBccColor`. |
| 18 | método | MifareUltralightDumpHighlighter | `static Color getLockColor(BuildContext context)` | Operación `getLockColor`. |
| 24 | método | MifareUltralightDumpHighlighter | `static Color getPasswordColor(BuildContext context)` | Operación `getPasswordColor`. |
| 30 | método | MifareUltralightDumpHighlighter | `static Color getDefaultColor(BuildContext context)` | Operación `getDefaultColor`. |
| 34 | método | MifareUltralightDumpHighlighter | `static List<TextSpan> highlightBlock(String blockData, int blockNumber, BuildContext context, CardSave cardSave)` | Operación `highlightBlock`. |
| 49 | método | MifareUltralightDumpHighlighter | `static List<TextSpan> highlightUidBlock( String blockData, BuildContext context)` | Operación `highlightUidBlock`. |
| 59 | método | MifareUltralightDumpHighlighter | `static List<TextSpan> highlightFirstUidBlock( String blockData, BuildContext context)` | Operación `highlightFirstUidBlock`. |
| 88 | método | MifareUltralightDumpHighlighter | `static List<TextSpan> highlightBccBlock( String blockData, BuildContext context)` | Operación `highlightBccBlock`. |
| 112 | método | MifareUltralightDumpHighlighter | `static List<TextSpan> highlightDataBlock( String blockData, BuildContext context)` | Operación `highlightDataBlock`. |
| 120 | método | MifareUltralightDumpHighlighter | `static List<TextSpan> highlightPasswordBlock( String blockData, BuildContext context)` | Operación `highlightPasswordBlock`. |
| 130 | método | MifareUltralightDumpHighlighter | `static String _addSpacesToHex(String hex)` | Operación `_addSpacesToHex`. |
## `lib/helpers/mifare_ultralight/general.dart`

| Línea | Tipo | Owner | Firma | Descripción |
|---:|---|---|---|---|
| 7 | función | - | `bool isMifareUltralight(TagType type)` | Función `isMifareUltralight`. |
| 21 | función | - | `Future<Uint8List> mfUltralightGetVersion( ChameleonCommunicator communicator)` | Función `mfUltralightGetVersion`. |
| 26 | función | - | `Future<Uint8List> mfUltralightGetSignature( ChameleonCommunicator communicator)` | Función `mfUltralightGetSignature`. |
| 36 | función | - | `TagType mfUltralightGetType(Uint8List version)` | Función `mfUltralightGetType`. |
| 58 | función | - | `int mfUltralightGetPagesCount(TagType type)` | Función `mfUltralightGetPagesCount`. |
| 81 | función | - | `int mfUltralightGetPasswordPage(TagType type)` | Función `mfUltralightGetPasswordPage`. |
| 104 | función | - | `bool mfUltralightHasCounters(TagType type)` | Función `mfUltralightHasCounters`. |
| 116 | función | - | `int mfUltralightGetCounterCount(TagType type)` | Función `mfUltralightGetCounterCount`. |
| 132 | función | - | `Future<TagType> mfUltralightType(ChameleonCommunicator communicator)` | Función `mfUltralightType`. |
| 178 | función | - | `Future<int?> mfUltralightReadCounterFromCard( ChameleonCommunicator communicator, int index)` | Función `mfUltralightReadCounterFromCard`. |
| 199 | función | - | `Future<List<int>> mfUltralightReadAllCountersFromCard( ChameleonCommunicator communicator, TagType type)` | Función `mfUltralightReadAllCountersFromCard`. |
| 213 | función | - | `List<Uint8List> mfUltralightGenerateFirstBlocks(Uint8List uid, TagType type)` | Función `mfUltralightGenerateFirstBlocks`. |
| 235 | función | - | `Future<(TagType, MifareUltralightInfo)> performMifareUltralightScan( ChameleonCommunicator communicator, MifareUltralightInfo mfuInfo, {TagType? override})` | Función `performMifareUltralightScan`. |
## `lib/helpers/mifare_ultralight/write/base.dart`

| Línea | Tipo | Owner | Firma | Descripción |
|---:|---|---|---|---|
| 16 | getter | BaseMifareUltralightWriteHelper | `@override bool get autoDetect` | Obtiene `autoDetect`. |
| 19 | getter | BaseMifareUltralightWriteHelper | `@override String get name` | Obtiene `name`. |
| 22 | getter | BaseMifareUltralightWriteHelper | `static String get staticName` | Obtiene `staticName`. |
| 26 | constructor | BaseMifareUltralightWriteHelper | `BaseMifareUltralightWriteHelper(super.communicator)` | Construye BaseMifareUltralightWriteHelper. |
| 28 | método | BaseMifareUltralightWriteHelper | `@override List<AbstractWriteHelper> getAvailableMethods()` | Operación `getAvailableMethods`. |
| 35 | método | BaseMifareUltralightWriteHelper | `@override List<AbstractWriteHelper> getAvailableMethodsByPriority()` | Operación `getAvailableMethodsByPriority`. |
| 40 | método | BaseMifareUltralightWriteHelper | `@override Widget getWriteWidget(BuildContext context, setState)` | Operación `getWriteWidget`. |
| 84 | método | BaseMifareUltralightWriteHelper | `@override Future<bool> isCompatible(CardSave card)` | Operación `isCompatible`. |
| 89 | método | BaseMifareUltralightWriteHelper | `@override Future<bool> isMagic(data)` | Operación `isMagic`. |
| 94 | método | BaseMifareUltralightWriteHelper | `@override bool isReady()` | Operación `isReady`. |
| 99 | método | BaseMifareUltralightWriteHelper | `@override bool writeWidgetSupported()` | Operación `writeWidgetSupported`. |
| 104 | método | BaseMifareUltralightWriteHelper | `@override Future<void> reset()` | Operación `reset`. |
| 110 | método | BaseMifareUltralightWriteHelper | `@override Future<bool> writeData( CardSave card, Function(int writeProgress) update)` | Operación `writeData`. |
| 178 | método | BaseMifareUltralightWriteHelper | `@override List<int> getFailedBlocks()` | Operación `getFailedBlocks`. |
## `lib/helpers/non_overlapping_poller.dart`

| Línea | Tipo | Owner | Firma | Descripción |
|---:|---|---|---|---|
| 4 | constructor | NonOverlappingPoller | `NonOverlappingPoller({ required this.interval, required this.task, this.onError, })` | Construye NonOverlappingPoller. |
| 20 | getter | NonOverlappingPoller | `bool get isActive` | Obtiene `isActive`. |
| 21 | getter | NonOverlappingPoller | `bool get isRunning` | Obtiene `isRunning`. |
| 23 | método | NonOverlappingPoller | `void start({bool immediate = true})` | Operación `start`. |
| 36 | método | NonOverlappingPoller | `void stop()` | Operación `stop`. |
| 44 | método | NonOverlappingPoller | `void dispose()` | Libera recursos de NonOverlappingPoller. |
| 46 | método | NonOverlappingPoller | `void _schedule(Duration delay, int generation)` | Operación `_schedule`. |
| 54 | método | NonOverlappingPoller | `Future<void> _run(int generation)` | Operación `_run`. |
## `lib/helpers/open_collective.dart`

| Línea | Tipo | Owner | Firma | Descripción |
|---:|---|---|---|---|
| 5 | función | - | `Future<List<String>> fetchOpenCollectiveContributors()` | Función `fetchOpenCollectiveContributors`. |
| 37 | función | - | `Future<double> fetchOpenCollectiveBalance()` | Función `fetchOpenCollectiveBalance`. |
## `lib/helpers/relay_lab.dart`

| Línea | Tipo | Owner | Firma | Descripción |
|---:|---|---|---|---|
| 12 | constructor | RelayLabPolicyResult | `const RelayLabPolicyResult(this.decision, this.reason, this.errorResponse)` | Construye RelayLabPolicyResult. |
| 18 | getter | RelayLabPolicyResult | `bool get allowed` | Obtiene `allowed`. |
| 21 | función | - | `RelayLabPolicyResult evaluateRelayLabApdu(Uint8List apdu)` | Función `evaluateRelayLabApdu`. |
| 48 | función | - | `bool? relayLabNonceBound(Uint8List command, Uint8List response)` | Función `relayLabNonceBound`. |
| 65 | función | - | `RelayLabPolicyResult _allow(String reason)` | Función `_allow`. |
| 71 | función | - | `RelayLabPolicyResult _reject(String reason, String response)` | Función `_reject`. |
| 79 | constructor | RelayLabExchange | `const RelayLabExchange({ required this.commandHex, required this.responseHex, required this.elapsedUs, required this.allowed, required this.reason, required this.withinDeadline, required this.nonceBound, })` | Construye RelayLabExchange. |
| 97 | getter | RelayLabExchange | `bool get passed` | Obtiene `passed`. |
| 103 | método | RelayLabExchange | `Map<String, Object?> toJson()` | Serializa RelayLabExchange. |
| 116 | constructor | RelayLabStats | `const RelayLabStats({ required this.count, required this.medianUs, required this.p95Us, required this.maxUs, required this.deadlineFailures, required this.nonceFailures, })` | Construye RelayLabStats. |
| 132 | método | RelayLabStats | `Map<String, Object?> toJson()` | Serializa RelayLabStats. |
| 142 | función | - | `RelayLabStats relayLabStats(Iterable<RelayLabExchange> exchanges)` | Función `relayLabStats`. |
| 173 | constructor | RelayLabComparison | `const RelayLabComparison({ required this.baseline, required this.relayed, required this.medianOverheadUs, required this.conclusion, })` | Construye RelayLabComparison. |
| 185 | método | RelayLabComparison | `Map<String, Object?> toJson()` | Serializa RelayLabComparison. |
| 193 | función | - | `RelayLabComparison compareRelayLabRuns( Iterable<RelayLabExchange> baseline, Iterable<RelayLabExchange> relayed, )` | Función `compareRelayLabRuns`. |
## `lib/helpers/saved_keyboard_script.dart`

| Línea | Tipo | Owner | Firma | Descripción |
|---:|---|---|---|---|
| 24 | constructor | SavedKeyboardScript | `SavedKeyboardScript._({ required this.id, required this.name, required this.source, required this.layout, required this.output, required this.program, required this.updatedAt, })` | Construye SavedKeyboardScript. |
| 34 | factory | SavedKeyboardScript | `factory SavedKeyboardScript.compile({ String? id, required String name, required String source, required KeyboardLayout layout, required KeyboardOutput output, DateTime? updatedAt, })` | Construye SavedKeyboardScript. |
| 55 | factory | SavedKeyboardScript | `factory SavedKeyboardScript.fromJson(String encoded)` | Construye SavedKeyboardScript. |
| 113 | método | SavedKeyboardScript | `String toJson()` | Serializa SavedKeyboardScript. |
| 125 | método | SavedKeyboardScript | `static void _validateText(String name, String source)` | Operación `_validateText`. |
| 136 | función | - | `bool _programsEqual(Uint8List first, Uint8List second)` | Función `_programsEqual`. |
## `lib/helpers/t55xx/write/base.dart`

| Línea | Tipo | Owner | Firma | Descripción |
|---:|---|---|---|---|
| 16 | getter | BaseT55XXCardHelper | `@override bool get autoDetect` | Obtiene `autoDetect`. |
| 19 | getter | BaseT55XXCardHelper | `@override String get name` | Obtiene `name`. |
| 22 | getter | BaseT55XXCardHelper | `static String get staticName` | Obtiene `staticName`. |
| 28 | constructor | BaseT55XXCardHelper | `BaseT55XXCardHelper(super.communicator)` | Construye BaseT55XXCardHelper. |
| 30 | método | BaseT55XXCardHelper | `@override List<AbstractWriteHelper> getAvailableMethods()` | Operación `getAvailableMethods`. |
| 37 | método | BaseT55XXCardHelper | `@override List<AbstractWriteHelper> getAvailableMethodsByPriority()` | Operación `getAvailableMethodsByPriority`. |
| 42 | método | BaseT55XXCardHelper | `@override Widget getWriteWidget(BuildContext context, setState)` | Operación `getWriteWidget`. |
| 120 | método | BaseT55XXCardHelper | `@override Future<bool> isCompatible(CardSave card)` | Operación `isCompatible`. |
| 125 | método | BaseT55XXCardHelper | `@override Future<bool> isMagic(data)` | Operación `isMagic`. |
| 130 | método | BaseT55XXCardHelper | `@override bool isReady()` | Operación `isReady`. |
| 135 | método | BaseT55XXCardHelper | `@override bool writeWidgetSupported()` | Operación `writeWidgetSupported`. |
| 140 | método | BaseT55XXCardHelper | `@override Future<void> reset()` | Operación `reset`. |
| 146 | método | BaseT55XXCardHelper | `@override Future<bool> writeData( CardSave card, Function(int writeProgress) update)` | Operación `writeData`. |
## `lib/helpers/transit_gate.dart`

| Línea | Tipo | Owner | Firma | Descripción |
|---:|---|---|---|---|
| 19 | constructor | TransitReplayResult | `const TransitReplayResult({ required this.assessment, required this.recordCount, required this.crc32, })` | Construye TransitReplayResult. |
| 31 | constructor | TransitApplicationDecode | `const TransitApplicationDecode({ required this.applicationIndex, required this.aid, required this.apdus, required this.fields, required this.aip, required this.cryptogram, })` | Construye TransitApplicationDecode. |
| 48 | función | - | `List<TransitApplicationDecode> decodeTransitTrace( Iterable<EmvTraceRecord> records)` | Función `decodeTransitTrace`. |
| 78 | función | - | `List<String> decodeTransitRfFrame(EmvTraceRecord record)` | Función `decodeTransitRfFrame`. |
| 165 | función | - | `TransitReplayResult replayTransitReport(String encoded)` | Función `replayTransitReport`. |
| 219 | constructor | TransitGpoAttempt | `const TransitGpoAttempt({ required this.index, required this.command, required this.pdolData, required this.ttq, required this.statusWord, required this.statusText, })` | Construye TransitGpoAttempt. |
| 235 | getter | TransitGpoAttempt | `bool get succeeded` | Obtiene `succeeded`. |
| 236 | getter | TransitGpoAttempt | `String get recommendation` | Obtiene `recommendation`. |
| 245 | método | TransitGpoAttempt | `Map<String, Object?> toJson()` | Serializa TransitGpoAttempt. |
| 257 | función | - | `Uint8List transitAmountBcd(String input)` | Función `transitAmountBcd`. |
| 273 | constructor | TransitApplicationEvidence | `const TransitApplicationEvidence({ required this.index, required this.aid, required this.scheme, required this.gpoAttempted, required this.gpoSucceeded, required this.gpoStatusWord, required this.gpoStatusText, required this.gpoAttempts, required this.generateAcAttempted, required this.cryptogram, required this.cryptogramType, required this.cvmResults, required this.cardTransactionQualifiers, required this.oda, })` | Construye TransitApplicationEvidence. |
| 305 | getter | TransitApplicationEvidence | `bool get hasTransactionEvidence` | Obtiene `hasTransactionEvidence`. |
| 306 | getter | TransitApplicationEvidence | `List<String> get gpoCommands` | Obtiene `gpoCommands`. |
| 309 | método | TransitApplicationEvidence | `Map<String, Object?> toJson()` | Serializa TransitApplicationEvidence. |
| 329 | constructor | TransitGateAssessment | `const TransitGateAssessment({ required this.outcome, required this.targetDetected, required this.ppseSucceeded, required this.transactionRequested, required this.gpoAttempted, required this.gpoSucceeded, required this.applications, })` | Construye TransitGateAssessment. |
| 347 | getter | TransitGateAssessment | `bool get walletResponded` | Obtiene `walletResponded`. |
| 349 | getter | TransitGateAssessment | `bool get hasTransactionEvidence` | Obtiene `hasTransactionEvidence`. |
| 352 | getter | TransitGateAssessment | `String get headline` | Obtiene `headline`. |
| 367 | getter | TransitGateAssessment | `String get explanation` | Obtiene `explanation`. |
| 384 | getter | TransitGateAssessment | `String get _gpoFailureExplanation` | Obtiene `_gpoFailureExplanation`. |
| 404 | método | TransitGateAssessment | `Map<String, Object?> toJson()` | Serializa TransitGateAssessment. |
| 419 | función | - | `TransitGateAssessment assessTransitCapture( EmvTraceCapture capture, { required bool transactionRequested, })` | Función `assessTransitCapture`. |
| 430 | función | - | `TransitGateAssessment assessTransitRecords({ required bool targetDetected, required Iterable<EmvTraceRecord> records, required bool transactionRequested, })` | Función `assessTransitRecords`. |
| 523 | función | - | `String paymentSchemeForAid(String aid)` | Función `paymentSchemeForAid`. |
| 537 | función | - | `List<EmvTerminalProfile> transitProfileOrder(String? scheme, {required bool adaptive})` | Función `transitProfileOrder`. |
| 569 | función | - | `TransitGpoAttempt _gpoAttempt(int index, EmvApduTrace trace)` | Función `_gpoAttempt`. |
| 598 | función | - | `List<(Uint8List, Uint8List)> _foldResponseChains( List<(Uint8List, Uint8List)> pairs)` | Función `_foldResponseChains`. |
| 633 | función | - | `int? _statusWord(Uint8List response)` | Función `_statusWord`. |
| 637 | función | - | `bool _hasInstruction(Uint8List command, int instruction)` | Función `_hasInstruction`. |
| 640 | función | - | `bool _isPpseSelect(Uint8List command)` | Función `_isPpseSelect`. |
| 667 | función | - | `String _cryptogramType(int cid)` | Función `_cryptogramType`. |
| 674 | función | - | `String? _hexOrNull(Uint8List? value)` | Función `_hexOrNull`. |
| 677 | función | - | `bool _bytesEqual(List<int> left, List<int> right)` | Función `_bytesEqual`. |
| 685 | función | - | `Uint8List _strictHex(String value)` | Función `_strictHex`. |
## `lib/helpers/validators.dart`

| Línea | Tipo | Owner | Firma | Descripción |
|---:|---|---|---|---|
| 10 | función | - | `String? validateName(String? value, AppLocalizations l)` | Función `validateName`. |
| 22 | función | - | `String? validateUid( String? value, AppLocalizations l, TagType tagType, { bool isCreate = false, })` | Función `validateUid`. |
| 59 | función | - | `String? validateHex( String? value, AppLocalizations l, { int? exactBytes, String? fieldName, bool required = false, })` | Función `validateHex`. |
| 94 | función | - | `String? validateIntRange( String? value, AppLocalizations l, { required int min, required int max, bool required = true, String? emptyMessage, })` | Función `validateIntRange`. |
| 120 | función | - | `String? validateBlePin(String? value, AppLocalizations l)` | Función `validateBlePin`. |
## `lib/helpers/write.dart`

| Línea | Tipo | Owner | Firma | Descripción |
|---:|---|---|---|---|
| 17 | constructor | AbstractWriteHelper | `AbstractWriteHelper(this.communicator)` | Construye AbstractWriteHelper. |
| 22 | getter | AbstractWriteHelper | `String get name` | Obtiene `name`. |
| 23 | getter | AbstractWriteHelper | `static String get staticName` | Obtiene `staticName`. |
| 25 | getter | AbstractWriteHelper | `bool get autoDetect` | Obtiene `autoDetect`. |
| 27 | método | AbstractWriteHelper | `Future<bool> isMagic(dynamic data)` | Operación `isMagic`. |
| 29 | método | AbstractWriteHelper | `bool isReady()` | Operación `isReady`. |
| 31 | método | AbstractWriteHelper | `Future<bool> isCompatible( CardSave card)` | Operación `isCompatible`. |
| 34 | método | AbstractWriteHelper | `List<AbstractWriteHelper> getAvailableMethods()` | Operación `getAvailableMethods`. |
| 36 | método | AbstractWriteHelper | `List<AbstractWriteHelper> getAvailableMethodsByPriority()` | Operación `getAvailableMethodsByPriority`. |
| 39 | método | AbstractWriteHelper | `Future<void> getCardType()` | Operación `getCardType`. |
| 41 | método | AbstractWriteHelper | `List<dynamic> getExtraData()` | Operación `getExtraData`. |
| 45 | método | AbstractWriteHelper | `Future<void> reset()` | Operación `reset`. |
| 47 | método | AbstractWriteHelper | `static AbstractWriteHelper? getClassByCardType( TagType type, ChameleonGUIState appState, void Function() update, AppLocalizations localizations)` | Operación `getClassByCardType`. |
| 76 | método | AbstractWriteHelper | `Future<bool> writeData(CardSave card, Function(int writeProgress) update)` | Operación `writeData`. |
| 78 | método | AbstractWriteHelper | `Widget getWriteWidget(BuildContext context, dynamic setState)` | Operación `getWriteWidget`. |
| 80 | método | AbstractWriteHelper | `List<int> getFailedBlocks()` | Operación `getFailedBlocks`. |
| 84 | método | AbstractWriteHelper | `bool writeWidgetSupported()` | Operación `writeWidgetSupported`. |
| 88 | operador | AbstractWriteHelper | `@override bool operator ==(Object other)` | Operación `==`. |
| 92 | getter | AbstractWriteHelper | `@override int get hashCode` | Obtiene `hashCode`. |
## `lib/main.dart`

| Línea | Tipo | Owner | Firma | Descripción |
|---:|---|---|---|---|
| 46 | función | - | `Future<void> main()` | Función `main`. |
| 56 | constructor | ChameleonGUI | `const ChameleonGUI(this._sharedPreferencesProvider, {super.key})` | Construye ChameleonGUI. |
| 58 | método | ChameleonGUI | `@override Widget build(BuildContext context)` | Construye la interfaz de ChameleonGUI. |
| 74 | constructor | ChameleonGUIState | `ChameleonGUIState(this.sharedPreferencesProvider)` | Construye ChameleonGUIState. |
| 107 | método | ChameleonGUIState | `void changesMade()` | Operación `changesMade`. |
| 112 | método | ChameleonGUIState | `Future<T> runSlotOperation<T>( Future<T> Function() operation, { bool invalidatesMonitorBaseline = true, })` | Operación `runSlotOperation`. |
| 144 | método | ChameleonGUIState | `void onConnectorStateChanged()` | Operación `onConnectorStateChanged`. |
| 156 | método | ChameleonGUIState | `bool isAutoReconnectSuppressed(dynamic devicePort)` | Operación `isAutoReconnectSuppressed`. |
| 160 | método | ChameleonGUIState | `void clearAutoReconnectSuppression([dynamic devicePort])` | Operación `clearAutoReconnectSuppression`. |
| 166 | método | ChameleonGUIState | `void syncAutoReconnectSuppression(Iterable<dynamic> visiblePorts)` | Operación `syncAutoReconnectSuppression`. |
| 180 | método | ChameleonGUIState | `Future<void> disconnect({bool manual = false})` | Operación `disconnect`. |
| 194 | método | ChameleonGUIState | `Future<void> resetConnector()` | Operación `resetConnector`. |
| 214 | método | ChameleonGUIState | `Future<void> attachConnectedCommunicator()` | Operación `attachConnectedCommunicator`. |
| 246 | método | ChameleonGUIState | `bool _shouldMonitorEmulationChanges()` | Operación `_shouldMonitorEmulationChanges`. |
| 261 | método | ChameleonGUIState | `Future<void> setEmulationChangeMonitoring(bool enabled)` | Operación `setEmulationChangeMonitoring`. |
| 271 | método | ChameleonGUIState | `void startEmulationChangeMonitor()` | Operación `startEmulationChangeMonitor`. |
| 282 | método | ChameleonGUIState | `void stopEmulationChangeMonitor()` | Operación `stopEmulationChangeMonitor`. |
| 289 | método | ChameleonGUIState | `Future<void> pauseEmulationChangeMonitor()` | Operación `pauseEmulationChangeMonitor`. |
| 297 | método | ChameleonGUIState | `void resumeEmulationChangeMonitor()` | Operación `resumeEmulationChangeMonitor`. |
| 303 | método | ChameleonGUIState | `void _scheduleEmulationChangePoll(int generation)` | Operación `_scheduleEmulationChangePoll`. |
| 316 | método | ChameleonGUIState | `Future<_FrozenEmulationSnapshot> _captureEmulationSnapshot( ChameleonCommunicator activeCommunicator, AbstractSerial activeConnector, int generation, )` | Operación `_captureEmulationSnapshot`. |
| 393 | método | ChameleonGUIState | `void _requireCurrentEmulationMonitor( ChameleonCommunicator activeCommunicator, AbstractSerial activeConnector, int generation, )` | Operación `_requireCurrentEmulationMonitor`. |
| 407 | método | ChameleonGUIState | `Future<bool> _persistPendingEmulationChange( ChameleonCommunicator activeCommunicator, AbstractSerial activeConnector, int generation, )` | Operación `_persistPendingEmulationChange`. |
| 443 | método | ChameleonGUIState | `Future<void> _pollEmulationChanges(int generation)` | Operación `_pollEmulationChanges`. |
| 566 | método | ChameleonGUIState | `@override void dispose()` | Libera recursos de ChameleonGUIState. |
| 595 | método | ChameleonGUIState | `void setProgressBar(dynamic value)` | Operación `setProgressBar`. |
| 621 | método | ChameleonGUIState | `bool _shouldScan()` | Operación `_shouldScan`. |
| 633 | método | ChameleonGUIState | `void ensureDeviceScanRunning()` | Start the periodic scan if it isn't already running and we're in a state where scanning makes sense. |
| 643 | método | ChameleonGUIState | `void stopDeviceScan()` | Operación `stopDeviceScan`. |
| 650 | método | ChameleonGUIState | `Future<void> refreshDeviceScan()` | Operación `refreshDeviceScan`. |
| 652 | método | ChameleonGUIState | `void _scheduleNextScan()` | Operación `_scheduleNextScan`. |
| 661 | método | ChameleonGUIState | `List<Chameleon> _normalizeDevices(List<Chameleon> devices)` | Operación `_normalizeDevices`. |
| 673 | método | ChameleonGUIState | `String _signatureOf(List<Chameleon> devices)` | Operación `_signatureOf`. |
| 680 | método | ChameleonGUIState | `dynamic _firstConnectablePort(List<Chameleon> devices)` | Operación `_firstConnectablePort`. |
| 689 | método | ChameleonGUIState | `Future<void> _scanTick()` | Operación `_scanTick`. |
| 746 | método | ChameleonGUIState | `bool _isCurrentDeviceScan(int generation, AbstractSerial activeConnector)` | Operación `_isCurrentDeviceScan`. |
| 751 | método | ChameleonGUIState | `Future<void> _maybeAutoConnect(List<Chameleon> devices)` | Operación `_maybeAutoConnect`. |
| 781 | método | ChameleonGUIState | `Future<bool> connectToDevice(Chameleon chameleonDevice)` | Connect to a discovered (non-DFU) device. |
| 852 | constructor | _EmulationSnapshot | `const _EmulationSnapshot({ required this.slot, required this.tagType, required this.ownerGeneration, required this.uid, required this.memory, })` | Construye _EmulationSnapshot. |
| 860 | método | _EmulationSnapshot | `bool matchesTag(_EmulationSnapshot other)` | Operación `matchesTag`. |
| 874 | constructor | _PendingEmulationChange | `_PendingEmulationChange({ required this.entry, required this.snapshot, required this.communicator, required this.connector, })` | Construye _PendingEmulationChange. |
| 883 | constructor | _EmulationMonitorCancelled | `const _EmulationMonitorCancelled()` | Construye _EmulationMonitorCancelled. |
| 890 | constructor | _FrozenEmulationSnapshot | `const _FrozenEmulationSnapshot({ required this.transaction, required this.snapshot, })` | Construye _FrozenEmulationSnapshot. |
| 897 | constructor | MainPage | `const MainPage({super.key, required this.sharedPreferencesProvider})` | Construye MainPage. |
| 901 | método | MainPage | `@override State<MainPage> createState()` | Operación `createState`. |
| 920 | método | _MainPageState | `void _confirmConnected(String deviceName)` | Operación `_confirmConnected`. |
| 947 | método | _MainPageState | `void _notifyEmulationChange(EmulationChangeEntry entry)` | Operación `_notifyEmulationChange`. |
| 973 | método | _MainPageState | `@override void initState()` | Inicializa el estado de _MainPageState. |
| 981 | método | _MainPageState | `@override void reassemble()` | Operación `reassemble`. |
| 990 | método | _MainPageState | `AbstractSerial getConnector(ChameleonGUIState appState)` | Operación `getConnector`. |
| 1010 | método | _MainPageState | `Logger getLogger(ChameleonGUIState appState)` | Operación `getLogger`. |
| 1023 | método | _MainPageState | `@override Widget build(BuildContext context)` | Construye la interfaz de _MainPageState. |
| 1338 | constructor | BottomProgressBar | `const BottomProgressBar({super.key})` | Construye BottomProgressBar. |
| 1340 | método | BottomProgressBar | `@override Widget build(BuildContext context)` | Construye la interfaz de BottomProgressBar. |
## `lib/recovery/recovery.dart`

| Línea | Tipo | Owner | Firma | Descripción |
|---:|---|---|---|---|
| 22 | constructor | DarksideItemDart | `DarksideItemDart( {required this.nt1, required this.ks1, required this.par, required this.nr, required this.ar})` | Construye DarksideItemDart. |
| 34 | constructor | DarksideDart | `DarksideDart({required this.uid, required this.items})` | Construye DarksideDart. |
| 47 | constructor | NestedDart | `NestedDart( {required this.uid, required this.distance, required this.nt0, required this.nt0Enc, required this.par0, required this.nt1, required this.nt1Enc, required this.par1})` | Construye NestedDart. |
| 66 | constructor | StaticNestedDart | `StaticNestedDart( {required this.uid, required this.keyType, required this.nt0, required this.nt0Enc, required this.nt1, required this.nt1Enc})` | Construye StaticNestedDart. |
| 81 | constructor | StaticEncryptedNestedDart | `StaticEncryptedNestedDart( {required this.uid, required this.nt, required this.ntEnc, required this.ntParEnc})` | Construye StaticEncryptedNestedDart. |
| 91 | constructor | HardNestedDart | `HardNestedDart({required this.nonces})` | Construye HardNestedDart. |
| 103 | constructor | Mfkey32Dart | `Mfkey32Dart( {required this.uid, required this.nt0, required this.nt1, required this.nr0Enc, required this.ar0Enc, required this.nr1Enc, required this.ar1Enc})` | Construye Mfkey32Dart. |
| 120 | constructor | Mfkey64Dart | `Mfkey64Dart( {required this.uid, required this.nt, required this.nrEnc, required this.arEnc, required this.atEnc})` | Construye Mfkey64Dart. |
| 128 | función | - | `Future<List<int>> darkside(DarksideDart darkside)` | Función `darkside`. |
| 133 | función | - | `Future<List<int>> nested(NestedDart nested)` | Función `nested`. |
| 138 | función | - | `Future<List<int>> hardNested(HardNestedDart nested)` | Función `hardNested`. |
| 145 | función | - | `Future<List<int>> staticNested(StaticNestedDart nested)` | Función `staticNested`. |
| 150 | función | - | `Future<List<int>> staticEncryptedNested( StaticEncryptedNestedDart nested)` | Función `staticEncryptedNested`. |
| 156 | función | - | `Future<List<int>> mfkey32(Mfkey32Dart mfkey)` | Función `mfkey32`. |
| 161 | función | - | `Future<List<int>> mfkey64(Mfkey64Dart mfkey)` | Función `mfkey64`. |
| 166 | función | - | `String resolvePath()` | Función `resolvePath`. |
| 201 | constructor | DarksideRequest | `const DarksideRequest(this.id, this.darkside)` | Construye DarksideRequest. |
| 208 | constructor | NestedRequest | `const NestedRequest(this.id, this.nested)` | Construye NestedRequest. |
| 215 | constructor | StaticNestedRequest | `const StaticNestedRequest(this.id, this.nested)` | Construye StaticNestedRequest. |
| 222 | constructor | HardNestedRequest | `const HardNestedRequest(this.id, this.nested)` | Construye HardNestedRequest. |
| 229 | constructor | StaticEncryptedNestedRequest | `const StaticEncryptedNestedRequest(this.id, this.nested)` | Construye StaticEncryptedNestedRequest. |
| 236 | constructor | Mfkey32Request | `const Mfkey32Request(this.id, this.mfkey32)` | Construye Mfkey32Request. |
| 243 | constructor | Mfkey64Request | `const Mfkey64Request(this.id, this.mfkey64)` | Construye Mfkey64Request. |
| 253 | constructor | KeyResponse | `const KeyResponse(this.id, this.result)` | Construye KeyResponse. |
| 270 | función | - | `Future<List<int>> _sendRecoveryRequest( Object Function(int requestId) createRequest, { Duration timeout = _recoveryRequestTimeout, })` | Función `_sendRecoveryRequest`. |
| 302 | función | - | `void _failPendingRecoveryRequests(Object error, [StackTrace? stackTrace])` | Función `_failPendingRecoveryRequests`. |
| 314 | función | - | `Future<SendPort> _getRecoveryWorker()` | Función `_getRecoveryWorker`. |
| 325 | función | - | `Future<SendPort> _startRecoveryWorker(int generation)` | Starts one generation of the native recovery isolate. |
| 421 | función | - | `void _runRecoveryWorker(SendPort sendPort)` | Función `_runRecoveryWorker`. |
## `lib/sharedprefsprovider.dart`

| Línea | Tipo | Owner | Firma | Descripción |
|---:|---|---|---|---|
| 66 | constructor | SyncCheckpoint | `const SyncCheckpoint({required this.revision, required this.stateHash})` | Construye SyncCheckpoint. |
| 68 | factory | SyncCheckpoint | `factory SyncCheckpoint.fromJson(Object? value)` | Construye SyncCheckpoint. |
| 84 | método | SyncCheckpoint | `Map<String, Object> toJson()` | Serializa SyncCheckpoint. |
| 89 | operador | SyncCheckpoint | `@override bool operator ==(Object other)` | Operación `==`. |
| 95 | getter | SyncCheckpoint | `@override int get hashCode` | Obtiene `hashCode`. |
| 98 | método | SyncCheckpoint | `@override String toString()` | Operación `toString`. |
| 114 | constructor | SyncCoordinatorRecovery | `const SyncCoordinatorRecovery({ required this.transactionId, required this.targetHash, required this.decision, required this.peerCheckpoint, })` | Construye SyncCoordinatorRecovery. |
| 121 | factory | SyncCoordinatorRecovery | `factory SyncCoordinatorRecovery.fromJson(Object? value)` | Construye SyncCoordinatorRecovery. |
| 151 | método | SyncCoordinatorRecovery | `SyncCoordinatorRecovery withDecision(SyncCoordinatorDecision value)` | Operación `withDecision`. |
| 159 | método | SyncCoordinatorRecovery | `Map<String, Object> toJson()` | Serializa SyncCoordinatorRecovery. |
| 175 | constructor | SyncTransactionReceipt | `const SyncTransactionReceipt({ required this.transactionId, required this.outcome, required this.targetHash, required this.checkpoint, })` | Construye SyncTransactionReceipt. |
| 182 | factory | SyncTransactionReceipt | `factory SyncTransactionReceipt.fromJson(Object? value)` | Construye SyncTransactionReceipt. |
| 212 | método | SyncTransactionReceipt | `Map<String, Object> toJson()` | Serializa SyncTransactionReceipt. |
| 224 | constructor | SyncCheckpointConflict | `const SyncCheckpointConflict(this.expected, this.actual)` | Construye SyncCheckpointConflict. |
| 226 | método | SyncCheckpointConflict | `@override String toString()` | Operación `toString`. |
| 235 | constructor | SyncPersistenceException | `const SyncPersistenceException(this.operation, this.key)` | Construye SyncPersistenceException. |
| 237 | método | SyncPersistenceException | `@override String toString()` | Operación `toString`. |
| 249 | constructor | _DeferredMutationJournal | `const _DeferredMutationJournal({ required this.transactionId, required this.nextSequence, required this.operations, })` | Construye _DeferredMutationJournal. |
| 255 | factory | _DeferredMutationJournal | `factory _DeferredMutationJournal.empty(String transactionId)` | Construye _DeferredMutationJournal. |
| 262 | factory | _DeferredMutationJournal | `factory _DeferredMutationJournal.fromJson(Object? value)` | Construye _DeferredMutationJournal. |
| 347 | método | _DeferredMutationJournal | `_DeferredMutationJournal withScalar(String key, Object value)` | Operación `withScalar`. |
| 371 | método | _DeferredMutationJournal | `_DeferredMutationJournal withRecords({ required String key, required Map<String, String> upserts, required List<String> removals, required List<String> order, })` | Operación `withRecords`. |
| 392 | método | _DeferredMutationJournal | `Object? apply(String key, Object? base)` | Operación `apply`. |
| 410 | método | _DeferredMutationJournal | `Map<String, Object> toJson()` | Serializa _DeferredMutationJournal. |
| 418 | función | - | `bool _validUniqueIds(List<dynamic> values)` | Función `_validUniqueIds`. |
| 425 | función | - | `String? _recordId(String encoded)` | Función `_recordId`. |
| 435 | función | - | `bool _validDeferredScalar(String key, Object? value)` | Función `_validDeferredScalar`. |
| 453 | función | - | `void _validateDeferredRecord(String key, String encoded)` | Función `_validateDeferredRecord`. |
| 466 | función | - | `List<String> _applyRecordOperation( List<String> records, Map<String, Object> operation, )` | Función `_applyRecordOperation`. |
| 510 | factory | Dictionary | `factory Dictionary.fromJson(String json)` | Construye Dictionary. |
| 540 | método | Dictionary | `String toJson()` | Serializa Dictionary. |
| 550 | método | Dictionary | `@override String toString()` | Operación `toString`. |
| 559 | método | Dictionary | `Uint8List toFile()` | Operación `toFile`. |
| 563 | factory | Dictionary | `factory Dictionary.fromString( String input, { String name = '', Color color = Colors.deepOrange, })` | Construye Dictionary. |
| 603 | constructor | Dictionary | `Dictionary({ String? id, this.name = "", this.keys = const [], this.color = Colors.deepOrange, this.keyLength = 0, }) : id = id ?? const Uuid().v4()` | Construye Dictionary. |
| 624 | factory | CardSave | `factory CardSave.fromJson(String json)` | Construye CardSave. |
| 655 | método | CardSave | `String toJson()` | Serializa CardSave. |
| 670 | constructor | CardSave | `CardSave({ String? id, required this.uid, required this.name, required this.tag, int? sak, Uint8List? atqa, Uint8List? ats, CardSaveExtra? extraData, this.color = Colors.deepOrange, this.data = const [], }) : id = id ?? const Uuid().v4(), sak = sak ?? 0, atqa = atqa ?? Uint8List(0), ats = ats ?? Uint8List(0), extraData = extraData ?? CardSaveExtra()` | Construye CardSave. |
| 693 | factory | CardSaveExtra | `factory CardSaveExtra.import(Map<String, dynamic> data)` | Construye CardSaveExtra. |
| 713 | método | CardSaveExtra | `Map<String, dynamic> export()` | Operación `export`. |
| 731 | constructor | CardSaveExtra | `CardSaveExtra({ Uint8List? ultralightSignature, Uint8List? ultralightVersion, List<int>? ultralightCounters, }) : ultralightSignature = ultralightSignature ?? Uint8List(0), ultralightVersion = ultralightVersion ?? Uint8List(0), ultralightCounters = ultralightCounters ?? <int>[]` | Construye CardSaveExtra. |
| 741 | constructor | SharedPreferencesProvider | `SharedPreferencesProvider._privateConstructor()` | Construye SharedPreferencesProvider. |
| 746 | factory | SharedPreferencesProvider | `factory SharedPreferencesProvider()` | Construye SharedPreferencesProvider. |
| 769 | método | SharedPreferencesProvider | `@visibleForTesting void debugAdvanceDataSyncMutationEpoch()` | Operación `debugAdvanceDataSyncMutationEpoch`. |
| 774 | método | SharedPreferencesProvider | `Future<void> load()` | Operación `load`. |
| 801 | método | SharedPreferencesProvider | `Future<T> withDataSyncCheckpoint<T>( T Function(SyncCheckpoint checkpoint) read, )` | Operación `withDataSyncCheckpoint`. |
| 822 | método | SharedPreferencesProvider | `Future<SyncCheckpoint> getDataSyncCheckpoint()` | Operación `getDataSyncCheckpoint`. |
| 825 | método | SharedPreferencesProvider | `Future<SyncTransactionReceipt> applyDataSyncValues({ required String transactionId, required SyncCheckpoint expectedCheckpoint, required Map<String, Object> values, })` | Operación `applyDataSyncValues`. |
| 843 | método | SharedPreferencesProvider | `Future<SyncTransactionReceipt> prepareDataSyncValues({ required String transactionId, required SyncCheckpoint expectedCheckpoint, required Map<String, Object> values, SyncTransactionRole role = SyncTransactionRole.participant, SyncCheckpoint? peerCheckpoint, String? claimedTargetHash, })` | Operación `prepareDataSyncValues`. |
| 864 | método | SharedPreferencesProvider | `Future<SyncTransactionReceipt> commitDataSyncTransaction( String transactionId, )` | Operación `commitDataSyncTransaction`. |
| 869 | método | SharedPreferencesProvider | `Future<SyncTransactionReceipt> abortDataSyncParticipantFromCoordinator( String transactionId, String targetHash, )` | Operación `abortDataSyncParticipantFromCoordinator`. |
| 898 | método | SharedPreferencesProvider | `Future<SyncTransactionReceipt> recordDataSyncAbort( String transactionId, String targetHash, )` | Operación `recordDataSyncAbort`. |
| 945 | método | SharedPreferencesProvider | `Future<SyncTransactionReceipt?> getDataSyncTransactionReceipt( String transactionId, )` | Operación `getDataSyncTransactionReceipt`. |
| 972 | método | SharedPreferencesProvider | `Future<SyncCoordinatorRecovery?> getDataSyncCoordinatorRecovery()` | Operación `getDataSyncCoordinatorRecovery`. |
| 976 | método | SharedPreferencesProvider | `Future<SyncCoordinatorRecovery> decideDataSyncCoordinatorAbort( String transactionId, )` | Operación `decideDataSyncCoordinatorAbort`. |
| 1020 | método | SharedPreferencesProvider | `Future<void> completeDataSyncCoordinator(String transactionId)` | Operación `completeDataSyncCoordinator`. |
| 1043 | método | SharedPreferencesProvider | `Future<SyncTransactionReceipt?> getPendingDataSyncParticipant()` | Operación `getPendingDataSyncParticipant`. |
| 1067 | método | SharedPreferencesProvider | `void notifyDataSyncCommitted()` | Operación `notifyDataSyncCommitted`. |
| 1071 | método | SharedPreferencesProvider | `ThemeMode getTheme()` | Operación `getTheme`. |
| 1078 | método | SharedPreferencesProvider | `Future<void> setTheme(ThemeMode theme)` | Operación `setTheme`. |
| 1081 | método | SharedPreferencesProvider | `bool getSideBarAutoExpansion()` | Operación `getSideBarAutoExpansion`. |
| 1085 | método | SharedPreferencesProvider | `bool getSideBarExpanded()` | Operación `getSideBarExpanded`. |
| 1089 | método | SharedPreferencesProvider | `int getSideBarExpandedIndex()` | Operación `getSideBarExpandedIndex`. |
| 1093 | método | SharedPreferencesProvider | `Future<void> setSideBarAutoExpansion(bool autoExpanded)` | Operación `setSideBarAutoExpansion`. |
| 1096 | método | SharedPreferencesProvider | `void setSideBarExpanded(bool expanded)` | Operación `setSideBarExpanded`. |
| 1100 | método | SharedPreferencesProvider | `Future<void> setSideBarExpandedIndex(int index)` | Operación `setSideBarExpandedIndex`. |
| 1103 | método | SharedPreferencesProvider | `int getThemeColorIndex()` | Operación `getThemeColorIndex`. |
| 1108 | método | SharedPreferencesProvider | `MaterialColor getThemeColor()` | Operación `getThemeColor`. |
| 1112 | método | SharedPreferencesProvider | `Color getThemeComplementaryColor()` | Operación `getThemeComplementaryColor`. |
| 1117 | método | SharedPreferencesProvider | `Future<void> setThemeColor(int color)` | Operación `setThemeColor`. |
| 1120 | método | SharedPreferencesProvider | `bool isDebugMode()` | Operación `isDebugMode`. |
| 1124 | método | SharedPreferencesProvider | `void setDebugMode(bool value)` | Operación `setDebugMode`. |
| 1128 | método | SharedPreferencesProvider | `bool isEmulatedChameleon()` | Operación `isEmulatedChameleon`. |
| 1132 | método | SharedPreferencesProvider | `void setEmulatedChameleon(bool value)` | Operación `setEmulatedChameleon`. |
| 1136 | método | SharedPreferencesProvider | `List<Dictionary> getDictionaries({int keyLength = 0})` | Operación `getDictionaries`. |
| 1146 | método | SharedPreferencesProvider | `Future<void> setDictionaries(List<Dictionary> dictionaries)` | Operación `setDictionaries`. |
| 1157 | método | SharedPreferencesProvider | `List<CardSave> getCards()` | Operación `getCards`. |
| 1161 | método | SharedPreferencesProvider | `Future<void> setCards(List<CardSave> cards)` | Operación `setCards`. |
| 1170 | método | SharedPreferencesProvider | `bool getEmulationChangeMonitoring()` | Operación `getEmulationChangeMonitoring`. |
| 1174 | método | SharedPreferencesProvider | `Future<void> setEmulationChangeMonitoring(bool value)` | Operación `setEmulationChangeMonitoring`. |
| 1177 | método | SharedPreferencesProvider | `bool getAuthorizedRelayAppleTransit()` | Operación `getAuthorizedRelayAppleTransit`. |
| 1182 | método | SharedPreferencesProvider | `void setAuthorizedRelayAppleTransit(bool value)` | Operación `setAuthorizedRelayAppleTransit`. |
| 1186 | método | SharedPreferencesProvider | `List<EmulationChangeEntry> getEmulationChangeHistory()` | Operación `getEmulationChangeHistory`. |
| 1201 | método | SharedPreferencesProvider | `Future<void> addEmulationChange(EmulationChangeEntry entry)` | Operación `addEmulationChange`. |
| 1226 | método | SharedPreferencesProvider | `void clearEmulationChangeHistory()` | Operación `clearEmulationChangeHistory`. |
| 1230 | método | SharedPreferencesProvider | `List<SavedKeyboardScript> getKeyboardScripts()` | Operación `getKeyboardScripts`. |
| 1236 | método | SharedPreferencesProvider | `Future<void> setKeyboardScripts(List<SavedKeyboardScript> scripts)` | Operación `setKeyboardScripts`. |
| 1246 | método | SharedPreferencesProvider | `Future<void> setLocale(Locale loc)` | Operación `setLocale`. |
| 1260 | método | SharedPreferencesProvider | `String getLocaleString()` | Operación `getLocaleString`. |
| 1264 | método | SharedPreferencesProvider | `Locale getLocale()` | Operación `getLocale`. |
| 1280 | método | SharedPreferencesProvider | `Future<void> clearLocale()` | Operación `clearLocale`. |
| 1283 | método | SharedPreferencesProvider | `bool isDebugLogging()` | Operación `isDebugLogging`. |
| 1287 | método | SharedPreferencesProvider | `void setDebugLogging(bool value)` | Operación `setDebugLogging`. |
| 1291 | método | SharedPreferencesProvider | `void addLogLine(String value)` | Operación `addLogLine`. |
| 1303 | método | SharedPreferencesProvider | `void clearLogLines()` | Operación `clearLogLines`. |
| 1307 | método | SharedPreferencesProvider | `List<String> getLogLines()` | Operación `getLogLines`. |
| 1311 | método | SharedPreferencesProvider | `String dumpSettingsToJson()` | Operación `dumpSettingsToJson`. |
| 1331 | método | SharedPreferencesProvider | `Future<void> restoreSettingsFromJson(String jsonSettings)` | Operación `restoreSettingsFromJson`. |
| 1370 | método | SharedPreferencesProvider | `bool getConfirmDelete()` | Operación `getConfirmDelete`. |
| 1374 | método | SharedPreferencesProvider | `Future<void> setConfirmDelete(bool value)` | Operación `setConfirmDelete`. |
| 1377 | método | SharedPreferencesProvider | `bool getAutoScanEnabled()` | Operación `getAutoScanEnabled`. |
| 1381 | método | SharedPreferencesProvider | `Future<void> setAutoScanEnabled(bool value)` | Operación `setAutoScanEnabled`. |
| 1384 | método | SharedPreferencesProvider | `bool getAutoConnectFirstFoundDevice()` | Operación `getAutoConnectFirstFoundDevice`. |
| 1388 | método | SharedPreferencesProvider | `Future<void> setAutoConnectFirstFoundDevice(bool value)` | Operación `setAutoConnectFirstFoundDevice`. |
| 1391 | método | SharedPreferencesProvider | `bool getEthicalHackingAck()` | Operación `getEthicalHackingAck`. |
| 1395 | método | SharedPreferencesProvider | `void setEthicalHackingAck(bool value)` | Operación `setEthicalHackingAck`. |
| 1399 | método | SharedPreferencesProvider | `bool getDeviceFoundBanner()` | Operación `getDeviceFoundBanner`. |
| 1403 | método | SharedPreferencesProvider | `Future<void> setDeviceFoundBanner(bool value)` | Operación `setDeviceFoundBanner`. |
| 1406 | método | SharedPreferencesProvider | `int? _visibleInt(String key)` | Operación `_visibleInt`. |
| 1408 | método | SharedPreferencesProvider | `bool? _visibleBool(String key)` | Operación `_visibleBool`. |
| 1410 | método | SharedPreferencesProvider | `String? _visibleString(String key)` | Operación `_visibleString`. |
| 1412 | método | SharedPreferencesProvider | `List<String>? _visibleStringList(String key)` | Operación `_visibleStringList`. |
| 1417 | método | SharedPreferencesProvider | `Object? _visiblePreferenceValue(String key)` | Operación `_visiblePreferenceValue`. |
| 1431 | método | SharedPreferencesProvider | `void _publishCommittedDataSyncValues(Map<String, Object> values)` | Operación `_publishCommittedDataSyncValues`. |
| 1438 | método | SharedPreferencesProvider | `void _publishCommittedPreferenceValues(Map<String, Object> values)` | Operación `_publishCommittedPreferenceValues`. |
| 1448 | método | SharedPreferencesProvider | `Future<void> _setSynchronizedScalar( String key, Object value, { bool notify = false, })` | Operación `_setSynchronizedScalar`. |
| 1454 | método | SharedPreferencesProvider | `Future<void> _setSynchronizedScalars( Map<String, Object> values, { bool notify = false, })` | Operación `_setSynchronizedScalars`. |
| 1493 | método | SharedPreferencesProvider | `Future<void> _setSynchronizedRecords(String key, List<String> desired)` | Operación `_setSynchronizedRecords`. |
| 1516 | método | SharedPreferencesProvider | `_DeferredMutationJournal _captureDeferredScalars( String transactionId, Map<String, Object> values, )` | Operación `_captureDeferredScalars`. |
| 1534 | método | SharedPreferencesProvider | `_DeferredMutationJournal _captureDeferredRecords( String transactionId, String key, List<String> desired, )` | Operación `_captureDeferredRecords`. |
| 1580 | método | SharedPreferencesProvider | `List<String>? _persistedVisibleStringList(String key)` | Operación `_persistedVisibleStringList`. |
| 1589 | método | SharedPreferencesProvider | `void _beginDeferredCapture(String transactionId)` | Operación `_beginDeferredCapture`. |
| 1594 | método | SharedPreferencesProvider | `void _completeDeferredCapture(String transactionId)` | Operación `_completeDeferredCapture`. |
| 1614 | método | SharedPreferencesProvider | `Future<void> _persistCapturedDeferredJournal( String transactionId, _DeferredMutationJournal captured, )` | Operación `_persistCapturedDeferredJournal`. |
| 1657 | método | SharedPreferencesProvider | `Future<void> _finishDeferredWithoutTransactionLocked( String transactionId, )` | Operación `_finishDeferredWithoutTransactionLocked`. |
| 1668 | método | SharedPreferencesProvider | `void _reserveSynchronizedData(String transactionId)` | Operación `_reserveSynchronizedData`. |
| 1676 | método | SharedPreferencesProvider | `void _releaseSynchronizedData(String transactionId)` | Operación `_releaseSynchronizedData`. |
| 1690 | método | SharedPreferencesProvider | `_DeferredMutationJournal? _readDeferredMutationJournalLocked()` | Operación `_readDeferredMutationJournalLocked`. |
| 1702 | método | SharedPreferencesProvider | `Future<void> _drainDeferredMutationsLocked(String transactionId)` | Operación `_drainDeferredMutationsLocked`. |
| 1747 | método | SharedPreferencesProvider | `Future<T> _serializeDataSync<T>(Future<T> Function() action)` | Operación `_serializeDataSync`. |
| 1757 | método | SharedPreferencesProvider | `Future<SyncCheckpoint> _dataSyncCheckpointLocked()` | Operación `_dataSyncCheckpointLocked`. |
| 1790 | método | SharedPreferencesProvider | `Map<String, Object> _currentDataSyncValues()` | Operación `_currentDataSyncValues`. |
| 1818 | método | SharedPreferencesProvider | `Future<SyncTransactionReceipt> _prepareDataSyncTransactionLocked({ required String transactionId, required SyncCheckpoint expectedCheckpoint, required Map<String, Object> values, required SyncTransactionRole role, SyncCheckpoint? peerCheckpoint, String? claimedTargetHash, })` | Operación `_prepareDataSyncTransactionLocked`. |
| 1958 | método | SharedPreferencesProvider | `Future<SyncTransactionReceipt> _commitDataSyncTransactionLocked( String transactionId, )` | Operación `_commitDataSyncTransactionLocked`. |
| 2022 | método | SharedPreferencesProvider | `Future<void> _recoverDataSyncTransactionLocked()` | Operación `_recoverDataSyncTransactionLocked`. |
| 2100 | método | SharedPreferencesProvider | `Future<SyncTransactionReceipt> _rollForwardDataSyncManifestLocked( _DataSyncManifest manifest, { Map<String, Object>? stagedValues, })` | Operación `_rollForwardDataSyncManifestLocked`. |
| 2137 | método | SharedPreferencesProvider | `Future<SyncTransactionReceipt> _abortDataSyncManifestLocked( _DataSyncManifest manifest, )` | Operación `_abortDataSyncManifestLocked`. |
| 2162 | método | SharedPreferencesProvider | `Map<String, Object> _readValidatedDataSyncStagesLocked( _DataSyncManifest manifest, )` | Operación `_readValidatedDataSyncStagesLocked`. |
| 2182 | método | SharedPreferencesProvider | `Future<Map<String, Object>> _validatePreparedDataSyncManifestLocked( _DataSyncManifest manifest, )` | Operación `_validatePreparedDataSyncManifestLocked`. |
| 2201 | método | SharedPreferencesProvider | `Future<void> _finishTerminalWithoutManifestLocked( SyncTransactionReceipt receipt, )` | Operación `_finishTerminalWithoutManifestLocked`. |
| 2245 | método | SharedPreferencesProvider | `Future<void> _cleanupDataSyncManifestLocked( _DataSyncManifest manifest, )` | Operación `_cleanupDataSyncManifestLocked`. |
| 2261 | método | SharedPreferencesProvider | `SyncCoordinatorRecovery? _readCoordinatorRecoveryLocked()` | Operación `_readCoordinatorRecoveryLocked`. |
| 2273 | método | SharedPreferencesProvider | `SyncCoordinatorDecision? _coordinatorDecisionLocked(String transactionId)` | Operación `_coordinatorDecisionLocked`. |
| 2278 | método | SharedPreferencesProvider | `_DataSyncManifest? _readDataSyncManifestLocked()` | Operación `_readDataSyncManifestLocked`. |
| 2290 | método | SharedPreferencesProvider | `SyncTransactionReceipt? _findDataSyncReceiptLocked(String transactionId)` | Operación `_findDataSyncReceiptLocked`. |
| 2306 | método | SharedPreferencesProvider | `Future<void> _saveDataSyncReceiptLocked( SyncTransactionReceipt receipt, )` | Operación `_saveDataSyncReceiptLocked`. |
| 2327 | método | SharedPreferencesProvider | `Future<void> _removeDataSyncStagesLocked( Iterable<_DataSyncStageEntry> entries, )` | Operación `_removeDataSyncStagesLocked`. |
| 2335 | método | SharedPreferencesProvider | `Future<void> _removeOrphanDataSyncStagesLocked()` | Operación `_removeOrphanDataSyncStagesLocked`. |
| 2345 | método | SharedPreferencesProvider | `Future<void> _checkedSet(String key, Object value)` | Operación `_checkedSet`. |
| 2383 | método | SharedPreferencesProvider | `Future<void> _checkedRemove(String key)` | Operación `_checkedRemove`. |
| 2411 | método | SharedPreferencesProvider | `Future<void> _reconcileFailedSet(String key, Object value)` | Operación `_reconcileFailedSet`. |
| 2417 | método | SharedPreferencesProvider | `Future<void> _reconcileFailedRemove(String key)` | Operación `_reconcileFailedRemove`. |
| 2431 | constructor | _DataSyncStageEntry | `const _DataSyncStageEntry({ required this.key, required this.stageKey, required this.valueType, })` | Construye _DataSyncStageEntry. |
| 2437 | factory | _DataSyncStageEntry | `factory _DataSyncStageEntry.fromJson(Object? value)` | Construye _DataSyncStageEntry. |
| 2465 | método | _DataSyncStageEntry | `Map<String, Object> toJson()` | Serializa _DataSyncStageEntry. |
| 2481 | constructor | _DataSyncManifest | `const _DataSyncManifest({ required this.transactionId, required this.phase, required this.role, required this.expected, required this.target, required this.entries, required this.mutationEpoch, })` | Construye _DataSyncManifest. |
| 2491 | factory | _DataSyncManifest | `factory _DataSyncManifest.fromJson(Object? value)` | Construye _DataSyncManifest. |
| 2543 | método | _DataSyncManifest | `_DataSyncManifest withPhase(_DataSyncTransactionPhase value)` | Operación `withPhase`. |
| 2554 | método | _DataSyncManifest | `Map<String, Object> toJson()` | Serializa _DataSyncManifest. |
| 2566 | función | - | `Map<String, Object> _validateDataSyncValues(Map<String, Object> values)` | Función `_validateDataSyncValues`. |
| 2645 | función | - | `String _hashDataSyncValues(Map<String, Object> values)` | Función `_hashDataSyncValues`. |
| 2652 | función | - | `String _dataSyncValueType(Object value)` | Función `_dataSyncValueType`. |
| 2661 | función | - | `bool _isSha256(String value)` | Función `_isSha256`. |
| 2664 | función | - | `bool _preferenceValuesEqual(Object? actual, Object expected)` | Función `_preferenceValuesEqual`. |
| 2675 | función | - | `Object _copyDataSyncPreferenceValue(Object value)` | Función `_copyDataSyncPreferenceValue`. |
| 2678 | función | - | `List<CardSave> _decodeStoredCards(List<String> encodedCards)` | Función `_decodeStoredCards`. |
| 2690 | función | - | `List<Dictionary> _decodeStoredDictionaries(List<String> encodedDictionaries)` | Función `_decodeStoredDictionaries`. |
| 2702 | función | - | `List<SavedKeyboardScript> _decodeStoredScripts(List<String> encodedScripts)` | Función `_decodeStoredScripts`. |
| 2715 | función | - | `void validateCardSaveSemantics(CardSave card)` | Función `validateCardSaveSemantics`. |
| 2784 | función | - | `Set<int>? _storedCardUidBytes(TagType tag)` | Función `_storedCardUidBytes`. |
| 2812 | función | - | `int? _storedUltralightPageCount(TagType tag)` | Función `_storedUltralightPageCount`. |
| 2823 | función | - | `int _storedUltralightCounterCount(TagType tag)` | Función `_storedUltralightCounterCount`. |
| 2833 | función | - | `bool _isStoredLfTag(TagType tag)` | Función `_isStoredLfTag`. |
| 2847 | función | - | `void _validateStoredDictionary(Dictionary dictionary)` | Función `_validateStoredDictionary`. |
| 2855 | función | - | `Map<String, Object> _validateLegacySettings(Object? value)` | Función `_validateLegacySettings`. |
## `test/active_slot_snapshot_monitor_test.dart`

| Línea | Tipo | Owner | Firma | Descripción |
|---:|---|---|---|---|
| 13 | función | - | `void main()` | Función `main`. |
| 169 | función | - | `Future<_SnapshotFixture> _fixture({ bool blockFirstRead = false, bool blockAntiColl = false, bool randomUid = false, bool advertiseSnapshot = true, bool failSave = false, bool legacyCapabilities = false, })` | Función `_fixture`. |
| 207 | función | - | `Future<void> _waitFor(bool Function() predicate)` | Función `_waitFor`. |
| 218 | constructor | _SnapshotFixture | `const _SnapshotFixture(this.state, this.serial, this.preferences)` | Construye _SnapshotFixture. |
| 226 | constructor | _SnapshotSerial | `_SnapshotSerial({ required this.blockFirstRead, required this.blockAntiColl, required this.randomUid, required this.advertiseSnapshot, required this.failSave, required this.legacyCapabilities, }) : super(log: Logger(level: Level.off))` | Construye _SnapshotSerial. |
| 257 | método | _SnapshotSerial | `@override Future<void> open()` | Operación `open`. |
| 262 | método | _SnapshotSerial | `@override Future<bool> write(Uint8List command, {bool firmware = false})` | Operación `write`. |
| 334 | método | _SnapshotSerial | `List<int> _u32(int value)` | Operación `_u32`. |
| 341 | método | _SnapshotSerial | `Future<void> _emit( int id, List<int> data, { int status = chameleonStatusSuccess, })` | Operación `_emit`. |
| 362 | método | _SnapshotSerial | `int _lrc(List<int> data)` | Operación `_lrc`. |
| 370 | método | _SnapshotSerial | `@override Future<bool> performDisconnect()` | Operación `performDisconnect`. |
| 377 | método | _SnapshotSerial | `@override Future<List<Chameleon>> availableChameleons(bool onlyDFU)` | Operación `availableChameleons`. |
| 380 | método | _SnapshotSerial | `@override Future<bool> connectSpecificDevice(dynamic devicePort)` | Operación `connectSpecificDevice`. |
| 383 | método | _SnapshotSerial | `@override bool isManualConnectionSupported()` | Operación `isManualConnectionSupported`. |
## `test/apdu_cheatsheet_test.dart`

| Línea | Tipo | Owner | Firma | Descripción |
|---:|---|---|---|---|
| 5 | función | - | `void main()` | Función `main`. |
## `test/authorized_relay_android_config_test.dart`

| Línea | Tipo | Owner | Firma | Descripción |
|---:|---|---|---|---|
| 5 | función | - | `void main()` | Función `main`. |
## `test/authorized_relay_test.dart`

| Línea | Tipo | Owner | Firma | Descripción |
|---:|---|---|---|---|
| 13 | función | - | `void main()` | Función `main`. |
| 1384 | función | - | `AuthorizedRelaySessionPolicy _appleTransitPolicy( Uint8List selectAid, Uint8List fci, )` | Función `_appleTransitPolicy`. |
| 1403 | función | - | `Uint8List _fci({ required String aidHex, List<Uint8List>? aidValues, List<Uint8List>? pdolDefinitions, })` | Función `_fci`. |
| 1427 | función | - | `List<int> _berTlv(List<int> tag, Uint8List value)` | Función `_berTlv`. |
| 1433 | función | - | `List<int> _berLength(int length)` | Función `_berLength`. |
| 1439 | función | - | `Uint8List _shortGpo(Uint8List values, {int? le})` | Función `_shortGpo`. |
## `test/autopwn_plus_test.dart`

| Línea | Tipo | Owner | Firma | Descripción |
|---:|---|---|---|---|
| 15 | función | - | `void main()` | Función `main`. |
| 277 | constructor | _FakePort | `_FakePort({ this.resolveOnCheck = false, this.resolveOnRecovery = false, this.cancelOnCheck = false, this.cancelOnDump = false, })` | Construye _FakePort. |
| 284 | getter | _FakePort | `@override int get sectorCount` | Obtiene `sectorCount`. |
| 287 | getter | _FakePort | `@override bool get isCancelled` | Obtiene `isCancelled`. |
| 290 | getter | _FakePort | `@override String get error` | Obtiene `error`. |
| 293 | getter | _FakePort | `@override List<Uint8List> get validKeys` | Obtiene `validKeys`. |
| 296 | getter | _FakePort | `@override List<AutopwnPlusBlock> get dumpedBlocks` | Obtiene `dumpedBlocks`. |
| 299 | método | _FakePort | `@override void cancel()` | Operación `cancel`. |
| 302 | método | _FakePort | `@override Future<void> prepare(Set<int> sectors)` | Operación `prepare`. |
| 305 | método | _FakePort | `@override Future<int> reverifySeededKeys(Set<int> sectors)` | Operación `reverifySeededKeys`. |
| 311 | método | _FakePort | `@override List<AutopwnPlusTarget> unresolvedTargets(Set<int> sectors)` | Operación `unresolvedTargets`. |
| 315 | método | _FakePort | `@override Future<bool> checkTarget( AutopwnPlusTarget target, List<Uint8List> candidates)` | Operación `checkTarget`. |
| 327 | método | _FakePort | `@override Future<void> recoverMissing()` | Operación `recoverMissing`. |
| 334 | método | _FakePort | `@override bool selectedComplete(Set<int> sectors)` | Operación `selectedComplete`. |
| 337 | método | _FakePort | `@override int verifiedSlots(Set<int> sectors)` | Operación `verifiedSlots`. |
| 340 | método | _FakePort | `@override List<AutopwnPlusVerifiedKey> verifiedKeys(Set<int> sectors)` | Operación `verifiedKeys`. |
| 345 | método | _FakePort | `@override Future<List<AutopwnPlusBlock>> dumpSelected( Set<int> sectors, void Function(int completed, int total) onProgress, { Future<bool> Function()? cardGuard, })` | Operación `dumpSelected`. |
## `test/ble_address_test.dart`

| Línea | Tipo | Owner | Firma | Descripción |
|---:|---|---|---|---|
| 6 | función | - | `void main()` | Función `main`. |
## `test/ble_advertising_lab_test.dart`

| Línea | Tipo | Owner | Firma | Descripción |
|---:|---|---|---|---|
| 6 | función | - | `void main()` | Función `main`. |
## `test/ble_audit_widgets_test.dart`

| Línea | Tipo | Owner | Firma | Descripción |
|---:|---|---|---|---|
| 8 | función | - | `void main()` | Función `main`. |
## `test/ble_presentation_test.dart`

| Línea | Tipo | Owner | Firma | Descripción |
|---:|---|---|---|---|
| 6 | función | - | `void main()` | Función `main`. |
## `test/ble_reliability_test.dart`

| Línea | Tipo | Owner | Firma | Descripción |
|---:|---|---|---|---|
| 14 | función | - | `void main()` | Función `main`. |
| 222 | constructor | _FakeCommunicator | `_FakeCommunicator(this.response) : super(Logger())` | Construye _FakeCommunicator. |
| 224 | método | _FakeCommunicator | `@override Future<ChameleonMessage?> sendCmd(ChameleonCommand cmd, {Uint8List? data, Duration timeout = const Duration(seconds: 5), bool skipReceive = false, bool firstRun = false})` | Operación `sendCmd`. |
| 238 | constructor | _QueuedCommunicator | `_QueuedCommunicator(this.responses) : super(Logger())` | Construye _QueuedCommunicator. |
| 240 | método | _QueuedCommunicator | `@override Future<ChameleonMessage?> sendCmd(ChameleonCommand cmd, {Uint8List? data, Duration timeout = const Duration(seconds: 5), bool skipReceive = false, bool firstRun = false})` | Operación `sendCmd`. |
## `test/ble_responsive_layout_test.dart`

| Línea | Tipo | Owner | Firma | Descripción |
|---:|---|---|---|---|
| 21 | función | - | `void main()` | Función `main`. |
| 230 | constructor | _CapabilityCommunicator | `_CapabilityCommunicator({required this.unsupported}) : super(Logger(level: Level.off))` | Construye _CapabilityCommunicator. |
| 233 | método | _CapabilityCommunicator | `@override bool? supportsCommandSync(ChameleonCommand command)` | Operación `supportsCommandSync`. |
| 239 | constructor | _ConnectedSerial | `_ConnectedSerial() : super(log: Logger(level: Level.off))` | Construye _ConnectedSerial. |
| 241 | método | _ConnectedSerial | `@override Future<void> open()` | Operación `open`. |
| 246 | método | _ConnectedSerial | `@override Future<bool> write(Uint8List command, {bool firmware = false})` | Operación `write`. |
| 249 | método | _ConnectedSerial | `@override Future<List<Chameleon>> availableChameleons(bool onlyDFU)` | Operación `availableChameleons`. |
| 252 | método | _ConnectedSerial | `@override Future<bool> connectSpecificDevice(dynamic devicePort)` | Operación `connectSpecificDevice`. |
| 255 | método | _ConnectedSerial | `@override bool isManualConnectionSupported()` | Operación `isManualConnectionSupported`. |
## `test/candidate_priority_test.dart`

| Línea | Tipo | Owner | Firma | Descripción |
|---:|---|---|---|---|
| 7 | función | - | `Uint8List key(int n)` | Función `key`. |
| 8 | función | - | `List<String> hexes(List<Uint8List> l)` | Función `hexes`. |
| 10 | función | - | `void main()` | Función `main`. |
## `test/chameleon_command_queue_test.dart`

| Línea | Tipo | Owner | Firma | Descripción |
|---:|---|---|---|---|
| 10 | función | - | `void main()` | Función `main`. |
| 1077 | función | - | `List<int> _detectionRecord( int block, int flags, int uid, int nt, int nr, int ar, )` | Función `_detectionRecord`. |
| 1094 | función | - | `ChameleonCommunicator _communicator( _FakeSerial serial, { Duration writeTimeout = const Duration(seconds: 1), Duration snapshotSaveTimeout = activeSlotSnapshotSaveTimeout, })` | Función `_communicator`. |
| 1123 | constructor | _FakeSerial | `_FakeSerial({ this.capabilityStatus = chameleonStatusSuccess, this.capabilityPayload, Set<int>? capabilities, this.hangingCommands = const <int>{}, this.failingCommands = const <int>{}, this.respondToCommands = true, this.synchronousResponses = false, this.onCommand, }) : capabilities = capabilities ?? ChameleonCommand.values.map((command) => command.value).toSet(), super(log: Logger(level: Level.off))` | Construye _FakeSerial. |
| 1137 | método | _FakeSerial | `@override Future<void> open()` | Operación `open`. |
| 1142 | método | _FakeSerial | `@override Future<bool> write(Uint8List command, {bool firmware = false})` | Operación `write`. |
| 1173 | método | _FakeSerial | `Future<void> emitCapabilities()` | Operación `emitCapabilities`. |
| 1179 | método | _FakeSerial | `Future<void> emit( int commandId, { int status = chameleonStatusSuccess, List<int> data = const [], })` | Operación `emit`. |
| 1187 | método | _FakeSerial | `Future<void> emitFrames(List<List<int>> frames)` | Operación `emitFrames`. |
| 1191 | método | _FakeSerial | `List<int> responseFrame( int commandId, { int status = chameleonStatusSuccess, List<int> data = const [], })` | Operación `responseFrame`. |
| 1212 | método | _FakeSerial | `Uint8List _capabilityBytes(Set<int> values)` | Operación `_capabilityBytes`. |
| 1216 | método | _FakeSerial | `int _lrc(List<int> data)` | Operación `_lrc`. |
| 1224 | método | _FakeSerial | `@override Future<bool> performDisconnect()` | Operación `performDisconnect`. |
| 1231 | método | _FakeSerial | `@override Future<List<Chameleon>> availableChameleons(bool onlyDFU)` | Operación `availableChameleons`. |
| 1234 | método | _FakeSerial | `@override Future<bool> connectSpecificDevice(dynamic devicePort)` | Operación `connectSpecificDevice`. |
| 1237 | método | _FakeSerial | `@override bool isManualConnectionSupported()` | Operación `isManualConnectionSupported`. |
## `test/chameleon_frame_decoder_test.dart`

| Línea | Tipo | Owner | Firma | Descripción |
|---:|---|---|---|---|
| 6 | función | - | `void main()` | Función `main`. |
## `test/chameleon_gui_state_lifecycle_test.dart`

| Línea | Tipo | Owner | Firma | Descripción |
|---:|---|---|---|---|
| 12 | función | - | `void main()` | Función `main`. |
| 89 | función | - | `Future<_LifecycleFixture> _fixture()` | Función `_fixture`. |
| 102 | función | - | `Future<void> _waitFor(bool Function() predicate)` | Función `_waitFor`. |
| 113 | constructor | _LifecycleFixture | `const _LifecycleFixture(this.state, this.serial)` | Construye _LifecycleFixture. |
| 120 | constructor | _BlockingSerial | `_BlockingSerial() : super(log: Logger(level: Level.off))` | Construye _BlockingSerial. |
| 126 | método | _BlockingSerial | `@override Future<List<Chameleon>> availableChameleons(bool onlyDFU)` | Operación `availableChameleons`. |
| 132 | método | _BlockingSerial | `@override Future<bool> performDisconnect()` | Operación `performDisconnect`. |
| 140 | método | _BlockingSerial | `@override Future<bool> connectSpecificDevice(dynamic devicePort)` | Operación `connectSpecificDevice`. |
| 143 | método | _BlockingSerial | `@override bool isManualConnectionSupported()` | Operación `isManualConnectionSupported`. |
| 146 | método | _BlockingSerial | `@override Future<bool> write(Uint8List command, {bool firmware = false})` | Operación `write`. |
## `test/connection_capability_test.dart`

| Línea | Tipo | Owner | Firma | Descripción |
|---:|---|---|---|---|
| 10 | función | - | `void main()` | Función `main`. |
| 32 | constructor | _TimeoutSerial | `_TimeoutSerial() : super(log: Logger(level: Level.off))` | Construye _TimeoutSerial. |
| 34 | método | _TimeoutSerial | `@override Future<void> open()` | Operación `open`. |
| 39 | método | _TimeoutSerial | `@override Future<bool> write(Uint8List command, {bool firmware = false})` | Operación `write`. |
| 44 | método | _TimeoutSerial | `@override Future<bool> performDisconnect()` | Operación `performDisconnect`. |
| 52 | método | _TimeoutSerial | `@override Future<List<Chameleon>> availableChameleons(bool onlyDFU)` | Operación `availableChameleons`. |
| 55 | método | _TimeoutSerial | `@override Future<bool> connectSpecificDevice(dynamic devicePort)` | Operación `connectSpecificDevice`. |
| 58 | método | _TimeoutSerial | `@override bool isManualConnectionSupported()` | Operación `isManualConnectionSupported`. |
## `test/data_sync_page_test.dart`

| Línea | Tipo | Owner | Firma | Descripción |
|---:|---|---|---|---|
| 12 | función | - | `void main()` | Función `main`. |
## `test/data_sync_storage_test.dart`

| Línea | Tipo | Owner | Firma | Descripción |
|---:|---|---|---|---|
| 15 | función | - | `void main()` | Función `main`. |
| 1473 | función | - | `CardSave _card(String id, String name)` | Función `_card`. |
| 1476 | función | - | `SavedKeyboardScript _script(String id)` | Función `_script`. |
| 1485 | función | - | `Map<String, Object> _visibleSynchronizedValues( SharedPreferencesProvider preferences, )` | Función `_visibleSynchronizedValues`. |
## `test/data_sync_test.dart`

| Línea | Tipo | Owner | Firma | Descripción |
|---:|---|---|---|---|
| 13 | función | - | `void main()` | Función `main`. |
## `test/data_sync_transport_test.dart`

| Línea | Tipo | Owner | Firma | Descripción |
|---:|---|---|---|---|
| 11 | función | - | `void main()` | Función `main`. |
| 452 | constructor | _MemoryParticipant | `_MemoryParticipant( this.initialSnapshot, { this.commitOnAbort = false, this.failCommitBeforeDecision = false, this.targetHashOverride, })` | Construye _MemoryParticipant. |
| 464 | getter | _MemoryParticipant | `SyncState get state` | Obtiene `state`. |
| 467 | método | _MemoryParticipant | `@override Future<SyncTransactionReceipt> prepare( String transactionId, SyncSnapshot snapshot, SyncCheckpoint expectedCheckpoint, { SyncTransactionRole role = SyncTransactionRole.participant, SyncCheckpoint? peerCheckpoint, String? claimedTargetHash, })` | Operación `prepare`. |
| 510 | método | _MemoryParticipant | `@override Future<SyncTransactionReceipt> commit(String transactionId)` | Operación `commit`. |
| 539 | método | _MemoryParticipant | `@override Future<SyncTransactionReceipt> abortFromCoordinator( String transactionId, String targetHash, )` | Operación `abortFromCoordinator`. |
| 564 | método | _MemoryParticipant | `@override Future<SyncTransactionReceipt> reject( String transactionId, String targetHash, )` | Operación `reject`. |
| 579 | método | _MemoryParticipant | `@override Future<SyncTransactionReceipt?> query(String transactionId)` | Operación `query`. |
| 583 | método | _MemoryParticipant | `@override Future<SyncCoordinatorRecovery?> coordinatorRecovery()` | Operación `coordinatorRecovery`. |
| 586 | método | _MemoryParticipant | `@override Future<SyncCoordinatorRecovery> decideCoordinatorAbort( String transactionId, )` | Operación `decideCoordinatorAbort`. |
| 605 | método | _MemoryParticipant | `@override Future<void> completeCoordinator(String transactionId)` | Operación `completeCoordinator`. |
| 610 | método | _MemoryParticipant | `@override Future<SyncTransactionReceipt?> pendingParticipant()` | Operación `pendingParticipant`. |
| 622 | función | - | `String _snapshotHash(SyncSnapshot snapshot)` | Función `_snapshotHash`. |
## `test/dfu_timeout_test.dart`

| Línea | Tipo | Owner | Firma | Descripción |
|---:|---|---|---|---|
| 9 | función | - | `void main()` | Función `main`. |
| 87 | constructor | _DfuSerial | `_DfuSerial() : super(log: Logger(level: Level.off))` | Construye _DfuSerial. |
| 89 | método | _DfuSerial | `@override Future<void> open()` | Operación `open`. |
| 94 | método | _DfuSerial | `@override Future<bool> write(Uint8List command, {bool firmware = false})` | Operación `write`. |
| 100 | método | _DfuSerial | `Future<void> emit(List<int> data)` | Operación `emit`. |
| 104 | método | _DfuSerial | `@override Future<bool> performDisconnect()` | Operación `performDisconnect`. |
| 111 | método | _DfuSerial | `@override Future<List<Chameleon>> availableChameleons(bool onlyDFU)` | Operación `availableChameleons`. |
| 114 | método | _DfuSerial | `@override Future<bool> connectSpecificDevice(dynamic devicePort)` | Operación `connectSpecificDevice`. |
| 117 | método | _DfuSerial | `@override bool isManualConnectionSupported()` | Operación `isManualConnectionSupported`. |
## `test/emulation_change_test.dart`

| Línea | Tipo | Owner | Firma | Descripción |
|---:|---|---|---|---|
| 9 | función | - | `void main()` | Función `main`. |
## `test/emv_helper_test.dart`

| Línea | Tipo | Owner | Firma | Descripción |
|---:|---|---|---|---|
| 7 | función | - | `Uint8List hex(String s)` | Función `hex`. |
| 9 | función | - | `void main()` | Función `main`. |
## `test/emv_trace_test.dart`

| Línea | Tipo | Owner | Firma | Descripción |
|---:|---|---|---|---|
| 6 | función | - | `void main()` | Función `main`. |
| 196 | función | - | `Uint8List _record(int type, int stage, int sequence, Uint8List payload)` | Función `_record`. |
| 211 | función | - | `Uint8List _page( int scanId, int start, List<Uint8List> records, { required int flags, })` | Función `_page`. |
| 232 | función | - | `Uint8List _meta(int scanId, Uint8List stream, {int recordCount = 1})` | Función `_meta`. |
| 256 | función | - | `Uint8List _bytes(String hex)` | Función `_bytes`. |
| 261 | función | - | `String _hex(List<int> bytes)` | Función `_hex`. |
## `test/firmware_archive_test.dart`

| Línea | Tipo | Owner | Firma | Descripción |
|---:|---|---|---|---|
| 8 | función | - | `void main()` | Función `main`. |
## `test/hf_sniff_test.dart`

| Línea | Tipo | Owner | Firma | Descripción |
|---:|---|---|---|---|
| 6 | función | - | `void main()` | Función `main`. |
| 90 | función | - | `List<int> _packFrame(Uint8List data, {required bool isTx, int? rawBitLength})` | Función `_packFrame`. |
| 102 | función | - | `List<int> _packParityBytes(Uint8List data)` | Función `_packParityBytes`. |
## `test/key_check_marks_test.dart`

| Línea | Tipo | Owner | Firma | Descripción |
|---:|---|---|---|---|
| 10 | función | - | `void main()` | Función `main`. |
## `test/keyboard_bridge_test.dart`

| Línea | Tipo | Owner | Firma | Descripción |
|---:|---|---|---|---|
| 9 | función | - | `void main()` | Función `main`. |
| 139 | constructor | _FakeKeyboardCommunicator | `_FakeKeyboardCommunicator() : super(Logger(level: Level.off))` | Construye _FakeKeyboardCommunicator. |
| 141 | método | _FakeKeyboardCommunicator | `@override Future<ChameleonMessage?> sendCmd(ChameleonCommand cmd, {Uint8List? data, Duration timeout = const Duration(seconds: 5), bool skipReceive = false, bool firstRun = false})` | Operación `sendCmd`. |
| 180 | función | - | `ChameleonMessage _response(ChameleonCommand command, Uint8List data)` | Función `_response`. |
| 187 | función | - | `Uint8List _beginBytes()` | Función `_beginBytes`. |
| 197 | función | - | `Uint8List _chunkBytes(int uploadId, int nextOffset)` | Función `_chunkBytes`. |
| 205 | función | - | `Uint8List _commitBytes(int crc32)` | Función `_commitBytes`. |
| 214 | función | - | `Uint8List _statusBytes( [KeyboardPayloadState state = KeyboardPayloadState.ready])` | Función `_statusBytes`. |
| 237 | función | - | `Uint8List _u32(int value)` | Función `_u32`. |
## `test/keyboard_payload_test.dart`

| Línea | Tipo | Owner | Firma | Descripción |
|---:|---|---|---|---|
| 18 | función | - | `void main()` | Función `main`. |
| 199 | constructor | _KeyboardCapabilityCommunicator | `_KeyboardCapabilityCommunicator() : super(Logger(level: Level.off))` | Construye _KeyboardCapabilityCommunicator. |
| 201 | método | _KeyboardCapabilityCommunicator | `@override bool? supportsCommandSync(ChameleonCommand command)` | Operación `supportsCommandSync`. |
| 204 | método | _KeyboardCapabilityCommunicator | `@override Future<bool> isBLEPairEnabled()` | Operación `isBLEPairEnabled`. |
| 209 | método | _LegacyKeyboardCommunicator | `@override bool? supportsCommandSync(ChameleonCommand command)` | Operación `supportsCommandSync`. |
| 216 | constructor | _ConnectedSerial | `_ConnectedSerial() : super(log: Logger(level: Level.off))` | Construye _ConnectedSerial. |
| 218 | método | _ConnectedSerial | `@override Future<List<Chameleon>> availableChameleons(bool onlyDFU)` | Operación `availableChameleons`. |
| 221 | método | _ConnectedSerial | `@override Future<bool> connectSpecificDevice(dynamic devicePort)` | Operación `connectSpecificDevice`. |
| 224 | método | _ConnectedSerial | `@override bool isManualConnectionSupported()` | Operación `isManualConnectionSupported`. |
| 227 | método | _ConnectedSerial | `@override Future<bool> write(Uint8List command, {bool firmware = false})` | Operación `write`. |
## `test/keyboard_script_test.dart`

| Línea | Tipo | Owner | Firma | Descripción |
|---:|---|---|---|---|
| 7 | función | - | `void main()` | Función `main`. |
## `test/lf_sniff_test.dart`

| Línea | Tipo | Owner | Firma | Descripción |
|---:|---|---|---|---|
| 6 | función | - | `void main()` | Función `main`. |
| 47 | función | - | `Uint8List _buildManchesterSamples( List<int> bits, { int halfClock = 32, int low = 0x10, int high = 0xE0, })` | Función `_buildManchesterSamples`. |
## `test/mobile_serial_lifecycle_test.dart`

| Línea | Tipo | Owner | Firma | Descripción |
|---:|---|---|---|---|
| 9 | función | - | `void main()` | Función `main`. |
| 100 | función | - | `Future<void> _waitFor(bool Function() predicate)` | Función `_waitFor`. |
| 110 | función | - | `UsbEvent _event(String action, String deviceName)` | Función `_event`. |
| 126 | constructor | _TestMobileSerial | `_TestMobileSerial(this.ports, this.events) : super(log: Logger(level: Level.off))` | Construye _TestMobileSerial. |
| 133 | getter | _TestMobileSerial | `UsbDevice get deviceDescription` | Obtiene `deviceDescription`. |
| 144 | método | _TestMobileSerial | `@override Future<List<UsbDevice>> listUsbDevices()` | Operación `listUsbDevices`. |
| 147 | método | _TestMobileSerial | `@override Future<UsbPort?> createUsbPort(UsbDevice device)` | Operación `createUsbPort`. |
| 150 | getter | _TestMobileSerial | `@override Stream<UsbEvent>? get usbEvents` | Obtiene `usbEvents`. |
| 155 | constructor | _FakeUsbPort | `_FakeUsbPort({ this.openResult = true, this.failConfiguration = false, this.failInputCancel = false, }) : inputController = StreamController<Uint8List>( onCancel: failInputCancel ? () => Future<void>.error( StateError('input cancellation failed'), ) : null, )` | Construye _FakeUsbPort. |
| 173 | getter | _FakeUsbPort | `@override Stream<Uint8List> get inputStream` | Obtiene `inputStream`. |
| 176 | método | _FakeUsbPort | `@override Future<bool> open()` | Operación `open`. |
| 179 | método | _FakeUsbPort | `@override Future<bool> close()` | Operación `close`. |
| 186 | método | _FakeUsbPort | `@override Future<void> setRTS(bool value)` | Operación `setRTS`. |
| 189 | método | _FakeUsbPort | `@override Future<void> setDTR(bool value)` | Operación `setDTR`. |
| 194 | método | _FakeUsbPort | `@override Future<void> setPortParameters( int baudRate, int dataBits, int stopBits, int parity)` | Operación `setPortParameters`. |
| 198 | método | _FakeUsbPort | `@override dynamic noSuchMethod(Invocation invocation)` | Operación `noSuchMethod`. |
## `test/native_serial_lifecycle_test.dart`

| Línea | Tipo | Owner | Firma | Descripción |
|---:|---|---|---|---|
| 6 | función | - | `void main()` | Función `main`. |
| 74 | constructor | _TestNativeSerial | `_TestNativeSerial( this.candidates, { this.failConfiguration = false, }) : super(log: Logger(level: Level.off))` | Construye _TestNativeSerial. |
| 83 | método | _TestNativeSerial | `@override Future<List> availableDevices()` | Operación `availableDevices`. |
| 87 | método | _TestNativeSerial | `@override SerialPort createSerialPort(String address)` | Operación `createSerialPort`. |
| 90 | método | _TestNativeSerial | `@override void configureSerialPort(SerialPort candidate)` | Operación `configureSerialPort`. |
| 97 | constructor | _FakeSerialPort | `_FakeSerialPort({ required this.manufacturer, required this.productName, })` | Construye _FakeSerialPort. |
| 113 | getter | _FakeSerialPort | `@override bool get isOpen` | Obtiene `isOpen`. |
| 116 | método | _FakeSerialPort | `@override bool openReadWrite()` | Operación `openReadWrite`. |
| 122 | método | _FakeSerialPort | `@override bool close()` | Operación `close`. |
| 129 | método | _FakeSerialPort | `@override void dispose()` | Libera recursos de _FakeSerialPort. |
| 134 | método | _FakeSerialPort | `@override dynamic noSuchMethod(Invocation invocation)` | Operación `noSuchMethod`. |
## `test/non_overlapping_poller_test.dart`

| Línea | Tipo | Owner | Firma | Descripción |
|---:|---|---|---|---|
| 6 | función | - | `Future<void> _waitFor(bool Function() predicate)` | Función `_waitFor`. |
| 16 | función | - | `void main()` | Función `main`. |
## `test/reader_key_recovery_test.dart`

| Línea | Tipo | Owner | Firma | Descripción |
|---:|---|---|---|---|
| 6 | función | - | `DetectionResult record({ int uid = 0x11223344, required int block, int type = 0x60, required int nt, required int nr, required int ar, bool nested = false, })` | Función `record`. |
| 26 | función | - | `void main()` | Función `main`. |
## `test/recovery_test.dart`

| Línea | Tipo | Owner | Firma | Descripción |
|---:|---|---|---|---|
| 7 | función | - | `void main()` | Función `main`. |
## `test/relay_lab_test.dart`

| Línea | Tipo | Owner | Firma | Descripción |
|---:|---|---|---|---|
| 7 | función | - | `Uint8List _hex(String value)` | Función `_hex`. |
| 9 | función | - | `void main()` | Función `main`. |
## `test/saved_keyboard_script_test.dart`

| Línea | Tipo | Owner | Firma | Descripción |
|---:|---|---|---|---|
| 10 | función | - | `void main()` | Función `main`. |
## `test/serial_ble_reliability_test.dart`

| Línea | Tipo | Owner | Firma | Descripción |
|---:|---|---|---|---|
| 10 | función | - | `void main()` | Función `main`. |
| 254 | función | - | `void _addDevice(BLESerial serial, {bool dfu = false})` | Función `_addDevice`. |
| 263 | función | - | `Future<void> _waitFor(bool Function() predicate)` | Función `_waitFor`. |
| 274 | constructor | _BleWrite | `const _BleWrite(this.value, this.withResponse)` | Construye _BleWrite. |
| 281 | constructor | _FakeReactiveBle | `_FakeReactiveBle()` | Construye _FakeReactiveBle. |
| 296 | método | _FakeReactiveBle | `@override Stream<DiscoveredDevice> scanForDevices({ required List<Uuid> withServices, ScanMode scanMode = ScanMode.balanced, bool requireLocationServicesEnabled = true, })` | Operación `scanForDevices`. |
| 305 | método | _FakeReactiveBle | `@override Stream<ConnectionStateUpdate> connectToAdvertisingDevice({ required String id, required List<Uuid> withServices, required Duration prescanDuration, Map<Uuid, List<Uuid>>? servicesWithCharacteristicsToDiscover, Duration? connectionTimeout, })` | Operación `connectToAdvertisingDevice`. |
| 321 | método | _FakeReactiveBle | `@override Stream<List<int>> subscribeToCharacteristic( QualifiedCharacteristic characteristic, )` | Operación `subscribeToCharacteristic`. |
| 332 | método | _FakeReactiveBle | `Future<void> close()` | Operación `close`. |
| 342 | método | _FakeReactiveBle | `@override dynamic noSuchMethod(Invocation invocation)` | Operación `noSuchMethod`. |
## `test/sharedprefsprovider_test.dart`

| Línea | Tipo | Owner | Firma | Descripción |
|---:|---|---|---|---|
| 8 | función | - | `void main()` | Función `main`. |
## `test/slot_transfer_test.dart`

| Línea | Tipo | Owner | Firma | Descripción |
|---:|---|---|---|---|
| 6 | función | - | `Uint8List block(int value)` | Función `block`. |
| 9 | función | - | `void main()` | Función `main`. |
## `test/transit_gate_test.dart`

| Línea | Tipo | Owner | Firma | Descripción |
|---:|---|---|---|---|
| 8 | función | - | `void main()` | Función `main`. |
| 288 | función | - | `EmvTraceRecord _applicationRecord(int application, Uint8List aid)` | Función `_applicationRecord`. |
| 298 | función | - | `EmvTraceRecord _apduRecord({ required int sequence, required int stage, required int application, required Uint8List command, required Uint8List response, })` | Función `_apduRecord`. |
| 324 | función | - | `EmvTraceRecord _rfRecord({ required int sequence, required int stage, required bool readerToCard, required Uint8List data, })` | Función `_rfRecord`. |
| 345 | función | - | `EmvTraceRecord _record({ required int type, required int sequence, required int stage, required int application, required Uint8List payload, })` | Función `_record`. |
| 366 | función | - | `Uint8List _bytes(String value)` | Función `_bytes`. |
| 371 | función | - | `String _hex(List<int> bytes)` | Función `_hex`. |
## `tool/generate_deep_analysis_signatures.dart`

| Línea | Tipo | Owner | Firma | Descripción |
|---:|---|---|---|---|
| 10 | función | - | `void main(List<String> arguments)` | Función `main`. |
| 109 | función | - | `bool _isGenerated(String path)` | Función `_isGenerated`. |
| 116 | función | - | `String _escape(String value)` | Función `_escape`. |
| 119 | función | - | `String _escapeCode(String value)` | Función `_escapeCode`. |
| 132 | constructor | _Declaration | `const _Declaration({ required this.path, required this.line, required this.kind, required this.owner, required this.signature, required this.description, })` | Construye _Declaration. |
| 148 | constructor | _DeclarationVisitor | `_DeclarationVisitor( this.path, this.content, this.lineInfo, this.declarations, )` | Construye _DeclarationVisitor. |
| 155 | método | _DeclarationVisitor | `@override void visitFunctionDeclaration(FunctionDeclaration node)` | Operación `visitFunctionDeclaration`. |
| 169 | método | _DeclarationVisitor | `@override void visitMethodDeclaration(MethodDeclaration node)` | Operación `visitMethodDeclaration`. |
| 185 | método | _DeclarationVisitor | `@override void visitConstructorDeclaration(ConstructorDeclaration node)` | Operación `visitConstructorDeclaration`. |
| 201 | método | _DeclarationVisitor | `void _add( Declaration node, int bodyOffset, String kind, String? owner, String name, )` | Operación `_add`. |
| 232 | función | - | `String? _ownerName(AstNode? node)` | Función `_ownerName`. |
| 249 | función | - | `String _description( Comment? comment, String kind, String? owner, String name, )` | Función `_description`. |

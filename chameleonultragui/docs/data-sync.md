# Data Sync transactions

Data Sync captures cards, dictionaries, keyboard scripts, and the allowlisted
GUI settings together with a `SyncCheckpoint`. A checkpoint is the persisted
revision and SHA-256 hash of the canonical synchronized state. Import and peer
merge reviews retain that checkpoint; apply uses compare-and-swap and rejects
the review if local state changed in the meantime.

## Local journal

Existing installations are migrated by adding `data_sync_meta_v1`. Migration
does not rewrite the shipped cards, dictionaries, scripts, or setting keys.
Synchronized setters are awaited. Preparing a transaction reserves every
synchronized key before PREPARED can be returned. Setter calls made while the
reservation is active persist ordered intents in
`data_sync_deferred_mutations_v1` before completing. Scalar intents are
last-write-wins. Card, dictionary, and script intents are record-ID
upsert/remove/order deltas over a getter-visible overlay, so sync-introduced
records are preserved unless the user explicitly removed that ID. The
reservation and overlay are reconstructed after restart.

Snapshot apply is serialized and uses these application-level WAL steps:

1. Decode and validate the complete snapshot and all safe settings.
2. Write and await every `data_sync_tx_stage_v1_*` value, checking each
   `Future<bool>` result.
3. Persist `data_sync_tx_manifest_v1` in `prepared` phase.
4. Read, type-check, canonicalize, and hash every stage.
5. Recheck the expected checkpoint and mutation epoch before voting PREPARED.
   COMMIT never repeats CAS after that vote; the reservation makes the vote
   stable.
6. Roll all target keys forward, verify the canonical target hash, and persist
   the new metadata and transaction receipt.
7. Replay durable mutation intents against that terminal state while the
   reservation remains held. Only after checked replay succeeds are the
   manifest, stages, intent journal, and reservation removed.

`SharedPreferencesProvider.load()` rolls a `commitDecided` manifest forward.
The operation is idempotent, so a crash after any target write, metadata write,
or receipt write is recoverable. A non-peer `prepared` transaction has no
commit decision and is aborted. A participant that reported PREPARED remains
durable and cannot be aborted by local code or UI. Only an authenticated ABORT
carrying the matching coordinator transaction ID and target hash can abort it.
A matching committed terminal
receipt makes COMMIT irrevocable even if cleanup was interrupted; ABORT then
rolls forward rather than deleting the journal.

SharedPreferences implementations may update their in-memory cache before a
write Future reports `false` or throws. Every checked failure therefore calls
`reload()` and compares the actual key/value before cleanup or continuation.

## Peer protocol

Nearby sync pairing and encrypted frames require protocol v2. There is no v1
fallback. The coordinator and host exchange PREPARE, PREPARED, COMMIT, ACK and
QUERY messages with a transaction ID, target hash, and durable receipts.

- Each side persists its staged prepare before reporting PREPARED.
- The coordinator persists its commit decision before sending COMMIT.
- The host persists its commit decision before applying and returning ACK.
- Duplicate requests return the stored receipt.
- If ACK is lost after commit, QUERY returns the committed receipt without
  applying the transaction a second time.

The coordinator also persists `data_sync_coordinator_v1`, containing its role,
transaction ID, target hash, decision, and the peer's reviewed checkpoint. A
pre-decision coordinator record becomes a durable `abortDecided` record during
startup. Commit and abort records are retained until the peer returns the
matching committed or aborted receipt. Lost ABORT is resumed with QUERY and an
identity-bound ABORT after explicit re-pairing, just like COMMIT.
The old pairing key is not persisted: after a process or network restart, the
host starts a new foreground pairing session and the coordinator explicitly
uses Join with that new code to resume QUERY/COMMIT or QUERY/ABORT. The transaction ID, target
hash, reviewed peer checkpoint, and encrypted new pairing bind the resume to
the in-doubt transaction.

Encrypted `.cusync` bundles intentionally remain format v1 compatible. The
bundle contains the snapshot; the importing device's local checkpoint guards
the review and apply operation.

## Durability limit

This is application-level crash recovery, not a transactional storage engine.
The SharedPreferences API reports whether an asynchronous write was accepted,
but it does not provide an atomic multi-key commit, an fsync contract, or a
guarantee against platform/backend data loss during power failure. The journal
therefore prevents an application-confirmed partial commit and repairs a
retained commit decision on restart, but cannot claim stronger durability than
the platform's SharedPreferences implementation.

Nearby hosting is foreground-only. Transaction receipts, participant prepares,
and coordinator decisions are durable, but the listening socket and one-time
pairing address do not survive a process or network restart. The explicit
Host/Join re-pair flow restores liveness without weakening an irrevocable
COMMIT.

## Model validation

Card validation follows the application's persisted `CardSave` conventions.
UID whitespace is ignored only while validating and the original string is
preserved. Classic recovery's 256-entry lists may contain empty placeholders,
including entries beyond the geometry of Mini/1K/2K cards, while every nonempty
in-geometry block is exactly 16 bytes. MIFARE 1K also accepts the shipped
72-block EV1 recovery representation. Ultralight/NTAG pages are four bytes or
empty placeholders and are bounded by the tag's page count. Version and
signature metadata are empty or exactly 8 and 32 bytes; nonempty counter sets
match the tag count and each counter is 24-bit. ATQA is empty legacy data or two
bytes, and ATS is bounded to the ISO14443-A maximum. Known LF formats use their
parser widths (including the 13-byte HID representation) and carry no HF page
data. Unknown/opaque supported records remain untouched.

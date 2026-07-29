# Authorized relay security model

The authorized relay is an offline laboratory tool. It does not establish a
cryptographic card identity and must not be treated as proof that the observed
credential is genuine.

## Local binding

Turning on Arm automatically starts one persistent ISO-DEP reader session in
firmware and sends SELECT PPSE on that same session. There is no separate Prepare
requirement or live-session approval dialog. The UI shows the resulting session
ID, UID, ATQA, SAK, ATS, and advertised payment AIDs as diagnostics only.

Automatic acquisition creates an internal one-shot capability bound to all of
the following:

- the exact `ChameleonCommunicator` instance;
- the current Dart operation generation;
- the selected transparent or Apple Transit mode;
- the exact nonzero firmware session ID;
- the PPSE response prefetched on that same open session.

Successful acquisition does not send firmware STOP. The same Arm action consumes
this live capability before Android HCE can be enabled; it does not reacquire or
substitute a second backend session. Consequently, two cards or wallets with
identical UID/ATQA/SAK/ATS/PPSE fingerprints cannot share the internal capability,
and a rotating wallet UID has no special bypass.

There is no firmware inactivity lease and no GUI recycle timer. The prepared or
armed firmware session has no time-based expiry; disarm, terminal deactivation,
app backgrounding, mode changes, connection changes, RF failure, or explicit
cleanup close it even when zero APDUs were relayed. The firmware session is bound
to the USB or BLE transport that started it and aborts when that owner transport
is lost.

Poison and cleanup barriers are held in a weak registry keyed by the exact
`ChameleonCommunicator`, not in page state. Reopening the route with the same
connection therefore retains poison and waits for any prior ordered firmware
reset. Confirmed reset permits the same connection to continue; poison is retained
when reset cannot be confirmed or transport framing is invalid, and then clears
only after the registry observes a disconnect/reconnect or an exact communicator
replacement. Android payment registration is intentionally not part of per-test
cleanup.

## Native permit

Dynamic payment AID registration only configures routing. It does not authorize
HCE. Dart allocates a native arm token and calls one atomic native
`authorizeAndEnable` operation with the exact registered AID set and configured
per-APDU terminal deadline. Native code rechecks the current resumed Activity
owner, routing, event sink, AIDs, token, and deadline under the same transition. A
queued arm after pause and a second/stale arm cannot replace or clear the current
arm.

Disable, deactivation, a pending APDU's terminal deadline expiry, event-sink
replacement, and AID reregistration clear the permit. That per-APDU deadline is
the only relay expiry: native code schedules it only after a terminal APDU is
pending and has no overall arm-expiry timer, including for zero-APDU arms.
Activity pause/stop, Flutter engine cleanup, engine replacement, and Activity
destruction clear pending APDUs and authorization even when Dart is suspended.
Activity ownership is generation-bound so teardown from an old Activity cannot
disarm its replacement.

The payment `HostApduService` and its static PPSE payment group remain installed
while disarmed so Android can list and retain `CU GUI Authorized Relay` as the
selected payment service. This discoverability is not authorization: a cold or
disarmed service has no token, event sink, or registered bridge state and returns
`6400` to terminal APDUs. The latest dynamic card AID group intentionally remains
registered after STOP, deactivation, disarm, page close, and app restart. A later
Arm replaces it only after Android confirms exact registration readback. In-place
upgrades clear the old disabled-component override through `MY_PACKAGE_REPLACED`,
with Activity startup as a fallback.

Android 15+ requests the wallet role. Older devices first receive the direct
default-payment-service prompt and then fall back to NFC payment/settings pages.
The relay page and payment-settings action remain available without a connected
Ultra; opening settings during acquisition cancels and waits for backend cleanup
first. Selecting the service is setup state and may persist across app restarts;
each actual relay automatically acquires a fresh live backend and uses a new
internal native arm token without asking for a separate approval.

## Uncertain cleanup

Armed-session and preparation cleanup call
`ChameleonCommunicator.hf14a4ReaderSessionReset`. It sends command `6013` through
the serialized command queue, ordered after every earlier `6012` response on USB
and BLE. An empty reset response with status `0x68`, `0x60`, or `0x66` confirms
that the old exchange response is consumed or obsolete. The reset then clears
only the `6012` timeout quarantine, allowing a new session on the same connection;
it does not clear quarantine for any other command. APDUs are never retried after
an uncertain backend outcome.

If reset fails, has a malformed response, or cannot be issued for an identified
session, the communicator remains poisoned and reconnect is required. Invalid
transport framing invalidates and disconnects the communicator directly. A
confirmed reset does not require reconnect.

A successful START response with malformed metadata raises a typed metadata
exception. A valid extracted session ID is cleaned with confirmed STOP; without
a valid ID, or if STOP is not confirmed, the communicator is synchronously
invalidated and disconnect begins before another START can enter the queue.

## Remaining trust gap

This is the strongest continuity binding available from the local firmware API,
not cryptographic card authentication. A sophisticated live relay can reproduce
static RF metadata and PPSE data while keeping its own upstream card online.
Defending against that threat requires validated DDA/fDDA/CDA using a trusted,
maintained CAPK store, plus scheme-appropriate relay timing and terminal risk
controls. Those verifiers are not present here.

Hardware-in-the-loop validation is still required on representative Android
payment-routing implementations, over USB and BLE, for field deactivation,
process death, owner-transport loss, default-wallet persistence, ordered reset
statuses, and late firmware responses.

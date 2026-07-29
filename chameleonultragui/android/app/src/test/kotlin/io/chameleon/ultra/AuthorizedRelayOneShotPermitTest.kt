package io.chameleon.ultra

import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class AuthorizedRelayOneShotPermitTest {
    @Test
    fun matchingTokenEnablesOnce() {
        val authorized = AuthorizedRelayAuthorizationReducer.authorize(
            AuthorizedRelayAuthorizationState(),
            token = 41L,
        )
        val enabled = AuthorizedRelayAuthorizationReducer.enable(
            authorized.state,
            token = 41L,
        )
        val repeated = AuthorizedRelayAuthorizationReducer.enable(
            enabled.state,
            token = 41L,
        )

        assertTrue(authorized.accepted)
        assertTrue(enabled.accepted)
        assertFalse(repeated.accepted)
        assertNull(repeated.state.permit)
    }

    @Test
    fun mismatchedTokenConsumesPermitFailClosed() {
        val authorized = AuthorizedRelayAuthorizationReducer.authorize(
            AuthorizedRelayAuthorizationState(),
            token = 41L,
        )

        val mismatched = AuthorizedRelayAuthorizationReducer.enable(
            authorized.state,
            token = 42L,
        )

        assertFalse(mismatched.accepted)
        assertNull(mismatched.state.permit)
        assertNull(mismatched.state.enabled)
    }

    @Test
    fun invalidTokenIsRejected() {
        val invalid = AuthorizedRelayAuthorizationReducer.authorize(
            AuthorizedRelayAuthorizationState(),
            token = 0L,
        )

        assertFalse(invalid.accepted)
        assertNull(invalid.state.permit)
    }

    @Test
    fun authorizationHasNoInactivityExpiry() {
        val authorized = AuthorizedRelayAuthorizationReducer.authorize(
            AuthorizedRelayAuthorizationState(),
            token = 41L,
        )
        val enabled = AuthorizedRelayAuthorizationReducer.enable(
            authorized.state,
            token = 41L,
        )

        assertTrue(authorized.accepted)
        assertTrue(enabled.accepted)
        assertTrue(enabled.state.enabled?.token == 41L)
    }

    @Test
    fun lifecycleCleanupClearsEnabledState() {
        val authorized = AuthorizedRelayAuthorizationReducer.authorize(
            AuthorizedRelayAuthorizationState(),
            token = 41L,
        )
        val enabled = AuthorizedRelayAuthorizationReducer.enable(
            authorized.state,
            token = 41L,
        )

        val cleared = AuthorizedRelayAuthorizationReducer.clear()

        assertTrue(enabled.state.enabled?.token == 41L)
        assertNull(cleared.enabled)
        assertNull(cleared.permit)
    }

    @Test
    fun staleEventSinkCancellationCannotClearReplacement() {
        val ownership = AuthorizedRelayEventSinkOwnership()
        val first = ownership.listen(11L)!!
        val replacement = ownership.listen(12L)!!

        assertFalse(first.replacedExisting)
        assertTrue(replacement.replacedExisting)
        assertFalse(ownership.cancel(first.ownerToken, first.generation))
        assertTrue(ownership.cancel(replacement.ownerToken, replacement.generation))
    }

    @Test
    fun paymentAidRegistrationRequiresExactConfirmedReadback() {
        val requested = setOf("325041592E5359532E4444463031", "A0000000031010")

        assertTrue(
            AuthorizedRelayAidMutationVerifier.registrationSucceeded(
                requested,
                requested,
                false,
            ),
        )
        assertFalse(
            AuthorizedRelayAidMutationVerifier.registrationSucceeded(
                requested,
                setOf("A0000000031010"),
                false,
            ),
        )
        assertFalse(
            AuthorizedRelayAidMutationVerifier.registrationSucceeded(
                requested,
                emptySet(),
                true,
            ),
        )
    }

    @Test
    fun lifecycleRejectsQueuedArmAfterPauseAndStaleActivityCleanup() {
        val first = AuthorizedRelayActivityLifecycleReducer.install(11L).state
        val resumedFirst = AuthorizedRelayActivityLifecycleReducer.resume(first, 11L).state
        val pausedFirst = AuthorizedRelayActivityLifecycleReducer.retire(resumedFirst, 11L)

        assertTrue(pausedFirst.accepted)
        assertFalse(AuthorizedRelayActivityLifecycleReducer.isResumed(pausedFirst.state, 11L))

        val replacement = AuthorizedRelayActivityLifecycleReducer.install(12L).state
        val resumedReplacement = AuthorizedRelayActivityLifecycleReducer.resume(
            replacement,
            12L,
        ).state
        val staleRetire = AuthorizedRelayActivityLifecycleReducer.retire(
            resumedReplacement,
            11L,
        )

        assertFalse(staleRetire.accepted)
        assertTrue(AuthorizedRelayActivityLifecycleReducer.isResumed(staleRetire.state, 12L))
    }

    @Test
    fun staleDisableCannotConsumeReplacementPermit() {
        val replacement = AuthorizedRelayAuthorizationState(
            permit = AuthorizedRelayArm(42L),
        )

        assertFalse(
            AuthorizedRelayAuthorizationReducer.canDisable(
                replacement,
                requestedToken = 41L,
                lastArmToken = 41L,
            ),
        )
        assertTrue(
            AuthorizedRelayAuthorizationReducer.canDisable(
                replacement,
                requestedToken = 42L,
                lastArmToken = 41L,
            ),
        )
        assertFalse(AuthorizedRelayAuthorizationReducer.canStartAtomicArm(replacement))
        assertFalse(
            AuthorizedRelayAuthorizationReducer.canStartAtomicArm(
                AuthorizedRelayAuthorizationState(
                    enabled = AuthorizedRelayArm(41L),
                ),
            ),
        )
        assertTrue(
            AuthorizedRelayAuthorizationReducer.canStartAtomicArm(
                AuthorizedRelayAuthorizationState(),
            ),
        )
    }
}

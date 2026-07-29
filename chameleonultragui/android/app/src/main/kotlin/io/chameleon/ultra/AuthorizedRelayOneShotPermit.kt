package io.chameleon.ultra

internal data class AuthorizedRelayArm(
    val token: Long,
)

internal data class AuthorizedRelayAuthorizationState(
    val permit: AuthorizedRelayArm? = null,
    val enabled: AuthorizedRelayArm? = null,
)

internal data class AuthorizedRelayAuthorizationTransition(
    val state: AuthorizedRelayAuthorizationState,
    val accepted: Boolean,
)

internal object AuthorizedRelayAuthorizationReducer {
    fun canStartAtomicArm(state: AuthorizedRelayAuthorizationState): Boolean =
        state.permit == null && state.enabled == null

    fun authorize(
        state: AuthorizedRelayAuthorizationState,
        token: Long,
    ): AuthorizedRelayAuthorizationTransition {
        val cleared = state.copy(permit = null)
        if (state.enabled != null || token <= 0L) {
            return AuthorizedRelayAuthorizationTransition(cleared, false)
        }
        return AuthorizedRelayAuthorizationTransition(
            cleared.copy(permit = AuthorizedRelayArm(token)),
            true,
        )
    }

    fun enable(
        state: AuthorizedRelayAuthorizationState,
        token: Long,
    ): AuthorizedRelayAuthorizationTransition {
        val permit = state.permit
        val cleared = state.copy(permit = null)
        if (state.enabled != null || permit == null || permit.token != token) {
            return AuthorizedRelayAuthorizationTransition(cleared, false)
        }
        return AuthorizedRelayAuthorizationTransition(
            cleared.copy(enabled = permit),
            true,
        )
    }

    fun clearPermit(state: AuthorizedRelayAuthorizationState) = state.copy(permit = null)

    fun canDisable(
        state: AuthorizedRelayAuthorizationState,
        requestedToken: Long?,
        lastArmToken: Long,
    ): Boolean {
        if (requestedToken == null) return true
        if (requestedToken <= 0L) return false
        val current = state.enabled ?: state.permit
        return current?.token == requestedToken ||
            (current == null && lastArmToken == requestedToken)
    }

    fun clear() = AuthorizedRelayAuthorizationState()
}

internal data class AuthorizedRelayEventSinkRegistration(
    val ownerToken: Long,
    val generation: Long,
    val replacedExisting: Boolean,
)

internal class AuthorizedRelayEventSinkOwnership {
    private var nextGeneration = 1L
    private var active: AuthorizedRelayEventSinkRegistration? = null

    fun listen(ownerToken: Long): AuthorizedRelayEventSinkRegistration? {
        if (ownerToken <= 0L || nextGeneration <= 0L) return null
        val registration = AuthorizedRelayEventSinkRegistration(
            ownerToken = ownerToken,
            generation = nextGeneration,
            replacedExisting = active != null,
        )
        nextGeneration = if (nextGeneration == Long.MAX_VALUE) 0L else nextGeneration + 1L
        active = registration
        return registration
    }

    fun cancel(ownerToken: Long, generation: Long): Boolean {
        val current = active ?: return false
        if (current.ownerToken != ownerToken || current.generation != generation) return false
        active = null
        return true
    }

    fun invalidate() {
        active = null
    }
}

internal data class AuthorizedRelayActivityLifecycleState(
    val activeOwnerToken: Long = 0L,
    val resumedOwnerToken: Long = 0L,
)

internal data class AuthorizedRelayActivityLifecycleTransition(
    val state: AuthorizedRelayActivityLifecycleState,
    val accepted: Boolean,
)

internal object AuthorizedRelayActivityLifecycleReducer {
    fun install(ownerToken: Long): AuthorizedRelayActivityLifecycleTransition {
        if (ownerToken <= 0L) {
            return AuthorizedRelayActivityLifecycleTransition(
                AuthorizedRelayActivityLifecycleState(),
                false,
            )
        }
        return AuthorizedRelayActivityLifecycleTransition(
            AuthorizedRelayActivityLifecycleState(activeOwnerToken = ownerToken),
            true,
        )
    }

    fun resume(
        state: AuthorizedRelayActivityLifecycleState,
        ownerToken: Long,
    ): AuthorizedRelayActivityLifecycleTransition {
        if (state.activeOwnerToken != ownerToken || ownerToken <= 0L) {
            return AuthorizedRelayActivityLifecycleTransition(state, false)
        }
        return AuthorizedRelayActivityLifecycleTransition(
            state.copy(resumedOwnerToken = ownerToken),
            true,
        )
    }

    fun retire(
        state: AuthorizedRelayActivityLifecycleState,
        ownerToken: Long,
    ): AuthorizedRelayActivityLifecycleTransition {
        if (state.activeOwnerToken != ownerToken || state.resumedOwnerToken != ownerToken) {
            return AuthorizedRelayActivityLifecycleTransition(state, false)
        }
        return AuthorizedRelayActivityLifecycleTransition(
            state.copy(resumedOwnerToken = 0L),
            true,
        )
    }

    fun isResumed(
        state: AuthorizedRelayActivityLifecycleState,
        ownerToken: Long,
    ): Boolean = ownerToken > 0L && state.activeOwnerToken == ownerToken &&
        state.resumedOwnerToken == ownerToken
}

internal object AuthorizedRelayAidMutationVerifier {
    fun registrationSucceeded(
        requested: Set<String>,
        readback: Set<String>,
        readbackFailed: Boolean,
    ): Boolean = !readbackFailed && readback == requested
}

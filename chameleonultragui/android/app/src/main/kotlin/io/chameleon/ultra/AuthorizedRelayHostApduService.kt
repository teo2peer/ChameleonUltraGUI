package io.chameleon.ultra

import android.nfc.cardemulation.HostApduService
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import io.flutter.plugin.common.EventChannel
import java.lang.ref.WeakReference
import java.util.concurrent.atomic.AtomicLong

internal object AuthorizedRelayBridge {
    const val PPSE_AID = "325041592E5359532E4444463031"
    const val DEFAULT_DEADLINE_MS = 1000L
    const val MIN_DEADLINE_MS = 50L
    const val MAX_DEADLINE_MS = 5000L
    const val MAX_APDU_BYTES = 512
    const val MAX_PAYMENT_AID_COUNT = 32

    private val lock = Any()
    private val mainHandler = Handler(Looper.getMainLooper())
    private val nextId = AtomicLong(1)
    private var nextArmToken = 1L
    private var eventSink: EventChannel.EventSink? = null
    private val eventSinkOwnership = AuthorizedRelayEventSinkOwnership()
    private var authorization = AuthorizedRelayAuthorizationState()
    private var activityLifecycle = AuthorizedRelayActivityLifecycleState()
    private var routingRegistered = false
    private var lastArmToken = 0L
    private var deadlineMs = DEFAULT_DEADLINE_MS
    private var pending: PendingApdu? = null
    private var activationService = WeakReference<AuthorizedRelayHostApduService>(null)

    private data class PendingApdu(
        val id: Long,
        val armToken: Long,
        val service: WeakReference<AuthorizedRelayHostApduService>,
        val timeout: Runnable,
        val expiresAtUs: Long,
    )

    enum class SubmitResult {
        ACCEPTED,
        BUSY,
        UNAVAILABLE,
        INVALIDATED,
    }

    fun setEventSink(
        activityOwnerToken: Long,
        ownerToken: Long,
        sink: EventChannel.EventSink,
    ): AuthorizedRelayEventSinkRegistration? {
        var abandoned: AuthorizedRelayHostApduService? = null
        var routeTarget: AuthorizedRelayHostApduService? = null
        val registration: AuthorizedRelayEventSinkRegistration
        synchronized(lock) {
            if (activityLifecycle.activeOwnerToken != activityOwnerToken) return null
            registration = eventSinkOwnership.listen(ownerToken) ?: return null
            eventSink = sink
            if (registration.replacedExisting) {
                routingRegistered = false
                clearAuthorizationLocked()
                abandoned = clearPendingLocked()
                routeTarget = activationService.get()
                activationService.clear()
            }
        }
        abandoned?.sendAuthorizedResponse(SW_UNAVAILABLE)
        routeTarget?.clearAuthorizedRelayRouting()
        return registration
    }

    fun clearEventSink(
        activityOwnerToken: Long,
        ownerToken: Long,
        generation: Long,
    ): Boolean {
        var abandoned: AuthorizedRelayHostApduService? = null
        var routeTarget: AuthorizedRelayHostApduService? = null
        synchronized(lock) {
            if (activityLifecycle.activeOwnerToken != activityOwnerToken) return false
            if (!eventSinkOwnership.cancel(ownerToken, generation)) return false
            eventSink = null
            routingRegistered = false
            clearAuthorizationLocked()
            abandoned = clearPendingLocked()
            routeTarget = activationService.get()
            activationService.clear()
        }
        abandoned?.sendAuthorizedResponse(SW_UNAVAILABLE)
        routeTarget?.clearAuthorizedRelayRouting()
        return true
    }

    fun invalidateEventSinkOwnership(activityOwnerToken: Long): Boolean {
        var abandoned: AuthorizedRelayHostApduService? = null
        var routeTarget: AuthorizedRelayHostApduService? = null
        synchronized(lock) {
            if (activityLifecycle.activeOwnerToken != activityOwnerToken) return false
            eventSinkOwnership.invalidate()
            eventSink = null
            routingRegistered = false
            clearAuthorizationLocked()
            abandoned = clearPendingLocked()
            routeTarget = activationService.get()
            activationService.clear()
        }
        abandoned?.sendAuthorizedResponse(SW_UNAVAILABLE)
        routeTarget?.clearAuthorizedRelayRouting()
        return true
    }

    fun allocateArmToken(): Long = synchronized(lock) {
        if (nextArmToken <= 0L) {
            throw IllegalStateException("Authorized relay arm-token space exhausted")
        }
        val token = nextArmToken
        nextArmToken = if (token == Long.MAX_VALUE) 0L else token + 1L
        token
    }

    fun installActivityOwner(ownerToken: Long): Boolean {
        var abandoned: AuthorizedRelayHostApduService? = null
        var routeTarget: AuthorizedRelayHostApduService? = null
        synchronized(lock) {
            val transition = AuthorizedRelayActivityLifecycleReducer.install(ownerToken)
            if (!transition.accepted) return false
            activityLifecycle = transition.state
            routingRegistered = false
            clearAuthorizationLocked()
            abandoned = clearPendingLocked()
            routeTarget = activationService.get()
            activationService.clear()
        }
        abandoned?.sendAuthorizedResponse(SW_UNAVAILABLE)
        routeTarget?.clearAuthorizedRelayRouting()
        return true
    }

    fun resumeActivityOwner(ownerToken: Long): Boolean = synchronized(lock) {
        val transition = AuthorizedRelayActivityLifecycleReducer.resume(
            activityLifecycle,
            ownerToken,
        )
        activityLifecycle = transition.state
        transition.accepted
    }

    fun retireActivityOwner(ownerToken: Long): Boolean {
        var abandoned: AuthorizedRelayHostApduService? = null
        var routeTarget: AuthorizedRelayHostApduService? = null
        synchronized(lock) {
            val transition = AuthorizedRelayActivityLifecycleReducer.retire(
                activityLifecycle,
                ownerToken,
            )
            if (!transition.accepted) return false
            activityLifecycle = transition.state
            routingRegistered = false
            clearAuthorizationLocked()
            abandoned = clearPendingLocked()
            routeTarget = activationService.get()
            activationService.clear()
        }
        abandoned?.sendAuthorizedResponse(SW_UNAVAILABLE)
        routeTarget?.clearAuthorizedRelayRouting()
        return true
    }

    fun isActivityOwner(ownerToken: Long): Boolean = synchronized(lock) {
        ownerToken > 0L && activityLifecycle.activeOwnerToken == ownerToken
    }

    fun isActivityOwnerResumed(ownerToken: Long): Boolean = synchronized(lock) {
        AuthorizedRelayActivityLifecycleReducer.isResumed(activityLifecycle, ownerToken)
    }

    fun authorizeAndEnable(
        activityOwnerToken: Long,
        token: Long,
        responseDeadlineMs: Long,
    ): Boolean = synchronized(lock) {
        if (!AuthorizedRelayActivityLifecycleReducer.isResumed(
                activityLifecycle,
                activityOwnerToken,
            ) || !routingRegistered || eventSink == null ||
            responseDeadlineMs !in MIN_DEADLINE_MS..MAX_DEADLINE_MS
        ) {
            return@synchronized false
        }
        if (!AuthorizedRelayAuthorizationReducer.canStartAtomicArm(authorization)) {
            return@synchronized false
        }
        val authorized = AuthorizedRelayAuthorizationReducer.authorize(
            authorization,
            token,
        )
        authorization = authorized.state
        if (!authorized.accepted) {
            clearAuthorizationLocked()
            return@synchronized false
        }
        val enabled = AuthorizedRelayAuthorizationReducer.enable(
            authorization,
            token,
        )
        authorization = enabled.state
        if (!enabled.accepted) {
            clearAuthorizationLocked()
            return@synchronized false
        }
        lastArmToken = token
        deadlineMs = responseDeadlineMs
        true
    }

    fun setEnabled(
        value: Boolean,
        requestedArmToken: Long? = null,
    ): Boolean {
        var abandoned: AuthorizedRelayHostApduService? = null
        synchronized(lock) {
            if (value) {
                return false
            } else {
                if (!AuthorizedRelayAuthorizationReducer.canDisable(
                        authorization,
                        requestedArmToken,
                        lastArmToken,
                    )
                ) return false
                clearAuthorizationLocked()
                abandoned = clearPendingLocked()
                activationService.clear()
            }
        }
        abandoned?.sendAuthorizedResponse(SW_UNAVAILABLE)
        return true
    }

    fun isEnabled(): Boolean = synchronized(lock) { authorization.enabled != null }

    fun setRoutingRegistered(value: Boolean) {
        var abandoned: AuthorizedRelayHostApduService? = null
        synchronized(lock) {
            routingRegistered = value
            clearAuthorizationLocked()
            if (!value) {
                abandoned = clearPendingLocked()
                activationService.clear()
            }
        }
        abandoned?.sendAuthorizedResponse(SW_UNAVAILABLE)
    }

    fun isRoutingRegistered(): Boolean = synchronized(lock) { routingRegistered }

    fun isPending(token: Long, id: Long): Boolean {
        if (token <= 0L || id <= 0L) return false
        var expired = false
        val valid = synchronized(lock) {
            val nowUs = SystemClock.elapsedRealtimeNanos() / 1000L
            val current = pending
            val active = authorization.enabled
            if (active?.token != token || current == null ||
                current.armToken != token || current.id != id
            ) {
                false
            } else if (nowUs >= current.expiresAtUs) {
                expired = true
                false
            } else {
                true
            }
        }
        if (expired) expire(id, token)
        return valid
    }

    fun submit(
        origin: AuthorizedRelayHostApduService,
        apdu: ByteArray,
    ): SubmitResult {
        var id = 0L
        var token = 0L
        var receivedUs = 0L
        var expiresAtUs = 0L
        var sink: EventChannel.EventSink? = null
        var invalidateReason: String? = null
        synchronized(lock) {
            val active = authorization.enabled ?: return SubmitResult.UNAVAILABLE
            token = active.token
            if (eventSink == null) {
                invalidateReason = "event_sink_unavailable"
            } else {
                if (pending != null) return SubmitResult.BUSY
                sink = eventSink
                id = nextId.getAndIncrement()
                receivedUs = SystemClock.elapsedRealtimeNanos() / 1000L
                expiresAtUs = receivedUs + deadlineMs * 1000L
                val timeout = Runnable { expire(id, token) }
                pending = PendingApdu(
                    id,
                    token,
                    WeakReference(origin),
                    timeout,
                    expiresAtUs,
                )
                activationService = WeakReference(origin)
                mainHandler.postDelayed(timeout, deadlineMs)
            }
        }

        val failedReason = invalidateReason
        if (failedReason != null) {
            invalidate(origin, token, failedReason, completePending = false)
            return SubmitResult.INVALIDATED
        }

        return try {
            sink!!.success(
                mapOf(
                    "type" to "apdu",
                    "armToken" to token,
                    "id" to id,
                    "apdu" to apdu,
                    "receivedUs" to receivedUs,
                    "expiresAtUs" to expiresAtUs,
                ),
            )
            SubmitResult.ACCEPTED
        } catch (_: RuntimeException) {
            invalidate(origin, token, "event_delivery_failed", completePending = false)
            SubmitResult.INVALIDATED
        }
    }

    fun invalidateFromService(origin: AuthorizedRelayHostApduService, reason: String): Boolean {
        val token = synchronized(lock) {
            authorization.enabled?.token ?: return false
        }
        return invalidate(origin, token, reason, completePending = true)
    }

    private fun invalidate(
        origin: AuthorizedRelayHostApduService,
        token: Long,
        reason: String,
        completePending: Boolean,
    ): Boolean {
        var abandoned: AuthorizedRelayHostApduService? = null
        val sink: EventChannel.EventSink?
        synchronized(lock) {
            if (authorization.enabled?.token != token) return false
            routingRegistered = false
            clearAuthorizationLocked()
            val current = pending
            if (current != null) {
                mainHandler.removeCallbacks(current.timeout)
                pending = null
                if (completePending) abandoned = current.service.get()
            }
            activationService.clear()
            sink = eventSink
        }
        abandoned?.sendAuthorizedResponse(SW_UNAVAILABLE)
        origin.clearAuthorizedRelayRouting()
        try {
            sink?.success(
                mapOf(
                    "type" to "invalidated",
                    "armToken" to token,
                    "reason" to reason,
                ),
            )
        } catch (_: RuntimeException) {
            // The bridge is already invalidated even if Flutter is unavailable.
        }
        return true
    }

    fun respond(token: Long, id: Long, response: ByteArray): Boolean {
        if (token <= 0L || response.size !in 2..MAX_APDU_BYTES) {
            return false
        }

        var target: AuthorizedRelayHostApduService? = null
        var expired = false
        synchronized(lock) {
            val current = pending ?: return false
            if (authorization.enabled?.token != token ||
                current.armToken != token || current.id != id
            ) {
                return false
            }
            if (SystemClock.elapsedRealtimeNanos() / 1000L >= current.expiresAtUs) {
                expired = true
                return@synchronized
            }
            target = current.service.get() ?: run {
                mainHandler.removeCallbacks(current.timeout)
                pending = null
                return false
            }
            mainHandler.removeCallbacks(current.timeout)
            pending = null
        }
        if (expired) {
            expire(id, token)
            return false
        }
        target!!.sendAuthorizedResponse(response)
        return true
    }

    fun onDeactivated(origin: AuthorizedRelayHostApduService, reason: Int) {
        val sink: EventChannel.EventSink?
        val token: Long
        synchronized(lock) {
            if (activationService.get() !== origin) return
            token = authorization.enabled?.token ?: return
            activationService.clear()
            routingRegistered = false
            clearAuthorizationLocked()
            val current = pending
            if (current?.service?.get() === origin) {
                mainHandler.removeCallbacks(current.timeout)
                pending = null
            }
            sink = eventSink
        }
        origin.clearAuthorizedRelayRouting()
        try {
            sink?.success(
                mapOf(
                    "type" to "deactivated",
                    "armToken" to token,
                    "reason" to reason,
                ),
            )
        } catch (_: RuntimeException) {
            // The Flutter listener may disappear during NFC deactivation.
        }
    }

    private fun expire(id: Long, token: Long) {
        val target: AuthorizedRelayHostApduService
        val sink: EventChannel.EventSink?
        synchronized(lock) {
            val current = pending ?: return
            if (current.id != id || current.armToken != token ||
                authorization.enabled?.token != token
            ) return
            target = current.service.get() ?: run {
                mainHandler.removeCallbacks(current.timeout)
                pending = null
                routingRegistered = false
                clearAuthorizationLocked()
                activationService.clear()
                return
            }
            mainHandler.removeCallbacks(current.timeout)
            pending = null
            routingRegistered = false
            clearAuthorizationLocked()
            activationService.clear()
            sink = eventSink
        }
        target.sendAuthorizedResponse(SW_DEADLINE_EXCEEDED)
        target.clearAuthorizedRelayRouting()
        try {
            sink?.success(mapOf("type" to "expired", "armToken" to token, "id" to id))
        } catch (_: RuntimeException) {
            // Flutter may have gone away while the native deadline was running.
        }
    }

    private fun clearAuthorizationLocked() {
        authorization = AuthorizedRelayAuthorizationReducer.clear()
    }

    private fun clearPendingLocked(): AuthorizedRelayHostApduService? {
        val current = pending ?: return null
        mainHandler.removeCallbacks(current.timeout)
        pending = null
        return current.service.get()
    }

    private val SW_UNAVAILABLE = byteArrayOf(0x64, 0x00)
    private val SW_DEADLINE_EXCEEDED = byteArrayOf(0x64, 0x01)
}

class AuthorizedRelayHostApduService : HostApduService() {
    override fun processCommandApdu(commandApdu: ByteArray?, extras: Bundle?): ByteArray? {
        val apdu = commandApdu
        if (apdu == null || apdu.size !in 4..AuthorizedRelayBridge.MAX_APDU_BYTES) {
            AuthorizedRelayBridge.invalidateFromService(this, "malformed_apdu")
            return sw(0x67, 0x00)
        }

        return when (
            AuthorizedRelayBridge.submit(
                this,
                apdu,
            )
        ) {
            AuthorizedRelayBridge.SubmitResult.ACCEPTED -> null
            AuthorizedRelayBridge.SubmitResult.BUSY -> sw(0x69, 0x85)
            AuthorizedRelayBridge.SubmitResult.UNAVAILABLE,
            AuthorizedRelayBridge.SubmitResult.INVALIDATED -> sw(0x64, 0x00)
        }
    }

    override fun onDeactivated(reason: Int) {
        AuthorizedRelayBridge.onDeactivated(this, reason)
    }

    internal fun sendAuthorizedResponse(response: ByteArray) {
        sendResponseApdu(response)
    }

    internal fun clearAuthorizedRelayRouting() {
        // Authorization is already cleared in AuthorizedRelayBridge. Keep this
        // service installed so Android can retain it as the selected payment app.
    }

    private fun sw(first: Int, second: Int) = byteArrayOf(first.toByte(), second.toByte())
}

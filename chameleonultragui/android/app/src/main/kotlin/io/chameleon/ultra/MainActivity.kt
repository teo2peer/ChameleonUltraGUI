package io.chameleon.ultra

import android.app.KeyguardManager
import android.app.role.RoleManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.nfc.NfcAdapter
import android.nfc.cardemulation.CardEmulation
import android.os.Build
import android.os.Bundle
import android.os.SystemClock
import android.provider.Settings
import com.polidea.rxandroidble2.exceptions.BleException
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.reactivex.exceptions.UndeliverableException
import io.reactivex.plugins.RxJavaPlugins
import java.util.Locale
import java.util.concurrent.atomic.AtomicLong

class MainActivity: FlutterActivity() {
    private val relayMethods = "io.chameleon.ultra/relay_lab_methods"
    private val relayEvents = "io.chameleon.ultra/relay_lab_events"
    private val authorizedRelayMethods = "io.chameleon.ultra/authorized_relay_methods"
    private val authorizedRelayEvents = "io.chameleon.ultra/authorized_relay_events"
    private val authorizedRelayActivityOwnerToken = allocateAuthorizedRelayActivityOwnerToken()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        RxJavaPlugins.setErrorHandler { throwable ->
            if (throwable is UndeliverableException && throwable.cause is BleException) {
                return@setErrorHandler // ignore BleExceptions since we do not have subscriber
            } else {
                throw throwable
            }
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        RelayLabBridge.setEnabled(false)
        setRelayLabComponentEnabled(false)
        check(AuthorizedRelayBridge.installActivityOwner(authorizedRelayActivityOwnerToken))
        resetAuthorizedRelayRouting()
        try {
            ensureAuthorizedRelayComponentEnabled()
        } catch (_: RuntimeException) {
            // Readiness reports HCE unavailable if PackageManager rejects the service.
        }
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, relayEvents)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    RelayLabBridge.eventSink = events
                }

                override fun onCancel(arguments: Any?) {
                    RelayLabBridge.eventSink = null
                    RelayLabBridge.setEnabled(false)
                    setRelayLabComponentEnabled(false)
                }
            })
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, relayMethods)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isAvailable" -> result.success(
                        packageManager.hasSystemFeature(PackageManager.FEATURE_NFC_HOST_CARD_EMULATION)
                    )
                    "setEnabled" -> {
                        val enabled = call.argument<Boolean>("enabled") == true
                        if (enabled) {
                            setRelayLabComponentEnabled(true)
                            RelayLabBridge.setEnabled(true)
                        } else {
                            RelayLabBridge.setEnabled(false)
                            setRelayLabComponentEnabled(false)
                        }
                        result.success(RelayLabBridge.enabled)
                    }
                    "respond" -> {
                        val id = call.argument<Number>("id")?.toLong()
                        val response = call.argument<String>("responseHex")
                        result.success(id != null && response != null && RelayLabBridge.respond(id, response))
                    }
                    else -> result.notImplemented()
                }
            }

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, authorizedRelayEvents)
            .setStreamHandler(object : EventChannel.StreamHandler {
                private val ownerToken = allocateAuthorizedRelayEventSinkOwnerToken()
                private var registration: AuthorizedRelayEventSinkRegistration? = null

                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    val sink = events
                    if (sink == null) {
                        registration = null
                        if (AuthorizedRelayBridge.invalidateEventSinkOwnership(
                                authorizedRelayActivityOwnerToken,
                            )
                        ) resetAuthorizedRelayRouting()
                        return
                    }
                    val next = AuthorizedRelayBridge.setEventSink(
                        authorizedRelayActivityOwnerToken,
                        ownerToken,
                        sink,
                    )
                    registration = next
                    if (next == null || next.replacedExisting) resetAuthorizedRelayRouting()
                }

                override fun onCancel(arguments: Any?) {
                    val owned = registration
                    registration = null
                    if (owned != null && AuthorizedRelayBridge.clearEventSink(
                            authorizedRelayActivityOwnerToken,
                            owned.ownerToken,
                            owned.generation,
                        )
                    ) {
                        resetAuthorizedRelayRouting()
                    }
                }
            })
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, authorizedRelayMethods)
            .setMethodCallHandler { call, result ->
                handleAuthorizedRelayMethod(call, result)
            }
    }

    override fun onResume() {
        super.onResume()
        AuthorizedRelayBridge.resumeActivityOwner(authorizedRelayActivityOwnerToken)
    }

    override fun onPause() {
        AuthorizedRelayBridge.retireActivityOwner(authorizedRelayActivityOwnerToken)
        super.onPause()
    }

    override fun onStop() {
        AuthorizedRelayBridge.retireActivityOwner(authorizedRelayActivityOwnerToken)
        super.onStop()
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        AuthorizedRelayBridge.retireActivityOwner(authorizedRelayActivityOwnerToken)
        super.cleanUpFlutterEngine(flutterEngine)
    }

    override fun onDestroy() {
        AuthorizedRelayBridge.retireActivityOwner(authorizedRelayActivityOwnerToken)
        super.onDestroy()
    }

    private fun handleAuthorizedRelayMethod(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "getReadiness" -> result.success(authorizedRelayReadiness())
            "allocateArmToken" -> allocateAuthorizedRelayArmToken(result)
            "registerAids" -> registerAuthorizedRelayAids(call, result)
            "authorizeAndEnable" -> authorizeAndEnableAuthorizedRelay(call, result)
            "setEnabled" -> setAuthorizedRelayEnabled(call, result)
            "isPending" -> isAuthorizedRelayPending(call, result)
            "respond" -> {
                val armToken = call.argument<Number>("armToken")?.toLong()
                val id = call.argument<Number>("id")?.toLong()
                val response = call.argument<ByteArray>("response")
                result.success(
                    armToken != null && armToken > 0L && id != null && response != null &&
                        AuthorizedRelayBridge.respond(armToken, id, response),
                )
            }
            "openPaymentSettings" -> openPaymentSettings(result)
            else -> result.notImplemented()
        }
    }

    private fun allocateAuthorizedRelayArmToken(result: MethodChannel.Result) {
        try {
            result.success(
                mapOf(
                    "armToken" to AuthorizedRelayBridge.allocateArmToken(),
                    "monotonicUs" to SystemClock.elapsedRealtimeNanos() / 1000L,
                ),
            )
        } catch (error: IllegalStateException) {
            result.error("ARM_TOKEN_EXHAUSTED", error.message, null)
        }
    }

    private fun isAuthorizedRelayPending(call: MethodCall, result: MethodChannel.Result) {
        val armToken = call.argument<Number>("armToken")?.toLong()
        val id = call.argument<Number>("id")?.toLong()
        if (armToken == null || armToken <= 0L || id == null || id <= 0L) {
            result.error("INVALID_ARGUMENT", "armToken and id must be positive integers", null)
            return
        }
        result.success(AuthorizedRelayBridge.isPending(armToken, id))
    }

    private fun authorizedRelayReadiness(): Map<String, Any> {
        val hceSupported = packageManager.hasSystemFeature(
            PackageManager.FEATURE_NFC_HOST_CARD_EMULATION,
        )
        val adapter = NfcAdapter.getDefaultAdapter(this)
        val nfcEnabled = try {
            adapter?.isEnabled == true
        } catch (_: RuntimeException) {
            false
        }
        val cardEmulation = if (hceSupported && adapter != null) {
            try {
                CardEmulation.getInstance(adapter)
            } catch (_: RuntimeException) {
                null
            }
        } else {
            null
        }
        val registeredAids = readRegisteredPaymentAids(cardEmulation).aids.toList()
        val isDefault = try {
            cardEmulation?.isDefaultServiceForCategory(
                authorizedRelayComponent(),
                CardEmulation.CATEGORY_PAYMENT,
            ) == true
        } catch (_: RuntimeException) {
            false
        }

        return mapOf(
            "hceSupported" to hceSupported,
            "nfcEnabled" to nfcEnabled,
            "deviceLocked" to isDeviceLocked(),
            "isDefaultPaymentService" to isDefault,
            "registeredAids" to registeredAids,
        )
    }

    private fun registerAuthorizedRelayAids(call: MethodCall, result: MethodChannel.Result) {
        if (!AuthorizedRelayBridge.isActivityOwnerResumed(authorizedRelayActivityOwnerToken)) {
            result.error("ACTIVITY_NOT_RESUMED", "Return to CU GUI before arming HCE", null)
            return
        }
        if (AuthorizedRelayBridge.isEnabled()) {
            result.error("RELAY_ARMED", "Disarm the authorized relay before changing AIDs", null)
            return
        }
        val rawAids = call.argument<List<*>>("aids")
        val aids = validatePaymentAids(rawAids)
        if (aids == null) {
            result.error(
                "INVALID_AIDS",
                "Supply 1..31 unique payment AIDs as 5..16 byte uppercase hex strings",
                null,
            )
            return
        }
        val cardEmulation = cardEmulationOrNull()
        if (cardEmulation == null) {
            result.error("HCE_UNAVAILABLE", "Payment HCE is not available", null)
            return
        }
        val previous = readRegisteredPaymentAids(cardEmulation)
        if (previous.error != null) {
            result.error(
                "AID_REGISTRATION_FAILED",
                "Android could not read the retained payment AID group",
                previous.error.toString(),
            )
            return
        }
        AuthorizedRelayBridge.setRoutingRegistered(false)
        // The service may be instantiated as soon as the component is enabled.
        // Routing intent is not authorization; HCE still requires an atomic arm.
        try {
            ensureAuthorizedRelayComponentEnabled()
        } catch (error: RuntimeException) {
            AuthorizedRelayBridge.setRoutingRegistered(false)
            result.error("HCE_UNAVAILABLE", "Could not enable payment HCE routing", error.toString())
            return
        }
        try {
            cardEmulation.registerAidsForService(
                authorizedRelayComponent(),
                CardEmulation.CATEGORY_PAYMENT,
                aids,
            )
        } catch (_: RuntimeException) {
            // Readback below decides which exact group Android retained.
        }
        val readback = readRegisteredPaymentAids(cardEmulation)
        if (AuthorizedRelayAidMutationVerifier.registrationSucceeded(
                aids.toSet(),
                readback.aids,
                readback.error != null,
            )
        ) {
            AuthorizedRelayBridge.setRoutingRegistered(true)
            result.success(true)
            return
        }

        var previousRestored = readback.error == null && readback.aids == previous.aids
        if (!previousRestored && previous.aids.isNotEmpty()) {
            try {
                cardEmulation.registerAidsForService(
                    authorizedRelayComponent(),
                    CardEmulation.CATEGORY_PAYMENT,
                    previous.aids.toList(),
                )
            } catch (_: RuntimeException) {
                // Readback below determines whether the prior group survived.
            }
            val restoredReadback = readRegisteredPaymentAids(cardEmulation)
            previousRestored = restoredReadback.error == null &&
                restoredReadback.aids == previous.aids
        }
        result.error(
            "AID_REGISTRATION_FAILED",
            if (previousRestored) {
                "Android rejected the new payment AIDs; the previous group remains registered"
            } else {
                "Android payment AID state is uncertain; relay authorization remains disabled"
            },
            readback.error?.toString(),
        )
    }

    private fun authorizeAndEnableAuthorizedRelay(call: MethodCall, result: MethodChannel.Result) {
        if (!AuthorizedRelayBridge.isActivityOwnerResumed(authorizedRelayActivityOwnerToken)) {
            result.error("ACTIVITY_NOT_RESUMED", "Return to CU GUI before arming HCE", null)
            return
        }
        val armToken = exactLongArgument(call, "armToken")
        val aids = validatePaymentAids(call.argument<List<*>>("aids"))
        if (armToken == null || armToken <= 0L || aids == null) {
            result.error(
                "INVALID_ARGUMENT",
                "arm token and exact payment AIDs are required",
                null,
            )
            return
        }
        val deadlineArgument = call.argument<Any>("deadlineMs")
        if (deadlineArgument != null && deadlineArgument !is Number) {
            result.error("INVALID_ARGUMENT", "deadlineMs must be an integer", null)
            return
        }
        val deadlineMs = deadlineArgument?.toLong()
            ?: AuthorizedRelayBridge.DEFAULT_DEADLINE_MS
        if ((deadlineArgument is Number && deadlineArgument.toDouble() != deadlineMs.toDouble()) ||
            deadlineMs !in
            AuthorizedRelayBridge.MIN_DEADLINE_MS..AuthorizedRelayBridge.MAX_DEADLINE_MS
        ) {
            result.error("INVALID_ARGUMENT", "deadlineMs must be an integer from 50 to 5000", null)
            return
        }
        val readiness = authorizedRelayReadiness()
        val registeredAids = (readiness["registeredAids"] as List<*>).toSet()
        val ready = readiness["hceSupported"] == true &&
            readiness["nfcEnabled"] == true &&
            readiness["deviceLocked"] == false &&
            readiness["isDefaultPaymentService"] == true &&
            registeredAids == aids.toSet()
        if (!ready) {
            result.error(
                "NOT_READY",
                "Enable NFC, unlock the device, retain the exact payment AIDs, and select this payment service",
                readiness,
            )
            return
        }
        result.success(
            AuthorizedRelayBridge.authorizeAndEnable(
                authorizedRelayActivityOwnerToken,
                armToken,
                deadlineMs,
            ),
        )
    }

    private fun setAuthorizedRelayEnabled(call: MethodCall, result: MethodChannel.Result) {
        val enabled = call.argument<Boolean>("enabled")
        if (enabled == null) {
            result.error("INVALID_ARGUMENT", "enabled must be a boolean", null)
            return
        }
        if (!enabled) {
            val armToken = call.argument<Number>("armToken")?.toLong()
            if (!AuthorizedRelayBridge.isActivityOwner(authorizedRelayActivityOwnerToken)) {
                result.success(false)
                return
            }
            if (armToken == null || armToken <= 0L) {
                result.error("INVALID_ARGUMENT", "armToken must be a positive integer", null)
                return
            }
            val disabled = AuthorizedRelayBridge.setEnabled(
                false,
                requestedArmToken = armToken,
            )
            if (disabled) resetAuthorizedRelayRouting()
            result.success(disabled)
            return
        }

        result.error(
            "INVALID_ARGUMENT",
            "HCE enable must use the atomic authorizeAndEnable operation",
            null,
        )
    }

    private fun openPaymentSettings(result: MethodChannel.Result) {
        try {
            ensureAuthorizedRelayComponentEnabled()
        } catch (error: RuntimeException) {
            result.error("HCE_UNAVAILABLE", "Could not enable the CU GUI payment service", error.toString())
            return
        }
        val intents = mutableListOf<Intent>()
        if (Build.VERSION.SDK_INT >= 35) {
            val roleManager = getSystemService(RoleManager::class.java)
            if (roleManager?.isRoleAvailable(RoleManager.ROLE_WALLET) == true) {
                if (roleManager.isRoleHeld(RoleManager.ROLE_WALLET)) {
                    intents.add(Intent(Settings.ACTION_NFC_PAYMENT_SETTINGS))
                } else {
                    intents.add(roleManager.createRequestRoleIntent(RoleManager.ROLE_WALLET))
                }
            }
        }
        intents.addAll(listOf(
            Intent(CardEmulation.ACTION_CHANGE_DEFAULT).apply {
                putExtra(CardEmulation.EXTRA_CATEGORY, CardEmulation.CATEGORY_PAYMENT)
                putExtra(
                    CardEmulation.EXTRA_SERVICE_COMPONENT,
                    authorizedRelayComponent(),
                )
            },
            Intent(Settings.ACTION_NFC_PAYMENT_SETTINGS),
            Intent(Settings.ACTION_NFC_SETTINGS),
        ))
        for (intent in intents) {
            try {
                startActivity(intent)
                result.success(true)
                return
            } catch (_: RuntimeException) {
                // Try the less-specific NFC settings page on devices without payment settings.
            }
        }
        result.error("SETTINGS_UNAVAILABLE", "No NFC payment settings activity is available", null)
    }

    private fun validatePaymentAids(rawAids: List<*>?): List<String>? {
        if (rawAids.isNullOrEmpty() || rawAids.size > AuthorizedRelayBridge.MAX_PAYMENT_AID_COUNT) {
            return null
        }
        val aids = linkedSetOf(AuthorizedRelayBridge.PPSE_AID)
        for (value in rawAids) {
            val aid = value as? String ?: return null
            if (aid.length !in 10..32 || aid.length % 2 != 0 || !aid.matches(AID_PATTERN)) {
                return null
            }
            aids.add(aid)
            if (aids.size > AuthorizedRelayBridge.MAX_PAYMENT_AID_COUNT) return null
        }
        if (aids.none { it != AuthorizedRelayBridge.PPSE_AID }) return null
        return aids.toList()
    }

    private fun exactLongArgument(call: MethodCall, name: String): Long? {
        val value = call.argument<Any>(name) as? Number ?: return null
        val integer = value.toLong()
        return if (value.toDouble() == integer.toDouble()) integer else null
    }

    private fun cardEmulationOrNull(): CardEmulation? {
        if (!packageManager.hasSystemFeature(PackageManager.FEATURE_NFC_HOST_CARD_EMULATION)) {
            return null
        }
        val adapter = NfcAdapter.getDefaultAdapter(this) ?: return null
        return try {
            CardEmulation.getInstance(adapter)
        } catch (_: RuntimeException) {
            null
        }
    }

    private fun readRegisteredPaymentAids(cardEmulation: CardEmulation?): PaymentAidReadback {
        if (cardEmulation == null) return PaymentAidReadback(emptySet())
        return try {
            val aids = cardEmulation.getAidsForService(
                authorizedRelayComponent(),
                CardEmulation.CATEGORY_PAYMENT,
            )
            PaymentAidReadback(aids.orEmpty().map { it.uppercase(Locale.US) }.toSet())
        } catch (error: RuntimeException) {
            PaymentAidReadback(emptySet(), error)
        }
    }

    private fun authorizedRelayComponent() =
        ComponentName(this, AuthorizedRelayHostApduService::class.java)

    private fun relayLabComponent() =
        ComponentName(this, RelayLabHostApduService::class.java)

    private fun setRelayLabComponentEnabled(enabled: Boolean) {
        packageManager.setComponentEnabledSetting(
            relayLabComponent(),
            if (enabled) {
                PackageManager.COMPONENT_ENABLED_STATE_ENABLED
            } else {
                PackageManager.COMPONENT_ENABLED_STATE_DISABLED
            },
            PackageManager.DONT_KILL_APP,
        )
    }

    private fun ensureAuthorizedRelayComponentEnabled() {
        packageManager.setComponentEnabledSetting(
            authorizedRelayComponent(),
            PackageManager.COMPONENT_ENABLED_STATE_DEFAULT,
            PackageManager.DONT_KILL_APP,
        )
    }

    private fun resetAuthorizedRelayRouting() {
        if (!AuthorizedRelayBridge.isActivityOwner(authorizedRelayActivityOwnerToken)) return
        // Keep the payment service discoverable/default while clearing every
        // one-shot authorization and pending APDU. Dynamic AIDs remain registered.
        AuthorizedRelayBridge.setEnabled(false)
        AuthorizedRelayBridge.setRoutingRegistered(false)
    }

    private fun isDeviceLocked(): Boolean {
        val keyguard = getSystemService(Context.KEYGUARD_SERVICE) as? KeyguardManager
            ?: return true
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP_MR1) {
            keyguard.isDeviceLocked
        } else {
            keyguard.isKeyguardLocked
        }
    }

    companion object {
        private val AID_PATTERN = Regex("[0-9A-F]+")
        private val NEXT_AUTHORIZED_RELAY_EVENT_SINK_OWNER = AtomicLong(1L)
        private val NEXT_AUTHORIZED_RELAY_ACTIVITY_OWNER = AtomicLong(1L)

        private fun allocateAuthorizedRelayEventSinkOwnerToken(): Long {
            val token = NEXT_AUTHORIZED_RELAY_EVENT_SINK_OWNER.getAndIncrement()
            check(token > 0L) { "Authorized relay event-sink owner space exhausted" }
            return token
        }

        private fun allocateAuthorizedRelayActivityOwnerToken(): Long {
            val token = NEXT_AUTHORIZED_RELAY_ACTIVITY_OWNER.getAndIncrement()
            check(token > 0L) { "Authorized relay Activity-owner space exhausted" }
            return token
        }
    }

    private data class PaymentAidReadback(
        val aids: Set<String>,
        val error: RuntimeException? = null,
    )
}

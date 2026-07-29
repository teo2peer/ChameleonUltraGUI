package io.chameleon.ultra

import android.nfc.cardemulation.HostApduService
import android.os.Bundle
import android.os.SystemClock
import io.flutter.plugin.common.EventChannel
import java.lang.ref.WeakReference
import java.util.concurrent.atomic.AtomicLong

object RelayLabBridge {
    private val nextId = AtomicLong(1)
    private var service = WeakReference<RelayLabHostApduService>(null)
    var eventSink: EventChannel.EventSink? = null
    var enabled = false
        private set

    @Synchronized
    fun setEnabled(value: Boolean) {
        enabled = value
        if (!value) {
            service.get()?.let(::clear)
            service.clear()
        }
    }

    @Synchronized
    fun submit(origin: RelayLabHostApduService, apdu: ByteArray): Boolean {
        if (!enabled || eventSink == null) return false
        val id = nextId.getAndIncrement()
        service = WeakReference(origin)
        origin.pendingId = id
        eventSink?.success(mapOf(
            "id" to id,
            "apduHex" to apdu.toHex(),
            "receivedUs" to SystemClock.elapsedRealtimeNanos() / 1000L,
        ))
        return true
    }

    @Synchronized
    fun respond(id: Long, responseHex: String): Boolean {
        if (!enabled) return false
        val target = service.get() ?: return false
        val response = responseHex.hexToBytesOrNull() ?: return false
        if (response.size !in 2..260) return false
        return target.deliverResponse(id, response)
    }

    @Synchronized
    fun clear(origin: RelayLabHostApduService) {
        if (service.get() === origin) service.clear()
        origin.pendingId = null
    }
}

class RelayLabHostApduService : HostApduService() {
    internal var pendingId: Long? = null
    private var pendingWasSelect = false
    private var privateAidSelected = false

    override fun processCommandApdu(commandApdu: ByteArray?, extras: Bundle?): ByteArray? {
        val apdu = commandApdu ?: return sw(0x67, 0x00)
        val rejection = rejectUnsafeApdu(apdu)
        if (rejection != null) return rejection
        if (pendingId != null) return sw(0x69, 0x85)
        pendingWasSelect = isPrivateSelect(apdu)
        return if (RelayLabBridge.submit(this, apdu)) null else sw(0x64, 0x00)
    }

    override fun onDeactivated(reason: Int) {
        privateAidSelected = false
        pendingWasSelect = false
        RelayLabBridge.clear(this)
    }

    internal fun deliverResponse(id: Long, response: ByteArray): Boolean {
        if (pendingId != id) return false
        if (pendingWasSelect) {
            privateAidSelected = response.size >= 2 &&
                response[response.size - 2] == 0x90.toByte() &&
                response[response.size - 1] == 0x00.toByte()
        }
        pendingId = null
        pendingWasSelect = false
        sendResponseApdu(response)
        return true
    }

    private fun rejectUnsafeApdu(apdu: ByteArray): ByteArray? {
        if (apdu.size !in 4..64) return sw(0x67, 0x00)
        val ins = apdu[1].toInt() and 0xff
        if ((apdu[0].toInt() and 0xff) == 0x00 && ins == 0xa4) {
            if (apdu.size < 12 || apdu[2] != 0x04.toByte() || apdu[3] != 0x00.toByte()) {
                return sw(0x6a, 0x86)
            }
            val aid = apdu.copyOfRange(5, 12).toHex()
            return if (apdu[4].toInt() == 7 && aid == PRIVATE_AID) null else sw(0x6a, 0x82)
        }
        if (!privateAidSelected) return sw(0x69, 0x85)
        return if ((apdu[0].toInt() and 0xff) == 0xf0) null else sw(0x6e, 0x00)
    }

    private fun isPrivateSelect(apdu: ByteArray): Boolean =
        apdu.size >= 12 &&
            apdu[0] == 0x00.toByte() &&
            apdu[1] == 0xa4.toByte() &&
            apdu[2] == 0x04.toByte() &&
            apdu[3] == 0x00.toByte() &&
            apdu[4].toInt() == 7 &&
            apdu.copyOfRange(5, 12).toHex() == PRIVATE_AID

    private fun sw(first: Int, second: Int) = byteArrayOf(first.toByte(), second.toByte())

    companion object {
        private const val PRIVATE_AID = "F0010203040506"
    }
}

private fun ByteArray.toHex(): String = joinToString("") { "%02X".format(it) }

private fun String.hexToBytesOrNull(): ByteArray? {
    if (length % 2 != 0 || !matches(Regex("[0-9a-fA-F]+"))) return null
    return try {
        ByteArray(length / 2) { index -> substring(index * 2, index * 2 + 2).toInt(16).toByte() }
    } catch (_: NumberFormatException) {
        null
    }
}

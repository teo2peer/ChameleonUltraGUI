package io.chameleon.ultra

import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager

class AuthorizedRelayUpgradeReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        if (intent?.action != Intent.ACTION_MY_PACKAGE_REPLACED) return
        try {
            context.packageManager.setComponentEnabledSetting(
                ComponentName(context, AuthorizedRelayHostApduService::class.java),
                PackageManager.COMPONENT_ENABLED_STATE_DEFAULT,
                PackageManager.DONT_KILL_APP,
            )
        } catch (_: RuntimeException) {
            // MainActivity retries the migration when the user next opens the app.
        }
    }
}

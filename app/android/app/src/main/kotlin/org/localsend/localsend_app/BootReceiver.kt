package org.localsend.localsend_app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.UserManager
import android.util.Log

class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        // BOOT_COMPLETED is delivered after credential-protected storage is unlocked.
        // Do not subscribe to USER_PRESENT (every unlock) or LOCKED_BOOT_COMPLETED.
        if (intent.action != Intent.ACTION_BOOT_COMPLETED) return
        if (!context.getSystemService(UserManager::class.java).isUserUnlocked) return
        val mode = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            .getString("flutter.ls_quick_save", "paired")
        if (mode != "on" && mode != "paired") return
        try {
            val service = Intent(context, BootReceiveService::class.java)
            if (Build.VERSION.SDK_INT >= 26) context.startForegroundService(service)
            else context.startService(service)
        } catch (e: Exception) {
            Log.e("LocalSendBoot", "Could not start receiving after unlock", e)
        }
    }
}

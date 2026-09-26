package com.navshield.nav_shield

import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.IBinder

/**
 * Service that monitors app process and task lifecycle.
 * When the app is swiped away from Android Recents or killed,
 * onTaskRemoved is immediately invoked to tear down the
 * floating overlay window and cancel all notifications.
 */
class NavShieldLifecycleService : Service() {
    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        return START_NOT_STICKY
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        super.onTaskRemoved(rootIntent)
        closeOverlayAndCleanUp()
        stopSelf()
    }

    override fun onDestroy() {
        closeOverlayAndCleanUp()
        super.onDestroy()
    }

    private fun closeOverlayAndCleanUp() {
        try {
            val closeIntent = Intent(applicationContext, flutter.overlay.window.flutter_overlay_window.OverlayService::class.java).apply {
                putExtra("IsCloseWindow", true)
            }
            applicationContext.startService(closeIntent)
            applicationContext.stopService(closeIntent)
        } catch (_: Exception) {}

        try {
            val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            nm.cancelAll()
        } catch (_: Exception) {}
    }
}

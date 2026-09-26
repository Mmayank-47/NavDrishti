package com.navshield.nav_shield

import android.content.Intent
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.navshield.nav_shield/overlay_control"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        setupChannel(flutterEngine)
        checkAndHookCachedEngine()
        try {
            startService(Intent(applicationContext, NavShieldLifecycleService::class.java))
        } catch (_: Exception) {}
    }

    override fun onDestroy() {
        try {
            val closeIntent = Intent(applicationContext, flutter.overlay.window.flutter_overlay_window.OverlayService::class.java).apply {
                putExtra("IsCloseWindow", true)
            }
            applicationContext.startService(closeIntent)
            applicationContext.stopService(closeIntent)
        } catch (_: Exception) {}

        try {
            val nm = getSystemService(NOTIFICATION_SERVICE) as android.app.NotificationManager
            nm.cancelAll()
        } catch (_: Exception) {}

        super.onDestroy()
    }

    override fun onResume() {
        super.onResume()
        checkAndHookCachedEngine()
    }

    private fun checkAndHookCachedEngine() {
        val handler = Handler(Looper.getMainLooper())
        handler.postDelayed({ hookOverlayEngine() }, 200)
        handler.postDelayed({ hookOverlayEngine() }, 1000)
    }

    private fun hookOverlayEngine() {
        try {
            val overlayEngine = FlutterEngineCache.getInstance().get("myCachedEngine")
            if (overlayEngine != null) {
                setupChannel(overlayEngine)
            }
        } catch (e: Exception) {
            // Ignore if overlay engine is not yet created
        }
    }

    private fun setupChannel(engine: FlutterEngine) {
        MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "bringToForeground" -> {
                    bringAppToForeground()
                    result.success(true)
                }
                "sendToBackground" -> {
                    moveTaskToBack(true)
                    result.success(true)
                }
                "hookOverlayEngine" -> {
                    hookOverlayEngine()
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun bringAppToForeground() {
        val intent = Intent(applicationContext, MainActivity::class.java).apply {
            action = Intent.ACTION_MAIN
            addCategory(Intent.CATEGORY_LAUNCHER)
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_REORDER_TO_FRONT or Intent.FLAG_ACTIVITY_SINGLE_TOP
        }
        applicationContext.startActivity(intent)
    }
}

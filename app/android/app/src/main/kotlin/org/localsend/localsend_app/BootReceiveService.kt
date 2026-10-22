package org.localsend.localsend_app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.util.Log
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel

/** Only bootstraps the existing receiver; its normal foreground service takes over. */
class BootReceiveService : Service() {
    companion object {
        var engine: FlutterEngine? = null
            private set
        var channel: AndroidReceiveChannel? = null
            private set
        var activityEngine: FlutterEngine? = null

        fun releaseEngine() {
            channel?.close()
            channel = null
            engine?.destroy()
            engine = null
        }
    }

    private val handler = Handler(Looper.getMainLooper())
    private var handedOver = false
    private var ownsEngine = false
    private val timeout = Runnable {
        Log.e("LocalSendBoot", "Receiver initialization timed out")
        stopSelf()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val manager = getSystemService(NotificationManager::class.java)
        val channelId = "localsend_boot"
        if (Build.VERSION.SDK_INT >= 26) {
            manager.createNotificationChannel(NotificationChannel(channelId, "LocalSend-x", NotificationManager.IMPORTANCE_LOW))
        }
        val launch = Intent(this, MainActivity::class.java)
        val pending = PendingIntent.getActivity(this, 0, launch, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        val builder = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(this, channelId) else Notification.Builder(this)
        val notification = builder.setSmallIcon(R.mipmap.ic_launcher_quicktile_foreground)
            .setContentTitle("LocalSend-x").setContentText("正在启动后台接收…")
            .setContentIntent(pending).setOngoing(true).build()
        if (Build.VERSION.SDK_INT >= 29) startForeground(2, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_CONNECTED_DEVICE)
        else startForeground(2, notification)

        if (activityEngine != null || (engine != null && !ownsEngine)) {
            handedOver = true
            stopSelf()
            return START_NOT_STICKY
        }
        if (ownsEngine) return START_NOT_STICKY

        ownsEngine = true
        val receiverEngine = FlutterEngine(applicationContext)
        engine = receiverEngine
        channel = AndroidReceiveChannel(applicationContext).also { it.attach(receiverEngine) }
        MethodChannel(receiverEngine.dartExecutor.binaryMessenger, "org.localsend.localsend_app/boot")
            .setMethodCallHandler { call, result ->
                if (call.method == "hasActivity") {
                    result.success(activityEngine != null)
                    return@setMethodCallHandler
                }
                if (call.method != "ready") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                handedOver = call.argument<Boolean>("success") == true
                Log.i("LocalSendBoot", "Receiver ready: $handedOver")
                result.success(null)
                handler.post { stopSelf() }
            }
        handler.postDelayed(timeout, 60_000)
        receiverEngine.dartExecutor.executeDartEntrypoint(DartExecutor.DartEntrypoint.createDefault(), listOf("--android-boot"))
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        handler.removeCallbacks(timeout)
        if (ownsEngine && !handedOver) releaseEngine()
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null
}

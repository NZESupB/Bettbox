package com.appshub.kitonybox.services

import android.annotation.SuppressLint
import android.app.Service
import android.content.Intent
import android.os.Binder
import android.os.Build
import android.os.IBinder
import android.text.SpannableString
import android.text.Spanned
import android.text.style.RelativeSizeSpan
import androidx.core.app.NotificationCompat
import com.appshub.kitonybox.GlobalState
import com.appshub.kitonybox.R
import com.appshub.kitonybox.models.VpnOptions

class KitonyBoxService : Service(), BaseServiceInterface {

    @Volatile
    private var cachedBuilder: NotificationCompat.Builder? = null
    private val binder = LocalBinder()
    @Volatile
    private var hasStartedForeground = false

    private val fairMemoryHelper = FairMemoryHelper("KitonyBoxService")

    override fun onCreate() {
        super.onCreate()
        fairMemoryHelper.register(
            context = this,
            onTrim = { GlobalState.getCurrentVPNPlugin()?.requestGc() },
            onKill = { /* system will kill process; service has no extra state to save */ }
        )
    }

    inner class LocalBinder : Binder() {
        fun getService() = this@KitonyBoxService
    }

    override suspend fun start(options: VpnOptions) = 0

    override fun stop() {
        hasStartedForeground = false

        runCatching {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                stopForeground(STOP_FOREGROUND_REMOVE)
            } else {
                stopForeground(true)
            }
        }.onFailure { android.util.Log.e("KitonyBoxService", "Failed to stop foreground: ${it.message}") }

        runCatching {
            getSystemService(android.app.NotificationManager::class.java)
                ?.cancel(GlobalState.NOTIFICATION_ID)
        }.onFailure { android.util.Log.e("KitonyBoxService", "Failed to cancel notification: ${it.message}") }

        stopSelf()
    }

    fun resetNotificationBuilder() {
        cachedBuilder = null
    }

    private suspend fun notificationBuilder() =
        cachedBuilder ?: createKitonyBoxNotificationBuilder().also { cachedBuilder = it }

    @SuppressLint("ForegroundServiceType")
    override suspend fun startForeground() {
        ensureNotificationChannel()
        val title: String
        val content: String
        if (GlobalState.isSmartStopped) {
            title = getString(R.string.core_suspended)
            content = getString(R.string.smart_auto_stop_service_running)
        } else {
            title = getString(R.string.core_connected)
            content = getString(R.string.service_running)
        }

        val builder = notificationBuilder()
        val notification = builder
            .setContentTitle(title)
            .setContentText(content)
            .setStyle(null)
            .setTicker("$title: $content")
            .build()

        if (!hasStartedForeground) {
            this.startForeground(notification, useSpecialType = !GlobalState.isSmartStopped)
            hasStartedForeground = true
        } else {
            getSystemService(android.app.NotificationManager::class.java)?.notify(GlobalState.NOTIFICATION_ID, notification)
        }
    }

    override fun onTrimMemory(level: Int) {
        super.onTrimMemory(level)
        if (level == 10 || level == 15 || level >= 40) {
            GlobalState.getCurrentVPNPlugin()?.requestGc()
        }
    }

    override fun onBind(intent: Intent): IBinder = binder

    override fun onDestroy() {
        stop()
        fairMemoryHelper.unregister(this)
        super.onDestroy()
    }
}

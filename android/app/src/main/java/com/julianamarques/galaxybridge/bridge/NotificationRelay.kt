package com.julianamarques.galaxybridge.bridge

import android.app.Notification
import android.app.NotificationManager
import android.app.RemoteInput
import android.content.Context
import android.content.Intent
import android.content.pm.ApplicationInfo
import android.graphics.Bitmap
import android.graphics.Canvas
import android.os.Build
import android.os.Bundle
import android.service.notification.NotificationListenerService.Ranking
import android.service.notification.StatusBarNotification
import android.util.Base64
import com.julianamarques.galaxybridge.protocol.PhoneNotification
import java.io.ByteArrayOutputStream
import java.util.concurrent.ConcurrentHashMap

object NotificationRelay {
    @Volatile var onPosted: ((PhoneNotification) -> Unit)? = null
    @Volatile var onRemoved: ((String) -> Unit)? = null

    @Volatile var muted: Set<String> = emptySet()

    private val mirrored = ConcurrentHashMap<String, StatusBarNotification>()
    private val apps = ConcurrentHashMap<String, ApplicationInfo>()
    private const val ICON_SIZE = 96
    private const val MAX_TEXT = 1_000
    private const val SKIPPED_FLAGS = Notification.FLAG_ONGOING_EVENT or Notification.FLAG_FOREGROUND_SERVICE or
        Notification.FLAG_GROUP_SUMMARY or Notification.FLAG_LOCAL_ONLY

    val activeKeys: List<String> get() = mirrored.keys.toList()

    fun posted(context: Context, notification: StatusBarNotification, ranking: Ranking?, announce: Boolean) {
        val described = describe(context, notification, ranking)
        if (described == null) return removed(notification.key)
        val isUpdate = mirrored.put(notification.key, notification) != null
        if (!announce) return
        val alertOnce = notification.notification.flags and Notification.FLAG_ONLY_ALERT_ONCE != 0
        onPosted?.invoke(described.copy(silent = isUpdate && alertOnce))
    }

    fun removed(key: String) {
        if (mirrored.remove(key) != null) onRemoved?.invoke(key)
    }

    fun act(context: Context, key: String, index: Int, reply: String?): Boolean {
        val action = mirrored[key]?.notification?.actions?.getOrNull(index) ?: return false
        return runCatching {
            if (reply == null) {
                action.actionIntent.send()
            } else {
                val inputs = action.remoteInputs.orEmpty().filter { it.allowFreeFormInput }.toTypedArray()
                if (inputs.isEmpty()) return false
                val results = Bundle().apply { inputs.forEach { putCharSequence(it.resultKey, reply) } }
                val intent = Intent().also { RemoteInput.addResultsToIntent(inputs, it, results) }
                action.actionIntent.send(context, 0, intent)
            }
        }.isSuccess
    }

    private fun describe(context: Context, notification: StatusBarNotification, ranking: Ranking?): PhoneNotification? {
        val content = notification.notification
        if (notification.packageName == context.packageName || notification.packageName in muted) return null
        if (content.flags and SKIPPED_FLAGS != 0 || !notification.isClearable) return null
        if (content.category == Notification.CATEGORY_CALL) return null
        if (ranking != null && ranking.importance < NotificationManager.IMPORTANCE_DEFAULT) return null
        val extras = content.extras
        val title = (extras.getCharSequence(Notification.EXTRA_CONVERSATION_TITLE) ?: extras.getCharSequence(Notification.EXTRA_TITLE))?.toString()
        val text = (extras.getCharSequence(Notification.EXTRA_BIG_TEXT) ?: extras.getCharSequence(Notification.EXTRA_TEXT))?.toString()?.take(MAX_TEXT)
        if (title.isNullOrBlank() && text.isNullOrBlank()) return null
        val actions = content.actions.orEmpty().mapIndexedNotNull { index, action ->
            val label = action.title?.toString() ?: return@mapIndexedNotNull null
            PhoneNotification.Action(index, label, action.remoteInputs.orEmpty().any { it.allowFreeFormInput })
        }
        return PhoneNotification(notification.key, notification.packageName, appName(context, notification), title, text, notification.postTime, actions, silent = false)
    }

    fun icon(context: Context, app: String): String? = runCatching {
        val info = apps[app] ?: context.packageManager.getApplicationInfo(app, 0)
        val bitmap = Bitmap.createBitmap(ICON_SIZE, ICON_SIZE, Bitmap.Config.ARGB_8888)
        info.loadIcon(context.packageManager).apply {
            setBounds(0, 0, ICON_SIZE, ICON_SIZE)
            draw(Canvas(bitmap))
        }
        val png = ByteArrayOutputStream().also { bitmap.compress(Bitmap.CompressFormat.PNG, 100, it) }.toByteArray()
        Base64.encodeToString(png, Base64.NO_WRAP)
    }.getOrNull()

    private fun appInfo(context: Context, notification: StatusBarNotification): ApplicationInfo? {
        val extras = notification.notification.extras
        val attached = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            extras.getParcelable(EXTRA_APP_INFO, ApplicationInfo::class.java)
        } else {
            @Suppress("DEPRECATION")
            extras.getParcelable<ApplicationInfo>(EXTRA_APP_INFO)
        }
        return (attached ?: runCatching { context.packageManager.getApplicationInfo(notification.packageName, 0) }.getOrNull())
            ?.also { apps[notification.packageName] = it }
    }

    private fun appName(context: Context, notification: StatusBarNotification): String =
        appInfo(context, notification)?.loadLabel(context.packageManager)?.toString() ?: notification.packageName

    private const val EXTRA_APP_INFO = "android.appInfo"
}

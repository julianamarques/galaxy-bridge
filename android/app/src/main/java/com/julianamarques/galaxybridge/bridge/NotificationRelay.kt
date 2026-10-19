package com.julianamarques.galaxybridge.bridge

import android.app.Notification
import android.app.NotificationManager
import android.app.RemoteInput
import android.content.Context
import android.content.Intent
import android.content.pm.ApplicationInfo
import android.graphics.Bitmap
import android.graphics.Canvas
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

    private val mirrored = ConcurrentHashMap<String, List<Notification.Action>>()
    private val appNames = ConcurrentHashMap<String, String>()
    private val sentIcons = ConcurrentHashMap.newKeySet<String>()
    private const val MAX_TEXT = 1_000
    private const val ICON_SIZE = 96
    private const val EXTRA_APP_INFO = "android.appInfo"
    private const val SKIPPED_FLAGS = Notification.FLAG_ONGOING_EVENT or Notification.FLAG_FOREGROUND_SERVICE or
        Notification.FLAG_GROUP_SUMMARY or Notification.FLAG_LOCAL_ONLY

    val activeKeys: List<String> get() = mirrored.keys.toList()

    fun connected() {
        sentIcons.clear()
    }

    fun forgetAll() {
        mirrored.clear()
    }

    fun posted(context: Context, notification: StatusBarNotification, ranking: Ranking?, announce: Boolean) {
        if (!isRelayed(context, notification, ranking)) return removed(notification.key)
        val isUpdate = mirrored.put(notification.key, notification.notification.actions.orEmpty().toList()) != null
        val send = onPosted ?: return
        if (!announce) return
        val alertOnce = notification.notification.flags and Notification.FLAG_ONLY_ALERT_ONCE != 0
        describe(context, notification, silent = isUpdate && alertOnce)?.let(send)
    }

    fun removed(key: String) {
        if (mirrored.remove(key) != null) onRemoved?.invoke(key)
    }

    fun act(context: Context, key: String, index: Int, reply: String?): Boolean {
        val action = mirrored[key]?.getOrNull(index) ?: return false
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

    private fun isRelayed(context: Context, notification: StatusBarNotification, ranking: Ranking?): Boolean {
        val content = notification.notification
        return notification.packageName != context.packageName &&
            notification.packageName !in muted &&
            content.flags and SKIPPED_FLAGS == 0 &&
            notification.isClearable &&
            content.category != Notification.CATEGORY_CALL &&
            (ranking == null || ranking.importance >= NotificationManager.IMPORTANCE_DEFAULT)
    }

    private fun describe(context: Context, notification: StatusBarNotification, silent: Boolean): PhoneNotification? {
        val content = notification.notification
        val extras = content.extras
        val title = (extras.getCharSequence(Notification.EXTRA_CONVERSATION_TITLE) ?: extras.getCharSequence(Notification.EXTRA_TITLE))?.toString()
        val text = (extras.getCharSequence(Notification.EXTRA_BIG_TEXT) ?: extras.getCharSequence(Notification.EXTRA_TEXT))?.toString()?.take(MAX_TEXT)
        if (title.isNullOrBlank() && text.isNullOrBlank()) return null
        val actions = content.actions.orEmpty().mapIndexedNotNull { index, action ->
            val label = action.title?.toString() ?: return@mapIndexedNotNull null
            PhoneNotification.Action(index, label, action.remoteInputs.orEmpty().any { it.allowFreeFormInput })
        }
        val app = notification.packageName
        val info by lazy { extras.parcelable<ApplicationInfo>(EXTRA_APP_INFO) ?: runCatching { context.packageManager.getApplicationInfo(app, 0) }.getOrNull() }
        val name = appNames.getOrPut(app) { info?.loadLabel(context.packageManager)?.toString() ?: app }
        val icon = if (sentIcons.add(app)) info?.let { icon(context, it) } else null
        return PhoneNotification(notification.key, app, name, title, text, notification.postTime, actions, silent, icon)
    }

    private fun icon(context: Context, info: ApplicationInfo): String? = runCatching {
        val bitmap = Bitmap.createBitmap(ICON_SIZE, ICON_SIZE, Bitmap.Config.ARGB_8888)
        info.loadIcon(context.packageManager).apply {
            setBounds(0, 0, ICON_SIZE, ICON_SIZE)
            draw(Canvas(bitmap))
        }
        val png = ByteArrayOutputStream().also { bitmap.compress(Bitmap.CompressFormat.PNG, 100, it) }.toByteArray()
        Base64.encodeToString(png, Base64.NO_WRAP)
    }.getOrNull()
}

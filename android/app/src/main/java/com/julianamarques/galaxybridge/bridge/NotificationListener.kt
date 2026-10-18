package com.julianamarques.galaxybridge.bridge

import android.app.Notification
import android.app.Person
import android.net.Uri
import android.os.Build
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import android.telecom.TelecomManager
import com.julianamarques.galaxybridge.Diagnostics

class NotificationListener : NotificationListenerService() {
    override fun onListenerConnected() {
        runCatching { activeNotifications }.getOrNull()?.forEach(::read)
    }

    override fun onNotificationPosted(notification: StatusBarNotification) = read(notification)

    private fun read(notification: StatusBarNotification) {
        if (!isCallNotification(notification)) return
        val extras = notification.notification.extras
        val person = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            extras.getParcelable(Notification.EXTRA_CALL_PERSON, Person::class.java)
        } else {
            @Suppress("DEPRECATION")
            extras.getParcelable<Person>(Notification.EXTRA_CALL_PERSON)
        }
        val title = extras.getCharSequence(Notification.EXTRA_TITLE)?.toString()
        val text = extras.getCharSequence(Notification.EXTRA_TEXT)?.toString()
        val number = person?.uri?.let(Uri::parse)?.takeIf { it.scheme == "tel" }?.schemeSpecificPart
        val name = (person?.name?.toString() ?: title)?.takeIf { it.any(Char::isLetter) }
        Diagnostics.record(
            this,
            "Aviso de ligação: nome=${name != null}, número=${number != null}, texto=$text, tipo=${extras.getInt(Notification.EXTRA_CALL_TYPE)}",
        )
        val voicemail = extras.getBoolean(VOICEMAIL_FLAG) || text in VOICEMAIL_TEXTS
        CallTracker.callerChanged(name, number, voicemail)
    }

    private fun isCallNotification(notification: StatusBarNotification): Boolean {
        if (notification.notification.category != Notification.CATEGORY_CALL) return false
        val dialer = getSystemService(TelecomManager::class.java).defaultDialerPackage
        return notification.packageName == dialer || notification.packageName in CALL_UI_PACKAGES
    }

    companion object {
        private const val VOICEMAIL_FLAG = "android.ongoingActivityNoti.nowbarCallChronometerWithText"
        private val VOICEMAIL_TEXTS = setOf("Correio de voz direto")
        private val CALL_UI_PACKAGES = setOf(
            "com.samsung.android.incallui",
            "com.google.android.dialer",
            "com.android.incallui",
            "com.android.dialer",
        )
    }
}

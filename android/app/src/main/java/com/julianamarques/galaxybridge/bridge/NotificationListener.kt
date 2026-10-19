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
        instance = this
        runCatching { activeNotifications }.getOrNull()?.forEach {
            read(it)
            NotificationRelay.posted(this, it, ranking(it), announce = false)
        }
    }

    override fun onListenerDisconnected() {
        instance = null
    }

    override fun onNotificationPosted(notification: StatusBarNotification, rankingMap: RankingMap?) {
        read(notification)
        NotificationRelay.posted(this, notification, rankingMap?.let { ranking(notification, it) }, announce = true)
    }

    override fun onNotificationRemoved(notification: StatusBarNotification) {
        NotificationRelay.removed(notification.key)
    }

    private fun ranking(notification: StatusBarNotification, map: RankingMap? = runCatching { currentRanking }.getOrNull()): Ranking? {
        val ranking = Ranking()
        return if (map?.getRanking(notification.key, ranking) == true) ranking else null
    }

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
        val contact = number?.let(::contactFor)
        CallTracker.callerChanged(name ?: contact?.name, number, contact?.key, voicemail)
    }

    private var lastLookup: Pair<String, PhoneContacts.Match?>? = null

    private fun contactFor(number: String): PhoneContacts.Match? {
        lastLookup?.takeIf { it.first == number }?.let { return it.second }
        return PhoneContacts.lookup(this, number).also { lastLookup = number to it }
    }

    private fun isCallNotification(notification: StatusBarNotification): Boolean {
        if (notification.notification.category != Notification.CATEGORY_CALL) return false
        val dialer = getSystemService(TelecomManager::class.java).defaultDialerPackage
        return notification.packageName == dialer || notification.packageName in CALL_UI_PACKAGES
    }

    companion object {
        @Volatile private var instance: NotificationListener? = null

        fun dismiss(key: String) {
            instance?.let { runCatching { it.cancelNotification(key) } }
        }

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

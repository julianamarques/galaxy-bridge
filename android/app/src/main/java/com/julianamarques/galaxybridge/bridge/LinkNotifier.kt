package com.julianamarques.galaxybridge.bridge

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.net.Uri
import com.julianamarques.galaxybridge.R

class LinkNotifier(private val context: Context) {
    private val notifications = context.getSystemService(NotificationManager::class.java)

    init {
        notifications.createNotificationChannel(
            NotificationChannel(CHANNEL_ID, context.getString(R.string.channel_links), NotificationManager.IMPORTANCE_HIGH),
        )
    }

    fun show(url: String) {
        val uri = Uri.parse(url)
        if (uri.scheme?.lowercase() !in SCHEMES) return
        val id = url.hashCode()
        val open = Intent(Intent.ACTION_VIEW, uri).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        val notification = Notification.Builder(context, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_notification)
            .setContentTitle(context.getString(R.string.link_title))
            .setContentText(url)
            .setStyle(Notification.BigTextStyle().bigText(url))
            .setCategory(Notification.CATEGORY_RECOMMENDATION)
            .setContentIntent(PendingIntent.getActivity(context, id, open, PendingIntent.FLAG_IMMUTABLE))
            .setAutoCancel(true)
            .build()
        notifications.notify(TAG, id, notification)
    }

    companion object {
        private const val CHANNEL_ID = "links"
        private const val TAG = "link"
        private val SCHEMES = setOf("http", "https")
    }
}

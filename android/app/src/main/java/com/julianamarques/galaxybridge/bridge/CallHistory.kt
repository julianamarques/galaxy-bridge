package com.julianamarques.galaxybridge.bridge

import android.Manifest
import android.content.Context
import android.provider.CallLog
import com.julianamarques.galaxybridge.Permission
import com.julianamarques.galaxybridge.protocol.RecentCall

object CallHistory {
    private const val ATTEMPTS = 10
    private const val RETRY_MS = 300L
    private const val CLOCK_SLACK_MS = 5_000L
    private const val RECENT_LIMIT = 8

    fun canRead(context: Context): Boolean = Permission.has(context, Manifest.permission.READ_CALL_LOG)

    fun wasDeclined(context: Context, since: Long): Boolean {
        if (!canRead(context)) return false
        repeat(ATTEMPTS) {
            lastIncomingType(context, since)?.let { return it == CallLog.Calls.REJECTED_TYPE }
            Thread.sleep(RETRY_MS)
        }
        return false
    }

    fun recent(context: Context): List<RecentCall>? {
        if (!canRead(context)) return null
        return runCatching {
            val uri = CallLog.Calls.CONTENT_URI.buildUpon()
                .appendQueryParameter(CallLog.Calls.LIMIT_PARAM_KEY, RECENT_LIMIT.toString())
                .build()
            val projection = arrayOf(CallLog.Calls.NUMBER, CallLog.Calls.CACHED_NAME, CallLog.Calls.TYPE, CallLog.Calls.DATE, CallLog.Calls.DURATION)
            context.contentResolver.query(uri, projection, null, null, "${CallLog.Calls.DATE} DESC")?.use { cursor ->
                buildList {
                    while (cursor.moveToNext()) {
                        val kind = kind(cursor.getInt(2)) ?: continue
                        val number = cursor.getString(0)?.takeIf { it.isNotBlank() }
                        val contact = number?.let { PhoneContacts.lookup(context, it) }
                        add(
                            RecentCall(
                                number = number,
                                name = contact?.name ?: cursor.getString(1)?.takeIf { it.isNotBlank() },
                                contact = contact?.key,
                                kind = kind,
                                time = cursor.getLong(3),
                                duration = cursor.getInt(4),
                            ),
                        )
                    }
                }
            }
        }.getOrNull()
    }

    private fun kind(type: Int): String? = when (type) {
        CallLog.Calls.INCOMING_TYPE, CallLog.Calls.ANSWERED_EXTERNALLY_TYPE -> RecentCall.INCOMING
        CallLog.Calls.OUTGOING_TYPE -> RecentCall.OUTGOING
        CallLog.Calls.MISSED_TYPE, CallLog.Calls.VOICEMAIL_TYPE -> RecentCall.MISSED
        CallLog.Calls.REJECTED_TYPE, CallLog.Calls.BLOCKED_TYPE -> RecentCall.DECLINED
        else -> null
    }

    private fun lastIncomingType(context: Context, since: Long): Int? = runCatching {
        context.contentResolver.query(
            CallLog.Calls.CONTENT_URI,
            arrayOf(CallLog.Calls.TYPE),
            "${CallLog.Calls.DATE} >= ? AND ${CallLog.Calls.TYPE} != ?",
            arrayOf((since - CLOCK_SLACK_MS).toString(), CallLog.Calls.OUTGOING_TYPE.toString()),
            "${CallLog.Calls.DATE} DESC",
        )?.use { if (it.moveToFirst()) it.getInt(0) else null }
    }.getOrNull()
}

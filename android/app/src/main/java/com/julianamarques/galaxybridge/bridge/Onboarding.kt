package com.julianamarques.galaxybridge.bridge

import android.content.Context
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow

object Onboarding {
    private const val PREFERENCES = "onboarding"
    private const val DONE = "done"
    private var state: MutableStateFlow<Boolean>? = null

    fun done(context: Context): StateFlow<Boolean> =
        state ?: MutableStateFlow(preferences(context).getBoolean(DONE, false)).also { state = it }

    fun finish(context: Context) = set(context, true)

    fun replay(context: Context) = set(context, false)

    private fun set(context: Context, value: Boolean) {
        preferences(context).edit().putBoolean(DONE, value).apply()
        (done(context) as MutableStateFlow).value = value
    }

    private fun preferences(context: Context) = context.applicationContext.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)
}

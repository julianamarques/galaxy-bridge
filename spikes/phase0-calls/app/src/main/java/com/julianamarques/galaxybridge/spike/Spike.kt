package com.julianamarques.galaxybridge.spike

import android.content.Context
import android.util.Log

/** Log e o método escolhido para a próxima chamada. */
object Spike {
    private const val TAG = "GBSpike"
    private const val PREFS = "spike"
    private const val KEY_MODE = "mode"

    enum class Mode { OBSERVE, ANSWER_TELECOM, DECLINE_TELECOM, ANSWER_NOTIFICATION, DECLINE_NOTIFICATION }

    fun log(message: String) {
        Log.i(TAG, message)
    }

    fun log(message: String, error: Throwable) {
        Log.e(TAG, "$message: ${error.javaClass.simpleName}: ${error.message}", error)
    }

    fun mode(context: Context): Mode {
        val name = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getString(KEY_MODE, null)
        return Mode.entries.firstOrNull { it.name == name } ?: Mode.OBSERVE
    }

    /** Ordem do modo `sequence`: cada ligação testa um método, e o app avança quando ela termina. */
    private val sequence = listOf(Mode.ANSWER_TELECOM, Mode.DECLINE_TELECOM, Mode.ANSWER_NOTIFICATION, Mode.DECLINE_NOTIFICATION)
    private const val KEY_SEQUENCE = "sequence"

    fun startSequence(context: Context) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().putBoolean(KEY_SEQUENCE, true).apply()
        setMode(context, sequence.first())
    }

    /** Depois de uma ligação, passa para o próximo método da sequência (ou para OBSERVE no fim). */
    fun advance(context: Context) {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        if (!prefs.getBoolean(KEY_SEQUENCE, false)) return
        val next = sequence.getOrNull(sequence.indexOf(mode(context)) + 1)
        if (next == null) {
            prefs.edit().putBoolean(KEY_SEQUENCE, false).apply()
            setMode(context, Mode.OBSERVE)
            log("Sequência concluída")
        } else {
            setMode(context, next)
            log("Próxima ligação: $next")
        }
    }

    fun setMode(context: Context, mode: Mode) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().putString(KEY_MODE, mode.name).apply()
        log("Modo: $mode")
    }
}

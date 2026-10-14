package com.julianamarques.galaxybridge

import android.Manifest
import android.annotation.SuppressLint
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings

/** As permissões que o app pede, na ordem em que aparecem na tela. */
enum class Permission(val title: String, val reason: String) {
    Notifications("Notificações", "Mostra quando o Galaxy está conectado ao Mac."),
    Calls("Ligações", "Para fazer as ligações que você pede no Mac."),
    Battery("Bateria sem restrições", "Para a conexão continuar com a tela apagada.");

    /** A permissão do Android a pedir, ou `null` para a bateria, que abre uma tela do sistema. */
    val manifestPermission: String?
        get() = when (this) {
            Notifications -> Manifest.permission.POST_NOTIFICATIONS
            Calls -> Manifest.permission.CALL_PHONE
            Battery -> null
        }

    fun isGranted(context: Context): Boolean = when (this) {
        Battery -> context.getSystemService(PowerManager::class.java).isIgnoringBatteryOptimizations(context.packageName)
        else -> context.checkSelfPermission(manifestPermission!!) == PackageManager.PERMISSION_GRANTED
    }

    companion object {
        fun needed(): List<Permission> =
            if (Build.VERSION.SDK_INT >= 33) entries else entries.filter { it != Notifications }

        fun missing(context: Context): List<Permission> = needed().filter { !it.isGranted(context) }

        /** O pedido do sistema para deixar a bateria do app sem restrições (ele vai para a lista de exceções do Doze). */
        @SuppressLint("BatteryLife")
        fun batteryIntent(context: Context) =
            Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS, Uri.parse("package:${context.packageName}"))
    }
}

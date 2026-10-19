package com.julianamarques.galaxybridge

import android.Manifest
import android.annotation.SuppressLint
import android.app.NotificationManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import com.julianamarques.galaxybridge.bridge.NotificationListener

enum class Permission(val title: String, val reason: String) {
    Notifications("Notificações", "Mostra quando o Galaxy está conectado ao Mac."),
    Calls("Ligações", "Para fazer, atender e recusar ligações pelo Mac."),
    CallerName("Nome de quem liga", "Lê o aviso de ligação do Galaxy para mostrar no Mac quem está ligando."),
    Contacts("Contatos", "Para buscar contatos e mostrar as fotos deles no Mac. Os contatos ficam no Galaxy."),
    Battery("Bateria sem restrições", "Para a conexão continuar com a tela apagada.");

    val manifestPermissions: List<String>
        get() = when (this) {
            Notifications -> listOf(Manifest.permission.POST_NOTIFICATIONS)
            Calls -> listOf(Manifest.permission.CALL_PHONE, Manifest.permission.READ_PHONE_STATE, Manifest.permission.ANSWER_PHONE_CALLS)
            Contacts -> listOf(Manifest.permission.READ_CONTACTS)
            CallerName, Battery -> emptyList()
        }

    fun isGranted(context: Context): Boolean = when (this) {
        Battery -> context.getSystemService(PowerManager::class.java).isIgnoringBatteryOptimizations(context.packageName)
        CallerName -> context.getSystemService(NotificationManager::class.java)
            .isNotificationListenerAccessGranted(ComponentName(context, NotificationListener::class.java))
        else -> manifestPermissions.all { has(context, it) }
    }

    @SuppressLint("BatteryLife")
    fun settingsIntent(context: Context): Intent? = when (this) {
        Battery -> Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS, Uri.parse("package:${context.packageName}"))
        CallerName -> Intent(Settings.ACTION_NOTIFICATION_LISTENER_DETAIL_SETTINGS).putExtra(
            Settings.EXTRA_NOTIFICATION_LISTENER_COMPONENT_NAME,
            ComponentName(context, NotificationListener::class.java).flattenToString(),
        )
        else -> null
    }

    companion object {
        fun needed(): List<Permission> =
            if (Build.VERSION.SDK_INT >= 33) entries else entries.filter { it != Notifications }

        fun missing(context: Context): List<Permission> = needed().filter { !it.isGranted(context) }

        fun has(context: Context, permission: String): Boolean =
            context.checkSelfPermission(permission) == PackageManager.PERMISSION_GRANTED
    }
}

package com.julianamarques.galaxybridge

import android.Manifest
import android.annotation.SuppressLint
import androidx.annotation.StringRes
import android.app.NotificationManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.os.PowerManager
import android.provider.Settings
import com.julianamarques.galaxybridge.bridge.NotificationListener
import com.julianamarques.galaxybridge.mirror.MirrorControlService

enum class Permission(@StringRes val title: Int, @StringRes val reason: Int) {
    Notifications(R.string.permission_notifications, R.string.permission_notifications_reason),
    Calls(R.string.permission_calls, R.string.permission_calls_reason),
    CallerName(R.string.permission_caller_name, R.string.permission_caller_name_reason),
    Contacts(R.string.permission_contacts, R.string.permission_contacts_reason),
    Photos(R.string.permission_photos, R.string.permission_photos_reason),
    AllFiles(R.string.permission_all_files, R.string.permission_all_files_reason),
    MirrorControl(R.string.permission_mirror_control, R.string.permission_mirror_control_reason),
    Battery(R.string.permission_battery, R.string.permission_battery_reason);

    val manifestPermissions: List<String>
        get() = when (this) {
            Notifications -> listOf(Manifest.permission.POST_NOTIFICATIONS)
            Calls -> listOf(
                Manifest.permission.CALL_PHONE,
                Manifest.permission.READ_PHONE_STATE,
                Manifest.permission.ANSWER_PHONE_CALLS,
                Manifest.permission.READ_CALL_LOG,
            )
            Contacts -> listOf(Manifest.permission.READ_CONTACTS)
            Photos -> listOf(
                if (Build.VERSION.SDK_INT >= 33) Manifest.permission.READ_MEDIA_IMAGES else Manifest.permission.READ_EXTERNAL_STORAGE,
            )
            CallerName, Battery, AllFiles, MirrorControl -> emptyList()
        }

    fun isGranted(context: Context): Boolean = when (this) {
        Battery -> context.getSystemService(PowerManager::class.java).isIgnoringBatteryOptimizations(context.packageName)
        AllFiles -> Environment.isExternalStorageManager()
        MirrorControl -> MirrorControlService.isEnabled(context)
        CallerName -> context.getSystemService(NotificationManager::class.java)
            .isNotificationListenerAccessGranted(ComponentName(context, NotificationListener::class.java))
        else -> manifestPermissions.all { has(context, it) }
    }

    @SuppressLint("BatteryLife")
    fun settingsIntent(context: Context): Intent? = when (this) {
        Battery -> Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS, Uri.parse("package:${context.packageName}"))
        AllFiles -> Intent(Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION, Uri.parse("package:${context.packageName}"))
        MirrorControl -> Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS)
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

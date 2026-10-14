package com.julianamarques.galaxybridge.spike

import android.Manifest
import android.app.Activity
import android.content.ComponentName
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Bundle
import android.provider.Settings
import android.widget.Button
import android.widget.LinearLayout
import android.widget.TextView

/** Só mostra o que já foi concedido. As permissões são dadas pelo `grant.sh`, via adb. */
class MainActivity : Activity() {
    override fun onResume() {
        super.onResume()
        val permissions = listOf(
            Manifest.permission.READ_PHONE_STATE,
            Manifest.permission.READ_CALL_LOG,
            Manifest.permission.ANSWER_PHONE_CALLS,
            Manifest.permission.CALL_PHONE,
            Manifest.permission.READ_CONTACTS,
        ).joinToString("\n") { permission ->
            val granted = checkSelfPermission(permission) == PackageManager.PERMISSION_GRANTED
            "${if (granted) "✓" else "✗"} ${permission.substringAfterLast('.')}"
        }
        val listener = ComponentName(this, CallListenerService::class.java).flattenToString()
        val enabled = Settings.Secure.getString(contentResolver, "enabled_notification_listeners")
            ?.contains(listener) == true
        val status = TextView(this).apply {
            textSize = 16f
            text = "Galaxy Bridge — teste de chamadas\n\n$permissions\n" +
                "${if (enabled) "✓" else "✗"} Acesso às notificações\n\n" +
                "Modo: ${Spike.mode(this@MainActivity)}"
        }
        // Abre a tela do sistema só para este app, como o app real vai fazer na configuração.
        val button = Button(this).apply {
            text = "Ativar acesso às notificações"
            isEnabled = !enabled
            setOnClickListener {
                startActivity(
                    Intent(Settings.ACTION_NOTIFICATION_LISTENER_DETAIL_SETTINGS)
                        .putExtra(Settings.EXTRA_NOTIFICATION_LISTENER_COMPONENT_NAME, listener)
                )
            }
        }
        setContentView(LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(48, 160, 48, 48)
            addView(status)
            addView(button)
        })
    }
}

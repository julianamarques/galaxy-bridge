package com.julianamarques.galaxybridge.spike.background

import android.app.Activity
import android.content.Intent
import android.os.Bundle

/** Inicia o serviço em primeiro plano (só é permitido com o app em primeiro plano) e fecha. */
class MainActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        startForegroundService(Intent(this, HeartbeatService::class.java))
        finish()
    }
}

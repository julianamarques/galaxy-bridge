package com.julianamarques.galaxybridge.spike.background

import android.app.Activity
import android.content.Intent
import android.os.Bundle

class MainActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        startForegroundService(Intent(this, HeartbeatService::class.java))
        finish()
    }
}

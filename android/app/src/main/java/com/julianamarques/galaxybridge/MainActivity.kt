package com.julianamarques.galaxybridge

import android.content.Intent
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import com.julianamarques.galaxybridge.bridge.BridgeService
import com.julianamarques.galaxybridge.bridge.BridgeState
import com.julianamarques.galaxybridge.bridge.Identity
import com.julianamarques.galaxybridge.bridge.Onboarding
import com.julianamarques.galaxybridge.bridge.PairingStore
import com.julianamarques.galaxybridge.protocol.PairingLink
import com.julianamarques.galaxybridge.ui.GalaxyBridgeTheme
import com.julianamarques.galaxybridge.ui.HomeScreen
import com.julianamarques.galaxybridge.ui.OnboardingScreen
import com.julianamarques.galaxybridge.ui.PairingController
import com.julianamarques.galaxybridge.ui.SetupScreen
import kotlin.concurrent.thread

class MainActivity : ComponentActivity() {
    private var resumes by mutableIntStateOf(0)
    private var pendingLink by mutableStateOf<PairingLink?>(null)

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        thread { Identity.ensure() }
        setContent {
            GalaxyBridgeTheme {
                val scope = rememberCoroutineScope()
                val controller = remember { PairingController(this, scope) }
                LaunchedEffect(pendingLink) {
                    pendingLink?.let(controller::pair)
                    pendingLink = null
                }
                val mac by PairingStore.mac(this).collectAsState()
                val connection by BridgeState.connection.collectAsState()
                val toured by Onboarding.done(this).collectAsState()
                val current = mac
                when {
                    current == null -> SetupScreen(controller, resumes)
                    !toured -> OnboardingScreen(resumes)
                    else -> HomeScreen(current, connection, resumes)
                }
            }
        }
        handle(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handle(intent)
    }

    override fun onResume() {
        super.onResume()
        resumes++
        BridgeService.start(this)
    }

    private fun handle(intent: Intent?) {
        val link = intent?.dataString?.let(PairingLink::parse) ?: return
        if (PairingStore.current(this) != null) return
        pendingLink = link
    }
}

package com.julianamarques.galaxybridge.ui

import androidx.annotation.StringRes
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInHorizontally
import androidx.compose.animation.slideOutHorizontally
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.BatteryChargingFull
import androidx.compose.material.icons.rounded.Call
import androidx.compose.material.icons.rounded.CheckCircle
import androidx.compose.material.icons.rounded.Contacts
import androidx.compose.material.icons.rounded.Headphones
import androidx.compose.material.icons.rounded.Notifications
import androidx.compose.material.icons.rounded.PhotoLibrary
import androidx.compose.material.icons.rounded.ScreenShare
import androidx.compose.material3.Button
import androidx.compose.material3.ExperimentalMaterial3ExpressiveApi
import androidx.compose.material3.Icon
import androidx.compose.material3.LinearWavyProgressIndicator
import androidx.compose.material3.MaterialShapes
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.toShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.julianamarques.galaxybridge.Permission
import com.julianamarques.galaxybridge.R
import com.julianamarques.galaxybridge.bridge.Onboarding

private data class TourPage(val icon: ImageVector?, @StringRes val title: Int, @StringRes val text: Int, val permissions: List<Permission> = emptyList())

private val TOUR = listOf(
    TourPage(null, R.string.tour_welcome_title, R.string.tour_welcome_text),
    TourPage(Icons.Rounded.Call, R.string.tour_calls_title, R.string.tour_calls_text, listOf(Permission.Calls)),
    TourPage(Icons.Rounded.Notifications, R.string.tour_notifications_title, R.string.tour_notifications_text, listOf(Permission.Notifications, Permission.CallerName)),
    TourPage(Icons.Rounded.Contacts, R.string.tour_contacts_title, R.string.tour_contacts_text, listOf(Permission.Contacts)),
    TourPage(Icons.Rounded.PhotoLibrary, R.string.tour_files_title, R.string.tour_files_text, listOf(Permission.Photos, Permission.AllFiles)),
    TourPage(Icons.Rounded.ScreenShare, R.string.tour_mirror_title, R.string.tour_mirror_text, listOf(Permission.MirrorControl)),
    TourPage(Icons.Rounded.Headphones, R.string.tour_accessories_title, R.string.tour_accessories_text, listOf(Permission.NearbyDevices)),
    TourPage(Icons.Rounded.BatteryChargingFull, R.string.tour_background_title, R.string.tour_background_text, listOf(Permission.Battery)),
    TourPage(Icons.Rounded.CheckCircle, R.string.tour_done_title, R.string.tour_done_text),
)

@OptIn(ExperimentalMaterial3ExpressiveApi::class)
@Composable
fun OnboardingScreen(refresh: Int) {
    val context = LocalContext.current
    val (granted, request) = rememberPermissions(refresh)
    var index by rememberSaveable { mutableIntStateOf(0) }
    val needed = Permission.needed()
    val page = TOUR[index]
    val missing = page.permissions.filter { it in needed && granted[it] != true }
    val last = index == TOUR.lastIndex

    fun next() {
        if (last) Onboarding.finish(context) else index++
    }

    Surface(Modifier.fillMaxSize(), color = MaterialTheme.colorScheme.surfaceContainerLowest) {
        Column(Modifier.safeDrawingPadding().padding(horizontal = 24.dp, vertical = 20.dp)) {
            LinearWavyProgressIndicator(progress = { (index + 1f) / TOUR.size }, modifier = Modifier.fillMaxWidth())
            AnimatedContent(
                targetState = index,
                transitionSpec = {
                    val forward = targetState > initialState
                    (slideInHorizontally { if (forward) it else -it } + fadeIn()) togetherWith
                        (slideOutHorizontally { if (forward) -it else it } + fadeOut())
                },
                modifier = Modifier.weight(1f),
                label = "tour",
            ) { shown ->
                TourContent(TOUR[shown], granted, needed)
            }
            Button(
                onClick = { if (missing.isEmpty()) next() else request(missing.first()) },
                modifier = Modifier.fillMaxWidth().height(56.dp),
            ) {
                Text(
                    stringResource(
                        when {
                            missing.isNotEmpty() -> R.string.tour_allow
                            last -> R.string.tour_start
                            else -> R.string.tour_continue
                        },
                    ),
                    style = MaterialTheme.typography.titleMedium,
                )
            }
            Row(Modifier.fillMaxWidth().padding(top = 4.dp), horizontalArrangement = Arrangement.SpaceBetween) {
                TextButton(onClick = { index-- }, enabled = index > 0) { Text(stringResource(R.string.tour_back)) }
                if (missing.isNotEmpty()) {
                    TextButton(onClick = ::next) { Text(stringResource(R.string.tour_not_now)) }
                } else if (!last) {
                    TextButton(onClick = { Onboarding.finish(context) }) { Text(stringResource(R.string.tour_skip)) }
                }
            }
        }
    }
}

@OptIn(ExperimentalMaterial3ExpressiveApi::class)
@Composable
private fun TourContent(page: TourPage, granted: Map<Permission, Boolean>, needed: List<Permission>) {
    Column(
        Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(top = 40.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        IconBadge(140.dp, MaterialShapes.Cookie9Sided.toShape(), MaterialTheme.colorScheme.primaryContainer) {
            if (page.icon == null) {
                Icon(painterResource(R.drawable.ic_laptop_phone), null, Modifier.size(76.dp), tint = MaterialTheme.colorScheme.onPrimaryContainer)
            } else {
                Icon(page.icon, null, Modifier.size(64.dp), tint = MaterialTheme.colorScheme.onPrimaryContainer)
            }
        }
        Spacer(Modifier.height(32.dp))
        Text(
            stringResource(page.title),
            style = MaterialTheme.typography.headlineMedium,
            fontWeight = FontWeight.SemiBold,
            textAlign = TextAlign.Center,
        )
        Spacer(Modifier.height(14.dp))
        Text(
            stringResource(page.text),
            style = MaterialTheme.typography.bodyLarge,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            textAlign = TextAlign.Center,
        )
        val permissions = page.permissions.filter { it in needed }
        if (permissions.isNotEmpty()) {
            Spacer(Modifier.height(24.dp))
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                permissions.forEach { permission ->
                    val allowed = granted[permission] == true
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Icon(
                            if (allowed) Icons.Rounded.CheckCircle else permission.icon,
                            null,
                            Modifier.size(20.dp),
                            tint = if (allowed) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                        Spacer(Modifier.size(8.dp))
                        Text(
                            stringResource(if (allowed) R.string.tour_allowed else R.string.tour_needs, stringResource(permission.title)),
                            style = MaterialTheme.typography.bodyMedium,
                            color = if (allowed) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                }
            }
        }
    }
}

package com.julianamarques.galaxybridge.ui

import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import com.julianamarques.galaxybridge.BuildConfig
import com.julianamarques.galaxybridge.bridge.Onboarding
import androidx.compose.ui.res.colorResource
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.foundation.layout.requiredSize
import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.IntrinsicSize
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.ArrowForward
import androidx.compose.material.icons.rounded.BatteryChargingFull
import androidx.compose.material.icons.rounded.Call
import androidx.compose.material.icons.rounded.CheckCircle
import androidx.compose.material.icons.rounded.Contacts
import androidx.compose.material.icons.rounded.ContentPaste
import androidx.compose.material.icons.rounded.Folder
import androidx.compose.material.icons.rounded.FolderOpen
import androidx.compose.material.icons.rounded.MusicNote
import androidx.compose.material.icons.rounded.Headphones
import androidx.compose.material.icons.rounded.ScreenShare
import androidx.compose.material.icons.rounded.Notifications
import androidx.compose.material.icons.rounded.Person
import androidx.compose.material.icons.rounded.PhotoLibrary
import androidx.compose.material.icons.rounded.QrCodeScanner
import androidx.compose.material.icons.rounded.Vibration
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.ExperimentalMaterial3ExpressiveApi
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.Icon
import androidx.compose.material3.LoadingIndicator
import androidx.compose.material3.MaterialShapes
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.toShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.activity.compose.LocalActivity
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.julianamarques.galaxybridge.Permission
import com.julianamarques.galaxybridge.R
import com.julianamarques.galaxybridge.bridge.BridgeService
import com.julianamarques.galaxybridge.bridge.BridgeState
import com.julianamarques.galaxybridge.bridge.PairedMac

private val Ready = Color(0xFF2E9E5B)

@Composable
private fun Page(content: @Composable ColumnScope.() -> Unit) {
    Surface(Modifier.fillMaxSize(), color = MaterialTheme.colorScheme.surfaceContainerLowest) {
        Column(
            Modifier
                .safeDrawingPadding()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 20.dp, vertical = 24.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) { content() }
    }
}

@OptIn(ExperimentalMaterial3ExpressiveApi::class)
@Composable
private fun Hero(title: String, subtitle: @Composable () -> Unit) {
    Column(
        Modifier.fillMaxWidth().padding(vertical = 8.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        IconBadge(132.dp, MaterialShapes.Cookie9Sided.toShape(), MaterialTheme.colorScheme.primaryContainer) {
            Icon(
                painterResource(R.drawable.ic_laptop_phone),
                contentDescription = null,
                modifier = Modifier.size(72.dp),
                tint = MaterialTheme.colorScheme.onPrimaryContainer,
            )
        }
        Spacer(Modifier.height(20.dp))
        Text(
            title,
            style = MaterialTheme.typography.headlineLarge,
            fontWeight = FontWeight.SemiBold,
            textAlign = TextAlign.Center,
        )
        Spacer(Modifier.height(10.dp))
        subtitle()
    }
}

@Composable
internal fun IconBadge(size: Dp, shape: Shape, container: Color, content: @Composable () -> Unit) {
    Box(Modifier.size(size).clip(shape).background(container), contentAlignment = Alignment.Center) { content() }
}

@Composable
private fun SectionTitle(text: String) {
    Text(
        text,
        style = MaterialTheme.typography.titleSmall,
        color = MaterialTheme.colorScheme.primary,
        modifier = Modifier.padding(start = 4.dp, top = 8.dp),
    )
}

@Composable
private fun PanelCard(content: @Composable ColumnScope.() -> Unit) {
    Card(
        shape = RoundedCornerShape(28.dp),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceContainer),
        content = content,
    )
}

@OptIn(ExperimentalMaterial3ExpressiveApi::class)
@Composable
fun SetupScreen(pairing: PairingController, refresh: Int) {
    val activity = LocalActivity.current
    val working = pairing.step is PairingStep.Working
    Page {
        Hero(stringResource(R.string.app_name)) {
            Text(
                stringResource(R.string.setup_intro),
                style = MaterialTheme.typography.bodyLarge,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                textAlign = TextAlign.Center,
            )
        }
        SectionTitle(stringResource(R.string.section_permissions))
        PermissionCard(refresh)
        SectionTitle(stringResource(R.string.section_pair))
        PanelCard {
            Column(Modifier.padding(20.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                Text(
                    stringResource(R.string.code_hint),
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                Button(
                    onClick = { activity?.let(pairing::scan) },
                    enabled = !working,
                    modifier = Modifier.fillMaxWidth().heightIn(min = 56.dp),
                ) {
                    Icon(Icons.Rounded.QrCodeScanner, contentDescription = null)
                    Spacer(Modifier.width(10.dp))
                    Text(stringResource(R.string.scan_mac_code), style = MaterialTheme.typography.titleMedium)
                }
                when (val step = pairing.step) {
                    PairingStep.Working -> Row(verticalAlignment = Alignment.CenterVertically) {
                        LoadingIndicator(Modifier.size(32.dp))
                        Spacer(Modifier.width(8.dp))
                        Text(stringResource(R.string.pairing))
                    }
                    is PairingStep.Failed -> Text(step.message, color = MaterialTheme.colorScheme.error)
                    else -> Unit
                }
            }
        }
    }
}

@Composable
fun HomeScreen(mac: PairedMac, connection: BridgeState.Connection, refresh: Int) {
    val context = LocalContext.current
    var confirmingForget by remember { mutableStateOf(false) }
    Page {
        val look = look(connection, mac.name)
        Hero(mac.name) { StatusChip(look) }
        look.detail?.let {
            Text(
                it,
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                textAlign = TextAlign.Center,
                modifier = Modifier.fillMaxWidth(),
            )
        }
        SectionTitle(stringResource(R.string.section_features))
        FeatureGrid(refresh)
        PanelCard {
            Text(
                stringResource(R.string.background_hint),
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(20.dp),
            )
        }
        SectionTitle(stringResource(R.string.section_about))
        AboutCard()
        TextButton(onClick = { confirmingForget = true }, modifier = Modifier.align(Alignment.CenterHorizontally)) {
            Text(stringResource(R.string.forget_mac), color = MaterialTheme.colorScheme.error)
        }
    }
    if (confirmingForget) {
        AlertDialog(
            onDismissRequest = { confirmingForget = false },
            title = { Text(stringResource(R.string.forget_mac_title, mac.name)) },
            text = { Text(stringResource(R.string.forget_mac_message)) },
            confirmButton = {
                Button(
                    onClick = {
                        confirmingForget = false
                        BridgeService.forget(context)
                    },
                    colors = ButtonDefaults.buttonColors(
                        containerColor = MaterialTheme.colorScheme.error,
                        contentColor = MaterialTheme.colorScheme.onError,
                    ),
                ) { Text(stringResource(R.string.forget)) }
            },
            dismissButton = { TextButton(onClick = { confirmingForget = false }) { Text(stringResource(R.string.cancel)) } },
        )
    }
}

private const val REPOSITORY = "https://github.com/julianamarques/galaxy-bridge"

@Composable
private fun AboutCard() {
    val links = LocalUriHandler.current
    PanelCard {
        Column(
            Modifier.fillMaxWidth().padding(horizontal = 24.dp, vertical = 28.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Box(
                Modifier.size(88.dp).clip(RoundedCornerShape(22.dp)).background(colorResource(R.color.icon_background)),
                contentAlignment = Alignment.Center,
            ) {
                Image(
                    painterResource(R.drawable.ic_launcher_foreground),
                    contentDescription = null,
                    modifier = Modifier.requiredSize(132.dp),
                )
            }
            Spacer(Modifier.height(16.dp))
            Text(stringResource(R.string.app_name), style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.SemiBold)
            Text(
                stringResource(R.string.about_version, BuildConfig.VERSION_NAME),
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            Spacer(Modifier.height(12.dp))
            Text(
                stringResource(R.string.about_description),
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                textAlign = TextAlign.Center,
            )
            Spacer(Modifier.height(8.dp))
            val context = LocalContext.current
            Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                TextButton(onClick = { Onboarding.replay(context) }) { Text(stringResource(R.string.about_tour)) }
                TextButton(onClick = { links.openUri(REPOSITORY) }) { Text(stringResource(R.string.about_github)) }
            }
            Text(
                stringResource(R.string.about_copyright),
                style = MaterialTheme.typography.labelMedium,
                color = MaterialTheme.colorScheme.outline,
            )
        }
    }
}

private data class ConnectionLook(val label: String, val color: Color, val detail: String?, val pulsing: Boolean)

@Composable
private fun look(connection: BridgeState.Connection, macName: String): ConnectionLook = when (connection) {
    is BridgeState.Connection.Connected -> ConnectionLook(stringResource(if (connection.usb) R.string.status_chip_connected_usb else R.string.status_chip_connected), Ready, null, pulsing = false)
    BridgeState.Connection.Refused -> ConnectionLook(
        stringResource(R.string.status_chip_refused),
        MaterialTheme.colorScheme.error,
        stringResource(R.string.status_refused, macName),
        pulsing = false,
    )
    else -> ConnectionLook(
        stringResource(R.string.status_chip_searching),
        MaterialTheme.colorScheme.tertiary,
        stringResource(R.string.status_searching),
        pulsing = true,
    )
}

@Composable
private fun StatusChip(look: ConnectionLook) {
    val dotColor by animateColorAsState(look.color, label = "status")
    val pulse = if (look.pulsing) {
        rememberInfiniteTransition(label = "pulse").animateFloat(
            initialValue = 1f,
            targetValue = 0.25f,
            animationSpec = infiniteRepeatable(tween(900), RepeatMode.Reverse),
            label = "alpha",
        )
    } else {
        null
    }
    Surface(shape = CircleShape, color = MaterialTheme.colorScheme.surfaceContainerHigh) {
        Row(Modifier.padding(horizontal = 14.dp, vertical = 8.dp), verticalAlignment = Alignment.CenterVertically) {
            Box(Modifier.size(10.dp).graphicsLayer { alpha = pulse?.value ?: 1f }.clip(CircleShape).background(dotColor))
            Spacer(Modifier.width(8.dp))
            Text(look.label, style = MaterialTheme.typography.labelLarge)
        }
    }
}

private data class Feature(val icon: ImageVector, val title: Int, val detail: Int, val permission: Permission?)

private val features = listOf(
    Feature(Icons.Rounded.BatteryChargingFull, R.string.feature_battery, R.string.feature_battery_on, Permission.Battery),
    Feature(Icons.Rounded.Call, R.string.feature_calls, R.string.feature_calls_on, Permission.Calls),
    Feature(Icons.Rounded.Notifications, R.string.feature_notifications, R.string.feature_notifications_on, Permission.CallerName),
    Feature(Icons.Rounded.Contacts, R.string.feature_contacts, R.string.feature_contacts_on, Permission.Contacts),
    Feature(Icons.Rounded.Folder, R.string.feature_files, R.string.feature_files_on, Permission.Notifications),
    Feature(Icons.Rounded.PhotoLibrary, R.string.feature_photos, R.string.feature_photos_on, Permission.Photos),
    Feature(Icons.Rounded.FolderOpen, R.string.feature_browse, R.string.feature_browse_on, Permission.AllFiles),
    Feature(Icons.Rounded.MusicNote, R.string.feature_media, R.string.feature_media_on, Permission.CallerName),
    Feature(Icons.Rounded.ScreenShare, R.string.feature_mirror, R.string.feature_mirror_on, Permission.MirrorControl),
    Feature(Icons.Rounded.Headphones, R.string.feature_accessories, R.string.feature_accessories_on, Permission.NearbyDevices),
    Feature(Icons.Rounded.ContentPaste, R.string.feature_clipboard, R.string.feature_clipboard_on, null),
    Feature(Icons.Rounded.Vibration, R.string.feature_find, R.string.feature_find_on, null),
)

@Composable
internal fun rememberPermissions(refresh: Int): Pair<Map<Permission, Boolean>, (Permission) -> Unit> {
    val context = LocalContext.current
    fun read() = Permission.needed().associateWith { it.isGranted(context) }
    var granted by remember(refresh) { mutableStateOf(read()) }
    val launcher = rememberLauncherForActivityResult(ActivityResultContracts.RequestMultiplePermissions()) { granted = read() }
    return granted to { permission ->
        val manifestPermissions = permission.manifestPermissions
        if (manifestPermissions.isNotEmpty()) launcher.launch(manifestPermissions.toTypedArray())
        else permission.settingsIntent(context)?.let(context::startActivity)
    }
}

@Composable
private fun FeatureGrid(refresh: Int) {
    val (granted, request) = rememberPermissions(refresh)
    val shown = features.filter { it.permission == null || it.permission in granted }
    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        shown.chunked(2).forEach { row ->
            Row(Modifier.height(IntrinsicSize.Min), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                row.forEach { feature ->
                    val ready = feature.permission == null || granted[feature.permission] == true
                    FeatureTile(feature, ready, Modifier.weight(1f).fillMaxHeight()) { feature.permission?.let(request) }
                }
                if (row.size == 1) Spacer(Modifier.weight(1f))
            }
        }
    }
}

@Composable
private fun FeatureTile(feature: Feature, ready: Boolean, modifier: Modifier, onRequest: () -> Unit) {
    val colors = MaterialTheme.colorScheme
    val (container, badge, onBadge, title, detail) = if (ready) {
        listOf(colors.surfaceContainer, colors.primaryContainer, colors.onPrimaryContainer, colors.onSurface, colors.onSurfaceVariant)
    } else {
        listOf(colors.errorContainer, colors.error, colors.onError, colors.onErrorContainer, colors.onErrorContainer)
    }
    Card(
        onClick = onRequest,
        enabled = !ready,
        modifier = modifier,
        shape = RoundedCornerShape(24.dp),
        colors = CardDefaults.cardColors(containerColor = container, disabledContainerColor = container),
    ) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            IconBadge(44.dp, RoundedCornerShape(14.dp), badge) {
                Icon(feature.icon, contentDescription = null, tint = onBadge)
            }
            Text(stringResource(feature.title), style = MaterialTheme.typography.titleMedium, color = title)
            Text(
                stringResource(if (ready) feature.detail else R.string.feature_needs_permission),
                style = MaterialTheme.typography.bodySmall,
                color = detail,
                minLines = 2,
            )
        }
    }
}

@Composable
private fun PermissionCard(refresh: Int) {
    val (granted, request) = rememberPermissions(refresh)
    PanelCard {
        Column(Modifier.padding(vertical = 8.dp)) {
            granted.forEach { (permission, isGranted) ->
                PermissionRow(permission, isGranted) { request(permission) }
            }
        }
    }
}

@Composable
private fun PermissionRow(permission: Permission, isGranted: Boolean, onRequest: () -> Unit) {
    Row(
        Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        IconBadge(40.dp, CircleShape, MaterialTheme.colorScheme.secondaryContainer) {
            Icon(permission.icon, contentDescription = null, tint = MaterialTheme.colorScheme.onSecondaryContainer)
        }
        Spacer(Modifier.width(14.dp))
        Column(Modifier.weight(1f)) {
            Text(stringResource(permission.title), style = MaterialTheme.typography.titleSmall)
            Text(
                stringResource(permission.reason),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
        Spacer(Modifier.width(8.dp))
        if (isGranted) {
            Icon(Icons.Rounded.CheckCircle, contentDescription = stringResource(R.string.allowed), tint = Ready)
        } else {
            FilledTonalButton(onClick = onRequest) {
                Text(stringResource(R.string.allow))
                Spacer(Modifier.width(4.dp))
                Icon(Icons.AutoMirrored.Rounded.ArrowForward, contentDescription = null, modifier = Modifier.size(16.dp))
            }
        }
    }
}

internal val Permission.icon: ImageVector
    get() = when (this) {
        Permission.Notifications -> Icons.Rounded.Notifications
        Permission.Calls -> Icons.Rounded.Call
        Permission.CallerName -> Icons.Rounded.Person
        Permission.Contacts -> Icons.Rounded.Contacts
        Permission.Photos -> Icons.Rounded.PhotoLibrary
        Permission.AllFiles -> Icons.Rounded.FolderOpen
        Permission.MirrorControl -> Icons.Rounded.ScreenShare
        Permission.NearbyDevices -> Icons.Rounded.Headphones
        Permission.Battery -> Icons.Rounded.BatteryChargingFull
    }

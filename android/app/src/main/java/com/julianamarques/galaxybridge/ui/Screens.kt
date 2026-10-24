package com.julianamarques.galaxybridge.ui

import android.app.Activity
import android.content.Context
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
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
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.ArrowForward
import androidx.compose.material.icons.rounded.BatteryChargingFull
import androidx.compose.material.icons.rounded.Call
import androidx.compose.material.icons.rounded.CheckCircle
import androidx.compose.material.icons.rounded.Contacts
import androidx.compose.material.icons.rounded.ContentPaste
import androidx.compose.material.icons.rounded.Folder
import androidx.compose.material.icons.rounded.Keyboard
import androidx.compose.material.icons.rounded.Notifications
import androidx.compose.material.icons.rounded.Person
import androidx.compose.material.icons.rounded.QrCodeScanner
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
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.RadioButton
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
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
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
        Box(
            Modifier
                .size(132.dp)
                .clip(MaterialShapes.Cookie9Sided.toShape())
                .background(MaterialTheme.colorScheme.primaryContainer),
            contentAlignment = Alignment.Center,
        ) {
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
    val activity = LocalContext.current as Activity
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
                    onClick = { pairing.scan(activity) },
                    enabled = !working,
                    modifier = Modifier.fillMaxWidth().heightIn(min = 56.dp),
                ) {
                    Icon(Icons.Rounded.QrCodeScanner, contentDescription = null)
                    Spacer(Modifier.width(10.dp))
                    Text(stringResource(R.string.scan_mac_code), style = MaterialTheme.typography.titleMedium)
                }
                OutlinedButton(
                    onClick = pairing::startCode,
                    enabled = !working,
                    modifier = Modifier.fillMaxWidth().heightIn(min = 52.dp),
                ) {
                    Icon(Icons.Rounded.Keyboard, contentDescription = null)
                    Spacer(Modifier.width(10.dp))
                    Text(stringResource(R.string.type_code))
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
    when (val step = pairing.step) {
        is PairingStep.CodeEntry -> CodeDialog(step, pairing)
        is PairingStep.Confirm -> AlertDialog(
            onDismissRequest = pairing::cancel,
            title = { Text(stringResource(R.string.check_mac)) },
            text = {
                Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    Text(stringResource(R.string.check_mac_question))
                    Surface(shape = RoundedCornerShape(16.dp), color = MaterialTheme.colorScheme.secondaryContainer) {
                        Text(
                            step.fingerprint,
                            style = MaterialTheme.typography.headlineSmall,
                            fontFamily = FontFamily.Monospace,
                            modifier = Modifier.fillMaxWidth().padding(vertical = 12.dp),
                            textAlign = TextAlign.Center,
                        )
                    }
                    Text(stringResource(R.string.check_mac_warning), style = MaterialTheme.typography.bodySmall)
                }
            },
            confirmButton = { Button(onClick = pairing::confirm) { Text(stringResource(R.string.check_mac_match)) } },
            dismissButton = { TextButton(onClick = pairing::cancel) { Text(stringResource(R.string.cancel)) } },
        )
        else -> Unit
    }
}

@OptIn(ExperimentalMaterial3ExpressiveApi::class)
@Composable
private fun CodeDialog(step: PairingStep.CodeEntry, pairing: PairingController) {
    AlertDialog(
        onDismissRequest = pairing::cancel,
        icon = { Icon(Icons.Rounded.Keyboard, contentDescription = null) },
        title = { Text(stringResource(R.string.type_code)) },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                when {
                    step.searching -> Row(verticalAlignment = Alignment.CenterVertically) {
                        LoadingIndicator(Modifier.size(28.dp))
                        Spacer(Modifier.width(8.dp))
                        Text(stringResource(R.string.searching_mac))
                    }
                    step.macs.isEmpty() -> Text(stringResource(R.string.no_mac_found))
                    step.macs.size == 1 -> Text(stringResource(R.string.mac_named, step.macs.first().name))
                    else -> step.macs.forEach { mac ->
                        Row(
                            Modifier.fillMaxWidth().selectable(selected = mac == step.selected, onClick = { pairing.select(mac) }),
                            verticalAlignment = Alignment.CenterVertically,
                        ) {
                            RadioButton(selected = mac == step.selected, onClick = { pairing.select(mac) })
                            Text(mac.name)
                        }
                    }
                }
                OutlinedTextField(
                    value = step.code,
                    onValueChange = pairing::updateCode,
                    label = { Text(stringResource(R.string.six_digit_code)) },
                    singleLine = true,
                    shape = RoundedCornerShape(16.dp),
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.NumberPassword),
                    textStyle = MaterialTheme.typography.headlineSmall.copy(fontFamily = FontFamily.Monospace),
                )
                step.error?.let { Text(it, color = MaterialTheme.colorScheme.error) }
            }
        },
        confirmButton = {
            if (!step.searching && step.macs.isEmpty()) {
                Button(onClick = pairing::startCode) { Text(stringResource(R.string.search_again)) }
            } else {
                Button(
                    onClick = pairing::submitCode,
                    enabled = step.selected != null && step.code.length == 6 && !step.connecting,
                ) { Text(stringResource(if (step.connecting) R.string.connecting else R.string.continue_label)) }
            }
        },
        dismissButton = { TextButton(onClick = pairing::cancel) { Text(stringResource(R.string.cancel)) } },
    )
}

@Composable
fun HomeScreen(mac: PairedMac, connection: BridgeState.Connection, refresh: Int) {
    val context = LocalContext.current
    var confirmingForget by remember { mutableStateOf(false) }
    Page {
        Hero(mac.name) { StatusChip(connection) }
        val detail = when (connection) {
            is BridgeState.Connection.Connected -> null
            BridgeState.Connection.Refused -> stringResource(R.string.status_refused, mac.name)
            else -> stringResource(R.string.status_searching)
        }
        detail?.let {
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

@Composable
private fun StatusChip(connection: BridgeState.Connection) {
    val searching = connection !is BridgeState.Connection.Connected && connection != BridgeState.Connection.Refused
    val (label, color) = when (connection) {
        is BridgeState.Connection.Connected -> stringResource(R.string.status_chip_connected) to Ready
        BridgeState.Connection.Refused -> stringResource(R.string.status_chip_refused) to MaterialTheme.colorScheme.error
        else -> stringResource(R.string.status_chip_searching) to MaterialTheme.colorScheme.tertiary
    }
    val dotColor by animateColorAsState(color, label = "status")
    val alpha by rememberInfiniteTransition(label = "pulse").animateFloat(
        initialValue = 1f,
        targetValue = if (searching) 0.25f else 1f,
        animationSpec = infiniteRepeatable(tween(900), RepeatMode.Reverse),
        label = "alpha",
    )
    Surface(shape = CircleShape, color = MaterialTheme.colorScheme.surfaceContainerHigh) {
        Row(Modifier.padding(horizontal = 14.dp, vertical = 8.dp), verticalAlignment = Alignment.CenterVertically) {
            Box(Modifier.size(10.dp).alpha(alpha).clip(CircleShape).background(dotColor))
            Spacer(Modifier.width(8.dp))
            Text(label, style = MaterialTheme.typography.labelLarge)
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
    Feature(Icons.Rounded.ContentPaste, R.string.feature_clipboard, R.string.feature_clipboard_on, null),
)

@Composable
private fun FeatureGrid(refresh: Int) {
    val context = LocalContext.current
    val needed = remember { Permission.needed() }
    fun read() = needed.associateWith { it.isGranted(context) }
    var granted by remember(refresh) { mutableStateOf(read()) }
    val request = rememberLauncherForActivityResult(ActivityResultContracts.RequestMultiplePermissions()) { granted = read() }
    val shown = features.filter { it.permission == null || it.permission in needed }
    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        shown.chunked(2).forEach { row ->
            Row(Modifier.height(IntrinsicSize.Min), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                row.forEach { feature ->
                    val ready = feature.permission == null || granted[feature.permission] == true
                    FeatureTile(feature, ready, Modifier.weight(1f).fillMaxHeight()) {
                        feature.permission?.let { requestPermission(it, context, request::launch) }
                    }
                }
                if (row.size == 1) Spacer(Modifier.weight(1f))
            }
        }
    }
}

@Composable
private fun FeatureTile(feature: Feature, ready: Boolean, modifier: Modifier, onRequest: () -> Unit) {
    val container = if (ready) MaterialTheme.colorScheme.surfaceContainer else MaterialTheme.colorScheme.errorContainer
    Card(
        onClick = onRequest,
        enabled = !ready,
        modifier = modifier,
        shape = RoundedCornerShape(24.dp),
        colors = CardDefaults.cardColors(containerColor = container, disabledContainerColor = container),
    ) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Box(
                Modifier
                    .size(44.dp)
                    .clip(RoundedCornerShape(14.dp))
                    .background(if (ready) MaterialTheme.colorScheme.primaryContainer else MaterialTheme.colorScheme.error),
                contentAlignment = Alignment.Center,
            ) {
                Icon(
                    feature.icon,
                    contentDescription = null,
                    tint = if (ready) MaterialTheme.colorScheme.onPrimaryContainer else MaterialTheme.colorScheme.onError,
                )
            }
            Text(
                stringResource(feature.title),
                style = MaterialTheme.typography.titleMedium,
                color = if (ready) MaterialTheme.colorScheme.onSurface else MaterialTheme.colorScheme.onErrorContainer,
            )
            Text(
                stringResource(if (ready) feature.detail else R.string.feature_needs_permission),
                style = MaterialTheme.typography.bodySmall,
                color = if (ready) MaterialTheme.colorScheme.onSurfaceVariant else MaterialTheme.colorScheme.onErrorContainer,
                minLines = 2,
            )
        }
    }
}

private fun requestPermission(permission: Permission, context: Context, launch: (Array<String>) -> Unit) {
    val manifestPermissions = permission.manifestPermissions
    if (manifestPermissions.isNotEmpty()) launch(manifestPermissions.toTypedArray())
    else permission.settingsIntent(context)?.let(context::startActivity)
}

@Composable
private fun PermissionCard(refresh: Int) {
    val context = LocalContext.current
    fun read() = Permission.needed().associateWith { it.isGranted(context) }
    var granted by remember(refresh) { mutableStateOf(read()) }
    val request = rememberLauncherForActivityResult(ActivityResultContracts.RequestMultiplePermissions()) { granted = read() }
    PanelCard {
        Column(Modifier.padding(vertical = 8.dp)) {
            Permission.needed().forEach { permission ->
                PermissionRow(permission, isGranted = granted[permission] == true) {
                    requestPermission(permission, context, request::launch)
                }
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
        Box(
            Modifier.size(40.dp).clip(CircleShape).background(MaterialTheme.colorScheme.secondaryContainer),
            contentAlignment = Alignment.Center,
        ) {
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

private val Permission.icon: ImageVector
    get() = when (this) {
        Permission.Notifications -> Icons.Rounded.Notifications
        Permission.Calls -> Icons.Rounded.Call
        Permission.CallerName -> Icons.Rounded.Person
        Permission.Contacts -> Icons.Rounded.Contacts
        Permission.Battery -> Icons.Rounded.BatteryChargingFull
    }

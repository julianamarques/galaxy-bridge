package com.julianamarques.galaxybridge.ui

import android.app.Activity
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Call
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Info
import androidx.compose.material.icons.filled.Notifications
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.RadioButton
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.julianamarques.galaxybridge.Permission
import com.julianamarques.galaxybridge.R
import com.julianamarques.galaxybridge.bridge.BridgeService
import com.julianamarques.galaxybridge.bridge.BridgeState
import com.julianamarques.galaxybridge.bridge.PairedMac

@Composable
private fun Page(content: @Composable ColumnScope.() -> Unit) {
    Surface(Modifier.fillMaxSize(), color = MaterialTheme.colorScheme.surfaceContainer) {
        Column(
            Modifier
                .safeDrawingPadding()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 24.dp, vertical = 32.dp),
            verticalArrangement = Arrangement.spacedBy(20.dp),
        ) { content() }
    }
}

@Composable
private fun Header(title: String, subtitle: String) {
    Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally) {
        Icon(
            painterResource(R.drawable.ic_laptop_phone),
            contentDescription = null,
            modifier = Modifier.size(96.dp),
            tint = MaterialTheme.colorScheme.primary,
        )
        Spacer(Modifier.height(12.dp))
        Text(title, style = MaterialTheme.typography.headlineMedium, textAlign = TextAlign.Center)
        Spacer(Modifier.height(8.dp))
        Text(
            subtitle,
            style = MaterialTheme.typography.bodyLarge,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            textAlign = TextAlign.Center,
        )
    }
}

// MARK: Configuração

@Composable
fun SetupScreen(pairing: PairingController, refresh: Int) {
    val activity = LocalContext.current as Activity
    Page {
        Header("Galaxy Bridge", "Conecte este Galaxy ao Mac para ver a bateria e fazer ligações pelo Mac, pela rede Wi-Fi.")
        PermissionCard(refresh)
        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Button(
                onClick = { pairing.scan(activity) },
                enabled = pairing.step !is PairingStep.Working,
                modifier = Modifier.fillMaxWidth(),
            ) { Text("Escanear código do Mac") }
            OutlinedButton(
                onClick = pairing::startCode,
                enabled = pairing.step !is PairingStep.Working,
                modifier = Modifier.fillMaxWidth(),
            ) { Text("Digitar código") }
        }
        Text(
            "No Mac, abra o Galaxy Bridge e clique em Continuar para ver o código.",
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        when (val step = pairing.step) {
            PairingStep.Working -> Row(verticalAlignment = Alignment.CenterVertically) {
                CircularProgressIndicator(Modifier.size(20.dp), strokeWidth = 2.dp)
                Spacer(Modifier.width(12.dp))
                Text("Pareando…")
            }
            is PairingStep.Failed -> Text(step.message, color = MaterialTheme.colorScheme.error)
            else -> Unit
        }
    }
    when (val step = pairing.step) {
        is PairingStep.CodeEntry -> CodeDialog(step, pairing)
        is PairingStep.Confirm -> AlertDialog(
            onDismissRequest = pairing::cancel,
            title = { Text("Confira o Mac") },
            text = {
                Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    Text("O Mac mostra estes caracteres embaixo do código?")
                    Text(step.fingerprint, style = MaterialTheme.typography.headlineSmall, fontFamily = FontFamily.Monospace)
                    Text(
                        "Se não forem iguais, outro aparelho está se passando pelo Mac. Cancele.",
                        style = MaterialTheme.typography.bodySmall,
                    )
                }
            },
            confirmButton = { TextButton(onClick = pairing::confirm) { Text("São iguais") } },
            dismissButton = { TextButton(onClick = pairing::cancel) { Text("Cancelar") } },
        )
        else -> Unit
    }
}

@Composable
private fun CodeDialog(step: PairingStep.CodeEntry, pairing: PairingController) {
    AlertDialog(
        onDismissRequest = pairing::cancel,
        title = { Text("Digitar código") },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                when {
                    step.searching -> Row(verticalAlignment = Alignment.CenterVertically) {
                        CircularProgressIndicator(Modifier.size(16.dp), strokeWidth = 2.dp)
                        Spacer(Modifier.width(8.dp))
                        Text("Procurando o Mac na rede…")
                    }
                    step.macs.isEmpty() -> Text(
                        "Nenhum Mac encontrado. Confira se o Mac está na mesma rede Wi-Fi, com a tela do código aberta.",
                    )
                    step.macs.size == 1 -> Text("Mac: ${step.macs.first().name}")
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
                    label = { Text("Código de seis dígitos") },
                    singleLine = true,
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.NumberPassword),
                    textStyle = MaterialTheme.typography.headlineSmall.copy(fontFamily = FontFamily.Monospace),
                )
                step.error?.let { Text(it, color = MaterialTheme.colorScheme.error) }
            }
        },
        confirmButton = {
            if (!step.searching && step.macs.isEmpty()) {
                TextButton(onClick = pairing::startCode) { Text("Procurar de novo") }
            } else {
                TextButton(
                    onClick = pairing::submitCode,
                    enabled = step.selected != null && step.code.length == 6 && !step.connecting,
                ) { Text(if (step.connecting) "Conectando…" else "Continuar") }
            }
        },
        dismissButton = { TextButton(onClick = pairing::cancel) { Text("Cancelar") } },
    )
}

// MARK: Conectado

@Composable
fun HomeScreen(mac: PairedMac, connection: BridgeState.Connection, refresh: Int) {
    val context = LocalContext.current
    var confirmingForget by remember { mutableStateOf(false) }
    val status = when (connection) {
        is BridgeState.Connection.Connected -> "Conectado pela rede Wi-Fi."
        BridgeState.Connection.Refused ->
            "O ${mac.name} não reconhece mais este celular. Esqueça o Mac aqui e pareie de novo."
        else -> "Procurando o Mac. Ele precisa estar ligado, na mesma rede Wi-Fi e com o Galaxy Bridge aberto."
    }
    Page {
        Header(mac.name, status)
        if (Permission.missing(context).isNotEmpty()) PermissionCard(refresh)
        Text(
            "Pode fechar este app: a conexão continua em segundo plano e volta sozinha quando o celular reinicia.",
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        TextButton(onClick = { confirmingForget = true }, modifier = Modifier.align(Alignment.CenterHorizontally)) {
            Text("Esquecer este Mac", color = MaterialTheme.colorScheme.error)
        }
    }
    if (confirmingForget) {
        AlertDialog(
            onDismissRequest = { confirmingForget = false },
            title = { Text("Esquecer o ${mac.name}?") },
            text = { Text("O Mac também esquece este celular. Para usá-los juntos de novo, será preciso parear outra vez.") },
            confirmButton = {
                TextButton(onClick = {
                    confirmingForget = false
                    BridgeService.forget(context)
                }) { Text("Esquecer", color = MaterialTheme.colorScheme.error) }
            },
            dismissButton = { TextButton(onClick = { confirmingForget = false }) { Text("Cancelar") } },
        )
    }
}

// MARK: Permissões

@Composable
private fun PermissionCard(refresh: Int) {
    val context = LocalContext.current
    // `refresh` muda quando o app volta ao primeiro plano, para reler o que o usuário mudou nos Ajustes.
    val granted = remember(refresh) { mutableStateOf(Permission.needed().associateWith { it.isGranted(context) }) }
    val request = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) {
        granted.value = Permission.needed().associateWith { it.isGranted(context) }
    }
    Card(Modifier.fillMaxWidth()) {
        Column(Modifier.padding(vertical = 8.dp)) {
            Permission.needed().forEach { permission ->
                PermissionRow(permission, isGranted = granted.value[permission] == true) {
                    val manifestPermission = permission.manifestPermission
                    if (manifestPermission != null) request.launch(manifestPermission)
                    else context.startActivity(Permission.batteryIntent(context))
                }
            }
        }
    }
}

@Composable
private fun PermissionRow(permission: Permission, isGranted: Boolean, onRequest: () -> Unit) {
    Row(
        Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(permission.icon, contentDescription = null, tint = MaterialTheme.colorScheme.onSurfaceVariant)
        Spacer(Modifier.width(16.dp))
        Column(Modifier.weight(1f)) {
            Text(permission.title, style = MaterialTheme.typography.titleSmall)
            Text(permission.reason, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        Spacer(Modifier.width(8.dp))
        if (isGranted) {
            Icon(Icons.Filled.CheckCircle, contentDescription = "Permitido", tint = MaterialTheme.colorScheme.primary)
        } else {
            FilledTonalButton(onClick = onRequest) { Text("Permitir") }
        }
    }
}

private val Permission.icon: ImageVector
    get() = when (this) {
        Permission.Notifications -> Icons.Filled.Notifications
        Permission.Calls -> Icons.Filled.Call
        Permission.Battery -> Icons.Filled.Info
    }

package com.julianamarques.galaxybridge.protocol

import java.net.URI
import java.net.URLDecoder

/** O conteúdo do QR code mostrado no Mac: `galaxybridge://pair?v=1&host=…&port=…&fp=…&token=…`. */
data class PairingLink(val host: String, val port: Int, val fingerprint: String, val token: String) {
    companion object {
        fun parse(text: String): PairingLink? {
            val uri = runCatching { URI(text.trim()) }.getOrNull() ?: return null
            if (uri.scheme != "galaxybridge" || uri.host != "pair") return null
            val items = uri.rawQuery.orEmpty().split('&').mapNotNull { item ->
                val parts = item.split('=', limit = 2)
                if (parts.size == 2) parts[0] to URLDecoder.decode(parts[1], "UTF-8") else null
            }.toMap()
            if (items["v"] != PROTOCOL_VERSION.toString()) return null
            val host = items["host"]?.takeIf { it.isNotEmpty() } ?: return null
            val port = items["port"]?.toIntOrNull()?.takeIf { it in 1..65535 } ?: return null
            val fingerprint = items["fp"]?.lowercase()?.takeIf { it.length == 64 } ?: return null
            val token = items["token"]?.takeIf { it.isNotEmpty() } ?: return null
            return PairingLink(host, port, fingerprint, token)
        }
    }
}

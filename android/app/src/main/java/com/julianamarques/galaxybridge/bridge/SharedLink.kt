package com.julianamarques.galaxybridge.bridge

object SharedLink {
    private const val MAX_EXTRA_TEXT = 100
    private val URL = Regex("""https?://[^\s<>"]+""", RegexOption.IGNORE_CASE)
    private val TRAILING = charArrayOf('.', ',', ';', ':', '!', '?', ')', ']', '}', '\'', '"')

    fun find(text: String): String? {
        val urls = URL.findAll(text).toList()
        val match = urls.singleOrNull() ?: return null
        val url = match.value.trimEnd(*TRAILING)
        val rest = text.removeRange(match.range).trim()
        return url.takeIf { rest.length <= MAX_EXTRA_TEXT }
    }
}

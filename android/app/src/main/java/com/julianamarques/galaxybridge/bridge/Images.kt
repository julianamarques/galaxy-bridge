package com.julianamarques.galaxybridge.bridge

import android.graphics.Bitmap
import android.util.Base64
import java.io.ByteArrayOutputStream

fun Bitmap.toBase64(maxSide: Int, format: Bitmap.CompressFormat = Bitmap.CompressFormat.JPEG, quality: Int = 80): String {
    val scale = maxSide.toFloat() / maxOf(width, height)
    val scaled = if (scale < 1f) Bitmap.createScaledBitmap(this, (width * scale).toInt(), (height * scale).toInt(), true) else this
    val bytes = ByteArrayOutputStream()
    scaled.compress(format, quality, bytes)
    if (scaled !== this) scaled.recycle()
    return Base64.encodeToString(bytes.toByteArray(), Base64.NO_WRAP)
}

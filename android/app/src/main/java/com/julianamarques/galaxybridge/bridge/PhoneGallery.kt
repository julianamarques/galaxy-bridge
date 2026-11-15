package com.julianamarques.galaxybridge.bridge

import android.content.ContentResolver
import android.content.ContentUris
import android.content.Context
import android.graphics.Bitmap
import android.net.Uri
import android.os.Bundle
import android.provider.MediaStore
import android.util.Base64
import android.util.Size
import com.julianamarques.galaxybridge.Permission
import com.julianamarques.galaxybridge.protocol.GalleryPhoto
import java.io.ByteArrayOutputStream

object PhoneGallery {
    private const val THUMBNAIL_PX = 200
    private const val JPEG_QUALITY = 75
    private const val MAX_LIMIT = 24
    private val IMAGES: Uri = MediaStore.Images.Media.EXTERNAL_CONTENT_URI

    fun canRead(context: Context): Boolean = Permission.Photos.isGranted(context)

    fun recent(context: Context, limit: Int): List<GalleryPhoto> {
        val resolver = context.contentResolver
        val query = Bundle().apply {
            putStringArray(ContentResolver.QUERY_ARG_SORT_COLUMNS, arrayOf(MediaStore.Images.Media.DATE_ADDED))
            putInt(ContentResolver.QUERY_ARG_SORT_DIRECTION, ContentResolver.QUERY_SORT_DIRECTION_DESCENDING)
            putInt(ContentResolver.QUERY_ARG_LIMIT, limit.coerceIn(1, MAX_LIMIT))
        }
        val projection = arrayOf(
            MediaStore.Images.Media._ID,
            MediaStore.Images.Media.DISPLAY_NAME,
            MediaStore.Images.Media.DATE_TAKEN,
            MediaStore.Images.Media.DATE_ADDED,
        )
        return resolver.query(IMAGES, projection, query, null)?.use { cursor ->
            buildList {
                while (cursor.moveToNext()) {
                    val id = cursor.getLong(0)
                    val thumbnail = runCatching { thumbnail(resolver, ContentUris.withAppendedId(IMAGES, id)) }.getOrNull() ?: continue
                    val time = if (cursor.isNull(2)) cursor.getLong(3) * 1000 else cursor.getLong(2)
                    add(GalleryPhoto(id.toString(), cursor.getString(1) ?: "$id.jpg", time, thumbnail))
                }
            }
        }.orEmpty()
    }

    fun uri(id: String): Uri? = id.toLongOrNull()?.let { ContentUris.withAppendedId(IMAGES, it) }

    private fun thumbnail(resolver: ContentResolver, uri: Uri): String {
        val bitmap = resolver.loadThumbnail(uri, Size(THUMBNAIL_PX, THUMBNAIL_PX), null)
        val bytes = ByteArrayOutputStream()
        bitmap.compress(Bitmap.CompressFormat.JPEG, JPEG_QUALITY, bytes)
        bitmap.recycle()
        return Base64.encodeToString(bytes.toByteArray(), Base64.NO_WRAP)
    }
}

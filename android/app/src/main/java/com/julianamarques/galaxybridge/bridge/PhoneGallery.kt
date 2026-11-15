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
import com.julianamarques.galaxybridge.protocol.GalleryAlbum
import com.julianamarques.galaxybridge.protocol.GalleryPhoto
import java.io.ByteArrayOutputStream

object PhoneGallery {
    private const val THUMBNAIL_PX = 200
    private const val JPEG_QUALITY = 75
    private const val MAX_LIMIT = 40
    private const val VIDEO_PREFIX = "video:"
    private val FILES: Uri = MediaStore.Files.getContentUri(MediaStore.VOLUME_EXTERNAL)
    private val IMAGES: Uri = MediaStore.Images.Media.EXTERNAL_CONTENT_URI
    private val VIDEOS: Uri = MediaStore.Video.Media.EXTERNAL_CONTENT_URI

    fun canRead(context: Context): Boolean = Permission.Photos.isGranted(context)

    fun recent(context: Context, limit: Int, offset: Int = 0, album: String? = null, videos: Boolean = false): List<GalleryPhoto> {
        val resolver = context.contentResolver
        val types = if (videos) listOf(MediaStore.Files.FileColumns.MEDIA_TYPE_IMAGE, MediaStore.Files.FileColumns.MEDIA_TYPE_VIDEO) else listOf(MediaStore.Files.FileColumns.MEDIA_TYPE_IMAGE)
        val selection = buildString {
            append("${MediaStore.Files.FileColumns.MEDIA_TYPE} IN (${types.joinToString()})")
            if (album != null) append(" AND ${MediaStore.MediaColumns.BUCKET_ID} = ?")
        }
        val query = Bundle().apply {
            putString(ContentResolver.QUERY_ARG_SQL_SELECTION, selection)
            if (album != null) putStringArray(ContentResolver.QUERY_ARG_SQL_SELECTION_ARGS, arrayOf(album))
            putString(ContentResolver.QUERY_ARG_SQL_SORT_ORDER, "COALESCE(${MediaStore.MediaColumns.DATE_TAKEN}, ${MediaStore.MediaColumns.DATE_ADDED} * 1000) DESC")
            putInt(ContentResolver.QUERY_ARG_LIMIT, limit.coerceIn(1, MAX_LIMIT))
            putInt(ContentResolver.QUERY_ARG_OFFSET, offset.coerceAtLeast(0))
        }
        val projection = arrayOf(
            MediaStore.Files.FileColumns._ID,
            MediaStore.MediaColumns.DISPLAY_NAME,
            MediaStore.MediaColumns.DATE_TAKEN,
            MediaStore.MediaColumns.DATE_ADDED,
            MediaStore.Files.FileColumns.MEDIA_TYPE,
            MediaStore.MediaColumns.DURATION,
        )
        return resolver.query(FILES, projection, query, null)?.use { cursor ->
            buildList {
                while (cursor.moveToNext()) {
                    val id = cursor.getLong(0)
                    val video = cursor.getInt(4) == MediaStore.Files.FileColumns.MEDIA_TYPE_VIDEO
                    val uri = ContentUris.withAppendedId(if (video) VIDEOS else IMAGES, id)
                    val thumbnail = runCatching { thumbnail(resolver, uri) }.getOrNull() ?: continue
                    val time = if (cursor.isNull(2)) cursor.getLong(3) * 1000 else cursor.getLong(2)
                    val duration = if (video && !cursor.isNull(5)) (cursor.getLong(5) / 1000).toInt() else null
                    val key = if (video) "$VIDEO_PREFIX$id" else id.toString()
                    add(GalleryPhoto(key, cursor.getString(1) ?: "$id", time, thumbnail, duration))
                }
            }
        }.orEmpty()
    }

    fun albums(context: Context): List<GalleryAlbum> {
        val selection = "${MediaStore.Files.FileColumns.MEDIA_TYPE} IN (${MediaStore.Files.FileColumns.MEDIA_TYPE_IMAGE}, ${MediaStore.Files.FileColumns.MEDIA_TYPE_VIDEO})"
        val projection = arrayOf(MediaStore.MediaColumns.BUCKET_ID, MediaStore.MediaColumns.BUCKET_DISPLAY_NAME)
        val albums = linkedMapOf<String, GalleryAlbum>()
        context.contentResolver.query(FILES, projection, selection, null, "${MediaStore.MediaColumns.DATE_ADDED} DESC")?.use { cursor ->
            while (cursor.moveToNext()) {
                val id = cursor.getString(0) ?: continue
                val current = albums[id]
                albums[id] = current?.copy(count = current.count + 1) ?: GalleryAlbum(id, cursor.getString(1) ?: id, 1)
            }
        }
        return albums.values.sortedByDescending { it.count }
    }

    fun uri(id: String): Uri? {
        val video = id.startsWith(VIDEO_PREFIX)
        val number = id.removePrefix(VIDEO_PREFIX).toLongOrNull() ?: return null
        return ContentUris.withAppendedId(if (video) VIDEOS else IMAGES, number)
    }

    private fun thumbnail(resolver: ContentResolver, uri: Uri): String {
        val bitmap = resolver.loadThumbnail(uri, Size(THUMBNAIL_PX, THUMBNAIL_PX), null)
        val bytes = ByteArrayOutputStream()
        bitmap.compress(Bitmap.CompressFormat.JPEG, JPEG_QUALITY, bytes)
        bitmap.recycle()
        return Base64.encodeToString(bytes.toByteArray(), Base64.NO_WRAP)
    }
}

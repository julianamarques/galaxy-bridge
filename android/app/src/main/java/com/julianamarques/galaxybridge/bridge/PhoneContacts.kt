package com.julianamarques.galaxybridge.bridge

import android.content.Context
import android.net.Uri
import android.provider.ContactsContract
import android.provider.ContactsContract.CommonDataKinds.Phone
import android.provider.ContactsContract.PhoneLookup
import android.telephony.PhoneNumberUtils
import android.util.Base64
import com.julianamarques.galaxybridge.Permission
import com.julianamarques.galaxybridge.protocol.Contact
import java.text.Normalizer

object PhoneContacts {
    data class Match(val key: String, val name: String)

    private const val ROWS_PER_CONTACT = 4

    fun canRead(context: Context): Boolean = Permission.Contacts.isGranted(context)

    fun search(context: Context, query: String, limit: Int): List<Contact> = read(context, emptyList()) {
        val uri = Uri.withAppendedPath(Phone.CONTENT_FILTER_URI, Uri.encode(query)).buildUpon()
            .appendQueryParameter(ContactsContract.LIMIT_PARAM_KEY, (limit * ROWS_PER_CONTACT).toString())
            .build()
        val projection = arrayOf(Phone.LOOKUP_KEY, Phone.DISPLAY_NAME_PRIMARY, Phone.NUMBER, Phone.TYPE, Phone.LABEL, Phone.PHOTO_THUMBNAIL_URI)
        val contacts = LinkedHashMap<String, Contact>()
        context.contentResolver.query(uri, projection, null, null, null)?.use { cursor ->
            while (cursor.moveToNext()) {
                val key = cursor.getString(0) ?: continue
                val name = cursor.getString(1) ?: continue
                val number = cursor.getString(2) ?: continue
                if (key !in contacts && contacts.size >= limit) continue
                val existing = contacts[key] ?: Contact(key, name, emptyList(), hasPhoto = cursor.getString(5) != null)
                if (existing.numbers.any { PhoneNumberUtils.compare(context, it.number, number) }) continue
                val label = Phone.getTypeLabel(context.resources, cursor.getInt(3), cursor.getString(4)).toString()
                contacts[key] = existing.copy(numbers = existing.numbers + Contact.Number(number, label))
            }
        }
        val prefix = normalize(query)
        contacts.values.sortedBy { contact -> normalize(contact.name).split(' ').none { it.startsWith(prefix) } }
    }

    private fun normalize(text: String): String =
        Normalizer.normalize(text.lowercase(), Normalizer.Form.NFD).replace(DIACRITICS, "")

    private val DIACRITICS = "\\p{Mn}+".toRegex()

    fun lookup(context: Context, number: String): Match? = read(context, null) {
        val uri = Uri.withAppendedPath(PhoneLookup.CONTENT_FILTER_URI, Uri.encode(number))
        context.contentResolver.query(uri, arrayOf(PhoneLookup.LOOKUP_KEY, PhoneLookup.DISPLAY_NAME), null, null, null)?.use { cursor ->
            if (cursor.moveToFirst()) Match(cursor.getString(0), cursor.getString(1)) else null
        }
    }

    fun photo(context: Context, key: String): String? = read(context, null) {
        val resolver = context.contentResolver
        val contact = ContactsContract.Contacts.lookupContact(resolver, Uri.withAppendedPath(ContactsContract.Contacts.CONTENT_LOOKUP_URI, key))
        contact?.let { ContactsContract.Contacts.openContactPhotoInputStream(resolver, it, false) }
            ?.use { it.readBytes() }
            ?.let { Base64.encodeToString(it, Base64.NO_WRAP) }
    }

    private inline fun <T> read(context: Context, fallback: T, block: () -> T): T =
        if (canRead(context)) runCatching(block).getOrDefault(fallback) else fallback
}

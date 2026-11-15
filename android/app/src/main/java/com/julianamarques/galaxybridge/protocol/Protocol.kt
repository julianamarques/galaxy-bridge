package com.julianamarques.galaxybridge.protocol

import kotlinx.serialization.KSerializer
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.contentOrNull

const val PROTOCOL_VERSION = 1

@Serializable
data class Hello(
    val version: Int = PROTOCOL_VERSION,
    val appVersion: String,
    val name: String,
    val model: String,
)

@Serializable
data class PairRequest(val secret: String, val name: String, val model: String)

@Serializable
data class PairAccepted(val name: String)

@Serializable
data class PairRejected(val reason: String)

@Serializable
data class PhoneStatus(
    val battery: Battery,
    val networkCountry: String? = null,
    val simCountry: String? = null,
    val carrier: String? = null,
    val signal: Int? = null,
    val network: String? = null,
    val wifi: Int? = null,
    val storage: Storage? = null,
    val dnd: Boolean? = null,
    val accessories: List<Accessory>? = null,
) {
    @Serializable
    data class Battery(val level: Int, val charging: Boolean)

    @Serializable
    data class Accessory(val name: String, val battery: Int, val kind: String? = null) {
        companion object {
            const val HEADPHONES = "headphones"
            const val WATCH = "watch"
            const val OTHER = "other"
        }
    }

    @Serializable
    data class Storage(val free: Long, val total: Long)
}

@Serializable
data class CallPlace(val number: String)

@Serializable
data class CallState(
    val call: String,
    val state: String,
    val direction: String,
    val number: String? = null,
    val name: String? = null,
    val contact: String? = null,
    val declined: Boolean? = null,
) {
    companion object {
        const val RINGING = "ringing"
        const val ACTIVE = "active"
        const val VOICEMAIL = "voicemail"
        const val ENDED = "ended"
        const val INCOMING = "incoming"
        const val OUTGOING = "outgoing"
    }
}

@Serializable
data class CallID(val call: String)

@Serializable
data class ContactsSearch(val query: String, val limit: Int)

@Serializable
data class Contact(val id: String, val name: String, val numbers: List<Number>, val hasPhoto: Boolean) {
    @Serializable
    data class Number(val number: String, val label: String? = null)
}

@Serializable
data class ContactResults(val contacts: List<Contact>)

@Serializable
data class PhotoRequest(val contact: String)

@Serializable
data class ContactPhoto(val contact: String, val data: String)

@Serializable
data class PhoneNotification(
    val key: String,
    val app: String,
    val appName: String,
    val title: String? = null,
    val text: String? = null,
    val time: Long,
    val actions: List<Action>,
    val silent: Boolean,
    val icon: String? = null,
    val image: String? = null,
) {
    @Serializable
    data class Action(val id: Int, val title: String, val reply: Boolean)
}

@Serializable
data class NotificationKey(val key: String)

@Serializable
data class NotificationKeys(val keys: List<String>)

@Serializable
data class NotificationAction(val key: String, val action: Int, val reply: String? = null)

@Serializable
data class NotificationFilter(val muted: List<String>)

@Serializable
data class TransferFile(
    val id: String,
    val name: String,
    val size: Long,
    val mime: String? = null,
    val folder: String? = null,
    val capture: Boolean? = null,
)

@Serializable
data class TransferID(val id: String)

@Serializable
data class TransferChunk(val id: String, val data: String)

@Serializable
data class TransferResult(val id: String, val ok: Boolean, val message: String? = null)

@Serializable
data class Clipboard(val text: String) {
    companion object {
        const val MAX_LENGTH = 100_000
    }
}

@Serializable
data class Ring(val on: Boolean)

@Serializable
data class RecentCall(
    val number: String? = null,
    val name: String? = null,
    val contact: String? = null,
    val kind: String,
    val time: Long,
    val duration: Int,
) {
    companion object {
        const val INCOMING = "incoming"
        const val OUTGOING = "outgoing"
        const val MISSED = "missed"
        const val DECLINED = "declined"
    }
}

@Serializable
data class RecentCalls(val calls: List<RecentCall>)

@Serializable
data class GalleryRequest(val limit: Int, val offset: Int? = null, val album: String? = null, val videos: Boolean? = null)

@Serializable
data class GalleryPhoto(val id: String, val name: String, val time: Long, val thumbnail: String, val duration: Int? = null)

@Serializable
data class GalleryAlbum(val id: String, val name: String, val count: Int)

@Serializable
data class GalleryAlbums(val albums: List<GalleryAlbum>)

@Serializable
data class GalleryResults(val photos: List<GalleryPhoto>)

@Serializable
data class GalleryID(val id: String)

@Serializable
data class Link(val url: String)

@Serializable
data class MediaState(
    val app: String? = null,
    val appName: String? = null,
    val title: String? = null,
    val artist: String? = null,
    val playing: Boolean,
    val artwork: String? = null,
)

@Serializable
data class MediaControl(val action: String) {
    companion object {
        const val PLAY = "play"
        const val PAUSE = "pause"
        const val NEXT = "next"
        const val PREVIOUS = "previous"
    }
}

@Serializable
data class DoNotDisturb(val on: Boolean)

@Serializable
data class FilesList(val path: String)

@Serializable
data class PhoneFile(val name: String, val folder: Boolean, val size: Long, val modified: Long)

@Serializable
data class FilesListing(val path: String, val files: List<PhoneFile>)

@Serializable
data class MirrorStart(val maxSize: Int? = null, val bitRate: Int, val audio: Boolean? = null)

@Serializable
data class MirrorState(val state: String, val control: Boolean? = null, val message: String? = null) {
    companion object {
        const val WAITING = "waiting"
        const val RUNNING = "running"
        const val STOPPED = "stopped"
    }
}

@Serializable
data class MirrorStream(val codec: String)

@Serializable
data class MirrorTouch(val action: String, val x: Int, val y: Int, val width: Int, val height: Int) {
    companion object {
        const val DOWN = "down"
        const val MOVE = "move"
        const val UP = "up"
    }
}

@Serializable
data class MirrorScroll(val x: Int, val y: Int, val width: Int, val height: Int, val dx: Double, val dy: Double)

@Serializable
data class MirrorKey(val key: String) {
    companion object {
        const val BACK = "back"
        const val HOME = "home"
        const val RECENTS = "recents"
        const val ENTER = "enter"
        const val DELETE = "delete"
        const val NOTIFICATIONS = "notifications"
        const val COPY = "copy"
        const val CUT = "cut"
    }
}

@Serializable
data class MirrorText(val text: String)

@Serializable
data class BridgeError(val code: String, val message: String)

sealed interface Message {
    val type: String

    data class HelloMessage(val body: Hello) : Message { override val type get() = "hello" }
    data class PairRequestMessage(val body: PairRequest) : Message { override val type get() = "pair.request" }
    data class PairAcceptedMessage(val body: PairAccepted) : Message { override val type get() = "pair.accepted" }
    data class PairRejectedMessage(val body: PairRejected) : Message { override val type get() = "pair.rejected" }
    data object Unpair : Message { override val type get() = "unpair" }
    data class StatusMessage(val body: PhoneStatus) : Message { override val type get() = "status" }
    data class CallPlaceMessage(val body: CallPlace) : Message { override val type get() = "call.place" }
    data class CallStateMessage(val body: CallState) : Message { override val type get() = "call.state" }
    data class CallAnswerMessage(val body: CallID) : Message { override val type get() = "call.answer" }
    data class CallDeclineMessage(val body: CallID) : Message { override val type get() = "call.decline" }
    data class CallEndMessage(val body: CallID) : Message { override val type get() = "call.end" }
    data class ContactsSearchMessage(val body: ContactsSearch) : Message { override val type get() = "contacts.search" }
    data class ContactsResultsMessage(val body: ContactResults) : Message { override val type get() = "contacts.results" }
    data class PhotoRequestMessage(val body: PhotoRequest) : Message { override val type get() = "photo.request" }
    data class PhotoMessage(val body: ContactPhoto) : Message { override val type get() = "photo" }
    data class NotificationPostedMessage(val body: PhoneNotification) : Message { override val type get() = "notification.posted" }
    data class NotificationRemovedMessage(val body: NotificationKey) : Message { override val type get() = "notification.removed" }
    data class NotificationActiveMessage(val body: NotificationKeys) : Message { override val type get() = "notification.active" }
    data class NotificationActionMessage(val body: NotificationAction) : Message { override val type get() = "notification.action" }
    data class NotificationDismissMessage(val body: NotificationKey) : Message { override val type get() = "notification.dismiss" }
    data class NotificationFilterMessage(val body: NotificationFilter) : Message { override val type get() = "notification.filter" }
    data class TransferUploadMessage(val body: TransferFile) : Message { override val type get() = "transfer.upload" }
    data class TransferOfferMessage(val body: TransferFile) : Message { override val type get() = "transfer.offer" }
    data class TransferDownloadMessage(val body: TransferID) : Message { override val type get() = "transfer.download" }
    data class TransferChunkMessage(val body: TransferChunk) : Message { override val type get() = "transfer.chunk" }
    data class TransferResultMessage(val body: TransferResult) : Message { override val type get() = "transfer.result" }
    data class ClipboardMessage(val body: Clipboard) : Message { override val type get() = "clipboard" }
    data class RingMessage(val body: Ring) : Message { override val type get() = "ring" }
    data class CallsRecentMessage(val body: RecentCalls) : Message { override val type get() = "calls.recent" }
    data class GalleryRequestMessage(val body: GalleryRequest) : Message { override val type get() = "gallery.request" }
    data class GalleryResultsMessage(val body: GalleryResults) : Message { override val type get() = "gallery.results" }
    data class GalleryImportMessage(val body: GalleryID) : Message { override val type get() = "gallery.import" }
    data class LinkMessage(val body: Link) : Message { override val type get() = "link" }
    data class MediaStateMessage(val body: MediaState) : Message { override val type get() = "media.state" }
    data class MediaControlMessage(val body: MediaControl) : Message { override val type get() = "media.control" }
    data class DndMessage(val body: DoNotDisturb) : Message { override val type get() = "dnd" }
    data class FilesListMessage(val body: FilesList) : Message { override val type get() = "files.list" }
    data class FilesListingMessage(val body: FilesListing) : Message { override val type get() = "files.listing" }
    data class FilesGetMessage(val body: FilesList) : Message { override val type get() = "files.get" }
    data class MirrorStartMessage(val body: MirrorStart) : Message { override val type get() = "mirror.start" }
    data class MirrorStateMessage(val body: MirrorState) : Message { override val type get() = "mirror.state" }
    data class MirrorStreamMessage(val body: MirrorStream) : Message { override val type get() = "mirror.stream" }
    data class MirrorTouchMessage(val body: MirrorTouch) : Message { override val type get() = "mirror.touch" }
    data class MirrorScrollMessage(val body: MirrorScroll) : Message { override val type get() = "mirror.scroll" }
    data class MirrorKeyMessage(val body: MirrorKey) : Message { override val type get() = "mirror.key" }
    data class MirrorTextMessage(val body: MirrorText) : Message { override val type get() = "mirror.text" }
    data object MirrorStop : Message { override val type get() = "mirror.stop" }
    data object GalleryAlbumsRequest : Message { override val type get() = "gallery.albums" }
    data object CameraCapture : Message { override val type get() = "camera.capture" }
    data class GalleryAlbumListMessage(val body: GalleryAlbums) : Message { override val type get() = "gallery.albumList" }
    data object MirrorSync : Message { override val type get() = "mirror.sync" }
    data class ErrorMessage(val body: BridgeError) : Message { override val type get() = "error" }
    data object Ping : Message { override val type get() = "ping" }
    data object Pong : Message { override val type get() = "pong" }

    data class Unknown(override val type: String) : Message
}

data class Envelope(val message: Message, val id: String? = null, val replyTo: String? = null)

object Codec {
    private val json = Json {
        ignoreUnknownKeys = true
        explicitNulls = false
        encodeDefaults = true
    }

    fun encode(envelope: Envelope): String = buildJsonObject {
        put("type", JsonPrimitive(envelope.message.type))
        envelope.id?.let { put("id", JsonPrimitive(it)) }
        envelope.replyTo?.let { put("replyTo", JsonPrimitive(it)) }
        body(envelope.message)?.let { put("body", it) }
    }.toString()

    fun decode(text: String): Envelope {
        val root = json.parseToJsonElement(text).jsonObject
        val type = root.getValue("type").jsonPrimitive.content
        val body = root["body"]
        fun <T> body(serializer: KSerializer<T>): T = json.decodeFromJsonElement(serializer, body ?: JsonObject(emptyMap()))
        val message = when (type) {
            "hello" -> Message.HelloMessage(body(Hello.serializer()))
            "pair.request" -> Message.PairRequestMessage(body(PairRequest.serializer()))
            "pair.accepted" -> Message.PairAcceptedMessage(body(PairAccepted.serializer()))
            "pair.rejected" -> Message.PairRejectedMessage(body(PairRejected.serializer()))
            "unpair" -> Message.Unpair
            "status" -> Message.StatusMessage(body(PhoneStatus.serializer()))
            "call.place" -> Message.CallPlaceMessage(body(CallPlace.serializer()))
            "call.state" -> Message.CallStateMessage(body(CallState.serializer()))
            "call.answer" -> Message.CallAnswerMessage(body(CallID.serializer()))
            "call.decline" -> Message.CallDeclineMessage(body(CallID.serializer()))
            "call.end" -> Message.CallEndMessage(body(CallID.serializer()))
            "contacts.search" -> Message.ContactsSearchMessage(body(ContactsSearch.serializer()))
            "contacts.results" -> Message.ContactsResultsMessage(body(ContactResults.serializer()))
            "photo.request" -> Message.PhotoRequestMessage(body(PhotoRequest.serializer()))
            "photo" -> Message.PhotoMessage(body(ContactPhoto.serializer()))
            "notification.posted" -> Message.NotificationPostedMessage(body(PhoneNotification.serializer()))
            "notification.removed" -> Message.NotificationRemovedMessage(body(NotificationKey.serializer()))
            "notification.active" -> Message.NotificationActiveMessage(body(NotificationKeys.serializer()))
            "notification.action" -> Message.NotificationActionMessage(body(NotificationAction.serializer()))
            "notification.dismiss" -> Message.NotificationDismissMessage(body(NotificationKey.serializer()))
            "notification.filter" -> Message.NotificationFilterMessage(body(NotificationFilter.serializer()))
            "transfer.upload" -> Message.TransferUploadMessage(body(TransferFile.serializer()))
            "transfer.offer" -> Message.TransferOfferMessage(body(TransferFile.serializer()))
            "transfer.download" -> Message.TransferDownloadMessage(body(TransferID.serializer()))
            "transfer.chunk" -> Message.TransferChunkMessage(body(TransferChunk.serializer()))
            "transfer.result" -> Message.TransferResultMessage(body(TransferResult.serializer()))
            "clipboard" -> Message.ClipboardMessage(body(Clipboard.serializer()))
            "ring" -> Message.RingMessage(body(Ring.serializer()))
            "calls.recent" -> Message.CallsRecentMessage(body(RecentCalls.serializer()))
            "gallery.request" -> Message.GalleryRequestMessage(body(GalleryRequest.serializer()))
            "gallery.results" -> Message.GalleryResultsMessage(body(GalleryResults.serializer()))
            "gallery.import" -> Message.GalleryImportMessage(body(GalleryID.serializer()))
            "link" -> Message.LinkMessage(body(Link.serializer()))
            "media.state" -> Message.MediaStateMessage(body(MediaState.serializer()))
            "media.control" -> Message.MediaControlMessage(body(MediaControl.serializer()))
            "dnd" -> Message.DndMessage(body(DoNotDisturb.serializer()))
            "files.list" -> Message.FilesListMessage(body(FilesList.serializer()))
            "files.listing" -> Message.FilesListingMessage(body(FilesListing.serializer()))
            "files.get" -> Message.FilesGetMessage(body(FilesList.serializer()))
            "mirror.start" -> Message.MirrorStartMessage(body(MirrorStart.serializer()))
            "mirror.state" -> Message.MirrorStateMessage(body(MirrorState.serializer()))
            "mirror.stream" -> Message.MirrorStreamMessage(body(MirrorStream.serializer()))
            "mirror.touch" -> Message.MirrorTouchMessage(body(MirrorTouch.serializer()))
            "mirror.scroll" -> Message.MirrorScrollMessage(body(MirrorScroll.serializer()))
            "mirror.key" -> Message.MirrorKeyMessage(body(MirrorKey.serializer()))
            "mirror.text" -> Message.MirrorTextMessage(body(MirrorText.serializer()))
            "mirror.stop" -> Message.MirrorStop
            "gallery.albums" -> Message.GalleryAlbumsRequest
            "camera.capture" -> Message.CameraCapture
            "gallery.albumList" -> Message.GalleryAlbumListMessage(body(GalleryAlbums.serializer()))
            "mirror.sync" -> Message.MirrorSync
            "error" -> Message.ErrorMessage(body(BridgeError.serializer()))
            "ping" -> Message.Ping
            "pong" -> Message.Pong
            else -> Message.Unknown(type)
        }
        return Envelope(
            message = message,
            id = root["id"]?.jsonPrimitive?.contentOrNull,
            replyTo = root["replyTo"]?.jsonPrimitive?.contentOrNull,
        )
    }

    private fun body(message: Message) = when (message) {
        is Message.HelloMessage -> json.encodeToJsonElement(Hello.serializer(), message.body)
        is Message.PairRequestMessage -> json.encodeToJsonElement(PairRequest.serializer(), message.body)
        is Message.PairAcceptedMessage -> json.encodeToJsonElement(PairAccepted.serializer(), message.body)
        is Message.PairRejectedMessage -> json.encodeToJsonElement(PairRejected.serializer(), message.body)
        is Message.StatusMessage -> json.encodeToJsonElement(PhoneStatus.serializer(), message.body)
        is Message.CallPlaceMessage -> json.encodeToJsonElement(CallPlace.serializer(), message.body)
        is Message.CallStateMessage -> json.encodeToJsonElement(CallState.serializer(), message.body)
        is Message.CallAnswerMessage -> json.encodeToJsonElement(CallID.serializer(), message.body)
        is Message.CallDeclineMessage -> json.encodeToJsonElement(CallID.serializer(), message.body)
        is Message.CallEndMessage -> json.encodeToJsonElement(CallID.serializer(), message.body)
        is Message.ContactsSearchMessage -> json.encodeToJsonElement(ContactsSearch.serializer(), message.body)
        is Message.ContactsResultsMessage -> json.encodeToJsonElement(ContactResults.serializer(), message.body)
        is Message.PhotoRequestMessage -> json.encodeToJsonElement(PhotoRequest.serializer(), message.body)
        is Message.PhotoMessage -> json.encodeToJsonElement(ContactPhoto.serializer(), message.body)
        is Message.NotificationPostedMessage -> json.encodeToJsonElement(PhoneNotification.serializer(), message.body)
        is Message.NotificationRemovedMessage -> json.encodeToJsonElement(NotificationKey.serializer(), message.body)
        is Message.NotificationActiveMessage -> json.encodeToJsonElement(NotificationKeys.serializer(), message.body)
        is Message.NotificationActionMessage -> json.encodeToJsonElement(NotificationAction.serializer(), message.body)
        is Message.NotificationDismissMessage -> json.encodeToJsonElement(NotificationKey.serializer(), message.body)
        is Message.NotificationFilterMessage -> json.encodeToJsonElement(NotificationFilter.serializer(), message.body)
        is Message.TransferUploadMessage -> json.encodeToJsonElement(TransferFile.serializer(), message.body)
        is Message.TransferOfferMessage -> json.encodeToJsonElement(TransferFile.serializer(), message.body)
        is Message.TransferDownloadMessage -> json.encodeToJsonElement(TransferID.serializer(), message.body)
        is Message.TransferChunkMessage -> json.encodeToJsonElement(TransferChunk.serializer(), message.body)
        is Message.TransferResultMessage -> json.encodeToJsonElement(TransferResult.serializer(), message.body)
        is Message.ClipboardMessage -> json.encodeToJsonElement(Clipboard.serializer(), message.body)
        is Message.RingMessage -> json.encodeToJsonElement(Ring.serializer(), message.body)
        is Message.CallsRecentMessage -> json.encodeToJsonElement(RecentCalls.serializer(), message.body)
        is Message.GalleryRequestMessage -> json.encodeToJsonElement(GalleryRequest.serializer(), message.body)
        is Message.GalleryResultsMessage -> json.encodeToJsonElement(GalleryResults.serializer(), message.body)
        is Message.GalleryImportMessage -> json.encodeToJsonElement(GalleryID.serializer(), message.body)
        is Message.LinkMessage -> json.encodeToJsonElement(Link.serializer(), message.body)
        is Message.MediaStateMessage -> json.encodeToJsonElement(MediaState.serializer(), message.body)
        is Message.MediaControlMessage -> json.encodeToJsonElement(MediaControl.serializer(), message.body)
        is Message.DndMessage -> json.encodeToJsonElement(DoNotDisturb.serializer(), message.body)
        is Message.FilesListMessage -> json.encodeToJsonElement(FilesList.serializer(), message.body)
        is Message.FilesListingMessage -> json.encodeToJsonElement(FilesListing.serializer(), message.body)
        is Message.FilesGetMessage -> json.encodeToJsonElement(FilesList.serializer(), message.body)
        is Message.MirrorStartMessage -> json.encodeToJsonElement(MirrorStart.serializer(), message.body)
        is Message.MirrorStateMessage -> json.encodeToJsonElement(MirrorState.serializer(), message.body)
        is Message.MirrorStreamMessage -> json.encodeToJsonElement(MirrorStream.serializer(), message.body)
        is Message.MirrorTouchMessage -> json.encodeToJsonElement(MirrorTouch.serializer(), message.body)
        is Message.MirrorScrollMessage -> json.encodeToJsonElement(MirrorScroll.serializer(), message.body)
        is Message.MirrorKeyMessage -> json.encodeToJsonElement(MirrorKey.serializer(), message.body)
        is Message.MirrorTextMessage -> json.encodeToJsonElement(MirrorText.serializer(), message.body)
        is Message.ErrorMessage -> json.encodeToJsonElement(BridgeError.serializer(), message.body)
        is Message.GalleryAlbumListMessage -> json.encodeToJsonElement(GalleryAlbums.serializer(), message.body)
        Message.Unpair, Message.Ping, Message.Pong, Message.MirrorStop, Message.MirrorSync,
        Message.GalleryAlbumsRequest, Message.CameraCapture, is Message.Unknown -> null
    }
}

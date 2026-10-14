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
) {
    @Serializable
    data class Battery(val level: Int, val charging: Boolean)
}

@Serializable
data class CallPlace(val number: String)

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
        is Message.ErrorMessage -> json.encodeToJsonElement(BridgeError.serializer(), message.body)
        Message.Unpair, Message.Ping, Message.Pong, is Message.Unknown -> null
    }
}

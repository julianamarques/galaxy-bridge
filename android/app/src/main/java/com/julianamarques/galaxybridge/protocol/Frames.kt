package com.julianamarques.galaxybridge.protocol

import java.io.DataInputStream
import java.io.DataOutputStream
import java.io.IOException
import java.nio.ByteBuffer

object Frames {
    const val MAX_LENGTH = 1 shl 20
    const val MAX_VIDEO_LENGTH = 1 shl 24

    class TooLarge(size: Int) : IOException("Mensagem grande demais: $size bytes")

    fun write(output: DataOutputStream, envelope: Envelope) {
        val body = Codec.encode(envelope).toByteArray(Charsets.UTF_8)
        if (body.size > MAX_LENGTH) throw TooLarge(body.size)
        output.writeInt(body.size)
        output.write(body)
        output.flush()
    }

    const val PREFIX = 4

    fun framed(bodyLength: Int): ByteArray {
        if (bodyLength > MAX_VIDEO_LENGTH) throw TooLarge(bodyLength)
        return ByteArray(PREFIX + bodyLength).also { ByteBuffer.wrap(it).putInt(bodyLength) }
    }

    fun read(input: DataInputStream): Envelope {
        val length = input.readInt()
        if (length < 0 || length > MAX_LENGTH) throw IOException("Tamanho de mensagem inválido: $length")
        val body = ByteArray(length).also(input::readFully)
        return try {
            Codec.decode(String(body, Charsets.UTF_8))
        } catch (e: RuntimeException) {
            Envelope(Message.Unknown(e.javaClass.simpleName))
        }
    }
}

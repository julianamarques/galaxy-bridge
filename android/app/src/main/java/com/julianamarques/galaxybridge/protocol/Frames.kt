package com.julianamarques.galaxybridge.protocol

import java.io.DataInputStream
import java.io.DataOutputStream
import java.io.IOException

object Frames {
    const val MAX_LENGTH = 1 shl 20

    fun write(output: DataOutputStream, envelope: Envelope) {
        val body = Codec.encode(envelope).toByteArray(Charsets.UTF_8)
        if (body.size > MAX_LENGTH) throw IOException("Mensagem grande demais: ${body.size} bytes")
        output.writeInt(body.size)
        output.write(body)
        output.flush()
    }

    fun writeRaw(output: DataOutputStream, body: ByteArray, length: Int = body.size) {
        if (length > MAX_LENGTH) throw IOException("Quadro grande demais: $length bytes")
        output.writeInt(length)
        output.write(body, 0, length)
        output.flush()
    }

    fun read(input: DataInputStream): Envelope {
        val length = input.readInt()
        if (length < 0 || length > MAX_LENGTH) throw IOException("Tamanho de mensagem inválido: $length")
        val body = ByteArray(length).also(input::readFully)
        return Codec.decode(String(body, Charsets.UTF_8))
    }
}

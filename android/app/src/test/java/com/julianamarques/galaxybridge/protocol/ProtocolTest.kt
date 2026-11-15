package com.julianamarques.galaxybridge.protocol

import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.io.DataInputStream
import java.io.DataOutputStream
import java.io.File
import java.io.IOException
import kotlinx.serialization.json.Json
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test

class ProtocolTest {
    private val fixtures = File("../../protocol/fixtures").listFiles { file -> file.extension == "json" }.orEmpty().sorted()

    @Test
    fun fixturesExist() {
        assertTrue("Exemplos não encontrados em ${File("../../protocol/fixtures").absolutePath}", fixtures.size >= 67)
    }

    @Test
    fun fixturesRoundTrip() {
        for (file in fixtures) {
            val text = file.readText()
            val envelope = Codec.decode(text)
            assertFalse("${file.name} não foi reconhecida", envelope.message is Message.Unknown)
            assertTrue(file.name, file.name.startsWith(envelope.message.type + "."))
            assertEquals(file.name, Json.parseToJsonElement(text), Json.parseToJsonElement(Codec.encode(envelope)))
        }
    }

    @Test
    fun ignoresUnknownTypesAndFields() {
        assertEquals(Message.Unknown("future.thing"), Codec.decode("""{"type":"future.thing","body":{"x":1}}""").message)
        val status = Codec.decode("""{"type":"status","body":{"battery":{"level":5,"charging":true,"temp":30},"future":"x"}}""")
        assertEquals(Message.StatusMessage(PhoneStatus(PhoneStatus.Battery(5, true))), status.message)
    }

    @Test
    fun leavesOutEmptyFields() {
        assertEquals("""{"type":"ping"}""", Codec.encode(Envelope(Message.Ping)))
        assertEquals(
            """{"type":"status","body":{"battery":{"level":9,"charging":false}}}""",
            Codec.encode(Envelope(Message.StatusMessage(PhoneStatus(PhoneStatus.Battery(9, false))))),
        )
    }

    @Test
    fun framesRoundTrip() {
        val bytes = ByteArrayOutputStream()
        val output = DataOutputStream(bytes)
        Frames.write(output, Envelope(Message.Ping))
        Frames.write(output, Envelope(Message.CallPlaceMessage(CallPlace("+5586999990001")), id = "1"))
        val input = DataInputStream(ByteArrayInputStream(bytes.toByteArray()))
        assertEquals(Envelope(Message.Ping), Frames.read(input))
        assertEquals(Envelope(Message.CallPlaceMessage(CallPlace("+5586999990001")), id = "1"), Frames.read(input))
    }

    @Test
    fun rejectsOversizedFrames() {
        val input = DataInputStream(ByteArrayInputStream(byteArrayOf(0x02, 0, 0, 0, 0x7b)))
        assertThrows(IOException::class.java) { Frames.read(input) }
    }
}

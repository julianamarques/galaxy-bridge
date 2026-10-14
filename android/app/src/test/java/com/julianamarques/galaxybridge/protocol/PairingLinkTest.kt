package com.julianamarques.galaxybridge.protocol

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class PairingLinkTest {
    private val fingerprint = "ab".repeat(32)

    @Test
    fun parsesTheMacLink() {
        val link = PairingLink.parse("galaxybridge://pair?v=1&host=192.168.1.20&port=52800&fp=$fingerprint&token=q3HcKk0b5mJ8b1yZ1Xr7Ag")
        assertEquals(PairingLink("192.168.1.20", 52800, fingerprint, "q3HcKk0b5mJ8b1yZ1Xr7Ag"), link)
    }

    @Test
    fun rejectsOtherVersionsAndBrokenLinks() {
        assertNull(PairingLink.parse("galaxybridge://pair?v=2&host=a&port=1&fp=$fingerprint&token=t"))
        assertNull(PairingLink.parse("galaxybridge://pair?v=1&host=a&port=1"))
        assertNull(PairingLink.parse("galaxybridge://pair?v=1&host=a&port=99999&fp=$fingerprint&token=t"))
        assertNull(PairingLink.parse("WIFI:T:ADB;S:studio;P:x;;"))
        assertNull(PairingLink.parse("https://example.com"))
    }
}

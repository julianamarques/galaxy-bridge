package com.julianamarques.galaxybridge.bridge

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class SharedLinkTest {
    @Test
    fun findsASharedLink() {
        assertEquals("https://youtu.be/abc123", SharedLink.find("https://youtu.be/abc123"))
        assertEquals("https://g1.globo.com/noticia.ghtml", SharedLink.find("Veja esta notícia: https://g1.globo.com/noticia.ghtml."))
        assertEquals("http://example.com/a?b=1", SharedLink.find("  http://example.com/a?b=1\n"))
    }

    @Test
    fun ignoresTextThatIsNotALink() {
        assertNull(SharedLink.find("Comprar pão e leite"))
        assertNull(SharedLink.find("https://a.com e https://b.com"))
        assertNull(SharedLink.find("https://a.com " + "texto longo ".repeat(20)))
    }
}

package net.lctechnology.streamdeck.shared

import kotlin.test.Test
import kotlin.test.assertTrue

class PlatformTest {
    @Test
    fun platformName_isNotEmpty() {
        assertTrue(platformName().isNotEmpty())
    }
}

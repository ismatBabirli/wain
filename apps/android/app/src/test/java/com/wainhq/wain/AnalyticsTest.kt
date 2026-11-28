package com.wainhq.wain

import com.wainhq.wain.store.Analytics
import com.wainhq.wain.wire.arr
import com.wainhq.wain.wire.get
import com.wainhq.wain.wire.int
import com.wainhq.wain.wire.str
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Test

class AnalyticsTest {
    private fun frame(cls: String, method: String, file: String?, line: Int) = StackTraceElement(cls, method, file, line)

    @Test
    fun aCrashCarriesItsTypeAndOurOwnFramesOutermostFirst() {
        val e = IllegalStateException("could not open /Users/someone/secret.txt").apply {
            stackTrace = arrayOf(
                frame("kotlin.collections.CollectionsKt", "first", "Collections.kt", 10),
                frame("com.wainhq.wain.ui.SettingsKt", "Privacy", "Settings.kt", 42),
                frame("com.wainhq.wain.ui.AppKt", "App", "App.kt", 7),
                frame("android.os.Looper", "loop", "Looper.java", 200),
            )
        }
        val props = Analytics.crash(e, "2026-11-28T17:00:00Z")
        val ex = props["\$exception_list"].arr.single()
        assertEquals("java.lang.IllegalStateException", ex["type"].str)
        assertEquals("crash at Settings.kt:42", ex["value"].str)
        val frames = ex["stacktrace"]["frames"].arr
        assertEquals(listOf("com.wainhq.wain.ui.AppKt.App", "com.wainhq.wain.ui.SettingsKt.Privacy"), frames.map { it["function"].str })
        assertEquals(42, frames.last()["lineno"].int)
        // The message is free text and may name a path: it never leaves the phone.
        assertFalse(props.toString().contains("secret"))
    }

    @Test
    fun framesComeFromTheCauseWhenTheWrapperHasNone() {
        val cause = RuntimeException().apply { stackTrace = arrayOf(frame("com.wainhq.wain.store.Store", "load", "Store.kt", 3)) }
        val e = RuntimeException(cause).apply { stackTrace = arrayOf(frame("java.lang.Thread", "run", "Thread.java", 1)) }
        val ex = Analytics.crash(e, "t")["\$exception_list"].arr.single()
        assertEquals(listOf("com.wainhq.wain.store.Store.load"), ex["stacktrace"]["frames"].arr.map { it["function"].str })
    }
}

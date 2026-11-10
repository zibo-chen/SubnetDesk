package com.carriez.flutter_hbb

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.json.JSONObject
import org.junit.After
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File
import java.security.KeyStore

@RunWith(AndroidJUnit4::class)
class LanCredentialStoreTest {
    private val context = InstrumentationRegistry.getInstrumentation().targetContext
    private val store = LanCredentialStore(context)
    private val first = "a".repeat(64)
    private val second = "b".repeat(64)
    private val directory = File(context.noBackupFilesDir, "lan-credentials")

    @After fun cleanup() {
        store.delete(first)
        store.delete(second)
    }

    @Test fun survivesStoreRecreationWithoutPlaintextOnDisk() {
        store.save(first, "alice", "密碼 with spaces!")
        val persisted = File(directory, "$first.cred").readText()
        assertFalse(persisted.contains("alice"))
        assertFalse(persisted.contains("密碼 with spaces!"))
        val loaded = JSONObject(LanCredentialStore(context).load(first)!!)
        assertEquals("alice", loaded.getString("username"))
        assertEquals("密碼 with spaces!", loaded.getString("password"))
        assertTrue(store.list().contains(first))
        // Recover a legacy AtomicFile backup left by an interrupted update.
        val target = File(directory, "$first.cred")
        assertTrue(target.renameTo(File(directory, "$first.cred.bak")))
        assertTrue(store.list().contains(first))
        assertEquals("alice", JSONObject(LanCredentialStore(context).load(first)!!).getString("username"))
    }

    @Test fun deviceBindingRejectsCopiedCiphertext() {
        store.save(first, "alice", "correct horse")
        File(directory, "$first.cred").copyTo(File(directory, "$second.cred"), overwrite = true)
        try {
            store.load(second)
            fail("Ciphertext must be bound to its device fingerprint")
        } catch (_: java.security.GeneralSecurityException) { }
        // The original record is still readable after a failed decryption.
        assertEquals("alice", JSONObject(store.load(first)!!).getString("username"))
    }

    @Test fun updatesAreIsolatedAndDeletionSurvivesRecreation() {
        store.save(first, "alice", "old password")
        store.save(second, "bob", "different password")
        store.save(first, "alice", "new password")
        assertEquals("new password", JSONObject(store.load(first)!!).getString("password"))
        assertEquals("different password", JSONObject(store.load(second)!!).getString("password"))
        store.delete(first)
        assertNull(LanCredentialStore(context).load(first))
        assertFalse(store.list().contains(first))
        store.delete(first) // Missing entries are harmless.
    }

    @Test fun freshEncryptionUsesDifferentCiphertextAndCorruptEntriesCanBeForgotten() {
        store.save(first, "alice", "same password")
        val target = File(directory, "$first.cred")
        val previous = target.readText()
        store.save(first, "alice", "same password")
        assertNotEquals(previous, target.readText())
        target.writeText("corrupt record")
        try {
            store.load(first)
            fail("Corrupt credentials must never be used")
        } catch (_: org.json.JSONException) { }
        assertTrue(store.list().contains(first))
        store.delete(first)
        assertNull(store.load(first))
    }

    @Test fun missingKeyDoesNotSilentlyReplaceCredentials() {
        store.save(first, "alice", "password")
        val keys = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        keys.deleteEntry("com.zibochen.subnetdesk.lan-credentials.v1")
        try {
            store.load(first)
            fail("An invalidated key must require reauthentication")
        } catch (_: IllegalStateException) { }
        assertTrue(store.list().contains(first)) // It can still be forgotten.
        store.delete(first)
        store.save(first, "alice", "replacement")
        assertEquals("replacement", JSONObject(store.load(first)!!).getString("password"))
    }

    @Test fun invalidDeviceIdentifiersCannotEscapeStoreDirectory() {
        for (invalid in listOf("", "../outside", "c".repeat(63), "G".repeat(64))) {
            try {
                store.save(invalid, "alice", "password")
                fail("Invalid fingerprint was accepted")
            } catch (_: IllegalArgumentException) { }
        }
    }
}

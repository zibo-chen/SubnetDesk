package com.carriez.flutter_hbb

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.AtomicFile
import android.util.Base64
import org.json.JSONObject
import java.io.File
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/** Secrets stay encrypted in noBackupFilesDir; the AES key never leaves AndroidKeyStore. */
class LanCredentialStore(context: Context) {
    private val directory = File(context.applicationContext.noBackupFilesDir, "lan-credentials")

    companion object {
        private const val KEY_ALIAS = "com.zibochen.subnetdesk.lan-credentials.v1"
        private val lock = Any()
        private val fingerprintPattern = Regex("[0-9a-f]{64}")
    }

    private fun file(fingerprint: String): AtomicFile {
        require(fingerprintPattern.matches(fingerprint)) { "Invalid device fingerprint" }
        return AtomicFile(File(directory, "$fingerprint.cred"))
    }

    private fun key(create: Boolean): SecretKey {
        val store = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        val existing = store.getKey(KEY_ALIAS, null)
        if (existing is SecretKey) return existing
        check(create) { "Saved credential key is unavailable; forget the credential and reconnect" }
        return KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore").apply {
            init(KeyGenParameterSpec.Builder(KEY_ALIAS,
                KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                .setKeySize(256)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setRandomizedEncryptionRequired(true)
                .build())
        }.generateKey()
    }

    fun load(fingerprint: String): String? = synchronized(lock) {
        val target = file(fingerprint)
        // Older Android AtomicFile implementations may leave only the backup after a crash.
        if (!target.baseFile.exists() && !File(target.baseFile.path + ".bak").exists()) {
            return@synchronized null
        }
        val record = JSONObject(String(target.readFully(), Charsets.UTF_8))
        check(record.getInt("version") == 1) { "Unsupported credential format" }
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.DECRYPT_MODE, key(false),
            GCMParameterSpec(128, Base64.decode(record.getString("iv"), Base64.NO_WRAP)))
        cipher.updateAAD(fingerprint.toByteArray(Charsets.UTF_8))
        val plaintext = cipher.doFinal(Base64.decode(record.getString("ciphertext"), Base64.NO_WRAP))
        try { String(plaintext, Charsets.UTF_8) } finally { plaintext.fill(0) }
    }

    fun save(fingerprint: String, username: String, password: String) = synchronized(lock) {
        val target = file(fingerprint)
        require(username.isNotBlank() && password.isNotEmpty()) { "Empty credential" }
        check(directory.isDirectory || directory.mkdirs()) { "Cannot create credential directory" }
        val plaintext = JSONObject().put("username", username).put("password", password)
            .toString().toByteArray(Charsets.UTF_8)
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        val encrypted = try {
            cipher.init(Cipher.ENCRYPT_MODE, key(true))
            cipher.updateAAD(fingerprint.toByteArray(Charsets.UTF_8))
            cipher.doFinal(plaintext)
        } finally { plaintext.fill(0) }
        val record = JSONObject().put("version", 1)
            .put("iv", Base64.encodeToString(cipher.iv, Base64.NO_WRAP))
            .put("ciphertext", Base64.encodeToString(encrypted, Base64.NO_WRAP))
            .toString().toByteArray(Charsets.UTF_8)
        val output = target.startWrite()
        try {
            output.write(record)
            target.finishWrite(output)
        } catch (error: Exception) {
            target.failWrite(output)
            throw error
        }
    }

    fun delete(fingerprint: String) = synchronized(lock) {
        val target = file(fingerprint)
        target.delete()
        check(!target.baseFile.exists() && !File(target.baseFile.path + ".bak").exists()) {
            "Cannot delete saved credential"
        }
        if (list().isEmpty()) {
            // Forgetting the last record also allows recovery from an invalidated key.
            KeyStore.getInstance("AndroidKeyStore").apply { load(null) }.deleteEntry(KEY_ALIAS)
        }
    }

    // Listing does not decrypt secrets, so corrupt or invalidated entries can still be deleted.
    fun list(): List<String> = synchronized(lock) {
        if (!directory.exists()) return@synchronized emptyList()
        val entries = checkNotNull(directory.listFiles()) { "Cannot list saved credentials" }
        entries.filter { it.isFile && (it.name.endsWith(".cred") || it.name.endsWith(".cred.bak")) }
            .map { it.name.removeSuffix(".bak").removeSuffix(".cred") }
            .filter { fingerprintPattern.matches(it) }.distinct().sorted()
    }
}

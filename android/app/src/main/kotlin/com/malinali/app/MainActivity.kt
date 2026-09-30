package app.malinali.l10n

import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.provider.OpenableColumns
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream

class MainActivity : FlutterActivity() {
    private val tag = "MalinaliMainActivity"
    private val channelName = "app.malinali.l10n/audio_open"
    private var audioChannel: MethodChannel? = null
    private val handler = android.os.Handler(android.os.Looper.getMainLooper())

    companion object {
        private var pendingAudioPath: String? = null

        private val audioExtensions = setOf(
            "opus", "ogg", "m4a", "mp3", "wav", "aac", "amr", "3gp", "flac", "wma", "webm",
        )

        fun setPending(path: String?) {
            pendingAudioPath = path
        }

        fun getAndClearPending(): String? {
            val path = pendingAudioPath
            pendingAudioPath = null
            return path
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val path = extractAudioPath(intent)
        if (path != null) {
            setPending(path)
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        audioChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
        audioChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "getPendingAudioPath" -> result.success(getAndClearPending())
                else -> result.notImplemented()
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        val path = extractAudioPath(intent)
        if (path != null) {
            setPending(path)
            notifyDartOfPath(path)
        }
    }

    private fun notifyDartOfPath(path: String) {
        val channel = audioChannel ?: return
        handler.postDelayed({
            channel.invokeMethod("onAudioPath", path)
        }, 500)
    }

    private fun extractAudioPath(intent: Intent?): String? {
        if (intent == null) return null

        val action = intent.action
        Log.i(tag, "extractAudioPath action=$action type=${intent.type} data=${intent.data}")

        // 1. Standard data URI (ACTION_VIEW)
        intent.data?.let { uri ->
            copyUriToCache(uri)?.let { return it }
        }

        // 2. ClipData (common on Samsung / WhatsApp)
        intent.clipData?.let { clip ->
            for (i in 0 until clip.itemCount) {
                clip.getItemAt(i).uri?.let { uri ->
                    copyUriToCache(uri)?.let { return it }
                }
            }
        }

        // 3. ACTION_SEND stream
        if (action == Intent.ACTION_SEND || action == Intent.ACTION_SEND_MULTIPLE) {
            @Suppress("DEPRECATION")
            val uri = intent.getParcelableExtra<Uri>(Intent.EXTRA_STREAM)
            if (uri != null) {
                copyUriToCache(uri)?.let { return it }
            }
        }

        return null
    }

    private fun getDisplayName(uri: Uri): String? {
        var name: String? = null
        if (uri.scheme == "content") {
            try {
                contentResolver.query(uri, null, null, null, null)?.use { cursor ->
                    if (cursor.moveToFirst()) {
                        val index = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                        if (index != -1) {
                            name = cursor.getString(index)
                        }
                    }
                }
            } catch (e: Exception) {
                Log.w(tag, "getDisplayName error: ${e.message}")
            }
        }
        return name ?: uri.lastPathSegment
    }

    private fun looksLikeAudio(displayName: String, mimeType: String?): Boolean {
        val lower = displayName.lowercase()
        val ext = lower.substringAfterLast('.', missingDelimiterValue = "")
        if (ext in audioExtensions) return true
        val mime = mimeType?.lowercase().orEmpty()
        if (mime.startsWith("audio/")) return true
        if (mime == "application/ogg") return true
        // WhatsApp voice notes often arrive as opaque names with octet-stream / */*
        if (lower.contains("ptt") || lower.contains("whatsapp") || lower.contains("audio")) {
            return true
        }
        return false
    }

    private fun copyUriToCache(uri: Uri): String? {
        return try {
            val displayName = getDisplayName(uri) ?: "incoming.opus"
            val mimeType = contentResolver.getType(uri) ?: intent?.type
            Log.i(tag, "copyUriToCache name=$displayName mime=$mimeType uri=$uri")

            if (!looksLikeAudio(displayName, mimeType)) {
                Log.i(tag, "Skipping non-audio share: $displayName ($mimeType)")
                return null
            }

            val lower = displayName.lowercase()
            val hasAudioExt = audioExtensions.any { lower.endsWith(".$it") }
            val safeName = if (hasAudioExt) displayName else "$displayName.opus"

            val outFile = File(cacheDir, "shared_$safeName")
            contentResolver.openInputStream(uri)?.use { input ->
                FileOutputStream(outFile).use { output ->
                    input.copyTo(output)
                }
            } ?: run {
                Log.e(tag, "openInputStream returned null for $uri")
                return null
            }

            outFile.absolutePath
        } catch (e: Exception) {
            Log.e(tag, "copyUriToCache failed: ${e.message}")
            null
        }
    }
}

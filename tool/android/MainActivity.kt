package dev.paperdrive.paperdrive

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.OpenableColumns
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * Riceve i file da "Condividi" (ACTION_SEND / SEND_MULTIPLE) e da "Apri con"
 * (ACTION_VIEW), li copia nella cache dell'app e li passa a Flutter sul
 * canale "paperdrive/share".
 */
class MainActivity : FlutterActivity() {
    private var channel: MethodChannel? = null
    private val pending = mutableListOf<Map<String, String>>()

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val ch = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "paperdrive/share")
        ch.setMethodCallHandler { call, result ->
            when (call.method) {
                "takePending" -> {
                    val out = ArrayList<Map<String, String>>(pending)
                    pending.clear()
                    result.success(out)
                }
                else -> result.notImplemented()
            }
        }
        channel = ch
        handle(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        if (handle(intent)) channel?.invokeMethod("shared", null)
    }

    @Suppress("DEPRECATION")
    private fun streamOf(intent: Intent): Uri? =
        if (Build.VERSION.SDK_INT >= 33) {
            intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
        } else {
            intent.getParcelableExtra(Intent.EXTRA_STREAM) as? Uri
        }

    @Suppress("DEPRECATION")
    private fun streamsOf(intent: Intent): List<Uri> =
        if (Build.VERSION.SDK_INT >= 33) {
            intent.getParcelableArrayListExtra(Intent.EXTRA_STREAM, Uri::class.java) ?: emptyList()
        } else {
            intent.getParcelableArrayListExtra<Uri>(Intent.EXTRA_STREAM) ?: emptyList()
        }

    /** Restituisce true se ha trovato file da importare. */
    private fun handle(intent: Intent?): Boolean {
        if (intent == null) return false
        val uris = mutableListOf<Uri>()
        when (intent.action) {
            Intent.ACTION_SEND -> streamOf(intent)?.let { uris.add(it) }
            Intent.ACTION_SEND_MULTIPLE -> uris.addAll(streamsOf(intent))
            Intent.ACTION_VIEW -> intent.data?.let { uris.add(it) }
        }
        if (uris.isEmpty()) return false
        var found = false
        for (u in uris) {
            copy(u, intent.type)?.let {
                pending.add(it)
                found = true
            }
        }
        // Per non importare di nuovo lo stesso file se l'attività viene ricreata.
        intent.action = Intent.ACTION_MAIN
        return found
    }

    private fun copy(uri: Uri, fallbackType: String?): Map<String, String>? {
        return try {
            var name = "documento"
            contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { c ->
                if (c.moveToFirst()) {
                    val i = c.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                    if (i >= 0) c.getString(i)?.let { name = it }
                }
            }
            if (name == "documento") uri.lastPathSegment?.substringAfterLast('/')?.let { if (it.isNotBlank()) name = it }
            val type = contentResolver.getType(uri) ?: fallbackType ?: ""
            if (!name.contains('.')) {
                name += when {
                    type == "application/pdf" -> ".pdf"
                    type == "image/png" -> ".png"
                    type == "image/webp" -> ".webp"
                    type.startsWith("image/") -> ".jpg"
                    else -> ".pdf"
                }
            }
            val dir = File(cacheDir, "shared").apply { mkdirs() }
            val out = File(dir, System.currentTimeMillis().toString() + "_" + name.replace('/', '_'))
            val input = contentResolver.openInputStream(uri) ?: return null
            input.use { inp -> out.outputStream().use { inp.copyTo(it) } }
            mapOf("path" to out.absolutePath, "name" to name)
        } catch (e: Exception) {
            null
        }
    }
}

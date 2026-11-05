package dev.paperdrive.paperdrive

import android.content.Intent
import android.graphics.Bitmap
import android.graphics.ImageDecoder
import android.net.Uri
import android.os.Build
import android.provider.DocumentsContract
import android.provider.OpenableColumns
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream

/**
 * Riceve i file da "Condividi" (ACTION_SEND / SEND_MULTIPLE) e da "Apri con"
 * (ACTION_VIEW), li copia nella cache dell'app e li passa a Flutter sul
 * canale "paperdrive/share".
 */
class MainActivity : FlutterActivity() {
    private var channel: MethodChannel? = null
    private val pending = mutableListOf<Map<String, String>>()
    private var pickResult: MethodChannel.Result? = null
    private val pickRequest = 4711

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
                // Scelta dei file con il selettore di Android: si tiene il
                // permesso di modificarli, così dopo l'archiviazione si può
                // eliminare l'originale (es. dalla cartella Download).
                "pickDocuments" -> {
                    if (pickResult != null) {
                        result.error("busy", "selezione già in corso", null)
                    } else {
                        pickResult = result
                        val i = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                            addCategory(Intent.CATEGORY_OPENABLE)
                            type = "*/*"
                            putExtra(Intent.EXTRA_ALLOW_MULTIPLE, true)
                            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION or
                                Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)
                        }
                        try {
                            startActivityForResult(i, pickRequest)
                        } catch (e: Exception) {
                            pickResult = null
                            result.error("picker", e.message, null)
                        }
                    }
                }
                // Elimina il file originale (dopo che il documento è su Drive).
                "deleteOriginal" -> {
                    val u = call.argument<String>("uri")
                    if (u == null) {
                        result.success(false)
                    } else {
                        val uri = Uri.parse(u)
                        var ok = false
                        try {
                            ok = DocumentsContract.deleteDocument(contentResolver, uri)
                        } catch (_: Exception) {
                        }
                        if (!ok) {
                            try {
                                ok = contentResolver.delete(uri, null, null) > 0
                            } catch (_: Exception) {
                            }
                        }
                        try {
                            contentResolver.releasePersistableUriPermission(
                                uri, Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
                        } catch (_: Exception) {
                        }
                        result.success(ok)
                    }
                }
                // Immagini che Flutter non legge (HEIC, AVIF, GIF, BMP, WEBP) → JPEG.
                "toJpeg" -> {
                    val src = call.argument<String>("path")
                    val dst = call.argument<String>("out")
                    if (src == null || dst == null) {
                        result.error("args", "path/out mancanti", null)
                    } else {
                        Thread {
                            try {
                                val source = ImageDecoder.createSource(File(src))
                                val bmp = ImageDecoder.decodeBitmap(source) { decoder, _, _ ->
                                    decoder.allocator = ImageDecoder.ALLOCATOR_SOFTWARE
                                }
                                FileOutputStream(dst).use { bmp.compress(Bitmap.CompressFormat.JPEG, 92, it) }
                                bmp.recycle()
                                runOnUiThread { result.success(true) }
                            } catch (e: Exception) {
                                runOnUiThread { result.error("decode", e.message, null) }
                            }
                        }.start()
                    }
                }
                else -> result.notImplemented()
            }
        }
        channel = ch
        handle(intent)
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != pickRequest) return
        val res = pickResult ?: return
        pickResult = null
        if (resultCode != RESULT_OK || data == null) {
            res.success(ArrayList<Map<String, String>>())
            return
        }
        val uris = mutableListOf<Uri>()
        data.clipData?.let { clip -> for (k in 0 until clip.itemCount) uris.add(clip.getItemAt(k).uri) }
        if (uris.isEmpty()) data.data?.let { uris.add(it) }
        Thread {
            val out = ArrayList<Map<String, String>>()
            for (u in uris) {
                try {
                    contentResolver.takePersistableUriPermission(
                        u, Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
                } catch (_: Exception) {
                    try {
                        contentResolver.takePersistableUriPermission(u, Intent.FLAG_GRANT_READ_URI_PERMISSION)
                    } catch (_: Exception) {
                    }
                }
                copy(u, null)?.let { out.add(it) }
            }
            runOnUiThread { res.success(out) }
        }.start()
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
                    type == "image/heic" || type == "image/heif" -> ".heic"
                    type == "image/tiff" -> ".tif"
                    type.startsWith("image/") -> ".jpg"
                    type == "message/rfc822" -> ".eml"
                    type == "text/plain" -> ".txt"
                    type == "text/csv" -> ".csv"
                    type == "text/html" -> ".html"
                    type == "application/rtf" -> ".rtf"
                    type == "application/msword" -> ".doc"
                    type == "application/vnd.ms-excel" -> ".xls"
                    type == "application/vnd.ms-powerpoint" -> ".ppt"
                    type.endsWith("wordprocessingml.document") -> ".docx"
                    type.endsWith("spreadsheetml.sheet") -> ".xlsx"
                    type.endsWith("presentationml.presentation") -> ".pptx"
                    type.endsWith("opendocument.text") -> ".odt"
                    type.endsWith("opendocument.spreadsheet") -> ".ods"
                    type.endsWith("opendocument.presentation") -> ".odp"
                    else -> ".pdf"
                }
            }
            val dir = File(cacheDir, "shared").apply { mkdirs() }
            val out = File(dir, System.currentTimeMillis().toString() + "_" + name.replace('/', '_'))
            val input = contentResolver.openInputStream(uri) ?: return null
            input.use { inp -> out.outputStream().use { inp.copyTo(it) } }
            mapOf("path" to out.absolutePath, "name" to name, "uri" to uri.toString())
        } catch (e: Exception) {
            null
        }
    }
}

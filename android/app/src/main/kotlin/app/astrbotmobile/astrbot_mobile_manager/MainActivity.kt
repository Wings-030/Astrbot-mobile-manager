// SPDX-License-Identifier: AGPL-3.0-or-later
package app.astrbotmobile.astrbot_mobile_manager

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.webkit.CookieManager
import android.webkit.MimeTypeMap
import android.webkit.URLUtil
import android.webkit.WebView
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugins.webviewflutter.WebViewFlutterAndroidExternalApi
import java.io.File
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    private val filesExecutor = Executors.newSingleThreadExecutor()
    private var pickerResult: MethodChannel.Result? = null
    private var saving: SaveRequest? = null

    private data class SaveRequest(val file: File, val result: MethodChannel.Result)

    override fun configureFlutterEngine(engine: FlutterEngine) {
        super.configureFlutterEngine(engine)
        WebView.setWebContentsDebuggingEnabled(false)
        val channel = MethodChannel(engine.dartExecutor.binaryMessenger, "app.astrbotmobile/web_files")
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "attach" -> attachDownloads(engine, channel, call, result)
                "pickFiles" -> pickFiles(call, result)
                "saveFile" -> saveFile(call, result)
                else -> result.notImplemented()
            }
        }
    }

    @Suppress("DEPRECATION")
    private fun attachDownloads(
        engine: FlutterEngine,
        channel: MethodChannel,
        call: MethodCall,
        result: MethodChannel.Result,
    ) {
        val id = call.argument<Number>("id")?.toLong()
        val port = call.argument<Int>("port")
        val view = id?.let { WebViewFlutterAndroidExternalApi.getWebView(engine, it) }
        if (view == null || port == null) {
            result.error("missing_webview", null, null)
            return
        }
        fun isLocal(url: String?): Boolean {
            val uri = url?.let(Uri::parse) ?: return false
            return uri.scheme == "http" && uri.host == "127.0.0.1" &&
                uri.port == port && uri.userInfo == null
        }
        view.setDownloadListener { url, agent, disposition, mime, _ ->
            if (isLocal(url) && isLocal(view.url)) {
                channel.invokeMethod("attachment", mapOf(
                    "id" to id,
                    "url" to url,
                    "userAgent" to agent,
                    "cookie" to CookieManager.getInstance().getCookie(url),
                    "filename" to URLUtil.guessFileName(url, disposition, mime),
                ))
            }
        }
        result.success(null)
    }

    @Suppress("DEPRECATION")
    private fun pickFiles(call: MethodCall, result: MethodChannel.Result) {
        if (pickerResult != null || saving != null) {
            result.success(emptyList<String>())
            return
        }
        val mimeTypes = call.argument<List<String>>("accept").orEmpty()
            .flatMap { it.split(',') }
            .mapNotNull { value ->
                val item = value.trim().lowercase()
                if (item.startsWith(".")) {
                    MimeTypeMap.getSingleton().getMimeTypeFromExtension(item.drop(1))
                } else {
                    item.takeIf { '/' in it }
                }
            }.distinct()
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = mimeTypes.singleOrNull() ?: "*/*"
            if (mimeTypes.size > 1) putExtra(Intent.EXTRA_MIME_TYPES, mimeTypes.toTypedArray())
            putExtra(Intent.EXTRA_ALLOW_MULTIPLE, call.argument<Boolean>("multiple") == true)
        }
        pickerResult = result
        try {
            startActivityForResult(intent, SELECT_FILES)
        } catch (_: android.content.ActivityNotFoundException) {
            pickerResult = null
            result.error("no_document_picker", null, null)
        }
    }

    @Suppress("DEPRECATION")
    private fun saveFile(call: MethodCall, result: MethodChannel.Result) {
        val path = call.argument<String>("path")
        val filename = call.argument<String>("name")
        val file = path?.let(::File)
        if (saving != null || pickerResult != null || file == null || filename.isNullOrEmpty() ||
            !file.canonicalPath.startsWith(cacheDir.canonicalPath + File.separator)
        ) {
            result.error("invalid_export", null, null)
            return
        }
        val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = MimeTypeMap.getSingleton().getMimeTypeFromExtension(
                filename.substringAfterLast('.', "").lowercase()
            ) ?: "application/octet-stream"
            putExtra(Intent.EXTRA_TITLE, filename)
        }
        saving = SaveRequest(file, result)
        try {
            startActivityForResult(intent, SAVE_FILE)
        } catch (_: android.content.ActivityNotFoundException) {
            saving = null
            result.error("no_document_picker", null, null)
        }
    }

    @Deprecated("FlutterActivity dispatches legacy activity results to its plugins.")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        when (requestCode) {
            SELECT_FILES -> {
                val pending = pickerResult ?: return
                pickerResult = null
                val files = if (resultCode != Activity.RESULT_OK || data == null) emptyList()
                    else data.clipData?.let { clips ->
                        (0 until clips.itemCount).mapNotNull { clips.getItemAt(it).uri?.toString() }
                    } ?: listOfNotNull(data.data?.toString())
                pending.success(files)
            }
            SAVE_FILE -> {
                val pending = saving ?: return
                val destination = data?.data
                if (resultCode != Activity.RESULT_OK || destination == null) {
                    saving = null
                    pending.result.success(false)
                    return
                }
                filesExecutor.execute {
                    val saved = runCatching {
                        val output = contentResolver.openOutputStream(destination)
                            ?: throw java.io.IOException("Missing destination stream")
                        output.use { sink -> pending.file.inputStream().use { it.copyTo(sink) } }
                    }.isSuccess
                    runOnUiThread {
                        saving = null
                        if (saved) pending.result.success(true)
                        else pending.result.error("save_failed", null, null)
                    }
                }
            }
        }
    }

    override fun onDestroy() {
        filesExecutor.shutdown()
        super.onDestroy()
    }

    companion object {
        private const val SELECT_FILES = 7810
        private const val SAVE_FILE = 7811
    }
}

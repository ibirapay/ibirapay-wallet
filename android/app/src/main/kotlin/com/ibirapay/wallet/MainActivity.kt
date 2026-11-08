package com.ibirapay.wallet

import android.app.Activity
import android.content.Intent
import android.os.Environment
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// Wallet backup (lib/seed_backup.dart): the shared Documents dir (outlives an uninstall), the system file picker for a
// backup this install cannot list (after a reinstall), and FLAG_SECURE while the words are on screen.
class MainActivity : FlutterActivity() {
    private var picking: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "ibirapay/seed_backup").setMethodCallHandler { call, result ->
            when (call.method) {
                "documentsDir" ->
                    result.success(Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOCUMENTS).path)
                "secure" -> {
                    if (call.arguments == true) window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
                    else window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                    result.success(null)
                }
                "pick" -> {
                    if (picking != null) {
                        result.error("busy", "o seletor de arquivos já está aberto", null)
                    } else {
                        picking = result
                        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).addCategory(Intent.CATEGORY_OPENABLE).setType("*/*")
                        startActivityForResult(intent, PICK)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    // null = nothing picked
    @Deprecated("FlutterActivity has no Activity Result API")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != PICK) return
        val result = picking ?: return
        picking = null
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) {
            result.success(null)
            return
        }
        try {
            val size = contentResolver.openFileDescriptor(uri, "r")?.use { it.statSize } ?: -1L
            if (size > MAX_BYTES) {
                result.error("size", "o arquivo tem $size bytes: não é um backup da seed", null)
                return
            }
            result.success(contentResolver.openInputStream(uri)?.use { it.readBytes() })
        } catch (e: Exception) {
            result.error("read", e.message, null)
        }
    }

    companion object {
        private const val PICK = 4242
        private const val MAX_BYTES = 64 * 1024L
    }
}

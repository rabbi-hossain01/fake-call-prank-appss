package com.example.fake_call_prank

import android.content.ContentValues
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream

class MainActivity : FlutterActivity() {
    private val channelName = "fake_call_prank/media_store"

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName).setMethodCallHandler { call, result ->
            if (call.method == "saveAudioToDownloads") {
                val sourcePath = call.argument<String>("sourcePath")
                val fileName = call.argument<String>("fileName")

                if (sourcePath.isNullOrBlank() || fileName.isNullOrBlank()) {
                    result.error("INVALID_ARGUMENT", "sourcePath and fileName are required", null)
                    return@setMethodCallHandler
                }

                try {
                    val savedLocation = saveAudioToDownloads(sourcePath, fileName)
                    result.success(savedLocation)
                } catch (e: Exception) {
                    result.error("SAVE_FAILED", e.message, null)
                }
            } else {
                result.notImplemented()
            }
        }
    }

    private fun saveAudioToDownloads(sourcePath: String, fileName: String): String {
        val sourceFile = File(sourcePath)
        if (!sourceFile.exists()) {
            throw IllegalArgumentException("Source file does not exist: $sourcePath")
        }

        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            saveWithMediaStore(sourceFile, fileName)
        } else {
            saveLegacyDownloads(sourceFile, fileName)
        }
    }

    private fun saveWithMediaStore(sourceFile: File, fileName: String): String {
        val resolver = applicationContext.contentResolver

        val values = ContentValues().apply {
            put(MediaStore.MediaColumns.DISPLAY_NAME, fileName)
            put(MediaStore.MediaColumns.MIME_TYPE, "audio/mpeg")
            put(MediaStore.MediaColumns.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS + "/PrankCallRecorder")
            put(MediaStore.MediaColumns.IS_PENDING, 1)
        }

        val uri = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
            ?: throw IllegalStateException("Could not create MediaStore record")

        resolver.openOutputStream(uri)?.use { output ->
            FileInputStream(sourceFile).use { input ->
                input.copyTo(output)
            }
        } ?: throw IllegalStateException("Could not open output stream")

        values.clear()
        values.put(MediaStore.MediaColumns.IS_PENDING, 0)
        resolver.update(uri, values, null, null)

        return uri.toString()
    }

    @Suppress("DEPRECATION")
    private fun saveLegacyDownloads(sourceFile: File, fileName: String): String {
        val downloadsDir = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS)
        val appDir = File(downloadsDir, "PrankCallRecorder")
        if (!appDir.exists()) appDir.mkdirs()

        val destFile = File(appDir, fileName)
        FileInputStream(sourceFile).use { input ->
            FileOutputStream(destFile).use { output ->
                input.copyTo(output)
            }
        }

        return destFile.absolutePath
    }
}

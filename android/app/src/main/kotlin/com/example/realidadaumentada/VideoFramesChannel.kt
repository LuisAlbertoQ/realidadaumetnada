package com.example.realidadaumentada

import android.graphics.Bitmap
import android.graphics.Matrix
import android.media.MediaMetadataRetriever
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.util.concurrent.Executors

/**
 * Extrae fotogramas JPEG de un video local sin dependencias de terceros.
 *
 * Canal: `waste/video_frames`
 *  - open {path} -> {durationMs, width, height, rotation}
 *  - frame {timeMs, maxWidth} -> Uint8List? (JPEG)
 *  - close -> null
 *
 * MediaMetadataRetriever no es thread-safe: todas las llamadas pasan por un
 * executor de un solo hilo y el resultado se devuelve en el hilo principal.
 */
class VideoFramesChannel : MethodChannel.MethodCallHandler {
    private val executor = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())

    private var retriever: MediaMetadataRetriever? = null
    private var rotationDegrees = 0
    private var codedWidth = 0
    private var codedHeight = 0

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "open" -> open(call, result)
            "frame" -> frame(call, result)
            "close" -> executor.execute {
                release()
                mainHandler.post { result.success(null) }
            }
            else -> result.notImplemented()
        }
    }

    private fun open(call: MethodCall, result: MethodChannel.Result) {
        val path = call.argument<String>("path")
        if (path.isNullOrBlank()) {
            result.error("bad_args", "Falta el path del video", null)
            return
        }
        executor.execute {
            try {
                release()
                val newRetriever = MediaMetadataRetriever()
                newRetriever.setDataSource(path)
                retriever = newRetriever

                rotationDegrees = newRetriever
                    .extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_ROTATION)
                    ?.toIntOrNull() ?: 0
                codedWidth = newRetriever
                    .extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH)
                    ?.toIntOrNull() ?: 0
                codedHeight = newRetriever
                    .extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT)
                    ?.toIntOrNull() ?: 0
                val durationMs = newRetriever
                    .extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)
                    ?.toLongOrNull() ?: 0L

                val swapped = rotationDegrees == 90 || rotationDegrees == 270
                val displayWidth = if (swapped) codedHeight else codedWidth
                val displayHeight = if (swapped) codedWidth else codedHeight

                val payload = mapOf(
                    "durationMs" to durationMs,
                    "width" to displayWidth,
                    "height" to displayHeight,
                    "rotation" to rotationDegrees,
                )
                mainHandler.post { result.success(payload) }
            } catch (e: Exception) {
                mainHandler.post {
                    result.error("open_failed", e.message ?: e.toString(), null)
                }
            }
        }
    }

    private fun frame(call: MethodCall, result: MethodChannel.Result) {
        val timeMs = call.argument<Number>("timeMs")?.toLong() ?: 0L
        val maxWidth = call.argument<Int>("maxWidth") ?: 640
        executor.execute {
            val active = retriever
            if (active == null) {
                mainHandler.post {
                    result.error("not_open", "Llama a open() antes de frame()", null)
                }
                return@execute
            }
            try {
                val raw = active.getFrameAtTime(
                    timeMs * 1000L,
                    MediaMetadataRetriever.OPTION_CLOSEST,
                )
                if (raw == null) {
                    mainHandler.post { result.success(null) }
                    return@execute
                }

                // Algunos dispositivos ya devuelven el frame rotado: si sus
                // dimensiones están intercambiadas respecto al video codificado,
                // no lo rotamos otra vez (evita cajas desalineadas).
                val alreadyRotated = codedWidth != codedHeight &&
                    raw.width == codedHeight &&
                    raw.height == codedWidth
                val needsRotation = rotationDegrees % 360 != 0 && !alreadyRotated
                val oriented = if (needsRotation) {
                    rotate(raw, rotationDegrees)
                } else {
                    raw
                }

                val scaled = scaleToWidth(oriented, maxWidth)
                val output = ByteArrayOutputStream()
                scaled.compress(Bitmap.CompressFormat.JPEG, 85, output)
                val bytes = output.toByteArray()
                mainHandler.post { result.success(bytes) }
            } catch (e: Exception) {
                mainHandler.post {
                    result.error("frame_failed", e.message ?: e.toString(), null)
                }
            }
        }
    }

    private fun rotate(bitmap: Bitmap, degrees: Int): Bitmap {
        if (degrees == 0) return bitmap
        val matrix = Matrix().apply { postRotate(degrees.toFloat()) }
        return Bitmap.createBitmap(
            bitmap,
            0,
            0,
            bitmap.width,
            bitmap.height,
            matrix,
            true,
        )
    }

    private fun scaleToWidth(bitmap: Bitmap, maxWidth: Int): Bitmap {
        if (maxWidth <= 0 || bitmap.width <= maxWidth) return bitmap
        val height = (bitmap.height.toDouble() * maxWidth / bitmap.width)
            .toInt()
            .coerceAtLeast(1)
        return Bitmap.createScaledBitmap(bitmap, maxWidth, height, true)
    }

    private fun release() {
        try {
            retriever?.release()
        } catch (_: Exception) {
            // Nada que hacer: el retriever ya estaba liberado.
        }
        retriever = null
        rotationDegrees = 0
        codedWidth = 0
        codedHeight = 0
    }
}

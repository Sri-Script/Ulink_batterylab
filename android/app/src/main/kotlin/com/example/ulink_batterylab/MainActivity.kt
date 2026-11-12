package com.example.ulink_batterylab

import android.media.AudioManager
import android.media.ToneGenerator
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    companion object {
        private const val ACKNOWLEDGEMENT_SOUND_CHANNEL =
            "com.example.ulink_batterylab/acknowledgement_sound"
        private const val BEEP_DURATION_MS = 150L
    }

    private val toneHandler = Handler(Looper.getMainLooper())
    private var toneGenerator: ToneGenerator? = null
    private var releaseTone: Runnable? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            ACKNOWLEDGEMENT_SOUND_CHANNEL,
        ).setMethodCallHandler { call, result ->
            if (call.method == "playAcknowledgement") {
                playAcknowledgement()
                result.success(null)
            } else {
                result.notImplemented()
            }
        }
    }

    private fun playAcknowledgement() {
        releaseToneGenerator()
        val generator = ToneGenerator(AudioManager.STREAM_NOTIFICATION, 85)
        toneGenerator = generator
        try {
            generator.startTone(ToneGenerator.TONE_PROP_BEEP, BEEP_DURATION_MS.toInt())
            releaseTone = Runnable {
                if (toneGenerator === generator) {
                    releaseToneGenerator()
                }
            }.also { toneHandler.postDelayed(it, BEEP_DURATION_MS) }
        } catch (_: RuntimeException) {
            releaseToneGenerator()
        }
    }

    private fun releaseToneGenerator() {
        releaseTone?.let(toneHandler::removeCallbacks)
        releaseTone = null
        try {
            toneGenerator?.release()
        } catch (_: RuntimeException) {
            // There is nothing left to recover when Android has already
            // invalidated the generator during activity teardown.
        }
        toneGenerator = null
    }

    override fun onDestroy() {
        releaseToneGenerator()
        super.onDestroy()
    }
}

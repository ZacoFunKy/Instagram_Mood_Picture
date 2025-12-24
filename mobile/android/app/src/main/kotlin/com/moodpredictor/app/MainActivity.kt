package com.moodpredictor.app

import android.content.ComponentName
import android.media.MediaMetadata
import android.media.session.MediaController
import android.media.session.MediaSessionManager
import android.os.Build
import androidx.annotation.NonNull
import androidx.annotation.RequiresApi
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

@RequiresApi(Build.VERSION_CODES.LOLLIPOP)
class MainActivity: FlutterActivity() {
    private val CHANNEL = "com.moodpredictor/media_session"
    private val EVENT_CHANNEL = "com.moodpredictor/media_session_events"
    
    private var mediaSessionManager: MediaSessionManager? = null
    private var eventSink: EventChannel.EventSink? = null

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        // Method channel for one-time queries
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getCurrentMediaMetadata" -> {
                    val metadata = getCurrentMediaMetadata()
                    result.success(metadata)
                }
                "isMediaPlaying" -> {
                    val isPlaying = isMediaPlaying()
                    result.success(isPlaying)
                }
                else -> result.notImplemented()
            }
        }
        
        // Event channel for track change notifications
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENT_CHANNEL).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    eventSink = events
                    startMediaSessionListener()
                }

                override fun onCancel(arguments: Any?) {
                    eventSink = null
                    stopMediaSessionListener()
                }
            }
        )
    }

    private fun getCurrentMediaMetadata(): Map<String, String>? {
        mediaSessionManager = getSystemService(MEDIA_SESSION_SERVICE) as MediaSessionManager
        
        val activeSessions = mediaSessionManager?.getActiveSessions(
            ComponentName(this, NotificationListener::class.java)
        ) ?: return null
        
        for (controller in activeSessions) {
            val metadata = controller.metadata ?: continue
            val packageName = controller.packageName ?: ""
            
            // Prioritize YouTube Music, but accept any media
            if (packageName.contains("youtube.music") || activeSessions.size == 1) {
                return mapOf(
                    "title" to (metadata.getString(MediaMetadata.METADATA_KEY_TITLE) ?: ""),
                    "artist" to (metadata.getString(MediaMetadata.METADATA_KEY_ARTIST) ?: ""),
                    "album" to (metadata.getString(MediaMetadata.METADATA_KEY_ALBUM) ?: ""),
                    "package" to packageName
                )
            }
        }
        
        return null
    }

    private fun isMediaPlaying(): Boolean {
        mediaSessionManager = getSystemService(MEDIA_SESSION_SERVICE) as MediaSessionManager
        
        val activeSessions = mediaSessionManager?.getActiveSessions(
            ComponentName(this, NotificationListener::class.java)
        ) ?: return false
        
        return activeSessions.any { it.playbackState?.state == android.media.session.PlaybackState.STATE_PLAYING }
    }

    private fun startMediaSessionListener() {
        // Note: Full implementation requires NotificationListenerService
        // This is a simplified version
    }

    private fun stopMediaSessionListener() {
        // Cleanup
    }
}

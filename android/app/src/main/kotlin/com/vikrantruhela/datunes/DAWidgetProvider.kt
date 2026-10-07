package com.vikrantruhela.datunes

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.support.v4.media.session.PlaybackStateCompat
import android.util.Log

abstract class BaseWidgetProvider : AppWidgetProvider() {
    companion object {
        const val ACTION_PLAY_PAUSE = "com.vikrantruhela.datunes.ACTION_PLAY_PAUSE"
        const val ACTION_NEXT = "com.vikrantruhela.datunes.ACTION_NEXT"
        const val ACTION_PREVIOUS = "com.vikrantruhela.datunes.ACTION_PREVIOUS"
        const val ACTION_SHUFFLE = "com.vikrantruhela.datunes.ACTION_SHUFFLE"
        const val ACTION_REPEAT = "com.vikrantruhela.datunes.ACTION_REPEAT"
        const val ACTION_FAVORITE = "com.vikrantruhela.datunes.ACTION_FAVORITE"
    }

    override fun onUpdate(context: Context, appWidgetManager: AppWidgetManager, appWidgetIds: IntArray) {
        super.onUpdate(context, appWidgetManager, appWidgetIds)
        WidgetUpdater.updateFromCache(context)
    }

    override fun onAppWidgetOptionsChanged(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int,
        newOptions: Bundle
    ) {
        super.onAppWidgetOptionsChanged(context, appWidgetManager, appWidgetId, newOptions)
        WidgetUpdater.updateFromCache(context)
    }

    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        val action = intent.action
        if (action != null) {
            when (action) {
                ACTION_PLAY_PAUSE -> sendMediaCommand(context, "PLAY_PAUSE")
                ACTION_NEXT -> sendMediaCommand(context, "NEXT")
                ACTION_PREVIOUS -> sendMediaCommand(context, "PREVIOUS")
                ACTION_SHUFFLE -> sendMediaCommand(context, "SHUFFLE")
                ACTION_REPEAT -> sendMediaCommand(context, "REPEAT")
                ACTION_FAVORITE -> sendMediaCommand(context, "FAVORITE")
            }
        }
    }

    private fun sendMediaCommand(context: Context, command: String) {
        val controller = DAApplication.instance?.getMediaController()
        if (controller != null) {
            try {
                when (command) {
                    "PLAY_PAUSE" -> {
                        val state = controller.playbackState?.state
                        if (state == PlaybackStateCompat.STATE_PLAYING) {
                            controller.transportControls.pause()
                        } else {
                            controller.transportControls.play()
                        }
                    }
                    "NEXT" -> controller.transportControls.skipToNext()
                    "PREVIOUS" -> controller.transportControls.skipToPrevious()
                    "SHUFFLE" -> {
                        val currentMode = controller.shuffleMode
                        val nextMode = if (currentMode == PlaybackStateCompat.SHUFFLE_MODE_NONE) {
                            PlaybackStateCompat.SHUFFLE_MODE_ALL
                        } else {
                            PlaybackStateCompat.SHUFFLE_MODE_NONE
                        }
                        controller.transportControls.setShuffleMode(nextMode)
                    }
                    "REPEAT" -> {
                        val currentMode = controller.repeatMode
                        val nextMode = when (currentMode) {
                            PlaybackStateCompat.REPEAT_MODE_NONE -> PlaybackStateCompat.REPEAT_MODE_ALL
                            PlaybackStateCompat.REPEAT_MODE_ALL -> PlaybackStateCompat.REPEAT_MODE_ONE
                            else -> PlaybackStateCompat.REPEAT_MODE_NONE
                        }
                        controller.transportControls.setRepeatMode(nextMode)
                    }
                    "FAVORITE" -> controller.transportControls.sendCustomAction("toggle_favorite", null)
                }
            } catch (e: Exception) {
                Log.e("BaseWidgetProvider", "Error sending command: ${e.message}", e)
            }
        } else {
            val keycode = when (command) {
                "PLAY_PAUSE" -> android.view.KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE
                "NEXT" -> android.view.KeyEvent.KEYCODE_MEDIA_NEXT
                "PREVIOUS" -> android.view.KeyEvent.KEYCODE_MEDIA_PREVIOUS
                else -> 0
            }
            if (keycode != 0) {
                try {
                    val down = Intent(Intent.ACTION_MEDIA_BUTTON).apply {
                        component = ComponentName(context, "com.ryanheise.audioservice.MediaButtonReceiver")
                        putExtra(Intent.EXTRA_KEY_EVENT, android.view.KeyEvent(android.view.KeyEvent.ACTION_DOWN, keycode))
                    }
                    context.sendBroadcast(down)
                    val up = Intent(Intent.ACTION_MEDIA_BUTTON).apply {
                        component = ComponentName(context, "com.ryanheise.audioservice.MediaButtonReceiver")
                        putExtra(Intent.EXTRA_KEY_EVENT, android.view.KeyEvent(android.view.KeyEvent.ACTION_UP, keycode))
                    }
                    context.sendBroadcast(up)
                } catch (e: Exception) {
                    Log.e("BaseWidgetProvider", "Error sending keycode: ${e.message}", e)
                }
            }
        }
    }
}

class DAWidget2x2Provider : BaseWidgetProvider()
class DAWidget4x2Provider : BaseWidgetProvider()
class DAWidget2x1Provider : BaseWidgetProvider()
class DAM3Widget4x2Provider : BaseWidgetProvider()
class DAM3Widget2x2Provider : BaseWidgetProvider()


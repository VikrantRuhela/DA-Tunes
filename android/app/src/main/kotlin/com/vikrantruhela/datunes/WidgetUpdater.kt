package com.vikrantruhela.datunes

import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.res.Configuration
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.PorterDuff
import android.graphics.PorterDuffXfermode
import android.graphics.Rect
import android.graphics.RectF
import android.support.v4.media.MediaMetadataCompat
import android.support.v4.media.session.PlaybackStateCompat
import android.widget.RemoteViews
import android.util.Log
import java.io.InputStream
import java.net.HttpURLConnection
import java.net.URL
import kotlin.concurrent.thread

object WidgetUpdater {
    private var cachedArtwork: Bitmap? = null
    private var cachedTopRoundedArtwork: Bitmap? = null
    private var cachedBlurredBackground: Bitmap? = null
    private var lastArtworkUri: String? = null
    private var downloadingUri: String? = null

    private var lastTitle: String? = null
    private var lastArtist: String? = null
    private var lastAlbum: String? = null
    private var lastIsPlaying: Boolean = false
    private var lastPosition: Long = -1L
    private var lastDuration: Long = -1L
    private var lastShuffleMode: Int = -1
    private var lastRepeatMode: Int = -1

    fun updateWidget(
        context: Context,
        metadata: MediaMetadataCompat?,
        state: PlaybackStateCompat?,
        shuffleMode: Int,
        repeatMode: Int
    ) {
        val title = metadata?.getString(MediaMetadataCompat.METADATA_KEY_TITLE) ?: lastTitle ?: "Not Playing"
        val artist = metadata?.getString(MediaMetadataCompat.METADATA_KEY_ARTIST) ?: lastArtist ?: "DA Tunes"
        val album = metadata?.getString(MediaMetadataCompat.METADATA_KEY_ALBUM) ?: lastAlbum ?: ""
        val songId = metadata?.getString(MediaMetadataCompat.METADATA_KEY_MEDIA_ID) ?: ""
        
        var artUriStr = metadata?.getString(MediaMetadataCompat.METADATA_KEY_ART_URI)
        if (artUriStr == null) {
            artUriStr = metadata?.getString(MediaMetadataCompat.METADATA_KEY_ALBUM_ART_URI)
        }
        if (artUriStr == null) {
            artUriStr = metadata?.getString(MediaMetadataCompat.METADATA_KEY_DISPLAY_ICON_URI)
        }
        
        val isPlaying = state?.state == PlaybackStateCompat.STATE_PLAYING
        val duration = metadata?.getLong(MediaMetadataCompat.METADATA_KEY_DURATION) ?: lastDuration
        var position = state?.position ?: lastPosition
        
        if (isPlaying && position < lastPosition && Math.abs(position - lastPosition) < 3000L) {
            position = lastPosition
        }
        
        if (isPlaying && position == 0L && lastPosition > 3000L) {
            position = lastPosition
        }

        val titleChanged = title != lastTitle
        val artistChanged = artist != lastArtist
        val albumChanged = album != lastAlbum
        val isPlayingChanged = isPlaying != lastIsPlaying
        val positionChanged = Math.abs(position - lastPosition) >= 900L
        val durationChanged = duration != lastDuration
        val shuffleChanged = shuffleMode != lastShuffleMode
        val repeatChanged = repeatMode != lastRepeatMode

        if (!titleChanged && !artistChanged && !albumChanged && !isPlayingChanged && 
            !positionChanged && !durationChanged && !shuffleChanged && !repeatChanged) {
            return
        }

        val isPartial = !titleChanged && !artistChanged && !albumChanged && !isPlayingChanged && 
                        !durationChanged && !shuffleChanged && !repeatChanged && positionChanged

        lastTitle = title
        lastArtist = artist
        lastAlbum = album
        lastIsPlaying = isPlaying
        lastPosition = position
        lastDuration = duration
        lastShuffleMode = shuffleMode
        lastRepeatMode = repeatMode

        val displayIconBitmap = metadata?.getBitmap(MediaMetadataCompat.METADATA_KEY_DISPLAY_ICON)
        val artBitmap = metadata?.getBitmap(MediaMetadataCompat.METADATA_KEY_ART)
        val albumArtBitmap = metadata?.getBitmap(MediaMetadataCompat.METADATA_KEY_ALBUM_ART)

        saveToSharedPreferences(context, title, artist, album, artUriStr, isPlaying, shuffleMode, repeatMode, songId, duration, position)

        if (isPartial) {
            renderWidgets(context, title, artist, album, isPlaying, shuffleMode, repeatMode, songId, duration, position, isPartial = true)
        } else {
            if (displayIconBitmap != null || artBitmap != null || albumArtBitmap != null) {
                val sourceBitmap = displayIconBitmap ?: artBitmap ?: albumArtBitmap
                thread {
                    processAndCacheBitmaps(sourceBitmap!!, "direct_metadata")
                    android.os.Handler(context.mainLooper).post {
                        renderWidgets(context, title, artist, album, isPlaying, shuffleMode, repeatMode, songId, duration, position, isPartial = false)
                    }
                }
            } else {
                triggerArtworkLoading(context, artUriStr)
                renderWidgets(context, title, artist, album, isPlaying, shuffleMode, repeatMode, songId, duration, position, isPartial = false)
            }
        }
    }

    private fun processAndCacheBitmaps(rawBitmap: Bitmap, sourceTag: String) {
        try {
            val maxDimension = 400
            val width = rawBitmap.width
            val height = rawBitmap.height
            val scaledBitmap = if (width > maxDimension || height > maxDimension) {
                val ratio = width.toFloat() / height.toFloat()
                val (newWidth, newHeight) = if (ratio > 1) {
                    Pair(maxDimension, (maxDimension / ratio).toInt())
                } else {
                    Pair((maxDimension * ratio).toInt(), maxDimension)
                }
                Bitmap.createScaledBitmap(rawBitmap, newWidth, newHeight, true)
            } else {
                rawBitmap
            }

            val sharpThumbnail = getRoundedCornerBitmap(scaledBitmap, 24)
            val topRoundedArt = getTopRoundedCornerBitmap(scaledBitmap, 36)
            
            val blurInput = Bitmap.createScaledBitmap(scaledBitmap, 150, 150, false)
            val blurredBackground = processBlurredBackground(blurInput)

            cachedArtwork = sharpThumbnail
            cachedTopRoundedArtwork = topRoundedArt
            cachedBlurredBackground = blurredBackground
        } catch (e: Exception) {
            Log.e("WidgetUpdater", "Error in processAndCacheBitmaps: ${e.message}", e)
        }
    }

    private fun triggerArtworkLoading(context: Context, artUriStr: String?) {
        if (artUriStr == null) {
            cachedArtwork = null
            cachedTopRoundedArtwork = null
            cachedBlurredBackground = null
            lastArtworkUri = null
            downloadingUri = null
            return
        }

        if (artUriStr == lastArtworkUri && cachedArtwork != null) {
            return
        }

        if (artUriStr == downloadingUri) {
            return
        }

        downloadingUri = artUriStr

        thread {
            try {
                val rawBitmap = loadArtwork(context, artUriStr)
                if (rawBitmap != null && artUriStr == downloadingUri) {
                    processAndCacheBitmaps(rawBitmap, artUriStr)
                    lastArtworkUri = artUriStr
                } else if (rawBitmap == null && artUriStr == downloadingUri) {
                    cachedArtwork = null
                    cachedTopRoundedArtwork = null
                    cachedBlurredBackground = null
                    lastArtworkUri = artUriStr
                }
            } catch (e: Exception) {
                e.printStackTrace()
                if (artUriStr == downloadingUri) {
                    cachedArtwork = null
                    cachedTopRoundedArtwork = null
                    cachedBlurredBackground = null
                }
            } finally {
                if (artUriStr == downloadingUri) {
                    downloadingUri = null
                }
            }

            android.os.Handler(context.mainLooper).post {
                updateFromCache(context)
            }
        }
    }

    private fun processBlurredBackground(raw: Bitmap): Bitmap? {
        val blurred = blur(raw, 10)
        val darkened = darkenBitmap(blurred, 0.40f)
        return getRoundedCornerBitmap(darkened, 24)
    }

    private fun isDarkMode(context: Context): Boolean {
        val prefs = context.getSharedPreferences("da_tunes_widget_prefs", Context.MODE_PRIVATE)
        if (prefs.contains("isDarkMode")) {
            return prefs.getBoolean("isDarkMode", true)
        }
        val flutterPrefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        val m3Mode = flutterPrefs.getString("flutter.m3_theme_mode", null)
        if (m3Mode != null) {
            return m3Mode != "light"
        }
        val currentTheme = flutterPrefs.getString("flutter.app_theme_mode", null)
        if (currentTheme == "amoled" || currentTheme == "defaultDA") {
            return true
        }
        val nightModeFlags = context.resources.configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK
        return nightModeFlags == Configuration.UI_MODE_NIGHT_YES
    }

    private fun renderWidgets(
        context: Context,
        title: String,
        artist: String,
        album: String,
        isPlaying: Boolean,
        shuffleMode: Int,
        repeatMode: Int,
        songId: String,
        duration: Long,
        position: Long,
        isPartial: Boolean
    ) {
        val appWidgetManager = AppWidgetManager.getInstance(context)

        val providers = arrayOf(
            Pair(DAWidget2x2Provider::class.java, R.layout.widget_2x2),
            Pair(DAWidget4x2Provider::class.java, R.layout.widget_4x2),
            Pair(DAWidget2x1Provider::class.java, R.layout.widget_2x1),
            Pair(DAM3Widget4x2Provider::class.java, R.layout.widget_m3_4x2),
            Pair(DAM3Widget2x2Provider::class.java, R.layout.widget_m3_2x2)
        )

        val progressValue = if (duration > 0) ((position * 10000) / duration).toInt() else 0
        val progressFloat = if (duration > 0) (position.toFloat() / duration.toFloat()).coerceIn(0f, 1f) else 0f
        val isDark = isDarkMode(context)

        for ((providerClass, explicitLayoutId) in providers) {
            val component = ComponentName(context, providerClass)
            val widgetIds = appWidgetManager.getAppWidgetIds(component)

            for (widgetId in widgetIds) {
                val layoutResId = if (explicitLayoutId != -1) {
                    explicitLayoutId
                } else {
                    val options = appWidgetManager.getAppWidgetOptions(widgetId)
                    val minWidth = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH)
                    val minHeight = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT)
                    if (minWidth < 200 && minHeight < 160) R.layout.widget_2x2
                    else if (minWidth >= 200 && minHeight >= 160) R.layout.widget_large
                    else R.layout.widget_4x2
                }

                if (isPartial) {
                    if (layoutResId == R.layout.widget_4x2 || layoutResId == R.layout.widget_large) {
                        val partialViews = RemoteViews(context.packageName, layoutResId)
                        partialViews.setProgressBar(R.id.widget_progress, 10000, progressValue, false)
                        try {
                            appWidgetManager.partiallyUpdateAppWidget(widgetId, partialViews)
                        } catch (e: Exception) {
                            Log.e("WidgetUpdater", "Error in partial update: ${e.message}")
                        }
                    } else if (layoutResId == R.layout.widget_m3_4x2 || layoutResId == R.layout.widget_m3_2x2) {
                        val m3Art = createM3CircularProgressArtwork(cachedArtwork, progressFloat, isDark, if (layoutResId == R.layout.widget_m3_4x2) 220 else 240)
                        if (m3Art != null) {
                            val partialViews = RemoteViews(context.packageName, layoutResId)
                            partialViews.setImageViewBitmap(R.id.widget_m3_circular_art, m3Art)
                            try {
                                appWidgetManager.partiallyUpdateAppWidget(widgetId, partialViews)
                            } catch (e: Exception) {
                                Log.e("WidgetUpdater", "Error in M3 partial update: ${e.message}")
                            }
                        }
                    }
                } else {
                    val views = RemoteViews(context.packageName, layoutResId)
                    when (layoutResId) {
                        R.layout.widget_m3_4x2, R.layout.widget_m3_2x2 -> {
                            setupM3Widget(context, views, title, artist, isPlaying, progressFloat, isDark, layoutResId)
                        }
                        R.layout.widget_4x2 -> {
                            setupMediumWidget(context, views, title, artist, isPlaying, duration, position)
                        }
                        R.layout.widget_2x1 -> {
                            setup2x1Widget(context, views, title, artist, isPlaying)
                        }
                        R.layout.widget_large -> {
                            setupLargeWidget(context, views, title, artist, album, isPlaying, shuffleMode, repeatMode, songId, duration, position)
                        }
                        else -> {
                            setupSmallWidget(context, views, title, artist, isPlaying)
                        }
                    }
                    try {
                        appWidgetManager.updateAppWidget(widgetId, views)
                    } catch (e: Exception) {
                        Log.e("WidgetUpdater", "Error updating widget $widgetId: ${e.message}")
                    }
                }
            }
        }
    }

    private fun getOpenAppPendingIntent(context: Context, isPlaying: Boolean): android.app.PendingIntent {
        val intent = Intent(context, MainActivity::class.java).apply {
            action = Intent.ACTION_MAIN
            addCategory(Intent.CATEGORY_LAUNCHER)
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            putExtra("open_player", isPlaying)
        }
        val flags = android.app.PendingIntent.FLAG_UPDATE_CURRENT or android.app.PendingIntent.FLAG_IMMUTABLE
        return android.app.PendingIntent.getActivity(context, 100, intent, flags)
    }

    private fun setupM3Widget(
        context: Context,
        views: RemoteViews,
        title: String,
        artist: String,
        isPlaying: Boolean,
        progressFloat: Float,
        isDark: Boolean,
        layoutResId: Int
    ) {
        views.setTextViewText(R.id.txt_title, title)
        views.setTextViewText(R.id.txt_artist, artist)

        val textColor = if (isDark) android.graphics.Color.WHITE else android.graphics.Color.parseColor("#1C1B1F")
        val subTextColor = if (isDark) android.graphics.Color.parseColor("#B3FFFFFF") else android.graphics.Color.parseColor("#79747E")
        val panelBg = if (isDark) R.drawable.m3_panel_background_dark else R.drawable.m3_panel_background_light

        views.setTextColor(R.id.txt_title, textColor)
        views.setTextColor(R.id.txt_artist, subTextColor)
        views.setInt(R.id.widget_m3_panel, "setBackgroundResource", panelBg)

        val playPauseRes = if (isPlaying) R.drawable.audio_service_pause else R.drawable.audio_service_play
        views.setImageViewResource(R.id.btn_previous, R.drawable.audio_service_skip_previous)
        views.setImageViewResource(R.id.btn_next, R.drawable.audio_service_skip_next)
        views.setImageViewResource(R.id.btn_play_pause, playPauseRes)

        val openAppPendingIntent = getOpenAppPendingIntent(context, isPlaying)
        views.setOnClickPendingIntent(android.R.id.background, openAppPendingIntent)
        views.setOnClickPendingIntent(R.id.widget_background_image, openAppPendingIntent)
        views.setOnClickPendingIntent(R.id.widget_m3_panel, openAppPendingIntent)
        views.setOnClickPendingIntent(R.id.widget_m3_circular_art, openAppPendingIntent)
        views.setOnClickPendingIntent(R.id.txt_title, openAppPendingIntent)
        views.setOnClickPendingIntent(R.id.txt_artist, openAppPendingIntent)

        views.setOnClickPendingIntent(R.id.btn_previous, getPendingIntent(context, BaseWidgetProvider.ACTION_PREVIOUS))
        views.setOnClickPendingIntent(R.id.btn_play_pause, getPendingIntent(context, BaseWidgetProvider.ACTION_PLAY_PAUSE))
        views.setOnClickPendingIntent(R.id.btn_next, getPendingIntent(context, BaseWidgetProvider.ACTION_NEXT))

        val m3Art = createM3CircularProgressArtwork(cachedArtwork, progressFloat, isDark, if (layoutResId == R.layout.widget_m3_4x2) 220 else 240)
        if (m3Art != null) {
            views.setImageViewBitmap(R.id.widget_m3_circular_art, m3Art)
        } else {
            views.setImageViewResource(R.id.widget_m3_circular_art, R.drawable.da_placeholder)
        }

        cachedBlurredBackground?.let {
            views.setImageViewBitmap(R.id.widget_background_image, it)
        } ?: run {
            views.setImageViewResource(R.id.widget_background_image, R.drawable.widget_background)
        }
    }

    private fun setup2x1Widget(context: Context, views: RemoteViews, title: String, artist: String, isPlaying: Boolean) {
        views.setTextViewText(R.id.txt_title, title)
        views.setTextViewText(R.id.txt_artist, artist)

        val playPauseRes = if (isPlaying) R.drawable.audio_service_pause else R.drawable.audio_service_play
        views.setImageViewResource(R.id.btn_previous, R.drawable.audio_service_skip_previous)
        views.setImageViewResource(R.id.btn_next, R.drawable.audio_service_skip_next)
        views.setImageViewResource(R.id.btn_play_pause, playPauseRes)

        val openAppPendingIntent = getOpenAppPendingIntent(context, isPlaying)
        views.setOnClickPendingIntent(android.R.id.background, openAppPendingIntent)
        views.setOnClickPendingIntent(R.id.widget_background_image, openAppPendingIntent)
        views.setOnClickPendingIntent(R.id.txt_title, openAppPendingIntent)
        views.setOnClickPendingIntent(R.id.txt_artist, openAppPendingIntent)

        views.setOnClickPendingIntent(R.id.btn_previous, getPendingIntent(context, BaseWidgetProvider.ACTION_PREVIOUS))
        views.setOnClickPendingIntent(R.id.btn_play_pause, getPendingIntent(context, BaseWidgetProvider.ACTION_PLAY_PAUSE))
        views.setOnClickPendingIntent(R.id.btn_next, getPendingIntent(context, BaseWidgetProvider.ACTION_NEXT))

        cachedBlurredBackground?.let {
            views.setImageViewBitmap(R.id.widget_background_image, it)
        } ?: run {
            views.setImageViewResource(R.id.widget_background_image, R.drawable.widget_background)
        }
    }

    private fun setupSmallWidget(context: Context, views: RemoteViews, title: String, artist: String, isPlaying: Boolean) {
        views.setTextViewText(R.id.txt_title, title)
        views.setTextViewText(R.id.txt_artist, artist)

        val playPauseRes = if (isPlaying) R.drawable.audio_service_pause else R.drawable.audio_service_play
        views.setImageViewResource(R.id.btn_previous, R.drawable.audio_service_skip_previous)
        views.setImageViewResource(R.id.btn_next, R.drawable.audio_service_skip_next)
        views.setImageViewResource(R.id.btn_play_pause, playPauseRes)

        val openAppPendingIntent = getOpenAppPendingIntent(context, isPlaying)
        views.setOnClickPendingIntent(android.R.id.background, openAppPendingIntent)
        views.setOnClickPendingIntent(R.id.widget_background_image, openAppPendingIntent)
        views.setOnClickPendingIntent(R.id.txt_title, openAppPendingIntent)
        views.setOnClickPendingIntent(R.id.txt_artist, openAppPendingIntent)

        views.setOnClickPendingIntent(R.id.btn_previous, getPendingIntent(context, BaseWidgetProvider.ACTION_PREVIOUS))
        views.setOnClickPendingIntent(R.id.btn_play_pause, getPendingIntent(context, BaseWidgetProvider.ACTION_PLAY_PAUSE))
        views.setOnClickPendingIntent(R.id.btn_next, getPendingIntent(context, BaseWidgetProvider.ACTION_NEXT))

        cachedBlurredBackground?.let {
            views.setImageViewBitmap(R.id.widget_background_image, it)
        } ?: run {
            views.setImageViewResource(R.id.widget_background_image, R.drawable.widget_background)
        }
    }

    private fun setupMediumWidget(
        context: Context,
        views: RemoteViews,
        title: String,
        artist: String,
        isPlaying: Boolean,
        duration: Long,
        position: Long
    ) {
        views.setTextViewText(R.id.txt_title, title)
        views.setTextViewText(R.id.txt_artist, artist)

        val playPauseRes = if (isPlaying) R.drawable.audio_service_pause else R.drawable.audio_service_play
        views.setImageViewResource(R.id.btn_previous, R.drawable.audio_service_skip_previous)
        views.setImageViewResource(R.id.btn_next, R.drawable.audio_service_skip_next)
        views.setImageViewResource(R.id.btn_play_pause, playPauseRes)

        if (duration > 0) {
            val progressValue = ((position * 10000) / duration).toInt()
            views.setProgressBar(R.id.widget_progress, 10000, progressValue, false)
        } else {
            views.setProgressBar(R.id.widget_progress, 10000, 0, false)
        }

        val openAppPendingIntent = getOpenAppPendingIntent(context, isPlaying)
        views.setOnClickPendingIntent(android.R.id.background, openAppPendingIntent)
        views.setOnClickPendingIntent(R.id.widget_background_image, openAppPendingIntent)
        views.setOnClickPendingIntent(R.id.widget_artwork, openAppPendingIntent)
        views.setOnClickPendingIntent(R.id.txt_title, openAppPendingIntent)
        views.setOnClickPendingIntent(R.id.txt_artist, openAppPendingIntent)

        views.setOnClickPendingIntent(R.id.btn_previous, getPendingIntent(context, BaseWidgetProvider.ACTION_PREVIOUS))
        views.setOnClickPendingIntent(R.id.btn_play_pause, getPendingIntent(context, BaseWidgetProvider.ACTION_PLAY_PAUSE))
        views.setOnClickPendingIntent(R.id.btn_next, getPendingIntent(context, BaseWidgetProvider.ACTION_NEXT))

        cachedArtwork?.let {
            views.setImageViewBitmap(R.id.widget_artwork, it)
        } ?: run {
            views.setImageViewResource(R.id.widget_artwork, R.drawable.da_placeholder)
        }

        cachedBlurredBackground?.let {
            views.setImageViewBitmap(R.id.widget_background_image, it)
        } ?: run {
            views.setImageViewResource(R.id.widget_background_image, R.drawable.widget_background)
        }
    }

    private fun setupLargeWidget(
        context: Context,
        views: RemoteViews,
        title: String,
        artist: String,
        album: String,
        isPlaying: Boolean,
        shuffleMode: Int,
        repeatMode: Int,
        songId: String,
        duration: Long,
        position: Long
    ) {
        views.setTextViewText(R.id.txt_title, title)
        views.setTextViewText(R.id.txt_artist, artist)
        views.setTextViewText(R.id.txt_album, album)

        val playPauseRes = if (isPlaying) R.drawable.audio_service_pause else R.drawable.audio_service_play
        views.setImageViewResource(R.id.btn_previous, R.drawable.audio_service_skip_previous)
        views.setImageViewResource(R.id.btn_next, R.drawable.audio_service_skip_next)
        views.setImageViewResource(R.id.btn_play_pause, playPauseRes)

        if (duration > 0) {
            val progressValue = ((position * 10000) / duration).toInt()
            views.setProgressBar(R.id.widget_progress, 10000, progressValue, false)
        } else {
            views.setProgressBar(R.id.widget_progress, 10000, 0, false)
        }

        val openAppPendingIntent = getOpenAppPendingIntent(context, isPlaying)
        views.setOnClickPendingIntent(android.R.id.background, openAppPendingIntent)
        views.setOnClickPendingIntent(R.id.widget_background_image, openAppPendingIntent)
        views.setOnClickPendingIntent(R.id.widget_artwork, openAppPendingIntent)
        views.setOnClickPendingIntent(R.id.txt_title, openAppPendingIntent)
        views.setOnClickPendingIntent(R.id.txt_artist, openAppPendingIntent)
        views.setOnClickPendingIntent(R.id.txt_album, openAppPendingIntent)

        views.setOnClickPendingIntent(R.id.btn_previous, getPendingIntent(context, BaseWidgetProvider.ACTION_PREVIOUS))
        views.setOnClickPendingIntent(R.id.btn_play_pause, getPendingIntent(context, BaseWidgetProvider.ACTION_PLAY_PAUSE))
        views.setOnClickPendingIntent(R.id.btn_next, getPendingIntent(context, BaseWidgetProvider.ACTION_NEXT))

        cachedBlurredBackground?.let {
            views.setImageViewBitmap(R.id.widget_background_image, it)
        } ?: run {
            views.setImageViewResource(R.id.widget_background_image, R.drawable.widget_background)
        }

        cachedTopRoundedArtwork?.let {
            views.setImageViewBitmap(R.id.widget_artwork, it)
        } ?: run {
            views.setImageViewResource(R.id.widget_artwork, R.drawable.da_placeholder)
        }
    }

    private fun createM3CircularProgressArtwork(
        sourceBitmap: Bitmap?,
        progress: Float,
        isDark: Boolean,
        sizePx: Int = 240
    ): Bitmap? {
        try {
            val output = Bitmap.createBitmap(sizePx, sizePx, Bitmap.Config.ARGB_8888)
            val canvas = Canvas(output)
            val center = sizePx / 2f
            val strokeWidth = sizePx * 0.07f
            val padding = strokeWidth / 2f + 2f
            val rectF = RectF(padding, padding, sizePx - padding, sizePx - padding)

            val trackPaint = Paint().apply {
                isAntiAlias = true
                style = Paint.Style.STROKE
                this.strokeWidth = strokeWidth
                strokeCap = Paint.Cap.ROUND
                color = if (isDark) android.graphics.Color.parseColor("#35FFFFFF") else android.graphics.Color.parseColor("#35000000")
            }
            canvas.drawOval(rectF, trackPaint)

            val sweepAngle = (progress * 360f).coerceIn(0f, 360f)
            if (sweepAngle > 0.5f) {
                val activePaint = Paint().apply {
                    isAntiAlias = true
                    style = Paint.Style.STROKE
                    this.strokeWidth = strokeWidth
                    strokeCap = Paint.Cap.ROUND
                    color = if (isDark) android.graphics.Color.parseColor("#D0BCFF") else android.graphics.Color.parseColor("#6750A4")
                }
                canvas.drawArc(rectF, -90f, sweepAngle, false, activePaint)
            }

            val artSize = (sizePx - (strokeWidth * 2.5f)).toInt()
            if (artSize > 10) {
                val artBitmap = if (sourceBitmap != null) {
                    Bitmap.createScaledBitmap(sourceBitmap, artSize, artSize, true)
                } else {
                    val placeholder = BitmapFactory.decodeResource(DAApplication.instance?.resources, R.drawable.da_placeholder)
                    Bitmap.createScaledBitmap(placeholder, artSize, artSize, true)
                }

                val artOutput = Bitmap.createBitmap(artSize, artSize, Bitmap.Config.ARGB_8888)
                val artCanvas = Canvas(artOutput)
                val artPaint = Paint().apply { isAntiAlias = true }
                val artRect = RectF(0f, 0f, artSize.toFloat(), artSize.toFloat())
                val artRadius = artSize / 2f

                artCanvas.drawRoundRect(artRect, artRadius, artRadius, artPaint)
                artPaint.xfermode = PorterDuffXfermode(PorterDuff.Mode.SRC_IN)
                artCanvas.drawBitmap(artBitmap, 0f, 0f, artPaint)

                val artOffset = (sizePx - artSize) / 2f
                canvas.drawBitmap(artOutput, artOffset, artOffset, null)
            }
            return output
        } catch (e: Exception) {
            Log.e("WidgetUpdater", "Error rendering M3 circular artwork: ${e.message}", e)
            return null
        }
    }

    private fun getPendingIntent(context: Context, action: String): android.app.PendingIntent {
        val requestCode = when (action) {
            BaseWidgetProvider.ACTION_PLAY_PAUSE -> 1
            BaseWidgetProvider.ACTION_NEXT -> 2
            BaseWidgetProvider.ACTION_PREVIOUS -> 3
            BaseWidgetProvider.ACTION_SHUFFLE -> 4
            BaseWidgetProvider.ACTION_REPEAT -> 5
            BaseWidgetProvider.ACTION_FAVORITE -> 6
            else -> 0
        }
        val intent = Intent(context, DAWidget2x2Provider::class.java).apply {
            this.action = action
        }
        val flags = android.app.PendingIntent.FLAG_UPDATE_CURRENT or android.app.PendingIntent.FLAG_IMMUTABLE
        return android.app.PendingIntent.getBroadcast(context, requestCode, intent, flags)
    }

    private fun loadArtwork(context: Context, uriStr: String?): Bitmap? {
        if (uriStr == null || uriStr.isEmpty()) return null
        try {
            if (uriStr.startsWith("http")) {
                var url = URL(uriStr)
                var connection = url.openConnection() as HttpURLConnection
                connection.instanceFollowRedirects = true
                connection.setRequestProperty("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36")
                var status = connection.responseCode
                var redirectCount = 0
                while ((status == HttpURLConnection.HTTP_MOVED_TEMP || 
                        status == HttpURLConnection.HTTP_MOVED_PERM || 
                        status == HttpURLConnection.HTTP_SEE_OTHER) && redirectCount < 5) {
                    val newUrl = connection.getHeaderField("Location")
                    connection.disconnect()
                    url = URL(newUrl)
                    connection = url.openConnection() as HttpURLConnection
                    connection.instanceFollowRedirects = true
                    connection.setRequestProperty("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36")
                    status = connection.responseCode
                    redirectCount++
                }
                if (status == HttpURLConnection.HTTP_OK) {
                    val input: InputStream = connection.inputStream
                    val bitmap = BitmapFactory.decodeStream(input)
                    input.close()
                    connection.disconnect()
                    return bitmap
                }
            } else if (uriStr.startsWith("content://") || uriStr.startsWith("android.resource://")) {
                val uri = android.net.Uri.parse(uriStr)
                val input = context.contentResolver.openInputStream(uri)
                val bitmap = BitmapFactory.decodeStream(input)
                input?.close()
                return bitmap
            } else if (uriStr.startsWith("file://") || uriStr.startsWith("/")) {
                val cleanPath = uriStr.replace("file://", "")
                return BitmapFactory.decodeFile(cleanPath)
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
        return null
    }

    private fun getRoundedCornerBitmap(bitmap: Bitmap?, pixels: Int): Bitmap? {
        if (bitmap == null) return null
        val output = Bitmap.createBitmap(bitmap.width, bitmap.height, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(output)
        val color = -0xbdbdbe
        val paint = Paint()
        val rect = Rect(0, 0, bitmap.width, bitmap.height)
        val rectF = RectF(rect)
        val roundPx = pixels.toFloat()
        paint.isAntiAlias = true
        canvas.drawARGB(0, 0, 0, 0)
        paint.color = color
        canvas.drawRoundRect(rectF, roundPx, roundPx, paint)
        paint.xfermode = PorterDuffXfermode(PorterDuff.Mode.SRC_IN)
        canvas.drawBitmap(bitmap, rect, rect, paint)
        return output
    }

    private fun getTopRoundedCornerBitmap(bitmap: Bitmap?, pixels: Int): Bitmap? {
        if (bitmap == null) return null
        val output = Bitmap.createBitmap(bitmap.width, bitmap.height, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(output)
        val color = -0xbdbdbe
        val paint = Paint()
        val rect = Rect(0, 0, bitmap.width, bitmap.height)
        val rectF = RectF(rect)
        val roundPx = pixels.toFloat()
        paint.isAntiAlias = true
        canvas.drawARGB(0, 0, 0, 0)
        paint.color = color
        
        canvas.drawRoundRect(rectF, roundPx, roundPx, paint)
        val bottomRect = RectF(0f, bitmap.height / 2f, bitmap.width.toFloat(), bitmap.height.toFloat())
        canvas.drawRect(bottomRect, paint)
        
        paint.xfermode = PorterDuffXfermode(PorterDuff.Mode.SRC_IN)
        canvas.drawBitmap(bitmap, rect, rect, paint)
        return output
    }

    private fun darkenBitmap(bitmap: Bitmap, factor: Float): Bitmap {
        val result = Bitmap.createBitmap(bitmap.width, bitmap.height, bitmap.config ?: Bitmap.Config.ARGB_8888)
        val canvas = Canvas(result)
        val paint = Paint().apply {
            isAntiAlias = true
        }
        canvas.drawBitmap(bitmap, 0f, 0f, paint)
        canvas.drawColor(android.graphics.Color.argb((factor * 255).toInt(), 0, 0, 0))
        return result
    }

    private fun blur(sentBitmap: Bitmap, radius: Int): Bitmap {
        val bitmap = sentBitmap.copy(sentBitmap.config ?: Bitmap.Config.ARGB_8888, true)
        if (radius < 1) return sentBitmap
        val w = bitmap.width
        val h = bitmap.height
        val pix = IntArray(w * h)
        bitmap.getPixels(pix, 0, w, 0, 0, w, h)
        val wm = w - 1
        val hm = h - 1
        val wh = w * h
        val div = radius + radius + 1
        val r = IntArray(wh)
        val g = IntArray(wh)
        val b = IntArray(wh)
        var rsum: Int
        var gsum: Int
        var bsum: Int
        var x: Int
        var y: Int
        var i: Int
        var p: Int
        var yp: Int
        var yi: Int
        var yw: Int
        val vmin = IntArray(Math.max(w, h))
        var divsum = div + 1 shr 1
        divsum *= divsum
        val dv = IntArray(256 * divsum)
        i = 0
        while (i < 256 * divsum) {
            dv[i] = i / divsum
            i++
        }
        yi = 0
        yw = 0
        val stack = Array(div) { IntArray(3) }
        var stackpointer: Int
        var stackstart: Int
        var sir: IntArray
        var rbs: Int
        val r1 = radius + 1
        var routsum: Int
        var goutsum: Int
        var boutsum: Int
        var rinsum: Int
        var ginsum: Int
        var binsum: Int
        y = 0
        while (y < h) {
            bsum = 0
            gsum = bsum
            rsum = gsum
            boutsum = rsum
            goutsum = boutsum
            routsum = goutsum
            binsum = routsum
            ginsum = binsum
            rinsum = ginsum
            i = -radius
            while (i <= radius) {
                p = pix[yi + Math.min(wm, Math.max(i, 0))]
                sir = stack[i + radius]
                sir[0] = p and 0xff0000 shr 16
                sir[1] = p and 0x00ff00 shr 8
                sir[2] = p and 0x0000ff
                rbs = r1 - Math.abs(i)
                rsum += sir[0] * rbs
                gsum += sir[1] * rbs
                bsum += sir[2] * rbs
                if (i > 0) {
                    rinsum += sir[0]
                    ginsum += sir[1]
                    binsum += sir[2]
                } else {
                    routsum += sir[0]
                    goutsum += sir[1]
                    boutsum += sir[2]
                }
                i++
            }
            stackpointer = radius
            x = 0
            while (x < w) {
                r[yi] = dv[rsum]
                g[yi] = dv[gsum]
                b[yi] = dv[bsum]
                rsum -= routsum
                gsum -= goutsum
                bsum -= boutsum
                stackstart = stackpointer - radius + div
                sir = stack[stackstart % div]
                routsum -= sir[0]
                goutsum -= sir[1]
                boutsum -= sir[2]
                if (y == 0) {
                    vmin[x] = Math.min(x + radius + 1, wm)
                }
                p = pix[yw + vmin[x]]
                sir[0] = p and 0xff0000 shr 16
                sir[1] = p and 0x00ff00 shr 8
                sir[2] = p and 0x0000ff
                rinsum += sir[0]
                ginsum += sir[1]
                binsum += sir[2]
                rsum += rinsum
                gsum += ginsum
                bsum += binsum
                stackpointer = (stackpointer + 1) % div
                sir = stack[stackpointer % div]
                routsum += sir[0]
                goutsum += sir[1]
                boutsum += sir[2]
                rinsum -= sir[0]
                ginsum -= sir[1]
                binsum -= sir[2]
                yi++
                x++
            }
            yw += w
            y++
        }
        x = 0
        while (x < w) {
            bsum = 0
            gsum = bsum
            rsum = gsum
            boutsum = rsum
            goutsum = boutsum
            routsum = goutsum
            binsum = routsum
            ginsum = binsum
            rinsum = ginsum
            i = -radius
            while (i <= radius) {
                yi = Math.max(0, i) * w + x
                sir = stack[i + radius]
                sir[0] = r[yi]
                sir[1] = g[yi]
                sir[2] = b[yi]
                rbs = r1 - Math.abs(i)
                rsum += r[yi] * rbs
                gsum += g[yi] * rbs
                bsum += b[yi] * rbs
                if (i > 0) {
                    rinsum += sir[0]
                    ginsum += sir[1]
                    binsum += sir[2]
                } else {
                    routsum += sir[0]
                    goutsum += sir[1]
                    boutsum += sir[2]
                }
                i++
            }
            stackpointer = radius
            y = 0
            while (y < h) {
                pix[x + y * w] = -0x1000000 or (dv[rsum] shl 16) or (dv[gsum] shl 8) or dv[bsum]
                rsum -= routsum
                gsum -= goutsum
                bsum -= boutsum
                stackstart = stackpointer - radius + div
                sir = stack[stackstart % div]
                routsum -= sir[0]
                goutsum -= sir[1]
                boutsum -= sir[2]
                if (x == 0) {
                    vmin[y] = Math.min(y + r1, hm) * w
                }
                p = x + vmin[y]
                sir[0] = r[p]
                sir[1] = g[p]
                sir[2] = b[p]
                rinsum += sir[0]
                ginsum += sir[1]
                binsum += sir[2]
                rsum += rinsum
                gsum += ginsum
                bsum += binsum
                stackpointer = (stackpointer + 1) % div
                sir = stack[stackpointer % div]
                routsum += sir[0]
                goutsum += sir[1]
                boutsum += sir[2]
                rinsum -= sir[0]
                ginsum -= sir[1]
                binsum -= sir[2]
                yi = Math.max(0, i) * w + x
                i++
                y++
            }
            x++
        }
        bitmap.setPixels(pix, 0, w, 0, 0, w, h)
        return bitmap
    }

    private fun saveToSharedPreferences(
        context: Context,
        title: String,
        artist: String,
        album: String,
        artworkUri: String?,
        isPlaying: Boolean,
        shuffleMode: Int,
        repeatMode: Int,
        songId: String,
        duration: Long,
        position: Long
    ) {
        val prefs = context.getSharedPreferences("da_tunes_widget_prefs", Context.MODE_PRIVATE)
        prefs.edit().apply {
            putString("title", title)
            putString("artist", artist)
            putString("album", album)
            putString("artworkUri", artworkUri)
            putBoolean("isPlaying", isPlaying)
            putInt("shuffleMode", shuffleMode)
            putInt("repeatMode", repeatMode)
            putString("songId", songId)
            putLong("duration", duration)
            putLong("position", position)
            apply()
        }
    }

    fun updateFromCache(context: Context) {
        val prefs = context.getSharedPreferences("da_tunes_widget_prefs", Context.MODE_PRIVATE)
        val title = prefs.getString("title", "Not Playing") ?: "Not Playing"
        val artist = prefs.getString("artist", "DA Tunes") ?: "DA Tunes"
        val album = prefs.getString("album", "") ?: ""
        val artworkUri = prefs.getString("artworkUri", null)
        val isPlaying = prefs.getBoolean("isPlaying", false)
        val shuffleMode = prefs.getInt("shuffleMode", PlaybackStateCompat.SHUFFLE_MODE_NONE)
        val repeatMode = prefs.getInt("repeatMode", PlaybackStateCompat.REPEAT_MODE_NONE)
        val songId = prefs.getString("songId", "") ?: ""
        val duration = prefs.getLong("duration", 0L)
        val position = prefs.getLong("position", 0L)

        DAApplication.instance?.connectMediaBrowser()
        triggerArtworkLoading(context, artworkUri)
        renderWidgets(context, title, artist, album, isPlaying, shuffleMode, repeatMode, songId, duration, position, isPartial = false)
    }
}

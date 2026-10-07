import 'dart:io';
import 'package:flutter/material.dart';
import '../../core/services/device_memory_manager.dart';

class DAImage extends StatelessWidget {
  static String? cacheDirPath;
  static String? documentsDirPath;

  final String? url;
  final double? width;
  final double? height;
  final BoxFit fit;
  final Widget? placeholder;
  final Widget Function(BuildContext, Object, StackTrace?)? errorBuilder;
  final String? trackId;
  final String? albumId;
  final String? artistId;
  final bool isTrack;

  const DAImage({
    super.key,
    required this.url,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.placeholder,
    this.errorBuilder,
    this.trackId,
    this.albumId,
    this.artistId,
    this.isTrack = true,
  });

  @override
  Widget build(BuildContext context) {
    var cleanUrl = url?.trim();

    if (trackId != null && trackId!.isNotEmpty) {
      if (cacheDirPath != null) {
        final cachedArtwork = File('$cacheDirPath/da_tunes_cache/$trackId.jpg');
        if (cachedArtwork.existsSync()) {
          cleanUrl = cachedArtwork.path;
        } else {
          final prefetchedArtwork = File('$cacheDirPath/da_tunes_prefetch/$trackId.jpg');
          if (prefetchedArtwork.existsSync()) {
            cleanUrl = prefetchedArtwork.path;
          }
        }
      }
      if ((cleanUrl == null || cleanUrl.startsWith('http')) && documentsDirPath != null) {
        final downloadedArtwork = File('$documentsDirPath/da_tunes_downloads/$trackId.jpg');
        if (downloadedArtwork.existsSync()) {
          cleanUrl = downloadedArtwork.path;
        }
      }
    }

    if ((cleanUrl == null || cleanUrl.isEmpty) && isTrack) {
      cleanUrl = 'assets/images/da_placeholder.jpg';
    } else if (cleanUrl == 'assets/images/da_placeholder.jpg' && !isTrack) {
      cleanUrl = '';
    }

    final fallback = placeholder ?? Container(
      width: width,
      height: height,

      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(8.0),
      ),
      child: const Center(
        child: Icon(Icons.music_note_outlined, color: Colors.white30),
      ),
    );

    if (cleanUrl == null || cleanUrl.isEmpty) {
      return fallback;
    }

    String filePath = cleanUrl;
    if (filePath.startsWith('file://')) {
      try {
        filePath = Uri.parse(filePath).toFilePath();
      } catch (_) {
        filePath = filePath.replaceFirst('file://', '');
      }
    }

    final hasNetwork = cleanUrl.startsWith('http://') || cleanUrl.startsWith('https://');
    final hasAsset = cleanUrl.startsWith('assets/');

    final dpr = MediaQuery.maybeOf(context)?.devicePixelRatio ?? 2.0;
    final int targetWidth = width != null
        ? DeviceMemoryManager.instance.getTargetCacheDimension(width!, devicePixelRatio: dpr)
        : DeviceMemoryManager.instance.getTargetCacheDimension(400, devicePixelRatio: dpr);
    final int targetHeight = height != null
        ? DeviceMemoryManager.instance.getTargetCacheDimension(height!, devicePixelRatio: dpr)
        : DeviceMemoryManager.instance.getTargetCacheDimension(400, devicePixelRatio: dpr);

    if (hasAsset) {
      return Image.asset(
        cleanUrl,
        width: width,
        height: height,
        fit: fit,
        cacheWidth: targetWidth,
        cacheHeight: targetHeight,
        frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
          if (frame != null) return child;
          return fallback;
        },
        errorBuilder: (ctx, err, st) => fallback,
      );
    }

    if (hasNetwork) {
      return Image.network(
        cleanUrl,
        width: width,
        height: height,
        fit: fit,
        cacheWidth: targetWidth,
        cacheHeight: targetHeight,
        frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
          if (frame != null) return child;
          return fallback;
        },
        errorBuilder: (ctx, err, st) {
          return errorBuilder?.call(ctx, err, st) ?? fallback;
        },
      );
    } else {
      final file = File(filePath);
      if (file.existsSync()) {
        return Image.file(
          file,
          width: width,
          height: height,
          fit: fit,
          cacheWidth: targetWidth,
          cacheHeight: targetHeight,
          frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
            if (frame != null) return child;
            return fallback;
          },
          errorBuilder: (ctx, err, st) => fallback,
        );
      }
      return fallback;
    }
  }
}

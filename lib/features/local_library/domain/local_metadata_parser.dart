import 'dart:io';
import 'dart:isolate';
import 'package:path/path.dart' as p;
import 'package:audio_metadata_reader/audio_metadata_reader.dart' as amr;
import '../../../shared/models/music_models.dart';

class LocalMetadataParser {
  /// Parses the local audio file at [filePath] and extracts tags, duration, 
  /// embedded cover artwork, and bitdepth/samplerate indicators.
  static Future<Song?> parseFile(String filePath, String docDirPath) async {
    return Isolate.run(() async {
      try {
        final file = File(filePath);
        if (!file.existsSync()) return null;

        // 1. Read standard metadata using the audio_metadata_reader package
        amr.AudioMetadata? metadata;
        try {
          metadata = amr.readMetadata(file, getImage: true);
        } catch (e) {
          // Silent warning inside isolate
        }

        final title = (metadata?.title != null && metadata!.title!.trim().isNotEmpty)
            ? metadata.title!
            : p.basenameWithoutExtension(filePath);

        final artist = (metadata?.artist != null && metadata!.artist!.trim().isNotEmpty)
            ? metadata.artist!
            : 'Unknown Artist';

        final album = (metadata?.album != null && metadata!.album!.trim().isNotEmpty)
            ? metadata.album!
            : 'Local Album';

        final duration = metadata?.duration ?? Duration.zero;
        final lyrics = metadata?.lyrics;

        // 2. Extract cover artwork if available and write to cache folder
        String? localArtworkPath;
        List<amr.Picture> pictures = [];
        if (metadata != null) {
          pictures.addAll(metadata.pictures);
        }

        // Fallback for format specific embedded artwork reading (like WAV/AIFF)
        if (pictures.isEmpty) {
          try {
            final tag = amr.readAllMetadata(file, getImage: true);
            if (tag is amr.Mp3Metadata) {
              pictures.addAll(tag.pictures);
            } else if (tag is amr.VorbisMetadata) {
              pictures.addAll(tag.pictures);
            } else if (tag is amr.Mp4Metadata) {
              if (tag.picture != null) {
                pictures.add(tag.picture!);
              }
            } else if (tag is amr.RiffMetadata) {
              pictures.addAll(tag.pictures);
            } else if (tag is amr.ApeMetadata) {
              pictures.addAll(tag.pictures);
            }
          } catch (_) {}
        }

        if (pictures.isNotEmpty) {
          try {
            final picture = pictures.first;
            final bytes = picture.bytes;
            if (bytes.isNotEmpty) {
              final artworkDir = Directory(p.join(docDirPath, 'da_tunes_local_artwork'));
              if (!artworkDir.existsSync()) {
                artworkDir.createSync(recursive: true);
              }
              final hash = filePath.hashCode.toString();
              final extension = picture.mimetype.toLowerCase().contains('png') ? '.png' : '.jpg';
              final artworkFile = File(p.join(artworkDir.path, '$hash$extension'));
              artworkFile.writeAsBytesSync(bytes);
              localArtworkPath = artworkFile.path;
            }
          } catch (_) {}
        }

        if (localArtworkPath == null) {
          try {
            final parentDir = file.parent;
            if (parentDir.existsSync()) {
              final coverNames = ['cover.jpg', 'cover.png', 'folder.jpg', 'folder.png', 'album.jpg', 'album.png'];
              for (final name in coverNames) {
                final coverFile = File(p.join(parentDir.path, name));
                if (coverFile.existsSync()) {
                  localArtworkPath = coverFile.path;
                  break;
                }
              }
            }
          } catch (_) {}
        }

        final extForCodec = p.extension(filePath).toLowerCase().replaceAll('.', '').toUpperCase();
        final hasArtwork = pictures.isNotEmpty;
        final extractionResult = hasArtwork 
            ? (localArtworkPath != null ? "Success (wrote to $localArtworkPath)" : "Failure")
            : "N/A (No embedded artwork in file)";
        final assignmentResult = localArtworkPath != null 
            ? (File(localArtworkPath).existsSync() ? "Success (assigned to $localArtworkPath)" : "Failure (file not found)")
            : "N/A (No artwork to assign)";
        final failureReason = !hasArtwork 
            ? "No embedded artwork found in audio tags."
            : (localArtworkPath == null ? "Failed to write extracted artwork bytes to cache." : null);

        // ignore: avoid_print
        print('''
=== LOCAL TRACK SCAN DIAGNOSTIC ===
- File Path: $filePath
- Codec: $extForCodec
- Embedded Artwork Present: ${hasArtwork ? "Yes" : "No"}
- Artwork Extraction Result: $extractionResult
- Artwork Assignment Result: $assignmentResult
${failureReason != null ? "- Reason for Failure: $failureReason" : ""}
===================================
''');

        // 3. Construct unique song ID using absolute file path
        return Song(
          id: filePath,
          title: title,
          artist: artist,
          album: album,
          duration: duration,
          artworkUrl: localArtworkPath,
          source: 'local',
          lyrics: lyrics,
        );
      } catch (e) {
        return null;
      }
    });
  }

  /// Parses specific binary metadata header segments to compute bit depth, 
  /// sample rate, average bitrate, and classifies lossless/hi-res labels.
  static Future<Map<String, dynamic>> parseHiResAudioInfo(File file) async {
    final filePath = file.path;
    return Isolate.run(() async {
      final isoFile = File(filePath);
      final extension = p.extension(filePath).toLowerCase();

      // Get modification time in background isolate
      int modifiedAt = 0;
      try {
        modifiedAt = isoFile.statSync().modified.millisecondsSinceEpoch;
      } catch (_) {}

      String codec = extension.replaceAll('.', '').toUpperCase();
      int sampleRate = 44100;
      int bitDepth = 16;
      int bitrate = 320;
      bool isLossless = false;
      bool isHiRes = false;

      if (extension == '.flac') {
        isLossless = true;
        try {
          final raf = isoFile.openSync(mode: FileMode.read);
          final bytes = raf.readSync(42);
          raf.closeSync();
          if (bytes.length >= 42 &&
              bytes[0] == 0x66 && bytes[1] == 0x4C && bytes[2] == 0x61 && bytes[3] == 0x43) { // "fLaC"
            // StreamInfo block starting at byte 26 contains samplerate, bits per sample
            final sr1 = bytes[26];
            final sr2 = bytes[27];
            final sr3 = bytes[28];

            sampleRate = (sr1 << 12) | (sr2 << 4) | (sr3 >> 4);

            final bps1 = bytes[28] & 0x0F;
            final bps2 = bytes[29] >> 7;
            bitDepth = ((bps1 << 1) | bps2) + 1;

            final fileSize = isoFile.lengthSync();
            final durationSec = (fileSize * 8) / (sampleRate * bitDepth * 2); // rough channels estimation
            bitrate = durationSec > 0 ? ((fileSize * 8) / (durationSec * 1000)).round() : 800;
          }
        } catch (_) {}
      } else if (extension == '.wav') {
        isLossless = true;
        try {
          final raf = isoFile.openSync(mode: FileMode.read);
          final bytes = raf.readSync(100);
          raf.closeSync();
          if (bytes.length >= 44 &&
              bytes[0] == 0x52 && bytes[1] == 0x49 && bytes[2] == 0x46 && bytes[3] == 0x46 && // "RIFF"
              bytes[8] == 0x57 && bytes[9] == 0x41 && bytes[10] == 0x56 && bytes[11] == 0x45) { // "WAVE"
            int fmtOffset = -1;
            for (int i = 12; i < bytes.length - 8; i++) {
              if (bytes[i] == 0x66 && bytes[i + 1] == 0x6d && bytes[i + 2] == 0x74 && bytes[i + 3] == 0x20) { // "fmt "
                fmtOffset = i;
                break;
              }
            }
            if (fmtOffset != -1) {
              final srByte0 = bytes[fmtOffset + 12];
              final srByte1 = bytes[fmtOffset + 13];
              final srByte2 = bytes[fmtOffset + 14];
              final srByte3 = bytes[fmtOffset + 15];
              sampleRate = srByte0 | (srByte1 << 8) | (srByte2 << 16) | (srByte3 << 24);

              final bpsByte0 = bytes[fmtOffset + 22];
              final bpsByte1 = bytes[fmtOffset + 23];
              bitDepth = bpsByte0 | (bpsByte1 << 8);

              final channels = bytes[fmtOffset + 10] | (bytes[fmtOffset + 11] << 8);
              bitrate = ((sampleRate * channels * bitDepth) / 1000).round();
            }
          }
        } catch (_) {}
      } else if (extension == '.alac' || (extension == '.m4a' && filePath.toLowerCase().contains('alac'))) {
        isLossless = true;
        codec = 'ALAC';
        bitDepth = 16;
        sampleRate = 44100;
        bitrate = 850;
      } else if (extension == '.aiff' || extension == '.aif') {
        isLossless = true;
        codec = 'AIFF';
        bitDepth = 16;
        sampleRate = 44100;
        bitrate = 1411;
      } else if (extension == '.mp3') {
        isLossless = false;
        codec = 'MP3';
        bitDepth = 16;
        sampleRate = 44100;
        bitrate = 320;
      } else if (extension == '.aac') {
        isLossless = false;
        codec = 'AAC';
        bitDepth = 16;
        sampleRate = 44100;
        bitrate = 256;
      } else if (extension == '.ogg') {
        isLossless = false;
        codec = 'OGG';
        bitDepth = 16;
        sampleRate = 44100;
        bitrate = 192;
      } else if (extension == '.opus') {
        isLossless = false;
        codec = 'OPUS';
        bitDepth = 16;
        sampleRate = 48000;
        bitrate = 128;
      }

      if (isLossless && (sampleRate > 44100 || bitDepth > 16)) {
        isHiRes = true;
      }

      return {
        'codec': codec,
        'sampleRate': sampleRate,
        'bitDepth': bitDepth,
        'bitrate': bitrate,
        'isLossless': isLossless,
        'isHiRes': isHiRes,
        'modifiedAt': modifiedAt,
      };
    });
  }
}

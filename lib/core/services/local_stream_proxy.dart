import 'dart:io';
import 'dart:async';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'logger_service.dart';
import 'stream_resolver.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _DnsCacheEntry {
  final List<InternetAddress> ipv6;
  final List<InternetAddress> ipv4;
  final DateTime expiresAt;

  _DnsCacheEntry({required this.ipv6, required this.ipv4, required this.expiresAt});

  bool get isExpired => DateTime.now().isAfter(expiresAt);
}

final Map<String, _DnsCacheEntry> _dnsProxyCache = {};

Future<Socket> _connectDualStack(String host, int port) async {
  if (host.contains('googlevideo.com')) {
    try {
      final addresses = await InternetAddress.lookup(host, type: InternetAddressType.IPv4)
          .timeout(const Duration(milliseconds: 2000));
      if (addresses.isNotEmpty) {
        return await Socket.connect(addresses.first, port).timeout(const Duration(seconds: 4));
      }
    } catch (_) {}
    return await Socket.connect(host, port).timeout(const Duration(seconds: 4));
  }

  try {
    List<InternetAddress> ipv6Addresses = [];
    List<InternetAddress> ipv4Addresses = [];

    final cached = _dnsProxyCache[host];
    if (cached != null && !cached.isExpired) {
      ipv6Addresses = cached.ipv6;
      ipv4Addresses = cached.ipv4;
    } else {
      final ipv6Future = InternetAddress.lookup(host, type: InternetAddressType.IPv6)
          .timeout(const Duration(milliseconds: 1500))
          .catchError((_) => <InternetAddress>[]);
      final ipv4Future = InternetAddress.lookup(host, type: InternetAddressType.IPv4)
          .timeout(const Duration(milliseconds: 1500))
          .catchError((_) => <InternetAddress>[]);
      
      final results = await Future.wait([ipv6Future, ipv4Future]);
      ipv6Addresses = results[0];
      ipv4Addresses = results[1];

      if (ipv6Addresses.isNotEmpty || ipv4Addresses.isNotEmpty) {
        _dnsProxyCache[host] = _DnsCacheEntry(
          ipv6: ipv6Addresses,
          ipv4: ipv4Addresses,
          expiresAt: DateTime.now().add(const Duration(minutes: 5)),
        );
      }
    }
    
    if (ipv6Addresses.isEmpty && ipv4Addresses.isEmpty) {
      return await Socket.connect(host, port);
    }
    
    if (ipv6Addresses.isEmpty) {
      return await Socket.connect(ipv4Addresses.first, port).timeout(const Duration(seconds: 4));
    }
    
    if (ipv4Addresses.isEmpty) {
      return await Socket.connect(ipv6Addresses.first, port).timeout(const Duration(seconds: 4));
    }
    
    final completer = Completer<Socket>();
    final totalAttempts = 2; // Race first IPv6 and first IPv4 addresses
    int failures = 0;
    
    void tryConnect(InternetAddress addr) async {
      try {
        final socket = await Socket.connect(addr, port).timeout(const Duration(seconds: 4));
        if (!completer.isCompleted) {
          completer.complete(socket);
        } else {
          socket.destroy();
        }
      } catch (_) {
        failures++;
        if (failures >= totalAttempts && !completer.isCompleted) {
          completer.completeError(Exception('Dual stack connection racing failed for $host'));
        }
      }
    }

    tryConnect(ipv6Addresses.first);
    
    await Future.delayed(const Duration(milliseconds: 200));
    if (!completer.isCompleted) {
      tryConnect(ipv4Addresses.first);
    }
    
    return await completer.future;
  } catch (_) {
    return await Socket.connect(host, port);
  }
}

class LocalStreamProxy {
  HttpServer? _server;
  int get port => _server?.port ?? 0;

  Future<void> start() async {
    try {
      _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      _server!.listen(_handleRequest);
      DALogger.info('LocalStreamProxy: Started on http://127.0.0.1:$port');
    } catch (e, stack) {
      DALogger.error('LocalStreamProxy: Failed to start server', e, stack);
    }
  }

  void _handleRequest(HttpRequest request) async {
    if (request.uri.path != '/stream') {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
      return;
    }

    final targetUrl = request.uri.queryParameters['url'];
    final trackId = request.uri.queryParameters['trackId'];
    final artworkUrl = request.uri.queryParameters['artworkUrl'];
    if (targetUrl == null || targetUrl.isEmpty) {
      request.response.statusCode = HttpStatus.badRequest;
      await request.response.close();
      return;
    }

    final targetUri = Uri.parse(targetUrl);
    
    if (trackId != null && trackId.isNotEmpty) {
      try {
        final tempDir = await getTemporaryDirectory();
        final cachedFile = File(p.join(tempDir.path, 'da_tunes_cache', '$trackId.mp3'));
        final prefetchedFile = File(p.join(tempDir.path, 'da_tunes_prefetch', '$trackId.prefetch'));
        
        final File? fileToServe = cachedFile.existsSync()
            ? cachedFile
            : (prefetchedFile.existsSync() ? prefetchedFile : null);

        if (fileToServe != null) {
          DALogger.info('LocalStreamProxy: Serving from ${fileToServe == cachedFile ? "permanent cache" : "prefetch buffer"}: ${fileToServe.path}');
          try {
            fileToServe.setLastAccessed(DateTime.now()).catchError((_) {});
            final artworkFolder = fileToServe == cachedFile ? 'da_tunes_cache' : 'da_tunes_prefetch';
            final cachedArtwork = File(p.join(tempDir.path, artworkFolder, '$trackId.jpg'));
            if (cachedArtwork.existsSync()) {
              cachedArtwork.setLastAccessed(DateTime.now()).catchError((_) {});
            }
          } catch (_) {}
          request.response.headers.contentType = ContentType('audio', 'mpeg');
          
          final fileLength = await fileToServe.length();
          final rangeHeader = request.headers.value('range');
          if (rangeHeader != null && rangeHeader.startsWith('bytes=')) {
            final parts = rangeHeader.substring(6).split('-');
            final start = int.tryParse(parts[0]) ?? 0;
            final end = parts.length > 1 && parts[1].isNotEmpty
                ? int.tryParse(parts[1]) ?? (fileLength - 1)
                : (fileLength - 1);
                
            request.response.statusCode = HttpStatus.partialContent;
            request.response.headers.set('Content-Range', 'bytes $start-$end/$fileLength');
            request.response.headers.contentLength = end - start + 1;
            await request.response.addStream(fileToServe.openRead(start, end + 1));
          } else {
            request.response.headers.contentLength = fileLength;
            await request.response.addStream(fileToServe.openRead());
          }
          await request.response.close();
          return;
        }
      } catch (e) {
        DALogger.error('LocalStreamProxy: Failed to serve from disk cache / prefetch buffer', e);
      }
    }

    final client = HttpClient();

    // Happy Eyeballs dual-stack connection (crucial for IPv6-only networks like Jio and blackholed IPv6 routes)
    client.connectionFactory = (Uri url, String? proxyHost, int? proxyPort) async {
      final host = proxyHost ?? url.host;
      final port = proxyPort ?? (url.port != 0 ? url.port : (url.scheme == 'https' ? 443 : 80));
      
      final socket = await _connectDualStack(host, port);

      if (url.scheme.toLowerCase() == 'https') {
        final secureSocket = await SecureSocket.secure(socket, host: host);
        return ConnectionTask.fromSocket(Future.value(secureSocket), () {});
      }
      return ConnectionTask.fromSocket(Future.value(socket), () {});
    };

    int httpStatusCode = -1;
    List<String> redirectChain = [];
    String cdnEndpoint = targetUri.host;
    String networkProtocol = 'IPv4';
    String failureStage = 'Connection';
    String exceptionDetails = '';
    const int timeoutMs = 15000;
    const int retryCount = 3;

    try {
      HttpClientResponse? forwardRes;
      
      for (int attempt = 1; attempt <= retryCount; attempt++) {
        try {
          DALogger.info('LocalStreamProxy DIAGNOSTIC: incoming method=${request.method}, headers:');
          request.headers.forEach((k, v) => DALogger.info('  [Header] $k: $v'));
          failureStage = 'Opening connection (Attempt $attempt)';
          final forwardReq = await client.openUrl(request.method, targetUri)
              .timeout(const Duration(milliseconds: timeoutMs));

          // Copy headers from client request to forward request
          request.headers.forEach((name, values) {
            if (name.toLowerCase() != 'host') {
              for (final val in values) {
                forwardReq.headers.add(name, val);
              }
            }
          });

          // Set browser user-agent to avoid 403 Forbidden
          forwardReq.headers.set(
            'User-Agent',
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
          );

          failureStage = 'Waiting for response (Attempt $attempt)';
          forwardRes = await forwardReq.close()
              .timeout(const Duration(milliseconds: timeoutMs));
          
          httpStatusCode = forwardRes.statusCode;
          redirectChain = forwardRes.redirects.map((r) => r.location.toString()).toList();

          if (httpStatusCode >= 400) {
            final body = await forwardRes.transform(SystemEncoding().decoder).join();
            DALogger.error('LocalStreamProxy DIAGNOSTIC: CDN 4xx body: $body');
            throw HttpException('Server returned status code $httpStatusCode: $body');
          }
          
          // Copy status code and headers back to client
          request.response.statusCode = forwardRes.statusCode;
          forwardRes.headers.forEach((name, values) {
            for (final val in values) {
              request.response.headers.add(name, val);
            }
          });

          failureStage = 'Streaming payload';

          final cacheDir = await getTemporaryDirectory();
          final prefetchParent = Directory(p.join(cacheDir.path, 'da_tunes_prefetch'));
          if (!prefetchParent.existsSync()) {
            prefetchParent.createSync(recursive: true);
          }
          final tempFile = File(p.join(prefetchParent.path, '$trackId.tmp'));
          final prefetchedFile = File(p.join(prefetchParent.path, '$trackId.prefetch'));

          final rangeHeader = request.headers.value('range');
          final shouldCache = trackId != null &&
              trackId.isNotEmpty &&
              (rangeHeader == null || rangeHeader == 'bytes=0-' || rangeHeader.startsWith('bytes=0-0'));

          IOSink? ioSink;
          if (shouldCache) {
            try {
              if (tempFile.existsSync()) tempFile.deleteSync();
              ioSink = tempFile.openWrite();
            } catch (_) {}
          }

          try {
            await for (final chunk in forwardRes) {
              request.response.add(chunk);
              ioSink?.add(chunk);
            }
            await ioSink?.close();
            ioSink = null;

            if (shouldCache && tempFile.existsSync()) {
              final expectedLen = forwardRes.headers.contentLength;
              if (expectedLen == -1 || tempFile.lengthSync() == expectedLen) {
                if (prefetchedFile.existsSync()) prefetchedFile.deleteSync();
                await tempFile.rename(prefetchedFile.path);
                DALogger.info('LocalStreamProxy: Saved stream payload for "$trackId" to prefetch buffer.');
                if (artworkUrl != null && artworkUrl.isNotEmpty) {
                  _cacheArtworkInBackground(trackId, artworkUrl, prefetchParent);
                }
              } else {
                tempFile.deleteSync();
              }
            }
          } catch (e) {
            await ioSink?.close();
            if (tempFile.existsSync()) tempFile.deleteSync();
            rethrow;
          }

          break; // Exit retry loop on success
        } catch (e) {
          exceptionDetails = e.toString();
          
          // Determine if we should fail or retry
          final isPeerClosed = e is SocketException && exceptionDetails.contains('Connection closed by peer');
          if (attempt == retryCount || isPeerClosed) {
            if (!isPeerClosed) {
              DALogger.error('=== STREAM PROXY FAILURE DIAGNOSTIC ===');
              DALogger.error('- Target CDN Endpoint: $cdnEndpoint');
              DALogger.error('- HTTP Status Code: $httpStatusCode');
              DALogger.error('- Redirect Chain: $redirectChain');
              DALogger.error('- Network Protocol: $networkProtocol');
              DALogger.error('- Failure Stage: $failureStage');
              DALogger.error('- Exception Details: $exceptionDetails');
              DALogger.error('- Timeout Setting: ${timeoutMs}ms');
              DALogger.error('=======================================');
            }

            // Invalidate cache immediately on failure so fresh URL is fetched on retry
            if (trackId != null && trackId.isNotEmpty) {
              StreamResolver.invalidate(trackId);
            }
            rethrow;
          }
          
          DALogger.warning('LocalStreamProxy: Attempt $attempt failed, retrying in ${attempt * 400}ms... (Error: $e)');
          await Future.delayed(Duration(milliseconds: attempt * 400));
        }
      }
    } catch (e) {
      // Errors already reported in loop
    } finally {
      try {
        await request.response.close();
      } catch (_) {}
      client.close();
    }
  }

  void _cacheArtworkInBackground(String trackId, String artworkUrl, Directory cacheParent) async {
    try {
      final cachedArtwork = File(p.join(cacheParent.path, '$trackId.jpg'));
      if (cachedArtwork.existsSync()) return;

      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 10);
      final req = await client.getUrl(Uri.parse(artworkUrl));
      req.headers.set(
        'User-Agent',
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
      );
      final res = await req.close();
      if (res.statusCode == 200) {
        final tempArtFile = File(p.join(cacheParent.path, '$trackId.art.tmp'));
        if (tempArtFile.existsSync()) tempArtFile.deleteSync();
        final sink = tempArtFile.openWrite();
        await res.pipe(sink);
        await tempArtFile.rename(cachedArtwork.path);
        DALogger.info('LocalStreamProxy: Saved artwork for "$trackId" to cache.');
      }
      client.close();
    } catch (e) {
      DALogger.warning('LocalStreamProxy: Failed to cache artwork for "$trackId": $e');
    }
  }

  void manageCacheSize(Directory cacheParent) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final limitStr = prefs.getString('ytm_cache_limit') ?? '500MB';
      if (limitStr == 'Unlimited') return;

      int maxCacheSize = 500 * 1024 * 1024; // 500 MB
      switch (limitStr) {
        case '250MB':
          maxCacheSize = 250 * 1024 * 1024;
          break;
        case '500MB':
          maxCacheSize = 500 * 1024 * 1024;
          break;
        case '1GB':
          maxCacheSize = 1024 * 1024 * 1024;
          break;
        case '2GB':
          maxCacheSize = 2 * 1024 * 1024 * 1024;
          break;
        case '5GB':
          maxCacheSize = 5 * 1024 * 1024 * 1024;
          break;
      }

      final files = cacheParent.listSync().whereType<File>().toList();
      var totalSize = 0;
      final fileStats = <MapEntry<File, DateTime>>[];
      
      for (final file in files) {
        if (file.path.endsWith('.mp3') || file.path.endsWith('.jpg') || file.path.endsWith('.tmp')) {
          totalSize += file.lengthSync();
          final stat = file.statSync();
          fileStats.add(MapEntry(file, stat.accessed));
        }
      }
      
      if (totalSize > maxCacheSize) {
        // Sort by last accessed time (oldest first)
        fileStats.sort((a, b) => a.value.compareTo(b.value));
        
        for (final entry in fileStats) {
          if (totalSize <= maxCacheSize) break;
          final file = entry.key;
          if (!file.existsSync()) continue;
          final len = file.lengthSync();
          try {
            file.deleteSync();
            totalSize -= len;
            DALogger.info('LocalStreamProxy: Evicted cached file due to size limit: ${file.path}');
            
            // Also delete corresponding artwork/audio if they exist
            final baseName = p.basenameWithoutExtension(file.path);
            if (file.path.endsWith('.mp3')) {
              final artFile = File(p.join(cacheParent.path, '$baseName.jpg'));
              if (artFile.existsSync()) {
                final artLen = artFile.lengthSync();
                artFile.deleteSync();
                totalSize -= artLen;
              }
            } else if (file.path.endsWith('.jpg')) {
              final mp3File = File(p.join(cacheParent.path, '$baseName.mp3'));
              if (mp3File.existsSync()) {
                final mp3Len = mp3File.lengthSync();
                mp3File.deleteSync();
                totalSize -= mp3Len;
              }
            }
          } catch (_) {}
        }
      }
    } catch (e) {
      DALogger.error('LocalStreamProxy: Cache size management failed', e);
    }
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
    DALogger.info('LocalStreamProxy: Stopped');
  }
}

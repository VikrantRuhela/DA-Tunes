import 'dart:io';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app/router/router.dart';
import 'app/theme/dynamic_theme_provider.dart';
import 'core/services/platform_service.dart';
import 'core/services/windows_platform_service.dart';
import 'core/services/default_platform_service.dart';
import 'core/services/json_storage_service.dart';
import 'shared/providers/library_providers.dart';
import 'shared/providers/backend_providers.dart';
import 'core/services/system_media_session_manager.dart';
import 'core/services/session_manager.dart';
import 'shared/providers/player_providers.dart';
import 'shared/widgets/da_image.dart';
import 'package:path_provider/path_provider.dart';

import 'package:desktop_webview_window/desktop_webview_window.dart';

import 'core/services/device_memory_manager.dart';
import 'core/services/startup_tracker.dart';
import 'core/services/logger_service.dart';

class DnsCacheEntry {
  final List<InternetAddress> ipv6;
  final List<InternetAddress> ipv4;
  final DateTime expiresAt;

  DnsCacheEntry({required this.ipv6, required this.ipv4, required this.expiresAt});

  bool get isExpired => DateTime.now().isAfter(expiresAt);
}

final Map<String, DnsCacheEntry> _dnsCache = {};

Future<Socket> connectDualStack(
  String host,
  int port, {
  bool isSecure = false,
  String? secureHost,
}) async {
  if (host == 'localhost' || host == '127.0.0.1' || host == '::1' || host == '0.0.0.0') {
    DALogger.info('[Network] connectDualStack: fast-path loopback bypass for $host');
    final socket = await Socket.connect(host, port).timeout(const Duration(seconds: 3));
    if (isSecure) {
      return await SecureSocket.secure(socket, host: secureHost ?? host);
    }
    return socket;
  }

  DALogger.info('[Network] connectDualStack starting: $host:$port (secure: $isSecure)');

  if (host.contains('googlevideo.com')) {
    DALogger.info('[Network] connectDualStack: host is googlevideo.com, forcing IPv4-only path');
    try {
      final addresses = await InternetAddress.lookup(host, type: InternetAddressType.IPv4)
          .timeout(const Duration(milliseconds: 2000));
      if (addresses.isNotEmpty) {
        DALogger.info('[Network] connectDualStack: googlevideo.com resolved to IPv4: ${addresses.first.address}');
        final connStart = DateTime.now();
        var socket = await Socket.connect(addresses.first, port).timeout(const Duration(seconds: 3));
        if (isSecure) {
          socket = await SecureSocket.secure(socket, host: secureHost ?? host).timeout(const Duration(seconds: 5));
        }
        DALogger.info('[Network] connectDualStack: googlevideo.com connected directly to IPv4 in ${DateTime.now().difference(connStart).inMilliseconds}ms');
        return socket;
      }
    } catch (err) {
      DALogger.warning('[Network] connectDualStack: googlevideo.com IPv4 lookup/connect failed: $err. Falling back to native connect.');
    }
    final socket = await Socket.connect(host, port).timeout(const Duration(seconds: 3));
    if (isSecure) {
      return await SecureSocket.secure(socket, host: secureHost ?? host).timeout(const Duration(seconds: 5));
    }
    return socket;
  }

  try {
    List<InternetAddress> ipv6Addresses = [];
    List<InternetAddress> ipv4Addresses = [];

    final cached = _dnsCache[host];
    if (cached != null && !cached.isExpired) {
      ipv6Addresses = cached.ipv6;
      ipv4Addresses = cached.ipv4;
      DALogger.info('[Network] connectDualStack: using cached DNS for $host. IPv6 count: ${ipv6Addresses.length}, IPv4 count: ${ipv4Addresses.length}');
    } else {
      DALogger.info('[Network] connectDualStack: resolving DNS for $host');
      final dnsStart = DateTime.now();

      final ipv6Future = InternetAddress.lookup(host, type: InternetAddressType.IPv6)
          .timeout(const Duration(milliseconds: 1500))
          .catchError((err) {
            DALogger.warning('[Network] connectDualStack: IPv6 lookup error for $host: $err');
            return <InternetAddress>[];
          });
      final ipv4Future = InternetAddress.lookup(host, type: InternetAddressType.IPv4)
          .timeout(const Duration(milliseconds: 1500))
          .catchError((err) {
            DALogger.warning('[Network] connectDualStack: IPv4 lookup error for $host: $err');
            return <InternetAddress>[];
          });

      final results = await Future.wait([ipv6Future, ipv4Future]);
      ipv6Addresses = results[0];
      ipv4Addresses = results[1];

      final dnsElapsed = DateTime.now().difference(dnsStart).inMilliseconds;
      DALogger.info('[Network] connectDualStack: DNS resolved for $host in ${dnsElapsed}ms. IPv6: ${ipv6Addresses.map((a) => a.address).toList()}, IPv4: ${ipv4Addresses.map((a) => a.address).toList()}');

      if (ipv6Addresses.isNotEmpty || ipv4Addresses.isNotEmpty) {
        _dnsCache[host] = DnsCacheEntry(
          ipv6: ipv6Addresses,
          ipv4: ipv4Addresses,
          expiresAt: DateTime.now().add(const Duration(minutes: 5)),
        );
      }
    }

    if (ipv6Addresses.isEmpty && ipv4Addresses.isEmpty) {
      DALogger.warning('[Network] connectDualStack: DNS lookup returned no addresses for $host. Falling back to native connect.');
      final socket = await Socket.connect(host, port).timeout(const Duration(seconds: 3));
      if (isSecure) {
        return await SecureSocket.secure(socket, host: secureHost ?? host).timeout(const Duration(seconds: 5));
      }
      return socket;
    }

    if (ipv6Addresses.isEmpty) {
      DALogger.info('[Network] connectDualStack: IPv6 empty for $host. Connecting directly to IPv4: ${ipv4Addresses.first.address}');
      final connStart = DateTime.now();
      var socket = await Socket.connect(ipv4Addresses.first, port).timeout(const Duration(seconds: 3));
      if (isSecure) {
        socket = await SecureSocket.secure(socket, host: secureHost ?? host).timeout(const Duration(seconds: 5));
      }
      DALogger.info('[Network] connectDualStack: directly connected and secured to IPv4 ${ipv4Addresses.first.address} for $host in ${DateTime.now().difference(connStart).inMilliseconds}ms');
      return socket;
    }

    if (ipv4Addresses.isEmpty) {
      DALogger.info('[Network] connectDualStack: IPv4 empty for $host. Connecting directly to IPv6: ${ipv6Addresses.first.address}');
      final connStart = DateTime.now();
      var socket = await Socket.connect(ipv6Addresses.first, port).timeout(const Duration(seconds: 3));
      if (isSecure) {
        socket = await SecureSocket.secure(socket, host: secureHost ?? host).timeout(const Duration(seconds: 5));
      }
      DALogger.info('[Network] connectDualStack: directly connected and secured to IPv6 ${ipv6Addresses.first.address} for $host in ${DateTime.now().difference(connStart).inMilliseconds}ms');
      return socket;
    }

    DALogger.info('[Network] connectDualStack: racing connection for $host. IPv6 target: ${ipv6Addresses.first.address}, IPv4 target: ${ipv4Addresses.first.address}');
    final completer = Completer<Socket>();
    const totalAttempts = 2;
    int failures = 0;

    void tryConnect(InternetAddress addr) async {
      final connStart = DateTime.now();
      DALogger.info('[Network] Racing connection attempt start: ${addr.address} ($host)');
      try {
        var socket = await Socket.connect(addr, port).timeout(const Duration(seconds: 3));
        if (isSecure) {
          DALogger.info('[Network] Racing connection upgrading socket to SecureSocket for ${addr.address} ($host)');
          socket = await SecureSocket.secure(socket, host: secureHost ?? host).timeout(const Duration(seconds: 5));
        }
        final elapsed = DateTime.now().difference(connStart).inMilliseconds;
        if (!completer.isCompleted) {
          DALogger.info('[Network] Racing connection won by ${addr.address} ($host) in ${elapsed}ms (secure: $isSecure)');
          completer.complete(socket);
        } else {
          DALogger.info('[Network] Racing connection completed but lost race: ${addr.address} ($host) in ${elapsed}ms. Destroying socket.');
          socket.destroy();
        }
      } catch (err) {
        final elapsed = DateTime.now().difference(connStart).inMilliseconds;
        DALogger.warning('[Network] Racing connection failed: ${addr.address} ($host) in ${elapsed}ms with error: $err');
        failures++;
        if (failures >= totalAttempts && !completer.isCompleted) {
          DALogger.error('[Network] Racing connection: all connection attempts failed for $host');
          completer.completeError(Exception('Dual stack connection racing failed for $host'));
        }
      }
    }

    tryConnect(ipv6Addresses.first);

    await Future.delayed(const Duration(milliseconds: 150));
    if (!completer.isCompleted) {
      DALogger.info('[Network] Racing connection: 150ms elapsed, starting fallback connection to IPv4: ${ipv4Addresses.first.address}');
      tryConnect(ipv4Addresses.first);
    }

    return await completer.future.timeout(
      const Duration(seconds: 8),
      onTimeout: () {
        if (!completer.isCompleted) {
          DALogger.error('[Network] Racing connection timeout (8s) hit for $host. Retrying raw native connect.');
          completer.completeError(TimeoutException('Dual stack connection timeout for $host'));
        }
        return () async {
          final socket = await Socket.connect(host, port).timeout(const Duration(seconds: 3));
          if (isSecure) {
            return await SecureSocket.secure(socket, host: secureHost ?? host).timeout(const Duration(seconds: 5));
          }
          return socket;
        }();
      },
    );
  } catch (err) {
    DALogger.error('[Network] connectDualStack error fallback to native connect for $host: $err');
    final socket = await Socket.connect(host, port).timeout(const Duration(seconds: 3));
    if (isSecure) {
      return await SecureSocket.secure(socket, host: secureHost ?? host).timeout(const Duration(seconds: 5));
    }
    return socket;
  }
}

class FallbackHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final client = super.createHttpClient(context);
    client.connectionFactory = (Uri url, String? proxyHost, int? proxyPort) async {
      final host = proxyHost ?? url.host;
      final port = proxyPort ?? (url.port != 0 ? url.port : (url.scheme == 'https' ? 443 : 80));

      DALogger.info('[Network] connectionFactory request URL: $url, proxyHost: $proxyHost, proxyPort: $proxyPort');

      if (host == 'localhost' || host == '127.0.0.1' || host == '::1' || host == '0.0.0.0') {
        DALogger.info('[Network] connectionFactory loopback bypass for $host');
        final socket = await Socket.connect(host, port).timeout(const Duration(seconds: 3));
        if (url.scheme.toLowerCase() == 'https') {
          DALogger.info('[Network] connectionFactory upgrading loopback socket to SecureSocket for $host');
          try {
            final secureSocket = await SecureSocket.secure(socket, host: host);
            DALogger.info('[Network] connectionFactory upgraded loopback socket successfully for $host');
            return ConnectionTask.fromSocket(Future.value(secureSocket), () {});
          } catch (err) {
            DALogger.error('[Network] connectionFactory loopback SecureSocket upgrade failed for $host: $err');
            rethrow;
          }
        }
        return ConnectionTask.fromSocket(Future.value(socket), () {});
      }

      DALogger.info('[Network] connectionFactory dual stack resolution for $host:$port');
      final isSecure = url.scheme.toLowerCase() == 'https';
      final socket = await connectDualStack(host, port, isSecure: isSecure, secureHost: host);
      DALogger.info('[Network] connectionFactory socket established for $host:$port (secure: $isSecure)');
      return ConnectionTask.fromSocket(Future.value(socket), () {});
    };
    return client;
  }
}

void main([List<String> args = const []]) async {
  StartupTracker.startStallDetector();
  final mainStep = StartupTracker.startStep('Total Application Launch');

  await StartupTracker.runStep('HTTP Overrides & Flutter Binding', () async {
    HttpOverrides.global = FallbackHttpOverrides();
    WidgetsFlutterBinding.ensureInitialized();
    DeviceMemoryManager.instance.initialize();
  });

  await StartupTracker.runStep('Cache & Documents Paths', () async {
    try {
      final tempDir = await getTemporaryDirectory();
      DAImage.cacheDirPath = tempDir.path;
      final docDir = await getApplicationDocumentsDirectory();
      DAImage.documentsDirPath = docDir.path;
    } catch (_) {}
  });

  if (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
    if (runWebViewTitleBarWidget(args)) {
      return;
    }
  }

  final PlatformService platformService = !kIsWeb && Platform.isWindows
      ? WindowsPlatformService()
      : DefaultPlatformService();

  await StartupTracker.runStep('Platform Window Initialization', () async {
    await platformService.initializeWindow();
  });

  final storageService = JsonStorageService();
  await StartupTracker.runStep('Local JsonStorage Initialization', () async {
    await storageService.init();
  });

  final container = ProviderContainer(
    overrides: [
      storageServiceProvider.overrideWithValue(storageService),
    ],
  );

  if (!kIsWeb && Platform.isWindows) {
    WindowsPlatformService.onShutdown = () async {
      final startTime = DateTime.now();
      debugPrint(' [Shutdown] Starting clean shutdown sequence...');

      final stopPlayerTime = DateTime.now();
      try {
        final playbackEngine = container.read(playbackEngineProvider);
        await playbackEngine.dispose();
        debugPrint(' [Shutdown] Audio player disposed in ${DateTime.now().difference(stopPlayerTime).inMilliseconds}ms');
      } catch (e) {
        debugPrint(' [Shutdown] Audio player disposal failed: $e');
      }

      final stopProxyTime = DateTime.now();
      try {
        final proxy = container.read(localStreamProxyProvider);
        await proxy.stop();
        debugPrint(' [Shutdown] Local stream proxy stopped in ${DateTime.now().difference(stopProxyTime).inMilliseconds}ms');
      } catch (e) {
        debugPrint(' [Shutdown] Local stream proxy stop failed: $e');
      }

      final stopDbTime = DateTime.now();
      try {
        final db = container.read(appDatabaseProvider);
        await db.close();
        debugPrint(' [Shutdown] Database closed in ${DateTime.now().difference(stopDbTime).inMilliseconds}ms');
      } catch (e) {
        debugPrint(' [Shutdown] Database close failed: $e');
      }

      final disposeContainerTime = DateTime.now();
      container.dispose();
      debugPrint(' [Shutdown] Riverpod container disposed in ${DateTime.now().difference(disposeContainerTime).inMilliseconds}ms');

      debugPrint(' [Shutdown] Clean shutdown completed in ${DateTime.now().difference(startTime).inMilliseconds}ms');
    };
  }

  final goRouter = container.read(goRouterProvider);
  container.read(sessionManagerProvider).onSessionExpired = () {
    goRouter.go('/welcome');
  };

  unawaited(_performPostAppLaunchInitialization(container));

  StartupTracker.endStep(mainStep, success: true);
  StartupTracker.printSummary();

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const DAMusicApp(),
    ),
  );
}

Future<void> _performPostAppLaunchInitialization(ProviderContainer container) async {
  await StartupTracker.runStep('MediaSession & AudioService Binding', () async {
    try {
      final controller = container.read(playbackControllerProvider);
      await SystemMediaSessionManager.initialize(controller);
    } catch (e) {
      debugPrint(' [Startup] MediaSession initialization warning: $e');
    }
  });

  await StartupTracker.runStep('YouTube Music Account Session Restore', () async {
    try {
      final accountService = container.read(ytAccountServiceProvider);
      await accountService.initialize();

      if (accountService.isLoggedIn) {
        container.read(ytmSyncManagerProvider.notifier).startSync();
      }
    } catch (e) {
      debugPrint(' [Startup] Account service initialization warning: $e');
    }
  });
  StartupTracker.stopStallDetector();
}

class DAMusicApp extends ConsumerWidget {
  const DAMusicApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeData = ref.watch(activeThemeProvider);
    final goRouter = ref.watch(goRouterProvider);

    ref.listen<SessionManager>(sessionManagerProvider, (previous, next) {
      if (next.isLoggedIn && !(previous?.isLoggedIn ?? false)) {
        ref.read(ytmSyncManagerProvider.notifier).startSync();
      }
    });

    return MaterialApp.router(
      title: 'DA Tunes',
      debugShowCheckedModeBanner: false,
      theme: themeData,
      darkTheme: themeData,
      themeMode: ThemeMode.dark,
      routerConfig: goRouter,
      builder: (context, child) {
        return AnimatedTheme(
          data: themeData,
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeInOut,
          child: child ?? const SizedBox.shrink(),
        );
      },
    );
  }
}

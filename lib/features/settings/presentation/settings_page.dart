import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../app/theme/tokens.dart';
import '../../../core/extensions/context_extensions.dart';
import '../../../core/services/logger_service.dart';
import '../../../core/services/ytm_sync_manager.dart';
import '../../../shared/animations/motion_system.dart';
import '../../../shared/providers/source_providers.dart';
import '../../../shared/providers/library_providers.dart';
import '../../../shared/providers/player_providers.dart';
import '../../../shared/providers/theme_providers.dart';
import '../../../shared/providers/backend_providers.dart' hide sourceManagerProvider;
import '../../../shared/widgets/da_card.dart';
import '../../taste_engine/presentation/music_dna_page.dart';
import '../../taste_engine/presentation/taste_settings_page.dart';
import '../../taste_engine/presentation/providers/taste_engine_providers.dart';
import '../../onboarding/presentation/widgets/auth_webview_page.dart';
import '../../onboarding/presentation/widgets/cookie_login_dialog.dart';
import 'about_page.dart';

final diagnosticLoggingProvider = StateProvider<bool>((ref) {
  return DALogger.activeLevel == LogLevel.debug;
});

final enablePermanentCacheProvider = StateNotifierProvider<EnablePermanentCacheNotifier, bool>((ref) {
  return EnablePermanentCacheNotifier();
});

class EnablePermanentCacheNotifier extends StateNotifier<bool> {
  EnablePermanentCacheNotifier() : super(true) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    state = prefs.getBool('ytm_enable_permanent_cache') ?? true;
  }

  Future<void> setEnabled(bool enabled) async {
    state = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('ytm_enable_permanent_cache', enabled);
  }
}

final cacheLimitProvider = StateNotifierProvider<CacheLimitNotifier, String>((ref) {
  return CacheLimitNotifier();
});

class CacheLimitNotifier extends StateNotifier<String> {
  CacheLimitNotifier() : super('500MB') {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    state = prefs.getString('ytm_cache_limit') ?? '500MB';
  }

  Future<void> setLimit(String limit) async {
    state = limit;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('ytm_cache_limit', limit);
  }
}

final cacheSizeProvider = FutureProvider.autoDispose<int>((ref) async {
  try {
    final tempDir = await getTemporaryDirectory();
    final cacheParent = Directory('${tempDir.path}/da_tunes_cache');
    if (!cacheParent.existsSync()) return 0;

    var totalSize = 0;
    final files = cacheParent.listSync();
    for (final file in files) {
      if (file is File && (file.path.endsWith('.mp3') || file.path.endsWith('.jpg') || file.path.endsWith('.tmp'))) {
        totalSize += file.lengthSync();
      }
    }
    return totalSize;
  } catch (_) {
    return 0;
  }
});

String _formatSize(int bytes) {
  if (bytes <= 0) return '0 MB';
  final mb = bytes / (1024 * 1024);
  return '${mb.toStringAsFixed(1)} MB';
}

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.daColors;
    final typography = context.daTypography;

    final motionMode = ref.watch(motionScaleModeProvider);
    final diagnosticLogging = ref.watch(diagnosticLoggingProvider);
    final showAlbumArt = ref.watch(showAlbumArtBackgroundProvider);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: EdgeInsets.only(
          left: DATokens.spacingLarge,
          right: DATokens.spacingLarge,
          top: DATokens.spacingMedium,
          bottom: Theme.of(context).platform == TargetPlatform.android ? 160.0 : DATokens.spacingMedium,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: DATokens.spacingLarge),
              child: Text(
                'Settings',
                style: typography.title.copyWith(fontSize: 28.0),
              ),
            ),

            _buildSectionHeader(context, 'YouTube Music'),
            _buildYtmAccountSection(context, ref, colors, typography),
            const SizedBox(height: DATokens.spacingLarge),

            _buildSectionHeader(context, 'Motion & Accessibility'),
            DACard(
              child: Column(
                children: [
                  _buildSwitchTile(
                    context: context,
                    icon: Icons.motion_photos_off_outlined,
                    title: 'Reduce Motion',
                    subtitle: 'Simplify page transitions and card hovers',
                    value: motionMode == MotionScaleMode.reduced || motionMode == MotionScaleMode.disabled,
                    onChanged: (val) {
                      ref.read(motionScaleModeProvider.notifier).state =
                          val ? MotionScaleMode.reduced : MotionScaleMode.normal;
                    },
                  ),
                  const Divider(height: 1),
                  _buildDropdownTile<MotionScaleMode>(
                    context: context,
                    icon: Icons.speed_outlined,
                    title: 'Animation Scale',
                    subtitle: 'Adjust global system animation speed',
                    value: motionMode,
                    items: const [
                      DropdownMenuItem(
                        value: MotionScaleMode.normal,
                        child: Text('Normal (100%)'),
                      ),
                      DropdownMenuItem(
                        value: MotionScaleMode.reduced,
                        child: Text('Reduced (50%)'),
                      ),
                      DropdownMenuItem(
                        value: MotionScaleMode.disabled,
                        child: Text('Disabled (0%)'),
                      ),
                    ],
                    onChanged: (val) {
                      if (val != null) {
                        ref.read(motionScaleModeProvider.notifier).state = val;
                      }
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: DATokens.spacingLarge),

            _buildSectionHeader(context, 'Appearance'),
            DACard(
              child: Column(
                children: [
                  _buildDropdownTile<AppThemeMode>(
                    context: context,
                    icon: Icons.palette_outlined,
                    title: 'App Theme',
                    subtitle: 'Choose between DA Tunes Default dynamic colors, Pitch Black AMOLED, and Material 3',
                    value: ref.watch(appThemeModeProvider),
                    items: const [
                      DropdownMenuItem(
                        value: AppThemeMode.defaultDA,
                        child: Text('DA Tunes Default'),
                      ),
                      DropdownMenuItem(
                        value: AppThemeMode.amoled,
                        child: Text('AMOLED'),
                      ),
                      DropdownMenuItem(
                        value: AppThemeMode.material3,
                        child: Text('Material 3'),
                      ),
                    ],
                    onChanged: (val) {
                      if (val != null) {
                        ref.read(appThemeModeProvider.notifier).setThemeMode(val);
                      }
                    },
                  ),
                  if (ref.watch(appThemeModeProvider) == AppThemeMode.material3) ...[
                    const Divider(height: 1),
                    _buildDropdownTile<M3ThemeMode>(
                      context: context,
                      icon: Icons.brightness_6_outlined,
                      title: 'Material 3 Appearance',
                      subtitle: 'Select Light or Dark theme for Material 3 presentation',
                      value: ref.watch(m3ThemeModeProvider),
                      items: const [
                        DropdownMenuItem(
                          value: M3ThemeMode.dark,
                          child: Text('Dark'),
                        ),
                        DropdownMenuItem(
                          value: M3ThemeMode.light,
                          child: Text('Light'),
                        ),
                      ],
                      onChanged: (val) {
                        if (val != null) {
                          ref.read(m3ThemeModeProvider.notifier).setMode(val);
                        }
                      },
                    ),
                  ],
                  if (ref.watch(appThemeModeProvider) != AppThemeMode.material3) ...[
                    const Divider(height: 1),
                    _buildSwitchTile(
                      context: context,
                      icon: Icons.image_outlined,
                      title: 'Show Album Art as Background',
                      subtitle: 'Use blurred current playing album artwork as app background',
                      value: showAlbumArt,
                      onChanged: (val) {
                        ref.read(showAlbumArtBackgroundProvider.notifier).toggle(val);
                      },
                    ),
                  ],
                  if (ref.watch(appThemeModeProvider) == AppThemeMode.defaultDA) ...[
                    const Divider(height: 1),
                    _buildDropdownTile<PlayerStyle>(
                      context: context,
                      icon: Icons.play_circle_outline,
                      title: 'Player Style',
                      subtitle: 'Select the visual theme for full screen playback',
                      value: ref.watch(playerStyleNotifierProvider),
                      items: const [
                        DropdownMenuItem(
                          value: PlayerStyle.immersive,
                          child: Text('Immersive'),
                        ),
                        DropdownMenuItem(
                          value: PlayerStyle.vinyl,
                          child: Text('Vinyl'),
                        ),
                        DropdownMenuItem(
                          value: PlayerStyle.minimal,
                          child: Text('Minimal'),
                        ),
                      ],
                      onChanged: (val) {
                        if (val != null) {
                          ref.read(playerStyleNotifierProvider.notifier).setStyle(val);
                        }
                      },
                    ),
                  ],
                  const Divider(height: 1),
                  _buildSwitchTile(
                    context: context,
                    icon: Icons.auto_awesome_outlined,
                    title: 'Enable Extra Effects',
                    subtitle: 'May cause lag on some devices.',
                    value: ref.watch(enableExtraEffectsProvider),
                    onChanged: (val) {
                      ref.read(enableExtraEffectsProvider.notifier).toggle(val);
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: DATokens.spacingLarge),

            _buildSectionHeader(context, 'Playback'),
            DACard(
              child: Column(
                children: [
                  _buildSwitchTile(
                    context: context,
                    icon: Icons.graphic_eq_outlined,
                    title: 'Crossfade',
                    subtitle: 'Fade out current track while fading in the next track',
                    value: ref.watch(crossfadeEnabledProvider),
                    onChanged: (val) {
                      ref.read(crossfadeEnabledProvider.notifier).toggle(val);
                    },
                  ),
                  if (ref.watch(crossfadeEnabledProvider)) ...[
                    const Divider(height: 1),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: DATokens.spacingMedium,
                        vertical: DATokens.spacingSmall,
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.timer_outlined, color: colors.textSecondary),
                          const SizedBox(width: DATokens.spacingMedium),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Crossfade Duration',
                                  style: typography.body.copyWith(fontWeight: FontWeight.w600),
                                ),
                                Text(
                                  '${ref.watch(crossfadeDurationProvider)} seconds',
                                  style: typography.caption.copyWith(color: colors.textSecondary),
                                ),
                              ],
                            ),
                          ),
                          SizedBox(
                            width: 160,
                            child: Slider(
                              value: ref.watch(crossfadeDurationProvider).toDouble(),
                              min: 0,
                              max: 12,
                              divisions: 12,
                              activeColor: colors.primary,
                              inactiveColor: colors.border,
                              onChanged: (val) {
                                ref.read(crossfadeDurationProvider.notifier).setDuration(val.round());
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const Divider(height: 1),
                  _buildSwitchTile(
                    context: context,
                    icon: Icons.power_settings_new_outlined,
                    title: 'Prevent app from being killed',
                    subtitle: 'Keep playback running in the background when the app is cleared from recents',
                    value: ref.watch(preventAppKilledProvider),
                    onChanged: (val) {
                      ref.read(preventAppKilledProvider.notifier).toggle(val);
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: DATokens.spacingLarge),

             _buildSectionHeader(context, 'Cache & Local Storage'),
             DACard(
               child: Column(
                 children: [
                   _buildSwitchTile(
                     context: context,
                     icon: Icons.save_outlined,
                     title: 'Cache songs for offline playback',
                     subtitle: 'Cache songs for offline playback in the background (uses internal storage).',
                     value: ref.watch(enablePermanentCacheProvider),
                     onChanged: (val) async {
                       if (!val) {
                         final sizeAsync = ref.read(cacheSizeProvider);
                         final sizeInBytes = sizeAsync.valueOrNull ?? 0;
                         final usedStr = _formatSize(sizeInBytes);
                         final shouldClear = await showDialog<bool>(
                           context: context,
                           builder: (ctx) => AlertDialog(
                             backgroundColor: colors.surface,
                             title: Text('Disable Permanent Cache?', style: typography.title.copyWith(fontSize: 18.0)),
                             content: Text(
                               'Songs will no longer be saved to permanent storage after playback. Would you also like to clear existing cached songs ($usedStr) to free up space?',
                               style: typography.body.copyWith(fontSize: 14.0, color: colors.textSecondary),
                             ),
                             actions: [
                               TextButton(
                                 onPressed: () => Navigator.of(ctx).pop(false),
                                 child: Text('Keep Files', style: TextStyle(color: colors.textSecondary)),
                               ),
                               TextButton(
                                 onPressed: () => Navigator.of(ctx).pop(true),
                                 child: Text('Clear & Disable', style: TextStyle(color: colors.primary, fontWeight: FontWeight.bold)),
                               ),
                             ],
                           ),
                         );

                         if (shouldClear == true) {
                           ref.read(sourceManagerProvider).clearCache();
                           try {
                             final tempDir = await getTemporaryDirectory();
                             final cacheParent = Directory('${tempDir.path}/da_tunes_cache');
                             if (cacheParent.existsSync()) {
                               final files = cacheParent.listSync();
                               for (final file in files) {
                                 if (file is File) {
                                   try {
                                     file.deleteSync();
                                   } catch (_) {}
                                 }
                               }
                             }
                             ref.invalidate(cacheSizeProvider);
                           } catch (_) {}
                         }

                         await ref.read(enablePermanentCacheProvider.notifier).setEnabled(false);
                       } else {
                         await ref.read(enablePermanentCacheProvider.notifier).setEnabled(true);
                       }
                     },
                   ),
                   const Divider(height: 1),
                   _buildDropdownTile<String>(
                     context: context,
                     icon: Icons.storage_outlined,
                     title: 'Cache Size Limit',
                     subtitle: 'Set maximum space for offline caching',
                     value: ref.watch(cacheLimitProvider),
                     items: const [
                       DropdownMenuItem(value: '250MB', child: Text('250 MB')),
                       DropdownMenuItem(value: '500MB', child: Text('500 MB')),
                       DropdownMenuItem(value: '1GB', child: Text('1 GB')),
                       DropdownMenuItem(value: '2GB', child: Text('2 GB')),
                       DropdownMenuItem(value: '5GB', child: Text('5 GB')),
                       DropdownMenuItem(value: 'Unlimited', child: Text('Unlimited')),
                     ],
                     onChanged: (val) {
                       if (val != null) {
                         ref.read(cacheLimitProvider.notifier).setLimit(val);
                       }
                     },
                   ),
                   const Divider(height: 1),
                   Consumer(
                     builder: (context, ref, child) {
                       final sizeAsync = ref.watch(cacheSizeProvider);
                       final limit = ref.watch(cacheLimitProvider);
                       
                       return sizeAsync.when(
                         loading: () => const ListTile(
                           leading: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)),
                           title: Text('Calculating cache size...'),
                         ),
                         error: (_, __) => const ListTile(
                           leading: Icon(Icons.error_outline),
                           title: Text('Error calculating cache size'),
                         ),
                         data: (sizeInBytes) {
                           final usedStr = _formatSize(sizeInBytes);
                           final limitStr = limit == 'Unlimited' ? 'Unlimited' : limit;
                           
                           return ListTile(
                             leading: Icon(Icons.info_outline, color: colors.primary),
                             title: Text('Cache Used', style: typography.title.copyWith(fontSize: 15.0)),
                             subtitle: Text('$usedStr / $limitStr', style: typography.body.copyWith(fontSize: 12.0, color: colors.textSecondary)),
                           );
                         },
                       );
                     },
                   ),
                   const Divider(height: 1),
                   ListTile(
                     leading: Icon(Icons.cleaning_services_outlined, color: colors.primary),
                     title: Text(
                       'Clear Playback Cache',
                       style: typography.title.copyWith(fontSize: 15.0),
                     ),
                     subtitle: Text(
                       'Free up space by removing cached songs and artwork files',
                       style: typography.body.copyWith(fontSize: 12.0, color: colors.textSecondary),
                     ),
                     trailing: TextButton(
                       onPressed: () async {
                         ref.read(sourceManagerProvider).clearCache();
                         try {
                           final tempDir = await getTemporaryDirectory();
                           final cacheParent = Directory('${tempDir.path}/da_tunes_cache');
                           if (cacheParent.existsSync()) {
                             final files = cacheParent.listSync();
                             for (final file in files) {
                               if (file is File) {
                                 try {
                                   file.deleteSync();
                                 } catch (_) {}
                               }
                             }
                           }
                           ref.invalidate(cacheSizeProvider);
                         } catch (_) {}

                         if (context.mounted) {
                           ScaffoldMessenger.of(context).showSnackBar(
                             SnackBar(
                               content: const Text('Playback cache files successfully cleared.'),
                               backgroundColor: colors.primary,
                             ),
                           );
                         }
                       },
                       child: const Text('Clear'),
                     ),
                   ),
                 ],
               ),
             ),
            const SizedBox(height: DATokens.spacingLarge),

            _buildSectionHeader(context, 'Developer Options'),
            DACard(
              child: Column(
                children: [
                  _buildSwitchTile(
                    context: context,
                    icon: Icons.bug_report_outlined,
                    title: 'Diagnostic Logging',
                    subtitle: 'Dump active platform API and audio backend ticks',
                    value: diagnosticLogging,
                    onChanged: (val) {
                      ref.read(diagnosticLoggingProvider.notifier).state = val;
                      DALogger.activeLevel = val ? LogLevel.debug : LogLevel.error;
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: DATokens.spacingLarge),
            _buildSectionHeader(context, 'Music Taste & Privacy'),
            DACard(
              child: Column(
                children: [
                  ListTile(
                    leading: Icon(Icons.bubble_chart_outlined, color: colors.primary),
                    title: Text('Music DNA Insights', style: typography.title.copyWith(fontSize: 15.0)),
                    subtitle: Text('View personalized listening habits and trends', style: typography.body.copyWith(fontSize: 12.0, color: colors.textSecondary)),
                    trailing: const Icon(Icons.chevron_right, size: 20.0),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => const MusicDnaPage()),
                      );
                    },
                  ),
                  const Divider(height: 1, color: Colors.white10),
                  ListTile(
                    leading: Icon(Icons.security_outlined, color: colors.primary),
                    title: Text('Taste Engine & Privacy', style: typography.title.copyWith(fontSize: 15.0)),
                    subtitle: Text('Manage listening logs and recommendation profile', style: typography.body.copyWith(fontSize: 12.0, color: colors.textSecondary)),
                    trailing: const Icon(Icons.chevron_right, size: 20.0),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => const TasteSettingsPage()),
                      );
                    },
                  ),
                  if (ref.watch(sessionManagerProvider).isGuestMode) ...[
                    const Divider(height: 1, color: Colors.white10),
                    ListTile(
                      leading: Icon(Icons.edit_outlined, color: colors.primary),
                      title: Text('Edit Guest Username', style: typography.title.copyWith(fontSize: 15.0)),
                      subtitle: Text('Change your custom display name', style: typography.body.copyWith(fontSize: 12.0, color: colors.textSecondary)),
                      trailing: const Icon(Icons.chevron_right, size: 20.0),
                      onTap: () async {
                        final currentName = ref.read(sessionManagerProvider).guestUsername ?? 'Voyager';
                        final editController = TextEditingController(text: currentName);
                        final newName = await showDialog<String>(
                          context: context,
                          builder: (context) => AlertDialog(
                            backgroundColor: colors.surfaceCard,
                            title: Text('Edit Username', style: typography.title.copyWith(fontSize: 18.0)),
                            content: TextField(
                              controller: editController,
                              autofocus: true,
                              maxLength: 20,
                              decoration: InputDecoration(
                                hintText: 'Enter new name...',
                                border: UnderlineInputBorder(
                                  borderSide: BorderSide(color: colors.primary),
                                ),
                              ),
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context),
                                child: Text('Cancel', style: TextStyle(color: colors.primary)),
                              ),
                              TextButton(
                                onPressed: () => Navigator.pop(context, editController.text.trim()),
                                child: Text('Save', style: TextStyle(color: colors.primary, fontWeight: FontWeight.bold)),
                              ),
                            ],
                          ),
                        );
                        if (newName != null && newName.isNotEmpty) {
                          await ref.read(sessionManagerProvider).updateGuestUsername(newName);
                        }
                      },
                    ),
                    const Divider(height: 1, color: Colors.white10),
                    ListTile(
                      leading: Icon(Icons.restart_alt, color: colors.primary),
                      title: Text('Reset Guest Onboarding', style: typography.title.copyWith(fontSize: 15.0)),
                      subtitle: Text('Re-create your guest username and music preferences profile', style: typography.body.copyWith(fontSize: 12.0, color: colors.textSecondary)),
                      trailing: const Icon(Icons.chevron_right, size: 20.0),
                      onTap: () async {
                        final confirm = await showDialog<bool>(
                          context: context,
                          builder: (context) => AlertDialog(
                            backgroundColor: colors.surfaceCard,
                            title: Text('Reset Onboarding?', style: typography.title.copyWith(fontSize: 18.0)),
                            content: Text('This will reset your guest username and preference profile, and redirect you to onboarding. Proceed?', style: typography.body.copyWith(fontSize: 14.0, color: colors.textSecondary)),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context, false),
                                child: Text('Cancel', style: TextStyle(color: colors.primary)),
                              ),
                              TextButton(
                                onPressed: () => Navigator.pop(context, true),
                                child: const Text('Reset', style: TextStyle(color: Colors.redAccent)),
                              ),
                            ],
                          ),
                        );
                        if (confirm == true) {
                          await ref.read(sessionManagerProvider).resetGuestOnboarding();
                          await ref.read(tasteEngineNotifierProvider.notifier).reload();
                        }
                      },
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: DATokens.spacingLarge),
            _buildSectionHeader(context, 'About'),
            DACard(
              child: ListTile(
                leading: Icon(Icons.info_outline, color: colors.primary),
                title: Text('About DA Tunes', style: typography.title.copyWith(fontSize: 15.0)),
                subtitle: Text('Version details, features, credits, and open source', style: typography.body.copyWith(fontSize: 12.0, color: colors.textSecondary)),
                trailing: const Icon(Icons.chevron_right, size: 20.0),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const AboutPage()),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(BuildContext context, String title) {
    final colors = context.daColors;
    final typography = context.daTypography;
    return Padding(
      padding: const EdgeInsets.only(left: 4.0, bottom: DATokens.spacingSmall),
      child: Text(
        title.toUpperCase(),
        style: typography.body.copyWith(
          fontSize: 11.0,
          fontWeight: FontWeight.bold,
          color: colors.textSecondary.withValues(alpha: 0.8),
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  Widget _buildSwitchTile({
    required BuildContext context,
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    final colors = context.daColors;
    final typography = context.daTypography;
    final isCompact = MediaQuery.of(context).size.width < 420;
    return ListTile(
      dense: isCompact,
      contentPadding: EdgeInsets.symmetric(horizontal: isCompact ? 12.0 : 16.0, vertical: 2.0),
      leading: Icon(icon, color: colors.primary, size: isCompact ? 20.0 : 24.0),
      title: Text(
        title,
        style: typography.title.copyWith(fontSize: isCompact ? 14.0 : 15.0),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        subtitle,
        style: typography.body.copyWith(fontSize: isCompact ? 11.0 : 12.0, color: colors.textSecondary),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Switch.adaptive(
        value: value,
        activeThumbColor: colors.primary,
        onChanged: onChanged,
      ),
    );
  }

  Widget _buildDropdownTile<T>({
    required BuildContext context,
    required IconData icon,
    required String title,
    required String subtitle,
    required T value,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?> onChanged,
  }) {
    final colors = context.daColors;
    final typography = context.daTypography;
    final isCompact = MediaQuery.of(context).size.width < 420;
    return ListTile(
      dense: isCompact,
      contentPadding: EdgeInsets.symmetric(horizontal: isCompact ? 12.0 : 16.0, vertical: 2.0),
      leading: Icon(icon, color: colors.primary, size: isCompact ? 20.0 : 24.0),
      title: Text(
        title,
        style: typography.title.copyWith(fontSize: isCompact ? 14.0 : 15.0),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        subtitle,
        style: typography.body.copyWith(fontSize: isCompact ? 11.0 : 12.0, color: colors.textSecondary),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: isCompact ? 120.0 : 160.0),
        child: DropdownButton<T>(
          value: value,
          items: items,
          onChanged: onChanged,
          isExpanded: true,
          underline: const SizedBox.shrink(),
          dropdownColor: colors.surfaceCard,
          style: typography.body.copyWith(fontSize: isCompact ? 12.0 : 14.0, color: colors.textPrimary),
        ),
      ),
    );
  }

  Widget _buildYtmAccountSection(
    BuildContext context,
    WidgetRef ref,
    dynamic colors,
    dynamic typography,
  ) {
    final session = ref.watch(sessionManagerProvider);
    final syncManager = ref.watch(ytmSyncManagerProvider);

    if (!session.isLoggedIn) {
      return DACard(
        child: Padding(
          padding: const EdgeInsets.all(DATokens.spacingMedium),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'YouTube Music Account',
                style: typography.title.copyWith(fontSize: 15.0, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4.0),
              Text(
                'Status: Not Logged In',
                style: typography.body.copyWith(fontSize: 13.0, color: Colors.redAccent),
              ),
              const SizedBox(height: 8.0),
              Text(
                'Login to your YouTube Music account to synchronize your personalized home feed, history, recommendations, and playlists.',
                style: typography.body.copyWith(fontSize: 12.0, color: colors.textSecondary),
              ),
              const SizedBox(height: DATokens.spacingMedium),
              SizedBox(
                width: double.infinity,
                height: 44,
                child: ElevatedButton.icon(
                  onPressed: () => _handleLogin(context, ref),
                  icon: const Icon(Icons.login),
                  label: const Text('Sign in to YouTube Music'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.black,
                    disabledBackgroundColor: Colors.black,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(DATokens.radiusMedium),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final displayName = session.accountName ?? session.accountEmail ?? "YouTube Music Member";
    final lastSyncText = syncManager.lastSuccessfulSync != null
        ? 'Last Synced: ${_formatDateTime(syncManager.lastSuccessfulSync!)}'
        : 'Never Synced';

    return DACard(
      child: Padding(
        padding: const EdgeInsets.all(DATokens.spacingMedium),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'YouTube Music Account',
              style: typography.title.copyWith(fontSize: 15.0, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4.0),
            Text(
              'Status: Logged In as $displayName',
              style: typography.body.copyWith(fontSize: 13.0, color: Colors.greenAccent),
            ),
            if (session.accountEmail != null && session.accountEmail != session.accountName) ...[
              const SizedBox(height: 2.0),
              Text(
                session.accountEmail!,
                style: typography.caption.copyWith(color: colors.textSecondary),
              ),
            ],
            const SizedBox(height: 6.0),
            Text(
              lastSyncText,
              style: typography.caption.copyWith(color: colors.textSecondary),
            ),
            if (syncManager.status == YtmSyncStatus.syncing) ...[
              const SizedBox(height: 8.0),
              Row(
                children: [
                  const SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white70),
                  ),
                  const SizedBox(width: 8.0),
                  Text(
                    'Syncing details...',
                    style: typography.caption.copyWith(color: colors.textSecondary),
                  ),
                ],
              ),
            ],
            const SizedBox(height: DATokens.spacingMedium),
            Row(
              children: [
                Expanded(
                  child: Tooltip(
                    message: syncManager.status == YtmSyncStatus.syncing ? 'Syncing...' : 'Sync Now',
                    child: SizedBox(
                      height: 44,
                      child: ElevatedButton(
                        onPressed: syncManager.status == YtmSyncStatus.syncing
                            ? null
                            : () => ref.read(ytmSyncManagerProvider.notifier).startSync(force: true),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.black,
                          disabledBackgroundColor: Colors.black,
                          foregroundColor: Colors.white,
                          padding: EdgeInsets.zero,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(DATokens.radiusSmall),
                          ),
                        ),
                        child: syncManager.status == YtmSyncStatus.syncing
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : const Icon(Icons.sync, size: 20, color: Colors.white),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: DATokens.spacingSmall),
                Expanded(
                  child: Tooltip(
                    message: 'Manage Account Profile',
                    child: SizedBox(
                      height: 44,
                      child: OutlinedButton(
                        onPressed: () {
                          showDialog(
                            context: context,
                            builder: (context) => AlertDialog(
                              title: const Text('YouTube Music Profile'),
                              content: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Name: $displayName', style: typography.title.copyWith(fontSize: 14.0)),
                                  const SizedBox(height: 4.0),
                                  Text('Email: ${session.accountEmail ?? "Unknown"}', style: typography.title.copyWith(fontSize: 14.0)),
                                  const SizedBox(height: 4.0),
                                  Text('Authorized Client: Active', style: typography.caption.copyWith(color: colors.textSecondary)),
                                ],
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(context),
                                  child: const Text('Close'),
                                ),
                              ],
                            ),
                          );
                        },
                        style: OutlinedButton.styleFrom(
                          backgroundColor: Colors.black,
                          foregroundColor: Colors.white,
                          side: BorderSide(color: colors.border),
                          padding: EdgeInsets.zero,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(DATokens.radiusSmall),
                          ),
                        ),
                        child: const Icon(Icons.account_circle_outlined, size: 20, color: Colors.white),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: DATokens.spacingSmall),
                Expanded(
                  child: Tooltip(
                    message: 'Sign Out',
                    child: SizedBox(
                      height: 44,
                      child: ElevatedButton(
                        onPressed: () => ref.read(sessionManagerProvider.notifier).logout(),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.redAccent.withValues(alpha: 0.8),
                          foregroundColor: Colors.white,
                          padding: EdgeInsets.zero,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(DATokens.radiusSmall),
                          ),
                        ),
                        child: const Icon(Icons.logout, size: 20),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _handleLogin(BuildContext context, WidgetRef ref) async {
    if (Platform.isAndroid || Platform.isIOS) {
      final success = await Navigator.push<bool>(
        context,
        MaterialPageRoute(builder: (context) => const AuthWebViewPage()),
      );
      if (success == true) {
        ref.read(ytmSyncManagerProvider.notifier).startSync();
      }
    } else if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Connect to YouTube Music'),
          content: const Text(
            'Choose how you want to sign in to YouTube Music:\n\n'
            '1. Automatic Sign-In (Recommended): Embedded sign-in page.\n'
            '2. Copy-Paste Cookies: Copy your browser cookie header manually.'
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                showDialog(
                  context: context,
                  builder: (context) => const CookieLoginDialog(),
                );
              },
              child: const Text('Copy-Paste Cookies'),
            ),
            TextButton(
              onPressed: () async {
                Navigator.pop(context);
                final success = await Navigator.push<bool>(
                  context,
                  MaterialPageRoute(builder: (context) => const AuthWebViewPage()),
                );
                if (success == true) {
                  ref.read(ytmSyncManagerProvider.notifier).startSync();
                }
              },
              child: const Text('Automatic Sign-In'),
            ),
          ],
        ),
      );
    }
  }

  String _formatDateTime(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}

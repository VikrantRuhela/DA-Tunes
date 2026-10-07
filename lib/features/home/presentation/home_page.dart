import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../../app/theme/tokens.dart';
import '../../../shared/animations/motion_system.dart';
import '../../../shared/providers/backend_providers.dart';
import '../../../shared/providers/library_providers.dart';
import '../../../shared/models/music_models.dart' as shared;
import '../../../domain/entities/home_feed.dart';
import '../../../domain/entities/song.dart';
import '../../../domain/entities/album.dart';
import '../../../domain/entities/playlist.dart';
import 'widgets/greeting_widget.dart';
import 'widgets/search_widget.dart';
import 'widgets/recently_played_widget.dart';
import 'widgets/favorites_grid.dart';
import 'widgets/recommended_section.dart';
import 'widgets/favorite_artists_section.dart';
import '../../taste_engine/presentation/providers/taste_engine_providers.dart';
import '../../../domain/entities/value_objects.dart';
import 'widgets/section_header.dart';
import 'widgets/song_tile.dart';
import 'widgets/album_card.dart';
import '../../../shared/providers/player_providers.dart';
import '../../../shared/utils/home_feed_cache_serializer.dart';
import 'package:go_router/go_router.dart';
import '../../../core/services/logger_service.dart';
import '../../../core/extensions/context_extensions.dart';
import '../../../core/services/music_content_classifier.dart';

final homeFeedProvider = FutureProvider<HomeFeed>((ref) async {
  final storage = ref.watch(storageServiceProvider);
  final sourceManager = ref.watch(sourceManagerProvider);
  final accountService = ref.watch(ytAccountServiceProvider);

  try {
    final genericFeed = await sourceManager.getHome();
    HomeFeed finalFeed = genericFeed;

    if (accountService.isLoggedIn) {
      try {
        final ytmSections = await accountService.fetchPersonalizedHomeSections();
        final List<HomeFeedSection> newSections = [];

        final ytmSongs = ytmSections['songs'] ?? [];
        if (ytmSongs.isNotEmpty) {
          final domainSongs = ytmSongs.map((s) => Song(
            id: s.id,
            title: s.title,
            artistId: s.artist,
            albumId: s.album,
            duration: DurationValue(s.duration),
            thumbnail: Artwork(s.artworkUrl ?? ''),
            artwork: Artwork(s.artworkUrl ?? ''),
            sourceId: s.source,
          )).toList();
          newSections.add(HomeFeedSection(
            title: 'Recommended for You',
            type: 'recommended',
            items: domainSongs,
          ));
        } else {
          newSections.add(genericFeed.sections.firstWhere((s) => s.type == 'recommended'));
        }

        final ytmAlbums = ytmSections['albums'] ?? [];
        if (ytmAlbums.isNotEmpty) {
          final domainAlbums = ytmAlbums.map((a) => Album(
            id: a.id,
            title: a.name,
            artistId: a.artist,
            cover: Artwork(a.artworkUrl ?? ''),
            year: 2026,
            trackCount: 10,
            duration: DurationValue(const Duration(minutes: 40)),
          )).toList();
          newSections.add(HomeFeedSection(
            title: 'Recommended Albums',
            type: 'albums',
            items: domainAlbums,
          ));
        } else {
          newSections.add(genericFeed.sections.firstWhere((s) => s.type == 'albums'));
        }

        final ytmPlaylists = ytmSections['playlists'] ?? [];
        if (ytmPlaylists.isNotEmpty) {
          final domainPlaylists = ytmPlaylists.map((p) => Playlist(
            id: p.id,
            title: p.name,
            description: 'YouTube Music Mix',
            cover: Artwork(p.artworkUrl ?? ''),
            owner: 'YouTube Music',
            songIds: const [],
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
          )).toList();
          newSections.add(HomeFeedSection(
            title: 'Daily Mixes & Playlists',
            type: 'playlists',
            items: domainPlaylists,
          ));
        } else {
          newSections.add(genericFeed.sections.firstWhere((s) => s.type == 'playlists'));
        }

        finalFeed = HomeFeed(sections: newSections);
      } catch (_) {}
    }

    final filteredSections = finalFeed.sections.map((section) {
      final filteredItems = section.items.where((item) {
        if (item is Song) {
          return !MusicContentClassifier.isBlacklistedTitleOrChannel(item.title, item.artistId);
        } else if (item is Album) {
          return !MusicContentClassifier.isBlacklistedTitleOrChannel(item.title, item.artistId);
        } else if (item is Playlist) {
          return !MusicContentClassifier.isBlacklistedTitleOrChannel(item.title, item.owner);
        }
        return true;
      }).toList();

      return HomeFeedSection(
        title: section.title,
        type: section.type,
        items: filteredItems,
      );
    }).toList();

    finalFeed = HomeFeed(sections: filteredSections);

    final jsonStr = HomeFeedCacheSerializer.serialize(finalFeed);
    await storage.setString('ytm_cache_home_feed', jsonStr);

    return finalFeed;
  } catch (e) {
    final cached = await storage.getString('ytm_cache_home_feed');
    if (cached != null && cached.isNotEmpty) {
      final feed = HomeFeedCacheSerializer.deserialize(cached);
      final filteredSections = feed.sections.map((section) {
        final filteredItems = section.items.where((item) {
          if (item is Song) {
            return !MusicContentClassifier.isBlacklistedTitleOrChannel(item.title, item.artistId);
          } else if (item is Album) {
            return !MusicContentClassifier.isBlacklistedTitleOrChannel(item.title, item.artistId);
          } else if (item is Playlist) {
            return !MusicContentClassifier.isBlacklistedTitleOrChannel(item.title, item.owner);
          }
          return true;
        }).toList();

        return HomeFeedSection(
          title: section.title,
          type: section.type,
          items: filteredItems,
        );
      }).toList();
      return HomeFeed(sections: filteredSections);
    }
    return HomeFeed(sections: [
      HomeFeedSection(title: 'Recommended for You', type: 'recommended', items: const []),
      HomeFeedSection(title: 'Trending Albums', type: 'albums', items: const []),
      HomeFeedSection(title: 'Featured Playlists', type: 'playlists', items: const []),
    ]);
  }
});

class HorizontalCarouselSection extends StatelessWidget {
  final String title;
  final String subtitle;
  final List<Widget> children;

  const HorizontalCarouselSection({
    super.key,
    required this.title,
    required this.subtitle,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) return const SizedBox.shrink();

    final colors = context.daColors;
    final typography = context.daTypography;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(title: title),
        Padding(
          padding: const EdgeInsets.only(left: 4.0, bottom: DATokens.spacingMedium),
          child: Text(
            subtitle,
            style: typography.caption.copyWith(color: colors.textSecondary),
          ),
        ),
        LayoutBuilder(
          builder: (context, constraints) {
            final double totalWidth = constraints.maxWidth;
            
            int visibleCards = 3;
            if (totalWidth >= 900) {
              visibleCards = 6;
            } else if (totalWidth >= 600) {
              visibleCards = 4;
            }

            const double gap = 12.0;
            final double calculatedWidth = (totalWidth - (visibleCards - 1) * gap) / visibleCards;
            if (calculatedWidth <= 0) {
              return const SizedBox.shrink();
            }
            final double cardWidth = calculatedWidth;

            return SizedBox(
              height: cardWidth + 76.0,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                padding: EdgeInsets.zero,
                itemCount: children.length,
                itemBuilder: (context, index) {
                  return Padding(
                    padding: EdgeInsets.only(
                      right: index == children.length - 1 ? 0.0 : gap,
                    ),
                    child: SizedBox(
                      width: cardWidth,
                      child: children[index],
                    ),
                  );
                },
              ),
            );
          },
        ),
      ],
    );
  }
}

class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  @override
  void initState() {
    super.initState();
    DALogger.info('[GUEST HOME] Home screen initialized.');
  }

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      print('[HOME] Render completed');
    });
    final scaleMode = ref.watch(motionScaleModeProvider);
    final sectionsAsync = ref.watch(personalizedSectionsProvider);
    final topArtists = ref.watch(tasteEngineNotifierProvider.select((s) => s.dna.topArtists));

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: AnimatedSwitcher(
        duration: ref.scaledDuration(DAMotion.standard),
        switchInCurve: ref.scaledCurve(DAMotion.enterCurve),
        switchOutCurve: ref.scaledCurve(DAMotion.exitCurve),
        child: sectionsAsync.when(
          loading: () => const _HomeSkeletonLoader(key: ValueKey('loading')),
          error: (err, stack) => Center(
            key: const ValueKey('error'),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline_outlined, color: Colors.redAccent, size: DATokens.iconXLarge),
                const SizedBox(height: DATokens.spacingMedium),
                const Text(
                  'Failed to load recommendations',
                  style: TextStyle(color: Colors.white, fontSize: 18.0, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: DATokens.spacingTiny),
                Text(
                  err.toString(),
                  style: const TextStyle(color: Colors.white70, fontSize: 14.0),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
          data: (sections) {
            DALogger.info('[GUEST HOME] Home feed created successfully. Section count: ${sections.length}');
            final List<Widget> children = [
              const Padding(
                padding: EdgeInsets.only(bottom: DATokens.spacingMedium),
                child: GreetingWidget(),
              ),
            ];

            for (final section in sections) {
              if (section.items.isEmpty) continue;

              final List<Widget> cards = [];

              if (section.items.first is Song) {
                final songs = section.items.cast<Song>().toList();
                for (int i = 0; i < songs.length; i++) {
                  final song = songs[i];
                  final index = i;
                  cards.add(
                    AlbumCard(
                      title: song.title,
                      subtitle: song.artistId,
                      artworkUrl: song.thumbnail.url,
                      onTap: () {
                        final modelSongs = songs.map((s) => shared.Song(
                          id: s.id,
                          title: s.title,
                          artist: s.artistId,
                          album: s.albumId,
                          duration: s.duration.value,
                          artworkUrl: s.artwork.url,
                          source: s.sourceId,
                          lyrics: null,
                        )).toList();
                        ref.read(playbackControllerProvider).setQueue(modelSongs, startIndex: index, autoPlay: true);
                      },
                    ),
                  );
                }
              } else if (section.items.first is Album) {
                final albums = section.items.cast<Album>().toList();
                for (final album in albums) {
                  cards.add(
                    AlbumCard(
                      title: album.title,
                      subtitle: album.artistId,
                      artworkUrl: album.cover.url,
                      onTap: () {
                        context.push('/album/${album.id}');
                      },
                    ),
                  );
                }
              } else if (section.items.first is Playlist) {
                final playlists = section.items.cast<Playlist>().toList();
                for (final playlist in playlists) {
                  cards.add(
                    AlbumCard(
                      title: playlist.title,
                      subtitle: 'Playlist • By ${playlist.owner}',
                      artworkUrl: playlist.cover.url,
                      onTap: () {
                        context.push('/album/${playlist.id}');
                      },
                    ),
                  );
                }
              }

              if (cards.isNotEmpty) {
                children.add(
                  Padding(
                    padding: const EdgeInsets.only(bottom: DATokens.spacingLarge),
                    child: HorizontalCarouselSection(
                      title: section.title,
                      subtitle: section.subtitle,
                      children: cards,
                    ),
                  ),
                );
              }
            }

            if (topArtists.isNotEmpty) {
              children.add(
                Padding(
                  padding: const EdgeInsets.only(bottom: DATokens.spacingLarge),
                  child: FavoriteArtistsSection(artists: topArtists),
                ),
              );
            }

            final double bottomPadding = Theme.of(context).platform == TargetPlatform.android ? 160.0 : DATokens.spacingMedium;

            Widget listWidget;
            if (scaleMode == MotionScaleMode.disabled) {
              listWidget = ListView.builder(
                key: const ValueKey('list'),
                cacheExtent: 800.0,
                addRepaintBoundaries: true,
                physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
                padding: EdgeInsets.only(
                  left: DATokens.spacingLarge,
                  right: DATokens.spacingLarge,
                  top: DATokens.spacingMedium,
                  bottom: bottomPadding,
                ),
                itemCount: children.length,
                itemBuilder: (context, index) => children[index],
              );
            } else {
              final duration = scaleMode == MotionScaleMode.reduced ? 120.ms : 250.ms;

              listWidget = ListView.builder(
                key: const ValueKey('list_animated'),
                cacheExtent: 800.0,
                addRepaintBoundaries: true,
                physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
                padding: EdgeInsets.only(
                  left: DATokens.spacingLarge,
                  right: DATokens.spacingLarge,
                  top: DATokens.spacingMedium,
                  bottom: bottomPadding,
                ),
                itemCount: children.length,
                itemBuilder: (context, index) {
                  return children[index]
                      .animate()
                      .fadeIn(duration: duration, curve: Curves.easeOut)
                      .slideY(begin: 0.03, end: 0, duration: duration, curve: Curves.easeOut);
                },
              );
            }

            return RefreshIndicator(
              onRefresh: () async {
                try {
                  final storage = ref.read(storageServiceProvider);
                  await storage.remove('ytm_cache_personalized_sections');
                  await storage.remove('ytm_cache_home_feed');
                } catch (_) {}
                
                ref.invalidate(personalizedRecommendationsProvider);
                ref.invalidate(personalizedAlbumsProvider);
                ref.invalidate(personalizedPlaylistsProvider);
                ref.invalidate(personalizedSectionsProvider);
                try {
                  await ref.read(personalizedSectionsProvider.future);
                } catch (_) {}
              },
              child: listWidget,
            );
          },
        ),
      ),
    );
  }
}

class _HomeSkeletonLoader extends ConsumerWidget {
  const _HomeSkeletonLoader({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.daColors;
    final scaleMode = ref.watch(motionScaleModeProvider);
    final isReduced = scaleMode == MotionScaleMode.reduced || scaleMode == MotionScaleMode.disabled;
    final duration = isReduced ? 800.ms : 1200.ms;

    Widget buildPulsingBlock({
      required double width,
      required double height,
      double borderRadius = 8.0,
    }) {
      return Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: colors.surfaceCard,
          borderRadius: BorderRadius.circular(borderRadius),
        ),
      )
          .animate(onPlay: (controller) => controller.repeat(reverse: true))
          .tint(color: colors.primary.withValues(alpha: 0.08), duration: duration);
    }

    return SingleChildScrollView(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(
        horizontal: DATokens.spacingLarge,
        vertical: DATokens.spacingMedium,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          buildPulsingBlock(width: 180.0, height: 32.0, borderRadius: 8.0),
          const SizedBox(height: DATokens.spacingMedium),
          buildPulsingBlock(width: double.infinity, height: 48.0, borderRadius: 24.0),
          const SizedBox(height: DATokens.spacingLarge),
          buildPulsingBlock(width: 150.0, height: 20.0, borderRadius: 4.0),
          const SizedBox(height: DATokens.spacingMedium),
          SizedBox(
            height: 230.0,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: 4,
              physics: const NeverScrollableScrollPhysics(),
              itemBuilder: (context, index) {
                return Padding(
                  padding: const EdgeInsets.only(right: DATokens.spacingMedium),
                  child: Container(
                    width: 160.0,
                    decoration: BoxDecoration(
                      color: colors.surfaceCard,
                      borderRadius: BorderRadius.circular(DATokens.radiusLarge),
                      border: Border.all(color: colors.border),
                    ),
                    padding: const EdgeInsets.all(DATokens.spacingSmall + 2),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        AspectRatio(
                          aspectRatio: 1.0,
                          child: buildPulsingBlock(
                            width: double.infinity,
                            height: double.infinity,
                            borderRadius: DATokens.radiusMedium,
                          ),
                        ),
                        const SizedBox(height: DATokens.spacingSmall + 2),
                        buildPulsingBlock(width: 100.0, height: 14.0),
                        const SizedBox(height: 6.0),
                        buildPulsingBlock(width: 60.0, height: 10.0),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: DATokens.spacingLarge),
          buildPulsingBlock(width: 180.0, height: 20.0, borderRadius: 4.0),
          const SizedBox(height: DATokens.spacingMedium),
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: 3,
            itemBuilder: (context, index) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 12.0),
                child: Row(
                  children: [
                    buildPulsingBlock(width: 48.0, height: 48.0, borderRadius: DATokens.radiusSmall),
                    const SizedBox(width: DATokens.spacingMedium),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          buildPulsingBlock(width: 140.0, height: 14.0),
                          const SizedBox(height: 6.0),
                          buildPulsingBlock(width: 80.0, height: 10.0),
                        ],
                      ),
                    ),
                    buildPulsingBlock(width: 40.0, height: 14.0),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}



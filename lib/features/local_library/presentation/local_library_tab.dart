import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/extensions/context_extensions.dart';
import '../../../app/theme/tokens.dart';
import '../../../shared/widgets/da_card.dart';
import '../data/local_library_repository.dart';
import 'local_category_page.dart';
import 'library_management_page.dart';
import '../../../shared/animations/motion_system.dart';

class LocalLibraryTab extends ConsumerWidget {
  const LocalLibraryTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.daColors;
    final typography = context.daTypography;

    final state = ref.watch(localLibraryRepositoryProvider);
    final songsCount = state.songs.length;
    final isScanning = state.isScanning;

    final categories = [
      _CategoryItem(
        title: 'Songs',
        subtitle: '$songsCount tracks',
        icon: Icons.music_note_outlined,
        category: LocalCategory.songs,
      ),
      _CategoryItem(
        title: 'Albums',
        subtitle: '${ref.read(localLibraryRepositoryProvider.notifier).getAlbums().length} albums',
        icon: Icons.album_outlined,
        category: LocalCategory.albums,
      ),
      _CategoryItem(
        title: 'Artists',
        subtitle: '${ref.read(localLibraryRepositoryProvider.notifier).getArtists().length} artists',
        icon: Icons.people_outline,
        category: LocalCategory.artists,
      ),
      _CategoryItem(
        title: 'Hi-Res Audio',
        subtitle: '${ref.read(localLibraryRepositoryProvider.notifier).getHiResSongs().length} tracks',
        icon: Icons.high_quality_outlined,
        category: LocalCategory.hiRes,
      ),
      _CategoryItem(
        title: 'Recently Added',
        subtitle: 'New files',
        icon: Icons.schedule_outlined,
        category: LocalCategory.recentlyAdded,
      ),
      _CategoryItem(
        title: 'Folders',
        subtitle: '${state.folders.length} paths',
        icon: Icons.folder_open_outlined,
        category: LocalCategory.folders,
      ),
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: DATokens.spacingMedium),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Manage & Refresh bar
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                isScanning ? 'Refreshing local files...' : '$songsCount songs available',
                style: typography.body.copyWith(color: colors.textSecondary, fontSize: 13),
              ),
              Row(
                children: [
                  if (isScanning)
                    Padding(
                      padding: const EdgeInsets.only(right: 8.0),
                      child: SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: colors.primary,
                        ),
                      ),
                    ),
                  IconButton(
                    icon: Icon(Icons.settings_outlined, color: colors.textPrimary),
                    tooltip: 'Manage Folders',
                    onPressed: () {
                      Navigator.push(
                        context,
                        DAMotion.createPageRoute(builder: (context) => const LibraryManagementPage()),
                      );
                    },
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: DATokens.spacingSmall),

          // Categories Grid
          Expanded(
            child: GridView.builder(
              physics: const BouncingScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: DATokens.spacingMedium,
                mainAxisSpacing: DATokens.spacingMedium,
                childAspectRatio: 1.35,
              ),
              itemCount: categories.length,
              itemBuilder: (context, idx) {
                final cat = categories[idx];
                return InkWell(
                  onTap: () {
                    Navigator.push(
                      context,
                      DAMotion.createPageRoute(
                        builder: (context) => LocalCategoryPage(category: cat.category),
                      ),
                    );
                  },
                  borderRadius: BorderRadius.circular(DATokens.radiusLarge),
                  child: DACard(
                    child: Padding(
                      padding: const EdgeInsets.all(DATokens.spacingMedium),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(cat.icon, color: colors.primary, size: 24),
                          const SizedBox(height: DATokens.spacingSmall),
                          Text(
                            cat.title,
                            style: typography.title.copyWith(fontSize: 14),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            cat.subtitle,
                            style: typography.body.copyWith(
                              color: colors.textSecondary,
                              fontSize: 11,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _CategoryItem {
  final String title;
  final String subtitle;
  final IconData icon;
  final LocalCategory category;

  _CategoryItem({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.category,
  });
}

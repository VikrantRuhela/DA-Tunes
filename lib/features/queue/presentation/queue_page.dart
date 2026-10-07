import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/extensions/context_extensions.dart';
import '../../../app/theme/tokens.dart';
import '../../../shared/providers/player_providers.dart';
import '../../../shared/widgets/da_empty_state.dart';
import '../../../shared/utils/song_options.dart';
import '../../../shared/models/music_models.dart';
import '../../../shared/widgets/da_image.dart';

class QueuePage extends ConsumerStatefulWidget {
  const QueuePage({super.key});

  @override
  ConsumerState<QueuePage> createState() => _QueuePageState();
}

class _QueuePageState extends ConsumerState<QueuePage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ref.read(activePlayerPanelProvider.notifier).state = PlayerPanelType.queue;
      }
    });
  }

  @override
  void dispose() {
    if (ref.read(activePlayerPanelProvider) == PlayerPanelType.queue) {
      ref.read(activePlayerPanelProvider.notifier).state = PlayerPanelType.none;
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.daColors;
    final typography = context.daTypography;

    final controller = ref.watch(playbackControllerProvider);
    final queue = controller.currentQueue;
    final currentIndex = controller.currentIndex;

    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) {
          if (ref.read(activePlayerPanelProvider) == PlayerPanelType.queue) {
            ref.read(activePlayerPanelProvider.notifier).state = PlayerPanelType.none;
            if (ref.read(restoreImmersiveOnCloseProvider)) {
              ref.read(immersiveModeProvider.notifier).state = true;
              ref.read(restoreImmersiveOnCloseProvider.notifier).state = false;
            }
          }
        }
      },
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          title: Text(
            'Play Queue',
            style: typography.title.copyWith(fontSize: 22.0, fontWeight: FontWeight.bold),
          ),
        ),
        body: queue.isEmpty
            ? const Center(
                child: DAEmptyState(
                  icon: Icons.queue_music_outlined,
                  title: 'Play Queue is Empty',
                  description: 'Start playing songs to build a queue.',
                ),
              )
            : ReorderableListView.builder(
                physics: const BouncingScrollPhysics(),
                buildDefaultDragHandles: false,
                padding: const EdgeInsets.only(
                  left: DATokens.spacingMedium,
                  right: DATokens.spacingMedium,
                  top: DATokens.spacingSmall,
                  bottom: 120.0,
                ),
                itemCount: queue.length,
                proxyDecorator: (Widget child, int index, Animation<double> animation) {
                  HapticFeedback.mediumImpact();
                  return AnimatedBuilder(
                    animation: animation,
                    builder: (context, child) {
                      final animValue = Curves.easeInOut.transform(animation.value);
                      final elevation = 0.0 + (8.0 - 0.0) * animValue;
                      final scale = 1.0 + (1.02 - 1.0) * animValue;
                      return Transform.scale(
                        scale: scale,
                        child: Material(
                          elevation: elevation,
                          color: Colors.transparent,
                          shadowColor: Colors.black.withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(DATokens.radiusMedium),
                          child: child,
                        ),
                      );
                    },
                    child: child,
                  );
                },
                onReorder: (oldIdx, newIdx) {
                  HapticFeedback.mediumImpact();
                  final controller = ref.read(playbackControllerProvider);
                  final queue = controller.currentQueue;
                  final currIdx = controller.currentIndex;
                  final updatedSongs = List<Song>.from(queue);
                  final s = updatedSongs.removeAt(oldIdx);
                  if (newIdx > oldIdx) newIdx--;
                  updatedSongs.insert(newIdx, s);
                  final newCurrentIndex = (currIdx == oldIdx)
                      ? newIdx
                      : ((currIdx > oldIdx && currIdx <= newIdx)
                          ? currIdx - 1
                          : ((currIdx < oldIdx && currIdx >= newIdx) ? currIdx + 1 : currIdx));
                  controller.reorderQueue(updatedSongs, newCurrentIndex);
                },
                itemBuilder: (context, index) {
                  final song = queue[index];
                  final isActive = index == currentIndex;

                  return Container(
                    key: ValueKey('queue_item_${song.id}_$index'),
                    margin: const EdgeInsets.symmetric(vertical: 4.0),
                    decoration: BoxDecoration(
                      color: isActive
                          ? colors.primary.withValues(alpha: 0.15)
                          : colors.surfaceCard.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(DATokens.radiusMedium),
                      border: isActive
                          ? Border.all(color: colors.primary, width: 1.0)
                          : Border.all(color: colors.border.withValues(alpha: 0.1), width: 1.0),
                    ),
                    child: ListTile(
                      onTap: () {
                        ref.read(playbackControllerProvider).skipToQueueIndex(index);
                      },
                      leading: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ReorderableDelayedDragStartListener(
                            index: index,
                            child: Padding(
                              padding: const EdgeInsets.only(right: DATokens.spacingSmall),
                              child: Icon(
                                Icons.drag_handle,
                                color: colors.textSecondary.withValues(alpha: 0.6),
                                size: 22.0,
                              ),
                            ),
                          ),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(4.0),
                            child: DAImage(
                              url: song.artworkUrl,
                              width: 48,
                              height: 48,
                              fit: BoxFit.cover,
                            ),
                          ),
                        ],
                      ),
                      title: Text(
                        song.title,
                        style: typography.body.copyWith(
                          fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                          color: isActive ? colors.primary : colors.textPrimary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        song.artist,
                        style: typography.caption.copyWith(color: colors.textSecondary),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (isActive) ...[
                            Icon(Icons.volume_up, color: colors.primary),
                            const SizedBox(width: DATokens.spacingSmall),
                          ],
                          IconButton(
                            icon: Icon(Icons.more_vert, color: colors.textSecondary),
                            onPressed: () {
                              showSongOptionsMenu(context, ref, song, queueIndex: index);
                            },
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
      ),
    );
  }
}

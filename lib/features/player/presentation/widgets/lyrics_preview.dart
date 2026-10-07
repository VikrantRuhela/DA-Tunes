import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../app/theme/tokens.dart';
import '../../../../shared/widgets/da_card.dart';
import '../../../../shared/providers/player_providers.dart';
import '../../../../core/services/lyrics_controller.dart';

class LyricsPreview extends ConsumerStatefulWidget {
  const LyricsPreview({super.key});

  @override
  ConsumerState<LyricsPreview> createState() => _LyricsPreviewState();
}

class _LyricsPreviewState extends ConsumerState<LyricsPreview> {
  final ScrollController _scrollController = ScrollController();
  int _lastActiveIndex = -1;
  String? _lastSongId;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToActiveLine(int index, double itemExtent) {
    if (!_scrollController.hasClients) return;
    final targetOffset = (index * itemExtent).clamp(0.0, _scrollController.position.maxScrollExtent);
    _scrollController.animateTo(
      targetOffset,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.daColors;
    final typography = context.daTypography;
    final currentSong = ref.watch(currentSongProvider);
    final lyricsState = ref.watch(lyricsControllerProvider);
    final playbackPosition = ref.watch(playbackControllerProvider).position;

    if (currentSong != null && currentSong.id != _lastSongId) {
      _lastSongId = currentSong.id;
      _lastActiveIndex = -1;
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(0.0);
      }
    }

    int activeIndex = -1;
    List<String> lines = [];

    final bool isCorrectSong = currentSong != null && lyricsState.songId == currentSong.id;
    final bool isLoading = lyricsState.isLoading || !isCorrectSong;

    if (isLoading) {
      lines = ['Loading lyrics...'];
    } else if (lyricsState.isInstrumental) {
      lines = ['Instrumental'];
    } else if (lyricsState.syncedLyrics != null && lyricsState.syncedLyrics!.isNotEmpty) {
      final sortedTimestamps = lyricsState.syncedLyrics!.keys.toList()..sort();
      lines = sortedTimestamps.map((t) => lyricsState.syncedLyrics![t]!).toList();
      for (int i = 0; i < sortedTimestamps.length; i++) {
        if (sortedTimestamps[i] <= playbackPosition) {
          activeIndex = i;
        } else {
          break;
        }
      }
    } else if (lyricsState.plainLyrics.isNotEmpty) {
      lines = lyricsState.plainLyrics.split('\n');
    }

    if (lines.isEmpty && !isLoading) {
      lines = [lyricsState.error ?? 'Lyrics unavailable.'];
    }

    const double lineItemExtent = 28.0;

    return Expanded(
      child: GestureDetector(
        onTap: () => PlayerPanelController.toggleLyrics(context, ref),
        child: DACard(
          isHoverable: true,
          padding: const EdgeInsets.all(DATokens.spacingMedium),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'LYRICS PREVIEW',
                    style: typography.caption.copyWith(
                      color: colors.primary,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.0,
                    ),
                  ),
                  Icon(
                    Icons.lyrics_outlined,
                    size: DATokens.iconSmall,
                    color: colors.primary,
                  ),
                ],
              ),
              const SizedBox(height: DATokens.spacingSmall),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final viewportHeight = constraints.maxHeight;
                    final verticalPadding = (viewportHeight - lineItemExtent) / 2;
                    final safePadding = verticalPadding > 0 ? verticalPadding : 0.0;

                    if (activeIndex != _lastActiveIndex && activeIndex != -1) {
                      _lastActiveIndex = activeIndex;
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        _scrollToActiveLine(activeIndex, lineItemExtent);
                      });
                    }

                    return ListView.builder(
                      controller: _scrollController,
                      padding: EdgeInsets.symmetric(vertical: safePadding),
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: lines.length,
                      itemExtent: lineItemExtent,
                      itemBuilder: (context, index) {
                        final isActive = activeIndex != -1 && index == activeIndex;
                        final color = isActive
                            ? colors.primary
                            : colors.textSecondary.withValues(alpha: 0.6);

                        final style = isActive
                            ? typography.body.copyWith(
                                color: color,
                                fontWeight: FontWeight.bold,
                                fontSize: 14.0,
                              )
                            : typography.body.copyWith(
                                color: color,
                                fontSize: 13.0,
                              );

                        return Center(
                          child: AnimatedDefaultTextStyle(
                            duration: const Duration(milliseconds: 200),
                            style: style,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            child: Text(lines[index]),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

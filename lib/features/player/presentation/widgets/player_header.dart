import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../app/theme/tokens.dart';
import 'expand_button.dart';
import '../../../../shared/widgets/da_icon_button.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../shared/providers/player_providers.dart';
import '../../../../shared/utils/song_options.dart';

class PlayerHeader extends ConsumerWidget {
  const PlayerHeader({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.daColors;
    final typography = context.daTypography;
    final currentSong = ref.watch(currentSongProvider);
    final isQueueOpen = ref.watch(activePlayerPanelProvider) == PlayerPanelType.queue;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'NOW PLAYING',
              style: typography.caption.copyWith(
                color: colors.primary,
                letterSpacing: 1.5,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        Row(
          children: [
            DAIconButton(
              icon: Icons.queue_music_outlined,
              tooltip: isQueueOpen ? 'Close Queue' : 'Open Queue',
              onPressed: () => PlayerPanelController.toggleQueue(context, ref),
            ),
            const SizedBox(width: DATokens.spacingTiny),
            ExpandButton(
              onPressed: () => ref.read(immersiveModeProvider.notifier).state = true,
            ),
            const SizedBox(width: DATokens.spacingTiny),
            DAIconButton(
              icon: Icons.more_horiz_outlined,
              tooltip: 'More options',
              onPressed: currentSong != null
                  ? () => showSongOptionsMenu(context, ref, currentSong)
                  : () {},
            ),
          ],
        ),
      ],
    );
  }
}

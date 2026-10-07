import 'package:flutter/material.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../app/theme/tokens.dart';
import '../../../../shared/widgets/da_image.dart';
import '../../../../shared/utils/metadata_formatter.dart';

class SongTile extends StatefulWidget {
  final String title;
  final String artist;
  final String duration;
  final String? coverUrl;
  final VoidCallback? onTap;
  final VoidCallback? onMorePressed;

  const SongTile({
    super.key,
    required this.title,
    required this.artist,
    required this.duration,
    this.coverUrl,
    this.onTap,
    this.onMorePressed,
  });

  @override
  State<SongTile> createState() => _SongTileState();
}

class _SongTileState extends State<SongTile> {
  bool _isHovered = false;
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.daColors;
    final typography = context.daTypography;

    final backgroundColor = _isPressed
        ? colors.surfaceHover.withValues(alpha: 0.9)
        : (_isHovered ? colors.surfaceHover.withValues(alpha: 0.5) : Colors.transparent);

    final duration = _isPressed ? DATokens.durationMedium : DATokens.durationFast;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: AnimatedContainer(
        duration: duration,
        curve: DATokens.curveHover,
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(DATokens.radiusLarge),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(DATokens.radiusLarge),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: widget.onTap,
              splashColor: colors.primary.withValues(alpha: 0.1),
              highlightColor: colors.primary.withValues(alpha: 0.05),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: DATokens.spacingMedium,
                  vertical: DATokens.spacingSmall + 2,
                ),
                child: Row(
                  children: [
                    // Album Thumbnail
                    Container(
                      width: 48.0,
                      height: 48.0,
                      decoration: BoxDecoration(
                        color: colors.border,
                        borderRadius: BorderRadius.circular(8.0),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: DAImage(
                        url: widget.coverUrl,
                        fit: BoxFit.cover,
                        placeholder: _buildPlaceholder(colors),
                      ),
                    ),
                    const SizedBox(width: DATokens.spacingMedium),

                    // Title and Artist
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.title,
                            style: typography.title.copyWith(fontSize: 14.0),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2.0),
                          Text(
                            MetadataFormatter.formatArtist(widget.artist),
                            style: typography.body.copyWith(
                              fontSize: 12.0,
                              color: colors.textSecondary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: DATokens.spacingMedium),

                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        widget.duration,
                        style: typography.caption.copyWith(color: colors.textSecondary),
                      ),
                    ),
                    if (widget.onMorePressed != null) ...[
                      const SizedBox(width: DATokens.spacingSmall),
                      IconButton(
                        icon: Icon(Icons.more_vert, color: colors.textSecondary),
                        onPressed: widget.onMorePressed,
                        constraints: const BoxConstraints(),
                        padding: EdgeInsets.zero,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPlaceholder(dynamic colors) {
    return Center(
      child: Icon(
        Icons.music_note,
        size: DATokens.iconMedium,
        color: colors.textSecondary,
      ),
    );
  }
}

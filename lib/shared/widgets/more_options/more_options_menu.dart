import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'menu_action.dart';
import '../da_image.dart';
import '../../../core/extensions/context_extensions.dart';
import '../../../core/services/device_memory_manager.dart';
import '../../animations/motion_system.dart';

class FloatingMoreOptionsRoute extends PopupRoute<void> {
  final Widget child;
  final Rect targetRect;

  FloatingMoreOptionsRoute({
    required this.child,
    required this.targetRect,
  });

  @override
  Color? get barrierColor => Colors.black.withValues(alpha: 0.25);

  @override
  bool get barrierDismissible => true;

  @override
  String? get barrierLabel => 'Dismiss Options Menu';

  @override
  Duration get transitionDuration => DAMotion.dialogDuration;

  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 180);

  @override
  Widget buildPage(BuildContext context, Animation<double> animation, Animation<double> secondaryAnimation) {
    return child;
  }

  @override
  Widget buildTransitions(BuildContext context, Animation<double> animation, Animation<double> secondaryAnimation, Widget child) {
    final curved = CurvedAnimation(
      parent: animation,
      curve: DAMotion.enterCurve,
      reverseCurve: DAMotion.exitCurve,
    );
    final scale = Tween<double>(begin: 0.95, end: 1.0).animate(curved);
    final opacity = Tween<double>(begin: 0.0, end: 1.0).animate(curved);
    final yOffset = Tween<double>(begin: 10.0, end: 0.0).animate(curved);
    final blur = Tween<double>(begin: 0.0, end: 8.0).animate(curved);

    return AnimatedBuilder(
      animation: animation,
      builder: (context, childWidget) {
        final effectiveBlur = DeviceMemoryManager.instance.getRecommendedBlurSigma(blur.value);
        return BackdropFilter(
          filter: ImageFilter.blur(sigmaX: effectiveBlur, sigmaY: effectiveBlur),
          child: Opacity(
            opacity: opacity.value,
            child: Transform.translate(
              offset: Offset(0, yOffset.value),
              child: Transform.scale(
                scale: scale.value,
                child: childWidget,
              ),
            ),
          ),
        );
      },
      child: child,
    );
  }
}

class AnchoredMenuPositionDelegate extends SingleChildLayoutDelegate {
  final Rect targetRect;
  final Size screenSize;
  final double menuWidth;

  AnchoredMenuPositionDelegate({
    required this.targetRect,
    required this.screenSize,
    required this.menuWidth,
  });

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    return BoxConstraints(
      minWidth: menuWidth,
      maxWidth: menuWidth,
      minHeight: 0,
      maxHeight: screenSize.height - 32.0,
    );
  }

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    double x = targetRect.right - childSize.width;
    if (x < 16.0) {
      x = targetRect.left;
    }
    if (x + childSize.width > screenSize.width - 16.0) {
      x = screenSize.width - childSize.width - 16.0;
    }
    if (x < 16.0) {
      x = 16.0;
    }

    double y = targetRect.bottom + 8.0;
    if (y + childSize.height > screenSize.height - 16.0) {
      y = targetRect.top - childSize.height - 8.0;
    }
    if (y < 16.0) {
      y = 16.0;
    }

    return Offset(x, y);
  }

  @override
  bool shouldRelayout(covariant AnchoredMenuPositionDelegate oldDelegate) {
    return targetRect != oldDelegate.targetRect ||
        screenSize != oldDelegate.screenSize ||
        menuWidth != oldDelegate.menuWidth;
  }
}

class MoreOptionsMenu extends StatelessWidget {
  final String title;
  final String? subtitle;
  final String? artworkUrl;
  final List<MenuAction> actions;

  const MoreOptionsMenu({
    super.key,
    required this.title,
    this.subtitle,
    this.artworkUrl,
    required this.actions,
  });

  static void show({
    required BuildContext context,
    required Rect targetRect,
    required String title,
    String? subtitle,
    String? artworkUrl,
    required List<MenuAction> actions,
  }) {
    Navigator.push(
      context,
      FloatingMoreOptionsRoute(
        targetRect: targetRect,
        child: CustomSingleChildLayout(
          delegate: AnchoredMenuPositionDelegate(
            targetRect: targetRect,
            screenSize: MediaQuery.of(context).size,
            menuWidth: 280.0,
          ),
          child: MoreOptionsMenu(
            title: title,
            subtitle: subtitle,
            artworkUrl: artworkUrl,
            actions: actions,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.daColors;
    final typography = context.daTypography;

    return Material(
      color: Colors.transparent,
      child: Container(
        width: 280.0,
        constraints: const BoxConstraints(maxHeight: 450.0),
        decoration: BoxDecoration(
          color: colors.surface.withValues(alpha: 0.8),
          borderRadius: BorderRadius.circular(24.0),
          border: Border.all(
            color: colors.border.withValues(alpha: 0.3),
            width: 1.0,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.35),
              blurRadius: 20.0,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24.0),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: Row(
                    children: [
                      if (artworkUrl != null) ...[
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8.0),
                          child: DAImage(
                            url: artworkUrl,
                            width: 44.0,
                            height: 44.0,
                            fit: BoxFit.cover,
                            placeholder: Icon(Icons.music_note, color: colors.textSecondary),
                          ),
                        ),
                        const SizedBox(width: 12.0),
                      ],
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              style: typography.title.copyWith(
                                fontSize: 14.0,
                                fontWeight: FontWeight.bold,
                                color: colors.textPrimary,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (subtitle != null) ...[
                              const SizedBox(height: 2.0),
                              Text(
                                subtitle!,
                                style: typography.body.copyWith(
                                  fontSize: 11.5,
                                  color: colors.textSecondary,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10.0),
                Divider(color: colors.border.withValues(alpha: 0.2), height: 1.0),
                const SizedBox(height: 4.0),
                Flexible(
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    child: Column(
                      children: actions.map((action) {
                        return ListTile(
                          dense: true,
                          leading: Icon(
                            action.icon,
                            color: action.color ?? colors.textSecondary,
                            size: 18.0,
                          ),
                          title: Text(
                            action.title,
                            style: typography.body.copyWith(
                              color: action.color ?? colors.textPrimary,
                              fontSize: 13.0,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          onTap: () {
                            HapticFeedback.lightImpact();
                            Navigator.pop(context);
                            action.onTap();
                          },
                        );
                      }).toList(),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

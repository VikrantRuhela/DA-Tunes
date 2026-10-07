import 'dart:ui';
import 'package:flutter/material.dart';
import 'navigation_pill_controller.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../app/theme/tokens.dart';
import '../../../../core/services/device_memory_manager.dart';
import '../../animations/motion_system.dart';

class NavigationPill extends StatelessWidget {
  const NavigationPill({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.daColors;
    final controller = NavigationPillController(context);
    final currentIndex = controller.currentIndex;

    return LayoutBuilder(
      builder: (context, constraints) {
        final double screenWidth = constraints.maxWidth;
        final double pillWidth = screenWidth > 600.0 ? 420.0 : screenWidth - 32.0;

        return Center(
          child: Container(
            width: pillWidth,
            height: 54.0,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(DATokens.radiusLarge),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.25),
                  blurRadius: 16.0,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(DATokens.radiusLarge),
              child: BackdropFilter(
                filter: ImageFilter.blur(
                  sigmaX: DeviceMemoryManager.instance.getRecommendedBlurSigma(12.0),
                  sigmaY: DeviceMemoryManager.instance.getRecommendedBlurSigma(12.0),
                ),
                child: Container(
                  decoration: BoxDecoration(
                    color: colors.surface.withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(DATokens.radiusLarge),
                    border: Border.all(
                      color: colors.border.withValues(alpha: 0.3),
                      width: 1.0,
                    ),
                  ),
                  child: Stack(
                  children: [
                    AnimatedPositioned(
                      duration: DAMotion.tabDuration,
                      curve: DAMotion.standardCurve,
                      left: (currentIndex * (pillWidth / controller.items.length)) + 8.0,
                      top: 6.0,
                      bottom: 6.0,
                      width: (pillWidth / controller.items.length) - 16.0,
                      child: Container(
                        decoration: BoxDecoration(
                          color: colors.primary.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(DATokens.radiusMedium),
                        ),
                      ),
                    ),
                    Row(
                      children: List.generate(controller.items.length, (index) {
                        final item = controller.items[index];
                        final isSelected = index == currentIndex;

                        return Expanded(
                          child: Semantics(
                            label: item.label,
                            selected: isSelected,
                            button: true,
                            child: MouseRegion(
                              cursor: SystemMouseCursors.click,
                              child: GestureDetector(
                                onTap: () => controller.navigateTo(index),
                                behavior: HitTestBehavior.opaque,
                                child: Container(
                                  height: double.infinity,
                                  alignment: Alignment.center,
                                  child: AnimatedScale(
                                    scale: 1.0,
                                    duration: DAMotion.fast,
                                    curve: DAMotion.standardCurve,
                                    child: Icon(
                                      isSelected ? item.selectedIcon : item.icon,
                                      color: isSelected ? colors.primary : colors.textSecondary,
                                      size: DATokens.iconMedium,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        );
                      }),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
  }
}

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import '../../../app/theme/tokens.dart';
import '../../../core/extensions/context_extensions.dart';
import '../../../shared/providers/backend_providers.dart';
import 'widgets/auth_webview_page.dart';
import '../../../shared/animations/motion_system.dart';

class WelcomePage extends ConsumerWidget {
  const WelcomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.daColors;
    final typography = context.daTypography;

    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          // 1. Sleek dark gradient background
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  colors.surface,
                  colors.surfaceCard,
                  Colors.black,
                ],
              ),
            ),
          ),
          
          // 2. Decorative blur circles
          Positioned(
            top: -100,
            right: -100,
            child: Container(
              width: 300,
              height: 300,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: colors.primary.withValues(alpha: 0.15),
              ),
            ),
          ),
          Positioned(
            bottom: -50,
            left: -50,
            child: Container(
              width: 250,
              height: 250,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: colors.primary.withValues(alpha: 0.1),
              ),
            ),
          ),

          // 3. Main Welcome Content
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(DATokens.spacingLarge),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Decorative Logo
                    Container(
                      padding: const EdgeInsets.all(DATokens.spacingMedium),
                      decoration: BoxDecoration(
                        color: colors.primary.withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: colors.primary.withValues(alpha: 0.3),
                          width: 2.0,
                        ),
                      ),
                      child: Icon(
                        Icons.music_note_outlined,
                        size: 72.0,
                        color: colors.primary,
                      ),
                    )
                    .animate()
                    .scale(duration: 600.ms, curve: Curves.easeOutCubic)
                    .fadeIn(duration: 400.ms),

                    const SizedBox(height: DATokens.spacingLarge),

                    Text(
                      'Welcome to DA Tunes',
                      style: typography.display.copyWith(
                        fontWeight: FontWeight.bold,
                        fontSize: 32.0,
                      ),
                      textAlign: TextAlign.center,
                    )
                    .animate()
                    .slideY(begin: 0.2, end: 0, delay: 100.ms, duration: 400.ms)
                    .fadeIn(delay: 100.ms, duration: 400.ms),

                    const SizedBox(height: DATokens.spacingSmall),

                    Text(
                      'Your premium local library and YouTube Music hub',
                      style: typography.body.copyWith(
                        color: colors.textSecondary,
                        fontSize: 16.0,
                      ),
                      textAlign: TextAlign.center,
                    )
                    .animate()
                    .slideY(begin: 0.2, end: 0, delay: 200.ms, duration: 400.ms)
                    .fadeIn(delay: 200.ms, duration: 400.ms),

                    const SizedBox(height: 50.0),

                    // Action buttons
                    SizedBox(
                      width: 280,
                      height: 50,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: colors.primary,
                          foregroundColor: Colors.black,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(DATokens.radiusMedium),
                          ),
                          elevation: 4.0,
                        ),
                        onPressed: () async {
                          if (kIsWeb) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Web authentication not supported.')),
                            );
                            return;
                          }
                          
                          final success = await Navigator.push<bool>(
                            context,
                            DAMotion.createPageRoute(builder: (context) => const AuthWebViewPage()),
                          );
                          if (success == true && context.mounted) {
                            context.go('/');
                          }
                        },
                        child: const FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            'Continue with YouTube Music',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15.0),
                          ),
                        ),
                      ),
                    )
                    .animate()
                    .slideY(begin: 0.3, end: 0, delay: 300.ms, duration: 500.ms, curve: Curves.easeOut)
                    .fadeIn(delay: 300.ms, duration: 500.ms),

                    const SizedBox(height: DATokens.spacingMedium),

                    SizedBox(
                      width: 280,
                      height: 50,
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: colors.textPrimary,
                          side: BorderSide(color: colors.textSecondary.withValues(alpha: 0.4)),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(DATokens.radiusMedium),
                          ),
                        ),
                        onPressed: () async {
                          await ref.read(sessionManagerProvider).setGuestMode(true);
                        },
                        child: const FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            'Continue as Guest',
                            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15.0),
                          ),
                        ),
                      ),
                    )
                    .animate()
                    .slideY(begin: 0.3, end: 0, delay: 400.ms, duration: 500.ms, curve: Curves.easeOut)
                    .fadeIn(delay: 400.ms, duration: 500.ms),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

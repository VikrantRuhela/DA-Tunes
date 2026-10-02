import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../app/theme/tokens.dart';
import '../../../core/extensions/context_extensions.dart';
import '../../../shared/widgets/da_card.dart';
import '../../../shared/animations/motion_system.dart';

class AboutPage extends ConsumerWidget {
  const AboutPage({super.key});

  String _getArchitecture() {
    final version = Platform.version.toLowerCase();
    if (version.contains('x64') || version.contains('x86_64')) return 'x64';
    if (version.contains('arm64') || version.contains('aarch64')) return 'arm64';
    if (version.contains('arm')) return 'arm';
    if (version.contains('x86') || version.contains('ia32')) return 'x86';
    return 'Unknown';
  }

  String _getPlatformName() {
    if (Platform.isWindows) return 'Windows';
    if (Platform.isAndroid) return 'Android';
    if (Platform.isIOS) return 'iOS';
    if (Platform.isMacOS) return 'macOS';
    if (Platform.isLinux) return 'Linux';
    return 'Unknown';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.daColors;
    final typography = context.daTypography;
    final scaleMode = ref.watch(motionScaleModeProvider);
    final isReduced = scaleMode == MotionScaleMode.reduced || scaleMode == MotionScaleMode.disabled;
    final duration = isReduced ? 150.ms : 450.ms;

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new, color: colors.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'About',
          style: typography.title.copyWith(fontSize: 20.0, fontWeight: FontWeight.bold),
        ),
      ),
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(
          horizontal: DATokens.spacingLarge,
          vertical: DATokens.spacingMedium,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              height: 180,
              width: double.infinity,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24.0),
                color: colors.surfaceCard,
                border: Border.all(
                  color: colors.border.withValues(alpha: 0.2),
                  width: 1.0,
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24.0),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Positioned.fill(
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: RadialGradient(
                            colors: [
                              colors.primary.withValues(alpha: 0.12),
                              Colors.transparent,
                            ],
                            radius: 0.8,
                          ),
                        ),
                      ),
                    ),
                    const Positioned.fill(
                      child: FloatingParticlesWidget(),
                    ),
                    Positioned.fill(
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              colors.background.withValues(alpha: 0.4),
                              Colors.transparent,
                              colors.background.withValues(alpha: 0.4),
                            ],
                          ),
                        ),
                      ),
                    ),
                    
                    // Logo image (keep motion blur exactly as it is)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
                      child: Image.asset(
                        'assets/images/da_logo.png',
                        fit: BoxFit.contain,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: DATokens.spacingLarge),

            // 2. About DA Tunes Description
            _buildSectionHeader(context, 'About DA Tunes'),
            DACard(
              child: Padding(
                padding: const EdgeInsets.all(DATokens.spacingMedium),
                child: Text(
                  'DA Tunes is a modern, open-source YouTube Music client focused on delivering a premium listening experience through elegant design, smooth animations, and powerful audio features. Built with Flutter, it combines aesthetics with functionality while remaining lightweight, fast, and completely free.',
                  style: typography.body.copyWith(
                    fontSize: 14.0,
                    height: 1.5,
                    color: colors.textPrimary.withValues(alpha: 0.9),
                  ),
                ),
              ),
            ),
            const SizedBox(height: DATokens.spacingLarge),

            // 3. Key Features
            _buildSectionHeader(context, 'Key Features'),
            const SeamlessFeatureTickerWidget(),
            const SizedBox(height: DATokens.spacingLarge),

            // 4. Version & System Layout Card
            _buildSectionHeader(context, 'Application Info'),
            DACard(
              child: Padding(
                padding: const EdgeInsets.all(DATokens.spacingMedium),
                child: Column(
                  children: [
                    _buildVersionRow(context, 'App Name', 'DA Tunes'),
                    const Divider(height: 1, color: Colors.white10),
                    _buildVersionRow(context, 'Version', '2.0'),
                    const Divider(height: 1, color: Colors.white10),
                    _buildVersionRow(context, 'Build Number', '200'),
                    const Divider(height: 1, color: Colors.white10),
                    _buildVersionRow(context, 'Release Channel', 'Stable'),
                    const Divider(height: 1, color: Colors.white10),
                    _buildVersionRow(context, 'Flutter Version', '3.22.2'),
                    const Divider(height: 1, color: Colors.white10),
                    _buildVersionRow(context, 'Platform', _getPlatformName()),
                    const Divider(height: 1, color: Colors.white10),
                    _buildVersionRow(context, 'Architecture', _getArchitecture()),
                  ],
                ),
              ),
            ),
            const SizedBox(height: DATokens.spacingLarge),

            // 5. Developer Card
            _buildSectionHeader(context, 'Developer'),
            DACard(
              child: Padding(
                padding: const EdgeInsets.all(DATokens.spacingMedium),
                child: Row(
                  children: [
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: colors.primary.withValues(alpha: 0.15), width: 1.5),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(26.0),
                        child: Image.asset(
                          'assets/images/developer.jpg',
                          fit: BoxFit.cover,
                          errorBuilder: (ctx, err, st) => Icon(Icons.person_outline, color: colors.primary, size: 28.0),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16.0),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          GestureDetector(
                            onTap: () async {
                              final uri = Uri.parse('https://github.com/VikrantRuhela');
                              try {
                                if (await canLaunchUrl(uri)) {
                                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                                }
                              } catch (_) {}
                            },
                            child: Text(
                              'Vikrant Ruhela',
                              style: typography.title.copyWith(fontSize: 16.0, fontWeight: FontWeight.bold),
                            ),
                          ),
                          const SizedBox(height: 2.0),
                          Text(
                            'Founder',
                            style: typography.body.copyWith(fontSize: 13.0, color: colors.textSecondary),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: DATokens.spacingLarge),

            // 6. Libraries & Credits Expandable Section
            _buildSectionHeader(context, 'Libraries & Credits'),
            DACard(
              child: Theme(
                data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  leading: Icon(Icons.library_books_outlined, color: colors.primary),
                  title: Text(
                    'Used Libraries',
                    style: typography.title.copyWith(fontSize: 15.0),
                  ),
                  subtitle: Text(
                    'Major open-source packages in this project',
                    style: typography.body.copyWith(fontSize: 12.0, color: colors.textSecondary),
                  ),
                  iconColor: colors.primary,
                  collapsedIconColor: colors.textSecondary,
                  childrenPadding: const EdgeInsets.only(bottom: 8.0),
                  children: [
                    _buildCreditItem(context, 'flutter_riverpod', 'State management solution', 'https://pub.dev/packages/flutter_riverpod'),
                    _buildCreditItem(context, 'go_router', 'Declarative routing system', 'https://pub.dev/packages/go_router'),
                    _buildCreditItem(context, 'media_kit', 'Cross-platform hardware video/audio playback', 'https://pub.dev/packages/media_kit'),
                    _buildCreditItem(context, 'audioplayers', 'Audio playback library', 'https://pub.dev/packages/audioplayers'),
                    _buildCreditItem(context, 'flutter_animate', 'Performant visual animations', 'https://pub.dev/packages/flutter_animate'),
                    _buildCreditItem(context, 'drift', 'Reactive local SQLite database', 'https://pub.dev/packages/drift'),
                    _buildCreditItem(context, 'window_manager', 'Desktop window management control', 'https://pub.dev/packages/window_manager'),
                  ],
                ),
              ),
            ),
            const SizedBox(height: DATokens.spacingLarge),

            // 7. Support Development Star Card
            _buildSectionHeader(context, 'Support Development'),
            DACard(
              child: Padding(
                padding: const EdgeInsets.all(DATokens.spacingMedium),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'If you enjoy DA Tunes and would like to support its development, consider starring the project on GitHub.',
                      style: typography.body.copyWith(fontSize: 13.0, height: 1.4),
                    ),
                    const SizedBox(height: DATokens.spacingMedium),
                    SizedBox(
                      width: double.infinity,
                      height: 40,
                      child: ElevatedButton.icon(
                        onPressed: () async {
                          final uri = Uri.parse('https://github.com/VikrantRuhela/DA-Tunes');
                          try {
                            if (await canLaunchUrl(uri)) {
                              final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
                              if (!launched && context.mounted) {
                                _showLaunchError(context);
                              }
                            } else if (context.mounted) {
                              _showLaunchError(context);
                            }
                          } catch (_) {
                            if (context.mounted) {
                              _showLaunchError(context);
                            }
                          }
                        },
                        icon: const Icon(Icons.star, color: Colors.amber),
                        label: Text(
                          'Star on GitHub',
                          style: TextStyle(color: colors.textPrimary, fontWeight: FontWeight.bold),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: colors.primary.withValues(alpha: 0.12),
                          elevation: 0,
                          side: BorderSide(color: colors.primary.withValues(alpha: 0.3), width: 1.0),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.0)),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // 8. Footer Section
            const SizedBox(height: DATokens.spacingXLarge),
            Center(
              child: Column(
                children: [
                  Text(
                    'DA Tunes',
                    style: typography.title.copyWith(fontSize: 16.0, fontWeight: FontWeight.bold, letterSpacing: 1.1),
                  ),
                  const SizedBox(height: 2.0),
                  Text(
                    'Music Meets Aesthetics',
                    style: typography.body.copyWith(fontSize: 12.0, color: colors.textSecondary),
                  ),
                  const SizedBox(height: 8.0),
                  Text(
                    'Made with ❤️ in India',
                    style: typography.body.copyWith(fontSize: 11.0, color: colors.textSecondary.withValues(alpha: 0.7)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: DATokens.spacingXXLarge),
          ],
        )
        .animate()
        .fadeIn(duration: duration, curve: Curves.easeOut)
        .slideY(begin: 0.05, end: 0, duration: duration, curve: Curves.easeOut),
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

  Widget _buildVersionRow(BuildContext context, String key, String value) {
    final colors = context.daColors;
    final typography = context.daTypography;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  key,
                  style: typography.body.copyWith(fontSize: 12.0, color: colors.textSecondary),
                ),
                const SizedBox(height: 2.0),
                Text(
                  value,
                  style: typography.title.copyWith(fontSize: 15.0, fontWeight: FontWeight.w500),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.copy_outlined, size: 18.0),
            color: colors.primary.withValues(alpha: 0.8),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: value));
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Copied "$value" to clipboard'),
                  backgroundColor: colors.primary,
                  duration: const Duration(seconds: 2),
                ),
              );
            },
            tooltip: 'Copy',
          ),
        ],
      ),
    );
  }

  Widget _buildFeatureItem(BuildContext context, IconData icon, String label) {
    final colors = context.daColors;
    final typography = context.daTypography;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          padding: const EdgeInsets.all(10.0),
          decoration: BoxDecoration(
            color: colors.primary.withValues(alpha: 0.05),
            shape: BoxShape.circle,
            border: Border.all(color: colors.primary.withValues(alpha: 0.12), width: 1.0),
          ),
          child: Icon(icon, color: colors.primary, size: 24.0),
        ),
        const SizedBox(height: 8.0),
        Text(
          label,
          style: typography.body.copyWith(fontSize: 11.0, fontWeight: FontWeight.w500),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildCreditItem(BuildContext context, String name, String desc, String url) {
    final colors = context.daColors;
    final typography = context.daTypography;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 2.0),
      title: Text(name, style: typography.title.copyWith(fontSize: 14.0, fontWeight: FontWeight.w600)),
      subtitle: Text(desc, style: typography.body.copyWith(fontSize: 12.0, color: colors.textSecondary)),
      trailing: const Icon(Icons.arrow_forward_ios, size: 12.0),
      onTap: () async {
        final uri = Uri.parse(url);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        }
      },
    );
  }
  void _showLaunchError(BuildContext context) {
    final colors = context.daColors;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Could not open repository link. Please check your web browser.'),
        backgroundColor: colors.primary,
        duration: const Duration(seconds: 3),
      ),
    );
  }
}

class SeamlessFeatureTickerWidget extends StatefulWidget {
  const SeamlessFeatureTickerWidget({super.key});

  @override
  State<SeamlessFeatureTickerWidget> createState() => _SeamlessFeatureTickerWidgetState();
}

class _SeamlessFeatureTickerWidgetState extends State<SeamlessFeatureTickerWidget> with SingleTickerProviderStateMixin {
  late final AnimationController _animController;
  final GlobalKey _singleSetKey = GlobalKey();
  double _singleSetWidth = 0.0;

  static const List<String> _features = [
    'Dynamic Colors',
    'Lyrics',
    'Insights',
    'Player Styles',
    'Audio Controls',
    'Offline Cache',
    'Open Source',
  ];

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 22),
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final renderBox = _singleSetKey.currentContext?.findRenderObject() as RenderBox?;
      if (renderBox != null && renderBox.hasSize && mounted) {
        setState(() {
          _singleSetWidth = renderBox.size.width;
        });
        _animController.repeat();
      }
    });
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.daColors;
    final typography = context.daTypography;

    Widget buildFeatureChips({Key? key}) {
      return Row(
        key: key,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final feature in _features) ...[
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 6.0, vertical: 10.0),
              padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 6.0),
              decoration: BoxDecoration(
                color: colors.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12.0),
                border: Border.all(
                  color: colors.primary.withValues(alpha: 0.25),
                  width: 1.0,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: colors.primary,
                    ),
                  ),
                  const SizedBox(width: 8.0),
                  Text(
                    feature,
                    style: typography.body.copyWith(
                      fontSize: 12.0,
                      fontWeight: FontWeight.w600,
                      color: colors.textPrimary,
                      letterSpacing: 0.4,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      );
    }

    return Container(
      width: double.infinity,
      height: 52,
      clipBehavior: Clip.hardEdge,
      decoration: BoxDecoration(
        color: colors.surfaceCard,
        borderRadius: BorderRadius.circular(16.0),
        border: Border.all(
          color: colors.primary.withValues(alpha: 0.2),
          width: 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: colors.primary.withValues(alpha: 0.05),
            blurRadius: 10,
            spreadRadius: 1,
          ),
        ],
      ),
      child: IgnorePointer(
        child: AnimatedBuilder(
          animation: _animController,
          builder: (context, child) {
            final shift = _singleSetWidth > 0 ? _animController.value * _singleSetWidth : 0.0;
            return OverflowBox(
              minWidth: 0,
              maxWidth: double.infinity,
              alignment: Alignment.centerLeft,
              child: Transform.translate(
                offset: Offset(-shift, 0),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    buildFeatureChips(key: _singleSetKey),
                    buildFeatureChips(),
                    buildFeatureChips(),
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

class FloatingParticlesWidget extends StatefulWidget {
  const FloatingParticlesWidget({super.key});

  @override
  State<FloatingParticlesWidget> createState() => _FloatingParticlesWidgetState();
}

class _FloatingParticlesWidgetState extends State<FloatingParticlesWidget> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  final List<_Particle> _particles = [];

  @override
  void initState() {
    super.initState();
    final rand = Random();
    for (int i = 0; i < 12; i++) {
      _particles.add(_Particle(
        x: rand.nextDouble(),
        y: rand.nextDouble(),
        size: rand.nextDouble() * 1.5 + 0.5,
        speedY: rand.nextDouble() * 0.0005 + 0.0002,
        speedX: (rand.nextDouble() - 0.5) * 0.0004,
        opacity: rand.nextDouble() * 0.15 + 0.05,
      ));
    }
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 10),
    )..addListener(() {
        final rand = Random();
        for (final p in _particles) {
          p.y -= p.speedY;
          p.x += p.speedX;
          if (p.y < 0) {
            p.y = 1.0;
            p.x = rand.nextDouble();
          }
          if (p.x < 0 || p.x > 1.0) {
            p.speedX = -p.speedX;
          }
        }
      })..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.daColors;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return CustomPaint(
          painter: _ParticlesPainter(_particles, colors.primary),
        );
      },
    );
  }
}

class _ParticlesPainter extends CustomPainter {
  final List<_Particle> particles;
  final Color color;

  _ParticlesPainter(this.particles, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;
    for (final p in particles) {
      paint.color = color.withValues(alpha: p.opacity);
      canvas.drawCircle(Offset(p.x * size.width, p.y * size.height), p.size, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

class _Particle {
  double x;
  double y;
  double size;
  double speedY;
  double speedX;
  double opacity;

  _Particle({
    required this.x,
    required this.y,
    required this.size,
    required this.speedY,
    required this.speedX,
    required this.opacity,
  });
}

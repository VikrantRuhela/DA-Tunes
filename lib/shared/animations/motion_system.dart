import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

enum MotionScaleMode { normal, reduced, disabled }

enum DAPageTransitionType {
  tab,
  hierarchical,
  modal,
  fade,
}

final motionScaleModeProvider = StateProvider<MotionScaleMode>((ref) => MotionScaleMode.normal);

class DAMotion {
  DAMotion._();

  static const Duration veryFast = Duration(milliseconds: 120);
  static const Duration fast = Duration(milliseconds: 180);
  static const Duration standard = Duration(milliseconds: 240);
  static const Duration medium = Duration(milliseconds: 280);
  static const Duration emphasized = Duration(milliseconds: 360);
  static const Duration large = Duration(milliseconds: 420);
  static const Duration extraLarge = Duration(milliseconds: 600);

  static const Duration tabDuration = Duration(milliseconds: 240);
  static const Duration navDuration = Duration(milliseconds: 300);
  static const Duration panelDuration = Duration(milliseconds: 320);
  static const Duration playerDuration = Duration(milliseconds: 360);
  static const Duration dialogDuration = Duration(milliseconds: 220);

  static const Curve enterCurve = Curves.easeOutCubic;
  static const Curve exitCurve = Curves.easeInOutCubic;
  static const Curve standardCurve = Curves.easeInOutCubic;
  static const Curve emphasizedCurve = Cubic(0.2, 0.0, 0.0, 1.0);
  static const Curve easeOut = Curves.easeOut;
  static const Curve easeIn = Curves.easeIn;
  static const Curve fastOutSlowIn = Curves.fastOutSlowIn;
  static const Curve spring = Curves.easeOutCubic;

  static Duration getDuration(WidgetRef ref, Duration baseDuration) {
    final mode = ref.watch(motionScaleModeProvider);
    switch (mode) {
      case MotionScaleMode.normal:
        return baseDuration;
      case MotionScaleMode.reduced:
        return Duration(milliseconds: (baseDuration.inMilliseconds * 0.5).toInt());
      case MotionScaleMode.disabled:
        return Duration.zero;
    }
  }

  static Curve getCurve(WidgetRef ref, Curve baseCurve) {
    final mode = ref.watch(motionScaleModeProvider);
    if (mode == MotionScaleMode.reduced || mode == MotionScaleMode.disabled) {
      return Curves.linear;
    }
    return baseCurve;
  }

  static MotionScaleMode getScaleMode(BuildContext context) {
    try {
      if (MediaQuery.of(context).disableAnimations) {
        return MotionScaleMode.disabled;
      }
      return ProviderScope.containerOf(context, listen: false).read(motionScaleModeProvider);
    } catch (_) {
      return MotionScaleMode.normal;
    }
  }

  static Page<dynamic> buildPageTransition({
    required LocalKey key,
    required Widget child,
    required DAPageTransitionType type,
    String? name,
    Object? arguments,
    String? restorationId,
  }) {
    Duration duration;
    Duration reverseDuration;

    switch (type) {
      case DAPageTransitionType.tab:
        duration = tabDuration;
        reverseDuration = tabDuration;
        break;
      case DAPageTransitionType.hierarchical:
        duration = navDuration;
        reverseDuration = const Duration(milliseconds: 240);
        break;
      case DAPageTransitionType.modal:
        duration = panelDuration;
        reverseDuration = const Duration(milliseconds: 260);
        break;
      case DAPageTransitionType.fade:
        duration = standard;
        reverseDuration = standard;
        break;
    }

    return CustomTransitionPage<void>(
      key: key,
      name: name,
      arguments: arguments,
      restorationId: restorationId,
      transitionDuration: duration,
      reverseTransitionDuration: reverseDuration,
      transitionsBuilder: (context, animation, secondaryAnimation, pageChild) {
        final mode = getScaleMode(context);
        if (mode == MotionScaleMode.disabled) {
          return pageChild;
        }

        if (mode == MotionScaleMode.reduced) {
          return FadeTransition(
            opacity: animation,
            child: pageChild,
          );
        }

        switch (type) {
          case DAPageTransitionType.tab:
            final tabCurved = CurvedAnimation(
              parent: animation,
              curve: standardCurve,
              reverseCurve: standardCurve,
            );
            return FadeTransition(
              opacity: tabCurved,
              child: ScaleTransition(
                scale: Tween<double>(begin: 0.985, end: 1.0).animate(tabCurved),
                child: pageChild,
              ),
            );

          case DAPageTransitionType.hierarchical:
            final enterAnimation = CurvedAnimation(
              parent: animation,
              curve: enterCurve,
              reverseCurve: exitCurve,
            );
            final secondaryCurved = CurvedAnimation(
              parent: secondaryAnimation,
              curve: enterCurve,
              reverseCurve: exitCurve,
            );

            return SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(1.0, 0.0),
                end: Offset.zero,
              ).animate(enterAnimation),
              child: FadeTransition(
                opacity: Tween<double>(begin: 0.0, end: 1.0).animate(
                  CurvedAnimation(
                    parent: animation,
                    curve: const Interval(0.0, 0.7, curve: Curves.easeOut),
                    reverseCurve: const Interval(0.3, 1.0, curve: Curves.easeIn),
                  ),
                ),
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: Offset.zero,
                    end: const Offset(-0.25, 0.0),
                  ).animate(secondaryCurved),
                  child: pageChild,
                ),
              ),
            );

          case DAPageTransitionType.modal:
            final modalCurved = CurvedAnimation(
              parent: animation,
              curve: enterCurve,
              reverseCurve: exitCurve,
            );
            return SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0.0, 1.0),
                end: Offset.zero,
              ).animate(modalCurved),
              child: FadeTransition(
                opacity: Tween<double>(begin: 0.0, end: 1.0).animate(
                  CurvedAnimation(
                    parent: animation,
                    curve: const Interval(0.0, 0.6, curve: Curves.easeOut),
                    reverseCurve: const Interval(0.4, 1.0, curve: Curves.easeIn),
                  ),
                ),
                child: pageChild,
              ),
            );

          case DAPageTransitionType.fade:
            final fadeCurved = CurvedAnimation(
              parent: animation,
              curve: standardCurve,
              reverseCurve: standardCurve,
            );
            return FadeTransition(
              opacity: fadeCurved,
              child: pageChild,
            );
        }
      },
      child: child,
    );
  }

  static Route<T> createPageRoute<T>({
    required WidgetBuilder builder,
    RouteSettings? settings,
    DAPageTransitionType type = DAPageTransitionType.hierarchical,
  }) {
    Duration duration;
    Duration reverseDuration;

    switch (type) {
      case DAPageTransitionType.tab:
        duration = tabDuration;
        reverseDuration = tabDuration;
        break;
      case DAPageTransitionType.hierarchical:
        duration = navDuration;
        reverseDuration = const Duration(milliseconds: 240);
        break;
      case DAPageTransitionType.modal:
        duration = panelDuration;
        reverseDuration = const Duration(milliseconds: 260);
        break;
      case DAPageTransitionType.fade:
        duration = standard;
        reverseDuration = standard;
        break;
    }

    return PageRouteBuilder<T>(
      settings: settings,
      transitionDuration: duration,
      reverseTransitionDuration: reverseDuration,
      pageBuilder: (context, animation, secondaryAnimation) => builder(context),
      transitionsBuilder: (context, animation, secondaryAnimation, pageChild) {
        final mode = getScaleMode(context);
        if (mode == MotionScaleMode.disabled) {
          return pageChild;
        }

        if (mode == MotionScaleMode.reduced) {
          return FadeTransition(
            opacity: animation,
            child: pageChild,
          );
        }

        switch (type) {
          case DAPageTransitionType.tab:
            final tabCurved = CurvedAnimation(
              parent: animation,
              curve: standardCurve,
              reverseCurve: standardCurve,
            );
            return FadeTransition(
              opacity: tabCurved,
              child: ScaleTransition(
                scale: Tween<double>(begin: 0.985, end: 1.0).animate(tabCurved),
                child: pageChild,
              ),
            );

          case DAPageTransitionType.hierarchical:
            final enterAnimation = CurvedAnimation(
              parent: animation,
              curve: enterCurve,
              reverseCurve: exitCurve,
            );
            final secondaryCurved = CurvedAnimation(
              parent: secondaryAnimation,
              curve: enterCurve,
              reverseCurve: exitCurve,
            );

            return SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(1.0, 0.0),
                end: Offset.zero,
              ).animate(enterAnimation),
              child: FadeTransition(
                opacity: Tween<double>(begin: 0.0, end: 1.0).animate(
                  CurvedAnimation(
                    parent: animation,
                    curve: const Interval(0.0, 0.7, curve: Curves.easeOut),
                    reverseCurve: const Interval(0.3, 1.0, curve: Curves.easeIn),
                  ),
                ),
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: Offset.zero,
                    end: const Offset(-0.25, 0.0),
                  ).animate(secondaryCurved),
                  child: pageChild,
                ),
              ),
            );

          case DAPageTransitionType.modal:
            final modalCurved = CurvedAnimation(
              parent: animation,
              curve: enterCurve,
              reverseCurve: exitCurve,
            );
            return SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0.0, 1.0),
                end: Offset.zero,
              ).animate(modalCurved),
              child: FadeTransition(
                opacity: Tween<double>(begin: 0.0, end: 1.0).animate(
                  CurvedAnimation(
                    parent: animation,
                    curve: const Interval(0.0, 0.6, curve: Curves.easeOut),
                    reverseCurve: const Interval(0.4, 1.0, curve: Curves.easeIn),
                  ),
                ),
                child: pageChild,
              ),
            );

          case DAPageTransitionType.fade:
            final fadeCurved = CurvedAnimation(
              parent: animation,
              curve: standardCurve,
              reverseCurve: standardCurve,
            );
            return FadeTransition(
              opacity: fadeCurved,
              child: pageChild,
            );
        }
      },
    );
  }
}

extension WidgetRefMotion on WidgetRef {
  Duration scaledDuration(Duration baseDuration) => DAMotion.getDuration(this, baseDuration);
  Curve scaledCurve(Curve baseCurve) => DAMotion.getCurve(this, baseCurve);
}

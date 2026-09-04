import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/locale_controller.dart';

/// Shown while `authControllerProvider`'s session-restore is resolving.
/// Purely decorative — the router redirects away once auth state settles,
/// so this widget never navigates itself; the animations just loop/hold
/// until the screen is disposed out from under them.
class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen>
    with TickerProviderStateMixin {
  static const _navyDark = Color(0xFF0A1128);
  static const _navyMid = Color(0xFF13224A);
  static const _gold = Color(0xFFD4AF37);
  static const _goldSoft = Color(0xFFF4E3B2);

  late final AnimationController _entrance = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..forward();

  late final AnimationController _ring = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 8),
  )..repeat();

  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  )..repeat(reverse: true);

  late final Animation<double> _logoScale = CurvedAnimation(
    parent: _entrance,
    curve: const Interval(0.0, 0.7, curve: Curves.easeOutBack),
  );

  late final Animation<double> _logoFade = CurvedAnimation(
    parent: _entrance,
    curve: const Interval(0.0, 0.5, curve: Curves.easeOut),
  );

  late final Animation<double> _textFade = CurvedAnimation(
    parent: _entrance,
    curve: const Interval(0.5, 1.0, curve: Curves.easeOut),
  );

  late final Animation<double> _textSlide = CurvedAnimation(
    parent: _entrance,
    curve: const Interval(0.5, 1.0, curve: Curves.easeOutCubic),
  );

  @override
  void dispose() {
    _entrance.dispose();
    _ring.dispose();
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(translationsProvider);

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [_navyDark, _navyMid, _navyDark],
          ),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 220,
                height: 220,
                child: AnimatedBuilder(
                  animation: Listenable.merge([_entrance, _ring, _pulse]),
                  builder: (context, _) {
                    final pulseScale = 1.0 + (_pulse.value * 0.04);
                    return Stack(
                      alignment: Alignment.center,
                      children: [
                        Transform.rotate(
                          angle: _ring.value * 6.28318,
                          child: Container(
                            width: 200,
                            height: 200,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: SweepGradient(
                                colors: [
                                  _gold.withValues(alpha: 0.0),
                                  _goldSoft.withValues(alpha: 0.55),
                                  _gold.withValues(alpha: 0.0),
                                  _gold.withValues(alpha: 0.0),
                                  _goldSoft.withValues(alpha: 0.35),
                                  _gold.withValues(alpha: 0.0),
                                ],
                              ),
                            ),
                          ),
                        ),
                        Container(
                          width: 170 * pulseScale,
                          height: 170 * pulseScale,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: _gold.withValues(
                                  alpha: 0.25 + (_pulse.value * 0.15),
                                ),
                                blurRadius: 30,
                                spreadRadius: 4,
                              ),
                            ],
                          ),
                        ),
                        Opacity(
                          opacity: _logoFade.value,
                          child: Transform.scale(
                            scale: _logoScale.value,
                            child: ClipOval(
                              child: Container(
                                width: 150,
                                height: 150,
                                color: Colors.white,
                                padding: const EdgeInsets.all(6),
                                child: ClipOval(
                                  child: Image.asset(
                                    'assets/branding/app_logo.png',
                                    fit: BoxFit.cover,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
              const SizedBox(height: 28),
              AnimatedBuilder(
                animation: _entrance,
                builder: (context, child) {
                  return Opacity(
                    opacity: _textFade.value,
                    child: Transform.translate(
                      offset: Offset(0, 16 * (1 - _textSlide.value)),
                      child: child,
                    ),
                  );
                },
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      t['splash.clinicName']!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: _goldSoft,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        height: 1.4,
                      ),
                    ),
                    Text(
                      t['splash.universityName']!,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 40),
              FadeTransition(
                opacity: _textFade,
                child: const SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    valueColor: AlwaysStoppedAnimation<Color>(_gold),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

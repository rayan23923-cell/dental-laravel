import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_config.dart';
import '../../../core/i18n/locale_controller.dart';
import '../../../core/widgets/tg_spinner.dart';
import 'auth_controller.dart';

/// Set once the opening animation has played and the screen has faded
/// out. The router keeps `/splash` on screen until then, so a session that
/// restores instantly still gets the full intro (by request, 2026-10-29:
/// "انميشن عند اول فتح للتطبيق", Telegram-style). Only flips once per run.
final splashDoneProvider = StateProvider<bool>((ref) => false);

/// The app's opening screen, in the style of Telegram's launch: on the
/// same plain background as the native launch window (white, or black in
/// dark mode, so there is no flash between the two), the logo springs in
/// while two rings ripple out from it, the name rises in under it, and a
/// Telegram spinner shows while the session restores. When both are done
/// the logo swells slightly and everything fades into the app.
class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen>
    with TickerProviderStateMixin {
  late final AnimationController _intro = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1300),
  )..forward().whenComplete(_maybeExit);

  late final AnimationController _exit = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 380),
  );

  late final Animation<double> _logoScale = Tween(begin: 0.4, end: 1.0).animate(
    CurvedAnimation(parent: _intro, curve: const Interval(0.0, 0.55, curve: Curves.elasticOut)),
  );
  late final Animation<double> _logoFade = CurvedAnimation(
    parent: _intro,
    curve: const Interval(0.0, 0.2, curve: Curves.easeOut),
  );
  late final Animation<double> _ripple = CurvedAnimation(
    parent: _intro,
    curve: const Interval(0.15, 0.85, curve: Curves.easeOutCubic),
  );
  late final Animation<double> _text = CurvedAnimation(
    parent: _intro,
    curve: const Interval(0.35, 0.75, curve: Curves.easeOutCubic),
  );
  late final Animation<double> _spinner = CurvedAnimation(
    parent: _intro,
    curve: const Interval(0.7, 1.0, curve: Curves.easeOut),
  );

  void _maybeExit() {
    if (!mounted || _exit.isAnimating || _exit.isCompleted) return;
    if (!_intro.isCompleted || ref.read(authControllerProvider).isLoading) return;
    _exit.forward().whenComplete(() {
      if (mounted) ref.read(splashDoneProvider.notifier).state = true;
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Decoded up front so the logo isn't an empty white disc as it pops in.
    precacheImage(const AssetImage(AppConfig.brandLogoAsset), context);
  }

  @override
  void dispose() {
    _intro.dispose();
    _exit.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(translationsProvider);
    ref.listen(authControllerProvider, (_, __) => _maybeExit());
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    final dark = theme.brightness == Brightness.dark;

    return Scaffold(
      body: AnimatedBuilder(
        animation: Listenable.merge([_intro, _exit]),
        builder: (context, _) {
          final exit = Curves.easeIn.transform(_exit.value);
          return Opacity(
            opacity: 1 - exit,
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 240,
                    height: 240,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        for (final delay in const [0.0, 0.3])
                          _Ripple(
                            progress: ((_ripple.value - delay) / (1 - delay)).clamp(0.0, 1.0),
                            color: primary,
                          ),
                        Opacity(
                          opacity: _logoFade.value,
                          child: Transform.scale(
                            scale: _logoScale.value * (1 + 0.12 * exit),
                            child: Container(
                              width: 132,
                              height: 132,
                              padding: const EdgeInsets.all(5),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: primary.withValues(alpha: dark ? 0.35 : 0.22),
                                    blurRadius: 28,
                                    offset: const Offset(0, 8),
                                  ),
                                ],
                              ),
                              child: ClipOval(
                                child: Image.asset(AppConfig.brandLogoAsset, fit: BoxFit.cover),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Opacity(
                    opacity: _text.value,
                    child: Transform.translate(
                      offset: Offset(0, 18 * (1 - _text.value)),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            t[AppConfig.storeBuild ? 'store.appName' : 'splash.clinicName']!,
                            textAlign: TextAlign.center,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                              height: 1.4,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            t[AppConfig.storeBuild ? 'store.tagline' : 'splash.universityName']!,
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 36),
                  Opacity(
                    opacity: _spinner.value,
                    child: const TgSpinner(size: 28, strokeWidth: 3),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// One ring that grows out from behind the logo and fades as it goes.
class _Ripple extends StatelessWidget {
  const _Ripple({required this.progress, required this.color});
  final double progress;
  final Color color;

  @override
  Widget build(BuildContext context) {
    if (progress <= 0 || progress >= 1) return const SizedBox.shrink();
    final d = 132 + 108 * progress;
    return Container(
      width: d,
      height: d,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: color.withValues(alpha: 0.45 * (1 - progress)),
          width: 2.5 * (1 - progress) + 0.5,
        ),
      ),
    );
  }
}

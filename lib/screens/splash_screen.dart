import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'auth_screen.dart';   // ✅ changed

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  late AnimationController _mainController;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;
  late AnimationController _subtitleController;
  late AnimationController _iconController;
  late Animation<double> _iconFadeAnimation;
  late Animation<double> _pulseAnimation;
  late AnimationController _fadeOutController;

  @override
  void initState() {
    super.initState();

    _mainController = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _mainController, curve: Curves.easeOut),
    );
    _scaleAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _mainController, curve: Curves.easeOutCubic),
    );

    _subtitleController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );

    _iconController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );
    _iconFadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _iconController, curve: Curves.easeIn),
    );
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.2).animate(
      CurvedAnimation(parent: _iconController, curve: Curves.easeInOut),
    );

    _fadeOutController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );

    _mainController.forward();

    Timer(const Duration(milliseconds: 600), () {
      if (mounted) _subtitleController.forward();
    });

    Timer(const Duration(milliseconds: 1100), () {
      if (mounted) _iconController.forward();
    });

    Timer(const Duration(seconds: 3), () {
      if (mounted) {
        _fadeOutController.forward().then((_) {
          Navigator.pushReplacement(
            context,
            PageRouteBuilder(
              pageBuilder: (_, __, ___) => const AuthScreen(),   // ✅ changed from CheckAuthScreen
              transitionDuration: const Duration(milliseconds: 300),
              transitionsBuilder: (_, animation, __, child) =>
                  FadeTransition(opacity: animation, child: child),
            ),
          );
        });
      }
    });
  }

  @override
  void dispose() {
    _mainController.dispose();
    _subtitleController.dispose();
    _iconController.dispose();
    _fadeOutController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _fadeOutController,
      builder: (context, child) {
        return Opacity(
          opacity: 1.0 - _fadeOutController.value,
          child: child,
        );
      },
      child: Scaffold(
        body: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: const [
                Color(0xFF000000),
                Color(0xFF121212),
                Color(0xFF2C2C2C),
              ],
            ),
          ),
          child: SafeArea(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  AnimatedBuilder(
                    animation: _mainController,
                    builder: (context, child) {
                      return Opacity(
                        opacity: _fadeAnimation.value,
                        child: Transform.scale(
                          scale: _scaleAnimation.value,
                          child: ShaderMask(
                            shaderCallback: (bounds) => const LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [Color(0xFFFFFFFF), Color(0xFFBDBDBD)],
                            ).createShader(bounds),
                            child: Text(
                              'SHACHAH',
                              style: GoogleFonts.playfairDisplay(
                                fontSize: 56,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                                letterSpacing: 3,
                                shadows: [
                                  Shadow(
                                    blurRadius: 12,
                                    color: Colors.white.withOpacity(0.3),
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 24),
                  FadeTransition(
                    opacity: _subtitleController,
                    child: Text(
                      'BLESSED HOPE ASSEMBLY OF GOD\nWORSHIP TEAM',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.montserrat(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        color: const Color(0xFFBDBDBD),
                        letterSpacing: 1.2,
                        height: 1.5,
                      ),
                    ),
                  ),
                  const SizedBox(height: 80),
                  FadeTransition(
                    opacity: _iconFadeAnimation,
                    child: const SizedBox(
                      width: 40,
                      height: 40,
                      child: CircularProgressIndicator(
                        valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFBDBDBD)),
                        strokeWidth: 2,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'package:nomade_client/services/auth_service.dart';
import 'package:nomade_client/services/notification_service.dart';
import 'package:nomade_client/screens/auth-firebase/auth/sign_in_screen.dart';
import 'package:nomade_client/screens/auth-firebase/phoneLogin/phone_login_screen.dart';
import 'package:nomade_client/screens/auth-firebase/signUp/components/sign_up_form.dart';
import 'package:nomade_client/screens/auth-firebase/auth/complete_phone_screen.dart';
import 'package:nomade_client/screens/HomeScreen/home_screen_app.dart';
import 'package:nomade_client/constants.dart';
import 'package:nomade_client/theme/app_colors.dart';

class SignUpScreen extends StatefulWidget {
  const SignUpScreen({super.key});

  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  final AuthService _authService = AuthService();
  bool _isGoogleLoading = false;
  bool _showEmailForm = false;

  Future<void> _signInWithGoogle() async {
    setState(() => _isGoogleLoading = true);
    try {
      final user = await _authService.signInWithGoogle();
      if (user != null && mounted) {
        await NotificationService().refreshTokenForUser();
        if (!mounted) return;
        final hasPhone = await _authService.hasPhoneNumber(user.uid);
        if (!mounted) return;
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(
            builder: (_) =>
                hasPhone ? const HomeScreenApp() : const CompletePhoneScreen(),
          ),
          (_) => false,
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString()),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isGoogleLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final c = isDark ? AppColors.dark : AppColors.light;

    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 48),

              // ── Logo + Titre ──────────────────────────────────────
              Center(
                child: Image.asset(
                  'assets/images/velox-logo-sansBG.png',
                  width: 96,
                  height: 96,
                  fit: BoxFit.contain,
                  errorBuilder: (_, _, _) => Container(
                    width: 96,
                    height: 96,
                    decoration: BoxDecoration(
                      color: primaryColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Icon(
                      Icons.delivery_dining_rounded,
                      size: 40,
                      color: primaryColor,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Center(
                child: Text(
                  'Velox',
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: primaryColor,
                    letterSpacing: -0.5,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Center(
                child: Text(
                  'Livraison & taxi à Djibouti',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: c.onSurfaceVariant,
                  ),
                ),
              ),

              const SizedBox(height: 40),

              // ── Titre section ─────────────────────────────────────
              Text(
                'Créer votre compte',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: c.onSurface,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Rejoignez des milliers d\'utilisateurs à Djibouti',
                style: theme.textTheme.bodyMedium?.copyWith(color: c.onSurfaceVariant),
              ),

              const SizedBox(height: 28),

              // ── Bouton Téléphone (principal) ──────────────────────
              _PrimaryAuthButton(
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const PhoneLoginScreen()),
                ),
                icon: Icons.phone_android_rounded,
                label: 'Continuer avec le téléphone',
                color: primaryColor,
              ),

              const SizedBox(height: 12),

              // ── Bouton Google ─────────────────────────────────────
              _GoogleAuthButton(
                onTap: _isGoogleLoading ? null : _signInWithGoogle,
                isLoading: _isGoogleLoading,
                colors: c,
              ),

              // ── Divider "ou" ──────────────────────────────────────
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Row(
                  children: [
                    Expanded(child: Divider(color: c.outlineVariant)),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Text(
                        'ou',
                        style: TextStyle(color: c.onSurfaceVariant, fontSize: 13),
                      ),
                    ),
                    Expanded(child: Divider(color: c.outlineVariant)),
                  ],
                ),
              ),

              // ── Toggle formulaire email ───────────────────────────
              GestureDetector(
                onTap: () => setState(() => _showEmailForm = !_showEmailForm),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.email_outlined,
                      size: 16,
                      color: c.onSurfaceVariant,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _showEmailForm
                          ? 'Masquer le formulaire email'
                          : 'S\'inscrire avec email et mot de passe',
                      style: TextStyle(
                        color: c.onSurfaceVariant,
                        fontSize: 13,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ],
                ),
              ),

              // ── Formulaire email (expandable) ─────────────────────
              if (_showEmailForm) ...[
                const SizedBox(height: 20),
                const SignUpForm(),
              ],

              const SizedBox(height: 32),

              // ── Déjà un compte ────────────────────────────────────
              Center(
                child: Text.rich(
                  TextSpan(
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                    text: 'Déjà un compte ? ',
                    children: [
                      TextSpan(
                        text: 'Se connecter',
                        style: const TextStyle(
                          color: primaryColor,
                          fontWeight: FontWeight.w600,
                        ),
                        recognizer: TapGestureRecognizer()
                          ..onTap = () => Navigator.pushReplacement(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const SignInScreen(),
                                ),
                              ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // ── CGU ───────────────────────────────────────────────
              Center(
                child: Text(
                  'En continuant, vous acceptez nos Conditions\nd\'utilisation et notre Politique de confidentialité.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 11,
                    color: c.onSurfaceVariant.withValues(alpha: 0.7),
                    height: 1.5,
                  ),
                ),
              ),

              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Bouton auth principal ─────────────────────────────────────────────────────

class _PrimaryAuthButton extends StatelessWidget {
  final VoidCallback? onTap;
  final IconData icon;
  final String label;
  final Color color;

  const _PrimaryAuthButton({
    required this.onTap,
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          height: 56,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            children: [
              Icon(icon, color: Colors.white, size: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const Icon(Icons.arrow_forward_ios_rounded,
                  color: Colors.white54, size: 16),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Bouton Google ─────────────────────────────────────────────────────────────

class _GoogleAuthButton extends StatelessWidget {
  final VoidCallback? onTap;
  final bool isLoading;
  final AppColors colors;

  const _GoogleAuthButton({required this.onTap, required this.isLoading, required this.colors});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          height: 56,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          decoration: BoxDecoration(
            border: Border.all(color: colors.outlineVariant, width: 1.5),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              if (isLoading)
                const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                SvgPicture.asset('assets/icons/google.svg', width: 22, height: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  isLoading ? 'Connexion en cours...' : 'Continuer avec Google',
                  style: TextStyle(
                    color: isLoading ? colors.onSurfaceVariant : colors.onSurface,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (!isLoading)
                Icon(Icons.arrow_forward_ios_rounded,
                    color: colors.onSurfaceVariant, size: 16),
            ],
          ),
        ),
      ),
    );
  }
}

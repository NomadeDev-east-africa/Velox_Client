import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:nomade_client/services/auth_service.dart';
import 'package:nomade_client/services/notification_service.dart';
import 'package:nomade_client/screens/HomeScreen/home_screen_app.dart';

import '../../../components/buttons/social_button.dart';
import '../../../components/welcome_text.dart';
import '../../../constants.dart';
import 'sign_up_screen.dart';
import 'components/sign_in_form.dart';
import '../phoneLogin/phone_login_screen.dart';

class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key});

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  final AuthService _authService = AuthService();
  bool _isLoadingGoogle = false;
  bool _isLoadingApple = false;

  Future<void> _signInWithGoogle() async {
    setState(() => _isLoadingGoogle = true);

    try {
      final user = await _authService.signInWithGoogle();

      if (user != null && mounted) {
        // ✅ Rafraîchir le token FCM après connexion Google
        await NotificationService().refreshTokenForUser();
        if (!mounted) return;
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(
            builder: (context) => const HomeScreenApp(),
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
      if (mounted) {
        setState(() => _isLoadingGoogle = false);
      }
    }
  }

  Future<void> _signInWithApple() async {
    setState(() => _isLoadingApple = true);

    try {
      final user = await _authService.signInWithApple();

      if (user != null && mounted) {
        await NotificationService().refreshTokenForUser();
        if (!mounted) return;
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(
            builder: (context) => const HomeScreenApp(),
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
      if (mounted) {
        setState(() => _isLoadingApple = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: const SizedBox(),
        title: const Text("Sign In"),
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: defaultPadding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const WelcomeText(
                title: "Welcome to",
                text:
                "Enter your Phone number or Email \naddress for sign in. Enjoy your food :)",
              ),
              const SignInForm(),
              const SizedBox(height: defaultPadding),
              const KOrText(),
              const SizedBox(height: defaultPadding * 1.5),

              Center(
                child: Text.rich(
                  TextSpan(
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall!
                        .copyWith(fontWeight: FontWeight.w600),
                    text: "Don't have account? ",
                    children: <TextSpan>[
                      TextSpan(
                        text: "Create new account.",
                        style: const TextStyle(color: primaryColor),
                        recognizer: TapGestureRecognizer()
                          ..onTap = () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const SignUpScreen(),
                            ),
                          ),
                      )
                    ],
                  ),
                ),
              ),
              const SizedBox(height: defaultPadding),

              // NOUVEAU : Bouton Phone/OTP
              ElevatedButton.icon(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const PhoneLoginScreen(),
                    ),
                  );
                },
                icon: const Icon(Icons.phone_android),
                label: const Text("Se connecter avec Téléphone"),
                style: ElevatedButton.styleFrom(
                  backgroundColor: secondaryColor,
                  minimumSize: const Size(double.infinity, 56),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
              const SizedBox(height: defaultPadding),

              // Facebook (non configuré - optionnel)
              SocialButton(
                press: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Facebook - À configurer plus tard'),
                    ),
                  );
                },
                text: "Connect with Facebook",
                color: const Color(0xFF395998),
                icon: SvgPicture.asset(
                  'assets/icons/facebook.svg',
                  colorFilter: const ColorFilter.mode(
                    Color(0xFF395998),
                    BlendMode.srcIn,
                  ),
                ),
              ),
              const SizedBox(height: defaultPadding),

              // Apple - CONFIGURÉ FIREBASE (requis avec Google, guideline 4.8)
              SocialButton(
                press: _isLoadingApple ? () {} : _signInWithApple,
                text: _isLoadingApple ? "Connexion..." : "Connect with Apple",
                color: Colors.black,
                icon: _isLoadingApple
                    ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor:
                    AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                )
                    : const FittedBox(
                  fit: BoxFit.contain,
                  child: Icon(Icons.apple, color: Colors.black),
                ),
              ),
              const SizedBox(height: defaultPadding),

              // Google - CONFIGURÉ FIREBASE
              SocialButton(
                press: _isLoadingGoogle ? () {} : _signInWithGoogle,
                text: _isLoadingGoogle
                    ? "Connexion..."
                    : "Connect with Google",
                color: const Color(0xFF4285F4),
                icon: _isLoadingGoogle
                    ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor:
                    AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                )
                    : SvgPicture.asset(
                  'assets/icons/google.svg',
                ),
              ),
              const SizedBox(height: defaultPadding),
            ],
          ),
        ),
      ),
    );
  }
}
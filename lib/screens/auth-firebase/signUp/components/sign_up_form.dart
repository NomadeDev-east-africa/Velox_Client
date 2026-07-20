import 'package:flutter/material.dart';
import 'package:nomade_client/components/inputs/djibouti_phone.dart';
import 'package:nomade_client/services/auth_service.dart';
import 'package:nomade_client/screens/HomeScreen/home_screen_app.dart';
import 'package:nomade_client/constants.dart';
import 'package:nomade_client/services/notification_service.dart';
import 'package:nomade_client/translations/app_translations.dart';

class SignUpForm extends StatefulWidget {
  const SignUpForm({super.key});

  @override
  State<SignUpForm> createState() => _SignUpFormState();
}

class _SignUpFormState extends State<SignUpForm> {
  final _formKey = GlobalKey<FormState>();
  final AuthService _authService = AuthService();

  // Controllers
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();

  bool _obscureText = true;
  bool _isLoading = false;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _signUp() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      // Inscription avec Firebase
      final user = await _authService.signUpWithEmailPassword(
        email: _emailController.text,
        password: _passwordController.text,
        name: _nameController.text,
        phone: toE164Djibouti(_phoneController.text),
      );

      if (user != null && mounted) {
        // ✅ Rafraîchir le token FCM après inscription
        await NotificationService().refreshTokenForUser();
        if (!mounted) return;
        // SUCCÈS - Navigation vers home
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(
            builder: (context) => const HomeScreenApp(),
          ),
              (_) => false,
        );
      }
    } catch (e) {
      // Erreur
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
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      child: Column(
        children: [
          // Name Field
          TextFormField(
            controller: _nameController,
            validator: (value) {
              if (value == null || value.isEmpty) {
                return 'Entrez votre nom';
              }
              return null;
            },
            textInputAction: TextInputAction.next,
            keyboardType: TextInputType.name,
            decoration: const InputDecoration(
              hintText: "Nom complet",
              prefixIcon: Icon(Icons.person),
            ),
            enabled: !_isLoading,
          ),
          const SizedBox(height: defaultPadding),

          // Email Field
          TextFormField(
            controller: _emailController,
            validator: emailValidator.call,
            textInputAction: TextInputAction.next,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(
              hintText: "Email Address",
              prefixIcon: Icon(Icons.email),
            ),
            enabled: !_isLoading,
          ),
          const SizedBox(height: defaultPadding),

          // Phone Field (obligatoire)
          TextFormField(
            controller: _phoneController,
            inputFormatters: djiboutiPhoneInputFormatters(),
            validator: validateDjiboutiPhone,
            textInputAction: TextInputAction.next,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(
              hintText: "77 XX XX XX",
              prefixIcon: DjiboutiPrefix(),
              prefixIconConstraints: BoxConstraints(minWidth: 0),
            ),
            enabled: !_isLoading,
          ),
          const SizedBox(height: defaultPadding),

          // Password Field
          TextFormField(
            controller: _passwordController,
            obscureText: _obscureText,
            validator: passwordValidator.call,
            textInputAction: TextInputAction.done,
            onFieldSubmitted: (_) => _signUp(),
            decoration: InputDecoration(
              hintText: tr('password'),
              prefixIcon: const Icon(Icons.lock),
              suffixIcon: GestureDetector(
                onTap: () {
                  setState(() {
                    _obscureText = !_obscureText;
                  });
                },
                child: _obscureText
                    ? Icon(Icons.visibility_off, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.54))
                    : Icon(Icons.visibility, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.54)),
              ),
            ),
            enabled: !_isLoading,
          ),
          const SizedBox(height: defaultPadding * 2),

          // Sign Up Button
          ElevatedButton(
            onPressed: _isLoading ? null : _signUp,
            child: _isLoading
                ? const SizedBox(
              height: 20,
              width: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
              ),
            )
                : Text(tr('signup')),
          ),
        ],
      ),
    );
  }
}
import 'package:flutter/material.dart';
import 'package:nomade_client/services/auth_service.dart';
import 'phone_recovery_screen.dart';
import 'reset_email_sent_screen.dart';

import '../../../components/welcome_text.dart';
import '../../../constants.dart';

/// Récupération de mot de passe — deux voies au choix : par email (lien de
/// réinitialisation Firebase) ou par SMS/OTP (définition d'un nouveau mot de
/// passe après vérification du numéro lié au compte).
class ForgotPasswordScreen extends StatelessWidget {
  const ForgotPasswordScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mot de passe oublié'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: defaultPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const WelcomeText(
              title: 'Mot de passe oublié',
              text:
                  'Choisissez comment réinitialiser votre mot de passe : par '
                  'email ou par SMS.',
            ),
            const SizedBox(height: defaultPadding),

            // ── Voie SMS (OTP → nouveau mot de passe) ──────────────
            OutlinedButton.icon(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const PhoneRecoveryScreen(),
                ),
              ),
              icon: const Icon(Icons.sms_outlined),
              label: const Text('Réinitialiser par SMS'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(double.infinity, 52),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
            const SizedBox(height: defaultPadding * 1.5),

            Row(
              children: [
                const Expanded(child: Divider()),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Text('ou par email',
                      style: Theme.of(context).textTheme.bodySmall),
                ),
                const Expanded(child: Divider()),
              ],
            ),
            const SizedBox(height: defaultPadding * 1.5),

            // ── Voie email (lien de réinitialisation Firebase) ─────
            const _EmailResetForm(),
            const SizedBox(height: defaultPadding),
          ],
        ),
      ),
    );
  }
}

class _EmailResetForm extends StatefulWidget {
  const _EmailResetForm();

  @override
  State<_EmailResetForm> createState() => _EmailResetFormState();
}

class _EmailResetFormState extends State<_EmailResetForm> {
  final _formKey = GlobalKey<FormState>();
  final AuthService _authService = AuthService();
  final TextEditingController _emailController = TextEditingController();

  bool _isLoading = false;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _resetPassword() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      await _authService.resetPassword(_emailController.text);

      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => ResetEmailSentScreen(
              email: _emailController.text,
            ),
          ),
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
          TextFormField(
            controller: _emailController,
            validator: emailValidator.call,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.done,
            onFieldSubmitted: (_) => _resetPassword(),
            decoration: const InputDecoration(
              hintText: 'Adresse email',
              prefixIcon: Icon(Icons.email),
            ),
            enabled: !_isLoading,
          ),
          const SizedBox(height: defaultPadding),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _isLoading ? null : _resetPassword,
              child: _isLoading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : const Text('Envoyer le lien par email'),
            ),
          ),
        ],
      ),
    );
  }
}

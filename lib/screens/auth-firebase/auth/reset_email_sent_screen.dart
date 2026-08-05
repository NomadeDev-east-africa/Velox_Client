import 'package:flutter/material.dart';
import 'package:nomade_client/services/auth_service.dart';

import '../../../constants.dart';
import '../../../components/welcome_text.dart';

class ResetEmailSentScreen extends StatefulWidget {
  final String email;

  const ResetEmailSentScreen({
    super.key,
    required this.email,
  });

  @override
  State<ResetEmailSentScreen> createState() => _ResetEmailSentScreenState();
}

class _ResetEmailSentScreenState extends State<ResetEmailSentScreen> {
  final AuthService _authService = AuthService();
  bool _isResending = false;

  Future<void> _resendEmail() async {
    setState(() => _isResending = true);

    try {
      await _authService.resetPassword(widget.email);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Email renvoyé avec succès!'),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
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
        setState(() => _isResending = false);
      }
    }
  }

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
            WelcomeText(
              title: 'Email envoyé',
              text:
                  'Nous avons envoyé un lien de réinitialisation à \n${widget.email}',
            ),
            const SizedBox(height: defaultPadding),
            
            // Info card
            Container(
              padding: const EdgeInsets.all(defaultPadding),
              decoration: BoxDecoration(
                color: primaryColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: primaryColor.withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline,
                    color: primaryColor,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Vérifiez votre boîte de réception et vos spams',
                      style: TextStyle(
                        fontSize: 14,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: defaultPadding * 2),
            
            // Send again button
            ElevatedButton(
              onPressed: _isResending ? null : _resendEmail,
              child: _isResending
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : const Text('Renvoyer l\'email'),
            ),

            const SizedBox(height: defaultPadding),

            // Back to login
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                Navigator.pop(context);
              },
              child: const Text("Retour à la connexion"),
            ),
          ],
        ),
      ),
    );
  }
}

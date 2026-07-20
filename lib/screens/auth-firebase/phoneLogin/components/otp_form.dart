import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nomade_client/services/notification_service.dart';
import 'package:nomade_client/services/auth_service.dart';
import 'package:nomade_client/screens/HomeScreen/home_screen_app.dart';

import '../../../../constants.dart';
import '../../../../components/buttons/primary_button.dart';
import '../../../../translations/app_translations.dart';

class OtpForm extends StatefulWidget {
  final String verificationId;
  final String phoneNumber;

  const OtpForm({
    super.key,
    required this.verificationId,
    required this.phoneNumber,
  });

  @override
  State<OtpForm> createState() => _OtpFormState();
}

class _OtpFormState extends State<OtpForm> {
  static const _codeLength = 6;

  final _formKey = GlobalKey<FormState>();
  final AuthService _authService = AuthService();

  final List<TextEditingController> _controllers = List.generate(
    _codeLength,
    (_) => TextEditingController(),
  );
  final List<FocusNode> _nodes = List.generate(_codeLength, (_) => FocusNode());

  bool _isLoading = false;

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    for (final n in _nodes) {
      n.dispose();
    }
    super.dispose();
  }

  String _getOTPCode() => _controllers.map((c) => c.text).join();

  /// iOS livre le code SMS entier ("123456") dans le champ focalisé plutôt que
  /// chiffre par chiffre : on le répartit sur les cases au lieu de le tronquer.
  void _handleChanged(int index, String value) {
    if (value.length > 1) {
      // Deux caractères = l'utilisateur retape par-dessus une case déjà remplie :
      // on ne garde que le NOUVEAU chiffre ici (le dernier), sinon _fillFrom
      // pousserait l'ancien dans la case suivante et écraserait sa saisie.
      // 3+ caractères = collage / autofill du code entier → on répartit.
      if (value.length == 2) {
        final last = value.substring(1);
        _controllers[index].value = TextEditingValue(
          text: last,
          selection: const TextSelection.collapsed(offset: 1),
        );
      } else {
        _fillFrom(value);
        return;
      }
    }
    if (_controllers[index].text.isEmpty) return;

    if (index < _codeLength - 1) {
      _nodes[index + 1].requestFocus();
    } else {
      _nodes[index].unfocus();
      _verifyOTP();
    }
  }

  void _fillFrom(String digits) {
    for (var i = 0; i < _codeLength; i++) {
      _controllers[i].text = i < digits.length ? digits[i] : '';
    }

    if (digits.length >= _codeLength) {
      FocusScope.of(context).unfocus();
      _verifyOTP();
    } else {
      _nodes[digits.length].requestFocus();
    }
  }

  Future<void> _verifyOTP() async {
    if (!_formKey.currentState!.validate()) return;

    final code = _getOTPCode();
    if (code.length != _codeLength) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Entrez le code à 6 chiffres complet'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      // Vérifier le code OTP avec Firebase
      final user = await _authService.verifyOTP(
        verificationId: widget.verificationId,
        smsCode: code,
      );

      if (user != null && mounted) {
        // ✅ Rafraîchir le token FCM après connexion téléphone
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
      child: AutofillGroup(
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: List.generate(_codeLength, (i) {
                return SizedBox(
                  width: 48,
                  height: 48,
                  child: TextFormField(
                    controller: _controllers[i],
                    focusNode: _nodes[i],
                    autofocus: i == 0,
                    onChanged: (value) => _handleChanged(i, value),
                    validator: (v) => (v == null || v.isEmpty) ? '' : null,
                    autofillHints: const [AutofillHints.oneTimeCode],
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    textAlign: TextAlign.center,
                    decoration: otpInputDecoration,
                    enabled: !_isLoading,
                  ),
                );
              }),
            ),
            const SizedBox(height: defaultPadding * 2),

            // Info loading
            if (_isLoading)
              Container(
                padding: const EdgeInsets.all(defaultPadding),
                margin: const EdgeInsets.only(bottom: defaultPadding),
                decoration: BoxDecoration(
                  color: secondaryColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    SizedBox(width: 12),
                    Text(
                      'Vérification en cours...',
                      style: TextStyle(fontSize: 14),
                    ),
                  ],
                ),
              ),

            // Continue Button
            PrimaryButton(
              text: _isLoading ? 'Vérification...' : tr('continue'),
              press: _isLoading ? () {} : _verifyOTP,
            )
          ],
        ),
      ),
    );
  }
}

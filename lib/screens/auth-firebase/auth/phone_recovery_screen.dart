import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nomade_client/components/inputs/djibouti_phone.dart';
import 'package:nomade_client/constants.dart';
import 'package:nomade_client/screens/homeScreen/home_screen_app.dart';
import 'package:nomade_client/services/auth_service.dart';
import 'package:nomade_client/services/notification_service.dart';

/// Récupération de mot de passe par SMS : numéro → code OTP → nouveau mot de
/// passe. L'OTP authentifie le compte qui possède ce numéro (lié à Firebase
/// Auth), puis on remplace le mot de passe via `updatePassword`.
class PhoneRecoveryScreen extends StatefulWidget {
  const PhoneRecoveryScreen({super.key});

  @override
  State<PhoneRecoveryScreen> createState() => _PhoneRecoveryScreenState();
}

enum _Step { enterPhone, enterCode, setPassword }

class _PhoneRecoveryScreenState extends State<PhoneRecoveryScreen> {
  final AuthService _authService = AuthService();

  final _phoneFormKey = GlobalKey<FormState>();
  final _passwordFormKey = GlobalKey<FormState>();
  final _phoneController = TextEditingController();
  final _codeController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();

  _Step _step = _Step.enterPhone;
  String? _verificationId;
  String _sentTo = '';
  bool _isBusy = false;
  bool _obscure = true;

  @override
  void dispose() {
    _phoneController.dispose();
    _codeController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  // ── Étape 1 : envoi du code ────────────────────────────────────
  Future<void> _sendCode() async {
    if (!_phoneFormKey.currentState!.validate()) return;
    final e164 = toE164Djibouti(_phoneController.text);

    setState(() => _isBusy = true);
    await _authService.sendOtpCode(
      phoneNumber: e164,
      codeSent: (verificationId) {
        if (!mounted) return;
        setState(() {
          _isBusy = false;
          _verificationId = verificationId;
          _sentTo = e164;
          _step = _Step.enterCode;
        });
      },
      verificationFailed: (error) {
        if (!mounted) return;
        setState(() => _isBusy = false);
        _showError(error);
      },
    );
  }

  // ── Étape 2 : vérification du code ─────────────────────────────
  Future<void> _verifyCode() async {
    final code = _codeController.text.trim();
    if (code.length != 6 || _verificationId == null) {
      _showError('Entrez le code à 6 chiffres reçu par SMS.');
      return;
    }
    setState(() => _isBusy = true);
    try {
      await _authService.signInForPasswordRecovery(
        verificationId: _verificationId!,
        smsCode: code,
      );
      if (!mounted) return;
      setState(() {
        _isBusy = false;
        _step = _Step.setPassword;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isBusy = false);
      _showError(e.toString());
    }
  }

  // ── Étape 3 : nouveau mot de passe ─────────────────────────────
  Future<void> _savePassword() async {
    if (!_passwordFormKey.currentState!.validate()) return;
    setState(() => _isBusy = true);
    try {
      await _authService.setNewPassword(_passwordController.text);
      // Le compte est authentifié : on entre directement dans l'app.
      await NotificationService().refreshTokenForUser();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Mot de passe mis à jour'),
          backgroundColor: Color(0xFF4CAF50),
          behavior: SnackBarBehavior.floating,
        ),
      );
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const HomeScreenApp()),
        (_) => false,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isBusy = false);
      _showError(e.toString());
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Récupération par SMS'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(defaultPadding),
          child: switch (_step) {
            _Step.enterPhone => _buildPhoneStep(context),
            _Step.enterCode => _buildCodeStep(context),
            _Step.setPassword => _buildPasswordStep(context),
          },
        ),
      ),
    );
  }

  Widget _buildPhoneStep(BuildContext context) {
    return Form(
      key: _phoneFormKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: defaultPadding),
          Text('Mot de passe oublié',
              style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 8),
          Text(
            'Entrez le numéro de téléphone associé à votre compte. Vous '
            'recevrez un code de vérification par SMS.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: defaultPadding * 1.5),
          TextFormField(
            controller: _phoneController,
            autofocus: true,
            keyboardType: TextInputType.phone,
            textInputAction: TextInputAction.done,
            onFieldSubmitted: (_) => _sendCode(),
            inputFormatters: djiboutiPhoneInputFormatters(),
            validator: validateDjiboutiPhone,
            decoration: const InputDecoration(
              hintText: '77 XX XX XX',
              prefixIcon: DjiboutiPrefix(),
              prefixIconConstraints: BoxConstraints(minWidth: 0),
            ),
            enabled: !_isBusy,
          ),
          const SizedBox(height: defaultPadding * 1.5),
          _primaryButton('Recevoir le code', _sendCode),
        ],
      ),
    );
  }

  Widget _buildCodeStep(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: defaultPadding),
        Text('Entrez le code',
            style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 8),
        Text('Code à 6 chiffres envoyé au $_sentTo.',
            style: Theme.of(context).textTheme.bodyMedium),
        const SizedBox(height: defaultPadding * 1.5),
        TextField(
          controller: _codeController,
          autofocus: true,
          keyboardType: TextInputType.number,
          textInputAction: TextInputAction.done,
          maxLength: 6,
          onSubmitted: (_) => _verifyCode(),
          autofillHints: const [AutofillHints.oneTimeCode],
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: const InputDecoration(
            hintText: '000000',
            counterText: '',
            prefixIcon: Icon(Icons.sms_outlined),
          ),
          enabled: !_isBusy,
        ),
        const SizedBox(height: defaultPadding * 1.5),
        _primaryButton('Vérifier', _verifyCode),
        const SizedBox(height: 8),
        TextButton(
          onPressed: _isBusy
              ? null
              : () => setState(() => _step = _Step.enterPhone),
          child: const Text('Modifier le numéro'),
        ),
      ],
    );
  }

  Widget _buildPasswordStep(BuildContext context) {
    return Form(
      key: _passwordFormKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: defaultPadding),
          Text('Nouveau mot de passe',
              style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 8),
          Text('Choisissez un nouveau mot de passe pour votre compte.',
              style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: defaultPadding * 1.5),
          TextFormField(
            controller: _passwordController,
            obscureText: _obscure,
            validator: passwordValidator.call,
            textInputAction: TextInputAction.next,
            decoration: InputDecoration(
              hintText: 'Nouveau mot de passe',
              prefixIcon: const Icon(Icons.lock_outline),
              suffixIcon: IconButton(
                icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ),
            enabled: !_isBusy,
          ),
          const SizedBox(height: defaultPadding),
          TextFormField(
            controller: _confirmController,
            obscureText: _obscure,
            textInputAction: TextInputAction.done,
            onFieldSubmitted: (_) => _savePassword(),
            validator: (v) => (v != _passwordController.text)
                ? 'Les mots de passe ne correspondent pas'
                : null,
            decoration: const InputDecoration(
              hintText: 'Confirmer le mot de passe',
              prefixIcon: Icon(Icons.lock_outline),
            ),
            enabled: !_isBusy,
          ),
          const SizedBox(height: defaultPadding * 1.5),
          _primaryButton('Enregistrer', _savePassword),
        ],
      ),
    );
  }

  Widget _primaryButton(String label, VoidCallback onPressed) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: _isBusy ? null : onPressed,
        child: _isBusy
            ? const SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              )
            : Text(label),
      ),
    );
  }
}

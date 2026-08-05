import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nomade_client/components/inputs/djibouti_phone.dart';
import 'package:nomade_client/constants.dart';
import 'package:nomade_client/providers/all_providers.dart';
import 'package:nomade_client/screens/homeScreen/home_screen_app.dart';
import 'package:nomade_client/services/auth_service.dart';

/// Écran bloquant demandant le numéro de téléphone après une connexion
/// Google/Apple/email (qui n'en fournissent aucun). Le numéro est **réellement
/// lié à Firebase Auth** (provider `phone`) via un OTP — et non plus seulement
/// écrit dans Firestore, ce qui laissait Firebase créer un compte fantôme à la
/// prochaine connexion par SMS.
class CompletePhoneScreen extends ConsumerStatefulWidget {
  /// Numéro (chiffres locaux) pré-rempli, ex. depuis le formulaire d'inscription.
  final String? initialPhone;

  const CompletePhoneScreen({super.key, this.initialPhone});

  @override
  ConsumerState<CompletePhoneScreen> createState() =>
      _CompletePhoneScreenState();
}

enum _Step { enterPhone, enterCode }

class _CompletePhoneScreenState extends ConsumerState<CompletePhoneScreen> {
  final _phoneFormKey = GlobalKey<FormState>();
  final _phoneController = TextEditingController();
  final _codeController = TextEditingController();
  final AuthService _authService = AuthService();

  _Step _step = _Step.enterPhone;
  String? _verificationId;
  String _sentTo = '';
  bool _isBusy = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialPhone != null) {
      _phoneController.text = localDigitsFrom(widget.initialPhone);
    }
  }

  @override
  void dispose() {
    _phoneController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  // ── Étape 1 : envoi du code ────────────────────────────────────
  Future<void> _sendCode() async {
    if (!_phoneFormKey.currentState!.validate()) return;
    final e164 = toE164Djibouti(_phoneController.text);

    setState(() => _isBusy = true);
    await _authService.verifyPhoneForLinking(
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
      autoLinked: () {
        // Android : code lu automatiquement → déjà lié.
        _onLinked();
      },
      verificationFailed: (error) {
        if (!mounted) return;
        setState(() => _isBusy = false);
        _showError(error);
      },
    );
  }

  // ── Étape 2 : vérification + liaison ───────────────────────────
  Future<void> _verifyAndLink() async {
    final code = _codeController.text.trim();
    if (code.length != 6 || _verificationId == null) {
      _showError('Entrez le code à 6 chiffres reçu par SMS.');
      return;
    }
    setState(() => _isBusy = true);
    try {
      final credential = PhoneAuthProvider.credential(
        verificationId: _verificationId!,
        smsCode: code,
      );
      await _authService.linkPhoneCredential(credential);
      await _onLinked();
    } catch (e) {
      if (mounted) {
        setState(() => _isBusy = false);
        _showError(e.toString());
      }
    }
  }

  Future<void> _onLinked() async {
    // Recharger l'état pour que le gating voie le numéro désormais lié.
    await ref.read(userNotifierProvider.notifier).refresh();
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const HomeScreenApp()),
      (_) => false,
    );
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

  Future<void> _logout() async {
    // Échappatoire anti-blocage : si le numéro est déjà pris par un autre
    // compte, l'utilisateur doit pouvoir sortir de cet écran bloquant.
    await ref.read(userNotifierProvider.notifier).logout();
    if (!mounted) return;
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          title: Text(_step == _Step.enterPhone
              ? 'Votre numéro de téléphone'
              : 'Vérification'),
          actions: [
            TextButton(
              onPressed: _isBusy ? null : _logout,
              child: const Text('Se déconnecter'),
            ),
          ],
        ),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(defaultPadding),
            child: _step == _Step.enterPhone
                ? _buildPhoneStep(context)
                : _buildCodeStep(context),
          ),
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
          Text('Pour finaliser votre inscription',
              style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 8),
          Text(
            'Un numéro de téléphone est nécessaire pour vous contacter lors de '
            'vos commandes et courses. Vous recevrez un code de vérification par '
            'SMS.',
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
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _isBusy ? null : _sendCode,
              child: _isBusy
                  ? const _Spinner()
                  : const Text('Recevoir le code'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCodeStep(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: defaultPadding),
        Text('Entrez le code', style: Theme.of(context).textTheme.headlineSmall),
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
          onSubmitted: (_) => _verifyAndLink(),
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
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _isBusy ? null : _verifyAndLink,
            child: _isBusy ? const _Spinner() : const Text('Vérifier'),
          ),
        ),
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
}

class _Spinner extends StatelessWidget {
  const _Spinner();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      height: 20,
      width: 20,
      child: CircularProgressIndicator(
        strokeWidth: 2,
        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
      ),
    );
  }
}

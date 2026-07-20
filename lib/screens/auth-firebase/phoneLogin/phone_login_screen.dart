import 'package:flutter/material.dart';
import 'package:nomade_client/components/inputs/djibouti_phone.dart';
import 'package:nomade_client/services/auth_service.dart';
import 'package:nomade_client/constants.dart';
import 'package:nomade_client/screens/homeScreen/home_screen_app.dart';
import 'number_verify_screen.dart';

class PhoneLoginScreen extends StatefulWidget {
  const PhoneLoginScreen({super.key});

  @override
  State<PhoneLoginScreen> createState() => _PhoneLoginScreenState();
}

class _PhoneLoginScreenState extends State<PhoneLoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final AuthService _authService = AuthService();
  final TextEditingController _phoneController = TextEditingController();
  final FocusNode _phoneFocusNode = FocusNode();

  bool _isLoading = false;

  @override
  void dispose() {
    _phoneController.dispose();
    _phoneFocusNode.dispose();
    super.dispose();
  }

  // L'utilisateur tape seulement les chiffres locaux — on préfixe +253
  String get _fullPhoneNumber => toE164Djibouti(_phoneController.text);

  Future<void> _sendOTP() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      await _authService.signInWithPhone(
        phoneNumber: _fullPhoneNumber,
        codeSent: (verificationId) {
          if (mounted) {
            setState(() => _isLoading = false);
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => NumberVerifyScreen(
                  phoneNumber: _fullPhoneNumber,
                  verificationId: verificationId,
                ),
              ),
            );
          }
        },
        verificationCompleted: (credential) {
          if (mounted) {
            setState(() => _isLoading = false);
            Navigator.pushAndRemoveUntil(
              context,
              MaterialPageRoute(
                builder: (context) => const HomeScreenApp(),
              ),
              (_) => false,
            );
          }
        },
        verificationFailed: (error) {
          if (mounted) {
            setState(() => _isLoading = false);
            _showError(error);
          }
        },
      );
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        _showError(e.toString());
      }
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
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 16),

              // ── Titre ─────────────────────────────────────────────
              Text(
                'Votre numéro',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: theme.colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Nous enverrons un code SMS de vérification\nà votre numéro Djibouti.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  height: 1.5,
                ),
              ),

              const SizedBox(height: 32),

              // ── Champ téléphone avec préfixe 🇩🇯 +253 ─────────────
              Form(
                key: _formKey,
                child: TextFormField(
                  controller: _phoneController,
                  focusNode: _phoneFocusNode,
                  autofocus: true,
                  enabled: !_isLoading,
                  keyboardType: TextInputType.phone,
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => _sendOTP(),
                  inputFormatters: djiboutiPhoneInputFormatters(),
                  validator: validateDjiboutiPhone,
                  style: theme.textTheme.titleLarge?.copyWith(
                    letterSpacing: 2,
                    fontWeight: FontWeight.w600,
                  ),
                  decoration: InputDecoration(
                    hintText: '77 XX XX XX',
                    hintStyle: TextStyle(
                      color: theme.colorScheme.onSurfaceVariant,
                      letterSpacing: 1,
                      fontWeight: FontWeight.w400,
                      fontSize: 18,
                    ),
                    prefixIcon: const DjiboutiPrefix(),
                    prefixIconConstraints: const BoxConstraints(minWidth: 0),
                    filled: true,
                    fillColor: theme.colorScheme.surfaceContainerHigh,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(color: theme.colorScheme.outlineVariant),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(color: theme.colorScheme.outlineVariant),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide:
                          const BorderSide(color: primaryColor, width: 2),
                    ),
                    errorBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(color: accentColor),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 18,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 12),

              // ── Numéro formaté en temps réel ──────────────────────
              ValueListenableBuilder<TextEditingValue>(
                valueListenable: _phoneController,
                builder: (_, value, _) {
                  final local = value.text.replaceAll(' ', '');
                  if (local.isEmpty) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(left: 4),
                    child: Text(
                      'Numéro complet : +253 ${value.text}',
                      style: TextStyle(
                        fontSize: 12,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  );
                },
              ),

              const Spacer(),

              // ── Indicateur SMS en cours ───────────────────────────
              if (_isLoading)
                Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: primaryColor.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: primaryColor,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        'Envoi du code SMS en cours...',
                        style: TextStyle(
                          fontSize: 14,
                          color: primaryColor,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),

              // ── Bouton envoyer ────────────────────────────────────
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _sendOTP,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryColor,
                    disabledBackgroundColor: theme.colorScheme.outlineVariant,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    elevation: 0,
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text(
                          'Envoyer le code',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
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


import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:nomade_client/components/inputs/djibouti_phone.dart';
import 'package:nomade_client/constants.dart';
import 'package:nomade_client/screens/homeScreen/home_screen_app.dart';

/// Écran bloquant (pas de retour possible) demandant le numéro de téléphone
/// après une connexion Google/Apple, qui n'en fournit aucun. Le numéro est
/// nécessaire pour contacter le client lors de ses commandes/courses.
class CompletePhoneScreen extends StatefulWidget {
  const CompletePhoneScreen({super.key});

  @override
  State<CompletePhoneScreen> createState() => _CompletePhoneScreenState();
}

class _CompletePhoneScreenState extends State<CompletePhoneScreen> {
  final _formKey = GlobalKey<FormState>();
  final _phoneController = TextEditingController();
  bool _isSaving = false;

  @override
  void dispose() {
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    setState(() => _isSaving = true);
    try {
      await FirebaseFirestore.instance.collection('users').doc(uid).set(
        {'phone': toE164Djibouti(_phoneController.text)},
        SetOptions(merge: true),
      );
      if (!mounted) return;
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const HomeScreenApp()),
        (_) => false,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erreur: $e'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          title: const Text('Votre numéro de téléphone'),
        ),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(defaultPadding),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: defaultPadding),
                  Text(
                    'Pour finaliser votre inscription',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Un numéro de téléphone est nécessaire pour vous contacter '
                    'lors de vos commandes et courses.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: defaultPadding * 1.5),
                  TextFormField(
                    controller: _phoneController,
                    autofocus: true,
                    keyboardType: TextInputType.phone,
                    textInputAction: TextInputAction.done,
                    onFieldSubmitted: (_) => _save(),
                    inputFormatters: djiboutiPhoneInputFormatters(),
                    validator: validateDjiboutiPhone,
                    decoration: const InputDecoration(
                      hintText: '77 XX XX XX',
                      prefixIcon: DjiboutiPrefix(),
                      prefixIconConstraints: BoxConstraints(minWidth: 0),
                    ),
                    enabled: !_isSaving,
                  ),
                  const SizedBox(height: defaultPadding * 1.5),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _isSaving ? null : _save,
                      child: _isSaving
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            )
                          : const Text('Continuer'),
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

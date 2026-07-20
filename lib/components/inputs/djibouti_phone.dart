import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Saisie de numéro Djibouti : l'indicatif +253 est figé dans le champ et
/// l'utilisateur ne tape que les 8 chiffres locaux. Le numéro est toujours
/// stocké au format E.164 (`+253XXXXXXXX`) — voir [toE164Djibouti].
const String kDjiboutiDialCode = '+253';

/// Nombre de chiffres d'un numéro local djiboutien (ex: 77 12 34 56).
const int kDjiboutiLocalDigits = 8;

/// Formatters à appliquer à tout champ de saisie de numéro local.
List<TextInputFormatter> djiboutiPhoneInputFormatters() => [
      FilteringTextInputFormatter.digitsOnly,
      LengthLimitingTextInputFormatter(kDjiboutiLocalDigits),
      DjiboutiPhoneFormatter(),
    ];

/// Convertit la saisie locale en E.164 : "77 12 34 56" → "+25377123456".
String toE164Djibouti(String local) =>
    '$kDjiboutiDialCode${local.replaceAll(RegExp(r'\D'), '')}';

/// Extrait les chiffres locaux d'un numéro déjà stocké, quel que soit le format
/// historique ("+25377123456", "25377123456", "77 12 34 56"). Sert à pré-remplir
/// un champ à partir de Firestore.
String localDigitsFrom(String? stored) {
  var digits = (stored ?? '').replaceAll(RegExp(r'\D'), '');
  if (digits.startsWith('253')) digits = digits.substring(3);
  if (digits.length > kDjiboutiLocalDigits) {
    digits = digits.substring(digits.length - kDjiboutiLocalDigits);
  }
  return digits;
}

/// Validation d'un champ ne contenant que les chiffres locaux.
String? validateDjiboutiPhone(String? value, {bool required = true}) {
  final digits = (value ?? '').replaceAll(RegExp(r'\D'), '');
  if (digits.isEmpty) {
    return required ? 'Entrez votre numéro de téléphone' : null;
  }
  if (digits.length < kDjiboutiLocalDigits) return 'Numéro trop court';
  return null;
}

/// Préfixe visuel affiché à gauche du champ : 🇩🇯 +253 │
class DjiboutiPrefix extends StatelessWidget {
  const DjiboutiPrefix({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(left: 16),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('🇩🇯', style: TextStyle(fontSize: 22)),
          const SizedBox(width: 8),
          Text(
            kDjiboutiDialCode,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: colors.onSurface,
            ),
          ),
          const SizedBox(width: 10),
          Container(width: 1, height: 24, color: colors.outlineVariant),
          const SizedBox(width: 10),
        ],
      ),
    );
  }
}

/// Espace les chiffres deux par deux : 77123456 → 77 12 34 56.
class DjiboutiPhoneFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    final digits = newValue.text.replaceAll(' ', '');
    final buffer = StringBuffer();

    for (int i = 0; i < digits.length; i++) {
      if (i == 2 || i == 4 || i == 6) buffer.write(' ');
      buffer.write(digits[i]);
    }

    final formatted = buffer.toString();
    return newValue.copyWith(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

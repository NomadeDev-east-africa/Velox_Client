import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:nomade_client/components/inputs/djibouti_phone.dart';
import 'package:nomade_client/providers/all_providers.dart';
import 'package:nomade_client/theme/app_colors.dart';

class EditProfileScreen extends ConsumerStatefulWidget {
  const EditProfileScreen({super.key});

  @override
  ConsumerState<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends ConsumerState<EditProfileScreen> {
  final _formKey = GlobalKey<FormState>();

  late TextEditingController _nameController;
  late TextEditingController _phoneController;

  DateTime? _birthDate;
  bool _isSaving        = false;
  bool _isUploadingPhoto= false;
  late AppColors _c;
  late bool _isDark;

  @override
  void initState() {
    super.initState();
    final userState = ref.read(userNotifierProvider);
    _nameController  = TextEditingController(text: userState.displayName);
    // Le champ ne contient que les 8 chiffres locaux : l'indicatif +253 est figé
    // dans le préfixe et rajouté à la sauvegarde.
    _phoneController =
        TextEditingController(text: localDigitsFrom(userState.displayPhone));

    final bd = userState.userData?['birthDate'];
    if (bd is Timestamp) _birthDate = bd.toDate();
  }

  @override
  Widget build(BuildContext context) {
    _isDark = ref.watch(themeNotifierProvider).isDarkMode;
    _c = _isDark ? AppColors.dark : AppColors.light;
    final userState = ref.watch(userNotifierProvider);

    return Scaffold(
      backgroundColor: _c.bg,
      appBar: AppBar(
        backgroundColor: _c.bg,
        foregroundColor: _c.onSurface,
        elevation: 0,
        title: Text(
          'Modifier mon profil',
          style: TextStyle(
            color: _c.onSurface,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        leading: IconButton(
          icon: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: _c.surfaceHigh,
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.arrow_back_ios_new, color: _c.onSurface, size: 15),
          ),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          if (_isSaving)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: SizedBox(
                  width: 22, height: 22,
                  child: CircularProgressIndicator(
                    color: _c.primary, strokeWidth: 2,
                  ),
                ),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: TextButton(
                onPressed: _saveProfile,
                style: TextButton.styleFrom(
                  backgroundColor: _c.primary.withValues(alpha: 0.12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                ),
                child: Text(
                  'Sauvegarder',
                  style: TextStyle(
                    color: _c.primary,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ),
            ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          children: [
            // ── Photo de profil ─────────────────────────
            Center(
              child: GestureDetector(
                onTap: _isUploadingPhoto ? null : _pickAndUploadPhoto,
                child: Stack(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: _c.primary, width: 2.5),
                        boxShadow: [
                          BoxShadow(
                            color: _c.primary.withValues(alpha: 0.15),
                            blurRadius: 20,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: Stack(
                        children: [
                          CircleAvatar(
                            radius: 56,
                            backgroundColor: _c.surfaceHigh,
                            backgroundImage: userState.displayPhotoUrl != null
                                ? NetworkImage(userState.displayPhotoUrl!)
                                : null,
                            child: userState.displayPhotoUrl == null
                                ? Icon(Icons.person, size: 56, color: _c.primary)
                                : null,
                          ),
                          if (_isUploadingPhoto)
                            Positioned.fill(
                              child: Container(
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Colors.black.withValues(alpha: 0.55),
                                ),
                                child: Center(
                                  child: CircularProgressIndicator(
                                    color: _c.primary, strokeWidth: 2,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: Container(
                        padding: const EdgeInsets.all(9),
                        decoration: BoxDecoration(
                          color: _c.primary,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: _c.primary.withValues(alpha: 0.3),
                              blurRadius: 10,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Icon(Icons.camera_alt, size: 17, color: _c.onPrimary),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Center(
              child: Text(
                'Appuyer pour changer la photo',
                style: TextStyle(fontSize: 13, color: _c.onSurfaceVariant),
              ),
            ),

            const SizedBox(height: 32),

            // ── Email (lecture seule) ─────────────────────
            _buildReadOnlyField(
              label: 'Email',
              value: userState.email ?? 'Non disponible',
              icon: Icons.email_outlined,
              badge: userState.isEmailVerified ? 'Vérifié' : null,
            ),

            const SizedBox(height: 16),

            // ── Nom complet ──────────────────────────────
            _buildTextField(
              controller: _nameController,
              label: 'Nom complet',
              icon: Icons.person_outline,
              hint: 'Votre nom et prénom',
              validator: (v) =>
                  (v == null || v.isEmpty) ? 'Veuillez entrer votre nom' : null,
            ),

            const SizedBox(height: 16),

            // ── Téléphone ────────────────────────────────
            _buildTextField(
              controller: _phoneController,
              label: 'Numéro de téléphone',
              icon: Icons.phone_outlined,
              hint: '77 XX XX XX',
              keyboardType: TextInputType.phone,
              prefix: const DjiboutiPrefix(),
              inputFormatters: djiboutiPhoneInputFormatters(),
              validator: (v) => validateDjiboutiPhone(v, required: false),
            ),

            const SizedBox(height: 16),

            // ── Date de naissance ─────────────────────────
            _buildDateField(),

            const SizedBox(height: 28),

            // ── Info card ─────────────────────────────────
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: _c.primary.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: _c.primary.withValues(alpha: 0.18)),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: _c.primary, size: 18),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Ces informations permettent une meilleure expérience et personnalisation de vos commandes.',
                      style: TextStyle(fontSize: 13, color: _c.onSurfaceVariant),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 32),

            // ── Bouton sauvegarder ─────────────────────────
            SizedBox(
              height: 54,
              child: ElevatedButton(
                onPressed: _isSaving ? null : _saveProfile,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _c.primary,
                  disabledBackgroundColor: _c.primary.withValues(alpha: 0.4),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  elevation: 0,
                ),
                child: _isSaving
                    ? SizedBox(
                        width: 22, height: 22,
                        child: CircularProgressIndicator(
                          color: _c.onPrimary, strokeWidth: 2,
                        ),
                      )
                    : Text(
                        'Sauvegarder les modifications',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: _c.onPrimary,
                        ),
                      ),
              ),
            ),

            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  // ── Widgets ──────────────────────────────────────────────────

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    required String hint,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
    Widget? prefix,
    List<TextInputFormatter>? inputFormatters,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: _c.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: controller,
          keyboardType: keyboardType,
          inputFormatters: inputFormatters,
          style: TextStyle(color: _c.onSurface, fontSize: 15),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(color: _c.outlineVariant, fontSize: 14),
            prefixIcon: prefix ?? Icon(icon, color: _c.primary, size: 20),
            prefixIconConstraints:
                prefix != null ? const BoxConstraints(minWidth: 0) : null,
            filled: true,
            fillColor: _c.surfaceLow,
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: _c.outlineVariant),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: _c.outlineVariant),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: _c.primary, width: 1.5),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: Colors.redAccent),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: Colors.redAccent, width: 1.5),
            ),
          ),
          validator: validator,
        ),
      ],
    );
  }

  Widget _buildReadOnlyField({
    required String label,
    required String value,
    required IconData icon,
    String? badge,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: _c.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
          decoration: BoxDecoration(
            color: _c.surfaceHigh,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _c.outlineVariant.withValues(alpha: 0.5)),
          ),
          child: Row(
            children: [
              Icon(icon, color: _c.onSurfaceVariant, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  value,
                  style: TextStyle(fontSize: 15, color: _c.onSurfaceVariant),
                ),
              ),
              if (badge != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF4CAF50).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    'Vérifié',
                    style: TextStyle(
                      fontSize: 12,
                      color: Color(0xFF4CAF50),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDateField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Date de naissance',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: _c.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        InkWell(
          onTap: _selectBirthDate,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            decoration: BoxDecoration(
              color: _c.surfaceLow,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: _c.outlineVariant),
            ),
            child: Row(
              children: [
                Icon(Icons.cake_outlined, color: _c.primary, size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _birthDate != null
                        ? DateFormat('dd/MM/yyyy').format(_birthDate!)
                        : 'Sélectionner une date',
                    style: TextStyle(
                      fontSize: 15,
                      color: _birthDate != null ? _c.onSurface : _c.outlineVariant,
                    ),
                  ),
                ),
                Icon(Icons.calendar_today_outlined, color: _c.onSurfaceVariant, size: 18),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ── Actions ──────────────────────────────────────────────────

  Future<void> _selectBirthDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _birthDate ?? DateTime(2000),
      firstDate: DateTime(1950),
      lastDate: DateTime.now(),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: _isDark
              ? ColorScheme.dark(primary: _c.primary, onPrimary: _c.onPrimary, surface: _c.surfaceLow, onSurface: _c.onSurface)
              : ColorScheme.fromSeed(seedColor: _c.primary),
        ),
        child: child!,
      ),
    );
    if (picked != null && picked != _birthDate) {
      setState(() => _birthDate = picked);
    }
  }

  Future<void> _pickAndUploadPhoto() async {
    final picker = ImagePicker();
    final c = _c;
    showModalBottomSheet(
      context: context,
      backgroundColor: c.surfaceLow,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40, height: 4,
                decoration: BoxDecoration(
                  color: c.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Changer la photo',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                  color: c.onSurface,
                ),
              ),
              const SizedBox(height: 16),
              _sourceOption(
                ctx: ctx,
                icon: Icons.photo_camera,
                label: 'Prendre une photo',
                source: ImageSource.camera,
                picker: picker,
              ),
              _sourceOption(
                ctx: ctx,
                icon: Icons.photo_library,
                label: 'Choisir depuis la galerie',
                source: ImageSource.gallery,
                picker: picker,
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sourceOption({
    required BuildContext ctx,
    required IconData icon,
    required String label,
    required ImageSource source,
    required ImagePicker picker,
  }) {
    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: _c.primary.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: _c.primary),
      ),
      title: Text(
        label,
        style: TextStyle(color: _c.onSurface, fontWeight: FontWeight.w600),
      ),
      onTap: () async {
        Navigator.pop(ctx);
        final XFile? image = await picker.pickImage(source: source, imageQuality: 80);
        if (image != null && mounted) await _doUpload(image);
      },
    );
  }

  Future<void> _doUpload(XFile image) async {
    setState(() => _isUploadingPhoto = true);
    try {
      await ref.read(userNotifierProvider.notifier).uploadProfilePhoto(image);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Photo mise à jour avec succès'),
            backgroundColor: Color(0xFF4CAF50),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erreur upload: $e'),
            backgroundColor: Colors.redAccent,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isUploadingPhoto = false);
    }
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);

    try {
      final localDigits = _phoneController.text.replaceAll(RegExp(r'\D'), '');
      await ref.read(userNotifierProvider.notifier).updateProfile(
        name: _nameController.text.trim(),
        phone: localDigits.isEmpty ? null : toE164Djibouti(localDigits),
        birthDate: _birthDate,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Profil mis à jour avec succès'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Color(0xFF4CAF50),
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erreur: $e'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }
}

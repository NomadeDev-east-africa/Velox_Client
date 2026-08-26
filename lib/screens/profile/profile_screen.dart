import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:nomade_client/providers/all_providers.dart';
import 'package:nomade_client/theme/app_colors.dart';
import 'package:nomade_client/translations/app_translations.dart';

// Screens
import 'edit_profile_screen.dart';
import 'adresses/add_address_screen.dart';
import 'adresses/my_addresses_screen.dart';
import '../history/order_history_screen.dart';
import '../notifications/notifications_screen.dart';
import '../food/favorites/favorite_restaurants_screen.dart';
import 'support/support_screen.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  bool _isUploading = false;
  late AppColors _c;

  @override
  Widget build(BuildContext context) {
    final themeState = ref.watch(themeNotifierProvider);
    _c = themeState.isDarkMode ? AppColors.dark : AppColors.light;
    final langState  = ref.watch(languageNotifierProvider);
    final userState  = ref.watch(userNotifierProvider);

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          _buildHeaderSliver(themeState, userState),
          SliverToBoxAdapter(
            child: Column(
              children: [
                const SizedBox(height: 24),
                _buildSection(
                  themeState: themeState,
                  title: tr('appearance_personalization'),
                  icon: Icons.palette,
                  children: [
                    _buildDarkModeToggle(themeState),
                    _buildLanguageSelector(langState),
                  ],
                ),
                const SizedBox(height: 16),
                _buildSection(
                  themeState: themeState,
                  title: tr('personal_info'),
                  icon: Icons.person,
                  children: [
                    _buildMenuItem(
                      themeState: themeState,
                      icon: Icons.edit,
                      title: tr('edit_profile'),
                      subtitle: tr('edit_profile_sub'),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const EditProfileScreen(),
                          ),
                        );
                      },
                    ),
                    _buildMenuItem(
                      themeState: themeState,
                      icon: Icons.email,
                      title: userState.email ?? tr('email_not_available'),
                      subtitle: tr('email_address'),
                      trailing: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.green.shade50,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          tr('verified'),
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.green.shade700,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _buildSection(
                  themeState: themeState,
                  title: tr('my_addresses'),
                  icon: Icons.location_on,
                  children: [
                    _buildMenuItem(
                      themeState: themeState,
                      icon: Icons.home,
                      title: tr('manage_addresses'),
                      subtitle: tr('address_types'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const MyAddressesScreen(),
                          ),
                        );
                      },
                    ),
                    _buildMenuItem(
                      themeState: themeState,
                      icon: Icons.add_location_alt,
                      title: tr('add_address'),
                      subtitle: tr('new_address'),
                      trailing: const Icon(Icons.chevron_right),
                      color: const Color(0xFFCE1126), // rouge
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const AddAddressScreen(),
                          ),
                        );
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _buildNotificationsSection(themeState),
                const SizedBox(height: 16),
                _buildSection(
                  themeState: themeState,
                  title: tr('history_favorites'),
                  icon: Icons.history,
                  children: [
                    _buildMenuItem(
                      themeState: themeState,
                      icon: Icons.notifications_none,
                      title: 'Mes notifications',
                      subtitle: 'Promotions et suivi',
                      trailing: _notificationsTrailing(),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const NotificationsScreen(),
                        ),
                      ),
                    ),
                    _buildMenuItem(
                      themeState: themeState,
                      icon: Icons.receipt_long,
                      title: tr('my_orders'),
                      subtitle: tr('full_history'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const OrderHistoryScreen(),
                        ),
                      ),
                    ),
                    _buildMenuItem(
                      themeState: themeState,
                      icon: Icons.favorite,
                      title: tr('favorite_restaurants'),
                      subtitle: '${ref.watch(favoritesNotifierProvider).length} ${tr('restaurants').toLowerCase()}',
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const FavoriteRestaurantsScreen(),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _buildSection(
                  themeState: themeState,
                  title: tr('support_legal'),
                  icon: Icons.help_outline,
                  children: [
                    _buildMenuItem(
                      themeState: themeState,
                      icon: Icons.help_center,
                      title: tr('help_center'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const SupportScreen(),
                        ),
                      ),
                    ),
                    _buildMenuItem(
                      themeState: themeState,
                      icon: Icons.info,
                      title: tr('about_app'),
                      subtitle: 'veloxdj.com',
                      trailing: const Icon(Icons.open_in_new, size: 18),
                      onTap: _openWebsite,
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _buildSection(
                  themeState: themeState,
                  title: tr('account'),
                  icon: Icons.security,
                  children: [
                    _buildMenuItem(
                      themeState: themeState,
                      icon: Icons.logout,
                      title: tr('logout'),
                      color: Colors.orange,
                      onTap: () => _showLogoutDialog(themeState),
                    ),
                    _buildMenuItem(
                      themeState: themeState,
                      icon: Icons.delete_forever,
                      title: tr('delete_account'),
                      color: const Color(0xFFCE1126), // rouge
                      onTap: () => _showDeleteAccountDialog(themeState),
                    ),
                  ],
                ),
                const SizedBox(height: 32),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderSliver(ThemeState themeState, UserState userState) {
    return SliverAppBar(
      expandedHeight: 280,
      floating: false,
      pinned: true,
      backgroundColor: _c.bg,
      flexibleSpace: FlexibleSpaceBar(
        background: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [_c.bg, _c.surfaceLow],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
          child: SafeArea(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(height: 40),
                Stack(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: _c.primary,
                          width: 3,
                        ),
                      ),
                      child: Stack(
                        children: [
                          CircleAvatar(
                            radius: 50,
                            backgroundColor: _c.surfaceHigh,
                            backgroundImage: userState.displayPhotoUrl != null
                                ? NetworkImage(userState.displayPhotoUrl!)
                                : null,
                            child: userState.displayPhotoUrl == null
                                ? Icon(Icons.person, size: 50, color: _c.primary)
                                : null,
                          ),
                          if (_isUploading)
                            Positioned.fill(
                              child: Container(
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Colors.black.withValues(alpha: 0.5),
                                ),
                                child: Center(
                                  child: CircularProgressIndicator(
                                    color: _c.primary,
                                    strokeWidth: 2,
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
                      child: GestureDetector(
                        onTap: _isUploading ? null : _pickImage,
                        child: Container(
                          padding: const EdgeInsets.all(8),
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
                          child: Icon(
                            Icons.camera_alt,
                            size: 18,
                            color: _c.onPrimary,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  userState.displayName,
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: _c.onSurface,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  userState.email ?? '',
                  style: TextStyle(
                    fontSize: 13,
                    color: _c.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSection({
    required ThemeState themeState,
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: _c.primary, size: 20),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: themeState.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Card(
            color: themeState.cardColor,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            elevation: 2,
            child: Column(children: children),
          ),
        ],
      ),
    );
  }

  /// Pastille de non-lus à droite de l'entrée « Mes notifications ».
  /// Rien ne s'affiche à zéro : une pastille vide serait du bruit.
  Widget _notificationsTrailing() {
    final unread = ref.watch(unreadNotificationsCountProvider);
    if (unread == 0) return const Icon(Icons.chevron_right, size: 20);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: _c.primary,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            unread > 99 ? '99+' : '$unread',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: _c.onPrimary,
            ),
          ),
        ),
        const SizedBox(width: 4),
        const Icon(Icons.chevron_right, size: 20),
      ],
    );
  }

  Widget _buildMenuItem({
    required ThemeState themeState,
    required IconData icon,
    required String title,
    String? subtitle,
    Widget? trailing,
    Color? color,
    VoidCallback? onTap,
  }) {
    return ListTile(
      onTap: onTap,
      leading: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: (color ?? _c.primary).withValues(alpha:0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(
          icon,
          color: color ?? _c.primary,
          size: 22,
        ),
      ),
      title: Text(
        title,
        style: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          color: color ?? themeState.textPrimary,
        ),
      ),
      subtitle: subtitle != null
          ? Text(
        subtitle,
        style: TextStyle(fontSize: 13, color: themeState.textSecondary),
      )
          : null,
      trailing: trailing ?? const Icon(Icons.chevron_right, size: 20),
    );
  }

  Widget _buildDarkModeToggle(ThemeState themeState) {
    return SwitchListTile(
      secondary: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: _c.primary.withValues(alpha:0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(
          themeState.isDarkMode ? Icons.dark_mode : Icons.light_mode,
          color: _c.primary,
          size: 22,
        ),
      ),
      title: Text(
        tr('dark_mode'),
        style: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          color: themeState.textPrimary,
        ),
      ),
      subtitle: Text(
        themeState.isDarkMode ? tr('enabled') : tr('disabled'),
        style: TextStyle(fontSize: 13, color: themeState.textSecondary),
      ),
      value: themeState.isDarkMode,
      activeThumbColor: _c.primary,
      onChanged: (value) => ref.read(themeNotifierProvider.notifier).toggleTheme(),
    );
  }

  Widget _buildLanguageSelector(LanguageState langState) {
    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: _c.primary.withValues(alpha:0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(
          Icons.language,
          color: _c.primary,
          size: 22,
        ),
      ),
      title: Text(
        tr('language'),
        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        langState.languageName,
        style: const TextStyle(fontSize: 13),
      ),
      trailing: const Icon(Icons.chevron_right, size: 20),
      onTap: () => _showLanguageDialog(langState),
    );
  }

  Widget _buildSwitchTile({
    required ThemeState themeState,
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return SwitchListTile(
      secondary: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: _c.primary.withValues(alpha:0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: _c.primary, size: 22),
      ),
      title: Text(
        title,
        style: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          color: themeState.textPrimary,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(fontSize: 13, color: themeState.textSecondary),
      ),
      value: value,
      activeThumbColor: _c.primary,
      onChanged: onChanged,
    );
  }

  Widget _buildNotificationsSection(ThemeState themeState) {
    final notif = ref.watch(notificationsNotifierProvider);
    final notifier = ref.read(notificationsNotifierProvider.notifier);
    return _buildSection(
      themeState: themeState,
      title: tr('notifications'),
      icon: Icons.notifications,
      children: [
        _buildSwitchTile(
          themeState: themeState,
          icon: Icons.notifications_active,
          title: tr('push_notifications'),
          subtitle: tr('receive_alerts'),
          value: notif.push,
          onChanged: notifier.setPush,
        ),
        _buildSwitchTile(
          themeState: themeState,
          icon: Icons.shopping_bag,
          title: tr('order_tracking'),
          subtitle: tr('realtime_updates'),
          value: notif.orders,
          onChanged: notifier.setOrders,
        ),
        _buildSwitchTile(
          themeState: themeState,
          icon: Icons.local_offer,
          title: tr('promotions'),
          subtitle: tr('offers_discounts'),
          value: notif.promos,
          onChanged: notifier.setPromos,
        ),
      ],
    );
  }

  Future<void> _pickImage() async {
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
              const SizedBox(height: 16),
              Text(
                tr('change_photo'),
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                  color: c.onSurface,
                ),
              ),
              const SizedBox(height: 12),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: c.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.photo_camera, color: c.primary),
                ),
                title: Text(tr('take_photo'),
                    style: TextStyle(color: c.onSurface, fontWeight: FontWeight.w600)),
                onTap: () async {
                  Navigator.pop(ctx);
                  final XFile? image = await picker.pickImage(
                      source: ImageSource.camera, imageQuality: 80);
                  if (image != null && mounted) await _uploadPhoto(image);
                },
              ),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: c.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.photo_library, color: c.primary),
                ),
                title: Text(tr('choose_from_gallery'),
                    style: TextStyle(color: c.onSurface, fontWeight: FontWeight.w600)),
                onTap: () async {
                  Navigator.pop(ctx);
                  final XFile? image = await picker.pickImage(
                      source: ImageSource.gallery, imageQuality: 80);
                  if (image != null && mounted) await _uploadPhoto(image);
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _uploadPhoto(XFile image) async {
    setState(() => _isUploading = true);
    try {
      await ref.read(userNotifierProvider.notifier).uploadProfilePhoto(image);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(tr('photo_updated')),
            backgroundColor: const Color(0xFF4CAF50),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erreur: $e'),
            backgroundColor: Colors.redAccent,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  Future<void> _openWebsite() async {
    final uri = Uri.parse('https://veloxdj.com');
    // launchUrl peut lever (PlatformException) si aucun handler n'existe, pas
    // seulement renvoyer false — on couvre les deux cas.
    bool launched = false;
    try {
      launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      launched = false;
    }
    if (!launched && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Impossible d\'ouvrir le site veloxdj.com'),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _showLanguageDialog(LanguageState langState) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr('choose_language')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _languageOption(langState, 'FR', 'Français'),
            _languageOption(langState, 'EN', 'English'),
            _languageOption(langState, 'SO', 'Somali'),
            _languageOption(langState, 'AR', 'العربية'),
            _languageOption(langState, 'AA', 'Afar'),
          ],
        ),
      ),
    );
  }

  Widget _languageOption(LanguageState langState, String code, String name) {
    final isSelected = langState.language == code;
    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: isSelected
              ? _c.primary.withValues(alpha: 0.15)
              : _c.surface,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          code,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: isSelected ? _c.primary : _c.onSurfaceVariant,
          ),
        ),
      ),
      title: Text(name),
      trailing: isSelected
          ? Icon(Icons.check_circle, color: _c.primary)
          : null,
      onTap: () {
        ref.read(languageNotifierProvider.notifier).setLanguage(code);
        Navigator.pop(context);
      },
    );
  }

  void _showLogoutDialog(ThemeState themeState) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: themeState.cardColor,
        title: Text(tr('logout'),
            style: TextStyle(color: themeState.textPrimary)),
        content: Text(
          tr('logout_confirm'),
          style: TextStyle(color: themeState.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(tr('cancel')),
          ),
          ElevatedButton(
            onPressed: () async {
              final navigator = Navigator.of(context);
              await ref.read(userNotifierProvider.notifier).logout();
              if (!mounted) return;
              navigator.pushNamedAndRemoveUntil('/', (_) => false);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
            child: Text(tr('logout_action')),
          ),
        ],
      ),
    );
  }

  void _showDeleteAccountDialog(ThemeState themeState) {
    final confirmController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocalState) => AlertDialog(
          backgroundColor: themeState.cardColor,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          title: Row(
            children: [
              const Icon(Icons.warning_amber_rounded, color: Color(0xFFCE1126)),
              const SizedBox(width: 8),
              Text(
                tr('delete_account_title'),
                style: TextStyle(color: themeState.textPrimary, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                tr('delete_account_warning'),
                style: TextStyle(color: themeState.textSecondary, fontSize: 13),
              ),
              const SizedBox(height: 16),
              Text(
                tr('type_delete_confirm'),
                style: TextStyle(
                  color: themeState.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: confirmController,
                onChanged: (_) => setLocalState(() {}),
                decoration: InputDecoration(
                  hintText: tr('delete_keyword'),
                  hintStyle: TextStyle(color: _c.onSurfaceVariant),
                  filled: true,
                  fillColor: _c.surfaceHigh,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none,
                  ),
                ),
                style: TextStyle(color: _c.onSurface),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                confirmController.dispose();
                Navigator.pop(ctx);
              },
              child: Text(tr('cancel'), style: TextStyle(color: _c.onSurfaceVariant)),
            ),
            ElevatedButton(
              onPressed: confirmController.text == tr('delete_keyword')
                  ? () async {
                      final navigator = Navigator.of(context);
                      Navigator.pop(ctx);
                      try {
                        await ref
                            .read(userNotifierProvider.notifier)
                            .deleteAccount();
                        if (!mounted) return;
                        navigator.pushNamedAndRemoveUntil('/', (_) => false);
                      } catch (e) {
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Erreur : $e'),
                            backgroundColor: Colors.redAccent,
                          ),
                        );
                      }
                    }
                  : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFCE1126),
                disabledBackgroundColor: _c.surfaceHigh,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: Text(tr('delete'), style: const TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'login.dart';

// ================================================================
// DESIGN TOKENS
// ================================================================

class _C {
  static const background = Color(0xFFF8FAFC);
  static const surface = Colors.white;
  static const border = Color(0xFFE2E8F0);

  static const textPrimary = Color(0xFF0F172A);
  static const textSecondary = Color(0xFF64748B);
  static const textMuted = Color(0xFF94A3B8);

  static const primary = Color(0xFF2563EB);
  static const primarySoft = Color(0xFFEFF6FF);

  static const success = Color(0xFF15803D);
  static const successSoft = Color(0xFFF0FDF4);

  static const danger = Color(0xFFDC2626);
  static const dangerSoft = Color(0xFFFEF2F2);
}

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final SupabaseClient _supabase = Supabase.instance.client;

  bool _isLoading = true;
  String _name = 'Pengguna';
  String _email = '-';
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  // ============================================================
  // LOAD PROFILE FROM SUPABASE
  // ============================================================

  Future<void> _loadProfile() async {
    final user = _supabase.auth.currentUser;

    if (user == null) {
      if (!mounted) return;

      setState(() {
        _name = 'Pengguna';
        _email = '-';
        _isLoading = false;
      });

      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final response = await _supabase
          .from('profiles')
          .select()
          .eq('id', user.id)
          .maybeSingle();

      final data = response ?? <String, dynamic>{};

      final name = (data['name'] ??
              user.userMetadata?['name'] ??
              user.userMetadata?['full_name'] ??
              'Pengguna')
          .toString()
          .trim();

      final email =
          (data['email'] ?? user.email ?? '-').toString().trim();

      if (!mounted) return;

      setState(() {
        _name = name.isEmpty ? 'Pengguna' : name;
        _email = email.isEmpty ? '-' : email;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _name = (user.userMetadata?['name'] ??
                user.userMetadata?['full_name'] ??
                'Pengguna')
            .toString()
            .trim();

        if (_name.isEmpty) {
          _name = 'Pengguna';
        }

        _email = user.email ?? '-';
        _errorMessage = 'Data profil belum dapat dimuat dari Supabase.';
        _isLoading = false;
      });
    }
  }

  // ============================================================
  // LOGOUT
  // ============================================================

  Future<void> _logout(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: _C.surface,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          contentPadding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
          actionsPadding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: const BoxDecoration(
                  color: _C.dangerSoft,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.logout_rounded,
                  color: _C.danger,
                  size: 24,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Keluar dari akun?',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: _C.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Anda harus masuk kembali untuk mengakses akun ini.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  height: 1.45,
                  color: _C.textSecondary,
                ),
              ),
            ],
          ),
          actions: [
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(dialogContext, false),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _C.textPrimary,
                      side: const BorderSide(color: _C.border),
                      minimumSize: const Size.fromHeight(46),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      'Batal',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(dialogContext, true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _C.danger,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      minimumSize: const Size.fromHeight(46),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      'Keluar',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );

    if (confirmed != true || !context.mounted) return;

    try {
      await _supabase.auth.signOut();

      if (!context.mounted) return;

      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginPage()),
        (route) => false,
      );
    } catch (e) {
      if (!context.mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Gagal keluar dari akun: $e'),
          backgroundColor: _C.danger,
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
    }
  }

  // ============================================================
  // APP BAR
  // ============================================================

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: _C.surface,
      surfaceTintColor: Colors.transparent,
      foregroundColor: _C.textPrimary,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: true,
      title: const Text(
        'Profil',
        style: TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w700,
          color: _C.textPrimary,
        ),
      ),
      bottom: const PreferredSize(
        preferredSize: Size.fromHeight(1),
        child: Divider(height: 1, thickness: 1, color: _C.border),
      ),
    );
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    final user = _supabase.auth.currentUser;

    if (user == null) {
      return Scaffold(
        backgroundColor: _C.background,
        appBar: _buildAppBar(),
        body: const Center(
          child: Text(
            'Pengguna belum login.',
            style: TextStyle(color: _C.textSecondary),
          ),
        ),
      );
    }

    if (_isLoading) {
      return Scaffold(
        backgroundColor: _C.background,
        appBar: _buildAppBar(),
        body: const Center(
          child: CircularProgressIndicator(
            color: _C.primary,
          ),
        ),
      );
    }

    final displayName = _name.trim().isEmpty ? 'Pengguna' : _name.trim();
    final displayEmail = _email.trim().isEmpty ? '-' : _email.trim();
    final initial = displayName.substring(0, 1).toUpperCase();

    return Scaffold(
      backgroundColor: _C.background,
      appBar: _buildAppBar(),
      body: SafeArea(
        top: false,
        child: RefreshIndicator(
          color: _C.primary,
          onRefresh: _loadProfile,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 28, 20, 24),
            children: [
              // ==================================================
              // HEADER PROFIL
              // ==================================================

              _ProfileHeader(
                initial: initial,
                name: displayName,
                email: displayEmail,
              ),

              const SizedBox(height: 28),

              // ==================================================
              // INFORMASI AKUN
              // ==================================================

              Container(
                decoration: BoxDecoration(
                  color: _C.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: _C.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.fromLTRB(18, 16, 18, 4),
                      child: Text(
                        'Informasi akun',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: _C.textPrimary,
                        ),
                      ),
                    ),
                    _ProfileRow(
                      icon: Icons.person_outline_rounded,
                      label: 'Nama',
                      value: displayName,
                    ),
                    const _RowDivider(),
                    _ProfileRow(
                      icon: Icons.mail_outline_rounded,
                      label: 'Email',
                      value: displayEmail,
                    ),
                  ],
                ),
              ),

              if (_errorMessage != null) ...[
                const SizedBox(height: 10),
                Text(
                  _errorMessage!,
                  style: const TextStyle(
                    fontSize: 12,
                    color: _C.danger,
                  ),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: _loadProfile,
                    child: const Text('Muat ulang profil'),
                  ),
                ),
              ],

              const SizedBox(height: 16),

              // ==================================================
              // TOMBOL LOGOUT
              // ==================================================

              SizedBox(
                height: 52,
                child: OutlinedButton.icon(
                  onPressed: () => _logout(context),
                  icon: const Icon(Icons.logout_rounded, size: 20),
                  label: const Text(
                    'Keluar dari akun',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _C.danger,
                    backgroundColor: _C.surface,
                    side: const BorderSide(color: Color(0xFFFECACA)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 24),

              // ==================================================
              // FOOTER APLIKASI
              // ==================================================

              const _AppFooter(),
            ],
          ),
        ),
      ),
    );
  }
}

// ================================================================
// PROFILE HEADER
// ================================================================

class _ProfileHeader extends StatelessWidget {
  final String initial;
  final String name;
  final String email;

  const _ProfileHeader({
    required this.initial,
    required this.name,
    required this.email,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 96,
          height: 96,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF3B82F6), Color(0xFF1D4ED8)],
            ),
            border: Border.all(color: _C.surface, width: 4),
            boxShadow: [
              BoxShadow(
                color: _C.primary.withValues(alpha: 0.22),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          alignment: Alignment.center,
          child: Text(
            initial,
            style: const TextStyle(
              fontSize: 38,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          name,
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            color: _C.textPrimary,
            letterSpacing: -0.2,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          email,
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 14,
            color: _C.textSecondary,
          ),
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: _C.successSoft,
            borderRadius: BorderRadius.circular(20),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.circle, size: 8, color: _C.success),
              SizedBox(width: 7),
              Text(
                'Akun aktif',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: _C.success,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ================================================================
// PROFILE ROW
// ================================================================

class _ProfileRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _ProfileRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: _C.primarySoft,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, size: 20, color: _C.primary),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 12,
                    color: _C.textMuted,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w600,
                    color: _C.textPrimary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RowDivider extends StatelessWidget {
  const _RowDivider();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.only(left: 72),
      child: Divider(height: 1, thickness: 1, color: _C.border),
    );
  }
}

// ================================================================
// APP FOOTER
// ================================================================

class _AppFooter extends StatelessWidget {
  const _AppFooter();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Text(
        'by TumbasCoding  •  Versi 1.0.0',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: _C.textMuted,
        ),
      ),
    );
  }
}


import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'login.dart';

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
  bool _isOwner = false;
  bool _isActive = false;
  bool _creatingEmployee = false;

  String _name = 'Pengguna';
  String _email = '-';
  String _role = 'Tidak diketahui';
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final user = _supabase.auth.currentUser;

    if (user == null) {
      if (!mounted) return;

      setState(() {
        _name = 'Pengguna';
        _email = '-';
        _role = 'Tidak diketahui';
        _isOwner = false;
        _isActive = false;
        _isLoading = false;
        _errorMessage = 'Silakan login kembali.';
      });
      return;
    }

    if (mounted) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    }

    try {
      final data = await _supabase
          .from('profiles')
          .select('id, full_name, role, is_active')
          .eq('id', user.id)
          .maybeSingle();

      if (!mounted) return;

      if (data == null) {
        setState(() {
          _name = user.userMetadata?['full_name']?.toString() ??
              user.userMetadata?['name']?.toString() ??
              'Pengguna';
          _email = user.email ?? '-';
          _role = 'Tidak diketahui';
          _isOwner = false;
          _isActive = false;
          _isLoading = false;
          _errorMessage =
              'Profil akun tidak ditemukan di tabel profiles.';
        });
        return;
      }

      final name = (data['full_name'] ??
              user.userMetadata?['full_name'] ??
              user.userMetadata?['name'] ??
              'Pengguna')
          .toString()
          .trim();

      final role =
          (data['role'] ?? '').toString().trim().toLowerCase();

      final isActive = data['is_active'] == true;

      setState(() {
        _name = name.isEmpty ? 'Pengguna' : name;
        _email = user.email ?? '-';
        _role = role;
        _isOwner = role == 'owner';
        _isActive = isActive;
        _isLoading = false;

        if (!isActive) {
          _errorMessage =
              'Akun ini tidak aktif. Hubungi administrator.';
        } else if (role != 'owner' && role != 'kasir') {
          _errorMessage =
              'Role akun tidak valid. Periksa kolom role di Supabase.';
        }
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _name = user.userMetadata?['full_name']?.toString() ??
            user.userMetadata?['name']?.toString() ??
            'Pengguna';
        _email = user.email ?? '-';
        _role = 'Tidak diketahui';
        _isOwner = false;
        _isActive = false;
        _isLoading = false;
        _errorMessage = 'Gagal memuat profil: $e';
      });
    }
  }

  Future<void> _showCreateEmployeeDialog() async {
    if (!_isOwner || !_isActive || _creatingEmployee) return;

    final result = await showDialog<_EmployeeFormData>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _CreateEmployeeDialog(),
    );

    if (!mounted || result == null) return;

    await _createEmployee(
      name: result.name,
      email: result.email,
      password: result.password,
    );
  }

  Future<void> _createEmployee({
    required String name,
    required String email,
    required String password,
  }) async {
    if (!_isOwner || !_isActive) {
      _showMessage(
        'Hanya Owner aktif yang dapat membuat akun karyawan.',
        error: true,
      );
      return;
    }

    if (_creatingEmployee) return;

    setState(() => _creatingEmployee = true);

    try {
      final response = await _supabase.functions.invoke(
        'create-employee',
        body: {
          'name': name,
          'email': email,
          'password': password,
        },
      );

      if (response.status < 200 || response.status >= 300) {
        throw Exception(
          'Permintaan gagal dengan status ${response.status}.',
        );
      }

      if (!mounted) return;

      _showMessage('Akun karyawan berhasil dibuat.');
    } on FunctionException catch (e) {
      if (!mounted) return;

      final details = e.details?.toString() ?? '';

      _showMessage(
        details.isNotEmpty
            ? 'Gagal membuat akun: $details'
            : 'Gagal membuat akun. Periksa Edge Function create-employee.',
        error: true,
      );
    } catch (e) {
      if (!mounted) return;

      _showMessage(
        'Gagal membuat akun karyawan: $e',
        error: true,
      );
    } finally {
      if (mounted) {
        setState(() => _creatingEmployee = false);
      }
    }
  }

  InputDecoration _inputDecoration(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, color: _C.textSecondary),
      filled: true,
      fillColor: _C.background,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _C.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _C.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(
          color: _C.primary,
          width: 1.5,
        ),
      ),
    );
  }

  void _showMessage(String message, {bool error = false}) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? _C.danger : _C.success,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  Future<void> _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: _C.surface,
          title: const Text('Keluar dari akun?'),
          content: const Text(
            'Anda harus masuk kembali untuk mengakses akun ini.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Batal'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: _C.danger,
              ),
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Keluar'),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !mounted) return;

    try {
      await _supabase.auth.signOut();

      if (!mounted) return;

      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (_) => const LoginPage(),
        ),
        (route) => false,
      );
    } catch (e) {
      _showMessage('Gagal keluar dari akun: $e', error: true);
    }
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      centerTitle: true,
      title: const Text(
        'Profil',
        style: TextStyle(
          color: _C.textPrimary,
          fontSize: 17,
          fontWeight: FontWeight.w700,
        ),
      ),
      bottom: const PreferredSize(
        preferredSize: Size.fromHeight(1),
        child: Divider(height: 1, color: _C.border),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = _supabase.auth.currentUser;

    if (user == null) {
      return Scaffold(
        backgroundColor: _C.background,
        appBar: _buildAppBar(),
        body: const Center(
          child: Text('Pengguna belum login.'),
        ),
      );
    }

    if (_isLoading) {
      return Scaffold(
        backgroundColor: _C.background,
        appBar: _buildAppBar(),
        body: const Center(
          child: CircularProgressIndicator(color: _C.primary),
        ),
      );
    }

    final displayName =
        _name.trim().isEmpty ? 'Pengguna' : _name.trim();
    final displayEmail =
        _email.trim().isEmpty ? '-' : _email.trim();
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
              _ProfileHeader(
                initial: initial,
                name: displayName,
                email: displayEmail,
                role: _role,
              ),
              const SizedBox(height: 28),
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
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
                    const _RowDivider(),
                    _ProfileRow(
                      icon: Icons.verified_user_outlined,
                      label: 'Peran',
                      value: _role == 'owner'
                          ? 'Owner'
                          : _role == 'kasir'
                              ? 'Kasir'
                              : _role,
                    ),
                  ],
                ),
              ),
              if (_errorMessage != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _C.dangerSoft,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    _errorMessage!,
                    style: const TextStyle(
                      color: _C.danger,
                      fontSize: 12,
                      height: 1.5,
                    ),
                  ),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: _loadProfile,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Muat ulang profil'),
                  ),
                ),
              ],
              if (_isOwner && _isActive) ...[
                const SizedBox(height: 20),
                const Text(
                  'Manajemen karyawan',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: _C.textPrimary,
                  ),
                ),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: _C.border),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(
                            Icons.group_add_outlined,
                            size: 26,
                            color: _C.primary,
                          ),
                          SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Buat akun karyawan',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                color: _C.textPrimary,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Buat akun untuk karyawan yang bertugas sebagai '
                        'kasir. Akun Kasir tidak mendapatkan menu '
                        'Produk dan Laporan.',
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.5,
                          color: _C.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 14),
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: FilledButton.icon(
                          onPressed: _creatingEmployee
                              ? null
                              : _showCreateEmployeeDialog,
                          icon: _creatingEmployee
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.person_add_alt_1),
                          label: Text(
                            _creatingEmployee
                                ? 'Membuat akun...'
                                : 'Tambah Karyawan',
                          ),
                          style: FilledButton.styleFrom(
                            backgroundColor: _C.primary,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 20),
              SizedBox(
                height: 52,
                child: OutlinedButton.icon(
                  onPressed: _logout,
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
                    backgroundColor: Colors.white,
                    side: const BorderSide(color: Color(0xFFFECACA)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              const _AppFooter(),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmployeeFormData {
  final String name;
  final String email;
  final String password;

  const _EmployeeFormData({
    required this.name,
    required this.email,
    required this.password,
  });
}

class _CreateEmployeeDialog extends StatefulWidget {
  const _CreateEmployeeDialog();

  @override
  State<_CreateEmployeeDialog> createState() =>
      _CreateEmployeeDialogState();
}

class _CreateEmployeeDialogState
    extends State<_CreateEmployeeDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();

  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  bool _submitting = false;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  InputDecoration _inputDecoration(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, color: _C.textSecondary),
      filled: true,
      fillColor: _C.background,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _C.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _C.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(
          color: _C.primary,
          width: 1.5,
        ),
      ),
    );
  }

  void _submit() {
    if (_submitting) return;

    if (!_formKey.currentState!.validate()) return;

    setState(() => _submitting = true);

    final result = _EmployeeFormData(
      name: _nameController.text.trim(),
      email: _emailController.text.trim(),
      password: _passwordController.text,
    );

    Navigator.of(context).pop(result);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: _C.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      title: const Text(
        'Buat Akun Karyawan',
        style: TextStyle(
          fontWeight: FontWeight.w700,
          color: _C.textPrimary,
        ),
      ),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Akun baru akan memiliki akses sebagai Kasir.',
                  style: TextStyle(
                    fontSize: 13,
                    color: _C.textSecondary,
                  ),
                ),
              ),
              const SizedBox(height: 18),
              TextFormField(
                controller: _nameController,
                textCapitalization: TextCapitalization.words,
                decoration: _inputDecoration(
                  'Nama karyawan',
                  Icons.person_outline,
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Nama wajib diisi';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                autocorrect: false,
                decoration: _inputDecoration(
                  'Email karyawan',
                  Icons.email_outlined,
                ),
                validator: (value) {
                  final email = value?.trim() ?? '';

                  if (!RegExp(
                    r'^[^@\s]+@[^@\s]+\.[^@\s]+$',
                  ).hasMatch(email)) {
                    return 'Masukkan email yang valid';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _passwordController,
                obscureText: _obscurePassword,
                decoration: _inputDecoration(
                  'Kata sandi (minimal 8 karakter)',
                  Icons.lock_outline,
                ).copyWith(
                  suffixIcon: IconButton(
                    onPressed: () {
                      setState(() {
                        _obscurePassword = !_obscurePassword;
                      });
                    },
                    icon: Icon(
                      _obscurePassword
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                    ),
                  ),
                ),
                validator: (value) {
                  if (value == null || value.length < 8) {
                    return 'Kata sandi minimal 8 karakter';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _confirmController,
                obscureText: _obscureConfirm,
                decoration: _inputDecoration(
                  'Konfirmasi kata sandi',
                  Icons.lock_reset_outlined,
                ).copyWith(
                  suffixIcon: IconButton(
                    onPressed: () {
                      setState(() {
                        _obscureConfirm = !_obscureConfirm;
                      });
                    },
                    icon: Icon(
                      _obscureConfirm
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                    ),
                  ),
                ),
                validator: (value) {
                  if (value != _passwordController.text) {
                    return 'Konfirmasi kata sandi tidak sama';
                  }
                  return null;
                },
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _submitting
              ? null
              : () => Navigator.of(context).pop(),
          child: const Text('Batal'),
        ),
        FilledButton(
          onPressed: _submitting ? null : _submit,
          style: FilledButton.styleFrom(
            backgroundColor: _C.primary,
            foregroundColor: Colors.white,
          ),
          child: const Text('Buat Akun'),
        ),
      ],
    );
  }
}

class _ProfileHeader extends StatelessWidget {
  final String initial;
  final String name;
  final String email;
  final String role;

  const _ProfileHeader({
    required this.initial,
    required this.name,
    required this.email,
    required this.role,
  });

  @override
  Widget build(BuildContext context) {
    final isOwner = role.toLowerCase() == 'owner';

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
              colors: [
                Color(0xFF3B82F6),
                Color(0xFF1D4ED8),
              ],
            ),
            border: Border.all(color: Colors.white, width: 4),
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
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            color: _C.textPrimary,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          email,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 14,
            color: _C.textSecondary,
          ),
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 6,
          ),
          decoration: BoxDecoration(
            color: isOwner ? _C.primarySoft : _C.successSoft,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.circle,
                size: 8,
                color: isOwner ? _C.primary : _C.success,
              ),
              const SizedBox(width: 7),
              Text(
                role == 'owner'
                    ? 'Owner'
                    : role == 'kasir'
                        ? 'Kasir'
                        : 'Role belum valid',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: isOwner ? _C.primary : _C.success,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

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
      padding: const EdgeInsets.symmetric(
        horizontal: 18,
        vertical: 12,
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: _C.primarySoft,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              icon,
              size: 20,
              color: _C.primary,
            ),
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
      child: Divider(height: 1, color: _C.border),
    );
  }
}

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

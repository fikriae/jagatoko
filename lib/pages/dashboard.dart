import 'package:flutter/material.dart';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'produk.dart' as produk_page;

import 'kasir.dart' as kasir_page;

import 'riwayat.dart' as riwayat_page;

import 'profile.dart' as profile_page;

import 'laporan.dart' as laporan_page;

import 'transaction_detail.dart' as transaction_detail;

class Dashboard extends StatefulWidget {

  final String? fullName;

  final String? role;

  const Dashboard({

    super.key,

    this.fullName,

    this.role,

  });

  @override

  State<Dashboard> createState() => _DashboardState();

}

class _DashboardState extends State<Dashboard> {

  final SupabaseClient _supabase = Supabase.instance.client;

  static const Color _primary = Color(0xFF2563EB);

  static const Color _background = Color(0xFFF8FAFC);

  static const int _lowStockLimit = 5;

  int _currentIndex = 0;

  bool _loading = false;

  String _fullName = 'Pengguna';

  String _role = 'kasir';

  List<Map<String, dynamic>> _products = [];

  List<Map<String, dynamic>> _todayTransactions = [];

  List<Map<String, dynamic>> _recentTransactions = [];

  @override

  void initState() {

    super.initState();

    _role = (widget.role ?? 'kasir').toLowerCase().trim();

    if (widget.fullName != null &&

        widget.fullName!.trim().isNotEmpty) {

      _fullName = widget.fullName!.trim();

    }

    _loadDashboard();

  }

  bool get _isOwner => _role == 'owner';

  List<_NavigationItem> get _navigationItems {

    if (_isOwner) {

      return [

        _NavigationItem(

          label: 'Dashboard',

          icon: Icons.dashboard_rounded,

          page: _buildDashboard(),

        ),

        _NavigationItem(

          label: 'Produk',

          icon: Icons.inventory_2_rounded,

          page: produk_page.ProdukPage(),

        ),

        _NavigationItem(

          label: 'Kasir',

          icon: Icons.point_of_sale_rounded,

          page: kasir_page.KasirPage(),

          isMain: true,

        ),

        _NavigationItem(

          label: 'Riwayat',

          icon: Icons.receipt_long_rounded,

          page: riwayat_page.RiwayatPage(),

        ),

        _NavigationItem(

          label: 'Profil',

          icon: Icons.person_outline_rounded,

          page: profile_page.ProfilePage(),

        ),

      ];

    }

    return [

      _NavigationItem(

        label: 'Dashboard',

        icon: Icons.dashboard_rounded,

        page: _buildDashboard(),

      ),

      _NavigationItem(

        label: 'Kasir',

        icon: Icons.point_of_sale_rounded,

        page: kasir_page.KasirPage(),

        isMain: true,

      ),

      _NavigationItem(

        label: 'Riwayat',

        icon: Icons.receipt_long_rounded,

        page: riwayat_page.RiwayatPage(),

      ),

      _NavigationItem(

        label: 'Profil',

        icon: Icons.person_outline_rounded,

        page: profile_page.ProfilePage(),

      ),

    ];

  }

  Future<void> _loadDashboard() async {

    if (!mounted) return;

    setState(() => _loading = true);

    try {

      final user = _supabase.auth.currentUser;

      if (user == null) {

        if (mounted) {

          _showMessage('Sesi login tidak ditemukan. Silakan login kembali.');

        }

        return;

      }

      final profile = await _supabase

          .from('profiles')

          .select('full_name, role, is_active')

          .eq('id', user.id)

          .maybeSingle();

      if (profile == null) {

        throw Exception('Profil pengguna tidak ditemukan.');

      }

      if (profile['is_active'] != true) {

        await _supabase.auth.signOut();

        if (mounted) {

          _showMessage('Akun kamu tidak aktif.');

        }

        return;

      }

      final String actualRole =

          (profile['role'] ?? 'kasir').toString().toLowerCase().trim();

      if (actualRole != 'owner' && actualRole != 'kasir') {

        throw Exception('Role pengguna tidak valid.');

      }

      final String actualName =

          (profile['full_name'] ?? '').toString().trim();

      final now = DateTime.now();

      final startOfDay = DateTime(now.year, now.month, now.day);

      final endOfDay = startOfDay.add(const Duration(days: 1));

      final results = await Future.wait<dynamic>([

        _supabase

            .from('products')

            .select(

              'id, name, barcode, selling_price, stock, category, '

              'image_url, is_active, created_at',

            )

            .eq('is_active', true)

            .order('name'),

        _supabase

            .from('transactions')

            .select(

              'id, invoice_number, cashier_id, customer_name, '

              'payment_method, subtotal, total, cash_received, '

              'change_amount, created_at',

            )

            .eq('is_hidden', false)

            .gte('created_at', startOfDay.toUtc().toIso8601String())

            .lt('created_at', endOfDay.toUtc().toIso8601String())

            .order('created_at', ascending: false),

        _supabase

            .from('transactions')

            .select(

              'id, invoice_number, cashier_id, customer_name, '

              'payment_method, subtotal, total, cash_received, '

              'change_amount, created_at',

            )

            .eq('is_hidden', false)

            .order('created_at', ascending: false)

            .limit(5),

      ]);

      if (!mounted) return;

      setState(() {

        _role = actualRole;

        if (actualName.isNotEmpty) {

          _fullName = actualName;

        } else if (widget.fullName != null &&

            widget.fullName!.trim().isNotEmpty) {

          _fullName = widget.fullName!.trim();

        }

        _products = List<Map<String, dynamic>>.from(results[0]);

        _todayTransactions =

            List<Map<String, dynamic>>.from(results[1]);

        _recentTransactions =

            List<Map<String, dynamic>>.from(results[2]);

        final maxIndex = _navigationItems.length - 1;

        if (_currentIndex > maxIndex) {

          _currentIndex = 0;

        }

      });

    } catch (e) {

      if (mounted) {

        _showMessage('Gagal memuat dashboard: $e');

      }

    } finally {

      if (mounted) {

        setState(() => _loading = false);

      }

    }

  }

  int _toInt(dynamic value) {

    if (value is num) return value.round();

    if (value is String) {

      return num.tryParse(value)?.round() ?? 0;

    }

    return 0;

  }

  String _formatToday() {

    const months = [

      'Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun',

      'Jul', 'Agu', 'Sep', 'Okt', 'Nov', 'Des',

    ];

    final now = DateTime.now();

    return '${now.day} ${months[now.month - 1]} ${now.year}';

  }

  int get _todaySales {

    return _todayTransactions.fold<int>(

      0,

      (sum, transaction) => sum + _toInt(transaction['total']),

    );

  }

  int get _todayCash {

    return _todayTransactions.fold<int>(0, (sum, transaction) {

      final method =

          (transaction['payment_method'] ?? '').toString().toLowerCase();

      if (method == 'cash' || method == 'tunai') {

        return sum + _toInt(transaction['total']);

      }

      return sum;

    });

  }

  int get _todayQris {

    return _todayTransactions.fold<int>(0, (sum, transaction) {

      final method =

          (transaction['payment_method'] ?? '').toString().toLowerCase();

      if (method == 'qris') {

        return sum + _toInt(transaction['total']);

      }

      return sum;

    });

  }

  int get _lowStockCount {

    return _products.where((product) {

      return _toInt(product['stock']) <= _lowStockLimit;

    }).length;

  }

  String _customerName(Map<String, dynamic> data) {

    final name = (data['customer_name'] ?? '').toString().trim();

    return name.isEmpty ? 'Umum' : name;

  }

  String _invoice(Map<String, dynamic> data) {

    final invoice = (data['invoice_number'] ?? '').toString().trim();

    return invoice.isEmpty ? '-' : invoice;

  }

  String _transactionTime(Map<String, dynamic> data) {

    final value = data['created_at'];

    if (value == null) return '-';

    final date = DateTime.tryParse(value.toString())?.toLocal();

    if (date == null) return '-';

    return '${date.hour.toString().padLeft(2, '0')}:'

        '${date.minute.toString().padLeft(2, '0')}';

  }

  void _showMessage(String message) {

    if (!mounted) return;

    ScaffoldMessenger.of(context)

      ..hideCurrentSnackBar()

      ..showSnackBar(

        SnackBar(

          content: Text(message),

          behavior: SnackBarBehavior.floating,

        ),

      );

  }

  void _openReport() {

    if (!_isOwner) {

      _showMessage('Menu laporan hanya tersedia untuk owner.');

      return;

    }

    Navigator.push(

      context,

      MaterialPageRoute(builder: (_) => const laporan_page.LaporanPage()),

    );

  }

  Future<void> _openTransaction(Map<String, dynamic> data) async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute<void>(
        builder: (_) => transaction_detail.TransactionDetailPage(
          transactionId: data['id'].toString(),
          data: data,
        ),
      ),
    );

    // Muat ulang data setelah halaman detail ditutup, termasuk setelah soft delete.
    if (!mounted) return;
    await _loadDashboard();
  }

  void _showLowStock() {

    final lowStock = _products.where((product) {

      return _toInt(product['stock']) <= _lowStockLimit;

    }).toList();

    showModalBottomSheet(

      context: context,

      backgroundColor: Colors.white,

      isScrollControlled: true,

      shape: const RoundedRectangleBorder(

        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),

      ),

      builder: (context) {

        return SafeArea(

          child: Padding(

            padding: const EdgeInsets.all(20),

            child: Column(

              mainAxisSize: MainAxisSize.min,

              crossAxisAlignment: CrossAxisAlignment.start,

              children: [

                const Text(

                  'Stok Produk Menipis',

                  style: TextStyle(

                    fontSize: 20,

                    fontWeight: FontWeight.w700,

                    color: Color(0xFF111827),

                  ),

                ),

                const SizedBox(height: 6),

                Text('${lowStock.length} produk membutuhkan perhatian'),

                const SizedBox(height: 16),

                if (lowStock.isEmpty)

                  const Padding(

                    padding: EdgeInsets.all(24),

                    child: Center(

                      child: Text('Tidak ada produk dengan stok menipis.'),

                    ),

                  )

                else

                  Flexible(

                    child: ListView.separated(

                      shrinkWrap: true,

                      itemCount: lowStock.length,

                      separatorBuilder: (_, __) =>

                          const SizedBox(height: 8),

                      itemBuilder: (context, index) {

                        final product = lowStock[index];

                        final stock = _toInt(product['stock']);

                        return ListTile(

                          leading: const CircleAvatar(

                            backgroundColor: Color(0xFFFFF7ED),

                            child: Icon(

                              Icons.inventory_2_outlined,

                              color: Color(0xFFEA580C),

                            ),

                          ),

                          title: Text(

                            (product['name'] ?? 'Produk').toString(),

                          ),

                          subtitle: Text(

                            (product['category'] ?? '').toString(),

                          ),

                          trailing: Text(

                            stock == 0 ? 'Habis' : '$stock stok',

                            style: TextStyle(

                              fontWeight: FontWeight.w700,

                              color: stock == 0

                                  ? Colors.red

                                  : const Color(0xFFEA580C),

                            ),

                          ),

                        );

                      },

                    ),

                  ),

              ],

            ),

          ),

        );

      },

    );

  }

  Widget _buildDashboard() {

    return RefreshIndicator(

      color: _primary,

      onRefresh: _loadDashboard,

      child: ListView(

        physics: const AlwaysScrollableScrollPhysics(),

        padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),

        children: [

          _buildWelcome(),

          const SizedBox(height: 16),

          if (_loading && _products.isEmpty)

            const Padding(

              padding: EdgeInsets.all(40),

              child: Center(

                child: CircularProgressIndicator(color: _primary),

              ),

            )

          else ...[

            _buildStatistics(),

            const SizedBox(height: 20),

            if (_isOwner) ...[

              _buildReportMenu(),

              const SizedBox(height: 20),

            ],

            _buildRecentTransactions(),

          ],

        ],

      ),

    );

  }

  Widget _buildWelcome() {

    return Container(

      width: double.infinity,

      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),

      decoration: BoxDecoration(

        color: _primary,

        borderRadius: BorderRadius.circular(16),

      ),

      child: Column(

        crossAxisAlignment: CrossAxisAlignment.start,

        children: [

          const Text(

            'Selamat datang 👋',

            style: TextStyle(fontSize: 13, color: Colors.white70),

          ),

          const SizedBox(height: 4),

          Text(

            _fullName,

            style: const TextStyle(

              fontSize: 20,

              fontWeight: FontWeight.w700,

              color: Colors.white,

            ),

          ),

          const SizedBox(height: 4),

          Text(

            _isOwner ? 'Owner Jagatoko' : 'Kasir Jagatoko',

            style: const TextStyle(fontSize: 12, color: Colors.white70),

          ),

        ],

      ),

    );

  }

  Widget _buildStatistics() {

    return GridView.count(

      shrinkWrap: true,

      physics: const NeverScrollableScrollPhysics(),

      crossAxisCount: 2,

      crossAxisSpacing: 12,

      mainAxisSpacing: 12,

      childAspectRatio: 1.15,

      children: [

        SalesStatCard(

          total: _todaySales,

          cash: _todayCash,

          qris: _todayQris,

        ),

        StatCard(

          title: 'Transaksi',

          value: '${_todayTransactions.length}',

          icon: Icons.receipt_long_rounded,

          iconColor: const Color(0xFF7C3AED),

          backgroundColor: const Color(0xFFF5F3FF),

        ),

        if (_isOwner)

          StatCard(

            title: 'Produk',

            value: '${_products.length}',

            icon: Icons.inventory_2_rounded,

            iconColor: const Color(0xFF0891B2),

            backgroundColor: const Color(0xFFECFEFF),

          ),

        StatCard(

            title: 'Stok Menipis',

            value: '$_lowStockCount',

            icon: Icons.warning_amber_rounded,

            iconColor: const Color(0xFFEA580C),

            backgroundColor: const Color(0xFFFFF7ED),

            onTap: _showLowStock,

          ),

      ],

    );

  }

  Widget _buildReportMenu() {

    return Column(

      crossAxisAlignment: CrossAxisAlignment.start,

      children: [

        const Text(

          'Lainnya',

          style: TextStyle(

            fontSize: 18,

            fontWeight: FontWeight.w700,

            color: Color(0xFF111827),

          ),

        ),

        const SizedBox(height: 10),

        Material(

          color: Colors.white,

          borderRadius: BorderRadius.circular(16),

          child: InkWell(

            onTap: _openReport,

            borderRadius: BorderRadius.circular(16),

            child: Container(

              padding: const EdgeInsets.all(16),

              decoration: BoxDecoration(

                borderRadius: BorderRadius.circular(16),

                border: Border.all(color: const Color(0xFFE5E7EB)),

              ),

              child: const Row(

                children: [

                  CircleAvatar(

                    backgroundColor: Color(0xFFEFF6FF),

                    child: Icon(

                      Icons.bar_chart_rounded,

                      color: _primary,

                    ),

                  ),

                  SizedBox(width: 12),

                  Expanded(

                    child: Column(

                      crossAxisAlignment: CrossAxisAlignment.start,

                      children: [

                        Text(

                          'Laporan',

                          style: TextStyle(

                            fontSize: 14,

                            fontWeight: FontWeight.w700,

                            color: Color(0xFF111827),

                          ),

                        ),

                        SizedBox(height: 3),

                        Text(

                          'Lihat laporan penjualan',

                          style: TextStyle(

                            fontSize: 12,

                            color: Color(0xFF6B7280),

                          ),

                        ),

                      ],

                    ),

                  ),

                  Icon(Icons.chevron_right_rounded, color: Color(0xFF9CA3AF)),

                ],

              ),

            ),

          ),

        ),

      ],

    );

  }

  Widget _buildRecentTransactions() {

    return Column(

      crossAxisAlignment: CrossAxisAlignment.start,

      children: [

        Row(

          children: [

            const Expanded(

              child: Text(

                'Transaksi Terbaru',

                style: TextStyle(

                  fontSize: 18,

                  fontWeight: FontWeight.w700,

                  color: Color(0xFF111827),

                ),

              ),

            ),

            TextButton(

              onPressed: () {

                final index = _navigationItems.indexWhere(

                  (item) => item.label == 'Riwayat',

                );

                if (index >= 0) setState(() => _currentIndex = index);

              },

              child: const Text(

                'Riwayat',

                style: TextStyle(

                  fontWeight: FontWeight.w600,

                  color: _primary,

                ),

              ),

            ),

          ],

        ),

        const SizedBox(height: 8),

        if (_recentTransactions.isEmpty)

          Container(

            width: double.infinity,

            padding: const EdgeInsets.symmetric(vertical: 30, horizontal: 20),

            decoration: BoxDecoration(

              color: Colors.white,

              borderRadius: BorderRadius.circular(16),

              border: Border.all(color: const Color(0xFFE5E7EB)),

            ),

            child: const Column(

              children: [

                Icon(

                  Icons.receipt_long_outlined,

                  color: _primary,

                  size: 42,

                ),

                SizedBox(height: 12),

                Text(

                  'Belum ada transaksi',

                  style: TextStyle(

                    fontSize: 15,

                    fontWeight: FontWeight.w600,

                  ),

                ),

                SizedBox(height: 4),

                Text(

                  'Transaksi terbaru akan tampil di sini.',

                  textAlign: TextAlign.center,

                  style: TextStyle(

                    fontSize: 12,

                    color: Color(0xFF6B7280),

                  ),

                ),

              ],

            ),

          )

        else

          Container(

            decoration: BoxDecoration(

              color: Colors.white,

              borderRadius: BorderRadius.circular(16),

              border: Border.all(color: const Color(0xFFE5E7EB)),

            ),

            child: ListView.separated(

              shrinkWrap: true,

              physics: const NeverScrollableScrollPhysics(),

              itemCount: _recentTransactions.length,

              separatorBuilder: (_, __) => const Divider(

                height: 1,

                indent: 72,

                endIndent: 16,

              ),

              itemBuilder: (context, index) {

                final transaction = _recentTransactions[index];

                return TransactionItem(

                  invoice: _invoice(transaction),

                  customer: _customerName(transaction),

                  amount: _toInt(transaction['total']),

                  time: _transactionTime(transaction),

                  paymentMethod:

                      (transaction['payment_method'] ?? 'Cash').toString(),

                  onTap: () => _openTransaction(transaction),

                );

              },

            ),

          ),

      ],

    );

  }

  @override

  Widget build(BuildContext context) {

    final items = _navigationItems;

    return Scaffold(

      backgroundColor: _background,

      appBar: _currentIndex == 0

          ? AppBar(

              backgroundColor: Colors.white,

              surfaceTintColor: Colors.transparent,

              foregroundColor: const Color(0xFF111827),

              elevation: 3,

              toolbarHeight: 80,

              titleSpacing: 20,

              shape: const RoundedRectangleBorder(

                borderRadius: BorderRadius.vertical(

                  bottom: Radius.circular(24),

                ),

              ),

              title: SizedBox(

                height: 58,

                width: 220,

                child: Image.asset(

                  'assets/images/logo_horizontal.png',

                  fit: BoxFit.contain,

                  alignment: Alignment.centerLeft,

                  errorBuilder: (_, __, ___) => const Align(

                    alignment: Alignment.centerLeft,

                    child: Text(

                      'JAGATOKO',

                      style: TextStyle(

                        fontSize: 24,

                        fontWeight: FontWeight.w800,

                        color: _primary,

                      ),

                    ),

                  ),

                ),

              ),

              actions: [

                Padding(

                  padding: const EdgeInsets.only(right: 16),

                  child: Center(

                    child: Container(

                      padding: const EdgeInsets.symmetric(

                        horizontal: 10,

                        vertical: 7,

                      ),

                      decoration: BoxDecoration(

                        color: const Color(0xFFEFF6FF),

                        borderRadius: BorderRadius.circular(20),

                      ),

                      child: Row(

                        mainAxisSize: MainAxisSize.min,

                        children: [

                          const Icon(

                            Icons.calendar_today_rounded,

                            size: 13,

                            color: _primary,

                          ),

                          const SizedBox(width: 5),

                          Text(

                            _formatToday(),

                            style: const TextStyle(

                              fontSize: 11,

                              fontWeight: FontWeight.w600,

                              color: _primary,

                            ),

                          ),

                        ],

                      ),

                    ),

                  ),

                ),

              ],

            )

          : null,

      body: IndexedStack(

        index: _currentIndex,

        children: items.map((item) => item.page).toList(),

      ),

      bottomNavigationBar: Container(

        decoration: const BoxDecoration(

          color: Colors.white,

          boxShadow: [

            BoxShadow(

              color: Color(0x12000000),

              blurRadius: 15,

              offset: Offset(0, -4),

            ),

          ],

        ),

        child: SafeArea(

          top: false,

          child: SizedBox(

            height: 72,

            child: Row(

              children: [

                for (int i = 0; i < items.length; i++)

                  Expanded(

                    child: _BottomNavItem(

                      icon: items[i].icon,

                      label: items[i].label,

                      isSelected: _currentIndex == i,

                      isMainMenu: items[i].isMain,

                      onTap: () => setState(() => _currentIndex = i),

                    ),

                  ),

              ],

            ),

          ),

        ),

      ),

    );

  }

}

class _NavigationItem {

  final String label;

  final IconData icon;

  final Widget page;

  final bool isMain;

  _NavigationItem({

    required this.label,

    required this.icon,

    required this.page,

    this.isMain = false,

  });

}

class SalesStatCard extends StatelessWidget {

  final int total;

  final int cash;

  final int qris;

  const SalesStatCard({

    super.key,

    required this.total,

    required this.cash,

    required this.qris,

  });

  String _rupiah(int value) {

    final number = value.abs().toString();

    final result = StringBuffer();

    for (int i = 0; i < number.length; i++) {

      if (i > 0 && (number.length - i) % 3 == 0) {

        result.write('.');

      }

      result.write(number[i]);

    }

    return '${value < 0 ? '-' : ''}Rp ${result.toString()}';

  }

  @override

  Widget build(BuildContext context) {

    return Container(

      padding: const EdgeInsets.all(14),

      decoration: BoxDecoration(

        color: Colors.white,

        borderRadius: BorderRadius.circular(16),

        border: Border.all(color: const Color(0xFFE5E7EB)),

        boxShadow: const [

          BoxShadow(

            color: Color(0x08000000),

            blurRadius: 8,

            offset: Offset(0, 2),

          ),

        ],

      ),

      child: Column(

        crossAxisAlignment: CrossAxisAlignment.start,

        children: [

          const Row(

            children: [

              CircleAvatar(

                radius: 17,

                backgroundColor: Color(0xFFECFDF5),

                child: Icon(

                  Icons.payments_rounded,

                  size: 19,

                  color: Color(0xFF059669),

                ),

              ),

              SizedBox(width: 8),

              Expanded(

                child: Text(

                  'Penjualan Hari Ini',

                  maxLines: 2,

                  style: TextStyle(

                    fontSize: 12,

                    fontWeight: FontWeight.w600,

                    color: Color(0xFF6B7280),

                  ),

                ),

              ),

            ],

          ),

          const SizedBox(height: 8),

          Text(

            _rupiah(total),

            maxLines: 1,

            overflow: TextOverflow.ellipsis,

            style: const TextStyle(

              fontSize: 17,

              fontWeight: FontWeight.w800,

              color: Color(0xFF111827),

            ),

          ),

          const SizedBox(height: 7),

          Expanded(

            child: Row(

              children: [

                Expanded(

                  child: _PaymentSummary(

                    label: 'Cash',

                    value: _rupiah(cash),

                  ),

                ),

                const SizedBox(width: 5),

                Expanded(

                  child: _PaymentSummary(

                    label: 'QRIS',

                    value: _rupiah(qris),

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

class _PaymentSummary extends StatelessWidget {

  final String label;

  final String value;

  const _PaymentSummary({

    required this.label,

    required this.value,

  });

  @override

  Widget build(BuildContext context) {

    return Column(

      crossAxisAlignment: CrossAxisAlignment.start,

      mainAxisAlignment: MainAxisAlignment.end,

      children: [

        Text(

          label,

          style: const TextStyle(

            fontSize: 9,

            color: Color(0xFF9CA3AF),

          ),

        ),

        const SizedBox(height: 1),

        Text(

          value,

          maxLines: 1,

          overflow: TextOverflow.ellipsis,

          style: const TextStyle(

            fontSize: 10,

            fontWeight: FontWeight.w700,

            color: Color(0xFF374151),

          ),

        ),

      ],

    );

  }

}

class StatCard extends StatelessWidget {

  final String title;

  final String value;

  final IconData icon;

  final Color iconColor;

  final Color backgroundColor;

  final VoidCallback? onTap;

  const StatCard({

    super.key,

    required this.title,

    required this.value,

    required this.icon,

    required this.iconColor,

    required this.backgroundColor,

    this.onTap,

  });

  @override

  Widget build(BuildContext context) {

    final card = Container(

      padding: const EdgeInsets.all(14),

      decoration: BoxDecoration(

        color: Colors.white,

        borderRadius: BorderRadius.circular(16),

        border: Border.all(color: const Color(0xFFE5E7EB)),

        boxShadow: const [

          BoxShadow(

            color: Color(0x08000000),

            blurRadius: 8,

            offset: Offset(0, 2),

          ),

        ],

      ),

      child: Column(

        crossAxisAlignment: CrossAxisAlignment.start,

        children: [

          Row(

            children: [

              Container(

                width: 34,

                height: 34,

                decoration: BoxDecoration(

                  color: backgroundColor,

                  borderRadius: BorderRadius.circular(10),

                ),

                child: Icon(icon, size: 19, color: iconColor),

              ),

              const Spacer(),

              if (onTap != null)

                const Icon(

                  Icons.chevron_right_rounded,

                  size: 18,

                  color: Color(0xFF9CA3AF),

                ),

            ],

          ),

          const Spacer(),

          Text(

            title,

            maxLines: 1,

            overflow: TextOverflow.ellipsis,

            style: const TextStyle(

              fontSize: 12,

              fontWeight: FontWeight.w500,

              color: Color(0xFF6B7280),

            ),

          ),

          const SizedBox(height: 2),

          Text(

            value,

            maxLines: 1,

            overflow: TextOverflow.ellipsis,

            style: const TextStyle(

              fontSize: 20,

              fontWeight: FontWeight.w800,

              color: Color(0xFF111827),

            ),

          ),

        ],

      ),

    );

    if (onTap == null) return card;

    return Material(

      color: Colors.transparent,

      child: InkWell(

        borderRadius: BorderRadius.circular(16),

        onTap: onTap,

        child: card,

      ),

    );

  }

}

class TransactionItem extends StatelessWidget {

  final String invoice;

  final String customer;

  final int amount;

  final String time;

  final String paymentMethod;

  final VoidCallback onTap;

  const TransactionItem({

    super.key,

    required this.invoice,

    required this.customer,

    required this.amount,

    required this.time,

    required this.paymentMethod,

    required this.onTap,

  });

  String _rupiah(int value) {

    final number = value.abs().toString();

    final result = StringBuffer();

    for (int i = 0; i < number.length; i++) {

      if (i > 0 && (number.length - i) % 3 == 0) {

        result.write('.');

      }

      result.write(number[i]);

    }

    return '${value < 0 ? '-' : ''}Rp ${result.toString()}';

  }

  @override

  Widget build(BuildContext context) {

    final isQris = paymentMethod.toLowerCase() == 'qris';

    return Material(

      color: Colors.transparent,

      child: InkWell(

        onTap: onTap,

        child: Padding(

          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),

          child: Row(

            children: [

              Container(

                width: 44,

                height: 44,

                decoration: BoxDecoration(

                  color: isQris

                      ? const Color(0xFFF5F3FF)

                      : const Color(0xFFECFDF5),

                  borderRadius: BorderRadius.circular(13),

                ),

                child: Icon(

                  isQris

                      ? Icons.qr_code_rounded

                      : Icons.payments_rounded,

                  color: isQris

                      ? const Color(0xFF7C3AED)

                      : const Color(0xFF059669),

                  size: 22,

                ),

              ),

              const SizedBox(width: 12),

              Expanded(

                child: Column(

                  crossAxisAlignment: CrossAxisAlignment.start,

                  children: [

                    Text(

                      invoice,

                      maxLines: 1,

                      overflow: TextOverflow.ellipsis,

                      style: const TextStyle(

                        fontSize: 13,

                        fontWeight: FontWeight.w700,

                        color: Color(0xFF111827),

                      ),

                    ),

                    const SizedBox(height: 3),

                    Text(

                      customer,

                      maxLines: 1,

                      overflow: TextOverflow.ellipsis,

                      style: const TextStyle(

                        fontSize: 12,

                        color: Color(0xFF6B7280),

                      ),

                    ),

                    const SizedBox(height: 3),

                    Text(

                      '$paymentMethod • $time',

                      style: TextStyle(

                        fontSize: 11,

                        color: isQris

                            ? const Color(0xFF7C3AED)

                            : const Color(0xFF059669),

                        fontWeight: FontWeight.w500,

                      ),

                    ),

                  ],

                ),

              ),

              const SizedBox(width: 8),

              Column(

                crossAxisAlignment: CrossAxisAlignment.end,

                children: [

                  Text(

                    _rupiah(amount),

                    style: const TextStyle(

                      fontSize: 13,

                      fontWeight: FontWeight.w700,

                      color: Color(0xFF111827),

                    ),

                  ),

                  const SizedBox(height: 5),

                  const Icon(

                    Icons.chevron_right_rounded,

                    size: 18,

                    color: Color(0xFF9CA3AF),

                  ),

                ],

              ),

            ],

          ),

        ),

      ),

    );

  }

}

class _BottomNavItem extends StatelessWidget {

  final IconData icon;

  final String label;

  final bool isSelected;

  final bool isMainMenu;

  final VoidCallback onTap;

  const _BottomNavItem({

    required this.icon,

    required this.label,

    required this.isSelected,

    required this.onTap,

    this.isMainMenu = false,

  });

  @override

  Widget build(BuildContext context) {

    if (isMainMenu) {

      return GestureDetector(

        onTap: onTap,

        child: Column(

          mainAxisAlignment: MainAxisAlignment.center,

          children: [

            Container(

              width: 48,

              height: 38,

              decoration: BoxDecoration(

                color: isSelected

                    ? const Color(0xFF2563EB)

                    : const Color(0xFFEFF6FF),

                borderRadius: BorderRadius.circular(14),

              ),

              child: Icon(

                icon,

                size: 22,

                color: isSelected

                    ? Colors.white

                    : const Color(0xFF2563EB),

              ),

            ),

            const SizedBox(height: 3),

            Text(

              label,

              style: TextStyle(

                fontSize: 10,

                fontWeight:

                    isSelected ? FontWeight.w700 : FontWeight.w500,

                color: isSelected

                    ? const Color(0xFF2563EB)

                    : const Color(0xFF6B7280),

              ),

            ),

          ],

        ),

      );

    }

    return InkWell(

      onTap: onTap,

      child: Column(

        mainAxisAlignment: MainAxisAlignment.center,

        children: [

          Icon(

            icon,

            size: 22,

            color: isSelected

                ? const Color(0xFF2563EB)

                : const Color(0xFF9CA3AF),

          ),

          const SizedBox(height: 4),

          Text(

            label,

            style: TextStyle(

              fontSize: 10,

              fontWeight:

                  isSelected ? FontWeight.w700 : FontWeight.w500,

              color: isSelected

                  ? const Color(0xFF2563EB)

                  : const Color(0xFF6B7280),

            ),

          ),

        ],

      ),

    );

  }

}

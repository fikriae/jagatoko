

import 'package:flutter/material.dart';

import 'package:supabase_flutter/supabase_flutter.dart';



const Color _primary = Color(0xFF2563EB);

const Color _background = Color(0xFFF8FAFC);

const Color _green = Color(0xFF047857);

const Color _red = Color(0xFFB91C1C);

const Color _text = Color(0xFF111827);

const Color _muted = Color(0xFF6B7280);

const Color _border = Color(0xFFE5E7EB);



class ArusKasPage extends StatefulWidget {

  const ArusKasPage({super.key});



  @override

  State<ArusKasPage> createState() => _ArusKasPageState();

}



class _ArusKasPageState extends State<ArusKasPage> {

  final SupabaseClient _supabase = Supabase.instance.client;



  DateTime _selectedMonth = DateTime(

    DateTime.now().year,

    DateTime.now().month,

  );



  bool _loading = true;

  bool _authorized = false;

  String? _errorMessage;



  List<Map<String, dynamic>> _transactions = [];

  List<Map<String, dynamic>> _expenses = [];

  List<Map<String, dynamic>> _products = [];

  List<Map<String, dynamic>> _transactionItems = [];

  Map<String, num> _purchasePrices = {};



  @override

  void initState() {

    super.initState();

    _load();

  }



  num _number(dynamic value) {

    if (value is num) return value;

    return num.tryParse(value?.toString() ?? '') ?? 0;

  }



  String _rupiah(num value) {

    final number = value.round().abs().toString();

    final result = StringBuffer();



    for (int i = 0; i < number.length; i++) {

      if (i > 0 && (number.length - i) % 3 == 0) {

        result.write('.');

      }

      result.write(number[i]);

    }



    return '${value < 0 ? '-' : ''}Rp ${result.toString()}';

  }



  String _dateString(DateTime date) {

    return '${date.year.toString().padLeft(4, '0')}-'

        '${date.month.toString().padLeft(2, '0')}-'

        '${date.day.toString().padLeft(2, '0')}';

  }



  Future<void> _load() async {

    if (!mounted) return;



    setState(() {

      _loading = true;

      _errorMessage = null;

    });



    try {

      final user = _supabase.auth.currentUser;



      if (user == null) {

        throw Exception('Sesi login tidak ditemukan. Silakan login kembali.');

      }



      final profile = await _supabase

          .from('profiles')

          .select('role, is_active')

          .eq('id', user.id)

          .maybeSingle();



      final role =

          (profile?['role'] ?? '').toString().toLowerCase().trim();



      if (profile == null ||

          profile['is_active'] != true ||

          role != 'owner') {

        if (mounted) {

          setState(() => _authorized = false);

        }

        throw Exception('Halaman Arus Kas hanya tersedia untuk Owner.');

      }



      if (mounted) {

        setState(() => _authorized = true);

      }



      final start = DateTime(

        _selectedMonth.year,

        _selectedMonth.month,

      );



      final end = DateTime(

        _selectedMonth.year,

        _selectedMonth.month + 1,

      );



      final startDate = _dateString(start);

      final endDate = _dateString(end);



      final result = await Future.wait<dynamic>([

        _supabase

            .from('transactions')

            .select('id, total, payment_method, created_at')

            .eq('is_hidden', false)

            .gte('created_at', start.toUtc().toIso8601String())

            .lt('created_at', end.toUtc().toIso8601String())

            .order('created_at', ascending: false),



        _supabase

            .from('expenses')

            .select(

              'id, amount, category, description, expense_date, '

              'payment_method',

            )

            .gte('expense_date', startDate)

            .lt('expense_date', endDate)

            .order('expense_date', ascending: false),

        // Data stok seluruh produk untuk menghitung total modal persediaan.
        _supabase.from('products').select('id, stock'),

      ]);



      final transactions =

          List<Map<String, dynamic>>.from(result[0]);



      final expenses =

          List<Map<String, dynamic>>.from(result[1]);

      final products =
          List<Map<String, dynamic>>.from(result[2]);



      // Ambil detail produk dari transaksi pada periode yang dipilih.

      List<Map<String, dynamic>> transactionItems = [];

      Map<String, num> purchasePrices = {};



      final transactionIds = transactions

          .map((item) => item['id'])

          .where((id) => id != null)

          .toList();



      if (transactionIds.isNotEmpty) {

        final itemsResponse = await _supabase

            .from('transaction_items')

            .select()

            .inFilter('transaction_id', transactionIds);



        transactionItems = List<Map<String, dynamic>>.from(

          (itemsResponse as List).map(

            (item) => Map<String, dynamic>.from(item),

          ),

        );



      }

      // Ambil seluruh harga beli untuk menghitung modal persediaan saat ini.
      final costsResponse = await _supabase
          .from('product_costs')
          .select('product_id, purchase_price');

      for (final row in costsResponse as List) {
        final productId = row['product_id']?.toString();

        if (productId != null && productId.isNotEmpty) {
          purchasePrices[productId] = _number(row['purchase_price']);
        }
      }

      if (!mounted) return;



      setState(() {

        _transactions = transactions;

        _expenses = expenses;

        _products = products;

        _transactionItems = transactionItems;

        _purchasePrices = purchasePrices;

      });

    } catch (e) {

      if (mounted) {

        setState(() {

          _errorMessage = e.toString().replaceFirst('Exception: ', '');

        });

      }

    } finally {

      if (mounted) {

        setState(() => _loading = false);

      }

    }

  }



  Future<void> _changeMonth(int offset) async {

    setState(() {

      _selectedMonth = DateTime(

        _selectedMonth.year,

        _selectedMonth.month + offset,

      );

    });



    await _load();

  }



  num get _cashIn {

    return _transactions.fold<num>(

      0,

      (sum, row) => sum + _number(row['total']),

    );

  }



  num get _cashOut {

    return _expenses.fold<num>(

      0,

      (sum, row) => sum + _number(row['amount']),

    );

  }



  num get _netCash => _cashIn - _cashOut;

  // Total modal persediaan = stok saat ini dikalikan harga beli terbaru.
  num get _totalStockCapital {
    num total = 0;

    for (final product in _products) {
      final productId = product['id']?.toString();
      if (productId == null || !_purchasePrices.containsKey(productId)) {
        continue;
      }

      total += _number(product['stock']) * (_purchasePrices[productId] ?? 0);
    }

    return total;
  }

  int get _productsWithoutCost {
    return _products.where((product) {
      final productId = product['id']?.toString();
      return productId == null || !_purchasePrices.containsKey(productId);
    }).length;
  }



  // Harga pokok hanya dapat dihitung jika semua item mempunyai

  // product_id dan harga modal tersedia di product_costs.

  bool get _hasCompleteCostData {

    if (_transactionItems.isEmpty) {

      return _transactions.isEmpty;

    }



    for (final item in _transactionItems) {

      final productId = item['product_id']?.toString();



      if (productId == null ||

          productId.isEmpty ||

          !_purchasePrices.containsKey(productId)) {

        return false;

      }

    }



    return true;

  }



  num get _costOfGoodsSold {

    num total = 0;



    for (final item in _transactionItems) {

      final productId = item['product_id']?.toString();



      if (productId == null ||

          !_purchasePrices.containsKey(productId)) {

        continue;

      }



      final quantity = _number(item['quantity']);

      final purchasePrice = _purchasePrices[productId] ?? 0;



      total += quantity * purchasePrice;

    }



    return total;

  }



  num get _grossProfit {

    return _cashIn - _costOfGoodsSold;

  }



  num get _estimatedNetProfit {

    return _grossProfit - _cashOut;

  }



  int get _missingCostCount {

    int count = 0;



    for (final item in _transactionItems) {

      final productId = item['product_id']?.toString();



      if (productId == null ||

          productId.isEmpty ||

          !_purchasePrices.containsKey(productId)) {

        count++;

      }

    }



    return count;

  }



  static const List<String> _months = [

    'Januari',

    'Februari',

    'Maret',

    'April',

    'Mei',

    'Juni',

    'Juli',

    'Agustus',

    'September',

    'Oktober',

    'November',

    'Desember',

  ];



  @override

  Widget build(BuildContext context) {

    return Scaffold(

      backgroundColor: _background,

      appBar: AppBar(

        title: const Text(

          'Arus Kas',

          style: TextStyle(fontWeight: FontWeight.w700),

        ),

        backgroundColor: Colors.white,

        surfaceTintColor: Colors.transparent,

        foregroundColor: _text,

        actions: [

          IconButton(

            tooltip: 'Muat ulang',

            onPressed: _loading ? null : _load,

            icon: const Icon(Icons.refresh_rounded),

          ),

        ],

      ),

      body: _loading

          ? const Center(

              child: CircularProgressIndicator(color: _primary),

            )

          : _errorMessage != null

              ? _buildError()

              : RefreshIndicator(

                  onRefresh: _load,

                  color: _primary,

                  child: ListView(

                    physics: const AlwaysScrollableScrollPhysics(),

                    padding: const EdgeInsets.all(16),

                    children: [

                      _buildMonthSelector(),

                      const SizedBox(height: 16),



                      // Arus kas: uang masuk dikurangi uang keluar.

                      _summaryCard(

                        title: 'Arus Kas Bersih',

                        value: _rupiah(_netCash),

                        subtitle: 'Pemasukan dikurangi pengeluaran',

                        icon: Icons.account_balance_wallet_rounded,

                        foreground: _primary,

                        background: const Color(0xFFEFF6FF),

                      ),

                      const SizedBox(height: 12),



                      _summaryCard(
                        title: 'Total Modal',
                        value: _rupiah(_totalStockCapital),
                        subtitle: _productsWithoutCost == 0
                            ? 'Nilai stok saat ini berdasarkan harga beli'
                            : 'Estimasi; $_productsWithoutCost produk belum memiliki harga beli',
                        icon: Icons.inventory_2_rounded,
                        foreground: const Color(0xFF7C3AED),
                        background: const Color(0xFFF5F3FF),
                      ),

                      const SizedBox(height: 12),

                      Row(

                        crossAxisAlignment: CrossAxisAlignment.start,

                        children: [

                          Expanded(

                            child: _summaryCard(

                              title: 'Total Pemasukan',

                              value: _rupiah(_cashIn),

                              subtitle:

                                  '${_transactions.length} transaksi',

                              icon: Icons.trending_up_rounded,

                              foreground: _green,

                              background: const Color(0xFFECFDF5),

                            ),

                          ),

                          const SizedBox(width: 10),

                          Expanded(

                            child: _summaryCard(

                              title: 'Total Pengeluaran',

                              value: _rupiah(_cashOut),

                              subtitle: '${_expenses.length} catatan',

                              icon: Icons.trending_down_rounded,

                              foreground: _red,

                              background: const Color(0xFFFEF2F2),

                            ),

                          ),

                        ],

                      ),



                      const SizedBox(height: 22),



                      const Text(

                        'Ringkasan Laba',

                        style: TextStyle(

                          fontSize: 18,

                          fontWeight: FontWeight.w800,

                          color: _text,

                        ),

                      ),

                      const SizedBox(height: 5),

                      const Text(

                        'Perhitungan berdasarkan penjualan dan harga modal '

                        'yang tersedia.',

                        style: TextStyle(

                          fontSize: 12,

                          color: _muted,

                        ),

                      ),

                      const SizedBox(height: 12),



                      _summaryCard(

                        title: 'Harga Pokok Penjualan',

                        value: _hasCompleteCostData

                            ? _rupiah(_costOfGoodsSold)

                            : 'Belum lengkap',

                        subtitle: 'Modal barang yang terjual',

                        icon: Icons.inventory_2_rounded,

                        foreground: const Color(0xFF7C3AED),

                        background: const Color(0xFFF5F3FF),

                      ),

                      const SizedBox(height: 10),



                      _summaryCard(

                        title: 'Laba Kotor',

                        value: _hasCompleteCostData

                            ? _rupiah(_grossProfit)

                            : 'Belum dapat dihitung',

                        subtitle: 'Penjualan dikurangi harga pokok',

                        icon: Icons.bar_chart_rounded,

                        foreground: const Color(0xFF0369A1),

                        background: const Color(0xFFE0F2FE),

                      ),

                      const SizedBox(height: 10),



                      _summaryCard(

                        title: 'Laba Bersih Estimasi',

                        value: _hasCompleteCostData

                            ? _rupiah(_estimatedNetProfit)

                            : 'Belum dapat dihitung',

                        subtitle: 'Laba kotor dikurangi pengeluaran',

                        icon: Icons.savings_rounded,

                        foreground: _hasCompleteCostData &&

                                _estimatedNetProfit < 0

                            ? _red

                            : _green,

                        background: _hasCompleteCostData &&

                                _estimatedNetProfit < 0

                            ? const Color(0xFFFEF2F2)

                            : const Color(0xFFECFDF5),

                      ),



                      if (!_hasCompleteCostData) ...[

                        const SizedBox(height: 12),

                        _notice(

                          'Laba belum dapat dihitung dengan lengkap. '

                          'Ada ${_missingCostCount} detail barang tanpa '

                          'harga modal yang cocok. Periksa product_costs '

                          'dan pastikan transaction_items memiliki '

                          'product_id yang benar.',

                          background: const Color(0xFFFFFBEB),

                          foreground: const Color(0xFF92400E),

                          borderColor: const Color(0xFFFDE68A),

                          icon: Icons.info_outline_rounded,

                        ),

                      ],



                      const SizedBox(height: 22),



                      const Text(

                        'Rincian Periode',

                        style: TextStyle(

                          fontSize: 18,

                          fontWeight: FontWeight.w800,

                          color: _text,

                        ),

                      ),

                      const SizedBox(height: 10),



                      _detailRow(

                        icon: Icons.point_of_sale_rounded,

                        title: 'Penerimaan penjualan',

                        subtitle: '${_transactions.length} transaksi',

                        amount: _rupiah(_cashIn),

                        color: _green,

                      ),

                      _detailRow(

                        icon: Icons.inventory_2_outlined,

                        title: 'Harga pokok barang terjual',

                        subtitle: 'Berdasarkan harga modal tersedia',

                        amount: _hasCompleteCostData

                            ? _rupiah(_costOfGoodsSold)

                            : 'Belum lengkap',

                        color: const Color(0xFF7C3AED),

                      ),

                      _detailRow(

                        icon: Icons.receipt_long_rounded,

                        title: 'Pengeluaran toko',

                        subtitle: '${_expenses.length} catatan',

                        amount: _rupiah(_cashOut),

                        color: _red,

                      ),



                      const SizedBox(height: 12),



                      _notice(

                        'Catatan: Arus kas bersih berbeda dengan laba. '

                        'Laba di halaman ini adalah estimasi menggunakan '

                        'harga modal terbaru dari product_costs, bukan '

                        'selalu harga modal historis saat barang terjual. '

                        'Biaya admin QRIS, pajak, utang, dan saldo awal '

                        'belum diperhitungkan.',

                        background: const Color(0xFFFFFBEB),

                        foreground: const Color(0xFF92400E),

                        borderColor: const Color(0xFFFDE68A),

                        icon: Icons.info_outline_rounded,

                      ),

                    ],

                  ),

                ),

    );

  }



  Widget _buildError() {

    return Center(

      child: SingleChildScrollView(

        padding: const EdgeInsets.all(24),

        child: Column(

          mainAxisSize: MainAxisSize.min,

          children: [

            Icon(

              _authorized

                  ? Icons.cloud_off_rounded

                  : Icons.lock_outline_rounded,

              size: 52,

              color: _red,

            ),

            const SizedBox(height: 12),

            const Text(

              'Arus Kas tidak dapat dimuat',

              textAlign: TextAlign.center,

              style: TextStyle(

                fontSize: 18,

                fontWeight: FontWeight.w800,

                color: _text,

              ),

            ),

            const SizedBox(height: 8),

            Text(

              _errorMessage ?? 'Terjadi kesalahan.',

              textAlign: TextAlign.center,

              style: const TextStyle(

                fontSize: 13,

                color: _muted,

              ),

            ),

            const SizedBox(height: 16),

            FilledButton.icon(

              onPressed: _load,

              icon: const Icon(Icons.refresh_rounded),

              label: const Text('Coba Lagi'),

              style: FilledButton.styleFrom(

                backgroundColor: _primary,

                foregroundColor: Colors.white,

              ),

            ),

          ],

        ),

      ),

    );

  }



  Widget _buildMonthSelector() {

    return Container(

      padding: const EdgeInsets.symmetric(

        horizontal: 8,

        vertical: 4,

      ),

      decoration: BoxDecoration(

        color: Colors.white,

        borderRadius: BorderRadius.circular(16),

        border: Border.all(color: _border),

      ),

      child: Row(

        children: [

          IconButton(

            tooltip: 'Bulan sebelumnya',

            onPressed: () => _changeMonth(-1),

            icon: const Icon(Icons.chevron_left_rounded),

          ),

          Expanded(

            child: Text(

              '${_months[_selectedMonth.month - 1]} '

              '${_selectedMonth.year}',

              textAlign: TextAlign.center,

              style: const TextStyle(

                fontSize: 16,

                fontWeight: FontWeight.w800,

                color: _text,

              ),

            ),

          ),

          IconButton(

            tooltip: 'Bulan berikutnya',

            onPressed: () => _changeMonth(1),

            icon: const Icon(Icons.chevron_right_rounded),

          ),

        ],

      ),

    );

  }



  Widget _summaryCard({

    required String title,

    required String value,

    required String subtitle,

    required IconData icon,

    required Color foreground,

    required Color background,

  }) {

    return Container(

      width: double.infinity,

      padding: const EdgeInsets.all(16),

      decoration: BoxDecoration(

        color: Colors.white,

        borderRadius: BorderRadius.circular(16),

        border: Border.all(color: _border),

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

                width: 38,

                height: 38,

                decoration: BoxDecoration(

                  color: background,

                  borderRadius: BorderRadius.circular(11),

                ),

                child: Icon(

                  icon,

                  color: foreground,

                  size: 21,

                ),

              ),

              const Spacer(),

              Flexible(

                child: Text(

                  title,

                  textAlign: TextAlign.end,

                  style: const TextStyle(

                    color: _muted,

                    fontSize: 12,

                    fontWeight: FontWeight.w600,

                  ),

                ),

              ),

            ],

          ),

          const SizedBox(height: 14),

          Text(

            value,

            maxLines: 2,

            overflow: TextOverflow.ellipsis,

            style: TextStyle(

              color: foreground,

              fontSize: 19,

              fontWeight: FontWeight.w800,

            ),

          ),

          const SizedBox(height: 5),

          Text(

            subtitle,

            style: const TextStyle(

              color: _muted,

              fontSize: 11,

            ),

          ),

        ],

      ),

    );

  }



  Widget _detailRow({

    required IconData icon,

    required String title,

    required String subtitle,

    required String amount,

    required Color color,

  }) {

    return Container(

      margin: const EdgeInsets.only(bottom: 8),

      padding: const EdgeInsets.all(14),

      decoration: BoxDecoration(

        color: Colors.white,

        borderRadius: BorderRadius.circular(14),

        border: Border.all(color: _border),

      ),

      child: Row(

        children: [

          CircleAvatar(

            backgroundColor: color.withValues(alpha: 0.10),

            child: Icon(icon, color: color),

          ),

          const SizedBox(width: 12),

          Expanded(

            child: Column(

              crossAxisAlignment: CrossAxisAlignment.start,

              children: [

                Text(

                  title,

                  style: const TextStyle(

                    fontWeight: FontWeight.w700,

                    color: _text,

                  ),

                ),

                const SizedBox(height: 3),

                Text(

                  subtitle,

                  style: const TextStyle(

                    fontSize: 11,

                    color: _muted,

                  ),

                ),

              ],

            ),

          ),

          const SizedBox(width: 8),

          Flexible(

            child: Text(

              amount,

              textAlign: TextAlign.end,

              style: TextStyle(

                color: color,

                fontWeight: FontWeight.w800,

                fontSize: 12,

              ),

            ),

          ),

        ],

      ),

    );

  }



  Widget _notice(

    String message, {

    required Color background,

    required Color foreground,

    required Color borderColor,

    required IconData icon,

  }) {

    return Container(

      padding: const EdgeInsets.all(14),

      decoration: BoxDecoration(

        color: background,

        borderRadius: BorderRadius.circular(12),

        border: Border.all(color: borderColor),

      ),

      child: Row(

        crossAxisAlignment: CrossAxisAlignment.start,

        children: [

          Icon(icon, color: foreground, size: 20),

          const SizedBox(width: 10),

          Expanded(

            child: Text(

              message,

              style: TextStyle(

                fontSize: 12,

                height: 1.5,

                color: foreground,

              ),

            ),

          ),

        ],

      ),

    );

  }

}

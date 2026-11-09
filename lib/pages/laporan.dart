import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class LaporanPage extends StatefulWidget {
  const LaporanPage({super.key});

  @override
  State<LaporanPage> createState() => _LaporanPageState();
}

class _LaporanPageState extends State<LaporanPage> {
  final SupabaseClient _supabase = Supabase.instance.client;

  static const Color _primary = Color(0xFF2563EB);
  static const Color _background = Color(0xFFF5F7FA);
  static const Color _border = Color(0xFFE5E7EB);
  static const Color _muted = Color(0xFF64748B);
  static const Color _text = Color(0xFF1E293B);
  static const Color _green = Color(0xFF16A34A);
  static const Color _red = Color(0xFFDC2626);
  static const Color _orange = Color(0xFFD97706);

  DateTime _selectedDate = DateTime.now();
  String _period = 'Harian';

  bool _isLoading = true;
  String? _errorMessage;

  List<Map<String, dynamic>> _transactions = [];
  List<Map<String, dynamic>> _expenses = [];

  final Map<String, List<Map<String, dynamic>>> _transactionItems = {};
  final Map<String, Map<String, dynamic>> _itemCosts = {};

  int _itemsWithoutCost = 0;

  @override
  void initState() {
    super.initState();
    _loadTransactions();
  }

  DateTime _startOfPeriod() {
    if (_period == 'Bulanan') {
      return DateTime(_selectedDate.year, _selectedDate.month, 1);
    }
    return DateTime(
      _selectedDate.year,
      _selectedDate.month,
      _selectedDate.day,
    );
  }

  DateTime _endOfPeriod() {
    if (_period == 'Bulanan') {
      return DateTime(_selectedDate.year, _selectedDate.month + 1, 1);
    }
    return DateTime(
      _selectedDate.year,
      _selectedDate.month,
      _selectedDate.day + 1,
    );
  }

  Future<void> _loadTransactions() async {
    if (!mounted) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final startUtc = _startOfPeriod().toUtc().toIso8601String();
      final endUtc = _endOfPeriod().toUtc().toIso8601String();

      final response = await _supabase
          .from('transactions')
          .select(
            'id, invoice_number, invoice, customer_name, '
            'payment_method, subtotal, total, created_at, is_hidden',
          )
          .eq('is_hidden', false)
          .gte('created_at', startUtc)
          .lt('created_at', endUtc)
          .order('created_at', ascending: false);

      final transactions = List<Map<String, dynamic>>.from(
        (response as List).map(
          (row) => Map<String, dynamic>.from(row),
        ),
      );

      // Pengeluaran memakai rentang tanggal yang sama dengan laporan.
      // expense_date diasumsikan bertipe DATE pada tabel expenses.
      final startDate = _startOfPeriod().toIso8601String().split('T').first;
      final endDate = _endOfPeriod().toIso8601String().split('T').first;

      final expenseResponse = await _supabase
          .from('expenses')
          .select(
            'id, amount, category, description, expense_date, payment_method',
          )
          .gte('expense_date', startDate)
          .lt('expense_date', endDate)
          .order('expense_date', ascending: false);

      final expenses = List<Map<String, dynamic>>.from(
        (expenseResponse as List).map(
          (row) => Map<String, dynamic>.from(row),
        ),
      );

      final itemsByTransaction =
          <String, List<Map<String, dynamic>>>{};
      final costsByItem = <String, Map<String, dynamic>>{};

      if (transactions.isNotEmpty) {
        final transactionIds = transactions
            .map((transaction) => transaction['id'].toString())
            .toList();

        final itemResponse = await _supabase
            .from('transaction_items')
            .select(
              'id, transaction_id, product_id, product_name, '
              'selling_price, quantity, subtotal',
            )
            .inFilter('transaction_id', transactionIds);

        final items = List<Map<String, dynamic>>.from(
          (itemResponse as List).map(
            (row) => Map<String, dynamic>.from(row),
          ),
        );

        for (final item in items) {
          final transactionId = item['transaction_id']?.toString();
          if (transactionId == null) continue;
          itemsByTransaction
              .putIfAbsent(transactionId, () => [])
              .add(item);
        }

        if (items.isNotEmpty) {
          final itemIds = items
              .map((item) => item['id'].toString())
              .toSet()
              .toList();

          // Prioritas pertama: modal historis transaksi.
          final costResponse = await _supabase
              .from('transaction_item_costs')
              .select(
                'transaction_item_id, purchase_price, total_cost',
              )
              .inFilter('transaction_item_id', itemIds);

          for (final row in costResponse as List) {
            final cost = Map<String, dynamic>.from(row);
            final itemId = cost['transaction_item_id']?.toString();
            if (itemId != null) costsByItem[itemId] = cost;
          }

          // Cadangan: modal produk saat ini untuk item tanpa modal historis.
          final productIds = items
              .map((item) => item['product_id']?.toString())
              .whereType<String>()
              .where((id) => id.isNotEmpty)
              .toSet()
              .toList();

          final currentCosts = <String, int>{};

          if (productIds.isNotEmpty) {
            final productCostResponse = await _supabase
                .from('product_costs')
                .select('product_id, purchase_price')
                .inFilter('product_id', productIds);

            for (final row in productCostResponse as List) {
              final cost = Map<String, dynamic>.from(row);
              final productId = cost['product_id']?.toString();
              if (productId != null && cost['purchase_price'] != null) {
                currentCosts[productId] = _toInt(cost['purchase_price']);
              }
            }
          }

          for (final item in items) {
            final itemId = item['id']?.toString();
            final productId = item['product_id']?.toString();
            if (itemId == null) continue;

            final quantity = _toInt(item['quantity']);
            final existingCost = costsByItem[itemId];

            if (existingCost != null) {
              final historicalTotalCost = existingCost['total_cost'];
              final historicalPurchasePrice =
                  existingCost['purchase_price'];

              if (historicalTotalCost != null) continue;

              if (historicalPurchasePrice != null) {
                existingCost['total_cost'] =
                    _toInt(historicalPurchasePrice) * quantity;
                continue;
              }
            }

            if (productId != null && currentCosts.containsKey(productId)) {
              final purchasePrice = currentCosts[productId]!;
              costsByItem[itemId] = {
                'transaction_item_id': itemId,
                'purchase_price': purchasePrice,
                'total_cost': purchasePrice * quantity,
                '_is_fallback': true,
              };
            }
          }
        }
      }

      var itemsWithoutCost = 0;
      for (final items in itemsByTransaction.values) {
        for (final item in items) {
          final itemId = item['id']?.toString();
          if (itemId == null || !_hasValidCost(costsByItem[itemId])) {
            itemsWithoutCost++;
          }
        }
      }

      if (!mounted) return;

      setState(() {
        _transactions = transactions;
        _expenses = expenses;
        _transactionItems
          ..clear()
          ..addAll(itemsByTransaction);
        _itemCosts
          ..clear()
          ..addAll(costsByItem);
        _itemsWithoutCost = itemsWithoutCost;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = e.toString();
      });
    }
  }

  int _toInt(dynamic value) {
    if (value is num) return value.round();
    final text = value?.toString() ?? '';
    return int.tryParse(text) ??
        double.tryParse(text)?.round() ??
        0;
  }

  int _transactionTotal(Map<String, dynamic> transaction) {
    return _toInt(transaction['total']);
  }

  String _paymentMethod(Map<String, dynamic> transaction) {
    return (transaction['payment_method'] ?? 'cash')
        .toString()
        .toLowerCase()
        .trim();
  }

  String _invoice(Map<String, dynamic> transaction) {
    return (transaction['invoice_number'] ??
            transaction['invoice'] ??
            transaction['id'] ??
            '-')
        .toString();
  }

  String _customer(Map<String, dynamic> transaction) {
    final value = transaction['customer_name']?.toString().trim() ?? '';
    return value.isEmpty ? 'Umum' : value;
  }

  DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value.toLocal();
    return DateTime.tryParse(value.toString())?.toLocal();
  }

  String _timeLabel(dynamic value) {
    final date = _parseDate(value);
    if (date == null) return '-';
    return '${date.hour.toString().padLeft(2, '0')}:'
        '${date.minute.toString().padLeft(2, '0')}';
  }

  bool _hasValidCost(Map<String, dynamic>? cost) {
    if (cost == null) return false;
    return cost['total_cost'] != null ||
        cost['purchase_price'] != null;
  }

  int _itemTotalCost(
    Map<String, dynamic> item,
    Map<String, dynamic> cost,
  ) {
    if (cost['total_cost'] != null) {
      return _toInt(cost['total_cost']);
    }
    return _toInt(cost['purchase_price']) *
        _toInt(item['quantity']);
  }

  int _profit(Map<String, dynamic> transaction) {
    final transactionId = transaction['id']?.toString();
    if (transactionId == null) return 0;

    final items = _transactionItems[transactionId] ?? [];
    var totalProfit = 0;

    for (final item in items) {
      final itemId = item['id']?.toString();
      if (itemId == null) continue;

      final cost = _itemCosts[itemId];
      if (!_hasValidCost(cost)) continue;

      totalProfit += _toInt(item['subtotal']) -
          _itemTotalCost(item, cost!);
    }
    return totalProfit;
  }

  int get _totalSales {
    return _transactions.fold<int>(
      0,
      (sum, transaction) => sum + _transactionTotal(transaction),
    );
  }

  int get _totalHpp {
    var total = 0;
    for (final items in _transactionItems.values) {
      for (final item in items) {
        final itemId = item['id']?.toString();
        if (itemId == null) continue;
        final cost = _itemCosts[itemId];
        if (!_hasValidCost(cost)) continue;
        total += _itemTotalCost(item, cost!);
      }
    }
    return total;
  }

  int get _totalExpenses {
    return _expenses.fold<int>(
      0,
      (sum, expense) => sum + _toInt(expense['amount']),
    );
  }

  int get _grossProfit => _totalSales - _totalHpp;
  int get _netProfit => _grossProfit - _totalExpenses;

  int get _cashTotal {
    return _transactions.fold<int>(0, (sum, transaction) {
      if (_paymentMethod(transaction) != 'cash') return sum;
      return sum + _transactionTotal(transaction);
    });
  }

  int get _qrisTotal {
    return _transactions.fold<int>(0, (sum, transaction) {
      if (_paymentMethod(transaction) != 'qris') return sum;
      return sum + _transactionTotal(transaction);
    });
  }

  int get _totalQuantity {
    var quantity = 0;
    for (final items in _transactionItems.values) {
      for (final item in items) {
        quantity += _toInt(item['quantity']);
      }
    }
    return quantity;
  }

  String _rupiah(num value) {
    final digits = value.abs().round().toString();
    final buffer = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      buffer.write(digits[i]);
      final remaining = digits.length - i - 1;
      if (remaining > 0 && remaining % 3 == 0) {
        buffer.write('.');
      }
    }
    return '${value < 0 ? '-' : ''}Rp $buffer';
  }

  String _dateLabel(DateTime date) {
    const months = [
      'Januari', 'Februari', 'Maret', 'April', 'Mei', 'Juni',
      'Juli', 'Agustus', 'September', 'Oktober', 'November', 'Desember',
    ];
    return '${date.day} ${months[date.month - 1]} ${date.year}';
  }

  String _monthLabel(DateTime date) {
    const months = [
      'Januari', 'Februari', 'Maret', 'April', 'Mei', 'Juni',
      'Juli', 'Agustus', 'September', 'Oktober', 'November', 'Desember',
    ];
    return '${months[date.month - 1]} ${date.year}';
  }

  String get _periodLabel => _period == 'Bulanan'
      ? _monthLabel(_selectedDate)
      : _dateLabel(_selectedDate);

  Future<void> _chooseDate() async {
    final now = DateTime.now();
    final selected = await showDatePicker(
      context: context,
      initialDate: _selectedDate.isAfter(now) ? now : _selectedDate,
      firstDate: DateTime(2020),
      lastDate: now,
      helpText: _period == 'Bulanan'
          ? 'Pilih bulan laporan'
          : 'Pilih tanggal laporan',
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(primary: _primary),
          ),
          child: child!,
        );
      },
    );

    if (selected == null || !mounted) return;
    setState(() => _selectedDate = selected);
    await _loadTransactions();
  }

  Future<void> _changePeriod(String period) async {
    if (_period == period) return;
    setState(() => _period = period);
    await _loadTransactions();
  }

  @override
  Widget build(BuildContext context) {
    final costIsIncomplete = _itemsWithoutCost > 0;
    final profitValue = costIsIncomplete
        ? 'Belum lengkap'
        : _rupiah(_grossProfit);
    final netProfitValue = costIsIncomplete
        ? 'Belum lengkap'
        : _rupiah(_netProfit);

    return Scaffold(
      backgroundColor: _background,
      appBar: AppBar(
        title: const Text('Laporan'),
        backgroundColor: _primary,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            tooltip: 'Muat ulang',
            onPressed: _loadTransactions,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: _primary),
            )
          : _errorMessage != null
              ? _buildError()
              : RefreshIndicator(
                  color: _primary,
                  onRefresh: _loadTransactions,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      _buildPeriodSelector(),
                      const SizedBox(height: 12),
                      _buildDateSelector(),
                      const SizedBox(height: 14),

                      // Urutan laporan: Omzet -> HPP -> Laba Kotor
                      // -> Pengeluaran -> Laba Bersih.
                      _summaryCard(
                        'Omzet $_period',
                        _rupiah(_totalSales),
                        Icons.payments_outlined,
                        _green,
                        const Color(0xFFDCFCE7),
                      ),
                      const SizedBox(height: 10),
                      _summaryCard(
                        'HPP $_period',
                        costIsIncomplete
                            ? 'Belum lengkap'
                            : _rupiah(_totalHpp),
                        Icons.inventory_2_outlined,
                        _orange,
                        const Color(0xFFFFF7ED),
                      ),
                      const SizedBox(height: 10),
                      _summaryCard(
                        'Laba Kotor $_period',
                        profitValue,
                        Icons.trending_up_rounded,
                        _primary,
                        const Color(0xFFEFF6FF),
                      ),
                      const SizedBox(height: 10),
                      _summaryCard(
                        'Pengeluaran $_period',
                        _rupiah(_totalExpenses),
                        Icons.money_off_csred_outlined,
                        _red,
                        const Color(0xFFFEE2E2),
                      ),
                      const SizedBox(height: 10),
                      _summaryCard(
                        'Laba Bersih $_period',
                        netProfitValue,
                        Icons.account_balance_wallet_outlined,
                        _netProfit >= 0 ? _green : _red,
                        _netProfit >= 0
                            ? const Color(0xFFDCFCE7)
                            : const Color(0xFFFEE2E2),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: _smallSummary(
                              'Cash',
                              _rupiah(_cashTotal),
                              Icons.payments_outlined,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _smallSummary(
                              'QRIS',
                              _rupiah(_qrisTotal),
                              Icons.qr_code_2_rounded,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: _smallSummary(
                              'Jumlah Transaksi',
                              _transactions.length.toString(),
                              Icons.receipt_long_outlined,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _smallSummary(
                              'Produk Terjual',
                              _totalQuantity.toString(),
                              Icons.inventory_2_outlined,
                            ),
                          ),
                        ],
                      ),
                      if (_itemsWithoutCost > 0) ...[
                        const SizedBox(height: 12),
                        _buildCostWarning(),
                      ],
                      const SizedBox(height: 14),
                      _buildTransactionList(),
                      const SizedBox(height: 16),
                      const Text(
                        'Laporan dihitung dengan urutan omzet dikurangi '
                        'harga pokok penjualan (HPP) untuk mendapatkan '
                        'laba kotor. Laba kotor kemudian dikurangi '
                        'pengeluaran untuk mendapatkan laba bersih. '
                        'Modal historis dari transaction_item_costs '
                        'diutamakan; product_costs digunakan sebagai '
                        'cadangan jika modal historis tidak tersedia.',
                        style: TextStyle(fontSize: 11, color: _muted),
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
            const Icon(
              Icons.error_outline_rounded,
              size: 44,
              color: Colors.red,
            ),
            const SizedBox(height: 12),
            const Text(
              'Gagal memuat laporan dari Supabase.',
              textAlign: TextAlign.center,
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 8),
            Text(
              _errorMessage ?? '',
              textAlign: TextAlign.center,
              style: const TextStyle(color: _muted, fontSize: 12),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _loadTransactions,
              icon: const Icon(Icons.refresh),
              label: const Text('Coba Lagi'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _primary,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPeriodSelector() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _border),
      ),
      child: Row(
        children: [
          Expanded(child: _periodButton('Harian')),
          Expanded(child: _periodButton('Bulanan')),
        ],
      ),
    );
  }

  Widget _periodButton(String period) {
    final selected = _period == period;
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => _changePeriod(period),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: selected ? _primary : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          period,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: selected ? Colors.white : _muted,
          ),
        ),
      ),
    );
  }

  Widget _buildDateSelector() {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: _chooseDate,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _border),
        ),
        child: Row(
          children: [
            const Icon(Icons.calendar_month_outlined, color: _primary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _period == 'Bulanan'
                        ? 'Bulan laporan'
                        : 'Tanggal laporan',
                    style: const TextStyle(fontSize: 12, color: _muted),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    _periodLabel,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: _text,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.keyboard_arrow_down_rounded, color: _muted),
          ],
        ),
      ),
    );
  }

  Widget _buildCostWarning() {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBEB),
        border: Border.all(color: const Color(0xFFFDE68A)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.warning_amber_rounded,
            color: Color(0xFFB45309),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Ada $_itemsWithoutCost item transaksi tanpa data modal. '
              'HPP, laba kotor, dan laba bersih belum dapat dihitung '
              'secara lengkap. Periksa tabel transaction_item_costs '
              'dan product_costs.',
              style: const TextStyle(
                color: Color(0xFF92400E),
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTransactionList() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Transaksi (${_transactions.length})',
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: _text,
            ),
          ),
          const SizedBox(height: 8),
          if (_transactions.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text(
                  'Belum ada transaksi pada periode ini.',
                  style: TextStyle(color: _muted),
                ),
              ),
            )
          else
            ..._transactions.map(_buildTransactionRow),
        ],
      ),
    );
  }

  Widget _buildTransactionRow(Map<String, dynamic> transaction) {
    final transactionId = transaction['id']?.toString() ?? '';
    final transactionProfit = _profit(transaction);
    final isQris = _paymentMethod(transaction) == 'qris';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 11),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: const Color(0xFFEFF6FF),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.receipt_long_outlined,
              color: _primary,
              size: 21,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _invoice(transaction),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: _text,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${_customer(transaction)} • '
                  '${_timeLabel(transaction['created_at'])}',
                  style: const TextStyle(fontSize: 11, color: _muted),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: isQris
                            ? const Color(0xFFF3E8FF)
                            : const Color(0xFFDCFCE7),
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: Text(
                        isQris ? 'QRIS' : 'Cash',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: isQris
                              ? const Color(0xFF7C3AED)
                              : const Color(0xFF15803D),
                        ),
                      ),
                    ),
                    const SizedBox(width: 7),
                    Flexible(
                      child: Text(
                        'Laba: ${_rupiah(transactionProfit)}',
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11,
                          color: _green,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '${(_transactionItems[transactionId] ?? []).length} '
                  'jenis produk',
                  style: const TextStyle(fontSize: 11, color: _muted),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              _rupiah(_transactionTotal(transaction)),
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: _text,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _summaryCard(
    String title,
    String value,
    IconData icon,
    Color iconColor,
    Color iconBackground,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _border),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: iconBackground,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: iconColor),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                fontSize: 13,
                color: _muted,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.bold,
                color: _text,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _smallSummary(String title, String value, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: _muted),
          const SizedBox(height: 8),
          Text(
            title,
            style: const TextStyle(fontSize: 12, color: _muted),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: _text,
            ),
          ),
        ],
      ),
    );
  }
}

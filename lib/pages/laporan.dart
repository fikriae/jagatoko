
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class LaporanPage extends StatefulWidget {
  const LaporanPage({super.key});

  @override
  State<LaporanPage> createState() => _LaporanPageState();
}

class _LaporanPageState extends State<LaporanPage> {
  final SupabaseClient _supabase = Supabase.instance.client;

  DateTime _selectedDate = DateTime.now();

  bool _isLoading = true;
  String? _errorMessage;

  List<Map<String, dynamic>> _transactions = [];
  final Map<String, List<Map<String, dynamic>>> _transactionItems = {};

  @override
  void initState() {
    super.initState();
    _loadTransactions();
  }

  Future<void> _loadTransactions() async {
    if (mounted) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    }

    try {
      final start = DateTime(
        _selectedDate.year,
        _selectedDate.month,
        _selectedDate.day,
      );

      final end = start.add(const Duration(days: 1));

      final response = await _supabase
          .from('transactions')
          .select()
          .gte('created_at', start.toIso8601String())
          .lt('created_at', end.toIso8601String())
          .order('created_at', ascending: false);

      final transactions = List<Map<String, dynamic>>.from(response);

      final itemsByTransaction = <String, List<Map<String, dynamic>>>{};

      if (transactions.isNotEmpty) {
        final transactionIds = transactions
            .map((transaction) => transaction['id'].toString())
            .toList();

        final itemResponse = await _supabase
            .from('transaction_items')
            .select()
            .inFilter('transaction_id', transactionIds);

        for (final rawItem in itemResponse) {
          final item = Map<String, dynamic>.from(rawItem);
          final transactionId = item['transaction_id']?.toString();

          if (transactionId == null) continue;

          itemsByTransaction
              .putIfAbsent(transactionId, () => [])
              .add(item);
        }
      }

      if (!mounted) return;

      setState(() {
        _transactions = transactions;
        _transactionItems
          ..clear()
          ..addAll(itemsByTransaction);
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
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  int _firstAvailableInt(
    Map<String, dynamic> data,
    List<String> keys,
  ) {
    for (final key in keys) {
      if (data.containsKey(key) && data[key] != null) {
        return _toInt(data[key]);
      }
    }

    return 0;
  }

  int _profit(Map<String, dynamic> transaction) {
    final transactionId = transaction['id']?.toString();

    if (transactionId == null) return 0;

    final items = _transactionItems[transactionId] ?? [];

    var totalProfit = 0;

    for (final item in items) {
      final sellingPrice = _firstAvailableInt(
        item,
        [
          'selling_price',
          'price',
          'sellingPrice',
          'harga_jual',
          'hargaJual',
        ],
      );

      final purchasePrice = _firstAvailableInt(
        item,
        [
          'purchase_price',
          'cost_price',
          'buy_price',
          'purchasePrice',
          'costPrice',
          'buyPrice',
          'harga_kulak',
          'harga_beli',
          'hargaKulak',
          'hargaBeli',
          'modal',
        ],
      );

      final quantity = _toInt(item['quantity']);

      totalProfit += (sellingPrice - purchasePrice) * quantity;
    }

    return totalProfit;
  }

  String _rupiah(int value) {
    final digits = value.abs().toString();
    final buffer = StringBuffer();

    for (var i = 0; i < digits.length; i++) {
      buffer.write(digits[i]);

      final remaining = digits.length - i - 1;

      if (remaining > 0 && remaining % 3 == 0) {
        buffer.write('.');
      }
    }

    return '${value < 0 ? '-' : ''}Rp ${buffer.toString()}';
  }

  String _dateLabel(DateTime date) {
    const months = [
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

    return '${date.day} ${months[date.month - 1]} ${date.year}';
  }

  String _timeLabel(dynamic value) {
    if (value == null) return '-';

    DateTime? date;

    if (value is DateTime) {
      date = value;
    } else {
      date = DateTime.tryParse(value.toString());
    }

    if (date == null) return '-';

    return '${date.hour.toString().padLeft(2, '0')}:'
        '${date.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _chooseDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Color(0xFF2563EB),
            ),
          ),
          child: child!,
        );
      },
    );

    if (date != null && mounted) {
      setState(() {
        _selectedDate = date;
      });

      await _loadTransactions();
    }
  }

  String _paymentMethod(Map<String, dynamic> transaction) {
    return (transaction['payment_method'] ??
            transaction['paymentMethod'] ??
            'cash')
        .toString()
        .toLowerCase()
        .trim();
  }

  int _transactionTotal(Map<String, dynamic> transaction) {
    return _firstAvailableInt(
      transaction,
      ['total', 'grand_total', 'grandTotal'],
    );
  }

  String _invoice(Map<String, dynamic> transaction) {
    return (transaction['invoice_number'] ??
            transaction['invoice'] ??
            transaction['invoiceNumber'] ??
            transaction['id'] ??
            '-')
        .toString();
  }

  String _customer(Map<String, dynamic> transaction) {
    return (transaction['customer_name'] ??
            transaction['customerName'] ??
            'Umum')
        .toString();
  }

  @override
  Widget build(BuildContext context) {
    final sales = _transactions.fold<int>(
      0,
      (total, transaction) => total + _transactionTotal(transaction),
    );

    final profit = _transactions.fold<int>(
      0,
      (total, transaction) => total + _profit(transaction),
    );

    final cash = _transactions.fold<int>(
      0,
      (total, transaction) {
        return total +
            (_paymentMethod(transaction) == 'cash'
                ? _transactionTotal(transaction)
                : 0);
      },
    );

    final qris = _transactions.fold<int>(
      0,
      (total, transaction) {
        return total +
            (_paymentMethod(transaction) == 'qris'
                ? _transactionTotal(transaction)
                : 0);
      },
    );

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: const Text('Laporan'),
        backgroundColor: const Color(0xFF2563EB),
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
              child: CircularProgressIndicator(
                color: Color(0xFF2563EB),
              ),
            )
          : _errorMessage != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.error_outline_rounded,
                          size: 42,
                          color: Colors.red,
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'Gagal memuat laporan dari Supabase.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _errorMessage!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Color(0xFF64748B),
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton.icon(
                          onPressed: _loadTransactions,
                          icon: const Icon(Icons.refresh),
                          label: const Text('Coba Lagi'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF2563EB),
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              : RefreshIndicator(
                  color: const Color(0xFF2563EB),
                  onRefresh: _loadTransactions,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      InkWell(
                        borderRadius: BorderRadius.circular(16),
                        onTap: _chooseDate,
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: const Color(0xFFE5E7EB),
                            ),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.calendar_month_outlined,
                                color: Color(0xFF2563EB),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'Tanggal laporan',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Color(0xFF64748B),
                                      ),
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      _dateLabel(_selectedDate),
                                      style: const TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.bold,
                                        color: Color(0xFF1E293B),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const Icon(
                                Icons.keyboard_arrow_down_rounded,
                                color: Color(0xFF64748B),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      _summaryCard(
                        'Omset',
                        _rupiah(sales),
                        Icons.payments_outlined,
                        const Color(0xFF16A34A),
                        const Color(0xFFDCFCE7),
                      ),
                      const SizedBox(height: 10),
                      _summaryCard(
                        'Total Laba',
                        _rupiah(profit),
                        Icons.trending_up_rounded,
                        const Color(0xFF2563EB),
                        const Color(0xFFEFF6FF),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: _smallSummary(
                              'Cash',
                              _rupiah(cash),
                              Icons.payments_outlined,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _smallSummary(
                              'QRIS',
                              _rupiah(qris),
                              Icons.qr_code_2_rounded,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: const Color(0xFFE5E7EB),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Transaksi (${_transactions.length})',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF1E293B),
                              ),
                            ),
                            const SizedBox(height: 8),
                            if (_transactions.isEmpty)
                              const Padding(
                                padding: EdgeInsets.symmetric(vertical: 24),
                                child: Center(
                                  child: Text(
                                    'Belum ada transaksi pada tanggal ini.',
                                    style: TextStyle(
                                      color: Color(0xFF64748B),
                                    ),
                                  ),
                                ),
                              )
                            else
                              ..._transactions.map((data) {
                                final transactionProfit = _profit(data);

                                return Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 10,
                                  ),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Container(
                                        width: 38,
                                        height: 38,
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFEFF6FF),
                                          borderRadius:
                                              BorderRadius.circular(10),
                                        ),
                                        child: const Icon(
                                          Icons.receipt_long_outlined,
                                          color: Color(0xFF2563EB),
                                          size: 20,
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              _invoice(data),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                fontSize: 13,
                                                fontWeight: FontWeight.bold,
                                                color: Color(0xFF1E293B),
                                              ),
                                            ),
                                            const SizedBox(height: 3),
                                            Text(
                                              '${_customer(data)} • '
                                              '${_timeLabel(data['created_at'] ?? data['createdAt'])}',
                                              style: const TextStyle(
                                                fontSize: 11,
                                                color: Color(0xFF64748B),
                                              ),
                                            ),
                                            Text(
                                              'Laba: ${_rupiah(transactionProfit)}',
                                              style: const TextStyle(
                                                fontSize: 11,
                                                color: Color(0xFF16A34A),
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        _rupiah(_transactionTotal(data)),
                                        style: const TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                          color: Color(0xFF1E293B),
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              }),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Catatan: laba dihitung dari harga jual dikurangi '
                        'harga kulak, kemudian dikalikan jumlah barang. '
                        'Detail item transaksi harus menyimpan harga jual '
                        'dan harga kulak agar laba dapat dihitung dengan benar.',
                        style: TextStyle(
                          fontSize: 11,
                          color: Color(0xFF64748B),
                        ),
                      ),
                    ],
                  ),
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
        border: Border.all(
          color: const Color(0xFFE5E7EB),
        ),
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
                color: Color(0xFF64748B),
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
                color: Color(0xFF1E293B),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _smallSummary(
    String title,
    String value,
    IconData icon,
  ) {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: const Color(0xFFE5E7EB),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            icon,
            size: 20,
            color: const Color(0xFF64748B),
          ),
          const SizedBox(height: 8),
          Text(
            title,
            style: const TextStyle(
              fontSize: 12,
              color: Color(0xFF64748B),
            ),
          ),
          const SizedBox(height: 3),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: Color(0xFF1E293B),
            ),
          ),
        ],
      ),
    );
  }
}

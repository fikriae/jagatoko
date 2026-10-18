import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

const Color _primary = Color(0xFF2563EB);
const Color _background = Color(0xFFF5F7FA);
const Color _border = Color(0xFFE5E7EB);
const Color _secondaryText = Color(0xFF64748B);
const Color _danger = Color(0xFFDC2626);

class RiwayatPage extends StatefulWidget {
  const RiwayatPage({super.key});

  @override
  State<RiwayatPage> createState() => _RiwayatPageState();
}

class _RiwayatPageState extends State<RiwayatPage> {
  final SupabaseClient _supabase = Supabase.instance.client;
  final TextEditingController _searchController = TextEditingController();

  String _searchQuery = '';
  String _paymentFilter = 'semua';
  bool _isRefreshing = false;

  late final Stream<List<Map<String, dynamic>>> _transactionsStream;

  @override
  void initState() {
    super.initState();

    _transactionsStream = _supabase
        .from('transactions')
        .stream(primaryKey: ['id'])
        .eq('is_hidden', false)
        .order('created_at', ascending: false);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  int _toInt(dynamic value) {
    if (value is num) return value.round();

    final text = value?.toString().trim() ?? '';
    return int.tryParse(text) ??
        double.tryParse(text)?.round() ??
        0;
  }

  String _rupiah(num value) {
    final digits = value.abs().round().toString();
    final result = StringBuffer();

    for (int i = 0; i < digits.length; i++) {
      result.write(digits[i]);

      final remaining = digits.length - i - 1;
      if (remaining > 0 && remaining % 3 == 0) {
        result.write('.');
      }
    }

    return '${value < 0 ? '-' : ''}Rp ${result.toString()}';
  }

  DateTime? _date(dynamic value) {
    if (value == null) return null;

    if (value is DateTime) return value.toLocal();

    return DateTime.tryParse(value.toString())?.toLocal();
  }

  String _dateTime(dynamic value) {
    final date = _date(value);
    if (date == null) return '-';

    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');
    final year = date.year.toString();
    final hour = date.hour.toString().padLeft(2, '0');
    final minute = date.minute.toString().padLeft(2, '0');

    return '$day/$month/$year, $hour:$minute';
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

  String _invoice(Map<String, dynamic> data) {
    return (data['invoice'] ??
            data['invoice_number'] ??
            data['id'] ??
            '-')
        .toString();
  }

  String _customer(Map<String, dynamic> data) {
    final value =
        (data['customer_name'] ?? data['customerName'] ?? 'Umum')
            .toString()
            .trim();

    return value.isEmpty ? 'Umum' : value;
  }

  String _paymentMethod(Map<String, dynamic> data) {
    return (data['payment_method'] ?? data['paymentMethod'] ?? 'cash')
        .toString()
        .toLowerCase();
  }

  List<Map<String, dynamic>> _filterTransactions(
    List<Map<String, dynamic>> transactions,
  ) {
    final query = _searchQuery.trim().toLowerCase();

    return transactions.where((transaction) {
      final invoice = _invoice(transaction).toLowerCase();
      final customer = _customer(transaction).toLowerCase();
      final method = _paymentMethod(transaction);

      final matchesSearch =
          query.isEmpty ||
          invoice.contains(query) ||
          customer.contains(query);

      final matchesPayment =
          _paymentFilter == 'semua' ||
          (_paymentFilter == 'cash' &&
              (method == 'cash' || method == 'tunai')) ||
          (_paymentFilter == 'qris' && method == 'qris');

      return matchesSearch && matchesPayment;
    }).toList();
  }

  Future<void> _hideTransaction(
    Map<String, dynamic> transaction,
  ) async {
    final id = transaction['id']?.toString();

    if (id == null || id.isEmpty) {
      _showMessage('ID transaksi tidak ditemukan.', isError: true);
      return;
    }

    final invoice = _invoice(transaction);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: const Text('Sembunyikan transaksi?'),
        content: Text(
          'Transaksi $invoice akan disembunyikan dari halaman Riwayat. '
          'Data tetap tersimpan di database Supabase.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: _danger,
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Sembunyikan'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _isRefreshing = true);

    try {
      await _supabase
          .from('transactions')
          .update({'is_hidden': true})
          .eq('id', id);

      if (!mounted) return;

      _showMessage('Transaksi berhasil disembunyikan.');
    } catch (e) {
      if (!mounted) return;

      _showMessage(
        'Gagal menyembunyikan transaksi: $e',
        isError: true,
      );
    } finally {
      if (mounted) {
        setState(() => _isRefreshing = false);
      }
    }
  }

  void _showMessage(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: isError ? _danger : const Color(0xFF15803D),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  Future<void> _openDetail(
    Map<String, dynamic> transaction,
  ) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TransactionDetailPage(
          transactionId: transaction['id'].toString(),
          data: transaction,
        ),
      ),
    );
  }

  Widget _paymentBadge(String method) {
    final isQris = method == 'qris';

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 9,
        vertical: 5,
      ),
      decoration: BoxDecoration(
        color: isQris
            ? const Color(0xFFF3E8FF)
            : const Color(0xFFDCFCE7),
        borderRadius: BorderRadius.circular(7),
      ),
      child: Text(
        isQris ? 'QRIS' : 'Cash',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: isQris
              ? const Color(0xFF7C3AED)
              : const Color(0xFF15803D),
        ),
      ),
    );
  }

  Widget _buildTransactionCard(
    Map<String, dynamic> transaction,
  ) {
    final method = _paymentMethod(transaction);
    final total = _toInt(transaction['total']);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: _border),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(15),
        onTap: () => _openDetail(transaction),
        child: Padding(
          padding: const EdgeInsets.all(15),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 43,
                    height: 43,
                    decoration: BoxDecoration(
                      color: const Color(0xFFEFF6FF),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.receipt_long,
                      color: _primary,
                    ),
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _invoice(transaction),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _dateTime(
                            transaction['created_at'] ??
                                transaction['createdAt'],
                          ),
                          style: const TextStyle(
                            fontSize: 12,
                            color: _secondaryText,
                          ),
                        ),
                      ],
                    ),
                  ),
                  PopupMenuButton<String>(
                    tooltip: 'Pilihan transaksi',
                    onSelected: (value) {
                      if (value == 'hide') {
                        _hideTransaction(transaction);
                      } else if (value == 'detail') {
                        _openDetail(transaction);
                      }
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(
                        value: 'detail',
                        child: Row(
                          children: [
                            Icon(Icons.visibility_outlined),
                            SizedBox(width: 9),
                            Text('Lihat detail'),
                          ],
                        ),
                      ),
                      PopupMenuItem(
                        value: 'hide',
                        child: Row(
                          children: [
                            Icon(
                              Icons.visibility_off_outlined,
                              color: _danger,
                            ),
                            SizedBox(width: 9),
                            Text(
                              'Sembunyikan',
                              style: TextStyle(color: _danger),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const Divider(height: 25),
              Row(
                children: [
                  const Icon(
                    Icons.person_outline,
                    size: 17,
                    color: _secondaryText,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      _customer(transaction),
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                  _paymentBadge(method),
                ],
              ),
              const SizedBox(height: 13),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Total transaksi',
                    style: TextStyle(
                      color: _secondaryText,
                      fontSize: 12,
                    ),
                  ),
                  Text(
                    _rupiah(total),
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: _primary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 5),
              const Align(
                alignment: Alignment.centerRight,
                child: Text(
                  'Ketuk untuk melihat detail',
                  style: TextStyle(
                    fontSize: 11,
                    color: _secondaryText,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState({
    required String title,
    required String message,
    IconData icon = Icons.receipt_long_outlined,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 60, color: const Color(0xFFCBD5E1)),
            const SizedBox(height: 15),
            Text(
              title,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 7),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: _secondaryText,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _background,
      appBar: AppBar(
        backgroundColor: _primary,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'Riwayat Transaksi',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          if (_isRefreshing)
            const Padding(
              padding: EdgeInsets.all(17),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 15, 16, 18),
            decoration: const BoxDecoration(
              color: _primary,
              borderRadius: BorderRadius.vertical(
                bottom: Radius.circular(22),
              ),
            ),
            child: TextField(
              controller: _searchController,
              onChanged: (value) {
                setState(() => _searchQuery = value);
              },
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Cari invoice atau pelanggan...',
                hintStyle: const TextStyle(color: Colors.white70),
                prefixIcon: const Icon(
                  Icons.search,
                  color: Colors.white,
                ),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _searchQuery = '');
                        },
                        icon: const Icon(
                          Icons.close,
                          color: Colors.white,
                        ),
                      )
                    : null,
                filled: true,
                fillColor: Colors.white.withValues(alpha: 0.14),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(13),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
            child: Row(
              children: [
                _filterChip('Semua', 'semua'),
                const SizedBox(width: 8),
                _filterChip('Cash', 'cash'),
                const SizedBox(width: 8),
                _filterChip('QRIS', 'qris'),
              ],
            ),
          ),
          Expanded(
            child: StreamBuilder<List<Map<String, dynamic>>>(
              stream: _transactionsStream,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return _buildEmptyState(
                    title: 'Gagal memuat riwayat',
                    message:
                        'Periksa koneksi, struktur kolom Supabase, '
                        'Realtime, dan kebijakan RLS.\n\n'
                        '${snapshot.error}',
                        icon: Icons.cloud_off_outlined,
                  );
                }

                if (snapshot.connectionState ==
                        ConnectionState.waiting &&
                    !snapshot.hasData) {
                  return const Center(
                    child: CircularProgressIndicator(color: _primary),
                  );
                }

                final allTransactions = snapshot.data ?? [];
                final transactions =
                    _filterTransactions(allTransactions);

                if (transactions.isEmpty) {
                  return _buildEmptyState(
                    title: _searchQuery.isNotEmpty ||
                            _paymentFilter != 'semua'
                        ? 'Transaksi tidak ditemukan'
                        : 'Belum ada transaksi',
                    message: _searchQuery.isNotEmpty ||
                            _paymentFilter != 'semua'
                        ? 'Coba ubah kata pencarian atau filter pembayaran.'
                        : 'Transaksi yang berhasil dibuat akan tampil di sini.',
                  );
                }

                final totalSales = transactions.fold<int>(
                  0,
                  (sum, item) => sum + _toInt(item['total']),
                );

                return ListView(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 22),
                  children: [
                    Container(
                      padding: const EdgeInsets.all(15),
                      margin: const EdgeInsets.only(bottom: 15),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: _border),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: const Color(0xFFDCFCE7),
                              borderRadius: BorderRadius.circular(11),
                            ),
                            child: const Icon(
                              Icons.trending_up,
                              color: Color(0xFF15803D),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Total hasil pencarian',
                                  style: TextStyle(
                                    color: _secondaryText,
                                    fontSize: 12,
                                  ),
                                ),
                                const SizedBox(height: 5),
                                Text(
                                  _rupiah(totalSales),
                                  style: const TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              const Text(
                                'Transaksi',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: _secondaryText,
                                ),
                              ),
                              Text(
                                '${transactions.length}',
                                style: const TextStyle(
                                  fontSize: 19,
                                  fontWeight: FontWeight.bold,
                                  color: _primary,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    ...transactions.map(_buildTransactionCard),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _filterChip(String label, String value) {
    final selected = _paymentFilter == value;

    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => setState(() => _paymentFilter = value),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 11),
          decoration: BoxDecoration(
            color: selected ? _primary : Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected ? _primary : _border,
            ),
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: selected ? Colors.white : _secondaryText,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class TransactionDetailPage extends StatefulWidget {
  final String transactionId;
  final Map<String, dynamic> data;

  const TransactionDetailPage({
    super.key,
    required this.transactionId,
    required this.data,
  });

  @override
  State<TransactionDetailPage> createState() =>
      _TransactionDetailPageState();
}

class _TransactionDetailPageState extends State<TransactionDetailPage> {
  final SupabaseClient _supabase = Supabase.instance.client;

  late Future<List<Map<String, dynamic>>> _itemsFuture;
  bool _isGeneratingPdf = false;

  @override
  void initState() {
    super.initState();
    _itemsFuture = _loadItems();
  }

  int _toInt(dynamic value) {
    if (value is num) return value.round();

    final text = value?.toString().trim() ?? '';
    return int.tryParse(text) ??
        double.tryParse(text)?.round() ??
        0;
  }

  String _rupiah(num value) {
    final digits = value.abs().round().toString();
    final result = StringBuffer();

    for (int i = 0; i < digits.length; i++) {
      result.write(digits[i]);

      final remaining = digits.length - i - 1;
      if (remaining > 0 && remaining % 3 == 0) {
        result.write('.');
      }
    }

    return '${value < 0 ? '-' : ''}Rp ${result.toString()}';
  }

  DateTime? _date(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value.toLocal();

    return DateTime.tryParse(value.toString())?.toLocal();
  }

  String _dateTime(dynamic value) {
    final date = _date(value);
    if (date == null) return '-';

    return '${date.day.toString().padLeft(2, '0')}/'
        '${date.month.toString().padLeft(2, '0')}/'
        '${date.year}, '
        '${date.hour.toString().padLeft(2, '0')}:'
        '${date.minute.toString().padLeft(2, '0')}';
  }

  String _invoice() {
    return (widget.data['invoice'] ??
            widget.data['invoice_number'] ??
            widget.transactionId)
        .toString();
  }

  String _customer() {
    final value =
        (widget.data['customer_name'] ??
                widget.data['customerName'] ??
                'Umum')
            .toString()
            .trim();

    return value.isEmpty ? 'Umum' : value;
  }

  String _paymentMethod() {
    return (widget.data['payment_method'] ??
            widget.data['paymentMethod'] ??
            'cash')
        .toString()
        .toLowerCase();
  }

  Future<List<Map<String, dynamic>>> _loadItems() async {
    final existingItems = widget.data['items'];

    if (existingItems is List && existingItems.isNotEmpty) {
      return existingItems
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
    }

    final response = await _supabase
        .from('transaction_items')
        .select()
        .eq('transaction_id', widget.transactionId);

    return List<Map<String, dynamic>>.from(response);
  }

  Future<void> _reloadItems() async {
    setState(() {
      _itemsFuture = _loadItems();
    });
  }

  void _showMessage(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? _danger : const Color(0xFF15803D),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<Uint8List> _generatePdf(
    List<Map<String, dynamic>> items,
  ) async {
    final pdf = pw.Document();

    final total = _toInt(widget.data['total']);
    final payment = _toInt(
      widget.data['payment'] ?? widget.data['amount_paid'],
    );
    final change = _toInt(
      widget.data['change'] ?? widget.data['change_amount'],
    );
    final method = _paymentMethod();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (context) => [
          pw.Center(
            child: pw.Column(
              children: [
                pw.Text(
                  'JAGATOKO',
                  style: pw.TextStyle(
                    fontSize: 24,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 5),
                pw.Text(
                  'Struk Transaksi',
                  style: const pw.TextStyle(
                    fontSize: 12,
                    color: PdfColors.grey700,
                  ),
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 22),
          pw.Divider(),
          _pdfInfo('Invoice', _invoice()),
          _pdfInfo(
            'Tanggal',
            _dateTime(
              widget.data['created_at'] ?? widget.data['createdAt'],
            ),
          ),
          _pdfInfo('Pelanggan', _customer()),
          _pdfInfo('Pembayaran', method == 'qris' ? 'QRIS' : 'Cash'),
          pw.SizedBox(height: 15),
          pw.Text(
            'Daftar Produk',
            style: pw.TextStyle(
              fontSize: 15,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(height: 10),
          if (items.isEmpty)
            pw.Text('Detail produk tidak tersedia.')
          else
            pw.Table(
              border: pw.TableBorder.all(color: PdfColors.grey300),
              columnWidths: {
                0: const pw.FlexColumnWidth(3),
                1: const pw.FlexColumnWidth(1),
                2: const pw.FlexColumnWidth(2),
                3: const pw.FlexColumnWidth(2),
              },
              children: [
                pw.TableRow(
                  decoration: const pw.BoxDecoration(
                    color: PdfColors.grey200,
                  ),
                  children: [
                    _pdfCell('Produk', bold: true),
                    _pdfCell('Qty', bold: true),
                    _pdfCell('Harga', bold: true),
                    _pdfCell('Subtotal', bold: true),
                  ],
                ),
                ...items.map((item) {
                  final name = (item['product_name'] ??
                          item['productName'] ??
                          item['name'] ??
                          'Produk')
                      .toString();

                  final quantity = _toInt(item['quantity']);
                  final price = _toInt(
                    item['selling_price'] ?? item['price'],
                  );

                  final subtotalValue = item['subtotal'];
                  final subtotal = subtotalValue == null
                      ? quantity * price
                      : _toInt(subtotalValue);

                  return pw.TableRow(
                    children: [
                      _pdfCell(name),
                      _pdfCell(quantity.toString()),
                      _pdfCell(_rupiah(price)),
                      _pdfCell(_rupiah(subtotal)),
                    ],
                  );
                }),
              ],
            ),
          pw.SizedBox(height: 18),
          pw.Divider(),
          _pdfSummary('Total', _rupiah(total), bold: true),
          if (method != 'qris') ...[
            _pdfSummary('Bayar', _rupiah(payment)),
            _pdfSummary('Kembalian', _rupiah(change)),
          ],
          pw.SizedBox(height: 25),
          pw.Center(
            child: pw.Text(
              'Terima kasih telah berbelanja di Jagatoko.',
              style: const pw.TextStyle(
                fontSize: 10,
                color: PdfColors.grey700,
              ),
            ),
          ),
        ],
      ),
    );

    return pdf.save();
  }

  pw.Widget _pdfInfo(String label, String value) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 4),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(label),
          pw.SizedBox(width: 15),
          pw.Expanded(
            child: pw.Text(
              value,
              textAlign: pw.TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _pdfCell(String value, {bool bold = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(7),
      child: pw.Text(
        value,
        style: pw.TextStyle(
          fontSize: 9,
          fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
        ),
      ),
    );
  }

  pw.Widget _pdfSummary(
    String label,
    String value, {
    bool bold = false,
  }) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 5),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            label,
            style: pw.TextStyle(
              fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
            ),
          ),
          pw.Text(
            value,
            style: pw.TextStyle(
              fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _sharePdf(
    List<Map<String, dynamic>> items,
  ) async {
    if (_isGeneratingPdf) return;

    setState(() => _isGeneratingPdf = true);

    try {
      final bytes = await _generatePdf(items);

      await Printing.sharePdf(
        bytes: bytes,
        filename: 'Struk-${_invoice()}.pdf',
      );
    } catch (e) {
      if (mounted) {
        _showMessage('Gagal membuat PDF: $e', isError: true);
      }
    } finally {
      if (mounted) {
        setState(() => _isGeneratingPdf = false);
      }
    }
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(color: _secondaryText),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  Widget _card({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _border),
      ),
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    final method = _paymentMethod();
    final total = _toInt(widget.data['total']);
    final payment = _toInt(
      widget.data['payment'] ?? widget.data['amount_paid'],
    );
    final change = _toInt(
      widget.data['change'] ?? widget.data['change_amount'],
    );

    return Scaffold(
      backgroundColor: _background,
      appBar: AppBar(
        backgroundColor: _primary,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('Detail Transaksi'),
        actions: [
          IconButton(
            tooltip: 'Muat ulang produk',
            onPressed: _reloadItems,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _itemsFuture,
        builder: (context, snapshot) {
          final items = snapshot.data ?? [];

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _card(
                child: Column(
                  children: [
                    const Icon(
                      Icons.receipt_long,
                      size: 45,
                      color: _primary,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      _invoice(),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      _dateTime(
                        widget.data['created_at'] ??
                            widget.data['createdAt'],
                      ),
                      style: const TextStyle(color: _secondaryText),
                    ),
                    const SizedBox(height: 16),
                    const Divider(),
                    _infoRow('Pelanggan', _customer()),
                    _infoRow(
                      'Kasir',
                      (widget.data['cashier_name'] ??
                              widget.data['cashierName'] ??
                              '-')
                          .toString(),
                    ),
                    _infoRow(
                      'Pembayaran',
                      method == 'qris' ? 'QRIS' : 'Cash',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              _card(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Daftar Produk',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 15),
                    if (snapshot.connectionState ==
                        ConnectionState.waiting)
                      const Center(
                        child: Padding(
                          padding: EdgeInsets.all(18),
                          child: CircularProgressIndicator(
                            color: _primary,
                          ),
                        ),
                      )
                    else if (snapshot.hasError)
                      Column(
                        children: [
                          const Text(
                            'Gagal memuat detail produk.',
                            style: TextStyle(color: _danger),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '${snapshot.error}',
                            style: const TextStyle(fontSize: 12),
                          ),
                          TextButton(
                            onPressed: _reloadItems,
                            child: const Text('Coba lagi'),
                          ),
                        ],
                      )
                    else if (items.isEmpty)
                      const Text(
                        'Detail produk tidak tersedia.',
                        style: TextStyle(color: _secondaryText),
                      )
                    else
                      ...items.map((item) {
                        final name = (item['product_name'] ??
                                item['productName'] ??
                                item['name'] ??
                                'Produk')
                            .toString();

                        final quantity = _toInt(item['quantity']);
                        final price = _toInt(
                          item['selling_price'] ?? item['price'],
                        );

                        final subtotal = item['subtotal'] == null
                            ? quantity * price
                            : _toInt(item['subtotal']);

                        return Padding(
                          padding: const EdgeInsets.only(bottom: 15),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  color: const Color(0xFFEFF6FF),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Icon(
                                  Icons.inventory_2_outlined,
                                  color: _primary,
                                ),
                              ),
                              const SizedBox(width: 11),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      name,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(height: 5),
                                    Text(
                                      '$quantity × ${_rupiah(price)}',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: _secondaryText,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                _rupiah(subtotal),
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        );
                      }),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              _card(
                child: Column(
                  children: [
                    _summaryRow('Total', _rupiah(total), bold: true),
                    if (method != 'qris') ...[
                      const SizedBox(height: 12),
                      _summaryRow('Bayar', _rupiah(payment)),
                      const SizedBox(height: 12),
                      _summaryRow('Kembalian', _rupiah(change)),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 18),
              SizedBox(
                height: 50,
                child: FilledButton.icon(
                  onPressed: snapshot.connectionState ==
                              ConnectionState.waiting ||
                          snapshot.hasError
                      ? null
                      : () => _sharePdf(items),
                  icon: _isGeneratingPdf
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.picture_as_pdf_outlined),
                  label: Text(
                    _isGeneratingPdf
                        ? 'Membuat PDF...'
                        : 'Bagikan Struk PDF',
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: _primary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _summaryRow(
    String label,
    String value, {
    bool bold = false,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontWeight: bold ? FontWeight.bold : FontWeight.normal,
          ),
        ),
        const SizedBox(width: 12),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: TextStyle(
              fontSize: bold ? 17 : 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const Color _primary = Color(0xFF2563EB);
const Color _background = Color(0xFFF5F7FA);
const Color _border = Color(0xFFE5E7EB);
const Color _muted = Color(0xFF64748B);
const Color _text = Color(0xFF0F172A);
const Color _success = Color(0xFF15803D);
const Color _purple = Color(0xFF7C3AED);

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
  late Future<Map<String, dynamic>> _detailFuture;

  @override
  void initState() {
    super.initState();
    _detailFuture = _loadDetail();
  }

  int _toInt(dynamic value) {
    if (value is num) return value.round();
    final text = value?.toString().trim() ?? '';
    return int.tryParse(text) ?? double.tryParse(text)?.round() ?? 0;
  }

  String _formatRupiah(num value) {
    final number = value.abs().round().toString();
    final result = StringBuffer();
    for (int i = 0; i < number.length; i++) {
      result.write(number[i]);
      final position = number.length - i - 1;
      if (position > 0 && position % 3 == 0) result.write('.');
    }
    return value < 0 ? '-Rp $result' : 'Rp $result';
  }

  DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value.toLocal();
    return DateTime.tryParse(value.toString())?.toLocal();
  }

  String _formatDate(dynamic value) {
    final date = _parseDate(value);
    if (date == null) return '-';
    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');
    final year = date.year.toString();
    final hour = date.hour.toString().padLeft(2, '0');
    final minute = date.minute.toString().padLeft(2, '0');
    final second = date.second.toString().padLeft(2, '0');
    return '$day/$month/$year, $hour:$minute:$second';
  }

  String _stringValue(dynamic value, {String fallback = '-'}) {
    final result = value?.toString().trim() ?? '';
    return result.isEmpty ? fallback : result;
  }

  Future<Map<String, dynamic>> _loadDetail() async {
    final transactionResponse = await _supabase
        .from('transactions')
        .select()
        .eq('id', widget.transactionId)
        .eq('is_hidden', false)
        .maybeSingle();

    if (transactionResponse == null) {
      throw Exception(
        'Transaksi tidak ditemukan atau sudah dihapus dari Riwayat.',
      );
    }

    final transaction = Map<String, dynamic>.from(transactionResponse);
    final cashierId = transaction['cashier_id'];
    String cashierName = _stringValue(
      widget.data['cashier_name'] ?? widget.data['_resolved_cashier_name'],
      fallback: '-',
    );

    if (cashierId != null && cashierId.toString().trim().isNotEmpty) {
      try {
        final profileResponse = await _supabase
            .from('profiles')
            .select('full_name')
            .eq('id', cashierId.toString())
            .maybeSingle();

        if (profileResponse != null) {
          cashierName = _stringValue(
            profileResponse['full_name'],
            fallback: cashierName,
          );
        }
      } catch (e) {
        debugPrint('Gagal mengambil nama kasir: $e');
      }
    }

    transaction['cashier_name'] = cashierName;

    final itemsResponse = await _supabase
        .from('transaction_items')
        .select()
        .eq('transaction_id', widget.transactionId);

    final items = List<Map<String, dynamic>>.from(
      (itemsResponse as List).map(
        (item) => Map<String, dynamic>.from(item),
      ),
    );

    return {'transaction': transaction, 'items': items};
  }

  Future<void> _reloadDetail() async {
    setState(() => _detailFuture = _loadDetail());
    try {
      await _detailFuture;
    } catch (_) {
      // Error ditampilkan oleh FutureBuilder.
    }
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
          'Detail Transaksi',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        actions: [
          IconButton(
            tooltip: 'Muat ulang detail',
            onPressed: _reloadDetail,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _detailFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: _primary),
            );
          }

          if (snapshot.hasError) {
            return Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 76,
                      height: 76,
                      decoration: BoxDecoration(
                        color: const Color(0xFFFEE2E2),
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: const Icon(
                        Icons.receipt_long_outlined,
                        color: Color(0xFFDC2626),
                        size: 38,
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Detail transaksi tidak dapat dimuat',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: _text,
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${snapshot.error}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: _muted,
                        fontSize: 12,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 18),
                    FilledButton.icon(
                      onPressed: _reloadDetail,
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

          final result = snapshot.data;
          if (result == null) {
            return const Center(child: Text('Data transaksi tidak tersedia.'));
          }

          final transaction =
              Map<String, dynamic>.from(result['transaction'] as Map);
          final items = List<Map<String, dynamic>>.from(result['items'] as List);
          return _buildContent(transaction, items);
        },
      ),
    );
  }

  Widget _buildContent(
    Map<String, dynamic> data,
    List<Map<String, dynamic>> items,
  ) {
    final invoice = _stringValue(
      data['invoice_number'] ?? data['invoice'],
      fallback: widget.transactionId,
    );
    final customer = _stringValue(data['customer_name'], fallback: 'Umum');
    final paymentMethod =
        _stringValue(data['payment_method'], fallback: 'cash').toLowerCase();
    final total = _toInt(data['total']);
    final subtotalTransaction = _toInt(data['subtotal'] ?? data['total']);
    final payment = _toInt(
      data['cash_received'] ?? data['payment'] ?? data['amount_paid'],
    );
    final change = _toInt(data['change_amount'] ?? data['change']);
    final createdAt = data['created_at'] ?? data['createdAt'];
    final cashierName = _stringValue(data['cashier_name']);
    final isQris = paymentMethod == 'qris';

    return RefreshIndicator(
      color: _primary,
      onRefresh: _reloadDetail,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
        children: [
          _buildInvoiceHeader(invoice, createdAt, total),
          const SizedBox(height: 14),
          _card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _sectionTitle(Icons.info_outline_rounded, 'Informasi Transaksi'),
                const SizedBox(height: 18),
                _infoRow(Icons.person_outline_rounded, 'Pelanggan', customer),
                const SizedBox(height: 16),
                _infoRow(Icons.badge_outlined, 'Kasir', cashierName),
                const SizedBox(height: 16),
                Row(
                  children: [
                    const Icon(Icons.payments_outlined, size: 19, color: _muted),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'Metode Pembayaran',
                        style: TextStyle(color: _muted, fontSize: 13),
                      ),
                    ),
                    _paymentBadge(isQris),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          _card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _sectionTitle(
                  Icons.shopping_bag_outlined,
                  'Daftar Produk',
                  trailing: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEFF6FF),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '${items.length} produk',
                      style: const TextStyle(
                        color: _primary,
                        fontWeight: FontWeight.w700,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                if (items.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 18),
                    child: Center(
                      child: Text(
                        'Detail produk tidak tersedia.',
                        style: TextStyle(color: _muted),
                      ),
                    ),
                  )
                else
                  ...items.asMap().entries.map(
                    (entry) => _buildProductItem(
                      entry.value,
                      isLast: entry.key == items.length - 1,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          _card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _sectionTitle(Icons.receipt_outlined, 'Rincian Pembayaran'),
                const SizedBox(height: 18),
                _summaryRow('Subtotal', _formatRupiah(subtotalTransaction)),
                const SizedBox(height: 13),
                _summaryRow('Total', _formatRupiah(total), bold: true),
                if (!isQris) ...[
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Divider(height: 1, color: _border),
                  ),
                  _summaryRow('Uang Diterima', _formatRupiah(payment)),
                  const SizedBox(height: 13),
                  _summaryRow('Kembalian', _formatRupiah(change)),
                ],
              ],
            ),
          ),
          const SizedBox(height: 10),
          const Center(
            child: Text(
              'JAGATOKO • Terima kasih telah berbelanja',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: _muted,
                fontSize: 11,
                letterSpacing: 0.2,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInvoiceHeader(String invoice, dynamic createdAt, int total) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [_primary, Color(0xFF1D4ED8)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: _primary.withValues(alpha: 0.18),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.receipt_long_rounded,
                  color: Colors.white,
                  size: 25,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'DETAIL PEMBELIAN',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.1,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Transaksi berhasil',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.verified_rounded, color: Colors.white70),
            ],
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 18),
            child: Divider(color: Color(0x66FFFFFF), height: 1),
          ),
          const Text(
            'Nomor Invoice',
            style: TextStyle(color: Colors.white70, fontSize: 12),
          ),
          const SizedBox(height: 5),
          Text(
            invoice,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 17,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(Icons.schedule_rounded, color: Colors.white70, size: 15),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  _formatDate(createdAt),
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'TOTAL PEMBAYARAN',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  _formatRupiah(total),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 25,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(
    IconData icon,
    String title, {
    Widget? trailing,
  }) {
    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: const Color(0xFFEFF6FF),
            borderRadius: BorderRadius.circular(11),
          ),
          child: Icon(icon, color: _primary, size: 19),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            title,
            style: const TextStyle(
              color: _text,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        if (trailing != null) trailing,
      ],
    );
  }

  Widget _paymentBadge(bool isQris) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      decoration: BoxDecoration(
        color: isQris ? const Color(0xFFF3E8FF) : const Color(0xFFDCFCE7),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isQris ? Icons.qr_code_2_rounded : Icons.payments_outlined,
            size: 15,
            color: isQris ? _purple : _success,
          ),
          const SizedBox(width: 5),
          Text(
            isQris ? 'QRIS' : 'Cash',
            style: TextStyle(
              color: isQris ? _purple : _success,
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProductItem(
    Map<String, dynamic> item, {
    required bool isLast,
  }) {
    final name = _stringValue(
      item['product_name'] ?? item['productName'] ?? item['name'],
      fallback: 'Produk',
    );
    final quantity = _toInt(item['quantity']);
    final price = _toInt(item['selling_price'] ?? item['price']);
    final subtotal = item['subtotal'] == null
        ? price * quantity
        : _toInt(item['subtotal']);

    return Padding(
      padding: EdgeInsets.only(bottom: isLast ? 0 : 15),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: const Icon(
                  Icons.inventory_2_outlined,
                  color: _primary,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: const TextStyle(
                          color: _text,
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '$quantity × ${_formatRupiah(price)}',
                        style: const TextStyle(
                          color: _muted,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 125),
                child: Text(
                  _formatRupiah(subtotal),
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                    color: _text,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
          if (!isLast)
            const Padding(
              padding: EdgeInsets.only(top: 15),
              child: Divider(height: 1, color: _border),
            ),
        ],
      ),
    );
  }

  Widget _card({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(17),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.025),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _infoRow(IconData icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 19, color: _muted),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(color: _muted, fontSize: 13),
          ),
        ),
        const SizedBox(width: 12),
        Flexible(
          flex: 2,
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: const TextStyle(
              color: _text,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
        ),
      ],
    );
  }

  Widget _summaryRow(
    String label,
    String value, {
    bool bold = false,
  }) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              color: bold ? _text : _muted,
              fontWeight: bold ? FontWeight.w700 : FontWeight.normal,
              fontSize: bold ? 14 : 13,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: TextStyle(
              color: bold ? _primary : _text,
              fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
              fontSize: bold ? 19 : 14,
            ),
          ),
        ),
      ],
    );
  }
}

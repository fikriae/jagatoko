import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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

  @override
  void initState() {
    super.initState();
    _itemsFuture = _loadItems();
  }

  int _toInt(dynamic value) {
    if (value is num) return value.round();
    return int.tryParse(value?.toString() ?? '') ??
        double.tryParse(value?.toString() ?? '')?.round() ??
        0;
  }

  String _formatRupiah(num value) {
    final number = value.abs().round().toString();
    final result = StringBuffer();

    for (int i = 0; i < number.length; i++) {
      result.write(number[i]);

      final position = number.length - i - 1;
      if (position > 0 && position % 3 == 0) {
        result.write('.');
      }
    }

    return value < 0 ? '-Rp $result' : 'Rp $result';
  }

  DateTime? _parseDate(dynamic value) {
    if (value == null) return null;

    if (value is DateTime) return value;

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

    return '$day/$month/$year, $hour:$minute';
  }

  dynamic _field(
    Map<String, dynamic> source,
    String snakeCase,
    String camelCase, [
    dynamic fallback,
  ]) {
    return source[snakeCase] ?? source[camelCase] ?? fallback;
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

  @override
  Widget build(BuildContext context) {
    final data = widget.data;

    final invoice = (data['invoice'] ??
            data['invoice_number'] ??
            widget.transactionId)
        .toString();

    final customer = (_field(
      data,
      'customer_name',
      'customerName',
      'Umum',
    )).toString().trim();

    final customerDisplay = customer.isEmpty ? 'Umum' : customer;

    final paymentMethod = (_field(
      data,
      'payment_method',
      'paymentMethod',
      'cash',
    )).toString().toLowerCase();

    final total = _toInt(data['total']);
    final payment = _toInt(
      _field(data, 'payment', 'amount_paid', data['amount_paid']),
    );
    final change = _toInt(
      _field(data, 'change', 'change_amount', data['change_amount']),
    );

    final createdAt = _field(data, 'created_at', 'createdAt');

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        backgroundColor: const Color(0xFF2563EB),
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('Detail Transaksi'),
        actions: [
          IconButton(
            tooltip: 'Muat ulang detail',
            onPressed: _reloadItems,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFE5E7EB)),
            ),
            child: Column(
              children: [
                const Icon(
                  Icons.receipt_long,
                  size: 42,
                  color: Color(0xFF2563EB),
                ),
                const SizedBox(height: 10),
                Text(
                  invoice,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  _formatDate(createdAt),
                  style: const TextStyle(color: Color(0xFF64748B)),
                ),
                const SizedBox(height: 18),
                _infoRow('Pelanggan', customerDisplay),
                const SizedBox(height: 12),
                _infoRow(
                  'Kasir',
                  (_field(data, 'cashier_name', 'cashierName', '-'))
                      .toString(),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Pembayaran'),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: paymentMethod == 'qris'
                            ? const Color(0xFFF3E8FF)
                            : const Color(0xFFDCFCE7),
                        borderRadius: BorderRadius.circular(7),
                      ),
                      child: Text(
                        paymentMethod == 'qris' ? 'QRIS' : 'Cash',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: paymentMethod == 'qris'
                              ? const Color(0xFF7C3AED)
                              : const Color(0xFF15803D),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFE5E7EB)),
            ),
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
                const SizedBox(height: 14),
                FutureBuilder<List<Map<String, dynamic>>>(
                  future: _itemsFuture,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState ==
                        ConnectionState.waiting) {
                      return const Padding(
                        padding: EdgeInsets.all(20),
                        child: Center(
                          child: CircularProgressIndicator(),
                        ),
                      );
                    }

                    if (snapshot.hasError) {
                      return Column(
                        children: [
                          const Icon(
                            Icons.error_outline,
                            color: Colors.red,
                            size: 36,
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Gagal mengambil detail produk dari Supabase.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.red),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '${snapshot.error}',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.grey,
                            ),
                          ),
                          TextButton(
                            onPressed: _reloadItems,
                            child: const Text('Coba lagi'),
                          ),
                        ],
                      );
                    }

                    final items = snapshot.data ?? [];

                    if (items.isEmpty) {
                      return const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: Text(
                          'Detail produk tidak tersedia.',
                          style: TextStyle(color: Color(0xFF64748B)),
                        ),
                      );
                    }

                    return Column(
                      children: items.map((item) {
                        final name = (_field(
                          item,
                          'product_name',
                          'productName',
                          item['name'] ?? 'Produk',
                        )).toString();

                        final quantity = _toInt(item['quantity']);
                        final price = _toInt(item['price']);

                        final subtotalValue = item['subtotal'];
                        final subtotal = subtotalValue == null
                            ? price * quantity
                            : _toInt(subtotalValue);

                        final imageUrl = (_field(
                          item,
                          'image_url',
                          'imageUrl',
                          '',
                        )).toString();

                        return Padding(
                          padding: const EdgeInsets.only(bottom: 14),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(9),
                                child: Container(
                                  width: 54,
                                  height: 54,
                                  color: const Color(0xFFF1F5F9),
                                  child: imageUrl.isEmpty
                                      ? const Icon(
                                          Icons.inventory_2_outlined,
                                          color: Colors.grey,
                                        )
                                      : Image.network(
                                          imageUrl,
                                          fit: BoxFit.cover,
                                          errorBuilder: (_, __, ___) =>
                                              const Icon(
                                            Icons.image_not_supported_outlined,
                                            color: Colors.grey,
                                          ),
                                        ),
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
                                      '$quantity × ${_formatRupiah(price)}',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: Color(0xFF64748B),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                _formatRupiah(subtotal),
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFE5E7EB)),
            ),
            child: Column(
              children: [
                _SummaryRow(
                  label: 'Total',
                  value: _formatRupiah(total),
                  bold: true,
                ),
                if (paymentMethod != 'qris') ...[
                  const SizedBox(height: 12),
                  _SummaryRow(
                    label: 'Bayar',
                    value: _formatRupiah(payment),
                  ),
                  const SizedBox(height: 12),
                  _SummaryRow(
                    label: 'Kembalian',
                    value: _formatRupiah(change),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(color: Color(0xFF64748B)),
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
    );
  }
}

class _SummaryRow extends StatelessWidget {
  final String label;
  final String value;
  final bool bold;

  const _SummaryRow({
    required this.label,
    required this.value,
    this.bold = false,
  });

  @override
  Widget build(BuildContext context) {
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
              fontWeight: bold ? FontWeight.bold : FontWeight.w600,
              fontSize: bold ? 17 : 14,
            ),
          ),
        ),
      ],
    );
  }
}

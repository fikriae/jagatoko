
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/database_service.dart';

class KasirPage extends StatefulWidget {
  const KasirPage({super.key});

  @override
  State<KasirPage> createState() => _KasirPageState();
}

class _KasirPageState extends State<KasirPage> {
  final SupabaseClient _supabase = Supabase.instance.client;
  final DatabaseService _databaseService = DatabaseService();

  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _customerController =
      TextEditingController(text: 'Umum');
  final TextEditingController _paymentController = TextEditingController();

  final Map<String, Map<String, dynamic>> _cart = {};

  String _paymentMethod = 'cash';
  String _searchQuery = '';
  bool _loadingCheckout = false;
  bool _loadingProducts = true;

  List<Map<String, dynamic>> _products = [];
  String _cashierName = 'Kasir';

  @override
  void initState() {
    super.initState();
    _loadProducts();
    _loadCashier();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _customerController.dispose();
    _paymentController.dispose();
    super.dispose();
  }

  double _number(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }

  int _integer(dynamic value) {
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  String _rupiah(num value) {
    final text = value.round().abs().toString();
    final result = StringBuffer();

    for (int i = 0; i < text.length; i++) {
      result.write(text[i]);
      final remaining = text.length - i - 1;

      if (remaining > 0 && remaining % 3 == 0) {
        result.write('.');
      }
    }

    return '${value < 0 ? '-' : ''}Rp$result';
  }

  double _parsePayment(String value) {
    final cleaned = value.replaceAll(RegExp(r'[^0-9]'), '');
    return double.tryParse(cleaned) ?? 0;
  }

  Future<void> _loadProducts() async {
    if (mounted) {
      setState(() => _loadingProducts = true);
    }

    try {
      final response = await _supabase
          .from('products')
          .select()
          .order('name');

      if (!mounted) return;

      final products = List<Map<String, dynamic>>.from(response);

      setState(() {
        _products = products;

        for (final entry in _cart.entries.toList()) {
          final product = products.where(
            (p) => (p['id'] ?? '').toString() == entry.key,
          );

          if (product.isEmpty) {
            _cart.remove(entry.key);
            continue;
          }

          final currentStock = _integer(product.first['stock']);
          entry.value['stock'] = currentStock;

          if (_integer(entry.value['quantity']) > currentStock) {
            entry.value['quantity'] = currentStock;
          }

          if (currentStock <= 0) {
            _cart.remove(entry.key);
          }
        }

        _loadingProducts = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() => _loadingProducts = false);

      _showMessage('Gagal mengambil produk: $e');
    }
  }

  Future<void> _loadCashier() async {
    final user = _supabase.auth.currentUser;
    if (user == null) return;

    try {
      final profile = await _supabase
          .from('profiles')
          .select('name')
          .eq('id', user.id)
          .maybeSingle();

      if (!mounted) return;

      setState(() {
        _cashierName =
            (profile?['name'] ?? user.email ?? 'Kasir').toString();
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _cashierName = user.email ?? 'Kasir';
      });
    }
  }

  List<Map<String, dynamic>> get _filteredProducts {
    final query = _searchQuery.trim().toLowerCase();

    if (query.isEmpty) return _products;

    return _products.where((product) {
      final name = (product['name'] ?? '').toString().toLowerCase();
      final barcode =
          (product['barcode'] ?? '').toString().toLowerCase();

      return name.contains(query) || barcode.contains(query);
    }).toList();
  }

  double get _total {
    double total = 0;

    for (final item in _cart.values) {
      total += _number(item['price']) * _integer(item['quantity']);
    }

    return total;
  }

  int get _totalItems {
    int total = 0;

    for (final item in _cart.values) {
      total += _integer(item['quantity']);
    }

    return total;
  }

  double get _payment {
    if (_paymentMethod == 'qris') return _total;
    return _parsePayment(_paymentController.text);
  }

  void _addProduct(Map<String, dynamic> product) {
    final id = (product['id'] ?? '').toString();

    if (id.isEmpty) {
      _showMessage('Produk tidak memiliki ID.');
      return;
    }

    final stock = _integer(product['stock']);

    if (stock <= 0) {
      _showMessage('Stok ${product['name']} habis.');
      return;
    }

    final existing = _cart[id];

    if (existing != null) {
      final quantity = _integer(existing['quantity']);

      if (quantity >= stock) {
        _showMessage('Jumlah melebihi stok yang tersedia.');
        return;
      }

      setState(() {
        existing['quantity'] = quantity + 1;
      });
    } else {
      setState(() {
        _cart[id] = {
          'productId': id,
          'productName': (product['name'] ?? '').toString(),
          'price': _number(product['price']),
          'purchasePrice': _number(
            product['purchase_price'] ?? product['purchasePrice'],
          ),
          'quantity': 1,
          'stock': stock,
          'imageUrl':
              (product['image_url'] ?? product['imageUrl'] ?? '').toString(),
        };
      });
    }

    _showMessage('${product['name']} ditambahkan ke keranjang.');
  }

  void _changeQuantity(String id, int difference) {
    final item = _cart[id];
    if (item == null) return;

    final current = _integer(item['quantity']);
    final next = current + difference;
    final stock = _integer(item['stock']);

    if (next <= 0) {
      _removeProduct(id);
      return;
    }

    if (next > stock) {
      _showMessage('Jumlah tidak boleh melebihi stok.');
      return;
    }

    setState(() {
      item['quantity'] = next;
    });
  }

  void _removeProduct(String id) {
    if (!_cart.containsKey(id)) return;

    setState(() {
      _cart.remove(id);
    });
  }

  void _showMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  String _generateInvoice() {
    final now = DateTime.now();
    final date =
        '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
    final time =
        '${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}${now.second.toString().padLeft(2, '0')}${now.millisecond.toString().padLeft(3, '0')}';

    return 'INV-$date-$time';
  }

  Future<void> _scanBarcode() async {
    final result = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => const _BarcodeScannerPage(),
      ),
    );

    if (result == null || result.trim().isEmpty || !mounted) return;

    final barcode = result.trim();

    setState(() {
      _searchController.text = barcode;
      _searchQuery = barcode;
    });

    final matches = _products.where((product) {
      return (product['barcode'] ?? '').toString().trim() == barcode;
    }).toList();

    if (matches.isEmpty) {
      _showMessage('Produk dengan barcode tersebut tidak ditemukan.');
      return;
    }

    _showMessage(
      'Produk ditemukan. Tekan tombol Tambah untuk memasukkan ke keranjang.',
    );
  }

  Future<void> _showCheckoutDialog() async {
    if (_cart.isEmpty) {
      _showMessage('Keranjang masih kosong.');
      return;
    }

    _customerController.text = 'Umum';
    _paymentMethod = 'cash';
    _paymentController.clear();

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.white,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final total = _total;
            final paid = _paymentMethod == 'qris'
                ? total
                : _parsePayment(_paymentController.text);
            final change = paid - total;

            return Padding(
              padding: EdgeInsets.fromLTRB(
                20,
                20,
                20,
                MediaQuery.of(context).viewInsets.bottom + 20,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Pembayaran',
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.pop(sheetContext),
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '$_totalItems item dalam keranjang',
                      style: const TextStyle(color: Colors.grey),
                    ),
                    const SizedBox(height: 16),
                    ..._cart.values.toList().map((item) {
                      final imageUrl = (item['imageUrl'] ?? '').toString();
                      final quantity = _integer(item['quantity']);
                      final price = _number(item['price']);
                      final id = item['productId'].toString();

                      return Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _productImage(imageUrl, size: 56),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    item['productName'].toString(),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '${_rupiah(price)} × $quantity',
                                    style: const TextStyle(
                                      color: Colors.grey,
                                      fontSize: 12,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      _quantityButton(
                                        icon: Icons.remove,
                                        onTap: () {
                                          _changeQuantity(id, -1);
                                          setSheetState(() {});
                                        },
                                      ),
                                      Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                        ),
                                        child: Text('$quantity'),
                                      ),
                                      _quantityButton(
                                        icon: Icons.add,
                                        onTap: () {
                                          _changeQuantity(id, 1);
                                          setSheetState(() {});
                                        },
                                      ),
                                      const Spacer(),
                                      IconButton(
                                        tooltip: 'Hapus produk',
                                        onPressed: () {
                                          _removeProduct(id);
                                          setSheetState(() {});
                                        },
                                        icon: const Icon(
                                          Icons.delete_outline,
                                          color: Colors.red,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              _rupiah(price * quantity),
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                    const Divider(height: 24),
                    _summaryRow(
                      'Total pembayaran',
                      _rupiah(total),
                      bold: true,
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Nama pelanggan',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _customerController,
                      decoration: InputDecoration(
                        hintText: 'Nama pelanggan',
                        prefixIcon: const Icon(Icons.person_outline),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Metode pembayaran',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: _paymentOption(
                            label: 'Cash',
                            icon: Icons.payments_outlined,
                            selected: _paymentMethod == 'cash',
                            onTap: () {
                              setSheetState(() {
                                _paymentMethod = 'cash';
                                _paymentController.clear();
                              });
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _paymentOption(
                            label: 'QRIS',
                            icon: Icons.qr_code_2,
                            selected: _paymentMethod == 'qris',
                            onTap: () {
                              setSheetState(() {
                                _paymentMethod = 'qris';
                                _paymentController.text =
                                    total.round().toString();
                              });
                            },
                          ),
                        ),
                      ],
                    ),
                    if (_paymentMethod == 'cash') ...[
                      const SizedBox(height: 16),
                      const Text(
                        'Uang diterima',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _paymentController,
                        keyboardType: TextInputType.number,
                        onChanged: (_) => setSheetState(() {}),
                        decoration: InputDecoration(
                          prefixText: 'Rp ',
                          hintText: 'Masukkan nominal uang',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEFF6FF),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        children: [
                          _summaryRow('Total', _rupiah(total)),
                          const SizedBox(height: 8),
                          _summaryRow('Dibayar', _rupiah(paid)),
                          const Divider(height: 20),
                          _summaryRow(
                            change >= 0 ? 'Kembalian' : 'Kurang bayar',
                            _rupiah(change.abs()),
                            bold: true,
                            valueColor:
                                change < 0 ? Colors.red : Colors.green,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton.icon(
                        onPressed: _loadingCheckout
                            ? null
                            : () async {
                                if (_cart.isEmpty) {
                                  _showMessage('Keranjang masih kosong.');
                                  return;
                                }

                                if (paid < total) {
                                  _showMessage(
                                    'Uang pembayaran belum cukup.',
                                  );
                                  return;
                                }

                                Navigator.pop(sheetContext);
                                await _processCheckout();
                              },
                        icon: _loadingCheckout
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.check_circle_outline),
                        label: Text(
                          _loadingCheckout
                              ? 'Memproses...'
                              : 'Selesaikan Pembayaran',
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF2563EB),
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
            );
          },
        );
      },
    );
  }

  Future<void> _processCheckout() async {
    if (_cart.isEmpty) return;

    final user = _supabase.auth.currentUser;

    if (user == null) {
      _showMessage('Silakan login terlebih dahulu.');
      return;
    }

    final total = _total;
    final payment = _paymentMethod == 'qris'
        ? total
        : _parsePayment(_paymentController.text);

    if (payment < total) {
      _showMessage('Uang pembayaran belum cukup.');
      return;
    }

    final customerName = _customerController.text.trim().isEmpty
        ? 'Umum'
        : _customerController.text.trim();

    final items = _cart.values.map((item) {
      return <String, dynamic>{
        'productId': item['productId'],
        'productName': item['productName'],
        'price': _number(item['price']).round(),
        'purchasePrice': _number(item['purchasePrice']).round(),
        'quantity': _integer(item['quantity']),
        'subtotal': (
          _number(item['price']) * _integer(item['quantity'])
        ).round(),
        'imageUrl': item['imageUrl'] ?? '',
      };
    }).toList();

    setState(() => _loadingCheckout = true);

    try {
      await _databaseService.processSale(
        invoice: _generateInvoice(),
        customerId: '',
        customerName: customerName,
        total: total.round(),
        payment: payment.round(),
        change: (payment - total).round(),
        paymentMethod: _paymentMethod,
        cashierId: user.id,
        cashierName: _cashierName,
        items: items,
      );

      if (!mounted) return;

      setState(() {
        _cart.clear();
        _paymentController.clear();
        _customerController.text = 'Umum';
        _loadingCheckout = false;
      });

      await _loadProducts();

      if (!mounted) return;

      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            icon: const Icon(
              Icons.check_circle,
              color: Colors.green,
              size: 54,
            ),
            title: const Text('Transaksi Berhasil'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Total: ${_rupiah(total)}'),
                const SizedBox(height: 6),
                Text('Metode: ${_paymentMethod.toUpperCase()}'),
                const SizedBox(height: 6),
                Text('Kembalian: ${_rupiah(payment - total)}'),
              ],
            ),
            actions: [
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF2563EB),
                ),
                child: const Text('Selesai'),
              ),
            ],
          );
        },
      );
    } catch (e) {
      if (!mounted) return;

      setState(() => _loadingCheckout = false);
      _showMessage('Transaksi gagal: $e');
    }
  }

  Widget _productImage(String imageUrl, {double size = 70}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: size,
        height: size,
        color: const Color(0xFFF1F5F9),
        child: imageUrl.isEmpty
            ? const Icon(
                Icons.inventory_2_outlined,
                color: Colors.grey,
                size: 30,
              )
            : Image.network(
                imageUrl,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const Icon(
                  Icons.image_not_supported_outlined,
                  color: Colors.grey,
                ),
              ),
      ),
    );
  }

  Widget _quantityButton({
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          border: Border.all(color: const Color(0xFFCBD5E1)),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, size: 17),
      ),
    );
  }

  Widget _summaryRow(
    String label,
    String value, {
    bool bold = false,
    Color? valueColor,
  }) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontWeight: bold ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontWeight: bold ? FontWeight.bold : FontWeight.w500,
            color: valueColor,
          ),
        ),
      ],
    );
  }

  Widget _paymentOption({
    required String label,
    required IconData icon,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFEFF6FF) : Colors.white,
          border: Border.all(
            color: selected
                ? const Color(0xFF2563EB)
                : const Color(0xFFE2E8F0),
            width: selected ? 1.5 : 1,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              color: selected
                  ? const Color(0xFF2563EB)
                  : Colors.grey,
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: selected
                    ? const Color(0xFF2563EB)
                    : Colors.black87,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProductCard(Map<String, dynamic> product) {
    final id = (product['id'] ?? '').toString();
    final name = (product['name'] ?? 'Produk').toString();
    final price = _number(product['price']);
    final stock = _integer(product['stock']);
    final imageUrl =
        (product['image_url'] ?? product['imageUrl'] ?? '').toString();
    final inCart = _cart.containsKey(id);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: SizedBox(
              width: double.infinity,
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(14),
                ),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    _productImage(imageUrl, size: 140),
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: stock > 0
                              ? Colors.white.withValues(alpha: 0.95)
                              : Colors.red.shade50,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          'Stok $stock',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: stock > 0 ? Colors.black87 : Colors.red,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  _rupiah(price),
                  style: const TextStyle(
                    color: Color(0xFF2563EB),
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  height: 36,
                  child: ElevatedButton.icon(
                    onPressed: stock <= 0 ? null : () => _addProduct(product),
                    icon: Icon(
                      inCart ? Icons.add : Icons.add_shopping_cart,
                      size: 16,
                    ),
                    label: Text(
                      inCart ? 'Tambah Lagi' : 'Tambah',
                      style: const TextStyle(fontSize: 12),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2563EB),
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: Colors.grey.shade300,
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(9),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCartPanel() {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(
          top: BorderSide(color: Color(0xFFE2E8F0)),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.shopping_cart_outlined,
                  color: Color(0xFF2563EB),
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Keranjang',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEFF6FF),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '$_totalItems item',
                    style: const TextStyle(
                      color: Color(0xFF2563EB),
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (_cart.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  'Belum ada produk. Pilih produk untuk memulai transaksi.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey, fontSize: 12),
                ),
              )
            else
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 145),
                child: ListView(
                  shrinkWrap: true,
                  children: _cart.values.toList().map((item) {
                    final id = item['productId'].toString();
                    final quantity = _integer(item['quantity']);
                    final price = _number(item['price']);

                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 5),
                      child: Row(
                        children: [
                          _productImage(
                            (item['imageUrl'] ?? '').toString(),
                            size: 44,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  item['productName'].toString(),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13,
                                  ),
                                ),
                                Text(
                                  _rupiah(price * quantity),
                                  style: const TextStyle(
                                    color: Color(0xFF2563EB),
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          _quantityButton(
                            icon: Icons.remove,
                            onTap: () => _changeQuantity(id, -1),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                            ),
                            child: Text('$quantity'),
                          ),
                          _quantityButton(
                            icon: Icons.add,
                            onTap: () => _changeQuantity(id, 1),
                          ),
                          IconButton(
                            onPressed: () => _removeProduct(id),
                            icon: const Icon(
                              Icons.delete_outline,
                              color: Colors.red,
                              size: 20,
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ),
            const Divider(height: 20),
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Total pembayaran',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                Text(
                  _rupiah(_total),
                  style: const TextStyle(
                    color: Color(0xFF2563EB),
                    fontSize: 19,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: _cart.isEmpty || _loadingCheckout
                    ? null
                    : _showCheckoutDialog,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2563EB),
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: Colors.grey.shade300,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  'Lanjut ke Pembayaran',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final products = _filteredProducts;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
        title: const Text(
          'Kasir',
          style: TextStyle(
            color: Color(0xFF0F172A),
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Muat ulang produk',
            onPressed: _loadProducts,
            icon: const Icon(Icons.refresh, color: Color(0xFF2563EB)),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              controller: _searchController,
              onChanged: (value) {
                setState(() => _searchQuery = value);
              },
              decoration: InputDecoration(
                hintText: 'Cari nama produk atau barcode...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: IconButton(
                  tooltip: 'Scan barcode',
                  onPressed: _scanBarcode,
                  icon: const Icon(
                    Icons.qr_code_scanner,
                    color: Color(0xFF2563EB),
                  ),
                ),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(
                    color: Color(0xFF2563EB),
                    width: 1.5,
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Daftar Produk',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Text(
                  '${products.length} produk',
                  style: const TextStyle(
                    color: Colors.grey,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: _loadingProducts
                ? const Center(child: CircularProgressIndicator())
                : products.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.inventory_2_outlined,
                              size: 56,
                              color: Colors.grey,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              _searchQuery.isEmpty
                                  ? 'Belum ada produk.'
                                  : 'Produk tidak ditemukan.',
                              style: const TextStyle(color: Colors.grey),
                            ),
                          ],
                        ),
                      )
                    : GridView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 12,
                          childAspectRatio: 0.69,
                        ),
                        itemCount: products.length,
                        itemBuilder: (context, index) {
                          return _buildProductCard(products[index]);
                        },
                      ),
          ),
          _buildCartPanel(),
        ],
      ),
    );
  }
}

class _BarcodeScannerPage extends StatefulWidget {
  const _BarcodeScannerPage();

  @override
  State<_BarcodeScannerPage> createState() => _BarcodeScannerPageState();
}

class _BarcodeScannerPageState extends State<_BarcodeScannerPage> {
  final MobileScannerController _controller = MobileScannerController();
  bool _scanned = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan Barcode'),
        actions: [
          IconButton(
            onPressed: () => _controller.toggleTorch(),
            icon: const Icon(Icons.flash_on),
          ),
          IconButton(
            onPressed: () => _controller.switchCamera(),
            icon: const Icon(Icons.cameraswitch),
          ),
        ],
      ),
      body: MobileScanner(
        controller: _controller,
        onDetect: (capture) {
          if (_scanned || capture.barcodes.isEmpty) return;

          final value = capture.barcodes.first.rawValue;

          if (value == null || value.isEmpty) return;

          _scanned = true;
          Navigator.pop(context, value);
        },
      ),
    );
  }
}

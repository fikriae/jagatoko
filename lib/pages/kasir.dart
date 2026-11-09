
import 'package:flutter/material.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';
import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
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

  final TextEditingController _searchController =
      TextEditingController();
  final TextEditingController _customerController =
      TextEditingController(text: 'Umum');
  final TextEditingController _paymentController =
      TextEditingController();
  final TextEditingController _discountController =
      TextEditingController();

  final Map<String, Map<String, dynamic>> _cart = {};

  String _paymentMethod = 'cash';
  String _discountType = 'nominal';
  String _searchQuery = '';
  String _cashierName = 'Kasir';

  bool _loadingCheckout = false;
  bool _loadingProducts = true;

  // Ukuran kertas printer thermal: 58 mm atau 80 mm.
  int _paperWidth = 58;

  List<Map<String, dynamic>> _products = [];

  static const Color _primary = Color(0xFF2563EB);
  static const Color _background = Color(0xFFF8FAFC);
  static const Color _border = Color(0xFFE2E8F0);

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
    _discountController.dispose();
    super.dispose();
  }

  double _number(dynamic value) {
    if (value is num) return value.toDouble();
    if (value == null) return 0;

    final cleaned = value.toString().replaceAll(',', '').trim();
    return double.tryParse(cleaned) ?? 0;
  }

  int _integer(dynamic value) {
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  // Harga jual selalu mengambil kolom selling_price.
  double _sellingPrice(Map<String, dynamic> product) {
    return _number(product['selling_price']);
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
      final response =
          await _supabase.from('products').select().order('name');

      final products = List<Map<String, dynamic>>.from(
        (response as List).map((row) {
          final product = Map<String, dynamic>.from(row);
          product['selling_price'] = _sellingPrice(product);
          product['price'] = _sellingPrice(product);
          return product;
        }),
      );

      if (!mounted) return;

      setState(() {
        _products = products;

        for (final entry in _cart.entries.toList()) {
          final matches = products.where(
            (product) =>
                (product['id'] ?? '').toString() == entry.key,
          );

          if (matches.isEmpty) {
            _cart.remove(entry.key);
            continue;
          }

          final product = matches.first;
          final currentStock = _integer(product['stock']);
          final currentPrice = _sellingPrice(product);

          entry.value['price'] = currentPrice;
          entry.value['stock'] = currentStock;
          entry.value['productName'] =
              (product['name'] ?? 'Produk').toString();
          entry.value['imageUrl'] =
              (product['image_url'] ?? '').toString();

          final quantity = _integer(entry.value['quantity']);

          if (currentStock <= 0) {
            _cart.remove(entry.key);
          } else if (quantity > currentStock) {
            entry.value['quantity'] = currentStock;
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
          .select('full_name')
          .eq('id', user.id)
          .maybeSingle();

      if (!mounted) return;

      setState(() {
        _cashierName =
            (profile?['full_name'] ?? user.email ?? 'Kasir').toString();
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

  // Subtotal sebelum diskon.
  double get _subtotal {
    double subtotal = 0;

    for (final item in _cart.values) {
      subtotal += _number(item['price']) * _integer(item['quantity']);
    }

    return subtotal;
  }

  // Nilai diskon berdasarkan pilihan nominal atau persentase.
  double get _discount {
    final input = _parsePayment(_discountController.text);

    if (_discountType == 'persentase') {
      final percentage = input.clamp(0, 100).toDouble();
      return (_subtotal * percentage / 100).clamp(0, _subtotal).toDouble();
    }

    return input.clamp(0, _subtotal).toDouble();
  }

  // Total akhir setelah diskon.
  double get _total {
    return (_subtotal - _discount).clamp(0, _subtotal).toDouble();
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
    final price = _sellingPrice(product);

    if (stock <= 0) {
      _showMessage('Stok ${product['name']} habis.');
      return;
    }

    if (price < 0) {
      _showMessage('Harga produk tidak valid.');
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
        existing['price'] = price;
        existing['stock'] = stock;
      });
    } else {
      setState(() {
        _cart[id] = {
          'productId': id,
          'productName': (product['name'] ?? 'Produk').toString(),
          'price': price,
          'purchasePrice': _number(
            product['purchase_price'] ?? product['purchasePrice'],
          ),
          'quantity': 1,
          'stock': stock,
          'imageUrl': (product['image_url'] ?? '').toString(),
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

    final matches = _products.where((product) {
      return (product['barcode'] ?? '').toString().trim() == barcode;
    }).toList();

    setState(() {
      _searchController.clear();
      _searchQuery = '';
    });

    if (matches.isEmpty) {
      _showMessage('Produk dengan barcode tersebut tidak ditemukan.');
      return;
    }

    _addProduct(matches.first);
  }

  Future<void> _showCheckoutDialog() async {
    if (_cart.isEmpty) {
      _showMessage('Keranjang masih kosong.');
      return;
    }

    _customerController.text = 'Umum';
    _paymentMethod = 'cash';
    _paymentController.clear();
    _discountController.clear();
    _discountType = 'nominal';

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.white,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final subtotal = _subtotal;
            final discount = _discount;
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
                      final imageUrl =
                          (item['imageUrl'] ?? '').toString();
                      final quantity = _integer(item['quantity']);
                      final price = _number(item['price']);
                      final id = item['productId'].toString();

                      return Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: _background,
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
                                        padding:
                                            const EdgeInsets.symmetric(
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
                      'Subtotal',
                      _rupiah(subtotal),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Jenis diskon',
                            style: TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                        SizedBox(
                          width: 150,
                          child: DropdownButtonFormField<String>(
                            value: _discountType,
                            isExpanded: true,
                            decoration: InputDecoration(
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 10,
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            items: const [
                              DropdownMenuItem(
                                value: 'nominal',
                                child: Text('Nominal (Rp)'),
                              ),
                              DropdownMenuItem(
                                value: 'persentase',
                                child: Text('Persentase (%)'),
                              ),
                            ],
                            onChanged: (value) {
                              if (value == null) return;

                              setSheetState(() {
                                _discountType = value;
                                _discountController.clear();

                                if (_paymentMethod == 'qris') {
                                  _paymentController.text =
                                      _total.round().toString();
                                }
                              });
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _discountController,
                      keyboardType: TextInputType.number,
                      onChanged: (_) {
                        setSheetState(() {
                          if (_paymentMethod == 'qris') {
                            _paymentController.text =
                                _total.round().toString();
                          }
                        });
                      },
                      decoration: InputDecoration(
                        prefixText: _discountType == 'nominal' ? 'Rp ' : null,
                        suffixText: _discountType == 'persentase' ? '%' : null,
                        hintText: _discountType == 'nominal'
                            ? 'Masukkan nominal diskon'
                            : 'Masukkan persentase diskon',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    _summaryRow(
                      'Potongan diskon',
                      '- ${_rupiah(discount)}',
                      valueColor: Colors.red,
                    ),
                    const Divider(height: 20),
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
                          backgroundColor: _primary,
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

    try {
      final ids = _cart.keys.toList();

      final latestResponse = await _supabase
          .from('products')
          .select()
          .inFilter('id', ids);

      final latestProducts = List<Map<String, dynamic>>.from(
        (latestResponse as List).map(
          (row) => Map<String, dynamic>.from(row),
        ),
      );

      for (final entry in _cart.entries) {
        final matches = latestProducts.where(
          (product) =>
              (product['id'] ?? '').toString() == entry.key,
        );

        if (matches.isEmpty) {
          _showMessage(
            'Produk ${entry.value['productName']} tidak ditemukan lagi.',
          );
          return;
        }

        final product = matches.first;
        final latestStock = _integer(product['stock']);
        final latestPrice = _sellingPrice(product);
        final quantity = _integer(entry.value['quantity']);

        if (latestStock < quantity) {
          _showMessage(
            'Stok ${product['name']} tidak cukup. '
            'Stok tersedia: $latestStock.',
          );
          await _loadProducts();
          return;
        }

        entry.value['price'] = latestPrice;
        entry.value['stock'] = latestStock;
        entry.value['productName'] =
            (product['name'] ?? 'Produk').toString();
        entry.value['imageUrl'] =
            (product['image_url'] ?? '').toString();
      }
    } catch (e) {
      _showMessage('Gagal memeriksa harga dan stok terbaru: $e');
      return;
    }

    if (!mounted) return;

    final subtotal = _subtotal;
    final discount = _discount;
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
      final price = _number(item['price']);
      final quantity = _integer(item['quantity']);

      return <String, dynamic>{
        'productId': item['productId'],
        'productName': item['productName'],
        'price': price.round(),
        'purchasePrice': _number(item['purchasePrice']).round(),
        'quantity': quantity,
        'subtotal': (price * quantity).round(),
        'imageUrl': item['imageUrl'] ?? '',
      };
    }).toList();

    final invoice = _generateInvoice();

    final completedItems = items
        .map((item) => Map<String, dynamic>.from(item))
        .toList();

    setState(() => _loadingCheckout = true);

    try {
      await _databaseService.processSale(
        invoice: invoice,
        customerId: '',
        customerName: customerName,
        subtotal: subtotal.round(),
        discount: discount.round(),
        total: total.round(),
        payment: payment.round(),
        change: (payment - total).round(),
        paymentMethod: _paymentMethod,
        cashierId: user.id,
        cashierName: _cashierName,
        items: items,
      );

      if (!mounted) return;

      final completedMethod = _paymentMethod;
      final completedSubtotal = subtotal;
      final completedDiscount = discount;
      final completedTotal = total;
      final completedPayment = payment;
      final completedChange = payment - total;
      final completedCustomerName = customerName;

      setState(() {
        _cart.clear();
        _paymentController.clear();
        _discountController.clear();
        _discountType = 'nominal';
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
                Text('Subtotal: ${_rupiah(completedSubtotal)}'),
                const SizedBox(height: 6),
                Text(
                  'Diskon: ${_rupiah(completedDiscount)}',
                  style: const TextStyle(color: Colors.red),
                ),
                const Divider(height: 18),
                Text(
                  'Total: ${_rupiah(completedTotal)}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                Text('Metode: ${completedMethod.toUpperCase()}'),
                const SizedBox(height: 6),
                Text('Kembalian: ${_rupiah(completedChange)}'),
              ],
            ),
            actions: [
              OutlinedButton.icon(
                onPressed: () => Navigator.pop(dialogContext),
                icon: const Icon(Icons.check),
                label: const Text('Selesai'),
              ),
              FilledButton.icon(
                onPressed: () async {
                  await _printReceipt(
                    invoice: invoice,
                    customerName: completedCustomerName,
                    subtotal: completedSubtotal,
                    discount: completedDiscount,
                    total: completedTotal,
                    payment: completedPayment,
                    change: completedChange,
                    paymentMethod: completedMethod,
                    items: completedItems,
                  );
                },
                style: FilledButton.styleFrom(
                  backgroundColor: _primary,
                ),
                icon: const Icon(Icons.print),
                label: const Text('Cetak'),
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

  Future<bool> _printReceipt({
    required String invoice,
    required String customerName,
    required num subtotal,
    required num discount,
    required num total,
    required num payment,
    required num change,
    required String paymentMethod,
    required List<Map<String, dynamic>> items,
  }) async {
    try {
      // Pastikan Bluetooth HP aktif.
      final bluetoothEnabled =
          await PrintBluetoothThermal.bluetoothEnabled;

      if (!bluetoothEnabled) {
        _showMessage(
          'Bluetooth HP belum aktif. Aktifkan Bluetooth terlebih dahulu.',
        );
        return false;
      }

      // Periksa izin Bluetooth.
      final permissionGranted =
          await PrintBluetoothThermal.isPermissionBluetoothGranted;

      if (!permissionGranted) {
        _showMessage(
          'Izin Bluetooth belum diberikan. '
          'Periksa izin aplikasi Jagatoko di Pengaturan HP.',
        );
        return false;
      }

      // Periksa perangkat yang sudah dipasangkan.
      final devices = await PrintBluetoothThermal.pairedBluetooths;

      if (devices.isEmpty) {
        _showMessage(
          'Printer belum dipasangkan. '
          'Pasangkan printer melalui Pengaturan Bluetooth HP terlebih dahulu.',
        );
        return false;
      }

      if (!mounted) return false;

      // Pilih printer sekaligus ukuran kertas.
      final selectedPrinter = await showDialog<BluetoothInfo>(
        context: context,
        builder: (dialogContext) {
          return StatefulBuilder(
            builder: (context, setDialogState) {
              return AlertDialog(
                title: const Text('Pengaturan Cetak Struk'),
                content: SizedBox(
                  width: double.maxFinite,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Ukuran kertas',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<int>(
                        value: _paperWidth,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: 58,
                            child: Text('Thermal 58 mm'),
                          ),
                          DropdownMenuItem(
                            value: 80,
                            child: Text('Thermal 80 mm'),
                          ),
                        ],
                        onChanged: (value) {
                          if (value == null) return;
                          setDialogState(() {
                            _paperWidth = value;
                          });
                        },
                      ),
                      const SizedBox(height: 18),
                      const Text(
                        'Pilih printer Bluetooth',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 8),
                      ConstrainedBox(
                        constraints: const BoxConstraints(
                          maxHeight: 250,
                        ),
                        child: ListView.separated(
                          shrinkWrap: true,
                          itemCount: devices.length,
                          separatorBuilder: (_, __) =>
                              const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final device = devices[index];

                            return ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: const Icon(
                                Icons.print,
                                color: _primary,
                              ),
                              title: Text(
                                device.name.isEmpty
                                    ? 'Printer Bluetooth'
                                    : device.name,
                              ),
                              subtitle: Text(device.macAdress),
                              onTap: () {
                                Navigator.pop(dialogContext, device);
                              },
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(dialogContext),
                    child: const Text('Batal'),
                  ),
                ],
              );
            },
          );
        },
      );

      if (selectedPrinter == null) {
        _showMessage('Pemilihan printer dibatalkan.');
        return false;
      }

      // Tutup koneksi lama jika masih tersambung.
      final alreadyConnected =
          await PrintBluetoothThermal.connectionStatus;

      if (alreadyConnected) {
        await PrintBluetoothThermal.disconnect;
      }

      // Hubungkan printer yang dipilih.
      _showMessage(
        'Menghubungkan ke printer ${selectedPrinter.name}...',
      );

      final connected = await PrintBluetoothThermal.connect(
        macPrinterAddress: selectedPrinter.macAdress,
      );

      if (!connected) {
        _showMessage(
          'Gagal terhubung ke printer ${selectedPrinter.name}. '
          'Pastikan printer menyala dan sudah dipasangkan.',
        );
        return false;
      }

      // Buat data struk dengan lebar kertas pilihan.
      final profile = await CapabilityProfile.load();

      final paperSize =
          _paperWidth == 80 ? PaperSize.mm80 : PaperSize.mm58;

      final generator = Generator(paperSize, profile);
      final List<int> bytes = [];

      bytes.addAll(
        generator.text(
          'JAGATOKO',
          styles: const PosStyles(
            align: PosAlign.center,
            bold: true,
            height: PosTextSize.size2,
            width: PosTextSize.size2,
          ),
        ),
      );

      bytes.addAll(
        generator.text(
          'STRUK PEMBELIAN',
          styles: const PosStyles(align: PosAlign.center),
        ),
      );

      bytes.addAll(generator.hr());
      bytes.addAll(generator.text('Invoice: $invoice'));
      bytes.addAll(generator.text('Pelanggan: $customerName'));
      bytes.addAll(generator.text('Kasir: $_cashierName'));
      bytes.addAll(
        generator.text(
          'Pembayaran: ${paymentMethod.toUpperCase()}',
        ),
      );
      bytes.addAll(generator.hr());

      for (final item in items) {
        final name = (item['productName'] ?? 'Produk').toString();
        final quantity = _integer(item['quantity']);
        final price = _number(item['price']);
        final subtotal = _number(item['subtotal']);

        bytes.addAll(generator.text(name));
        bytes.addAll(
          generator.text(
            '$quantity x ${_rupiah(price)} = ${_rupiah(subtotal)}',
          ),
        );
      }

      bytes.addAll(generator.hr());

      bytes.addAll(
        generator.text('Subtotal: ${_rupiah(subtotal)}'),
      );

      bytes.addAll(
        generator.text(
          'Diskon: -${_rupiah(discount)}',
          styles: const PosStyles(bold: true),
        ),
      );

      bytes.addAll(generator.hr());

      bytes.addAll(
        generator.text(
          'TOTAL: ${_rupiah(total)}',
          styles: const PosStyles(
            bold: true,
            height: PosTextSize.size2,
          ),
        ),
      );

      bytes.addAll(generator.text('Dibayar: ${_rupiah(payment)}'));
      bytes.addAll(generator.text('Kembalian: ${_rupiah(change)}'));
      bytes.addAll(generator.hr());

      bytes.addAll(
        generator.text(
          'Terima kasih telah berbelanja',
          styles: const PosStyles(align: PosAlign.center),
        ),
      );

      bytes.addAll(
        generator.text(
          'di Jagatoko',
          styles: const PosStyles(align: PosAlign.center),
        ),
      );

      bytes.addAll(generator.feed(3));

      // Kirim data ke printer.
      final printed = await PrintBluetoothThermal.writeBytes(bytes);

      if (!printed) {
        _showMessage(
          'Struk gagal dicetak. Periksa koneksi dan kertas printer.',
        );
        return false;
      }

      _showMessage(
        'Struk berhasil dikirim ke printer ${selectedPrinter.name}.',
      );

      return true;
    } catch (e) {
      _showMessage('Gagal mencetak struk: $e');
      return false;
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
            color: selected ? _primary : _border,
            width: selected ? 1.5 : 1,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              color: selected ? _primary : Colors.grey,
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: selected ? _primary : Colors.black87,
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
    final price = _sellingPrice(product);
    final stock = _integer(product['stock']);
    final imageUrl = (product['image_url'] ?? '').toString();
    final inCart = _cart.containsKey(id);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _border),
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
                    color: _primary,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  height: 36,
                  child: ElevatedButton.icon(
                    onPressed:
                        stock <= 0 ? null : () => _addProduct(product),
                    icon: Icon(
                      inCart
                          ? Icons.add
                          : Icons.add_shopping_cart,
                      size: 16,
                    ),
                    label: Text(
                      inCart ? 'Tambah Lagi' : 'Tambah',
                      style: const TextStyle(fontSize: 12),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _primary,
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
        border: Border(top: BorderSide(color: _border)),
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
                  color: _primary,
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
                      color: _primary,
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
                                    color: _primary,
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
                    color: _primary,
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
                  backgroundColor: _primary,
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
      backgroundColor: _background,
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
            icon: const Icon(Icons.refresh, color: _primary),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: _border),
              ),
              child: Row(
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      color: _primary.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.qr_code_scanner_rounded,
                      color: _primary,
                      size: 26,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Scan Barcode',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF0F172A),
                          ),
                        ),
                        SizedBox(height: 3),
                        Text(
                          'Pindai barcode untuk menambahkan produk',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    onPressed: _scanBarcode,
                    icon: const Icon(
                      Icons.camera_alt_outlined,
                      size: 18,
                    ),
                    label: const Text('Scan'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _primary,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: TextField(
              controller: _searchController,
              onChanged: (value) {
                setState(() => _searchQuery = value);
              },
              decoration: InputDecoration(
                hintText: 'Cari nama produk atau barcode...',
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: _border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: _border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(
                    color: _primary,
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
                        padding: const EdgeInsets.fromLTRB(
                          16,
                          0,
                          16,
                          16,
                        ),
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
  const _BarcodeScannerPage({super.key});

  @override
  State<_BarcodeScannerPage> createState() =>
      _BarcodeScannerPageState();
}

class _BarcodeScannerPageState extends State<_BarcodeScannerPage> {
  final MobileScannerController _controller = MobileScannerController();
  bool _hasScanned = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_hasScanned) return;

    for (final barcode in capture.barcodes) {
      final value = barcode.rawValue?.trim();

      if (value != null && value.isNotEmpty) {
        _hasScanned = true;
        Navigator.of(context).pop(value);
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Scan Barcode'),
        backgroundColor: const Color(0xFF2563EB),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: 'Nyalakan/matikan lampu',
            onPressed: () => _controller.toggleTorch(),
            icon: const Icon(Icons.flash_on_rounded),
          ),
          IconButton(
            tooltip: 'Ganti kamera',
            onPressed: () => _controller.switchCamera(),
            icon: const Icon(Icons.cameraswitch_rounded),
          ),
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
          ),
          Center(
            child: Container(
              width: 280,
              height: 160,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white, width: 3),
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
          Positioned(
            left: 24,
            right: 24,
            bottom: 36,
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.65),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text(
                'Arahkan kamera ke barcode produk sampai berhasil terbaca.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

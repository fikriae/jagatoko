
import 'package:supabase_flutter/supabase_flutter.dart';

class DatabaseService {
  final SupabaseClient _supabase = Supabase.instance.client;

  int _toInt(dynamic value) {
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  String? _nullableId(String value) {
    final id = value.trim();
    return id.isEmpty ? null : id;
  }

  Map<String, dynamic> _productToDatabase({
    required String name,
    required int price,
    required int stock,
    required String category,
    required int purchasePrice,
    required String barcode,
    required String imageUrl,
  }) {
    return {
      'name': name.trim(),
      'price': price,
      'purchase_price': purchasePrice,
      'stock': stock,
      'category': category.trim(),
      'barcode': barcode.trim().isEmpty ? null : barcode.trim(),
      'image_url': imageUrl.trim().isEmpty ? null : imageUrl.trim(),
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };
  }

  void _validateProduct({
    required String name,
    required int price,
    required int stock,
    required String category,
    required int purchasePrice,
  }) {
    if (name.trim().isEmpty || category.trim().isEmpty) {
      throw Exception('Nama dan kategori wajib diisi.');
    }

    if (price < 0 || purchasePrice < 0 || stock < 0) {
      throw Exception('Harga dan stok tidak boleh negatif.');
    }
  }

  Future<void> _checkBarcode(
    String barcode, {
    String? excludeProductId,
  }) async {
    final normalizedBarcode = barcode.trim();
    if (normalizedBarcode.isEmpty) return;

    var query = _supabase
        .from('products')
        .select('id')
        .eq('barcode', normalizedBarcode);

    if (excludeProductId != null && excludeProductId.isNotEmpty) {
      query = query.neq('id', excludeProductId);
    }

    final existing = await query.maybeSingle();

    if (existing != null) {
      throw Exception('Barcode sudah digunakan oleh produk lain.');
    }
  }

  // ============================================================
  // USERS / PROFILES
  // ============================================================

  Future<void> createUser({
    required String uid,
    required String name,
    required String email,
  }) async {
    await _supabase.from('profiles').upsert({
      'id': uid,
      'name': name.trim(),
      'email': email.trim(),
    });
  }

  Future<Map<String, dynamic>?> getUserProfile(String uid) async {
    return await _supabase
        .from('profiles')
        .select()
        .eq('id', uid)
        .maybeSingle();
  }

  // ============================================================
  // PRODUCTS
  // ============================================================

  Future<String> addProduct({
    required String name,
    required int price,
    required int stock,
    required String category,
    required int purchasePrice,
    String barcode = '',
    String imageUrl = '',
  }) async {
    _validateProduct(
      name: name,
      price: price,
      stock: stock,
      category: category,
      purchasePrice: purchasePrice,
    );

    await _checkBarcode(barcode);

    final data = _productToDatabase(
      name: name,
      price: price,
      stock: stock,
      category: category,
      purchasePrice: purchasePrice,
      barcode: barcode,
      imageUrl: imageUrl,
    );

    data['created_at'] = DateTime.now().toUtc().toIso8601String();

    final result = await _supabase
        .from('products')
        .insert(data)
        .select('id')
        .single();

    return result['id'].toString();
  }

  Future<void> updateProduct({
    required String productId,
    required String name,
    required int price,
    required int stock,
    required String category,
    required int purchasePrice,
    String barcode = '',
    String imageUrl = '',
  }) async {
    _validateProduct(
      name: name,
      price: price,
      stock: stock,
      category: category,
      purchasePrice: purchasePrice,
    );

    await _checkBarcode(barcode, excludeProductId: productId);

    await _supabase
        .from('products')
        .update(
          _productToDatabase(
            name: name,
            price: price,
            stock: stock,
            category: category,
            purchasePrice: purchasePrice,
            barcode: barcode,
            imageUrl: imageUrl,
          ),
        )
        .eq('id', productId);
  }

  Future<void> deleteProduct(String productId) async {
    await _supabase.from('products').delete().eq('id', productId);
  }

  Stream<List<Map<String, dynamic>>> productsStream() {
    return _supabase
        .from('products')
        .stream(primaryKey: ['id'])
        .order('created_at', ascending: false);
  }

  Future<List<Map<String, dynamic>>> getProducts() async {
    final result = await _supabase
        .from('products')
        .select()
        .order('created_at', ascending: false);

    return List<Map<String, dynamic>>.from(result);
  }

  Future<Map<String, dynamic>?> getProductById(
    String productId,
  ) async {
    return await _supabase
        .from('products')
        .select()
        .eq('id', productId)
        .maybeSingle();
  }

  Future<Map<String, dynamic>?> getProductByBarcode(
    String barcode,
  ) async {
    final normalizedBarcode = barcode.trim();
    if (normalizedBarcode.isEmpty) return null;

    return await _supabase
        .from('products')
        .select()
        .eq('barcode', normalizedBarcode)
        .maybeSingle();
  }

  // ============================================================
  // CUSTOMERS
  // ============================================================

  Future<String> addCustomer({
    required String name,
    required String phone,
    required String address,
  }) async {
    if (name.trim().isEmpty) {
      throw Exception('Nama pelanggan wajib diisi.');
    }

    final result = await _supabase
        .from('customers')
        .insert({
          'name': name.trim(),
          'phone': phone.trim(),
          'address': address.trim(),
        })
        .select('id')
        .single();

    return result['id'].toString();
  }

  Stream<List<Map<String, dynamic>>> customersStream() {
    return _supabase
        .from('customers')
        .stream(primaryKey: ['id'])
        .order('created_at', ascending: false);
  }

  Future<List<Map<String, dynamic>>> getCustomers() async {
    final result = await _supabase
        .from('customers')
        .select()
        .order('created_at', ascending: false);

    return List<Map<String, dynamic>>.from(result);
  }

  // ============================================================
  // TRANSACTIONS
  // ============================================================

  Future<String> createTransaction({
    required String invoice,
    required String customerId,
    required String customerName,
    required int total,
    required int payment,
    required int change,
    required String paymentMethod,
    required String cashierId,
    required String cashierName,
    required List<Map<String, dynamic>> items,
  }) async {
    if (items.isEmpty) {
      throw Exception('Tidak ada produk dalam transaksi.');
    }

    if (total < 0 || payment < total || change < 0) {
      throw Exception('Data pembayaran tidak valid.');
    }

    final transaction = await _supabase
        .from('transactions')
        .insert({
          'invoice': invoice,
          'customer_id': _nullableId(customerId),
          'customer_name': customerName,
          'total': total,
          'payment': payment,
          'change_amount': change,
          'payment_method': paymentMethod,
          'cashier_id': _nullableId(cashierId),
          'cashier_name': cashierName,
        })
        .select('id')
        .single();

    final transactionId = transaction['id'].toString();

    final savedItems = items.map((item) {
      final price = _toInt(item['price']);
      final quantity = _toInt(item['quantity']);
      final subtotal = _toInt(item['subtotal']);

      return {
        'transaction_id': transactionId,
        'product_id': _nullableId(
          item['productId']?.toString() ?? '',
        ),
        'product_name': item['productName']?.toString() ?? 'Produk',
        'price': price,
        'purchase_price': _toInt(item['purchasePrice']),
        'quantity': quantity,
        'subtotal': subtotal == 0 ? price * quantity : subtotal,
        'image_url': item['imageUrl']?.toString(),
      };
    }).toList();

    await _supabase.from('transaction_items').insert(savedItems);

    return transactionId;
  }

  Stream<List<Map<String, dynamic>>> transactionsStream() {
    return _supabase
        .from('transactions')
        .stream(primaryKey: ['id'])
        .order('created_at', ascending: false);
  }

  Future<List<Map<String, dynamic>>> getTransactions() async {
    final result = await _supabase
        .from('transactions')
        .select()
        .order('created_at', ascending: false);

    return List<Map<String, dynamic>>.from(result);
  }

  Future<List<Map<String, dynamic>>> getTransactionItems(
    String transactionId,
  ) async {
    final result = await _supabase
        .from('transaction_items')
        .select()
        .eq('transaction_id', transactionId);

    return List<Map<String, dynamic>>.from(result);
  }

  // ============================================================
  // PROCESS SALE
  // RPC: SIMPAN TRANSAKSI + RINCIAN + KURANGI STOK
  // ============================================================

  Future<String> processSale({
    required String invoice,
    required String customerId,
    required String customerName,
    required int total,
    required int payment,
    required int change,
    required String paymentMethod,
    required String cashierId,
    required String cashierName,
    required List<Map<String, dynamic>> items,
  }) async {
    if (items.isEmpty) {
      throw Exception('Tidak ada produk dalam transaksi.');
    }

    if (total < 0 || payment < total || change < 0) {
      throw Exception('Data pembayaran tidak valid.');
    }

    final normalizedItems = items.map((item) {
      return {
        'productId': item['productId']?.toString() ?? '',
        'productName': item['productName']?.toString() ?? 'Produk',
        'price': _toInt(item['price']),
        'quantity': _toInt(item['quantity']),
        'subtotal': _toInt(item['subtotal']),
        'imageUrl': item['imageUrl']?.toString() ?? '',
      };
    }).toList();

    final result = await _supabase.rpc(
      'process_sale',
      params: {
        'p_invoice': invoice,
        'p_customer_id': _nullableId(customerId),
        'p_customer_name': customerName,
        'p_total': total,
        'p_payment': payment,
        'p_change_amount': change,
        'p_payment_method': paymentMethod,
        'p_cashier_id': _nullableId(cashierId),
        'p_cashier_name': cashierName,
        'p_items': normalizedItems,
      },
    );

    return result.toString();
  }
}

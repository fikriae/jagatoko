import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ProdukPage extends StatefulWidget {
  const ProdukPage({super.key});

  @override
  State<ProdukPage> createState() => _ProdukPageState();
}

class _ProdukPageState extends State<ProdukPage> {
  static const Color _primary = Color(0xFF2563EB);
  static const Color _background = Color(0xFFF5F7FA);
  static const Color _border = Color(0xFFE5E7EB);
  static const Color _textDark = Color(0xFF111827);
  static const Color _textMuted = Color(0xFF64748B);
  static const int _lowStockLimit = 5;
  static const String _allCategories = 'Semua';

  final SupabaseClient _supabase = Supabase.instance.client;
  final ImagePicker _imagePicker = ImagePicker();
  final TextEditingController _searchController = TextEditingController();

  String _searchQuery = '';
  String _selectedCategory = _allCategories;
  bool _isLoading = false;
  List<Map<String, dynamic>> _products = [];

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
    _loadProducts();
  }

  void _onSearchChanged() {
    if (!mounted) return;
    setState(() {
      _searchQuery = _searchController.text.trim().toLowerCase();
    });
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    super.dispose();
  }

  String _formatRupiah(int value) {
    final number = value.abs().toString();
    final result = StringBuffer();

    for (int i = 0; i < number.length; i++) {
      result.write(number[i]);
      final position = number.length - i;

      if (position > 1 && position % 3 == 1) {
        result.write('.');
      }
    }

    return value < 0 ? '-Rp $result' : 'Rp $result';
  }

  int _toInt(dynamic value) {
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  InputDecoration _inputDecoration({
    required String label,
    required IconData icon,
    String? prefixText,
    Widget? suffixIcon,
  }) {
    return InputDecoration(
      labelText: label,
      prefixText: prefixText,
      prefixIcon: Icon(icon, size: 20, color: _textMuted),
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: const Color(0xFFF8FAFC),
      contentPadding: const EdgeInsets.symmetric(
        horizontal: 14,
        vertical: 14,
      ),
      labelStyle: const TextStyle(fontSize: 13, color: _textMuted),
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
        borderSide: const BorderSide(color: _primary, width: 1.5),
      ),
    );
  }

  Future<void> _loadProducts({bool showError = true}) async {
    if (!mounted) return;

    setState(() => _isLoading = true);

    try {
      final productResponse = await _supabase
          .from('products')
          .select()
          .order('created_at', ascending: false);

      final costResponse =
          await _supabase.from('product_costs').select(
                'product_id, purchase_price',
              );

      final costs = <String, int>{};

      for (final row in costResponse) {
        final productId = row['product_id']?.toString();
        if (productId != null) {
          costs[productId] = _toInt(row['purchase_price']);
        }
      }

      final loadedProducts = <Map<String, dynamic>>[];

      for (final row in productResponse) {
        final product = Map<String, dynamic>.from(row);
        final id = product['id']?.toString() ?? '';

        product['purchase_price'] = costs[id] ?? 0;
        loadedProducts.add(product);
      }

      if (!mounted) return;

      setState(() {
        _products = loadedProducts;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() => _isLoading = false);

      if (showError) {
        _showMessage(
          'Gagal mengambil data produk: $e',
          isError: true,
        );
      }
    }
  }

  Future<XFile?> _pickImage() async {
    try {
      return await _imagePicker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
        maxWidth: 1200,
        maxHeight: 1200,
      );
    } catch (e) {
      if (!mounted) return null;
      _showMessage('Gagal memilih gambar: $e', isError: true);
      return null;
    }
  }

  Future<String> _uploadProductImage(XFile file) async {
    final originalName =
        file.name.isNotEmpty ? file.name : 'product_image.jpg';

    final extension = originalName.contains('.')
        ? originalName.split('.').last.toLowerCase()
        : 'jpg';

    final safeExtension =
        RegExp(r'^[a-z0-9]+$').hasMatch(extension) ? extension : 'jpg';

    final fileName =
        '${DateTime.now().millisecondsSinceEpoch}_${DateTime.now().microsecond}.$safeExtension';

    final bytes = await file.readAsBytes();

    await _supabase.storage.from('products').uploadBinary(
          fileName,
          bytes,
          fileOptions: FileOptions(
            contentType: _contentType(safeExtension),
            upsert: false,
          ),
        );

    return _supabase.storage.from('products').getPublicUrl(fileName);
  }

  String _contentType(String extension) {
    switch (extension) {
      case 'png':
        return 'image/png';
      case 'webp':
        return 'image/webp';
      case 'gif':
        return 'image/gif';
      case 'heic':
        return 'image/heic';
      default:
        return 'image/jpeg';
    }
  }

  String? _storagePathFromUrl(String url) {
    try {
      final uri = Uri.parse(url);
      final marker = '/storage/v1/object/public/products/';
      final index = uri.path.indexOf(marker);

      if (index < 0) return null;

      return Uri.decodeComponent(
        uri.path.substring(index + marker.length),
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> _deleteStorageImage(String url) async {
    if (url.isEmpty) return;

    final path = _storagePathFromUrl(url);
    if (path == null || path.isEmpty) return;

    try {
      await _supabase.storage.from('products').remove([path]);
    } catch (_) {
      // Penghapusan gambar tidak membatalkan perubahan data produk.
    }
  }

  void _showMessage(String message, {bool isError = false}) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : null,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _showProductForm({
    String? productId,
    String? currentName,
    int? currentPrice,
    int? currentPurchasePrice,
    int? currentStock,
    String? currentCategory,
    String? currentBarcode,
    String? currentImageUrl,
  }) async {
    final nameController = TextEditingController(text: currentName ?? '');
    final priceController = TextEditingController(
      text: currentPrice?.toString() ?? '',
    );
    final purchasePriceController = TextEditingController(
      text: currentPurchasePrice?.toString() ?? '',
    );
    final stockController = TextEditingController(
      text: currentStock?.toString() ?? '',
    );
    final categoryController = TextEditingController(
      text: currentCategory ?? '',
    );
    final barcodeController = TextEditingController(
      text: currentBarcode ?? '',
    );

    final isEdit = productId != null;
    XFile? selectedImage;
    String imageUrl = currentImageUrl ?? '';
    bool isSaving = false;

    try {
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          return StatefulBuilder(
            builder: (context, setDialogState) {
              Future<void> chooseImage() async {
                if (isSaving) return;

                final image = await _pickImage();

                if (image == null || !dialogContext.mounted) return;

                setDialogState(() {
                  selectedImage = image;
                });
              }

              Future<void> scanBarcode() async {
                if (isSaving) return;

                final scannedCode =
                    await Navigator.of(dialogContext).push<String>(
                  MaterialPageRoute(
                    builder: (_) => const _BarcodeScannerPage(),
                  ),
                );

                if (scannedCode != null && dialogContext.mounted) {
                  setDialogState(() {
                    barcodeController.text = scannedCode;
                  });
                }
              }

              Future<void> saveProduct() async {
                final name = nameController.text.trim();
                final price = int.tryParse(priceController.text.trim());
                final purchasePrice =
                    int.tryParse(purchasePriceController.text.trim());
                final stock = int.tryParse(stockController.text.trim());
                final category = categoryController.text.trim();
                final barcode = barcodeController.text.trim();

                if (name.isEmpty ||
                    price == null ||
                    price < 0 ||
                    purchasePrice == null ||
                    purchasePrice < 0 ||
                    stock == null ||
                    stock < 0 ||
                    category.isEmpty) {
                  ScaffoldMessenger.of(dialogContext).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Nama, harga jual, harga beli, stok, dan kategori harus diisi dengan benar.',
                      ),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                  return;
                }

                setDialogState(() => isSaving = true);

                String? newlyUploadedUrl;

                try {
                  if (barcode.isNotEmpty) {
                    var duplicateQuery = _supabase
                        .from('products')
                        .select('id')
                        .eq('barcode', barcode);

                    final duplicateRows = await duplicateQuery;

                    final duplicateExists = duplicateRows.any(
                      (row) => row['id'].toString() != productId,
                    );

                    if (duplicateExists) {
                      if (dialogContext.mounted) {
                        setDialogState(() => isSaving = false);
                        ScaffoldMessenger.of(dialogContext).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Barcode sudah digunakan oleh produk lain.',
                            ),
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                      }
                      return;
                    }
                  }

                  if (selectedImage != null) {
                    newlyUploadedUrl =
                        await _uploadProductImage(selectedImage!);
                    imageUrl = newlyUploadedUrl;
                  }

                  final now = DateTime.now().toUtc().toIso8601String();

                  final productData = <String, dynamic>{
                    'name': name,
                    'selling_price': price,
                    'stock': stock,
                    'category': category,
                    'barcode': barcode.isEmpty ? null : barcode,
                    'image_url': imageUrl.isEmpty ? null : imageUrl,
                    'is_active': true,
                    'updated_at': now,
                  };

                  String savedProductId;

                  if (isEdit) {
                    await _supabase
                        .from('products')
                        .update(productData)
                        .eq('id', productId);

                    savedProductId = productId;
                  } else {
                    final inserted = await _supabase
                        .from('products')
                        .insert({
                          ...productData,
                          'created_at': now,
                        })
                        .select('id')
                        .single();

                    savedProductId = inserted['id'].toString();
                  }

                  await _supabase.from('product_costs').upsert(
                    {
                      'product_id': savedProductId,
                      'purchase_price': purchasePrice,
                      'updated_at': now,
                    },
                    onConflict: 'product_id',
                  );

                  if (selectedImage != null &&
                      currentImageUrl != null &&
                      currentImageUrl.isNotEmpty &&
                      currentImageUrl != imageUrl) {
                    await _deleteStorageImage(currentImageUrl);
                  }

                  if (!dialogContext.mounted) return;

                  Navigator.of(dialogContext).pop();

                  _showMessage(
                    isEdit
                        ? 'Produk berhasil diperbarui.'
                        : 'Produk berhasil ditambahkan.',
                  );

                  await _loadProducts(showError: false);
                } catch (e) {
                  if (newlyUploadedUrl != null) {
                    await _deleteStorageImage(newlyUploadedUrl);
                  }

                  if (!dialogContext.mounted) return;

                  setDialogState(() => isSaving = false);

                  ScaffoldMessenger.of(dialogContext).showSnackBar(
                    SnackBar(
                      content: Text('Gagal menyimpan produk: $e'),
                      backgroundColor: Colors.red,
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                }
              }

              return AlertDialog(
                backgroundColor: Colors.white,
                surfaceTintColor: Colors.transparent,
                insetPadding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 24,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(22),
                ),
                title: Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: const Color(0xFFEFF6FF),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        isEdit
                            ? Icons.edit_outlined
                            : Icons.add_box_outlined,
                        color: _primary,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isEdit ? 'Edit Produk' : 'Tambah Produk',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: _textDark,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            isEdit
                                ? 'Perbarui data produk Anda.'
                                : 'Isi data produk baru.',
                            style: const TextStyle(
                              fontSize: 12,
                              color: _textMuted,
                              fontWeight: FontWeight.normal,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                content: SingleChildScrollView(
                  child: SizedBox(
                    width: 420,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        GestureDetector(
                          onTap: isSaving ? null : chooseImage,
                          child: Container(
                            width: double.infinity,
                            height: 150,
                            decoration: BoxDecoration(
                              color: const Color(0xFFF8FAFC),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: _border),
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: selectedImage != null
                                ? _SelectedImagePreview(file: selectedImage!)
                                : imageUrl.isNotEmpty
                                    ? Image.network(
                                        imageUrl,
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, __, ___) =>
                                            const _ImageEmptyState(),
                                      )
                                    : const _ImageEmptyState(),
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: barcodeController,
                          enabled: !isSaving,
                          decoration: _inputDecoration(
                            label: 'Barcode (opsional)',
                            icon: Icons.qr_code_2_rounded,
                            suffixIcon: IconButton(
                              tooltip: 'Scan barcode',
                              onPressed: isSaving ? null : scanBarcode,
                              icon: const Icon(
                                Icons.camera_alt_outlined,
                                color: _primary,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: nameController,
                          enabled: !isSaving,
                          textCapitalization: TextCapitalization.words,
                          textInputAction: TextInputAction.next,
                          decoration: _inputDecoration(
                            label: 'Nama Produk',
                            icon: Icons.inventory_2_outlined,
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: priceController,
                          enabled: !isSaving,
                          keyboardType: TextInputType.number,
                          textInputAction: TextInputAction.next,
                          decoration: _inputDecoration(
                            label: 'Harga Jual',
                            icon: Icons.payments_outlined,
                            prefixText: 'Rp ',
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: purchasePriceController,
                          enabled: !isSaving,
                          keyboardType: TextInputType.number,
                          textInputAction: TextInputAction.next,
                          decoration: _inputDecoration(
                            label: 'Harga Beli / Kulak',
                            icon: Icons.shopping_cart_outlined,
                            prefixText: 'Rp ',
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: stockController,
                          enabled: !isSaving,
                          keyboardType: TextInputType.number,
                          textInputAction: TextInputAction.next,
                          decoration: _inputDecoration(
                            label: 'Stok',
                            icon: Icons.inventory_outlined,
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: categoryController,
                          enabled: !isSaving,
                          textCapitalization: TextCapitalization.words,
                          textInputAction: TextInputAction.done,
                          decoration: _inputDecoration(
                            label: 'Kategori',
                            icon: Icons.category_outlined,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                actions: [
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: isSaving
                              ? null
                              : () => Navigator.of(dialogContext).pop(),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: _textMuted,
                            side: const BorderSide(color: _border),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: const Text('Batal'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: isSaving ? null : saveProduct,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _primary,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: isSaving
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : Text(isEdit ? 'Simpan' : 'Tambah'),
                        ),
                      ),
                    ],
                  ),
                ],
              );
            },
          );
        },
      );
    } finally {
      nameController.dispose();
      priceController.dispose();
      purchasePriceController.dispose();
      stockController.dispose();
      categoryController.dispose();
      barcodeController.dispose();
    }
  }

  Future<void> _deleteProduct(
    String productId,
    String productName,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
          ),
          title: const Text('Hapus Produk'),
          content: Text(
            'Apakah Anda yakin ingin menghapus "$productName"? '
            'Tindakan ini tidak dapat dibatalkan.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Batal'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFDC2626),
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Hapus'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;

    try {
      final product = _products.firstWhere(
        (item) => item['id'].toString() == productId,
        orElse: () => <String, dynamic>{},
      );

      final imageUrl = (product['image_url'] ?? '').toString();

      await _supabase
          .from('product_costs')
          .delete()
          .eq('product_id', productId);

      await _supabase.from('products').delete().eq('id', productId);

      await _deleteStorageImage(imageUrl);

      _showMessage('Produk berhasil dihapus.');
      await _loadProducts(showError: false);
    } catch (e) {
      _showMessage('Gagal menghapus produk: $e', isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final activeProducts = _products.where((product) {
      return product['is_active'] != false;
    }).toList();

    final categories = <String>{};

    for (final product in activeProducts) {
      final category =
          (product['category'] ?? '').toString().trim();
      if (category.isNotEmpty) categories.add(category);
    }

    final categoryList = categories.toList()..sort();
    final activeCategory = categories.contains(_selectedCategory)
        ? _selectedCategory
        : _allCategories;

    final products = activeProducts.where((product) {
      final name = (product['name'] ?? '').toString().toLowerCase();
      final category =
          (product['category'] ?? '').toString().toLowerCase();
      final barcode =
          (product['barcode'] ?? '').toString().toLowerCase();

      final matchSearch = name.contains(_searchQuery) ||
          category.contains(_searchQuery) ||
          barcode.contains(_searchQuery);

      final matchCategory = activeCategory == _allCategories ||
          (product['category'] ?? '').toString().trim() ==
              activeCategory;

      return matchSearch && matchCategory;
    }).toList();

    final lowStockCount = activeProducts.where((product) {
      return _toInt(product['stock']) <= _lowStockLimit;
    }).length;

    return Scaffold(
      backgroundColor: _background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        foregroundColor: _textDark,
        shadowColor: const Color(0x26000000),
        elevation: 3,
        scrolledUnderElevation: 3,
        toolbarHeight: 72,
        centerTitle: false,
        titleSpacing: 20,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            bottom: Radius.circular(24),
          ),
        ),
        title: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: const Color(0xFFEFF6FF),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.inventory_2_outlined,
                color: _primary,
                size: 22,
              ),
            ),
            const SizedBox(width: 12),
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Produk',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: _textDark,
                  ),
                ),
                SizedBox(height: 1),
                Text(
                  'Kelola stok dan harga',
                  style: TextStyle(
                    fontSize: 11,
                    color: _textMuted,
                    fontWeight: FontWeight.normal,
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Muat ulang',
            onPressed: _isLoading
                ? null
                : () => _loadProducts(),
            icon: const Icon(Icons.refresh_rounded),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _isLoading && _products.isEmpty
          ? const Center(
              child: CircularProgressIndicator(color: _primary),
            )
          : RefreshIndicator(
              onRefresh: _loadProducts,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
                    child: TextField(
                      controller: _searchController,
                      decoration: InputDecoration(
                        hintText: 'Cari produk atau kategori...',
                        hintStyle: const TextStyle(
                          fontSize: 14,
                          color: Color(0xFF94A3B8),
                        ),
                        prefixIcon: const Icon(
                          Icons.search_rounded,
                          color: _textMuted,
                        ),
                        suffixIcon: _searchQuery.isNotEmpty
                            ? IconButton(
                                onPressed: _searchController.clear,
                                icon: const Icon(
                                  Icons.close_rounded,
                                  size: 20,
                                  color: _textMuted,
                                ),
                              )
                            : null,
                        filled: true,
                        fillColor: Colors.white,
                        contentPadding:
                            const EdgeInsets.symmetric(vertical: 14),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: const BorderSide(color: _border),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: const BorderSide(color: _border),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: const BorderSide(
                            color: _primary,
                            width: 1.5,
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (activeProducts.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                      child: Row(
                        children: [
                          _SummaryChip(
                            icon: Icons.inventory_2_outlined,
                            label: '${activeProducts.length} produk',
                            color: _primary,
                            background: const Color(0xFFEFF6FF),
                          ),
                          if (lowStockCount > 0) ...[
                            const SizedBox(width: 8),
                            _SummaryChip(
                              icon: Icons.warning_amber_rounded,
                              label: '$lowStockCount stok menipis',
                              color: const Color(0xFFDC2626),
                              background: const Color(0xFFFEF2F2),
                            ),
                          ],
                        ],
                      ),
                    ),
                  if (categoryList.isNotEmpty)
                    SizedBox(
                      height: 38,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        padding:
                            const EdgeInsets.symmetric(horizontal: 16),
                        children: [
                          for (final category in [
                            _allCategories,
                            ...categoryList,
                          ])
                            Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: _CategoryChip(
                                label: category,
                                selected: category == activeCategory,
                                onTap: () {
                                  setState(
                                    () => _selectedCategory = category,
                                  );
                                },
                              ),
                            ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 6),
                  Expanded(
                    child: products.isEmpty
                        ? _buildEmptyState(activeProducts.isEmpty)
                        : ListView.builder(
                            physics:
                                const AlwaysScrollableScrollPhysics(),
                            padding: const EdgeInsets.fromLTRB(
                              16,
                              8,
                              16,
                              100,
                            ),
                            itemCount: products.length,
                            itemBuilder: (context, index) {
                              return _buildProductCard(products[index]);
                            },
                          ),
                  ),
                ],
              ),
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showProductForm(),
        backgroundColor: _primary,
        foregroundColor: Colors.white,
        elevation: 3,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        icon: const Icon(Icons.add_rounded),
        label: const Text(
          'Tambah Produk',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
    );
  }

  Widget _buildEmptyState(bool noProductsAtAll) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        SizedBox(
          height: 350,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 88,
                    height: 88,
                    decoration: const BoxDecoration(
                      color: Color(0xFFEFF6FF),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      noProductsAtAll
                          ? Icons.inventory_2_outlined
                          : Icons.search_off_rounded,
                      size: 42,
                      color: _primary,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    noProductsAtAll
                        ? 'Belum ada produk'
                        : 'Produk tidak ditemukan',
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                      color: _textDark,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    noProductsAtAll
                        ? 'Tambahkan produk pertama Anda.'
                        : 'Coba gunakan kata pencarian atau kategori lain.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 13,
                      color: _textMuted,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildProductCard(Map<String, dynamic> product) {
    final id = product['id'].toString();
    final name = (product['name'] ?? '').toString();
    final category = (product['category'] ?? '').toString();
    final barcode = (product['barcode'] ?? '').toString();
    final imageUrl = (product['image_url'] ?? '').toString();
    final price = _toInt(product['selling_price']);
    final stock = _toInt(product['stock']);

    final isEmpty = stock <= 0;
    final isLow = stock <= _lowStockLimit;

    final stockColor = isEmpty
        ? const Color(0xFFDC2626)
        : isLow
            ? const Color(0xFFD97706)
            : const Color(0xFF16A34A);

    final stockBackground = isEmpty
        ? const Color(0xFFFEE2E2)
        : isLow
            ? const Color(0xFFFEF3C7)
            : const Color(0xFFDCFCE7);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _border),
      ),
      child: Row(
        children: [
          _ProductImage(imageUrl: imageUrl),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: _textDark,
                  ),
                ),
                if (category.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      category,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: _textMuted,
                      ),
                    ),
                  ),
                ],
                if (barcode.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(
                        Icons.qr_code_2_rounded,
                        size: 13,
                        color: _textMuted,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          barcode,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 11,
                            color: _textMuted,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 7),
                Wrap(
                  spacing: 8,
                  runSpacing: 5,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      _formatRupiah(price),
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: _primary,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: stockBackground,
                        borderRadius: BorderRadius.circular(7),
                      ),
                      child: Text(
                        isEmpty ? 'Habis' : 'Stok $stock',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: stockColor,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          PopupMenuButton<String>(
            icon: const Icon(
              Icons.more_vert_rounded,
              color: _textMuted,
            ),
            color: Colors.white,
            surfaceTintColor: Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            onSelected: (value) {
              if (value == 'edit') {
                _showProductForm(
                  productId: id,
                  currentName: name,
                  currentPrice: price,
                  currentPurchasePrice:
                      _toInt(product['purchase_price']),
                  currentStock: stock,
                  currentCategory: category,
                  currentBarcode: barcode,
                  currentImageUrl: imageUrl,
                );
              } else if (value == 'delete') {
                _deleteProduct(id, name);
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem<String>(
                value: 'edit',
                child: Row(
                  children: [
                    Icon(
                      Icons.edit_outlined,
                      size: 20,
                      color: _primary,
                    ),
                    SizedBox(width: 10),
                    Text('Edit'),
                  ],
                ),
              ),
              PopupMenuItem<String>(
                value: 'delete',
                child: Row(
                  children: [
                    Icon(
                      Icons.delete_outline_rounded,
                      size: 20,
                      color: Color(0xFFDC2626),
                    ),
                    SizedBox(width: 10),
                    Text(
                      'Hapus',
                      style: TextStyle(color: Color(0xFFDC2626)),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SummaryChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final Color background;

  const _SummaryChip({
    required this.icon,
    required this.label,
    required this.color,
    required this.background,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _CategoryChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? const Color(0xFF2563EB) : Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected
                  ? const Color(0xFF2563EB)
                  : const Color(0xFFE5E7EB),
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: selected ? Colors.white : const Color(0xFF64748B),
            ),
          ),
        ),
      ),
    );
  }
}

class _SelectedImagePreview extends StatelessWidget {
  final XFile file;

  const _SelectedImagePreview({required this.file});

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) {
      return FutureBuilder<Uint8List>(
        future: file.readAsBytes(),
        builder: (context, snapshot) {
          if (snapshot.hasData) {
            return Image.memory(snapshot.data!, fit: BoxFit.cover);
          }

          if (snapshot.hasError) {
            return const _ImageEmptyState();
          }

          return const Center(
            child: CircularProgressIndicator(),
          );
        },
      );
    }

    return Image.file(
      File(file.path),
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => const _ImageEmptyState(),
    );
  }
}

class _ProductImage extends StatelessWidget {
  final String imageUrl;

  const _ProductImage({required this.imageUrl});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 76,
      height: 76,
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(14),
      ),
      clipBehavior: Clip.antiAlias,
      child: imageUrl.isNotEmpty
          ? Image.network(
              imageUrl,
              fit: BoxFit.cover,
              loadingBuilder: (context, child, progress) {
                if (progress == null) return child;

                return const Center(
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Color(0xFF2563EB),
                    ),
                  ),
                );
              },
              errorBuilder: (_, __, ___) => const _ImagePlaceholder(),
            )
          : const _ImagePlaceholder(),
    );
  }
}

class _ImagePlaceholder extends StatelessWidget {
  const _ImagePlaceholder();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Icon(
        Icons.image_outlined,
        size: 28,
        color: Color(0xFF94A3B8),
      ),
    );
  }
}

class _ImageEmptyState extends StatelessWidget {
  const _ImageEmptyState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.add_photo_alternate_outlined,
            size: 38,
            color: Color(0xFF2563EB),
          ),
          SizedBox(height: 8),
          Text(
            'Pilih Gambar Produk',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Color(0xFF64748B),
            ),
          ),
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
  bool _hasScanned = false;

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
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(onDetect: _onDetect),
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

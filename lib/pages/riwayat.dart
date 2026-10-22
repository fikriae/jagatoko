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
const Color _darkText = Color(0xFF0F172A);

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
  String _currentRole = 'kasir';
  bool _isRefreshing = false;
  Future<List<Map<String, dynamic>>>? _transactionsFuture;

  @override
  void initState() {
    super.initState();
    _transactionsFuture = _fetchTransactions();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<List<Map<String, dynamic>>> _fetchTransactions() async {
    final user = _supabase.auth.currentUser;
    if (user == null) {
      throw Exception('Sesi login tidak ditemukan. Silakan login kembali.');
    }

    try {
      final profile = await _supabase
          .from('profiles')
          .select('role')
          .eq('id', user.id)
          .maybeSingle();
      _currentRole = (profile?['role'] ?? 'kasir').toString().toLowerCase().trim();
    } catch (e) {
      _currentRole = 'kasir';
      debugPrint('Gagal memeriksa role pengguna: $e');
    }

    final response = await _supabase
        .from('transactions')
        .select()
        .eq('is_hidden', false)
        .order('created_at', ascending: false);
    final transactions = List<Map<String, dynamic>>.from(
      (response as List).map((item) => Map<String, dynamic>.from(item)),
    );

    final cashierIds = transactions
        .map((item) => item['cashier_id']?.toString())
        .whereType<String>()
        .where((id) => id.trim().isNotEmpty)
        .toSet()
        .toList();

    if (cashierIds.isNotEmpty) {
      try {
        final responseProfiles = await _supabase
            .from('profiles')
            .select('id, full_name')
            .inFilter('id', cashierIds);
        final namesById = <String, String>{};
        for (final raw in responseProfiles as List) {
          final profile = Map<String, dynamic>.from(raw);
          final id = profile['id']?.toString() ?? '';
          final name = profile['full_name']?.toString().trim() ?? '';
          if (id.isNotEmpty && name.isNotEmpty) namesById[id] = name;
        }
        for (final transaction in transactions) {
          final id = transaction['cashier_id']?.toString() ?? '';
          transaction['_resolved_cashier_name'] =
              namesById[id] ?? 'Nama kasir tidak tersedia';
        }
      } catch (e) {
        debugPrint('Gagal mengambil nama kasir: $e');
        for (final transaction in transactions) {
          transaction['_cashier_profile_error'] = true;
        }
      }
    }
    return transactions;
  }

  int _toInt(dynamic value) {
    if (value is num) return value.round();
    final text = value?.toString().trim() ?? '';
    return int.tryParse(text) ?? double.tryParse(text)?.round() ?? 0;
  }

  String _rupiah(num value) {
    final digits = value.abs().round().toString();
    final result = StringBuffer();
    for (int i = 0; i < digits.length; i++) {
      result.write(digits[i]);
      final remaining = digits.length - i - 1;
      if (remaining > 0 && remaining % 3 == 0) result.write('.');
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
        '${date.year}, ${date.hour.toString().padLeft(2, '0')}:'
        '${date.minute.toString().padLeft(2, '0')}';
  }

  String _invoice(Map<String, dynamic> data) =>
      (data['invoice_number'] ?? data['invoice'] ?? data['id'] ?? '-').toString();

  String _customer(Map<String, dynamic> data) {
    final value = (data['customer_name'] ?? data['customerName'] ?? 'Umum')
        .toString()
        .trim();
    return value.isEmpty ? 'Umum' : value;
  }

  String _paymentMethod(Map<String, dynamic> data) =>
      (data['payment_method'] ?? data['paymentMethod'] ?? 'cash')
          .toString()
          .toLowerCase();

  String _cashierName(Map<String, dynamic> data) {
    final resolved = data['_resolved_cashier_name']?.toString().trim() ?? '';
    if (resolved.isNotEmpty && resolved != 'Nama kasir tidak tersedia') {
      return resolved;
    }
    for (final key in ['nama_kasir', 'cashier_name', 'cashierName', 'kasir_name', 'full_name']) {
      final value = data[key]?.toString().trim() ?? '';
      if (value.isNotEmpty) return value;
    }
    return 'Nama kasir tidak tersedia';
  }

  List<Map<String, dynamic>> _filterTransactions(
    List<Map<String, dynamic>> transactions,
  ) {
    final query = _searchQuery.trim().toLowerCase();
    return transactions.where((item) {
      final method = _paymentMethod(item);
      final matchesSearch = query.isEmpty ||
          _invoice(item).toLowerCase().contains(query) ||
          _customer(item).toLowerCase().contains(query) ||
          _cashierName(item).toLowerCase().contains(query);
      final matchesPayment = _paymentFilter == 'semua' ||
          (_paymentFilter == 'cash' && (method == 'cash' || method == 'tunai')) ||
          (_paymentFilter == 'qris' && method == 'qris');
      return matchesSearch && matchesPayment;
    }).toList();
  }

  Future<void> _refreshTransactions() async {
    if (_isRefreshing) return;
    setState(() {
      _isRefreshing = true;
      _transactionsFuture = _fetchTransactions();
    });
    try {
      await _transactionsFuture!;
      if (mounted) _showMessage('Riwayat transaksi berhasil diperbarui.');
    } catch (e) {
      if (mounted) _showMessage('Gagal memuat riwayat transaksi: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isRefreshing = false);
    }
  }

  void _showMessage(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(message),
        backgroundColor: isError ? _danger : const Color(0xFF15803D),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ));
  }

  Future<void> _openDetail(Map<String, dynamic> transaction) async {
    final id = transaction['id']?.toString();
    if (id == null || id.isEmpty) {
      _showMessage('ID transaksi tidak ditemukan.', isError: true);
      return;
    }
    await Navigator.push(context, MaterialPageRoute(
      builder: (_) => TransactionDetailPage(
        transactionId: id,
        data: Map<String, dynamic>.from(transaction),
      ),
    ));
  }

  Future<void> _hideTransaction(Map<String, dynamic> transaction) async {
    final user = _supabase.auth.currentUser;
    if (user == null) {
      _showMessage('Sesi login tidak ditemukan. Silakan login kembali.', isError: true);
      return;
    }
    final id = transaction['id']?.toString();
    if (id == null || id.isEmpty) {
      _showMessage('ID transaksi tidak ditemukan.', isError: true);
      return;
    }
    final isOwner = _currentRole == 'owner';
    final isOwnTransaction = transaction['cashier_id']?.toString() == user.id;
    if (!isOwner && !isOwnTransaction) {
      _showMessage('Anda tidak dapat menghapus transaksi milik kasir lain.', isError: true);
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        icon: const Icon(Icons.delete_outline_rounded, color: _danger, size: 32),
        title: const Text('Hapus riwayat transaksi?'),
        content: Text('Riwayat ${_invoice(transaction)} akan disembunyikan. Data transaksi dan detail barang tetap tersimpan di database.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Batal')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: _danger),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Hapus riwayat'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _isRefreshing = true);
    try {
      final List<dynamic> result;
      if (isOwner) {
        result = await _supabase.from('transactions')
            .update({'is_hidden': true}).eq('id', id).eq('is_hidden', false).select('id');
      } else {
        result = await _supabase.from('transactions')
            .update({'is_hidden': true}).eq('id', id).eq('cashier_id', user.id)
            .eq('is_hidden', false).select('id');
      }
      if (result.isEmpty) {
        if (mounted) _showMessage('Riwayat tidak dapat dihapus. Periksa status transaksi dan kebijakan UPDATE RLS Supabase.', isError: true);
        return;
      }
      if (!mounted) return;
      setState(() => _transactionsFuture = _fetchTransactions());
      await _transactionsFuture!;
      if (mounted) _showMessage('Riwayat transaksi berhasil disembunyikan.');
    } catch (e) {
      if (mounted) _showMessage('Gagal menghapus riwayat transaksi. Periksa kebijakan UPDATE RLS Supabase.\n$e', isError: true);
    } finally {
      if (mounted) setState(() => _isRefreshing = false);
    }
  }

  Widget _paymentBadge(String method) {
    final isQris = method == 'qris';
    final color = isQris ? const Color(0xFF7C3AED) : const Color(0xFF15803D);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: isQris ? const Color(0xFFF3E8FF) : const Color(0xFFDCFCE7),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(isQris ? Icons.qr_code_2_rounded : Icons.payments_outlined, size: 14, color: color),
        const SizedBox(width: 4),
        Text(isQris ? 'QRIS' : 'Cash', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: color)),
      ]),
    );
  }

  Widget _filterChip(String label, String value) {
    final selected = _paymentFilter == value;
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.only(right: 8),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => setState(() => _paymentFilter = value),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(vertical: 11),
            decoration: BoxDecoration(
              color: selected ? _primary : Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: selected ? _primary : _border),
              boxShadow: selected ? [BoxShadow(color: _primary.withValues(alpha: .15), blurRadius: 9, offset: const Offset(0, 3))] : null,
            ),
            child: Center(child: Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: selected ? Colors.white : _secondaryText))),
          ),
        ),
      ),
    );
  }

  Widget _buildTransactionCard(Map<String, dynamic> transaction) {
    final method = _paymentMethod(transaction);
    final total = _toInt(transaction['total']);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _border),
        boxShadow: const [BoxShadow(color: Color(0x080F172A), blurRadius: 12, offset: Offset(0, 4))],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => _openDetail(transaction),
          child: Padding(
            padding: const EdgeInsets.all(15),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Container(
                  width: 46, height: 46,
                  decoration: BoxDecoration(color: const Color(0xFFEFF6FF), borderRadius: BorderRadius.circular(14)),
                  child: const Icon(Icons.receipt_long_rounded, color: _primary, size: 23),
                ),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(_invoice(transaction), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: _darkText)),
                  const SizedBox(height: 5),
                  Row(children: [const Icon(Icons.schedule_rounded, size: 13, color: _secondaryText), const SizedBox(width: 4), Expanded(child: Text(_dateTime(transaction['created_at'] ?? transaction['createdAt']), style: const TextStyle(fontSize: 11, color: _secondaryText))) ]),
                ])),
                PopupMenuButton<String>(
                  tooltip: 'Pilihan transaksi',
                  icon: const Icon(Icons.more_vert_rounded, color: _secondaryText),
                  onSelected: (value) {
                    if (value == 'hide') _hideTransaction(transaction);
                    if (value == 'detail') _openDetail(transaction);
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'detail', child: Row(children: [Icon(Icons.visibility_outlined, size: 19), SizedBox(width: 9), Text('Lihat detail')])),
                    PopupMenuItem(value: 'hide', child: Row(children: [Icon(Icons.delete_outline_rounded, color: _danger, size: 19), SizedBox(width: 9), Text('Hapus riwayat', style: TextStyle(color: _danger))])),
                  ],
                ),
              ]),
              const Padding(padding: EdgeInsets.symmetric(vertical: 13), child: Divider(height: 1, color: _border)),
              Row(children: [
                const Icon(Icons.person_outline_rounded, size: 17, color: _secondaryText),
                const SizedBox(width: 7),
                Expanded(child: Text(_customer(transaction), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: Color(0xFF334155)))),
                _paymentBadge(method),
              ]),
              const SizedBox(height: 9),
              Row(children: [
                const Icon(Icons.badge_outlined, size: 17, color: _secondaryText),
                const SizedBox(width: 7),
                Expanded(child: Text(_cashierName(transaction), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: Color(0xFF334155), fontWeight: FontWeight.w600))),
              ]),
              const SizedBox(height: 13),
              Container(
                padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
                decoration: BoxDecoration(color: const Color(0xFFF8FAFC), borderRadius: BorderRadius.circular(12)),
                child: Row(children: [
                  const Expanded(child: Text('Total transaksi', style: TextStyle(fontSize: 12, color: _secondaryText, fontWeight: FontWeight.w600))),
                  Flexible(child: Text(_rupiah(total), textAlign: TextAlign.right, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: _primary))),
                ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _emptyState({required String title, required String message, IconData icon = Icons.receipt_long_outlined}) {
    return Center(child: SingleChildScrollView(child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 84, height: 84, decoration: const BoxDecoration(color: Color(0xFFEFF6FF), shape: BoxShape.circle), child: Icon(icon, size: 39, color: _primary)),
        const SizedBox(height: 18),
        Text(title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: _darkText)),
        const SizedBox(height: 8),
        Text(message, textAlign: TextAlign.center, style: const TextStyle(color: _secondaryText, height: 1.5, fontSize: 13)),
        const SizedBox(height: 16),
        OutlinedButton.icon(onPressed: _refreshTransactions, icon: const Icon(Icons.refresh_rounded), label: const Text('Muat ulang'), style: OutlinedButton.styleFrom(foregroundColor: _primary, side: const BorderSide(color: _primary), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)))),
      ]),
    )));
  }

  Widget _searchAndFilters() {
    return Container(
      color: _background,
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
      child: Column(children: [
        TextField(
          controller: _searchController,
          onChanged: (value) => setState(() => _searchQuery = value),
          style: const TextStyle(fontSize: 14, color: _darkText),
          decoration: InputDecoration(
            hintText: 'Cari invoice, pelanggan, atau kasir...',
            hintStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
            prefixIcon: const Icon(Icons.search_rounded, color: _primary),
            suffixIcon: _searchQuery.isNotEmpty ? IconButton(onPressed: () { _searchController.clear(); setState(() => _searchQuery = ''); }, icon: const Icon(Icons.close_rounded, color: _secondaryText)) : null,
            filled: true,
            fillColor: Colors.white,
            contentPadding: const EdgeInsets.symmetric(vertical: 14),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: _border)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: _border)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: _primary, width: 1.5)),
          ),
        ),
        const SizedBox(height: 12),
        Row(children: [
          _filterChip('Semua', 'semua'),
          _filterChip('Cash', 'cash'),
          _filterChip('QRIS', 'qris'),
        ]),
      ]),
    );
  }

  Widget _summaryCard(List<Map<String, dynamic>> transactions) {
    final total = transactions.fold<int>(0, (sum, item) => sum + _toInt(item['total']));
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [Color(0xFF2563EB), Color(0xFF1D4ED8)], begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [BoxShadow(color: _primary.withValues(alpha: .18), blurRadius: 14, offset: const Offset(0, 6))],
      ),
      child: Row(children: [
        Container(width: 46, height: 46, decoration: BoxDecoration(color: Colors.white.withValues(alpha: .17), borderRadius: BorderRadius.circular(14)), child: const Icon(Icons.trending_up_rounded, color: Colors.white, size: 25)),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(_searchQuery.isEmpty && _paymentFilter == 'semua' ? 'Total transaksi' : 'Total hasil filter', style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w500)),
          const SizedBox(height: 5),
          Text(_rupiah(total), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.w800)),
        ])),
        Container(width: 1, height: 42, color: Colors.white.withValues(alpha: .25)),
        const SizedBox(width: 14),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          const Text('Transaksi', style: TextStyle(color: Colors.white70, fontSize: 11)),
          const SizedBox(height: 3),
          Text('${transactions.length}', style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800)),
        ]),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final future = _transactionsFuture ??= _fetchTransactions();
    return Scaffold(
      backgroundColor: _background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: _darkText,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 1,
        titleSpacing: 20,
        title: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Riwayat Transaksi', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: _darkText)),
          SizedBox(height: 2),
          Text('Pantau transaksi toko Anda', style: TextStyle(fontSize: 11, color: _secondaryText, fontWeight: FontWeight.normal)),
        ]),
        actions: [
          Padding(padding: const EdgeInsets.only(right: 12), child: IconButton(
            tooltip: 'Muat ulang riwayat',
            onPressed: _isRefreshing ? null : _refreshTransactions,
            style: IconButton.styleFrom(backgroundColor: const Color(0xFFEFF6FF), foregroundColor: _primary),
            icon: _isRefreshing ? const SizedBox(width: 19, height: 19, child: CircularProgressIndicator(strokeWidth: 2, color: _primary)) : const Icon(Icons.refresh_rounded),
          )),
        ],
      ),
      body: Column(children: [
        _searchAndFilters(),
        Expanded(child: FutureBuilder<List<Map<String, dynamic>>>(
          future: future,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return _emptyState(title: 'Gagal memuat riwayat', message: 'Supabase gagal mengambil data transaksi.\n\n${snapshot.error}\n\nPeriksa koneksi dan kebijakan SELECT RLS.', icon: Icons.cloud_off_outlined);
            }
            if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
              return const Center(child: CircularProgressIndicator(color: _primary));
            }
            final transactions = _filterTransactions(snapshot.data ?? []);
            if (transactions.isEmpty) {
              final filtered = _searchQuery.isNotEmpty || _paymentFilter != 'semua';
              return _emptyState(title: filtered ? 'Transaksi tidak ditemukan' : 'Belum ada transaksi', message: filtered ? 'Coba ubah kata pencarian atau filter pembayaran.' : 'Belum ada transaksi aktif yang dapat dibaca akun ini.');
            }
            return RefreshIndicator(
              color: _primary,
              onRefresh: _refreshTransactions,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.only(bottom: 24),
                children: [
                  _summaryCard(transactions),
                  Padding(padding: const EdgeInsets.fromLTRB(17, 0, 16, 10), child: Row(children: [
                    const Text('Daftar transaksi', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: _darkText)),
                    const Spacer(),
                    Text('${transactions.length} data', style: const TextStyle(fontSize: 12, color: _secondaryText)),
                  ])),
                  Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Column(children: transactions.map(_buildTransactionCard).toList())),
                ],
              ),
            );
          },
        )),
      ]),
    );
  }
}

class TransactionDetailPage extends StatefulWidget {
  final String transactionId;
  final Map<String, dynamic> data;

  const TransactionDetailPage({super.key, required this.transactionId, required this.data});

  @override
  State<TransactionDetailPage> createState() => _TransactionDetailPageState();
}

class _TransactionDetailPageState extends State<TransactionDetailPage> {
  final SupabaseClient _supabase = Supabase.instance.client;
  late Future<List<Map<String, dynamic>>> _itemsFuture;
  late Future<String> _cashierNameFuture;
  bool _isGeneratingPdf = false;

  @override
  void initState() {
    super.initState();
    _itemsFuture = _loadItems();
    _cashierNameFuture = _loadCashierName();
  }

  int _toInt(dynamic value) {
    if (value is num) return value.round();
    final text = value?.toString().trim() ?? '';
    return int.tryParse(text) ?? double.tryParse(text)?.round() ?? 0;
  }

  String _rupiah(num value) {
    final digits = value.abs().round().toString();
    final result = StringBuffer();
    for (int i = 0; i < digits.length; i++) {
      result.write(digits[i]);
      final remaining = digits.length - i - 1;
      if (remaining > 0 && remaining % 3 == 0) result.write('.');
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
        '${date.year}, ${date.hour.toString().padLeft(2, '0')}:'
        '${date.minute.toString().padLeft(2, '0')}';
  }

  String _invoice() => (widget.data['invoice_number'] ?? widget.data['invoice'] ?? widget.transactionId).toString();
  String _customer() {
    final value = (widget.data['customer_name'] ?? widget.data['customerName'] ?? 'Umum').toString().trim();
    return value.isEmpty ? 'Umum' : value;
  }
  String _paymentMethod() => (widget.data['payment_method'] ?? widget.data['paymentMethod'] ?? 'cash').toString().toLowerCase();
  int _payment() => _toInt(widget.data['cash_received'] ?? widget.data['payment'] ?? widget.data['amount_paid']);
  int _change() => _toInt(widget.data['change_amount'] ?? widget.data['change']);

  Future<String> _loadCashierName() async {
    final resolved = widget.data['_resolved_cashier_name']?.toString().trim() ?? '';
    if (resolved.isNotEmpty && resolved != 'Nama kasir tidak tersedia') return resolved;
    for (final key in ['nama_kasir', 'cashier_name', 'cashierName', 'kasir_name', 'full_name']) {
      final value = widget.data[key]?.toString().trim() ?? '';
      if (value.isNotEmpty) return value;
    }
    final cashierId = widget.data['cashier_id']?.toString();
    if (cashierId == null || cashierId.isEmpty) return 'Nama kasir tidak tersedia';
    try {
      final profile = await _supabase.from('profiles').select('full_name').eq('id', cashierId).maybeSingle();
      final name = profile?['full_name']?.toString().trim() ?? '';
      if (name.isNotEmpty) return name;
    } catch (e) {
      debugPrint('Gagal mengambil nama kasir detail: $e');
    }
    return 'Nama kasir tidak tersedia';
  }

  Future<List<Map<String, dynamic>>> _loadItems() async {
    final existing = widget.data['items'];
    if (existing is List && existing.isNotEmpty) {
      return existing.whereType<Map>().map((item) => Map<String, dynamic>.from(item)).toList();
    }
    final response = await _supabase.from('transaction_items').select().eq('transaction_id', widget.transactionId);
    return List<Map<String, dynamic>>.from((response as List).map((item) => Map<String, dynamic>.from(item)));
  }

  void _reloadItems() {
    setState(() {
      _itemsFuture = _loadItems();
      _cashierNameFuture = _loadCashierName();
    });
  }

  void _showMessage(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: isError ? _danger : const Color(0xFF15803D),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
  }

  Future<Uint8List> _generatePdf(List<Map<String, dynamic>> items, String cashierName) async {
    final pdf = pw.Document();
    final total = _toInt(widget.data['total']);
    final payment = _payment();
    final change = _change();
    final method = _paymentMethod();
    pdf.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(32),
      build: (context) => [
        pw.Center(child: pw.Column(children: [
          pw.Text('JAGATOKO', style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 5),
          pw.Text('Struk Transaksi', style: const pw.TextStyle(fontSize: 12, color: PdfColors.grey700)),
        ])),
        pw.SizedBox(height: 22),
        pw.Divider(),
        _pdfInfo('Invoice', _invoice()),
        _pdfInfo('Tanggal', _dateTime(widget.data['created_at'] ?? widget.data['createdAt'])),
        _pdfInfo('Pelanggan', _customer()),
        _pdfInfo('Kasir', cashierName),
        _pdfInfo('Pembayaran', method == 'qris' ? 'QRIS' : 'Cash'),
        pw.SizedBox(height: 15),
        pw.Text('Daftar Produk', style: pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 10),
        if (items.isEmpty) pw.Text('Detail produk tidak tersedia.') else pw.Table(
          border: pw.TableBorder.all(color: PdfColors.grey300),
          columnWidths: {0: const pw.FlexColumnWidth(3), 1: const pw.FlexColumnWidth(1), 2: const pw.FlexColumnWidth(2), 3: const pw.FlexColumnWidth(2)},
          children: [
            pw.TableRow(decoration: const pw.BoxDecoration(color: PdfColors.grey200), children: [_pdfCell('Produk', bold: true), _pdfCell('Qty', bold: true), _pdfCell('Harga', bold: true), _pdfCell('Subtotal', bold: true)]),
            ...items.map((item) {
              final name = (item['product_name'] ?? item['productName'] ?? item['name'] ?? 'Produk').toString();
              final qty = _toInt(item['quantity']);
              final price = _toInt(item['selling_price'] ?? item['price']);
              final subtotal = item['subtotal'] == null ? qty * price : _toInt(item['subtotal']);
              return pw.TableRow(children: [_pdfCell(name), _pdfCell('$qty'), _pdfCell(_rupiah(price)), _pdfCell(_rupiah(subtotal))]);
            }),
          ],
        ),
        pw.SizedBox(height: 18),
        pw.Divider(),
        _pdfSummary('Total', _rupiah(total), bold: true),
        if (method != 'qris') ...[_pdfSummary('Bayar', _rupiah(payment)), _pdfSummary('Kembalian', _rupiah(change))],
        pw.SizedBox(height: 25),
        pw.Center(child: pw.Text('Terima kasih telah berbelanja di Jagatoko.', style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700))),
      ],
    ));
    return pdf.save();
  }

  pw.Widget _pdfInfo(String label, String value) => pw.Padding(
    padding: const pw.EdgeInsets.symmetric(vertical: 4),
    child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [pw.Text(label), pw.SizedBox(width: 15), pw.Expanded(child: pw.Text(value, textAlign: pw.TextAlign.right))]),
  );

  pw.Widget _pdfCell(String value, {bool bold = false}) => pw.Padding(
    padding: const pw.EdgeInsets.all(7),
    child: pw.Text(value, style: pw.TextStyle(fontSize: 9, fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal)),
  );

  pw.Widget _pdfSummary(String label, String value, {bool bold = false}) => pw.Padding(
    padding: const pw.EdgeInsets.symmetric(vertical: 5),
    child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [pw.Text(label, style: pw.TextStyle(fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal)), pw.Text(value, style: pw.TextStyle(fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal))]),
  );

  Future<void> _sharePdf(List<Map<String, dynamic>> items) async {
    if (_isGeneratingPdf) return;
    setState(() => _isGeneratingPdf = true);
    try {
      final cashier = await _cashierNameFuture;
      final bytes = await _generatePdf(items, cashier);
      await Printing.sharePdf(bytes: bytes, filename: 'Struk-${_invoice()}.pdf');
    } catch (e) {
      if (mounted) _showMessage('Gagal membuat PDF: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isGeneratingPdf = false);
    }
  }

  Widget _detailCard({required Widget child, EdgeInsetsGeometry padding = const EdgeInsets.all(16)}) => Container(
    width: double.infinity,
    padding: padding,
    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18), border: Border.all(color: _border), boxShadow: const [BoxShadow(color: Color(0x060F172A), blurRadius: 10, offset: Offset(0, 3))]),
    child: child,
  );

  Widget _infoRow(String label, String value, {IconData? icon}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Row(children: [
      if (icon != null) ...[Icon(icon, size: 17, color: _secondaryText), const SizedBox(width: 8)],
      Expanded(child: Text(label, style: const TextStyle(color: _secondaryText, fontSize: 13))),
      const SizedBox(width: 12),
      Flexible(child: Text(value, textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.w700, color: _darkText, fontSize: 13))),
    ]),
  );

  Widget _summaryRow(String label, String value, {bool bold = false}) => Row(children: [
    Expanded(child: Text(label, style: TextStyle(fontSize: bold ? 14 : 13, fontWeight: bold ? FontWeight.w800 : FontWeight.normal, color: bold ? _darkText : _secondaryText))),
    const SizedBox(width: 12),
    Flexible(child: Text(value, textAlign: TextAlign.right, style: TextStyle(fontSize: bold ? 18 : 14, fontWeight: FontWeight.w800, color: bold ? _primary : _darkText))),
  ]);

  Widget _sectionTitle(String title, IconData icon) => Row(children: [
    Container(width: 35, height: 35, decoration: BoxDecoration(color: const Color(0xFFEFF6FF), borderRadius: BorderRadius.circular(11)), child: Icon(icon, size: 19, color: _primary)),
    const SizedBox(width: 10),
    Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: _darkText)),
  ]);

  @override
  Widget build(BuildContext context) {
    final method = _paymentMethod();
    final total = _toInt(widget.data['total']);
    final payment = _payment();
    final change = _change();
    final isQris = method == 'qris';

    return Scaffold(
      backgroundColor: _background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: _darkText,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: const Text('Detail Transaksi', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
        actions: [Padding(padding: const EdgeInsets.only(right: 12), child: IconButton(onPressed: _reloadItems, tooltip: 'Muat ulang detail', style: IconButton.styleFrom(backgroundColor: const Color(0xFFEFF6FF), foregroundColor: _primary), icon: const Icon(Icons.refresh_rounded)))],
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _itemsFuture,
        builder: (context, snapshot) {
          final items = snapshot.data ?? [];
          return ListView(padding: const EdgeInsets.fromLTRB(16, 14, 16, 28), children: [
            _detailCard(child: Column(children: [
              Container(width: 64, height: 64, decoration: BoxDecoration(color: const Color(0xFFEFF6FF), borderRadius: BorderRadius.circular(20)), child: const Icon(Icons.receipt_long_rounded, size: 34, color: _primary)),
              const SizedBox(height: 13),
              Text(_invoice(), textAlign: TextAlign.center, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: _darkText)),
              const SizedBox(height: 6),
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [const Icon(Icons.schedule_rounded, size: 14, color: _secondaryText), const SizedBox(width: 5), Text(_dateTime(widget.data['created_at'] ?? widget.data['createdAt']), style: const TextStyle(color: _secondaryText, fontSize: 12))]),
              const SizedBox(height: 15),
              Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7), decoration: BoxDecoration(color: isQris ? const Color(0xFFF3E8FF) : const Color(0xFFDCFCE7), borderRadius: BorderRadius.circular(10)), child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(isQris ? Icons.qr_code_2_rounded : Icons.payments_outlined, size: 16, color: isQris ? const Color(0xFF7C3AED) : const Color(0xFF15803D)), const SizedBox(width: 6), Text(isQris ? 'Pembayaran QRIS' : 'Pembayaran Cash', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: isQris ? const Color(0xFF7C3AED) : const Color(0xFF15803D)))])),
              const Padding(padding: EdgeInsets.symmetric(vertical: 13), child: Divider(color: _border, height: 1)),
              _infoRow('Pelanggan', _customer(), icon: Icons.person_outline_rounded),
              FutureBuilder<String>(future: _cashierNameFuture, builder: (context, cashierSnapshot) => _infoRow('Kasir', cashierSnapshot.data ?? 'Memuat nama kasir...', icon: Icons.badge_outlined)),
            ])),
            const SizedBox(height: 14),
            _detailCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _sectionTitle('Daftar Produk', Icons.inventory_2_outlined),
              const SizedBox(height: 17),
              if (snapshot.connectionState == ConnectionState.waiting)
                const Center(child: Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator(color: _primary)))
              else if (snapshot.hasError)
                Center(child: Column(children: [const Icon(Icons.cloud_off_outlined, size: 35, color: _danger), const SizedBox(height: 8), const Text('Gagal memuat detail produk.', style: TextStyle(color: _danger, fontWeight: FontWeight.w600)), const SizedBox(height: 5), Text('${snapshot.error}', style: const TextStyle(fontSize: 12)), TextButton(onPressed: _reloadItems, child: const Text('Coba lagi'))]))
              else if (items.isEmpty)
                const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Text('Detail produk tidak tersedia.', style: TextStyle(color: _secondaryText)))
              else
                ...items.asMap().entries.map((entry) {
                  final item = entry.value;
                  final name = (item['product_name'] ?? item['productName'] ?? item['name'] ?? 'Produk').toString();
                  final qty = _toInt(item['quantity']);
                  final price = _toInt(item['selling_price'] ?? item['price']);
                  final subtotal = item['subtotal'] == null ? qty * price : _toInt(item['subtotal']);
                  return Padding(padding: EdgeInsets.only(bottom: entry.key == items.length - 1 ? 0 : 14), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Container(width: 42, height: 42, decoration: BoxDecoration(color: const Color(0xFFF1F5F9), borderRadius: BorderRadius.circular(12)), child: const Icon(Icons.inventory_2_outlined, color: _primary, size: 21)),
                    const SizedBox(width: 11),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: _darkText)), const SizedBox(height: 5), Text('$qty × ${_rupiah(price)}', style: const TextStyle(fontSize: 12, color: _secondaryText))])),
                    const SizedBox(width: 8),
                    Flexible(child: Text(_rupiah(subtotal), textAlign: TextAlign.right, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: _darkText))),
                  ]));
                }),
            ])),
            const SizedBox(height: 14),
            _detailCard(child: Column(children: [
              _summaryRow('Subtotal', _rupiah(_toInt(widget.data['subtotal'] ?? widget.data['total']))),
              const SizedBox(height: 13),
              _summaryRow('Total pembayaran', _rupiah(total), bold: true),
              if (!isQris) ...[
                const Padding(padding: EdgeInsets.symmetric(vertical: 13), child: Divider(color: _border, height: 1)),
                _summaryRow('Uang diterima', _rupiah(payment)),
                const SizedBox(height: 12),
                _summaryRow('Kembalian', _rupiah(change)),
              ],
            ])),
            const SizedBox(height: 18),
            SizedBox(height: 52, child: FilledButton.icon(
              onPressed: snapshot.connectionState == ConnectionState.waiting || snapshot.hasError || _isGeneratingPdf ? null : () => _sharePdf(items),
              icon: _isGeneratingPdf ? const SizedBox(width: 19, height: 19, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.picture_as_pdf_outlined),
              label: Text(_isGeneratingPdf ? 'Membuat PDF...' : 'Bagikan Struk PDF', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
              style: FilledButton.styleFrom(backgroundColor: _primary, disabledBackgroundColor: const Color(0xFF93C5FD), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)), elevation: 0),
            )),
          ]);
        },
      ),
    );
  }
}

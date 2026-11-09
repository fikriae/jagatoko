
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const Color _primary = Color(0xFF2563EB);
const Color _background = Color(0xFFF8FAFC);

class PengeluaranPage extends StatefulWidget {
  const PengeluaranPage({super.key});

  @override
  State<PengeluaranPage> createState() => _PengeluaranPageState();
}

class _PengeluaranPageState extends State<PengeluaranPage> {
  final SupabaseClient _supabase = Supabase.instance.client;
  final _formKey = GlobalKey<FormState>();
  final _descriptionController = TextEditingController();
  final _amountController = TextEditingController();

  static const List<String> _categories = [
    'Sewa toko',
    'Wi-Fi',
    'Parkir',
    'Listrik',
    'Air',
    'Gaji karyawan',
    'Pembelian stok',
    'Transportasi',
    'Perlengkapan',
    'Lainnya',
  ];

  static const List<String> _payments = [
    'Cash',
    'Transfer',
    'QRIS',
    'Lainnya',
  ];

  static const List<String> _monthNames = [
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

  String _category = 'Sewa toko';
  String _payment = 'Cash';
  DateTime _expenseDate = DateTime.now();
  DateTime _selectedMonth = DateTime(
    DateTime.now().year,
    DateTime.now().month,
  );

  bool _saving = false;
  bool _loading = true;

  String _role = 'kasir';
  String _fullName = 'Pengguna';

  List<Map<String, dynamic>> _expenses = [];

  @override
  void initState() {
    super.initState();
    _loadExpenses();
  }

  @override
  void dispose() {
    _descriptionController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  String _rupiah(num value) {
    final s = value.round().abs().toString();
    final b = StringBuffer();

    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) {
        b.write('.');
      }
      b.write(s[i]);
    }

    return '${value < 0 ? '-' : ''}Rp ${b.toString()}';
  }

  String _dateString(DateTime date) {
    return '${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
  }

  String get _selectedMonthLabel {
    return '${_monthNames[_selectedMonth.month - 1]} ${_selectedMonth.year}';
  }

  num _amountOf(Map<String, dynamic> expense) {
    final amount = expense['amount'];

    if (amount is num) return amount;

    return num.tryParse('$amount') ?? 0;
  }

  num get _monthlyTotal {
    return _expenses.fold<num>(
      0,
      (sum, expense) => sum + _amountOf(expense),
    );
  }

  Future<void> _loadExpenses() async {
    if (mounted) {
      setState(() => _loading = true);
    }

    try {
      final user = _supabase.auth.currentUser;

      if (user == null) {
        throw Exception('Sesi login tidak ditemukan.');
      }

      final profile = await _supabase
          .from('profiles')
          .select('full_name, role, is_active')
          .eq('id', user.id)
          .maybeSingle();

      if (profile == null || profile['is_active'] != true) {
        throw Exception(
          'Profil pengguna tidak aktif atau tidak ditemukan.',
        );
      }

      final role = (profile['role'] ?? 'kasir')
          .toString()
          .toLowerCase()
          .trim();

      if (role != 'owner' && role != 'kasir') {
        throw Exception('Role pengguna tidak valid.');
      }

      // Batas tanggal: awal bulan yang dipilih sampai awal bulan berikutnya.
      final startDate = DateTime(
        _selectedMonth.year,
        _selectedMonth.month,
        1,
      );

      final endDate = DateTime(
        _selectedMonth.year,
        _selectedMonth.month + 1,
        1,
      );

      final rows = await _supabase
          .from('expenses')
          .select()
          .gte('expense_date', _dateString(startDate))
          .lt('expense_date', _dateString(endDate))
          .order('expense_date', ascending: false)
          .order('created_at', ascending: false);

      if (!mounted) return;

      setState(() {
        _role = role;
        _fullName = (profile['full_name'] ?? 'Pengguna').toString();
        _expenses = List<Map<String, dynamic>>.from(rows);
      });
    } catch (e) {
      _message('Gagal memuat pengeluaran: $e');
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  void _message(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  Future<void> _changeMonth(int difference) async {
    setState(() {
      _selectedMonth = DateTime(
        _selectedMonth.year,
        _selectedMonth.month + difference,
        1,
      );
    });

    await _loadExpenses();
  }

  Future<void> _chooseMonth() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedMonth,
      firstDate: DateTime(2020, 1),
      lastDate: DateTime(DateTime.now().year + 5, 12, 31),
      helpText: 'Pilih tanggal pada bulan yang dicari',
      cancelText: 'Batal',
      confirmText: 'Pilih bulan',
    );

    if (picked == null || !mounted) return;

    setState(() {
      _selectedMonth = DateTime(picked.year, picked.month, 1);
    });

    await _loadExpenses();
  }

  Future<void> _addExpense() async {
    if (!_formKey.currentState!.validate()) return;

    final user = _supabase.auth.currentUser;

    if (user == null) {
      _message('Sesi login tidak ditemukan.');
      return;
    }

    final amount = num.tryParse(
      _amountController.text.replaceAll('.', '').replaceAll(',', ''),
    );

    if (amount == null || amount <= 0) {
      _message('Masukkan nominal pengeluaran yang valid.');
      return;
    }

    setState(() => _saving = true);

    try {
      await _supabase.from('expenses').insert({
        'created_by': user.id,
        'created_by_name': _fullName,
        'category': _category,
        'description': _descriptionController.text.trim(),
        'amount': amount,
        'payment_method': _payment.toLowerCase() == 'cash'
            ? 'cash'
            : _payment.toLowerCase(),
        'expense_date': _dateString(_expenseDate),
      });

      if (!mounted) return;

      Navigator.pop(context);

      _descriptionController.clear();
      _amountController.clear();

      _message('Pengeluaran berhasil dicatat.');

      // Jika tanggal pengeluaran berada pada bulan lain,
      // pindahkan filter ke bulan transaksi tersebut.
      if (_expenseDate.year != _selectedMonth.year ||
          _expenseDate.month != _selectedMonth.month) {
        setState(() {
          _selectedMonth = DateTime(
            _expenseDate.year,
            _expenseDate.month,
            1,
          );
        });
      }

      await _loadExpenses();
    } catch (e) {
      _message('Gagal menyimpan pengeluaran: $e');
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Future<void> _showAddDialog() async {
    _formKey.currentState?.reset();

    _descriptionController.clear();
    _amountController.clear();

    _category = 'Sewa toko';
    _payment = 'Cash';
    _expenseDate = DateTime.now();

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(24),
        ),
      ),
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              20,
              20,
              20,
              20 + MediaQuery.of(context).viewInsets.bottom,
            ),
            child: Form(
              key: _formKey,
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Tambah Pengeluaran',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 16),

                    DropdownButtonFormField<String>(
                      value: _category,
                      decoration: const InputDecoration(
                        labelText: 'Kategori',
                        border: OutlineInputBorder(),
                      ),
                      items: _categories
                          .map(
                            (v) => DropdownMenuItem(
                              value: v,
                              child: Text(v),
                            ),
                          )
                          .toList(),
                      onChanged: (v) {
                        if (v != null) {
                          setSheetState(() => _category = v);
                        }
                      },
                    ),

                    const SizedBox(height: 12),

                    TextFormField(
                      controller: _descriptionController,
                      decoration: const InputDecoration(
                        labelText: 'Keterangan (opsional)',
                        hintText: 'Contoh: pembayaran Wi-Fi bulan Oktober',
                        border: OutlineInputBorder(),
                      ),
                      textCapitalization: TextCapitalization.sentences,
                    ),

                    const SizedBox(height: 12),

                    TextFormField(
                      controller: _amountController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Nominal (Rp)',
                        hintText: 'Contoh: 250000',
                        prefixText: 'Rp ',
                        border: OutlineInputBorder(),
                      ),
                      validator: (v) {
                        final amount = num.tryParse(
                          (v ?? '').replaceAll('.', '').replaceAll(',', ''),
                        );

                        if (amount == null || amount <= 0) {
                          return 'Nominal wajib lebih dari 0.';
                        }

                        return null;
                      },
                    ),

                    const SizedBox(height: 12),

                    DropdownButtonFormField<String>(
                      value: _payment,
                      decoration: const InputDecoration(
                        labelText: 'Metode pembayaran',
                        border: OutlineInputBorder(),
                      ),
                      items: _payments
                          .map(
                            (v) => DropdownMenuItem(
                              value: v,
                              child: Text(v),
                            ),
                          )
                          .toList(),
                      onChanged: (v) {
                        if (v != null) {
                          setSheetState(() => _payment = v);
                        }
                      },
                    ),

                    const SizedBox(height: 12),

                    OutlinedButton.icon(
                      onPressed: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: _expenseDate,
                          firstDate: DateTime(2020),
                          lastDate: DateTime.now().add(
                            const Duration(days: 365),
                          ),
                        );

                        if (picked != null) {
                          setSheetState(() => _expenseDate = picked);
                        }
                      },
                      icon: const Icon(Icons.calendar_month_outlined),
                      label: Text(
                        'Tanggal: '
                        '${_expenseDate.day.toString().padLeft(2, '0')}/'
                        '${_expenseDate.month.toString().padLeft(2, '0')}/'
                        '${_expenseDate.year}',
                      ),
                    ),

                    const SizedBox(height: 16),

                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _saving ? null : _addExpense,
                        icon: _saving
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.save_outlined),
                        label: Text(
                          _saving
                              ? 'Menyimpan...'
                              : 'Simpan Pengeluaran',
                        ),
                        style: FilledButton.styleFrom(
                          backgroundColor: _primary,
                          padding: const EdgeInsets.symmetric(
                            vertical: 14,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMonthSelector() {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 8,
        vertical: 8,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Bulan sebelumnya',
            onPressed: () => _changeMonth(-1),
            icon: const Icon(Icons.chevron_left_rounded),
          ),

          Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: _chooseMonth,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.calendar_month_outlined,
                      color: _primary,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        _selectedMonthLabel,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Icon(
                      Icons.arrow_drop_down_rounded,
                      color: _primary,
                    ),
                  ],
                ),
              ),
            ),
          ),

          IconButton(
            tooltip: 'Bulan berikutnya',
            onPressed: () => _changeMonth(1),
            icon: const Icon(Icons.chevron_right_rounded),
          ),
        ],
      ),
    );
  }

  Widget _buildMonthlySummary() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _primary,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: _primary.withValues(alpha: 0.15),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.account_balance_wallet_outlined,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Total Pengeluaran Bulanan',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 18),

          Text(
            _rupiah(_monthlyTotal),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.w800,
            ),
          ),

          const SizedBox(height: 8),

          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 10,
              vertical: 6,
            ),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              _selectedMonthLabel,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),

          const SizedBox(height: 12),

          Divider(
            color: Colors.white.withValues(alpha: 0.25),
            height: 1,
          ),

          const SizedBox(height: 12),

          Row(
            children: [
              const Icon(
                Icons.receipt_long_outlined,
                color: Colors.white70,
                size: 18,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${_expenses.length} catatan pengeluaran pada bulan ini',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 5),

          Text(
            'Dicatat oleh: $_fullName',
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildExpenseItem(Map<String, dynamic> expense) {
    final date = DateTime.tryParse(
      '${expense['expense_date'] ?? ''}',
    );

    final dateLabel = date == null
        ? '-'
        : '${date.day.toString().padLeft(2, '0')}/'
            '${date.month.toString().padLeft(2, '0')}/'
            '${date.year}';

    final description = (expense['description'] ?? '').toString();
    final category = (expense['category'] ?? 'Lainnya').toString();
    final cashier = (expense['created_by_name'] ?? 'Pengguna').toString();
    final payment = (expense['payment_method'] ?? '-').toString();

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 8,
        ),
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: const Color(0xFFFFF7ED),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(
            Icons.receipt_long_outlined,
            color: Color(0xFFEA580C),
          ),
        ),
        title: Text(
          category,
          style: const TextStyle(
            fontWeight: FontWeight.w700,
          ),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 5),
          child: Text(
            '${description.isNotEmpty ? '$description\n' : ''}'
            '$dateLabel • $cashier\n'
            'Metode: $payment',
            style: const TextStyle(
              fontSize: 12,
              height: 1.5,
              color: Color(0xFF64748B),
            ),
          ),
        ),
        isThreeLine: true,
        trailing: Text(
          '-${_rupiah(_amountOf(expense))}',
          textAlign: TextAlign.end,
          style: const TextStyle(
            color: Color(0xFFDC2626),
            fontWeight: FontWeight.w800,
            fontSize: 12,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _background,
      appBar: AppBar(
        title: const Text(
          'Pengeluaran',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        actions: [
          IconButton(
            tooltip: 'Muat ulang',
            onPressed: _loading ? null : _loadExpenses,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddDialog,
        backgroundColor: _primary,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('Tambah'),
      ),
      body: RefreshIndicator(
        onRefresh: _loadExpenses,
        child: _loading
            ? const Center(
                child: CircularProgressIndicator(color: _primary),
              )
            : ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                children: [
                  // Pemilih bulan
                  _buildMonthSelector(),

                  const SizedBox(height: 16),

                  // Ringkasan total pengeluaran pada bulan terpilih
                  _buildMonthlySummary(),

                  const SizedBox(height: 22),

                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Riwayat Pengeluaran',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      Text(
                        '${_expenses.length} transaksi',
                        style: const TextStyle(
                          color: Color(0xFF64748B),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 10),

                  if (_expenses.isEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 36,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: const Color(0xFFE5E7EB),
                        ),
                      ),
                      child: Column(
                        children: [
                          const Icon(
                            Icons.receipt_long_outlined,
                            size: 42,
                            color: Color(0xFF94A3B8),
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'Belum ada pengeluaran',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Tidak ada catatan pengeluaran pada '
                            '$_selectedMonthLabel.',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Color(0xFF64748B),
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(height: 14),
                          OutlinedButton.icon(
                            onPressed: _showAddDialog,
                            icon: const Icon(Icons.add),
                            label: const Text('Tambah Pengeluaran'),
                          ),
                        ],
                      ),
                    )
                  else
                    ..._expenses.map(_buildExpenseItem),

                  const SizedBox(height: 90),
                ],
              ),
      ),
    );
  }
}

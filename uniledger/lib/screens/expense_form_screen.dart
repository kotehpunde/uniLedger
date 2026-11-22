import 'package:flutter/material.dart';

import '../categories.dart';
import '../currency_service.dart';
import '../database_helper.dart';

/// Add a new expense, or edit an existing one when [existing] is given.
class ExpenseFormScreen extends StatefulWidget {
  final int userId;
  final Map<String, dynamic>? existing;
  const ExpenseFormScreen({super.key, required this.userId, this.existing});

  @override
  State<ExpenseFormScreen> createState() => _ExpenseFormScreenState();
}

class _ExpenseFormScreenState extends State<ExpenseFormScreen> {
  static final _moneyFormat = RegExp(r'^\d+(\.\d{1,2})?$');

  final _formKey = GlobalKey<FormState>();
  final _titleCtrl = TextEditingController();
  final _amountCtrl = TextEditingController();

  String _category = categories.first;
  bool _userPickedCategory = false; // stop auto-suggest once user chooses
  bool _autoSuggested = false;
  String _currency = 'MYR';
  DateTime _date = DateTime.now();
  double? _previewMYR;
  String? _rateError;
  bool _saving = false;

  bool get _isEditing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e != null) {
      _titleCtrl.text = e['title'] as String;
      _amountCtrl.text =
          (e['original_amount'] as num).toDouble().toStringAsFixed(2);
      _currency = e['currency'] as String;
      _category = e['category'] as String;
      _date = DateTime.parse(e['date'] as String);
      _userPickedCategory = true;
      if (_currency != 'MYR') _updatePreview();
    }
  }

  /// Keyword auto-category, e.g. "Grab to campus" -> Transport.
  void _onTitleChanged(String value) {
    if (_userPickedCategory) return;
    final suggestion = suggestCategory(value);
    setState(() {
      if (suggestion != null) {
        _category = suggestion;
        _autoSuggested = true;
      } else {
        _autoSuggested = false;
      }
    });
  }

  /// Shows "≈ RM xx.xx" under the amount for foreign currencies.
  Future<void> _updatePreview() async {
    final amount = double.tryParse(_amountCtrl.text.trim());
    if (_currency == 'MYR' || amount == null) {
      setState(() {
        _previewMYR = null;
        _rateError = null;
      });
      return;
    }
    try {
      final myr = await CurrencyService.toMYR(amount, _currency);
      if (!mounted) return;
      setState(() {
        _previewMYR = myr;
        _rateError = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _previewMYR = null;
        _rateError = 'Could not get the exchange rate (no internet?)';
      });
    }
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _date.isAfter(now) ? now : _date,
      firstDate: DateTime(now.year - 1),
      lastDate: now, // can't record spending in the future
    );
    if (picked == null) return;
    setState(() {
      _date = DateTime(
          picked.year, picked.month, picked.day, _date.hour, _date.minute);
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    final original = double.parse(_amountCtrl.text.trim());
    double amountMYR;
    try {
      amountMYR = await CurrencyService.toMYR(original, _currency);
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              'Could not convert the currency. Check your internet or use MYR.')));
      return;
    }
    amountMYR = double.parse(amountMYR.toStringAsFixed(2));

    final db = DatabaseHelper.instance;
    final title = _titleCtrl.text.trim();
    if (_isEditing) {
      await db.updateExpense(
        userId: widget.userId,
        expenseId: widget.existing!['id'] as int,
        title: title,
        amount: amountMYR,
        category: _category,
        date: _date,
        originalAmount: original,
        currency: _currency,
      );
    } else {
      await db.addExpense(
        userId: widget.userId,
        title: title,
        amount: amountMYR,
        category: _category,
        date: _date,
        originalAmount: original,
        currency: _currency,
      );
    }
    if (!mounted) return;
    Navigator.pop(context, true); // true = something was saved
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _amountCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_isEditing ? 'Edit expense' : 'Add expense')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // ---- Description ----
            TextFormField(
              controller: _titleCtrl,
              maxLength: 40,
              onChanged: _onTitleChanged,
              decoration: const InputDecoration(
                labelText: 'What did you spend on?',
                hintText: 'e.g. Lunch at mamak, Grab to campus',
                border: OutlineInputBorder(),
              ),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Enter a description' : null,
            ),
            const SizedBox(height: 8),

            // ---- Currency + amount ----
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 110,
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'Currency',
                      border: OutlineInputBorder(),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: _currency,
                        isDense: true,
                        isExpanded: true,
                        items: CurrencyService.currencies
                            .map((c) =>
                                DropdownMenuItem(value: c, child: Text(c)))
                            .toList(),
                        onChanged: (v) {
                          setState(() => _currency = v!);
                          _updatePreview();
                        },
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _amountCtrl,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    onChanged: (_) => _updatePreview(),
                    decoration: const InputDecoration(
                      labelText: 'Amount',
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) {
                      final text = (v ?? '').trim();
                      if (text.isEmpty) return 'Enter an amount';
                      if (!_moneyFormat.hasMatch(text)) {
                        return 'Numbers only, max 2 decimals';
                      }
                      final amount = double.parse(text);
                      if (amount <= 0) return 'Must be more than 0';
                      if (amount > 100000) return 'Too large (max 100,000)';
                      return null;
                    },
                  ),
                ),
              ],
            ),
            if (_previewMYR != null)
              Padding(
                padding: const EdgeInsets.only(top: 6, left: 4),
                child: Text('≈ ${formatRM(_previewMYR!)} (live exchange rate)',
                    style: const TextStyle(color: Colors.green)),
              ),
            if (_rateError != null)
              Padding(
                padding: const EdgeInsets.only(top: 6, left: 4),
                child: Text(_rateError!,
                    style: const TextStyle(color: Colors.red)),
              ),
            const SizedBox(height: 16),

            // ---- Category ----
            InputDecorator(
              decoration: InputDecoration(
                labelText: 'Category',
                helperText: _autoSuggested && !_userPickedCategory
                    ? 'Picked automatically from your description'
                    : null,
                border: const OutlineInputBorder(),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _category,
                  isDense: true,
                  isExpanded: true,
                  items: categories
                      .map((c) => DropdownMenuItem(
                            value: c,
                            child: Row(children: [
                              Icon(categoryIcons[c], size: 18),
                              const SizedBox(width: 8),
                              Text(c),
                            ]),
                          ))
                      .toList(),
                  onChanged: (v) => setState(() {
                    _category = v!;
                    _userPickedCategory = true;
                  }),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // ---- Date ----
            OutlinedButton.icon(
              onPressed: _pickDate,
              icon: const Icon(Icons.calendar_month),
              label: Text('Date: ${formatDate(_date.toIso8601String())}'),
            ),
            const SizedBox(height: 24),

            FilledButton(
              onPressed: _saving ? null : _save,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(_isEditing ? 'Save changes' : 'Save expense'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

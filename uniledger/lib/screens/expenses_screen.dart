import 'package:flutter/material.dart';

import '../categories.dart';
import '../database_helper.dart';
import '../export_service.dart';
import 'expense_form_screen.dart';

class ExpensesScreen extends StatefulWidget {
  final int userId;
  const ExpensesScreen({super.key, required this.userId});

  @override
  State<ExpensesScreen> createState() => _ExpensesScreenState();
}

class _ExpensesScreenState extends State<ExpensesScreen> {
  List<Map<String, dynamic>> _expenses = [];
  String? _filter; // null = show all categories
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final rows = await DatabaseHelper.instance.getExpenses(widget.userId);
    if (!mounted) return;
    setState(() {
      _expenses = rows;
      _loading = false;
    });
  }

  List<Map<String, dynamic>> get _visible => _filter == null
      ? _expenses
      : _expenses.where((e) => e['category'] == _filter).toList();

  /// Opens the form. [existing] = the expense to edit, or null to add.
  Future<void> _openForm([Map<String, dynamic>? existing]) async {
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) =>
            ExpenseFormScreen(userId: widget.userId, existing: existing),
      ),
    );
    if (saved == true) {
      await _load();
      await _checkBudget();
    }
  }

  /// Spending limit alert: warns at 80% and 100% of the monthly budget.
  Future<void> _checkBudget() async {
    final db = DatabaseHelper.instance;
    final user = await db.getUser(widget.userId);
    final budget = (user?['budget'] as num?)?.toDouble() ?? 0;
    final spent = await db.monthTotal(widget.userId);
    if (!mounted || budget <= 0) return;

    final ratio = spent / budget;
    if (ratio < 0.8) return;

    final over = ratio >= 1;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Icon(Icons.warning_amber,
            color: over ? Colors.red : Colors.orange, size: 40),
        title: Text(over ? 'Over budget!' : 'Budget warning'),
        content: Text(over
            ? 'You have spent ${formatRM(spent)} this month, which is over your ${formatRM(budget)} budget.\n\nCheck "Spending insights" on the Home tab for tips.'
            : 'You have used ${(ratio * 100).toStringAsFixed(0)}% of your monthly budget (${formatRM(spent)} of ${formatRM(budget)}).'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
        ],
      ),
    );
  }

  /// Deletes straight away but offers Undo.
  Future<void> _delete(Map<String, dynamic> e) async {
    final db = DatabaseHelper.instance;
    setState(() => _expenses = List.of(_expenses)..remove(e));
    await db.deleteExpense(widget.userId, e['id'] as int);
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(
      content: Text('Deleted "${e['title']}"'),
      action: SnackBarAction(
        label: 'UNDO',
        onPressed: () async {
          await db.restoreExpense(e);
          _load();
        },
      ),
    ));
  }

  /// Exports personal expenses as a CSV spreadsheet.
  Future<void> _export() async {
    if (_expenses.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No expenses to export yet')));
      return;
    }
    final rows = <List<Object?>>[
      ['Date', 'Time', 'Description', 'Category', 'Original amount',
        'Currency', 'Amount (RM)'],
      for (final e in _expenses)
        [
          formatDate(e['date'] as String),
          formatDateTime(e['date'] as String).substring(11),
          e['title'],
          e['category'],
          (e['original_amount'] as num).toStringAsFixed(2),
          e['currency'],
          (e['amount'] as num).toStringAsFixed(2),
        ],
    ];
    try {
      final savedTo = await ExportService.saveCsv(
        'uniledger_my_expenses_${ExportService.timestamp()}.csv',
        rows,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Spreadsheet saved to $savedTo')));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not save the file')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final visible = _visible;
    final total = visible.fold<double>(
        0, (sum, e) => sum + (e['amount'] as num).toDouble());

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openForm(),
        icon: const Icon(Icons.add),
        label: const Text('Add'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // ---- Category filter ----
                SizedBox(
                  height: 56,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: const Text('All'),
                          selected: _filter == null,
                          onSelected: (_) => setState(() => _filter = null),
                        ),
                      ),
                      for (final c in categories)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            avatar: Icon(categoryIcons[c], size: 16),
                            label: Text(c),
                            selected: _filter == c,
                            onSelected: (_) => setState(() => _filter = c),
                          ),
                        ),
                    ],
                  ),
                ),

                // ---- Total + export ----
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${visible.length} expense${visible.length == 1 ? '' : 's'} • Total ${formatRM(total)}',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                      TextButton.icon(
                        onPressed: _export,
                        icon: const Icon(Icons.file_download),
                        label: const Text('Download'),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),

                // ---- List ----
                Expanded(
                  child: visible.isEmpty
                      ? Center(
                          child: Text(
                            _expenses.isEmpty
                                ? 'No expenses yet.\nTap "Add" to record one.'
                                : 'No expenses in this category.',
                            textAlign: TextAlign.center,
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.only(bottom: 80),
                          itemCount: visible.length,
                          itemBuilder: (context, i) {
                            final e = visible[i];
                            final currency = e['currency'] as String;
                            final foreign = currency != 'MYR'
                                ? ' • $currency ${(e['original_amount'] as num).toStringAsFixed(2)}'
                                : '';
                            return Dismissible(
                              key: ValueKey(e['id']),
                              direction: DismissDirection.endToStart,
                              background: Container(
                                color: Colors.red,
                                alignment: Alignment.centerRight,
                                padding: const EdgeInsets.only(right: 20),
                                child: const Icon(Icons.delete,
                                    color: Colors.white),
                              ),
                              onDismissed: (_) => _delete(e),
                              child: ListTile(
                                onTap: () => _openForm(e),
                                leading: CircleAvatar(
                                    child: Icon(categoryIcons[e['category']] ??
                                        Icons.category)),
                                title: Text(e['title'] as String),
                                subtitle: Text(
                                    '${e['category']} • ${formatDate(e['date'] as String)}$foreign'),
                                trailing: Text(
                                  formatRM((e['amount'] as num).toDouble()),
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold),
                                ),
                              ),
                            );
                          },
                        ),
                ),
                const Padding(
                  padding: EdgeInsets.only(bottom: 4),
                  child: Text('Tap to edit • Swipe left to delete',
                      style: TextStyle(fontSize: 12)),
                ),
              ],
            ),
    );
  }
}

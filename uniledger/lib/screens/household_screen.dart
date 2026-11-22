import 'dart:math';

import 'package:flutter/material.dart';

import '../categories.dart';
import '../database_helper.dart';
import '../export_service.dart';
import 'statement_screen.dart';

/// One "X owes Y RM amount" line.
class Debt {
  final int fromId;
  final int toId;
  final double amount;
  Debt(this.fromId, this.toId, this.amount);
}

/// The member ids who share a bill, e.g. "1,3" -> [1, 3].
/// If none were saved, everyone shares it.
List<int> splitIdsOf(
    Map<String, dynamic> expense, List<Map<String, dynamic>> members) {
  final ids = ((expense['split_ids'] as String?) ?? '')
      .split(',')
      .where((s) => s.isNotEmpty)
      .map(int.parse)
      .toList();
  return ids.isEmpty ? members.map((m) => m['id'] as int).toList() : ids;
}

class HouseholdScreen extends StatefulWidget {
  final int userId;
  const HouseholdScreen({super.key, required this.userId});

  @override
  State<HouseholdScreen> createState() => _HouseholdScreenState();
}

class _HouseholdScreenState extends State<HouseholdScreen> {
  bool _loading = true;
  List<Map<String, dynamic>> _members = [];
  List<Map<String, dynamic>> _shared = [];
  List<Map<String, dynamic>> _settlements = [];
  List<Debt> _debts = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final db = DatabaseHelper.instance;
    final members = await db.getMembers(widget.userId);
    final shared = await db.getSharedExpenses(widget.userId);
    final settlements = await db.getSettlements(widget.userId);
    if (!mounted) return;
    setState(() {
      _members = members;
      _shared = shared;
      _settlements = settlements;
      _debts = _calculateDebts();
      _loading = false;
    });
  }

  String _name(int memberId) {
    for (final m in _members) {
      if (m['id'] == memberId) return m['name'] as String;
    }
    return 'Unknown';
  }

  /// Step 1: work out each member's balance.
  ///   Positive balance = the group owes them money.
  ///   Negative balance = they owe the group money.
  /// Each bill is split equally between the members chosen for it.
  ///
  /// Step 2: repeatedly match the person who owes the most with the
  /// person who is owed the most, until everyone is (almost) zero.
  List<Debt> _calculateDebts() {
    if (_members.isEmpty) return [];

    final balance = <int, double>{
      for (final m in _members) m['id'] as int: 0.0,
    };

    for (final e in _shared) {
      final amount = (e['amount'] as num).toDouble();
      final payer = e['payer_id'] as int;
      final splitIds = splitIdsOf(e, _members);
      final share = amount / splitIds.length;
      balance[payer] = (balance[payer] ?? 0) + amount;
      for (final id in splitIds) {
        balance[id] = (balance[id] ?? 0) - share;
      }
    }

    for (final s in _settlements) {
      final from = s['from_id'] as int;
      final to = s['to_id'] as int;
      final amount = (s['amount'] as num).toDouble();
      balance[from] = (balance[from] ?? 0) + amount;
      balance[to] = (balance[to] ?? 0) - amount;
    }

    final debts = <Debt>[];
    while (true) {
      int? debtor;
      int? creditor;
      double lowest = -0.01;
      double highest = 0.01;
      for (final entry in balance.entries) {
        if (entry.value < lowest) {
          lowest = entry.value;
          debtor = entry.key;
        }
        if (entry.value > highest) {
          highest = entry.value;
          creditor = entry.key;
        }
      }
      if (debtor == null || creditor == null) break;

      final amount = min(-lowest, highest);
      debts.add(Debt(debtor, creditor, amount));
      balance[debtor] = balance[debtor]! + amount;
      balance[creditor] = balance[creditor]! - amount;
    }
    return debts;
  }

  // ---------- Actions ----------

  Future<void> _addMember() async {
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add roommate'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          maxLength: 30,
          decoration: const InputDecoration(labelText: 'Name'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Add')),
        ],
      ),
    );
    final name = ctrl.text.trim();
    if (ok != true || name.isEmpty) return;
    if (_members.any((m) =>
        (m['name'] as String).toLowerCase() == name.toLowerCase())) {
      _snack('$name is already in the household');
      return;
    }
    await DatabaseHelper.instance.addMember(widget.userId, name);
    _load();
  }

  Future<void> _addSharedExpense() async {
    if (_members.length < 2) {
      _snack('Add at least one roommate first');
      return;
    }
    final titleCtrl = TextEditingController();
    final amountCtrl = TextEditingController();
    int payerId = _members.first['id'] as int;
    final selected = <int>{for (final m in _members) m['id'] as int};

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Add shared expense'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: titleCtrl,
                  maxLength: 40,
                  decoration: const InputDecoration(
                      labelText: 'Description (e.g. Electricity bill)'),
                ),
                TextField(
                  controller: amountCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration:
                      const InputDecoration(labelText: 'Total amount (RM)'),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Text('Paid by: '),
                    const SizedBox(width: 8),
                    Expanded(
                      child: DropdownButton<int>(
                        value: payerId,
                        isExpanded: true,
                        items: _members
                            .map((m) => DropdownMenuItem(
                                  value: m['id'] as int,
                                  child: Text(m['name'] as String),
                                ))
                            .toList(),
                        onChanged: (v) => setDialogState(() => payerId = v!),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                const Text('Split between:'),
                Wrap(
                  spacing: 6,
                  children: _members.map((m) {
                    final id = m['id'] as int;
                    return FilterChip(
                      label: Text(m['name'] as String),
                      selected: selected.contains(id),
                      onSelected: (on) => setDialogState(() {
                        on ? selected.add(id) : selected.remove(id);
                      }),
                    );
                  }).toList(),
                ),
                Text(
                  selected.isEmpty
                      ? 'Choose at least one person'
                      : 'Split equally between ${selected.length} ${selected.length == 1 ? 'person' : 'people'}',
                  style: Theme.of(ctx).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Save')),
          ],
        ),
      ),
    );

    if (ok != true) return;
    final title = titleCtrl.text.trim();
    final amount = double.tryParse(amountCtrl.text.trim());
    if (title.isEmpty ||
        amount == null ||
        amount <= 0 ||
        amount > 100000 ||
        !RegExp(r'^\d+(\.\d{1,2})?$').hasMatch(amountCtrl.text.trim())) {
      _snack('Please enter a description and a valid amount (max 2 decimals)');
      return;
    }
    if (selected.isEmpty) {
      _snack('Choose at least one person to split with');
      return;
    }
    await DatabaseHelper.instance.addSharedExpense(
        widget.userId, title, amount, payerId, selected.toList()..sort());
    _load();
  }

  /// Mock payment: nothing is really paid. It simulates choosing a
  /// payment method, waits 2 seconds, then records the settlement.
  Future<void> _settle(Debt d) async {
    final method = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(
            '${_name(d.fromId)} pays ${formatRM(d.amount)} to ${_name(d.toId)}'),
        children: [
          for (final m in const [
            ("Touch 'n Go eWallet", Icons.account_balance_wallet),
            ('DuitNow QR', Icons.qr_code),
            ('Cash', Icons.payments),
          ])
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, m.$1),
              child: Row(children: [
                Icon(m.$2),
                const SizedBox(width: 12),
                Text(m.$1),
              ]),
            ),
        ],
      ),
    );
    if (method == null || !mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        content: Row(
          children: [
            const CircularProgressIndicator(),
            const SizedBox(width: 16),
            Expanded(child: Text('Processing $method payment (mock)...')),
          ],
        ),
      ),
    );
    await Future.delayed(const Duration(seconds: 2));
    await DatabaseHelper.instance
        .addSettlement(widget.userId, d.fromId, d.toId, d.amount, method);
    if (!mounted) return;
    Navigator.pop(context); // close the "processing" dialog
    _snack('Payment successful via $method (mock)');
    _load();
  }

  /// Sends a text summary to WhatsApp/Telegram etc. so roommates without
  /// the app can still see who owes whom.
  Future<void> _shareSummary() async {
    final b = StringBuffer()
      ..writeln('UniLedger - Household summary')
      ..writeln(formatDateTime(DateTime.now().toIso8601String()))
      ..writeln()
      ..writeln('Who owes whom:');
    if (_debts.isEmpty) {
      b.writeln('- Everyone is settled up');
    } else {
      for (final d in _debts) {
        b.writeln('- ${_name(d.fromId)} owes ${_name(d.toId)} ${formatRM(d.amount)}');
      }
    }
    if (_shared.isNotEmpty) {
      b
        ..writeln()
        ..writeln('Recent shared bills:');
      for (final e in _shared.take(5)) {
        final n = splitIdsOf(e, _members).length;
        b.writeln('- ${formatDate(e['date'] as String)} ${e['title']}: '
            '${formatRM((e['amount'] as num).toDouble())} '
            '(paid by ${_name(e['payer_id'] as int)}, split $n ways)');
      }
    }
    try {
      await ExportService.shareText(b.toString(), 'UniLedger household summary');
    } catch (_) {
      _snack('Could not open the share menu');
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  // ---------- UI ----------

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    final text = Theme.of(context).textTheme;

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addSharedExpense,
        icon: const Icon(Icons.add),
        label: const Text('Shared expense'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
        children: [
          // Action buttons
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) =>
                            StatementScreen(userId: widget.userId)),
                  ),
                  icon: const Icon(Icons.table_chart),
                  label: const Text('Statement'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _shareSummary,
                  icon: const Icon(Icons.share),
                  label: const Text('Share summary'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Members
          Text('Members', style: text.titleMedium),
          const SizedBox(height: 4),
          Text('One person keeps the household record. Roommates can see it via "Share summary".',
              style: text.bodySmall),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              ..._members.map((m) => Chip(
                    avatar: const Icon(Icons.person, size: 18),
                    label: Text(m['name'] as String),
                  )),
              ActionChip(
                avatar: const Icon(Icons.person_add, size: 18),
                label: const Text('Add roommate'),
                onPressed: _addMember,
              ),
            ],
          ),
          const Divider(height: 32),

          // Who owes whom
          Text('Who owes whom', style: text.titleMedium),
          const SizedBox(height: 8),
          if (_debts.isEmpty)
            const Card(
              child: ListTile(
                leading: Icon(Icons.check_circle, color: Colors.green),
                title: Text('Everyone is settled up'),
              ),
            )
          else
            ..._debts.map((d) => Card(
                  child: ListTile(
                    leading: const Icon(Icons.swap_horiz),
                    title: Text('${_name(d.fromId)} owes ${_name(d.toId)}'),
                    subtitle: Text(formatRM(d.amount)),
                    trailing: FilledButton.tonal(
                      onPressed: () => _settle(d),
                      child: const Text('Settle'),
                    ),
                  ),
                )),
          const Divider(height: 32),

          // Shared expenses
          Text('Shared expenses', style: text.titleMedium),
          if (_shared.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text('No shared expenses yet.'),
            ),
          ..._shared.map((e) {
            final names =
                splitIdsOf(e, _members).map(_name).join(', ');
            return ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.receipt),
              title: Text(e['title'] as String),
              subtitle: Text('Paid by ${_name(e['payer_id'] as int)} • '
                  '${formatDateTime(e['date'] as String)}\nSplit: $names'),
              isThreeLine: true,
              trailing: Text(formatRM((e['amount'] as num).toDouble())),
            );
          }),
        ],
      ),
    );
  }
}

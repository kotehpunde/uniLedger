import 'package:flutter/material.dart';

import '../categories.dart';
import '../database_helper.dart';
import '../export_service.dart';
import 'household_screen.dart';

/// One row of the statement: a shared bill or a payment between members.
class StatementEntry {
  final String date; // ISO date-time
  final String type; // 'Bill' or 'Payment'
  final String description;
  final String paidBy;
  final String detail; // who it was split between / who was paid
  final double amount;
  StatementEntry(this.date, this.type, this.description, this.paidBy,
      this.detail, this.amount);
}

/// Household statement: every bill and payment in date/time order,
/// with totals per person and CSV export.
class StatementScreen extends StatefulWidget {
  final int userId;
  const StatementScreen({super.key, required this.userId});

  @override
  State<StatementScreen> createState() => _StatementScreenState();
}

class _StatementScreenState extends State<StatementScreen> {
  bool _loading = true;
  List<StatementEntry> _entries = [];
  List<Map<String, dynamic>> _members = [];
  Map<int, double> _paid = {}; // how much each person paid for bills
  Map<int, double> _share = {}; // each person's share of the bills

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

    String name(int id) {
      for (final m in members) {
        if (m['id'] == id) return m['name'] as String;
      }
      return 'Unknown';
    }

    final paid = <int, double>{for (final m in members) m['id'] as int: 0};
    final share = <int, double>{for (final m in members) m['id'] as int: 0};
    final entries = <StatementEntry>[];

    for (final e in shared) {
      final amount = (e['amount'] as num).toDouble();
      final payer = e['payer_id'] as int;
      final splitIds = splitIdsOf(e, members);
      paid[payer] = (paid[payer] ?? 0) + amount;
      for (final id in splitIds) {
        share[id] = (share[id] ?? 0) + amount / splitIds.length;
      }
      entries.add(StatementEntry(
        e['date'] as String,
        'Bill',
        e['title'] as String,
        name(payer),
        'Split: ${splitIds.map(name).join(', ')}',
        amount,
      ));
    }

    for (final s in settlements) {
      entries.add(StatementEntry(
        s['date'] as String,
        'Payment',
        'Settle up (${s['method']})',
        name(s['from_id'] as int),
        'Paid to: ${name(s['to_id'] as int)}',
        (s['amount'] as num).toDouble(),
      ));
    }

    // Newest first. ISO dates sort correctly as text.
    entries.sort((a, b) => b.date.compareTo(a.date));

    if (!mounted) return;
    setState(() {
      _members = members;
      _entries = entries;
      _paid = paid;
      _share = share;
      _loading = false;
    });
  }

  Future<void> _export() async {
    if (_entries.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Nothing to export yet')));
      return;
    }
    final rows = <List<Object?>>[
      ['Date', 'Time', 'Type', 'Description', 'Paid by', 'Details',
        'Amount (RM)'],
      for (final e in _entries)
        [
          formatDate(e.date),
          formatDateTime(e.date).substring(11),
          e.type,
          e.description,
          e.paidBy,
          e.detail,
          e.amount.toStringAsFixed(2),
        ],
      [],
      ['Totals per person'],
      ['Name', 'Paid for bills (RM)', 'Share of bills (RM)'],
      for (final m in _members)
        [
          m['name'],
          (_paid[m['id']] ?? 0).toStringAsFixed(2),
          (_share[m['id']] ?? 0).toStringAsFixed(2),
        ],
    ];
    try {
      final savedTo = await ExportService.saveCsv(
        'uniledger_household_${ExportService.timestamp()}.csv',
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
    final text = Theme.of(context).textTheme;
    final totalBills = _paid.values.fold<double>(0, (a, b) => a + b);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Household statement'),
        actions: [
          IconButton(
            tooltip: 'Download CSV',
            icon: const Icon(Icons.file_download),
            onPressed: _export,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // ---- Who spent what ----
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Who spent what', style: text.titleMedium),
                        Text('Total shared bills: ${formatRM(totalBills)}'),
                        const SizedBox(height: 8),
                        Table(
                          columnWidths: const {0: FlexColumnWidth(2)},
                          children: [
                            const TableRow(children: [
                              Text('Name',
                                  style: TextStyle(fontWeight: FontWeight.bold)),
                              Text('Paid',
                                  textAlign: TextAlign.right,
                                  style: TextStyle(fontWeight: FontWeight.bold)),
                              Text('Share',
                                  textAlign: TextAlign.right,
                                  style: TextStyle(fontWeight: FontWeight.bold)),
                            ]),
                            for (final m in _members)
                              TableRow(children: [
                                Padding(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 4),
                                  child: Text(m['name'] as String),
                                ),
                                Padding(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 4),
                                  child: Text(formatRM(_paid[m['id']] ?? 0),
                                      textAlign: TextAlign.right),
                                ),
                                Padding(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 4),
                                  child: Text(formatRM(_share[m['id']] ?? 0),
                                      textAlign: TextAlign.right),
                                ),
                              ]),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _export,
                  icon: const Icon(Icons.file_download),
                  label: const Text('Download CSV spreadsheet'),
                ),
                const SizedBox(height: 16),

                // ---- All records ----
                Text('All records (newest first)', style: text.titleMedium),
                if (_entries.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Text('No bills or payments yet.'),
                  ),
                ..._entries.map((e) => ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        e.type == 'Bill' ? Icons.receipt : Icons.check_circle,
                        color: e.type == 'Bill' ? null : Colors.green,
                      ),
                      title: Text(e.description),
                      subtitle: Text(
                          '${formatDateTime(e.date)} • ${e.type} by ${e.paidBy}\n${e.detail}'),
                      isThreeLine: true,
                      trailing: Text(formatRM(e.amount)),
                    )),
              ],
            ),
    );
  }
}

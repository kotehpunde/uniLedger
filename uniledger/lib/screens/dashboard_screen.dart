import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../categories.dart';
import '../database_helper.dart';

class DashboardScreen extends StatefulWidget {
  final int userId;
  const DashboardScreen({super.key, required this.userId});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  bool _loading = true;
  String _name = '';
  double _budget = 0;
  double _spent = 0;
  double _lastMonth = 0;
  Map<String, double> _byCategory = {};
  String _tip = 'Loading tip...';

  @override
  void initState() {
    super.initState();
    _load();
    _loadTip();
  }

  Future<void> _load() async {
    final db = DatabaseHelper.instance;
    final now = DateTime.now();
    final user = await db.getUser(widget.userId);
    final spent = await db.monthTotal(widget.userId);
    // DateTime handles month 0 as December of the previous year.
    final lastMonth =
        await db.monthTotal(widget.userId, DateTime(now.year, now.month - 1, 1));
    final byCategory = await db.categoryTotals(widget.userId);
    if (!mounted) return;
    setState(() {
      _name = user?['name'] as String? ?? '';
      _budget = (user?['budget'] as num?)?.toDouble() ?? 0;
      _spent = spent;
      _lastMonth = lastMonth;
      _byCategory = byCategory;
      _loading = false;
    });
  }

  /// External API: Advice Slip API gives a random piece of advice.
  Future<void> _loadTip() async {
    try {
      final res = await http
          .get(Uri.parse(
              'https://api.adviceslip.com/advice?t=${DateTime.now().millisecondsSinceEpoch}'))
          .timeout(const Duration(seconds: 8));
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final advice = data['slip']['advice'] as String;
      if (mounted) setState(() => _tip = advice);
    } catch (_) {
      if (mounted) {
        setState(() =>
            _tip = 'Could not load a tip. Check your internet connection.');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());

    final colors = Theme.of(context).colorScheme;
    final ratio = _budget <= 0 ? 0.0 : _spent / _budget;
    final remaining = _budget - _spent;

    Color barColor = colors.primary;
    String status = 'You are within your budget.';
    if (ratio >= 1) {
      barColor = Colors.red;
      status = 'You are over budget by ${formatRM(-remaining)}!';
    } else if (ratio >= 0.8) {
      barColor = Colors.orange;
      status =
          'Careful, you have used ${(ratio * 100).toStringAsFixed(0)}% of your budget.';
    }

    return RefreshIndicator(
      onRefresh: () async {
        await _load();
        await _loadTip();
      },
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Hi, $_name',
              style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 16),

          // ---- Budget card ----
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Spent this month'),
                  const SizedBox(height: 4),
                  Text(formatRM(_spent),
                      style: Theme.of(context).textTheme.headlineMedium),
                  Text('of ${formatRM(_budget)} budget'),
                  const SizedBox(height: 12),
                  LinearProgressIndicator(
                    value: ratio.clamp(0.0, 1.0),
                    minHeight: 10,
                    color: barColor,
                    borderRadius: BorderRadius.circular(5),
                  ),
                  const SizedBox(height: 8),
                  Text(status, style: TextStyle(color: barColor)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          // ---- Spending insights ----
          _insightsCard(remaining),
          const SizedBox(height: 12),

          // ---- Category chart ----
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Spending by category',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 12),
                  if (_byCategory.isEmpty)
                    const Text('No expenses this month yet.')
                  else
                    ..._byCategory.entries.map((e) => _categoryBar(
                        e.key, e.value, _byCategory.values.first, colors)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          // ---- Tip from API ----
          Card(
            color: colors.secondaryContainer,
            child: ListTile(
              leading: const Icon(Icons.lightbulb),
              title: const Text('Tip of the day'),
              subtitle: Text(_tip),
              trailing: IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: _loadTip,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Helps the student improve, not just warns them.
  Widget _insightsCard(double remaining) {
    final now = DateTime.now();
    final daysInMonth = DateTime(now.year, now.month + 1, 0).day;
    final daysLeft = daysInMonth - now.day + 1; // including today
    final safePerDay = remaining > 0 ? remaining / daysLeft : 0.0;

    // 1. Safe to spend today
    final Widget safeTile = remaining > 0
        ? ListTile(
            leading: const Icon(Icons.today, color: Colors.green),
            title: Text('Safe to spend today: ${formatRM(safePerDay)}'),
            subtitle: Text(
                '${formatRM(remaining)} left for $daysLeft day${daysLeft == 1 ? '' : 's'}'),
          )
        : ListTile(
            leading: const Icon(Icons.block, color: Colors.red),
            title: const Text('Safe to spend today: RM 0.00'),
            subtitle: Text(
                'Your budget is used up. For the next $daysLeft day${daysLeft == 1 ? '' : 's'}, spend only on essentials like groceries and transport.'),
          );

    // 2. Biggest category + tip
    Widget? topTile;
    if (_byCategory.isNotEmpty && _spent > 0) {
      final top = _byCategory.entries.first;
      final percent = (top.value / _spent * 100).toStringAsFixed(0);
      topTile = ListTile(
        leading: Icon(categoryIcons[top.key] ?? Icons.category,
            color: Colors.orange),
        title: Text('${top.key} is $percent% of your spending'),
        subtitle: Text(categoryTips[top.key] ?? ''),
      );
    }

    // 3. Compared with last month
    final Widget compareTile;
    if (_lastMonth <= 0) {
      compareTile = const ListTile(
        leading: Icon(Icons.history),
        title: Text('No data from last month yet'),
        subtitle: Text('Keep recording to see how you compare.'),
      );
    } else {
      final change = (_spent - _lastMonth) / _lastMonth * 100;
      final more = change > 0;
      compareTile = ListTile(
        leading: Icon(more ? Icons.trending_up : Icons.trending_down,
            color: more ? Colors.red : Colors.green),
        title: Text(
            '${change.abs().toStringAsFixed(0)}% ${more ? 'more' : 'less'} than last month'),
        subtitle: Text(
            'So far this month: ${formatRM(_spent)}  •  Last month: ${formatRM(_lastMonth)}'),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Text('Spending insights',
                  style: Theme.of(context).textTheme.titleMedium),
            ),
            safeTile,
            if (topTile != null) topTile,
            compareTile,
          ],
        ),
      ),
    );
  }

  /// One horizontal bar. The biggest category fills the full width.
  Widget _categoryBar(
      String name, double amount, double max, ColorScheme colors) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(categoryIcons[name] ?? Icons.category, size: 20),
          const SizedBox(width: 8),
          SizedBox(width: 90, child: Text(name)),
          Expanded(
            child: Container(
              height: 14,
              decoration: BoxDecoration(
                color: colors.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(7),
              ),
              child: FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: max == 0 ? 0 : amount / max,
                child: Container(
                  decoration: BoxDecoration(
                    color: colors.primary,
                    borderRadius: BorderRadius.circular(7),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(formatRM(amount)),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../categories.dart';
import '../database_helper.dart';
import '../session.dart';
import 'login_screen.dart';

class ProfileScreen extends StatefulWidget {
  final int userId;
  const ProfileScreen({super.key, required this.userId});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  String _username = '';
  String _studentId = '';
  double _budget = 0;
  int _expenseCount = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final db = DatabaseHelper.instance;
    final user = await db.getUser(widget.userId);
    final expenses = await db.getExpenses(widget.userId);
    if (!mounted) return;
    setState(() {
      _username = user?['name'] as String? ?? '';
      _studentId = user?['student_id'] as String? ?? '';
      _budget = (user?['budget'] as num?)?.toDouble() ?? 0;
      _expenseCount = expenses.length;
    });
  }

  Future<void> _editBudget() async {
    final ctrl = TextEditingController(text: _budget.toStringAsFixed(0));
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Monthly budget'),
        content: TextField(
          controller: ctrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(prefixText: 'RM '),
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
    );
    final value = double.tryParse(ctrl.text.trim());
    if (ok != true || value == null || value <= 0) return;
    await DatabaseHelper.instance.updateBudget(widget.userId, value);
    _load();
  }

  Future<void> _logout() async {
    await Session.clear();
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const SizedBox(height: 16),
        CircleAvatar(
          radius: 40,
          backgroundColor: colors.primaryContainer,
          child: Text(
            _username.isEmpty ? '?' : _username[0].toUpperCase(),
            style: const TextStyle(fontSize: 32),
          ),
        ),
        const SizedBox(height: 12),
        Text(_username,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleLarge),
        Text(_studentId, textAlign: TextAlign.center),
        const SizedBox(height: 24),
        Card(
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.savings),
                title: const Text('Monthly budget'),
                subtitle: Text(formatRM(_budget)),
                trailing: const Icon(Icons.edit),
                onTap: _editBudget,
              ),
              ListTile(
                leading: const Icon(Icons.receipt_long),
                title: const Text('Expenses recorded'),
                trailing: Text('$_expenseCount'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        OutlinedButton.icon(
          onPressed: _logout,
          icon: const Icon(Icons.logout),
          label: const Text('Log out'),
        ),
      ],
    );
  }
}

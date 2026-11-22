import 'package:flutter/material.dart';

import '../database_helper.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  static final _idFormat = RegExp(r'^P\d{8}$'); // P + 8 digits

  final _formKey = GlobalKey<FormState>();
  final _idCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  bool _loading = false;
  String? _foundName; // name from the mock university records
  bool _checkedId = false;

  /// Looks the student up as soon as a full ID is typed.
  Future<void> _onIdChanged(String value) async {
    final id = value.trim().toUpperCase();
    if (!_idFormat.hasMatch(id)) {
      setState(() {
        _foundName = null;
        _checkedId = false;
      });
      return;
    }
    final name = await DatabaseHelper.instance.studentName(id);
    if (!mounted) return;
    setState(() {
      _foundName = name;
      _checkedId = true;
    });
  }

  Future<void> _register() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);

    final error = await DatabaseHelper.instance
        .register(_idCtrl.text.trim().toUpperCase(), _passwordCtrl.text);

    if (!mounted) return;
    setState(() => _loading = false);

    if (error != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error)));
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Account created. Please log in.')),
    );
    Navigator.pop(context);
  }

  @override
  void dispose() {
    _idCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Create account')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                  'Sign up with your university student ID and create your own password.'),
              const SizedBox(height: 16),
              TextFormField(
                controller: _idCtrl,
                textCapitalization: TextCapitalization.characters,
                onChanged: _onIdChanged,
                decoration: const InputDecoration(
                  labelText: 'Student ID',
                  hintText: 'P22014397',
                  prefixIcon: Icon(Icons.badge),
                  border: OutlineInputBorder(),
                ),
                validator: (v) {
                  final id = (v ?? '').trim().toUpperCase();
                  if (!_idFormat.hasMatch(id)) {
                    return 'Format: P followed by 8 digits';
                  }
                  if (_checkedId && _foundName == null) {
                    return 'Student ID not found in university records';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 8),
              if (_foundName != null)
                Row(children: [
                  const Icon(Icons.check_circle, color: Colors.green, size: 18),
                  const SizedBox(width: 6),
                  Text('Student found: $_foundName'),
                ])
              else if (_checkedId)
                const Row(children: [
                  Icon(Icons.error, color: Colors.red, size: 18),
                  SizedBox(width: 6),
                  Text('Not found in university records'),
                ]),
              const SizedBox(height: 16),
              TextFormField(
                controller: _passwordCtrl,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Password',
                  prefixIcon: Icon(Icons.lock),
                  border: OutlineInputBorder(),
                ),
                validator: (v) => (v == null || v.length < 6)
                    ? 'At least 6 characters'
                    : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _confirmCtrl,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Confirm password',
                  prefixIcon: Icon(Icons.lock_outline),
                  border: OutlineInputBorder(),
                ),
                validator: (v) =>
                    v != _passwordCtrl.text ? 'Passwords do not match' : null,
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _loading ? null : _register,
                child: const Padding(
                  padding: EdgeInsets.all(12),
                  child: Text('Sign up'),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Demo student IDs (mock university records): P22014397 to P22014406',
                textAlign: TextAlign.center,
                style: TextStyle(color: colors.outline, fontSize: 13),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

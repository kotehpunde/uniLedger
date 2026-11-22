import 'package:flutter/material.dart';

import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'session.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // If someone logged in before, skip the login screen.
  final userId = await Session.getUserId();
  runApp(UniLedgerApp(startUserId: userId));
}

class UniLedgerApp extends StatelessWidget {
  final int? startUserId;
  const UniLedgerApp({super.key, this.startUserId});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'UniLedger',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF00897B), // teal
        useMaterial3: true,
      ),
      home: startUserId == null
          ? const LoginScreen()
          : HomeScreen(userId: startUserId!),
    );
  }
}

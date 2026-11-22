import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

/// Handles everything to do with the local SQLite database.
/// Every query is filtered by user_id so a user can only see their own data.
class DatabaseHelper {
  DatabaseHelper._();
  static final DatabaseHelper instance = DatabaseHelper._();

  Database? _db;

  /// Mock university records. In a real deployment this would be replaced
  /// by the university's own student system.
  static const Map<String, String> mockStudents = {
    'P22014397': 'Joel Vincent',
    'P22014398': 'Aiman Hakim',
    'P22014399': 'Tan Wei Jie',
    'P22014400': 'Priya Nair',
    'P22014401': 'Lim Mei Ling',
    'P22014402': 'Muhammad Faris',
    'P22014403': 'Sarah Lee',
    'P22014404': 'Arjun Kumar',
    'P22014405': 'Nurul Aina',
    'P22014406': 'Daniel Wong',
  };

  Future<Database> get database async {
    _db ??= await _open();
    return _db!;
  }

  Future<Database> _open() async {
    // "v2" file name so the database from the first version is not reused.
    final path = join(await getDatabasesPath(), 'uniledger_v2.db');
    return openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE students(
            student_id TEXT PRIMARY KEY,
            name TEXT NOT NULL
          )''');
        await db.execute('''
          CREATE TABLE users(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            student_id TEXT UNIQUE NOT NULL,
            name TEXT NOT NULL,
            password_hash TEXT NOT NULL,
            budget REAL NOT NULL DEFAULT 1000
          )''');
        await db.execute('''
          CREATE TABLE expenses(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            user_id INTEGER NOT NULL,
            title TEXT NOT NULL,
            amount REAL NOT NULL,
            category TEXT NOT NULL,
            date TEXT NOT NULL,
            original_amount REAL NOT NULL,
            currency TEXT NOT NULL DEFAULT 'MYR'
          )''');
        await db.execute('''
          CREATE TABLE members(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            user_id INTEGER NOT NULL,
            name TEXT NOT NULL
          )''');
        await db.execute('''
          CREATE TABLE shared_expenses(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            user_id INTEGER NOT NULL,
            title TEXT NOT NULL,
            amount REAL NOT NULL,
            payer_id INTEGER NOT NULL,
            split_ids TEXT NOT NULL,
            date TEXT NOT NULL
          )''');
        await db.execute('''
          CREATE TABLE settlements(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            user_id INTEGER NOT NULL,
            from_id INTEGER NOT NULL,
            to_id INTEGER NOT NULL,
            amount REAL NOT NULL,
            method TEXT NOT NULL,
            date TEXT NOT NULL
          )''');

        // Fill the mock student records.
        final batch = db.batch();
        mockStudents.forEach((id, name) {
          batch.insert('students', {'student_id': id, 'name': name});
        });
        await batch.commit(noResult: true);
      },
    );
  }

  // ---------- Students / authentication ----------

  /// Passwords are never stored as plain text, only as a SHA-256 hash.
  String hashPassword(String password) =>
      sha256.convert(utf8.encode(password)).toString();

  /// Looks up a student's name in the mock university records.
  Future<String?> studentName(String studentId) async {
    final db = await database;
    final rows = await db.query('students',
        where: 'student_id = ?', whereArgs: [studentId]);
    return rows.isEmpty ? null : rows.first['name'] as String;
  }

  /// Returns null if successful, otherwise an error message.
  Future<String?> register(String studentId, String password) async {
    final db = await database;
    final name = await studentName(studentId);
    if (name == null) return 'Student ID not found in university records';

    final existing = await db.query('users',
        where: 'student_id = ?', whereArgs: [studentId]);
    if (existing.isNotEmpty) return 'This student ID already has an account';

    final id = await db.insert('users', {
      'student_id': studentId,
      'name': name,
      'password_hash': hashPassword(password),
    });
    // The student is automatically the first member of their household.
    await db.insert('members', {'user_id': id, 'name': name});
    return null;
  }

  /// Returns the user id if the student ID and password match, otherwise null.
  Future<int?> login(String studentId, String password) async {
    final db = await database;
    final rows = await db.query(
      'users',
      where: 'student_id = ? AND password_hash = ?',
      whereArgs: [studentId, hashPassword(password)],
    );
    if (rows.isEmpty) return null;
    return rows.first['id'] as int;
  }

  Future<Map<String, dynamic>?> getUser(int userId) async {
    final db = await database;
    final rows =
        await db.query('users', where: 'id = ?', whereArgs: [userId]);
    return rows.isEmpty ? null : rows.first;
  }

  Future<void> updateBudget(int userId, double budget) async {
    final db = await database;
    await db.update('users', {'budget': budget},
        where: 'id = ?', whereArgs: [userId]);
  }

  // ---------- Personal expenses ----------

  /// "2026-11" style key for a month.
  static String monthKey(DateTime d) => d.toIso8601String().substring(0, 7);

  Future<void> addExpense({
    required int userId,
    required String title,
    required double amount,
    required String category,
    required DateTime date,
    required double originalAmount,
    required String currency,
  }) async {
    final db = await database;
    await db.insert('expenses', {
      'user_id': userId,
      'title': title,
      'amount': amount,
      'category': category,
      'date': date.toIso8601String(),
      'original_amount': originalAmount,
      'currency': currency,
    });
  }

  Future<void> updateExpense({
    required int userId,
    required int expenseId,
    required String title,
    required double amount,
    required String category,
    required DateTime date,
    required double originalAmount,
    required String currency,
  }) async {
    final db = await database;
    await db.update(
      'expenses',
      {
        'title': title,
        'amount': amount,
        'category': category,
        'date': date.toIso8601String(),
        'original_amount': originalAmount,
        'currency': currency,
      },
      where: 'id = ? AND user_id = ?',
      whereArgs: [expenseId, userId],
    );
  }

  /// Puts a deleted expense back (used by the Undo button).
  Future<void> restoreExpense(Map<String, dynamic> row) async {
    final db = await database;
    await db.insert('expenses', row);
  }

  Future<List<Map<String, dynamic>>> getExpenses(int userId) async {
    final db = await database;
    return db.query('expenses',
        where: 'user_id = ?', whereArgs: [userId], orderBy: 'date DESC');
  }

  Future<void> deleteExpense(int userId, int expenseId) async {
    final db = await database;
    await db.delete('expenses',
        where: 'id = ? AND user_id = ?', whereArgs: [expenseId, userId]);
  }

  /// Total spent in a month (default: this month).
  Future<double> monthTotal(int userId, [DateTime? month]) async {
    final db = await database;
    final rows = await db.rawQuery(
      'SELECT SUM(amount) AS total FROM expenses WHERE user_id = ? AND date LIKE ?',
      [userId, '${monthKey(month ?? DateTime.now())}%'],
    );
    final total = rows.first['total'];
    return total == null ? 0 : (total as num).toDouble();
  }

  /// Spending per category for this month, biggest first.
  Future<Map<String, double>> categoryTotals(int userId) async {
    final db = await database;
    final rows = await db.rawQuery(
      'SELECT category, SUM(amount) AS total FROM expenses '
      'WHERE user_id = ? AND date LIKE ? GROUP BY category ORDER BY total DESC',
      [userId, '${monthKey(DateTime.now())}%'],
    );
    return {
      for (final r in rows)
        r['category'] as String: (r['total'] as num).toDouble(),
    };
  }

  // ---------- Household (shared expenses) ----------

  Future<List<Map<String, dynamic>>> getMembers(int userId) async {
    final db = await database;
    return db.query('members',
        where: 'user_id = ?', whereArgs: [userId], orderBy: 'id');
  }

  Future<void> addMember(int userId, String name) async {
    final db = await database;
    await db.insert('members', {'user_id': userId, 'name': name});
  }

  /// [splitIds] = the members who share this bill.
  Future<void> addSharedExpense(int userId, String title, double amount,
      int payerId, List<int> splitIds) async {
    final db = await database;
    await db.insert('shared_expenses', {
      'user_id': userId,
      'title': title,
      'amount': amount,
      'payer_id': payerId,
      'split_ids': splitIds.join(','),
      'date': DateTime.now().toIso8601String(),
    });
  }

  Future<List<Map<String, dynamic>>> getSharedExpenses(int userId) async {
    final db = await database;
    return db.query('shared_expenses',
        where: 'user_id = ?', whereArgs: [userId], orderBy: 'date DESC');
  }

  Future<void> addSettlement(int userId, int fromId, int toId, double amount,
      String method) async {
    final db = await database;
    await db.insert('settlements', {
      'user_id': userId,
      'from_id': fromId,
      'to_id': toId,
      'amount': amount,
      'method': method,
      'date': DateTime.now().toIso8601String(),
    });
  }

  Future<List<Map<String, dynamic>>> getSettlements(int userId) async {
    final db = await database;
    return db.query('settlements',
        where: 'user_id = ?', whereArgs: [userId], orderBy: 'date DESC');
  }
}

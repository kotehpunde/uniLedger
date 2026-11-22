import 'package:flutter/material.dart';

/// Expense categories and their icons, shared by several screens.
const Map<String, IconData> categoryIcons = {
  'Food': Icons.restaurant,
  'Groceries': Icons.shopping_cart,
  'Transport': Icons.directions_bus,
  'Utilities': Icons.bolt,
  'Entertainment': Icons.movie,
  'Shopping': Icons.shopping_bag,
  'Other': Icons.category,
};

List<String> get categories => categoryIcons.keys.toList();

/// Keywords used to guess a category from what the user types.
/// Example: "Grab to campus" -> Transport.
const Map<String, List<String>> _keywords = {
  'Food': [
    'mamak', 'nasi', 'mee', 'roti', 'lunch', 'dinner', 'breakfast', 'makan',
    'mcd', 'kfc', 'pizza', 'burger', 'coffee', 'kopi', 'starbucks', 'tealive',
    'food', 'cafe', 'restaurant',
  ],
  'Groceries': [
    'grocer', 'tesco', 'lotus', 'aeon', 'giant', 'mydin', 'speedmart',
    'market', 'supermarket',
  ],
  'Transport': [
    'grab', 'bus', 'lrt', 'mrt', 'petrol', 'fuel', 'parking', 'taxi', 'toll',
    'train', 'ktm',
  ],
  'Utilities': [
    'electric', 'tnb', 'water', 'wifi', 'internet', 'unifi', 'maxis',
    'celcom', 'digi', 'phone bill', 'rent',
  ],
  'Entertainment': [
    'movie', 'tgv', 'gsc', 'cinema', 'netflix', 'spotify', 'game', 'steam',
    'concert', 'karaoke',
  ],
  'Shopping': [
    'shopee', 'lazada', 'clothes', 'shirt', 'shoes', 'uniqlo', 'zalora',
    'watson', 'guardian',
  ],
};

/// Returns a suggested category, or null if no keyword matches.
String? suggestCategory(String title) {
  final text = title.toLowerCase();
  for (final entry in _keywords.entries) {
    for (final word in entry.value) {
      if (text.contains(word)) return entry.key;
    }
  }
  return null;
}

/// A money-saving tip for each category (used in Spending insights).
const Map<String, String> categoryTips = {
  'Food': 'Try cooking or bringing lunch from home a few days a week.',
  'Groceries': 'Make a shopping list and compare prices between stores.',
  'Transport': 'Share rides with friends or use the bus instead of Grab.',
  'Utilities': 'Switch off the air-con and lights when leaving the room.',
  'Entertainment': 'Look for student discounts or share subscriptions.',
  'Shopping': 'Wait 24 hours before buying anything that is not essential.',
  'Other': 'Review these expenses and cut the ones you do not need.',
};

String formatRM(double value) => 'RM ${value.toStringAsFixed(2)}';

/// "2026-11-22T14:05:33.123" -> "2026-11-22 14:05"
String formatDateTime(String iso) =>
    iso.length >= 16 ? iso.substring(0, 16).replaceFirst('T', ' ') : iso;

/// "2026-11-22T14:05:33.123" -> "2026-11-22"
String formatDate(String iso) => iso.length >= 10 ? iso.substring(0, 10) : iso;

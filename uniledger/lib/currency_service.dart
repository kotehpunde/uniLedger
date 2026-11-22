import 'dart:convert';

import 'package:http/http.dart' as http;

/// External API: ExchangeRate-API (free, no key needed).
/// Used when an expense is paid in a foreign currency, e.g. a Netflix
/// or Spotify subscription charged in USD.
class CurrencyService {
  static const currencies = [
    'MYR', 'USD', 'SGD', 'EUR', 'GBP', 'AUD', 'CNY', 'JPY', 'THB', 'IDR',
  ];

  // Rates are downloaded once and then kept in memory.
  static Map<String, double>? _rates;

  /// How many units of each currency equal 1 MYR.
  static Future<Map<String, double>> getRates() async {
    if (_rates != null) return _rates!;
    final res = await http
        .get(Uri.parse('https://open.er-api.com/v6/latest/MYR'))
        .timeout(const Duration(seconds: 10));
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    if (data['result'] != 'success') throw Exception('API error');
    final raw = data['rates'] as Map<String, dynamic>;
    _rates = raw.map((code, rate) => MapEntry(code, (rate as num).toDouble()));
    return _rates!;
  }

  /// Converts an amount in [currency] into Malaysian Ringgit.
  static Future<double> toMYR(double amount, String currency) async {
    if (currency == 'MYR') return amount;
    final rates = await getRates();
    final rate = rates[currency];
    if (rate == null || rate == 0) throw Exception('No rate for $currency');
    return amount / rate;
  }
}

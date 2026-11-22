import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// Saves CSV spreadsheets to the phone's Downloads folder, and shares
/// the household text summary.
class ExportService {
  /// Wraps a value in quotes so commas inside text don't break the CSV.
  static String _cell(Object? value) {
    final text = '${value ?? ''}';
    return '"${text.replaceAll('"', '""')}"';
  }

  static String toCsv(List<List<Object?>> rows) =>
      rows.map((row) => row.map(_cell).join(',')).join('\n');

  /// e.g. 20261122_1405, used in file names.
  static String timestamp() {
    final n = DateTime.now();
    String two(int x) => x.toString().padLeft(2, '0');
    return '${n.year}${two(n.month)}${two(n.day)}_${two(n.hour)}${two(n.minute)}';
  }

  /// Saves the CSV into the phone's Download folder and returns where it
  /// went. If Android blocks that folder, it saves inside the app's own
  /// storage folder instead.
  static Future<String> saveCsv(
      String fileName, List<List<Object?>> rows) async {
    final csv = toCsv(rows);
    try {
      final file = File('/storage/emulated/0/Download/$fileName');
      await file.writeAsString(csv);
      return 'Downloads/$fileName';
    } catch (_) {
      final dir = await getExternalStorageDirectory() ??
          await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/$fileName');
      await file.writeAsString(csv);
      return file.path;
    }
  }

  static Future<void> shareText(String text, String subject) async {
    await SharePlus.instance.share(ShareParams(text: text, subject: subject));
  }
}

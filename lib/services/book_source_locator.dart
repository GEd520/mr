import '../models/book_source.dart';

class BookSourceLocator {
  static List<BookSource> locate(
    String bookUrl,
    Iterable<BookSource> sources, {
    bool enabledOnly = true,
  }) {
    final normalized = _stripUrlOption(bookUrl);
    final matches = <BookSource>[];
    for (final source in sources) {
      if (enabledOnly && !source.enabled) continue;
      final pattern = source.bookUrlPattern?.trim();
      if (pattern != null && pattern.isNotEmpty) {
        try {
          if (RegExp(pattern).hasMatch(normalized)) matches.add(source);
        } on FormatException {
          // Invalid source patterns are ignored instead of breaking source lookup.
        }
      } else if (_sameHost(normalized, source.bookSourceUrl)) {
        matches.add(source);
      }
    }
    matches.sort((a, b) {
      final weight = b.weight.compareTo(a.weight);
      return weight != 0 ? weight : a.customOrder.compareTo(b.customOrder);
    });
    return matches;
  }

  static BookSource? locateFirst(String bookUrl, Iterable<BookSource> sources) {
    final matches = locate(bookUrl, sources);
    return matches.isEmpty ? null : matches.first;
  }

  static String _stripUrlOption(String value) =>
      value.split(RegExp(r'\s*,\s*(?=\{)')).first.trim();

  static bool _sameHost(String left, String right) {
    final leftUri = Uri.tryParse(left);
    final rightUri = Uri.tryParse(right);
    return leftUri != null &&
        rightUri != null &&
        leftUri.host.isNotEmpty &&
        leftUri.host.toLowerCase() == rightUri.host.toLowerCase();
  }
}

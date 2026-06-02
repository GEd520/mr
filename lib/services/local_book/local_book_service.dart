import 'dart:io';
import 'dart:typed_data';
import '../../models/book.dart';
import '../../models/chapter.dart';
import 'epub_parser.dart';
import 'txt_parser.dart';

enum LocalBookType { txt, epub, pdf, unsupported }

class LocalBookService {
  static final LocalBookService instance = LocalBookService._internal();
  LocalBookService._internal();

  final Map<String, dynamic> _epubCache = {};
  final Map<String, List<TxtChapter>> _txtChapterCache = {};
  final Map<String, String> _contentCache = {};

  static LocalBookType detectBookType(String filePath) {
    final ext = filePath.split('.').last.toLowerCase();
    switch (ext) {
      case 'txt':
        return LocalBookType.txt;
      case 'epub':
        return LocalBookType.epub;
      case 'pdf':
        return LocalBookType.pdf;
      default:
        return LocalBookType.unsupported;
    }
  }

  static bool isSupported(String filePath) {
    return detectBookType(filePath) != LocalBookType.unsupported;
  }

  static List<String> get supportedExtensions => ['txt', 'epub'];

  Future<List<Book>> scanDirectory(String directoryPath) async {
    final books = <Book>[];
    final dir = Directory(directoryPath);
    
    if (!await dir.exists()) return books;
    
    await for (final entity in dir.list(recursive: true)) {
      if (entity is File) {
        final filePath = entity.path;
        if (isSupported(filePath)) {
          try {
            final bytes = await entity.readAsBytes();
            final book = createBookFromFile(filePath, bytes: bytes);
            books.add(book);
          } catch (e) {
            continue;
          }
        }
      }
    }
    
    return books;
  }

  Future<Book?> importFile(String filePath) async {
    if (!isSupported(filePath)) return null;
    
    try {
      final file = File(filePath);
      if (!await file.exists()) return null;
      
      final bytes = await file.readAsBytes();
      return createBookFromFile(filePath, bytes: bytes);
    } catch (e) {
      return null;
    }
  }

  Book createBookFromFile(String filePath, {Uint8List? bytes}) {
    final bookType = detectBookType(filePath);
    final fileName = filePath.split('/').last.split('\\').last;
    final (name, author) = TxtParser.extractNameAndAuthor(fileName);

    String? coverPath;
    String? description;

    if (bookType == LocalBookType.epub && bytes != null) {
      final epubData = _parseEpubData(bytes);
      if (epubData != null) {
        final epubBook = EpubParser.parse(epubData);
        return Book(
          bookUrl: filePath,
          name: epubBook.title.isNotEmpty ? epubBook.title : name,
          author: epubBook.author ?? author ?? '',
          coverUrl: epubBook.coverPath ?? '',
          intro: epubBook.description ?? '',
          mediaType: MediaType.novel,
          originType: BookOriginType.local,
          canUpdate: false,
          addedTime: DateTime.now(),
        );
      }
    }

    return Book(
      bookUrl: filePath,
      name: name,
      author: author ?? '',
      coverUrl: coverPath ?? '',
      intro: description ?? '',
      mediaType: MediaType.novel,
      originType: BookOriginType.local,
      canUpdate: false,
      addedTime: DateTime.now(),
    );
  }

  Future<List<Chapter>> getChapterList(Book book) async {
    final bookType = detectBookType(book.bookUrl);

    switch (bookType) {
      case LocalBookType.txt:
        return _getTxtChapterList(book);
      case LocalBookType.epub:
        return _getEpubChapterList(book);
      case LocalBookType.pdf:
      case LocalBookType.unsupported:
        return [];
    }
  }

  Future<String?> getContent(Book book, Chapter chapter) async {
    final cacheKey = '${book.bookUrl}_${chapter.index}';
    if (_contentCache.containsKey(cacheKey)) {
      return _contentCache[cacheKey];
    }

    final bookType = detectBookType(book.bookUrl);
    String? content;

    switch (bookType) {
      case LocalBookType.txt:
        content = await _getTxtContent(book, chapter);
        break;
      case LocalBookType.epub:
        content = await _getEpubContent(book, chapter);
        break;
      case LocalBookType.pdf:
      case LocalBookType.unsupported:
        content = null;
    }

    if (content != null) {
      _contentCache[cacheKey] = content;
      if (_contentCache.length > 100) {
        _contentCache.remove(_contentCache.keys.first);
      }
    }

    return content;
  }

  Future<List<Chapter>> _getTxtChapterList(Book book) async {
    if (_txtChapterCache.containsKey(book.bookUrl)) {
      return _txtChapterCache[book.bookUrl]!.asMap().entries.map((entry) {
        return Chapter(
          id: '${book.bookUrl}_${entry.key}',
          bookId: book.bookUrl,
          title: entry.value.title,
          index: entry.value.index,
        );
      }).toList();
    }

    return [];
  }

  void cacheTxtChapters(String bookUrl, List<TxtChapter> chapters) {
    _txtChapterCache[bookUrl] = chapters;
  }

  Future<String?> _getTxtContent(Book book, Chapter chapter) async {
    final chapters = _txtChapterCache[book.bookUrl];
    if (chapters == null || chapter.index >= chapters.length) return null;
    return chapters[chapter.index].content;
  }

  Future<List<Chapter>> _getEpubChapterList(Book book) async {
    final epubData = _epubCache[book.bookUrl];
    if (epubData == null) return [];

    final epubBook = EpubParser.parse(epubData);
    return epubBook.chapters.map((epubChapter) {
      return Chapter(
        id: '${book.bookUrl}_${epubChapter.index}',
        bookId: book.bookUrl,
        title: epubChapter.title,
        index: epubChapter.index,
        url: epubChapter.href,
      );
    }).toList();
  }

  Future<String?> _getEpubContent(Book book, Chapter chapter) async {
    final epubData = _epubCache[book.bookUrl];
    if (epubData == null) return null;

    final epubBook = EpubParser.parse(epubData);
    if (chapter.index >= epubBook.chapters.length) return null;

    final epubChapter = epubBook.chapters[chapter.index];
    if (epubChapter.content != null) {
      return EpubParser.extractTextFromHtml(epubChapter.content!);
    }

    final contents = epubData['contents'] as List<dynamic>? ?? [];
    if (chapter.index < contents.length) {
      final content = contents[chapter.index];
      if (content is String) {
        return EpubParser.extractTextFromHtml(content);
      }
      if (content is Map && content.containsKey('data')) {
        final data = content['data'];
        if (data is String) {
          return EpubParser.extractTextFromHtml(data);
        }
      }
    }

    return null;
  }

  Map<String, dynamic>? _parseEpubData(Uint8List bytes) {
    return null;
  }

  void cacheEpubData(String bookUrl, Map<String, dynamic> data) {
    _epubCache[bookUrl] = data;
  }

  void clearCache({String? bookUrl}) {
    if (bookUrl != null) {
      _epubCache.remove(bookUrl);
      _txtChapterCache.remove(bookUrl);
      _contentCache.removeWhere((key, _) => key.startsWith(bookUrl));
    } else {
      _epubCache.clear();
      _txtChapterCache.clear();
      _contentCache.clear();
    }
  }

  static String formatWordCount(int count) {
    if (count < 1000) return '$count';
    if (count < 10000) return '${(count / 1000).toStringAsFixed(1)}k';
    return '${(count / 10000).toStringAsFixed(1)}万';
  }
}

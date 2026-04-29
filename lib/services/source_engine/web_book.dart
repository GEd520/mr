import 'package:dio/dio.dart';
import '../../models/book_source.dart';
import '../../models/book.dart';
import '../../models/chapter.dart';
import 'analyze_rule.dart';

class WebBook {
  final BookSource source;
  final Dio _dio;

  WebBook(this.source) : _dio = Dio(BaseOptions(
    headers: _parseHeaders(source.header),
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 30),
  ));

  static Map<String, String> _parseHeaders(String? headerStr) {
    final headers = <String, String>{};
    if (headerStr == null || headerStr.isEmpty) return headers;

    try {
      final lines = headerStr.split('\n');
      for (final line in lines) {
        final parts = line.split(':');
        if (parts.length >= 2) {
          headers[parts[0].trim()] = parts.sublist(1).join(':').trim();
        }
      }
    } catch (_) {}

    return headers;
  }

  Future<List<Map<String, dynamic>>> searchBook(String keyword) async {
    if (source.searchUrl == null || source.searchUrl!.isEmpty) {
      return [];
    }

    final searchRule = source.ruleSearch;
    if (searchRule == null) return [];

    String url = source.searchUrl!;
    if (url.contains('{{key}}')) {
      url = url.replaceAll('{{key}}', keyword);
    } else if (url.contains('{{searchKey}}')) {
      url = url.replaceAll('{{searchKey}}', keyword);
    }

    try {
      final response = await _dio.get(url);
      final html = response.data.toString();

      final rule = AnalyzeRule()..setContent(html, baseUrl: source.bookSourceUrl);

      final bookList = rule.getStringList(searchRule.bookList ?? '');
      final nameList = rule.getStringList(searchRule.name ?? '');
      final authorList = rule.getStringList(searchRule.author ?? '');
      final coverList = rule.getStringList(searchRule.coverUrl ?? '');
      final introList = rule.getStringList(searchRule.intro ?? '');
      final bookUrlList = rule.getStringList(searchRule.bookUrl ?? '');

      final results = <Map<String, dynamic>>[];

      for (int i = 0; i < nameList.length; i++) {
        results.add({
          'name': nameList[i],
          'author': i < authorList.length ? authorList[i] : '',
          'coverUrl': i < coverList.length ? coverList[i] : '',
          'intro': i < introList.length ? introList[i] : '',
          'bookUrl': i < bookUrlList.length ? bookUrlList[i] : '',
          'sourceUrl': source.bookSourceUrl,
          'sourceName': source.bookSourceName,
        });
      }

      return results;
    } catch (e) {
      return [];
    }
  }

  Future<Book?> getBookInfo(String bookUrl) async {
    final bookInfoRule = source.ruleBookInfo;
    if (bookInfoRule == null) return null;

    try {
      final response = await _dio.get(bookUrl);
      final html = response.data.toString();

      final rule = AnalyzeRule()..setContent(html, baseUrl: bookUrl);

      return Book(
        bookUrl: bookUrl,
        name: rule.getString(bookInfoRule.name ?? '') ?? '未知书名',
        author: rule.getString(bookInfoRule.author ?? '') ?? '',
        coverUrl: rule.getString(bookInfoRule.coverUrl ?? '') ?? '',
        intro: rule.getString(bookInfoRule.intro ?? '') ?? '',
        mediaType: MediaType.novel,
        originType: BookOriginType.online,
        sourceUrl: source.bookSourceUrl,
        sourceName: source.bookSourceName,
        canUpdate: true,
        addedTime: DateTime.now(),
      );
    } catch (e) {
      return null;
    }
  }

  Future<List<Chapter>> getChapterList(String bookUrl) async {
    final tocRule = source.ruleToc;
    if (tocRule == null) return [];

    try {
      final response = await _dio.get(bookUrl);
      final html = response.data.toString();

      final rule = AnalyzeRule()..setContent(html, baseUrl: bookUrl);

      final chapterList = rule.getStringList(tocRule.chapterList ?? '');
      final nameList = rule.getStringList(tocRule.chapterName ?? '');
      final urlList = rule.getStringList(tocRule.chapterUrl ?? '');

      final chapters = <Chapter>[];

      for (int i = 0; i < nameList.length; i++) {
        chapters.add(Chapter(
          id: '${bookUrl}_$i',
          bookId: bookUrl,
          title: nameList[i],
          index: i,
          url: i < urlList.length ? urlList[i] : null,
        ));
      }

      return chapters;
    } catch (e) {
      return [];
    }
  }

  Future<String?> getContent(String bookUrl, Chapter chapter) async {
    final contentRule = source.ruleContent;
    if (contentRule == null) return null;

    final chapterUrl = chapter.url ?? bookUrl;

    try {
      final response = await _dio.get(chapterUrl);
      final html = response.data.toString();

      final rule = AnalyzeRule()..setContent(html, baseUrl: chapterUrl);
      return rule.getString(contentRule.content ?? '');
    } catch (e) {
      return null;
    }
  }

  Future<List<Map<String, dynamic>>> exploreBook(String exploreUrl) async {
    final exploreRule = source.ruleExplore;
    if (exploreRule == null) return [];

    try {
      final response = await _dio.get(exploreUrl);
      final html = response.data.toString();

      final rule = AnalyzeRule()..setContent(html, baseUrl: source.bookSourceUrl);

      final bookList = rule.getStringList(exploreRule.bookList ?? '');
      final nameList = rule.getStringList(exploreRule.name ?? '');
      final authorList = rule.getStringList(exploreRule.author ?? '');
      final coverList = rule.getStringList(exploreRule.coverUrl ?? '');
      final introList = rule.getStringList(exploreRule.intro ?? '');
      final bookUrlList = rule.getStringList(exploreRule.bookUrl ?? '');

      final results = <Map<String, dynamic>>[];

      for (int i = 0; i < nameList.length; i++) {
        results.add({
          'name': nameList[i],
          'author': i < authorList.length ? authorList[i] : '',
          'coverUrl': i < coverList.length ? coverList[i] : '',
          'intro': i < introList.length ? introList[i] : '',
          'bookUrl': i < bookUrlList.length ? bookUrlList[i] : '',
          'sourceUrl': source.bookSourceUrl,
          'sourceName': source.bookSourceName,
        });
      }

      return results;
    } catch (e) {
      return [];
    }
  }
}

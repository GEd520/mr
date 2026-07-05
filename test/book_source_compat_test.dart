import 'package:mr/models/book_source.dart';
import 'package:mr/models/book.dart';
import 'package:mr/services/book_data_provider.dart';
import 'package:mr/services/book_source_import_service.dart';
import 'package:mr/services/book_source_locator.dart';
import 'package:mr/services/source_engine/analyze_url.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AnalyzeUrl', () {
    test('parses legado page rules, variables, options and relative URLs', () {
      final parsed = AnalyzeUrl.parse(
        'search/<1,2,3>?q={{key}}, {"method":"POST","body":{"page":"{{page}}"}}',
        baseUrl: 'https://example.com/root/',
        keyword: '三体',
        page: 4,
      );

      expect(
          parsed.url, 'https://example.com/root/search/3?q=%E4%B8%89%E4%BD%93');
      expect(parsed.option?.method, 'POST');
      expect(parsed.option?.body, '{"page":"4"}');
    });

    test('preserves JSON option with JS expression in body (QQ reading style)',
        () {
      final parsed = AnalyzeUrl.parse(
        'https://novel.html5.qq.com/be-api/content/ads-read,{'
        '"method":"POST",'
        '"body":{"Scene":"chapter","ContentAnchorBatch":[{"BookID":"{{page+1}}","ChapterSeqNo":[{{page}}]}]},'
        '"headers":{"QG-UID":"test"}}',
        page: 5,
      );

      // 验证 JSON 配置选项没有被截断/丢失
      expect(parsed.url, 'https://novel.html5.qq.com/be-api/content/ads-read');
      expect(parsed.option?.method, 'POST');
      expect(parsed.option?.body, isNotNull);
      // {{page}} 是固定变量，不需要 JsEngine，应被替换为 5
      expect(parsed.option!.body!, contains('"ChapterSeqNo":[5]'));
      expect(parsed.option?.headers?['QG-UID'], 'test');
    });

    test('preserves {{\$.jsonPath}} expressions without replacing them', () {
      // 直接测试 replaceVariables，不经过 parse（避免 jsonDecode 失败）
      // 因为 {{$.serialID}} 保留后不是合法 JSON 值，jsonDecode 会失败
      // 这是预期行为：{{$.xxx}} 应由上游 AnalyzeRule 在有 content 上下文时替换
      const input = r'{"body":{"id":{{$.serialID}}}}';
      final result = AnalyzeUrl.replaceVariables(input);

      // JSONPath 表达式应保留原样，不被当 JS 执行替换为空
      expect(result, contains(r'{{$.serialID}}'));
    });

    // [回归测试] 验证 JS 输出的 url,{headers} 格式被正确解析
    // 场景：全本小说书源 JS 返回 /?c=book&...,{\"headers\":{\"Referer\":\"...\"}}
    test('parses JS output url with headers option (quanben style)', () {
      final jsOutput =
          '/?c=book&a=search.json&callback=search&t=1783250564438'
          '&keywords=我的&b=y%25NPr1IPyc,'
          '{"headers":{"Referer":"https://quanben-xiaoshuo.com/search.html"}}';
      final parsed = AnalyzeUrl.parse(
        jsOutput,
        baseUrl: 'https://www.quanben5.com',
      );

      // URL 部分应分离出来，不含 ,{...}
      expect(parsed.url,
          'https://www.quanben5.com/?c=book&a=search.json&callback=search&t=1783250564438&keywords=%E6%88%91%E7%9A%84&b=y%25NPr1IPyc');
      // option.headers 应被正确解析
      expect(parsed.option, isNotNull);
      expect(parsed.option!.headers, isNotNull);
      expect(parsed.option!.headers!['Referer'],
          'https://quanben-xiaoshuo.com/search.html');
    });
  });

  group('BookSource import compatibility', () {
    test('restores nested rules from Hive-style dynamic maps', () {
      final source = BookSource.fromJson(<String, dynamic>{
        'bookSourceUrl': 'https://a.example',
        'bookSourceName': 'A',
        'ruleSearch': <dynamic, dynamic>{
          'bookList': '.book',
          'name': '.name@text',
        },
      });

      expect(source.ruleSearch?.bookList, '.book');
      expect(source.ruleSearch?.name, '.name@text');
    });

    test('parses sourceUrls recursively and deduplicates by source URL',
        () async {
      final responses = <String, String>{
        'https://example.com/a.json':
            '[{"bookSourceUrl":"https://a.example","bookSourceName":"A"}]',
        'https://example.com/b.json':
            '{"bookSourceUrl":"https://a.example","bookSourceName":"A2"}',
      };
      final service = BookSourceImportService(
        fetchText: (url, withoutUserAgent) async => responses[url]!,
      );

      final sources = await service.parseText(
        '{"sourceUrls":["https://example.com/a.json","https://example.com/b.json"]}',
      );

      expect(sources, hasLength(1));
      expect(sources.single.bookSourceName, 'A2');
    });

    test('accepts string encoded numeric and boolean fields', () async {
      final service = BookSourceImportService();
      final sources = await service.parseText(
        '{"bookSourceUrl":"https://a.example","bookSourceName":"A",'
        '"bookSourceType":"2","enabled":"false","weight":"9"}',
      );

      expect(sources.single.bookSourceType, BookSourceType.image);
      expect(sources.single.enabled, isFalse);
      expect(sources.single.weight, 9);
    });
  });

  test('locates sources by bookUrlPattern and orders by weight', () {
    const low = BookSource(
      bookSourceUrl: 'https://fallback.example',
      bookSourceName: 'low',
      bookUrlPattern: r'https://books\.example/\d+',
      weight: 1,
    );
    const high = BookSource(
      bookSourceUrl: 'https://other.example',
      bookSourceName: 'high',
      bookUrlPattern: r'https://books\.example/\d+',
      weight: 10,
    );

    final matches = BookSourceLocator.locate(
      'https://books.example/123, {"headers":{"x":"y"}}',
      const [low, high],
    );

    expect(matches.map((source) => source.bookSourceName), ['high', 'low']);
  });

  test('merges detail metadata without discarding search result fields', () {
    final searchBook = Book(
      bookUrl: 'https://books.example/1',
      name: '搜索书名',
      author: '搜索作者',
      coverUrl: 'https://img.example/cover.jpg',
      intro: '搜索简介',
      mediaType: MediaType.novel,
      originType: BookOriginType.online,
      sourceUrl: 'https://source.example',
      sourceName: '测试书源',
      kind: '玄幻 都市',
      lastChapter: '第一百章',
      wordCount: '120万',
      addedTime: DateTime(2026),
    );
    final detailBook = Book(
      bookUrl: searchBook.bookUrl,
      name: '详情书名',
      author: '',
      mediaType: MediaType.novel,
      originType: BookOriginType.online,
      sourceUrl: searchBook.sourceUrl,
      tocUrl: 'https://books.example/1/chapters',
      addedTime: DateTime(2026),
    );

    final merged = mergeBookMetadata(detailBook, searchBook);

    expect(merged.name, '详情书名');
    expect(merged.author, '搜索作者');
    expect(merged.coverUrl, searchBook.coverUrl);
    expect(merged.intro, searchBook.intro);
    expect(merged.lastChapter, searchBook.lastChapter);
    expect(merged.wordCount, searchBook.wordCount);
    expect(merged.tags, ['玄幻', '都市']);
    expect(merged.tocUrl, detailBook.tocUrl);
    expect(createBookDataProvider(merged), isA<OnlineBookDataProvider>());
  });
}

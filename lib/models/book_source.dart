import 'rules/search_rule.dart';
import 'rules/explore_rule.dart';
import 'rules/book_info_rule.dart';
import 'rules/toc_rule.dart';
import 'rules/content_rule.dart';

enum BookSourceType { text, audio, image, file, video }

class BookSource {
  final String bookSourceUrl;
  final String bookSourceName;
  final String? bookSourceGroup;
  final BookSourceType bookSourceType;
  final String? bookUrlPattern;
  final int customOrder;
  final bool enabled;
  final bool enabledExplore;
  final String? jsLib;
  final bool enabledCookieJar;
  final String? concurrentRate;
  final String? header;
  final String? loginUrl;
  final String? loginUi;
  final String? loginCheckJs;
  final String? coverDecodeJs;
  final String? bookSourceComment;
  final String? variableComment;
  final int lastUpdateTime;
  final int respondTime;
  final int weight;
  final String? searchUrl;
  final String? exploreUrl;
  final SearchRule? ruleSearch;
  final ExploreRule? ruleExplore;
  final BookInfoRule? ruleBookInfo;
  final TocRule? ruleToc;
  final ContentRule? ruleContent;

  const BookSource({
    required this.bookSourceUrl,
    required this.bookSourceName,
    this.bookSourceGroup,
    this.bookSourceType = BookSourceType.text,
    this.bookUrlPattern,
    this.customOrder = 0,
    this.enabled = true,
    this.enabledExplore = true,
    this.jsLib,
    this.enabledCookieJar = true,
    this.concurrentRate,
    this.header,
    this.loginUrl,
    this.loginUi,
    this.loginCheckJs,
    this.coverDecodeJs,
    this.bookSourceComment,
    this.variableComment,
    this.lastUpdateTime = 0,
    this.respondTime = 180000,
    this.weight = 0,
    this.searchUrl,
    this.exploreUrl,
    this.ruleSearch,
    this.ruleExplore,
    this.ruleBookInfo,
    this.ruleToc,
    this.ruleContent,
  });

  BookSource copyWith({
    String? bookSourceUrl,
    String? bookSourceName,
    String? bookSourceGroup,
    BookSourceType? bookSourceType,
    String? bookUrlPattern,
    int? customOrder,
    bool? enabled,
    bool? enabledExplore,
    String? jsLib,
    bool? enabledCookieJar,
    String? concurrentRate,
    String? header,
    String? loginUrl,
    String? loginUi,
    String? loginCheckJs,
    String? coverDecodeJs,
    String? bookSourceComment,
    String? variableComment,
    int? lastUpdateTime,
    int? respondTime,
    int? weight,
    String? searchUrl,
    String? exploreUrl,
    SearchRule? ruleSearch,
    ExploreRule? ruleExplore,
    BookInfoRule? ruleBookInfo,
    TocRule? ruleToc,
    ContentRule? ruleContent,
  }) {
    return BookSource(
      bookSourceUrl: bookSourceUrl ?? this.bookSourceUrl,
      bookSourceName: bookSourceName ?? this.bookSourceName,
      bookSourceGroup: bookSourceGroup ?? this.bookSourceGroup,
      bookSourceType: bookSourceType ?? this.bookSourceType,
      bookUrlPattern: bookUrlPattern ?? this.bookUrlPattern,
      customOrder: customOrder ?? this.customOrder,
      enabled: enabled ?? this.enabled,
      enabledExplore: enabledExplore ?? this.enabledExplore,
      jsLib: jsLib ?? this.jsLib,
      enabledCookieJar: enabledCookieJar ?? this.enabledCookieJar,
      concurrentRate: concurrentRate ?? this.concurrentRate,
      header: header ?? this.header,
      loginUrl: loginUrl ?? this.loginUrl,
      loginUi: loginUi ?? this.loginUi,
      loginCheckJs: loginCheckJs ?? this.loginCheckJs,
      coverDecodeJs: coverDecodeJs ?? this.coverDecodeJs,
      bookSourceComment: bookSourceComment ?? this.bookSourceComment,
      variableComment: variableComment ?? this.variableComment,
      lastUpdateTime: lastUpdateTime ?? this.lastUpdateTime,
      respondTime: respondTime ?? this.respondTime,
      weight: weight ?? this.weight,
      searchUrl: searchUrl ?? this.searchUrl,
      exploreUrl: exploreUrl ?? this.exploreUrl,
      ruleSearch: ruleSearch ?? this.ruleSearch,
      ruleExplore: ruleExplore ?? this.ruleExplore,
      ruleBookInfo: ruleBookInfo ?? this.ruleBookInfo,
      ruleToc: ruleToc ?? this.ruleToc,
      ruleContent: ruleContent ?? this.ruleContent,
    );
  }

  factory BookSource.fromJson(Map<String, dynamic> json) {
    return BookSource(
      bookSourceUrl: json['bookSourceUrl'] as String? ?? '',
      bookSourceName: json['bookSourceName'] as String? ?? '',
      bookSourceGroup: json['bookSourceGroup'] as String?,
      bookSourceType: BookSourceType.values[json['bookSourceType'] as int? ?? 0],
      bookUrlPattern: json['bookUrlPattern'] as String?,
      customOrder: json['customOrder'] as int? ?? 0,
      enabled: json['enabled'] as bool? ?? true,
      enabledExplore: json['enabledExplore'] as bool? ?? true,
      jsLib: json['jsLib'] as String?,
      enabledCookieJar: json['enabledCookieJar'] as bool? ?? true,
      concurrentRate: json['concurrentRate'] as String?,
      header: json['header'] as String?,
      loginUrl: json['loginUrl'] as String?,
      loginUi: json['loginUi'] as String?,
      loginCheckJs: json['loginCheckJs'] as String?,
      coverDecodeJs: json['coverDecodeJs'] as String?,
      bookSourceComment: json['bookSourceComment'] as String?,
      variableComment: json['variableComment'] as String?,
      lastUpdateTime: json['lastUpdateTime'] as int? ?? 0,
      respondTime: json['respondTime'] as int? ?? 180000,
      weight: json['weight'] as int? ?? 0,
      searchUrl: json['searchUrl'] as String?,
      exploreUrl: json['exploreUrl'] as String?,
      ruleSearch: json['ruleSearch'] != null
          ? SearchRule.fromJson(json['ruleSearch'] as Map<String, dynamic>)
          : null,
      ruleExplore: json['ruleExplore'] != null
          ? ExploreRule.fromJson(json['ruleExplore'] as Map<String, dynamic>)
          : null,
      ruleBookInfo: json['ruleBookInfo'] != null
          ? BookInfoRule.fromJson(json['ruleBookInfo'] as Map<String, dynamic>)
          : null,
      ruleToc: json['ruleToc'] != null
          ? TocRule.fromJson(json['ruleToc'] as Map<String, dynamic>)
          : null,
      ruleContent: json['ruleContent'] != null
          ? ContentRule.fromJson(json['ruleContent'] as Map<String, dynamic>)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'bookSourceUrl': bookSourceUrl,
      'bookSourceName': bookSourceName,
      if (bookSourceGroup != null) 'bookSourceGroup': bookSourceGroup,
      'bookSourceType': bookSourceType.index,
      if (bookUrlPattern != null) 'bookUrlPattern': bookUrlPattern,
      'customOrder': customOrder,
      'enabled': enabled,
      'enabledExplore': enabledExplore,
      if (jsLib != null) 'jsLib': jsLib,
      'enabledCookieJar': enabledCookieJar,
      if (concurrentRate != null) 'concurrentRate': concurrentRate,
      if (header != null) 'header': header,
      if (loginUrl != null) 'loginUrl': loginUrl,
      if (loginUi != null) 'loginUi': loginUi,
      if (loginCheckJs != null) 'loginCheckJs': loginCheckJs,
      if (coverDecodeJs != null) 'coverDecodeJs': coverDecodeJs,
      if (bookSourceComment != null) 'bookSourceComment': bookSourceComment,
      if (variableComment != null) 'variableComment': variableComment,
      'lastUpdateTime': lastUpdateTime,
      'respondTime': respondTime,
      'weight': weight,
      if (searchUrl != null) 'searchUrl': searchUrl,
      if (exploreUrl != null) 'exploreUrl': exploreUrl,
      if (ruleSearch != null) 'ruleSearch': ruleSearch!.toJson(),
      if (ruleExplore != null) 'ruleExplore': ruleExplore!.toJson(),
      if (ruleBookInfo != null) 'ruleBookInfo': ruleBookInfo!.toJson(),
      if (ruleToc != null) 'ruleToc': ruleToc!.toJson(),
      if (ruleContent != null) 'ruleContent': ruleContent!.toJson(),
    };
  }

  String get typeName {
    switch (bookSourceType) {
      case BookSourceType.text:
        return '小说';
      case BookSourceType.audio:
        return '音频';
      case BookSourceType.image:
        return '漫画';
      case BookSourceType.file:
        return '文件';
      case BookSourceType.video:
        return '视频';
    }
  }
}

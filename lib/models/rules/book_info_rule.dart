class BookInfoRule {
  final String? init;
  final String? name;
  final String? author;
  final String? intro;
  final String? kind;
  final String? lastChapter;
  final String? updateTime;
  final String? coverUrl;
  final String? tocUrl;
  final String? wordCount;
  final String? canReName;
  final String? downloadUrls;

  const BookInfoRule({
    this.init,
    this.name,
    this.author,
    this.intro,
    this.kind,
    this.lastChapter,
    this.updateTime,
    this.coverUrl,
    this.tocUrl,
    this.wordCount,
    this.canReName,
    this.downloadUrls,
  });

  factory BookInfoRule.fromJson(Map<String, dynamic> json) {
    return BookInfoRule(
      init: json['init'] as String?,
      name: json['name'] as String?,
      author: json['author'] as String?,
      intro: json['intro'] as String?,
      kind: json['kind'] as String?,
      lastChapter: json['lastChapter'] as String?,
      updateTime: json['updateTime'] as String?,
      coverUrl: json['coverUrl'] as String?,
      tocUrl: json['tocUrl'] as String?,
      wordCount: json['wordCount'] as String?,
      canReName: json['canReName'] as String?,
      downloadUrls: json['downloadUrls'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (init != null) 'init': init,
      if (name != null) 'name': name,
      if (author != null) 'author': author,
      if (intro != null) 'intro': intro,
      if (kind != null) 'kind': kind,
      if (lastChapter != null) 'lastChapter': lastChapter,
      if (updateTime != null) 'updateTime': updateTime,
      if (coverUrl != null) 'coverUrl': coverUrl,
      if (tocUrl != null) 'tocUrl': tocUrl,
      if (wordCount != null) 'wordCount': wordCount,
      if (canReName != null) 'canReName': canReName,
      if (downloadUrls != null) 'downloadUrls': downloadUrls,
    };
  }
}

class ExploreRule {
  final String? bookList;
  final String? name;
  final String? author;
  final String? intro;
  final String? kind;
  final String? lastChapter;
  final String? updateTime;
  final String? bookUrl;
  final String? coverUrl;
  final String? wordCount;

  const ExploreRule({
    this.bookList,
    this.name,
    this.author,
    this.intro,
    this.kind,
    this.lastChapter,
    this.updateTime,
    this.bookUrl,
    this.coverUrl,
    this.wordCount,
  });

  factory ExploreRule.fromJson(Map<String, dynamic> json) {
    return ExploreRule(
      bookList: json['bookList'] as String?,
      name: json['name'] as String?,
      author: json['author'] as String?,
      intro: json['intro'] as String?,
      kind: json['kind'] as String?,
      lastChapter: json['lastChapter'] as String?,
      updateTime: json['updateTime'] as String?,
      bookUrl: json['bookUrl'] as String?,
      coverUrl: json['coverUrl'] as String?,
      wordCount: json['wordCount'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (bookList != null) 'bookList': bookList,
      if (name != null) 'name': name,
      if (author != null) 'author': author,
      if (intro != null) 'intro': intro,
      if (kind != null) 'kind': kind,
      if (lastChapter != null) 'lastChapter': lastChapter,
      if (updateTime != null) 'updateTime': updateTime,
      if (bookUrl != null) 'bookUrl': bookUrl,
      if (coverUrl != null) 'coverUrl': coverUrl,
      if (wordCount != null) 'wordCount': wordCount,
    };
  }
}

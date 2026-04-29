class TocRule {
  final String? preUpdateJs;
  final String? chapterList;
  final String? chapterName;
  final String? chapterUrl;
  final String? formatJs;
  final String? isVolume;
  final String? isVip;
  final String? isPay;
  final String? updateTime;
  final String? nextTocUrl;

  const TocRule({
    this.preUpdateJs,
    this.chapterList,
    this.chapterName,
    this.chapterUrl,
    this.formatJs,
    this.isVolume,
    this.isVip,
    this.isPay,
    this.updateTime,
    this.nextTocUrl,
  });

  factory TocRule.fromJson(Map<String, dynamic> json) {
    return TocRule(
      preUpdateJs: json['preUpdateJs'] as String?,
      chapterList: json['chapterList'] as String?,
      chapterName: json['chapterName'] as String?,
      chapterUrl: json['chapterUrl'] as String?,
      formatJs: json['formatJs'] as String?,
      isVolume: json['isVolume'] as String?,
      isVip: json['isVip'] as String?,
      isPay: json['isPay'] as String?,
      updateTime: json['updateTime'] as String?,
      nextTocUrl: json['nextTocUrl'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (preUpdateJs != null) 'preUpdateJs': preUpdateJs,
      if (chapterList != null) 'chapterList': chapterList,
      if (chapterName != null) 'chapterName': chapterName,
      if (chapterUrl != null) 'chapterUrl': chapterUrl,
      if (formatJs != null) 'formatJs': formatJs,
      if (isVolume != null) 'isVolume': isVolume,
      if (isVip != null) 'isVip': isVip,
      if (isPay != null) 'isPay': isPay,
      if (updateTime != null) 'updateTime': updateTime,
      if (nextTocUrl != null) 'nextTocUrl': nextTocUrl,
    };
  }
}

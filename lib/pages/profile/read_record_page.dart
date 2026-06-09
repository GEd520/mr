import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../routes/app_routes.dart';
import '../../services/read_record_service.dart';

enum DisplayMode { aggregate, timeline, latest, readTime }

class ReadRecordPage extends StatefulWidget {
  final String? bookUrl;

  const ReadRecordPage({super.key, this.bookUrl});

  @override
  State<ReadRecordPage> createState() => _ReadRecordPageState();
}

class _ReadRecordPageState extends State<ReadRecordPage> {
  final _searchController = TextEditingController();
  final _service = ReadRecordService.instance;

  List<ReadRecord> _records = const [];
  List<ReadRecordSummary> _summaries = const [];
  final Set<String> _selectedBooks = {};
  bool _isLoading = true;
  bool _showSearch = false;
  bool _skipDeleteConfirmation = false;
  String _searchKeyword = '';
  int _totalReadTime = 0;
  DisplayMode _displayMode = DisplayMode.aggregate;
  DateTime? _selectedDate;

  bool get _isSelectionMode => _selectedBooks.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _loadRecords();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadRecords() async {
    if (mounted) setState(() => _isLoading = true);
    final results = await Future.wait<Object>([
      _service.getAllRecords(),
      _service.getSummaryRecords(),
      _service.getTotalReadTime(),
    ]);
    if (!mounted) return;
    setState(() {
      _records = results[0] as List<ReadRecord>;
      _summaries = results[1] as List<ReadRecordSummary>;
      _totalReadTime = results[2] as int;
      _selectedBooks.removeWhere(
        (key) => !_summaries.any((record) => _bookKey(record) == key),
      );
      _isLoading = false;
    });
  }

  String _bookKey(Object record) {
    return switch (record) {
      ReadRecord r => '${r.bookName}\u0000${r.bookAuthor}',
      ReadRecordSummary r => '${r.bookName}\u0000${r.bookAuthor}',
      _ => throw ArgumentError('Unsupported record type'),
    };
  }

  String get _displayModeName => switch (_displayMode) {
    DisplayMode.aggregate => '聚合视图',
    DisplayMode.timeline => '时间线',
    DisplayMode.latest => '最近阅读',
    DisplayMode.readTime => '阅读时长',
  };

  IconData get _displayModeIcon => switch (_displayMode) {
    DisplayMode.aggregate => Icons.timeline,
    DisplayMode.timeline => Icons.list_alt,
    DisplayMode.latest => Icons.auto_awesome,
    DisplayMode.readTime => Icons.schedule,
  };

  void _toggleDisplayMode() {
    setState(() {
      _displayMode = DisplayMode
          .values[(_displayMode.index + 1) % DisplayMode.values.length];
      _selectedBooks.clear();
    });
  }

  void _toggleSelection(Object record) {
    final key = _bookKey(record);
    setState(() {
      if (!_selectedBooks.add(key)) _selectedBooks.remove(key);
    });
  }

  void _selectAllVisible() {
    setState(() {
      _selectedBooks.addAll(_visibleBookKeys());
    });
  }

  Set<String> _visibleBookKeys() {
    if (_displayMode == DisplayMode.timeline) {
      return _filteredRecords.map(_bookKey).toSet();
    }
    return _filteredSummaries.map(_bookKey).toSet();
  }

  bool _matchesSearch(String name, String author) {
    if (_searchKeyword.isEmpty) return true;
    return name.toLowerCase().contains(_searchKeyword) ||
        author.toLowerCase().contains(_searchKeyword);
  }

  bool _matchesSelectedDate(int timestamp) {
    if (_selectedDate == null) return true;
    final date = _dateFromSeconds(timestamp);
    return _sameDay(date, _selectedDate!);
  }

  List<ReadRecord> get _filteredRecords {
    return _records.where((record) {
      return _matchesSearch(record.bookName, record.bookAuthor) &&
          _matchesSelectedDate(record.startTime);
    }).toList();
  }

  List<ReadRecordSummary> get _filteredSummaries {
    final source = _selectedDate == null
        ? _summaries
        : _summariesForRecords(_filteredRecords);
    return source.where((record) {
      return _matchesSearch(record.bookName, record.bookAuthor);
    }).toList();
  }

  List<ReadRecordSummary> _summariesForRecords(List<ReadRecord> records) {
    final grouped = <String, List<ReadRecord>>{};
    for (final record in records) {
      grouped.putIfAbsent(_bookKey(record), () => []).add(record);
    }
    return grouped.values.map((items) {
      items.sort((a, b) => b.endTime.compareTo(a.endTime));
      final latest = items.first;
      return ReadRecordSummary(
        bookUrl: latest.bookUrl,
        bookName: latest.bookName,
        bookAuthor: latest.bookAuthor,
        coverUrl: latest.coverUrl,
        totalReadTime: items.fold(0, (sum, item) => sum + item.readTime),
        firstReadTime: items.map((item) => item.startTime).reduce(math.min),
        lastReadTime: items.map((item) => item.endTime).reduce(math.max),
        readCount: items.length,
        lastChapterIndex: latest.chapterIndex,
        lastChapterTitle: latest.chapterTitle,
      );
    }).toList()..sort((a, b) => b.lastReadTime.compareTo(a.lastReadTime));
  }

  Future<bool> _confirmDelete({required String message}) async {
    if (_skipDeleteConfirmation) return true;
    var skipNextTime = _skipDeleteConfirmation;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('确认删除'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(message),
              const SizedBox(height: 8),
              CheckboxListTile(
                value: skipNextTime,
                onChanged: (value) {
                  setDialogState(() => skipNextTime = value ?? false);
                },
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: const Text('本次使用期间不再提示'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(
                '删除',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          ],
        ),
      ),
    );
    if (confirmed == true) {
      _skipDeleteConfirmation = skipNextTime;
      return true;
    }
    return false;
  }

  Future<void> _deleteSummary(ReadRecordSummary record) async {
    if (!await _confirmDelete(message: '确定删除《${record.bookName}》的全部阅读记录吗？')) {
      return;
    }
    await _service.deleteRecordsByBook(record.bookName, record.bookAuthor);
    await _loadRecords();
  }

  Future<void> _deleteSession(ReadRecord record) async {
    if (!await _confirmDelete(message: '确定删除这次阅读记录吗？')) return;
    await _service.deleteRecord(record.id);
    await _loadRecords();
  }

  Future<void> _deleteSelected() async {
    final count = _selectedBooks.length;
    if (count == 0 ||
        !await _confirmDelete(message: '确定删除选中的 $count 本书的全部阅读记录吗？')) {
      return;
    }
    final targets = _summaries
        .where((record) => _selectedBooks.contains(_bookKey(record)))
        .toList();
    for (final record in targets) {
      await _service.deleteRecordsByBook(record.bookName, record.bookAuthor);
    }
    _selectedBooks.clear();
    await _loadRecords();
  }

  Future<void> _clearAllRecords() async {
    if (_records.isEmpty ||
        !await _confirmDelete(message: '确定清空全部阅读记录吗？此操作无法撤销。')) {
      return;
    }
    await _service.clearAllRecords();
    await _loadRecords();
  }

  void _openBook(String bookUrl) {
    if (bookUrl.isEmpty) return;
    Navigator.pushNamed(
      context,
      AppRoutes.detail,
      arguments: {'bookUrl': bookUrl},
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _buildAppBar(),
      body: Column(
        children: [
          AnimatedSize(
            duration: const Duration(milliseconds: 180),
            child: _showSearch ? _buildSearchField() : const SizedBox.shrink(),
          ),
          if (_selectedDate != null) _buildDateFilter(),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _buildBody(),
          ),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    if (_isSelectionMode) {
      return AppBar(
        leading: IconButton(
          onPressed: () => setState(_selectedBooks.clear),
          icon: const Icon(Icons.close),
          tooltip: '取消选择',
        ),
        title: Text('已选择 ${_selectedBooks.length} 项'),
        actions: [
          IconButton(
            onPressed: _selectAllVisible,
            icon: const Icon(Icons.select_all),
            tooltip: '全选',
          ),
          IconButton(
            onPressed: _deleteSelected,
            icon: const Icon(Icons.delete_outline),
            tooltip: '删除所选',
          ),
        ],
      );
    }

    return AppBar(
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('阅读记录'),
          Text(
            _displayModeName,
            style: Theme.of(context).textTheme.labelMedium,
          ),
        ],
      ),
      actions: [
        IconButton(
          onPressed: () {
            setState(() {
              _showSearch = !_showSearch;
              if (!_showSearch) {
                _searchController.clear();
                _searchKeyword = '';
              }
            });
          },
          icon: const Icon(Icons.search),
          tooltip: '搜索',
        ),
        IconButton(
          onPressed: _showHeatmap,
          icon: const Icon(Icons.calendar_month_outlined),
          tooltip: '阅读日历',
        ),
        IconButton(
          onPressed: _toggleDisplayMode,
          icon: Icon(_displayModeIcon),
          tooltip: '切换视图',
        ),
        PopupMenuButton<String>(
          onSelected: (value) {
            if (value == 'clear') _clearAllRecords();
          },
          itemBuilder: (context) => const [
            PopupMenuItem(
              value: 'clear',
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.delete_sweep_outlined),
                title: Text('清空全部记录'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSearchField() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: TextField(
        controller: _searchController,
        autofocus: true,
        maxLines: 1,
        decoration: InputDecoration(
          hintText: '搜索书名或作者',
          prefixIcon: const Icon(Icons.search),
          suffixIcon: _searchKeyword.isEmpty
              ? null
              : IconButton(
                  onPressed: () {
                    _searchController.clear();
                    setState(() => _searchKeyword = '');
                  },
                  icon: const Icon(Icons.clear),
                  tooltip: '清除',
                ),
          border: const OutlineInputBorder(),
        ),
        onChanged: (value) {
          setState(() => _searchKeyword = value.trim().toLowerCase());
        },
      ),
    );
  }

  Widget _buildDateFilter() {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.only(left: 12),
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(Icons.event, size: 18, color: colorScheme.onPrimaryContainer),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '正在查看 ${_formatFullDate(_selectedDate!)}',
              style: TextStyle(color: colorScheme.onPrimaryContainer),
            ),
          ),
          IconButton(
            onPressed: () => setState(() => _selectedDate = null),
            icon: const Icon(Icons.close),
            tooltip: '清除日期筛选',
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    final hasVisibleRecords = _displayMode == DisplayMode.timeline
        ? _filteredRecords.isNotEmpty
        : _filteredSummaries.isNotEmpty;
    if (!hasVisibleRecords) return _buildEmptyState();

    return RefreshIndicator(
      onRefresh: _loadRecords,
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(child: _buildSummaryCard()),
          ..._buildContentSlivers(),
          const SliverPadding(padding: EdgeInsets.only(bottom: 16)),
        ],
      ),
    );
  }

  List<Widget> _buildContentSlivers() {
    return switch (_displayMode) {
      DisplayMode.aggregate => _buildAggregateSlivers(),
      DisplayMode.timeline => _buildTimelineSlivers(),
      DisplayMode.latest => [
        _buildSummaryListSliver(
          _filteredSummaries
            ..sort((a, b) => b.lastReadTime.compareTo(a.lastReadTime)),
        ),
      ],
      DisplayMode.readTime => [
        _buildSummaryListSliver(
          _filteredSummaries
            ..sort((a, b) => b.totalReadTime.compareTo(a.totalReadTime)),
          showReadTime: true,
        ),
      ],
    };
  }

  List<Widget> _buildAggregateSlivers() {
    final records = [..._filteredRecords]
      ..sort((a, b) => b.endTime.compareTo(a.endTime));
    final grouped = <DateTime, List<ReadRecord>>{};
    for (final record in records) {
      final date = _day(_dateFromSeconds(record.endTime));
      grouped.putIfAbsent(date, () => []).add(record);
    }
    final dates = grouped.keys.toList()..sort((a, b) => b.compareTo(a));
    return [
      for (final date in dates) ...[
        SliverToBoxAdapter(
          child: _DateHeader(
            title: _formatFriendlyDate(date),
            duration: grouped[date]!.fold(
              0,
              (sum, item) => sum + item.readTime,
            ),
          ),
        ),
        SliverList.builder(
          itemCount: _summariesForRecords(grouped[date]!).length,
          itemBuilder: (context, index) {
            final item = _summariesForRecords(grouped[date]!)[index];
            return _buildSummaryItem(item);
          },
        ),
      ],
    ];
  }

  List<Widget> _buildTimelineSlivers() {
    final grouped = <DateTime, List<ReadRecord>>{};
    for (final record in _filteredRecords) {
      final date = _day(_dateFromSeconds(record.startTime));
      grouped.putIfAbsent(date, () => []).add(record);
    }
    final dates = grouped.keys.toList()..sort((a, b) => b.compareTo(a));
    return [
      for (final date in dates) ...[
        SliverToBoxAdapter(
          child: _DateHeader(
            title: _formatFriendlyDate(date),
            duration: grouped[date]!.fold(
              0,
              (sum, item) => sum + item.readTime,
            ),
          ),
        ),
        SliverList.builder(
          itemCount: grouped[date]!.length,
          itemBuilder: (context, index) {
            return _buildTimelineItem(grouped[date]![index]);
          },
        ),
      ],
    ];
  }

  Widget _buildSummaryListSliver(
    List<ReadRecordSummary> records, {
    bool showReadTime = false,
  }) {
    return SliverList.builder(
      itemCount: records.length,
      itemBuilder: (context, index) {
        return _buildSummaryItem(records[index], showReadTime: showReadTime);
      },
    );
  }

  Widget _buildSummaryCard() {
    final colorScheme = Theme.of(context).colorScheme;
    final latest = _filteredSummaries.take(3).toList();
    final visibleReadTime = _selectedDate == null
        ? _totalReadTime
        : _filteredRecords.fold(0, (sum, item) => sum + item.readTime);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colorScheme.outlineVariant),
        boxShadow: [
          BoxShadow(
            color: colorScheme.shadow.withValues(alpha: 0.08),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _selectedDate == null
                      ? '累计阅读成就'
                      : _formatFullDate(_selectedDate!),
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 8),
                Text.rich(
                  TextSpan(
                    children: [
                      const TextSpan(text: '已读 '),
                      TextSpan(
                        text: '${_filteredSummaries.length}',
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: colorScheme.primary,
                        ),
                      ),
                      const TextSpan(text: ' 本'),
                    ],
                  ),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 4),
                Text(
                  '累计阅读 ${_formatDuration(visibleReadTime)}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          if (latest.isNotEmpty) _BookStack(records: latest),
        ],
      ),
    );
  }

  Widget _buildSummaryItem(
    ReadRecordSummary record, {
    bool showReadTime = false,
  }) {
    final selected = _selectedBooks.contains(_bookKey(record));
    return Dismissible(
      key: ValueKey('summary-${_bookKey(record)}-${_selectedDate ?? ''}'),
      direction: _isSelectionMode
          ? DismissDirection.none
          : DismissDirection.endToStart,
      confirmDismiss: (_) async {
        await _deleteSummary(record);
        return false;
      },
      background: _deleteBackground(),
      child: _RecordCard(
        selected: selected,
        onTap: () {
          if (_isSelectionMode) {
            _toggleSelection(record);
          } else {
            _openBook(record.bookUrl);
          }
        },
        onLongPress: () => _toggleSelection(record),
        coverUrl: record.coverUrl,
        title: record.bookName,
        subtitle: record.bookAuthor.isEmpty ? '未知作者' : record.bookAuthor,
        detail: record.lastChapterTitle.isEmpty
            ? '第 ${record.lastChapterIndex + 1} 章'
            : record.lastChapterTitle,
        footer:
            '${record.readCount} 次 · ${_formatFriendlyDateTime(record.lastReadTime)}',
        trailing: showReadTime
            ? Text(
                _formatDuration(record.totalReadTime),
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
              )
            : null,
        menu: PopupMenuButton<String>(
          onSelected: (value) {
            if (value == 'delete') _deleteSummary(record);
          },
          itemBuilder: (context) => const [
            PopupMenuItem(
              value: 'delete',
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.delete_outline),
                title: Text('删除'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTimelineItem(ReadRecord record) {
    final selected = _selectedBooks.contains(_bookKey(record));
    return Dismissible(
      key: ValueKey('session-${record.id}'),
      direction: _isSelectionMode
          ? DismissDirection.none
          : DismissDirection.endToStart,
      confirmDismiss: (_) async {
        await _deleteSession(record);
        return false;
      },
      background: _deleteBackground(),
      child: _RecordCard(
        selected: selected,
        onTap: () {
          if (_isSelectionMode) {
            _toggleSelection(record);
          } else {
            _openBook(record.bookUrl);
          }
        },
        onLongPress: () => _toggleSelection(record),
        coverUrl: record.coverUrl,
        title: record.bookName,
        subtitle: record.bookAuthor.isEmpty ? '未知作者' : record.bookAuthor,
        detail: record.chapterTitle.isEmpty
            ? '第 ${record.chapterIndex + 1} 章'
            : record.chapterTitle,
        footer:
            '${_formatTime(record.startTime)} - ${_formatTime(record.endTime)} · ${_formatDuration(record.readTime)}',
        menu: PopupMenuButton<String>(
          onSelected: (value) {
            if (value == 'delete') _deleteSession(record);
          },
          itemBuilder: (context) => const [
            PopupMenuItem(
              value: 'delete',
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.delete_outline),
                title: Text('删除本次记录'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _deleteBackground() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: const EdgeInsets.only(right: 20),
      alignment: Alignment.centerRight,
      color: Theme.of(context).colorScheme.error,
      child: Icon(
        Icons.delete_outline,
        color: Theme.of(context).colorScheme.onError,
      ),
    );
  }

  Widget _buildEmptyState() {
    final filtered = _searchKeyword.isNotEmpty || _selectedDate != null;
    return RefreshIndicator(
      onRefresh: _loadRecords,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          SizedBox(height: MediaQuery.sizeOf(context).height * 0.22),
          Icon(
            filtered ? Icons.search_off : Icons.menu_book_outlined,
            size: 64,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 16),
          Text(
            filtered ? '没有符合条件的阅读记录' : '暂无阅读记录',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showHeatmap() async {
    final selected = await showModalBottomSheet<DateTime?>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) =>
          _ReadingCalendarSheet(records: _records, initialDate: _selectedDate),
    );
    if (!mounted) return;
    if (selected != null) {
      setState(() {
        _selectedDate = selected.year == 1 ? null : _day(selected);
        _selectedBooks.clear();
      });
    }
  }

  DateTime _dateFromSeconds(int timestamp) {
    return DateTime.fromMillisecondsSinceEpoch(timestamp * 1000);
  }

  DateTime _day(DateTime date) => DateTime(date.year, date.month, date.day);

  bool _sameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  String _formatDuration(int seconds) {
    if (seconds < 60) return '$seconds 秒';
    final hours = seconds ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;
    if (hours == 0) return '$minutes 分钟';
    return minutes == 0 ? '$hours 小时' : '$hours 小时 $minutes 分钟';
  }

  String _formatFriendlyDate(DateTime date) {
    final today = _day(DateTime.now());
    if (_sameDay(date, today)) return '今天';
    if (_sameDay(date, today.subtract(const Duration(days: 1)))) return '昨天';
    return _formatFullDate(date);
  }

  String _formatFullDate(DateTime date) {
    return '${date.year}年${date.month}月${date.day}日';
  }

  String _formatFriendlyDateTime(int timestamp) {
    final date = _dateFromSeconds(timestamp);
    final dayLabel = _formatFriendlyDate(date);
    if (dayLabel == '今天') return '今天 ${_formatTime(timestamp)}';
    if (dayLabel == '昨天') return '昨天 ${_formatTime(timestamp)}';
    return '${date.month}月${date.day}日';
  }

  String _formatTime(int timestamp) {
    final time = _dateFromSeconds(timestamp);
    return '${time.hour.toString().padLeft(2, '0')}:'
        '${time.minute.toString().padLeft(2, '0')}';
  }
}

class _DateHeader extends StatelessWidget {
  final String title;
  final int duration;

  const _DateHeader({required this.title, required this.duration});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
            ),
          ),
          Text(
            _compactDuration(duration),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  String _compactDuration(int seconds) {
    if (seconds < 60) return '$seconds 秒';
    if (seconds < 3600) return '${seconds ~/ 60} 分钟';
    return '${seconds ~/ 3600} 小时 ${(seconds % 3600) ~/ 60} 分钟';
  }
}

class _RecordCard extends StatelessWidget {
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final String coverUrl;
  final String title;
  final String subtitle;
  final String detail;
  final String footer;
  final Widget? trailing;
  final Widget menu;

  const _RecordCard({
    required this.selected,
    required this.onTap,
    required this.onLongPress,
    required this.coverUrl,
    required this.title,
    required this.subtitle,
    required this.detail,
    required this.footer,
    required this.menu,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: selected
            ? colorScheme.primaryContainer.withValues(alpha: 0.6)
            : colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: selected ? colorScheme.primary : colorScheme.outlineVariant,
          width: selected ? 1.5 : 1,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              _BookCover(url: coverUrl, width: 48, height: 68),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      detail,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      footer,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (trailing != null) ...[const SizedBox(width: 8), trailing!],
              if (selected)
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Icon(Icons.check_circle, color: colorScheme.primary),
                )
              else
                menu,
            ],
          ),
        ),
      ),
    );
  }
}

class _BookCover extends StatelessWidget {
  final String url;
  final double width;
  final double height;

  const _BookCover({
    required this.url,
    required this.width,
    required this.height,
  });

  @override
  Widget build(BuildContext context) {
    final placeholder = Container(
      width: width,
      height: height,
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      alignment: Alignment.center,
      child: Icon(
        Icons.book_outlined,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: url.isEmpty
          ? placeholder
          : CachedNetworkImage(
              imageUrl: url,
              width: width,
              height: height,
              fit: BoxFit.cover,
              placeholder: (_, __) => placeholder,
              errorWidget: (_, __, ___) => placeholder,
            ),
    );
  }
}

class _BookStack extends StatelessWidget {
  final List<ReadRecordSummary> records;

  const _BookStack({required this.records});

  @override
  Widget build(BuildContext context) {
    const width = 48.0;
    const height = 72.0;
    const step = 12.0;
    return SizedBox(
      width: width + step * (records.length - 1),
      height: height,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          for (var index = 0; index < records.length; index++)
            Positioned(
              left: index * step,
              child: Transform.rotate(
                angle: (index.isEven ? 3 : -3) * math.pi / 180,
                child: Material(
                  elevation: 4,
                  borderRadius: BorderRadius.circular(4),
                  clipBehavior: Clip.antiAlias,
                  child: _BookCover(
                    url: records[index].coverUrl,
                    width: width,
                    height: height,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

enum _HeatmapMode { duration, count }

class _ReadingCalendarSheet extends StatefulWidget {
  final List<ReadRecord> records;
  final DateTime? initialDate;

  const _ReadingCalendarSheet({
    required this.records,
    required this.initialDate,
  });

  @override
  State<_ReadingCalendarSheet> createState() => _ReadingCalendarSheetState();
}

class _ReadingCalendarSheetState extends State<_ReadingCalendarSheet> {
  late DateTime _month;
  late DateTime? _selectedDate;
  _HeatmapMode _mode = _HeatmapMode.duration;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialDate ?? DateTime.now();
    _month = DateTime(initial.year, initial.month);
    _selectedDate = widget.initialDate;
  }

  Map<DateTime, List<ReadRecord>> get _dailyRecords {
    final result = <DateTime, List<ReadRecord>>{};
    for (final record in widget.records) {
      final time = DateTime.fromMillisecondsSinceEpoch(record.startTime * 1000);
      final day = DateTime(time.year, time.month, time.day);
      result.putIfAbsent(day, () => []).add(record);
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final daily = _dailyRecords;
    final monthEntries = daily.entries.where(
      (entry) =>
          entry.key.year == _month.year && entry.key.month == _month.month,
    );
    final monthRecords = monthEntries.expand((entry) => entry.value).toList();
    final activeDays = monthEntries.length;
    final totalTime = monthRecords.fold<int>(
      0,
      (sum, record) => sum + record.readTime,
    );
    final maxValue = math.max(
      1,
      daily.entries
          .where(
            (entry) =>
                entry.key.year == _month.year &&
                entry.key.month == _month.month,
          )
          .map((entry) => _valueFor(entry.value))
          .fold<int>(0, math.max),
    );

    return FractionallySizedBox(
      heightFactor: 0.88,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '阅读日历',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        '按日期查看阅读频次和时长',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                SegmentedButton<_HeatmapMode>(
                  segments: const [
                    ButtonSegment(
                      value: _HeatmapMode.duration,
                      icon: Icon(Icons.schedule, size: 18),
                      tooltip: '按时长',
                    ),
                    ButtonSegment(
                      value: _HeatmapMode.count,
                      icon: Icon(Icons.numbers, size: 18),
                      tooltip: '按次数',
                    ),
                  ],
                  selected: {_mode},
                  showSelectedIcon: false,
                  onSelectionChanged: (value) {
                    setState(() => _mode = value.first);
                  },
                ),
              ],
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                IconButton(
                  onPressed: () => setState(() {
                    _month = DateTime(_month.year, _month.month - 1);
                  }),
                  icon: const Icon(Icons.chevron_left),
                  tooltip: '上个月',
                ),
                Expanded(
                  child: Column(
                    children: [
                      Text(
                        '${_month.year}年${_month.month}月',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      Text(
                        _mode == _HeatmapMode.duration ? '按阅读时长' : '按阅读次数',
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => setState(() {
                    _month = DateTime(_month.year, _month.month + 1);
                  }),
                  icon: const Icon(Icons.chevron_right),
                  tooltip: '下个月',
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                _StatTile(label: '阅读', value: '${monthRecords.length} 次'),
                const SizedBox(width: 8),
                _StatTile(label: '时长', value: _compactDuration(totalTime)),
                const SizedBox(width: 8),
                _StatTile(label: '活跃', value: '$activeDays 天'),
              ],
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                for (final label in const ['一', '二', '三', '四', '五', '六', '日'])
                  Expanded(child: Center(child: Text(label))),
              ],
            ),
            const SizedBox(height: 8),
            _buildCalendar(daily, maxValue),
            const SizedBox(height: 12),
            _buildLegend(),
            if (_selectedDate != null) ...[
              const SizedBox(height: 16),
              _buildSelectedSummary(daily[_selectedDate] ?? const []),
            ],
            if (widget.initialDate != null) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => Navigator.pop(context, DateTime(1, 1, 1)),
                  icon: const Icon(Icons.filter_alt_off),
                  label: const Text('清除日期筛选'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildCalendar(Map<DateTime, List<ReadRecord>> daily, int maxValue) {
    final first = DateTime(_month.year, _month.month, 1);
    final leadingDays = first.weekday - 1;
    final daysInMonth = DateTime(_month.year, _month.month + 1, 0).day;
    final totalCells = ((leadingDays + daysInMonth + 6) ~/ 7) * 7;
    final start = first.subtract(Duration(days: leadingDays));
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: totalCells,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 7,
        mainAxisSpacing: 4,
        crossAxisSpacing: 4,
      ),
      itemBuilder: (context, index) {
        final date = start.add(Duration(days: index));
        final inMonth = date.month == _month.month;
        final records = daily[date] ?? const [];
        final value = _valueFor(records);
        final selected =
            _selectedDate != null && _sameDay(date, _selectedDate!);
        final today = _sameDay(date, DateTime.now());
        final color = _heatColor(value, maxValue, inMonth, selected);
        return InkWell(
          onTap: !inMonth
              ? null
              : () {
                  setState(() {
                    _selectedDate = selected ? null : date;
                  });
                  if (!selected) Navigator.pop(context, date);
                },
          borderRadius: BorderRadius.circular(8),
          child: Container(
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(8),
              border: today
                  ? Border.all(
                      color: Theme.of(context).colorScheme.primary,
                      width: 2,
                    )
                  : null,
            ),
            child: Text(
              '${date.day}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: selected
                    ? Theme.of(context).colorScheme.onPrimary
                    : inMonth
                    ? Theme.of(context).colorScheme.onSurface
                    : Theme.of(
                        context,
                      ).colorScheme.onSurfaceVariant.withValues(alpha: 0.35),
                fontWeight: selected || today
                    ? FontWeight.bold
                    : FontWeight.normal,
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildLegend() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Text('少', style: Theme.of(context).textTheme.labelSmall),
        const SizedBox(width: 4),
        for (var index = 0; index < 5; index++)
          Container(
            width: 14,
            height: 14,
            margin: const EdgeInsets.all(1),
            decoration: BoxDecoration(
              color: _heatColor(index, 4, true, false),
              borderRadius: BorderRadius.circular(3),
            ),
          ),
        const SizedBox(width: 4),
        Text('多', style: Theme.of(context).textTheme.labelSmall),
      ],
    );
  }

  Widget _buildSelectedSummary(List<ReadRecord> records) {
    final colorScheme = Theme.of(context).colorScheme;
    final total = records.fold<int>(0, (sum, item) => sum + item.readTime);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${_selectedDate!.year}年${_selectedDate!.month}月${_selectedDate!.day}日',
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                ),
                Text('${records.length} 次 · ${_compactDuration(total)}'),
              ],
            ),
          ),
          IconButton(
            onPressed: () => setState(() => _selectedDate = null),
            icon: const Icon(Icons.close),
            tooltip: '取消选择',
          ),
        ],
      ),
    );
  }

  int _valueFor(List<ReadRecord> records) {
    if (_mode == _HeatmapMode.count) return records.length;
    return records.fold<int>(0, (sum, record) => sum + record.readTime) ~/ 60;
  }

  Color _heatColor(int value, int maxValue, bool inMonth, bool selected) {
    final colorScheme = Theme.of(context).colorScheme;
    if (selected) return colorScheme.primary;
    if (!inMonth) {
      return colorScheme.surfaceContainerHighest.withValues(alpha: 0.22);
    }
    if (value <= 0) {
      return colorScheme.surfaceContainerHighest.withValues(alpha: 0.5);
    }
    final ratio = math.min(1.0, value / math.max(1, maxValue));
    return Color.lerp(
      colorScheme.primaryContainer.withValues(alpha: 0.55),
      colorScheme.primary,
      ratio * ratio,
    )!;
  }

  bool _sameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  String _compactDuration(int seconds) {
    if (seconds < 60) return '$seconds 秒';
    if (seconds < 3600) return '${seconds ~/ 60} 分钟';
    return '${seconds ~/ 3600}小时${(seconds % 3600) ~/ 60}分';
  }
}

class _StatTile extends StatelessWidget {
  final String label;
  final String value;

  const _StatTile({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          children: [
            Text(
              label,
              maxLines: 1,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}

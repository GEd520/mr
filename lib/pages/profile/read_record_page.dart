import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/bookshelf_provider.dart';

/// 阅读记录页面 - 参考 legados 的 ReadRecordActivity
class ReadRecordPage extends StatefulWidget {
  final String? bookUrl;

  const ReadRecordPage({super.key, this.bookUrl});

  @override
  State<ReadRecordPage> createState() => _ReadRecordPageState();
}

class _ReadRecordPageState extends State<ReadRecordPage> {
  final TextEditingController _searchController = TextEditingController();
  String _searchKeyword = '';
  List<ReadRecord> _records = [];
  List<ReadRecord> _filteredRecords = [];
  bool _isLoading = true;

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
    // TODO: 从存储加载阅读记录
    // 这里使用模拟数据
    await Future.delayed(const Duration(milliseconds: 500));
    
    final provider = context.read<BookshelfProvider>();
    final records = <ReadRecord>[];
    
    for (final book in provider.books) {
      if (book.durChapterIndex > 0) {
        records.add(ReadRecord(
          bookUrl: book.bookUrl,
          bookName: book.name,
          author: book.author,
          coverUrl: book.coverUrl,
          totalReadTime: Duration(minutes: (book.durChapterIndex * 5)), // 模拟数据
          firstReadTime: DateTime.now().subtract(const Duration(days: 7)),
          lastReadTime: DateTime.now().subtract(const Duration(hours: 2)),
          chapterCount: book.durChapterIndex,
        ));
      }
    }

    setState(() {
      _records = records;
      _filteredRecords = records;
      _isLoading = false;
    });
  }

  void _filterRecords(String keyword) {
    setState(() {
      _searchKeyword = keyword.trim().toLowerCase();
      if (_searchKeyword.isEmpty) {
        _filteredRecords = _records;
      } else {
        _filteredRecords = _records.where((r) {
          return r.bookName.toLowerCase().contains(_searchKeyword) ||
              r.author.toLowerCase().contains(_searchKeyword);
        }).toList();
      }
    });
  }

  Future<void> _clearRecord(ReadRecord record) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清除确认'),
        content: Text('确定要清除 "${record.bookName}" 的阅读记录吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('清除'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      setState(() {
        _records.remove(record);
        _filteredRecords.remove(record);
      });
      // TODO: 从存储中删除记录
    }
  }

  Future<void> _clearAllRecords() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清除全部'),
        content: const Text('确定要清除所有阅读记录吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('清除'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      setState(() {
        _records.clear();
        _filteredRecords.clear();
      });
      // TODO: 从存储中删除所有记录
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _searchController,
          decoration: InputDecoration(
            hintText: '搜索阅读记录',
            border: InputBorder.none,
            suffixIcon: _searchKeyword.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear),
                    onPressed: () {
                      _searchController.clear();
                      _filterRecords('');
                    },
                  )
                : null,
          ),
          onChanged: _filterRecords,
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_sweep),
            onPressed: _records.isEmpty ? null : _clearAllRecords,
            tooltip: '清除全部',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _filteredRecords.isEmpty
              ? _buildEmptyState()
              : _buildRecordList(),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.history,
            size: 80,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 16),
          Text(
            _searchKeyword.isNotEmpty ? '未找到匹配的记录' : '暂无阅读记录',
            style: TextStyle(
              fontSize: 18,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecordList() {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: _filteredRecords.length,
      itemBuilder: (context, index) {
        final record = _filteredRecords[index];
        return _buildRecordItem(record);
      },
    );
  }

  Widget _buildRecordItem(ReadRecord record) {
    return InkWell(
      onTap: () {
        // 跳转到书籍详情
        Navigator.pop(context, record.bookUrl);
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 书名
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    record.bookName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 8),
                  // 累计阅读时间
                  Row(
                    children: [
                      Text(
                        '累计阅读: ',
                        style: TextStyle(
                          fontSize: 13,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      Text(
                        _formatDuration(record.totalReadTime),
                        style: TextStyle(
                          fontSize: 13,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  // 首次阅读时间
                  Row(
                    children: [
                      Text(
                        '首次阅读: ',
                        style: TextStyle(
                          fontSize: 13,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      Text(
                        _formatDateTime(record.firstReadTime),
                        style: TextStyle(
                          fontSize: 13,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  // 最后阅读时间
                  Row(
                    children: [
                      Text(
                        '最后阅读: ',
                        style: TextStyle(
                          fontSize: 13,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      Text(
                        _formatDateTime(record.lastReadTime),
                        style: TextStyle(
                          fontSize: 13,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            // 清除按钮
            TextButton(
              onPressed: () => _clearRecord(record),
              style: TextButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.error,
              ),
              child: const Text('清除'),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDuration(Duration duration) {
    if (duration.inHours > 0) {
      return '${duration.inHours}小时${duration.inMinutes % 60}分钟';
    } else if (duration.inMinutes > 0) {
      return '${duration.inMinutes}分钟';
    } else {
      return '${duration.inSeconds}秒';
    }
  }

  String _formatDateTime(DateTime time) {
    final now = DateTime.now();
    final diff = now.difference(time);
    
    if (diff.inDays == 0) {
      return '今天 ${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
    } else if (diff.inDays == 1) {
      return '昨天 ${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
    } else if (diff.inDays < 7) {
      return '${diff.inDays}天前';
    } else {
      return '${time.year}-${time.month.toString().padLeft(2, '0')}-${time.day.toString().padLeft(2, '0')}';
    }
  }
}

/// 阅读记录数据模型
class ReadRecord {
  final String bookUrl;
  final String bookName;
  final String author;
  final String coverUrl;
  final Duration totalReadTime;
  final DateTime firstReadTime;
  final DateTime lastReadTime;
  final int chapterCount;

  ReadRecord({
    required this.bookUrl,
    required this.bookName,
    required this.author,
    required this.coverUrl,
    required this.totalReadTime,
    required this.firstReadTime,
    required this.lastReadTime,
    required this.chapterCount,
  });

  Map<String, dynamic> toJson() => {
    'bookUrl': bookUrl,
    'bookName': bookName,
    'author': author,
    'coverUrl': coverUrl,
    'totalReadTime': totalReadTime.inSeconds,
    'firstReadTime': firstReadTime.toIso8601String(),
    'lastReadTime': lastReadTime.toIso8601String(),
    'chapterCount': chapterCount,
  };

  factory ReadRecord.fromJson(Map<String, dynamic> json) => ReadRecord(
    bookUrl: json['bookUrl'],
    bookName: json['bookName'],
    author: json['author'] ?? '',
    coverUrl: json['coverUrl'] ?? '',
    totalReadTime: Duration(seconds: json['totalReadTime'] ?? 0),
    firstReadTime: DateTime.parse(json['firstReadTime']),
    lastReadTime: DateTime.parse(json['lastReadTime']),
    chapterCount: json['chapterCount'] ?? 0,
  );
}

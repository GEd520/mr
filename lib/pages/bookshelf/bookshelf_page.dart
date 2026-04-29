import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import '../../models/book.dart';
import '../../providers/bookshelf_provider.dart';
import '../../routes/app_routes.dart';

class BookshelfPage extends StatefulWidget {
  const BookshelfPage({super.key});

  @override
  State<BookshelfPage> createState() => _BookshelfPageState();
}

class _BookshelfPageState extends State<BookshelfPage> {
  final List<String> _groups = ['全部', '追更', '漫画', '已完结'];
  int _selectedGroupIndex = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('书架'),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () {
              Navigator.pushNamed(context, AppRoutes.search);
            },
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: (value) {
              final provider = context.read<BookshelfProvider>();
              switch (value) {
                case 'view':
                  provider.toggleViewMode();
                  break;
                case 'batch':
                  provider.enterBatchMode();
                  break;
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'view',
                child: Text(context.read<BookshelfProvider>().isGridView ? '切换列表视图' : '切换网格视图'),
              ),
              const PopupMenuItem(
                value: 'batch',
                child: Text('批量管理'),
              ),
            ],
          ),
        ],
      ),
      body: Consumer<BookshelfProvider>(
        builder: (context, provider, child) {
          return Column(
            children: [
              _buildGroupTabs(provider),
              Expanded(
                child: provider.isBatchMode
                    ? _buildBatchView(provider)
                    : provider.isGridView
                        ? _buildGridView(provider)
                        : _buildListView(provider),
              ),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showImportDialog,
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildGroupTabs(BookshelfProvider provider) {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: _groups.length + 1,
        itemBuilder: (context, index) {
          if (index == _groups.length) {
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: ActionChip(
                label: const Text('+ 新建分组'),
                onPressed: () {
                  _showCreateGroupDialog();
                },
              ),
            );
          }

          final isSelected = index == _selectedGroupIndex;
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: FilterChip(
              label: Text(_groups[index]),
              selected: isSelected,
              onSelected: (selected) {
                setState(() {
                  _selectedGroupIndex = index;
                });
                provider.setGroup(
                  index == 0 ? null : _groups[index],
                );
              },
            ),
          );
        },
      ),
    );
  }

  Widget _buildGridView(BookshelfProvider provider) {
    if (provider.books.isEmpty) {
      return _buildEmptyState();
    }

    return RefreshIndicator(
      onRefresh: provider.loadBooks,
      child: GridView.builder(
        padding: const EdgeInsets.all(12),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          childAspectRatio: 0.65,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
        ),
        itemCount: provider.books.length,
        itemBuilder: (context, index) {
          final book = provider.books[index];
          return _buildGridBookCard(book, provider);
        },
      ),
    );
  }

  Widget _buildGridBookCard(Book book, BookshelfProvider provider) {
    return GestureDetector(
      onTap: () => _openBook(book),
      onLongPress: () => _showBookOptions(book, provider),
      child: Stack(
        children: [
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: book.coverUrl.isNotEmpty
                      ? CachedNetworkImage(
                          imageUrl: book.coverUrl,
                          fit: BoxFit.cover,
                          placeholder: (context, url) => Container(
                            color: Theme.of(context).colorScheme.surfaceVariant,
                            child: const Center(
                              child: CircularProgressIndicator(),
                            ),
                          ),
                          errorWidget: (context, url, error) => Container(
                            color: Theme.of(context).colorScheme.surfaceVariant,
                            child: const Icon(Icons.book, size: 48),
                          ),
                        )
                      : Container(
                          color: Theme.of(context).colorScheme.surfaceVariant,
                          child: const Icon(Icons.book, size: 48),
                        ),
                ),
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        book.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        book.author,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 10,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 4),
                      LinearProgressIndicator(
                        value: book.progress,
                        backgroundColor: Theme.of(context).colorScheme.surfaceVariant,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (book.originType == BookOriginType.local)
            Positioned(
              top: 8,
              left: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text(
                  '本地',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                  ),
                ),
              ),
            ),
          if (book.isTop)
            Positioned(
              top: 8,
              right: 8,
              child: Icon(
                Icons.push_pin,
                size: 16,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildListView(BookshelfProvider provider) {
    if (provider.books.isEmpty) {
      return _buildEmptyState();
    }

    return RefreshIndicator(
      onRefresh: provider.loadBooks,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: provider.books.length,
        itemBuilder: (context, index) {
          final book = provider.books[index];
          return _buildListBookCard(book, provider);
        },
      ),
    );
  }

  Widget _buildListBookCard(Book book, BookshelfProvider provider) {
    return Slidable(
      endActionPane: ActionPane(
        motion: const DrawerMotion(),
        children: [
          SlidableAction(
            onPressed: (_) => provider.toggleTop(book.bookUrl),
            backgroundColor: Theme.of(context).colorScheme.primaryContainer,
            foregroundColor: Theme.of(context).colorScheme.onPrimaryContainer,
            icon: book.isTop ? Icons.push_pin_outlined : Icons.push_pin,
            label: book.isTop ? '取消置顶' : '置顶',
          ),
          SlidableAction(
            onPressed: (_) => provider.removeFromBookshelf(book.bookUrl),
            backgroundColor: Theme.of(context).colorScheme.errorContainer,
            foregroundColor: Theme.of(context).colorScheme.onErrorContainer,
            icon: Icons.delete,
            label: '移除',
          ),
        ],
      ),
      child: ListTile(
        leading: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: book.coverUrl.isNotEmpty
              ? CachedNetworkImage(
                  imageUrl: book.coverUrl,
                  width: 48,
                  height: 64,
                  fit: BoxFit.cover,
                  placeholder: (context, url) => Container(
                    width: 48,
                    height: 64,
                    color: Theme.of(context).colorScheme.surfaceVariant,
                  ),
                  errorWidget: (context, url, error) => Container(
                    width: 48,
                    height: 64,
                    color: Theme.of(context).colorScheme.surfaceVariant,
                    child: const Icon(Icons.book),
                  ),
                )
              : Container(
                  width: 48,
                  height: 64,
                  color: Theme.of(context).colorScheme.surfaceVariant,
                  child: const Icon(Icons.book),
                ),
        ),
        title: Text(book.name),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(book.author),
            const SizedBox(height: 4),
            LinearProgressIndicator(
              value: book.progress,
              backgroundColor: Theme.of(context).colorScheme.surfaceVariant,
            ),
          ],
        ),
        trailing: book.originType == BookOriginType.local
            ? Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '本地',
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                  ),
                ),
              )
            : null,
        onTap: () => _openBook(book),
        onLongPress: () => _showBookOptions(book, provider),
      ),
    );
  }

  Widget _buildBatchView(BookshelfProvider provider) {
    return Column(
      children: [
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.all(12),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              childAspectRatio: 0.65,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
            ),
            itemCount: provider.books.length,
            itemBuilder: (context, index) {
              final book = provider.books[index];
              final isSelected = provider.selectedBookIds.contains(book.bookUrl);

              return GestureDetector(
                onTap: () => provider.toggleBookSelection(book.bookUrl),
                child: Stack(
                  children: [
                    _buildGridBookCard(book, provider),
                    if (isSelected)
                      Positioned.fill(
                        child: Container(
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.primary.withOpacity(0.3),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Center(
                            child: Icon(
                              Icons.check_circle,
                              size: 48,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        ),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 8,
                offset: const Offset(0, -2),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              TextButton.icon(
                onPressed: provider.selectedBookIds.isEmpty
                    ? null
                    : () => provider.batchRemove(),
                icon: const Icon(Icons.delete),
                label: const Text('批量移除'),
              ),
              TextButton.icon(
                onPressed: () => provider.exitBatchMode(),
                icon: const Icon(Icons.close),
                label: const Text('取消'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.book_outlined,
            size: 80,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 16),
          Text(
            '书架空空如也',
            style: TextStyle(
              fontSize: 18,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '点击右下角按钮导入书籍',
            style: TextStyle(
              fontSize: 14,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  void _showImportDialog() {
    showModalBottomSheet(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.folder),
                title: const Text('扫描目录'),
                subtitle: const Text('选择文件夹自动识别支持的格式'),
                onTap: () {
                  Navigator.pop(context);
                  _scanDirectory();
                },
              ),
              ListTile(
                leading: const Icon(Icons.insert_drive_file),
                title: const Text('选择文件'),
                subtitle: const Text('手动选择单个或多个文件'),
                onTap: () {
                  Navigator.pop(context);
                  _selectFiles();
                },
              ),
            ],
          ),
        );
      },
    );
  }

  void _scanDirectory() {
  }

  void _selectFiles() {
  }

  void _showCreateGroupDialog() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('新建分组'),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(
              hintText: '分组名称',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () {
                if (controller.text.isNotEmpty) {
                  setState(() {
                    _groups.add(controller.text);
                  });
                  Navigator.pop(context);
                }
              },
              child: const Text('创建'),
            ),
          ],
        );
      },
    );
  }

  void _showBookOptions(Book book, BookshelfProvider provider) {
    showModalBottomSheet(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: Icon(book.isTop ? Icons.push_pin_outlined : Icons.push_pin),
                title: Text(book.isTop ? '取消置顶' : '置顶'),
                onTap: () {
                  provider.toggleTop(book.bookUrl);
                  Navigator.pop(context);
                },
              ),
              ListTile(
                leading: const Icon(Icons.folder),
                title: const Text('移动到分组'),
                onTap: () {
                  Navigator.pop(context);
                  _showMoveToGroupDialog(book, provider);
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete),
                title: const Text('从书架移除'),
                onTap: () {
                  provider.removeFromBookshelf(book.bookUrl);
                  Navigator.pop(context);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  void _showMoveToGroupDialog(Book book, BookshelfProvider provider) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('移动到分组'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: _groups.map((group) {
              return RadioListTile<String>(
                title: Text(group),
                value: group,
                groupValue: book.groupId ?? '全部',
                onChanged: (value) {
                  Navigator.pop(context);
                },
              );
            }).toList(),
          ),
        );
      },
    );
  }

  void _openBook(Book book) {
    Navigator.pushNamed(
      context,
      AppRoutes.detail,
      arguments: {'bookUrl': book.bookUrl},
    );
  }
}

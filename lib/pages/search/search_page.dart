import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/search_provider.dart';
import '../../models/book_source.dart';
import '../../routes/app_routes.dart';

class SearchPage extends StatefulWidget {
  final String? initialKeyword;

  const SearchPage({super.key, this.initialKeyword});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  bool _isGridView = false;

  @override
  void initState() {
    super.initState();
    
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = context.read<SearchProvider>();
      provider.loadBookSources();
      provider.loadSearchHistory();
    });

    if (widget.initialKeyword != null) {
      _searchController.text = widget.initialKeyword!;
      _performSearch();
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _searchController,
          focusNode: _focusNode,
          decoration: InputDecoration(
            hintText: '搜索书籍、漫画、视频...',
            border: InputBorder.none,
            suffixIcon: IconButton(
              icon: const Icon(Icons.clear),
              onPressed: () {
                _searchController.clear();
                context.read<SearchProvider>().clearResults();
              },
            ),
          ),
          onSubmitted: (_) => _performSearch(),
        ),
        actions: [
          TextButton(
            onPressed: _performSearch,
            child: const Text('搜索'),
          ),
        ],
      ),
      body: Consumer<SearchProvider>(
        builder: (context, provider, child) {
          return Column(
            children: [
              _buildFilters(provider),
              Expanded(
                child: provider.isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : provider.error != null
                        ? _buildErrorState(provider)
                        : provider.searchResults.isEmpty
                            ? _buildEmptyState(provider)
                            : _isGridView
                                ? _buildGridView(provider)
                                : _buildListView(provider),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildFilters(SearchProvider provider) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  ActionChip(
                    label: Text('书源 (${provider.selectedSourceUrls.length})'),
                    avatar: const Icon(Icons.source, size: 18),
                    onPressed: () => _showSourceFilter(provider),
                  ),
                  const SizedBox(width: 8),
                  if (provider.selectedSourceUrls.isNotEmpty)
                    ActionChip(
                      label: const Text('全选'),
                      onPressed: () => provider.selectAllSources(),
                    ),
                  const SizedBox(width: 8),
                  if (provider.selectedSourceUrls.isNotEmpty)
                    ActionChip(
                      label: const Text('取消全选'),
                      onPressed: () => provider.deselectAllSources(),
                    ),
                ],
              ),
            ),
          ),
          IconButton(
            icon: Icon(_isGridView ? Icons.view_list : Icons.grid_view),
            onPressed: () {
              setState(() {
                _isGridView = !_isGridView;
              });
            },
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState(SearchProvider provider) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.error_outline,
            size: 64,
            color: Theme.of(context).colorScheme.error,
          ),
          const SizedBox(height: 16),
          Text(
            provider.error!,
            style: TextStyle(
              color: Theme.of(context).colorScheme.error,
            ),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: () => _showSourceFilter(provider),
            child: const Text('选择书源'),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(SearchProvider provider) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (provider.searchHistory.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '搜索历史',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  TextButton(
                    onPressed: () => provider.clearHistory(),
                    child: const Text('清空'),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: provider.searchHistory.map((keyword) {
                  return InputChip(
                    label: Text(keyword),
                    onPressed: () {
                      _searchController.text = keyword;
                      _performSearch();
                    },
                    onDeleted: () => provider.removeFromHistory(keyword),
                  );
                }).toList(),
              ),
            ),
          ],
          const SizedBox(height: 24),
          Center(
            child: Column(
              children: [
                Icon(
                  Icons.search,
                  size: 80,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                const SizedBox(height: 16),
                Text(
                  '输入关键词搜索',
                  style: TextStyle(
                    fontSize: 18,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                if (provider.bookSources.isEmpty) ...[
                  const SizedBox(height: 16),
                  TextButton.icon(
                    onPressed: () {
                      Navigator.pushNamed(context, AppRoutes.profile);
                    },
                    icon: const Icon(Icons.add),
                    label: const Text('导入书源'),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildListView(SearchProvider provider) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: provider.searchResults.length,
      itemBuilder: (context, index) {
        final result = provider.searchResults[index];
        return _buildListResultItem(result);
      },
    );
  }

  Widget _buildListResultItem(Map<String, dynamic> result) {
    return ListTile(
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: 48,
          height: 64,
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          child: const Icon(Icons.book),
        ),
      ),
      title: Text(result['name'] ?? '未知书名'),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(result['author'] ?? '未知作者'),
          const SizedBox(height: 4),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  result['sourceName'] ?? '',
                  style: TextStyle(
                    fontSize: 10,
                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
      onTap: () {
        Navigator.pushNamed(
          context,
          AppRoutes.detail,
          arguments: {
            'bookUrl': result['bookUrl'],
            'bookData': result,
          },
        );
      },
    );
  }

  Widget _buildGridView(SearchProvider provider) {
    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        childAspectRatio: 0.65,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: provider.searchResults.length,
      itemBuilder: (context, index) {
        final result = provider.searchResults[index];
        return _buildGridResultItem(result);
      },
    );
  }

  Widget _buildGridResultItem(Map<String, dynamic> result) {
    return GestureDetector(
      onTap: () {
        Navigator.pushNamed(
          context,
          AppRoutes.detail,
          arguments: {
            'bookUrl': result['bookUrl'],
            'bookData': result,
          },
        );
      },
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Container(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                child: const Center(child: Icon(Icons.book, size: 48)),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    result['name'] ?? '未知书名',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    result['author'] ?? '未知作者',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 10,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _performSearch() {
    final keyword = _searchController.text.trim();
    if (keyword.isEmpty) return;
    context.read<SearchProvider>().search(keyword);
  }

  void _showSourceFilter(SearchProvider provider) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.6,
          minChildSize: 0.4,
          maxChildSize: 0.9,
          expand: false,
          builder: (context, scrollController) {
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '选择书源 (${provider.bookSources.length})',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      Row(
                        children: [
                          TextButton(
                            onPressed: () => provider.selectAllSources(),
                            child: const Text('全选'),
                          ),
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('确定'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const Divider(),
                Expanded(
                  child: provider.bookSources.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Text('暂无可用书源'),
                              const SizedBox(height: 16),
                              ElevatedButton(
                                onPressed: () {
                                  Navigator.pop(context);
                                  Navigator.pushNamed(context, AppRoutes.profile);
                                },
                                child: const Text('导入书源'),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          controller: scrollController,
                          itemCount: provider.bookSources.length,
                          itemBuilder: (context, index) {
                            final source = provider.bookSources[index];
                            final isSelected = provider.selectedSourceUrls
                                .contains(source.bookSourceUrl);
                            return CheckboxListTile(
                              value: isSelected,
                              onChanged: (checked) {
                                provider.toggleSourceSelection(source.bookSourceUrl);
                              },
                              title: Text(source.bookSourceName),
                              subtitle: Text(
                                source.bookSourceGroup ?? '默认分组',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                                ),
                              ),
                              secondary: _buildSourceTypeIcon(source),
                            );
                          },
                        ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildSourceTypeIcon(BookSource source) {
    IconData icon;
    switch (source.bookSourceType) {
      case BookSourceType.text:
        icon = Icons.book;
        break;
      case BookSourceType.audio:
        icon = Icons.headphones;
        break;
      case BookSourceType.image:
        icon = Icons.image;
        break;
      case BookSourceType.video:
        icon = Icons.video_library;
        break;
      case BookSourceType.file:
        icon = Icons.folder;
        break;
    }
    return Icon(icon, size: 20);
  }
}

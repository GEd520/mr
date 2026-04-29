import 'package:flutter/material.dart';
import '../models/book_source.dart';

enum DiscoveryCategory { recommend, novel, comic, video, audio }

class DiscoveryProvider extends ChangeNotifier {
  DiscoveryCategory _currentCategory = DiscoveryCategory.recommend;
  List<BookSource> _enabledSources = [];
  Set<String> _selectedSourceIds = {};
  bool _isLoading = false;
  List<dynamic> _content = [];

  DiscoveryCategory get currentCategory => _currentCategory;
  List<BookSource> get enabledSources => _enabledSources;
  Set<String> get selectedSourceIds => _selectedSourceIds;
  bool get isLoading => _isLoading;
  List<dynamic> get content => _content;

  void setCategory(DiscoveryCategory category) {
    _currentCategory = category;
    notifyListeners();
  }

  void setEnabledSources(List<BookSource> sources) {
    _enabledSources = sources;
    _selectedSourceIds = sources.map((s) => s.bookSourceUrl).toSet();
    notifyListeners();
  }

  void toggleSourceSelection(String sourceId) {
    if (_selectedSourceIds.contains(sourceId)) {
      _selectedSourceIds.remove(sourceId);
    } else {
      _selectedSourceIds.add(sourceId);
    }
    notifyListeners();
  }

  Future<void> loadContent() async {
    _isLoading = true;
    notifyListeners();

    try {
      await Future.delayed(const Duration(seconds: 1));
      _content = [];
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> refresh() async {
    await loadContent();
  }
}

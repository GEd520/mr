import 'dart:convert';
import 'package:dio/dio.dart';

class LegadoApiService {
  static final LegadoApiService instance = LegadoApiService._internal();
  LegadoApiService._internal();

  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 30),
  ));

  String _baseUrl = 'http://localhost:1122';

  void setBaseUrl(String url) {
    _baseUrl = url.replaceAll(RegExp(r'/+$'), '');
    _dio.options.baseUrl = _baseUrl;
  }

  String get baseUrl => _baseUrl;

  Future<List<dynamic>> getBookshelf() async {
    try {
      final response = await _dio.get('$_baseUrl/getBookshelf');
      if (response.statusCode == 200) {
        return response.data is String
            ? jsonDecode(response.data) as List<dynamic>
            : response.data as List<dynamic>;
      }
      return [];
    } catch (e) {
      return [];
    }
  }

  Future<List<dynamic>> getChapterList(String bookUrl) async {
    try {
      final response = await _dio.get(
        '$_baseUrl/getChapterList',
        queryParameters: {'url': bookUrl},
      );
      if (response.statusCode == 200) {
        return response.data is String
            ? jsonDecode(response.data) as List<dynamic>
            : response.data as List<dynamic>;
      }
      return [];
    } catch (e) {
      return [];
    }
  }

  Future<Map<String, dynamic>?> getBookContent(
    String bookUrl,
    int chapterIndex,
  ) async {
    try {
      final response = await _dio.get(
        '$_baseUrl/getBookContent',
        queryParameters: {'url': bookUrl, 'index': chapterIndex},
      );
      if (response.statusCode == 200) {
        return response.data is String
            ? jsonDecode(response.data) as Map<String, dynamic>
            : response.data as Map<String, dynamic>;
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  Future<List<dynamic>> getBookSources() async {
    try {
      final response = await _dio.get('$_baseUrl/getBookSources');
      if (response.statusCode == 200) {
        return response.data is String
            ? jsonDecode(response.data) as List<dynamic>
            : response.data as List<dynamic>;
      }
      return [];
    } catch (e) {
      return [];
    }
  }

  Future<Map<String, dynamic>?> getBookSource(String sourceUrl) async {
    try {
      final response = await _dio.get(
        '$_baseUrl/getBookSource',
        queryParameters: {'url': sourceUrl},
      );
      if (response.statusCode == 200) {
        return response.data is String
            ? jsonDecode(response.data) as Map<String, dynamic>
            : response.data as Map<String, dynamic>;
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  Future<bool> saveBookSource(Map<String, dynamic> sourceData) async {
    try {
      final response = await _dio.post(
        '$_baseUrl/saveBookSource',
        data: jsonEncode(sourceData),
        options: Options(contentType: 'application/json'),
      );
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  Future<bool> saveBook(Map<String, dynamic> bookData) async {
    try {
      final response = await _dio.post(
        '$_baseUrl/saveBook',
        data: jsonEncode(bookData),
        options: Options(contentType: 'application/json'),
      );
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  Future<bool> saveBookProgress(Map<String, dynamic> progressData) async {
    try {
      final response = await _dio.post(
        '$_baseUrl/saveBookProgress',
        data: jsonEncode(progressData),
        options: Options(contentType: 'application/json'),
      );
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  Future<Map<String, dynamic>?> getReadConfig() async {
    try {
      final response = await _dio.get('$_baseUrl/getReadConfig');
      if (response.statusCode == 200) {
        return response.data is String
            ? jsonDecode(response.data) as Map<String, dynamic>
            : response.data as Map<String, dynamic>;
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  Future<bool> saveReadConfig(Map<String, dynamic> configData) async {
    try {
      final response = await _dio.post(
        '$_baseUrl/saveReadConfig',
        data: jsonEncode(configData),
        options: Options(contentType: 'application/json'),
      );
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  String getCoverUrl(String coverUrl) {
    return '$_baseUrl/cover?url=${Uri.encodeComponent(coverUrl)}';
  }

  String getImageUrl(String imageUrl) {
    return '$_baseUrl/image?url=${Uri.encodeComponent(imageUrl)}';
  }

  Future<bool> testConnection() async {
    try {
      final response = await _dio.get('$_baseUrl/getBookshelf');
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }
}

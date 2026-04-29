import 'dart:convert';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart' as encrypt;
import '../../models/book_source.dart';

enum DanFileType { bookSource, miniprogram, plugin }

class DanFile {
  final DanFileType type;
  final String name;
  final String version;
  final String author;
  final String? description;
  final String? password;
  final Map<String, dynamic> metadata;
  final Uint8List? icon;
  final dynamic data;

  const DanFile({
    required this.type,
    required this.name,
    required this.version,
    this.author = '',
    this.description,
    this.password,
    this.metadata = const {},
    this.icon,
    this.data,
  });

  factory DanFile.fromJson(Map<String, dynamic> json) {
    return DanFile(
      type: DanFileType.values.firstWhere(
        (t) => t.name == json['type'],
        orElse: () => DanFileType.bookSource,
      ),
      name: json['name'] ?? '',
      version: json['version'] ?? '1.0.0',
      author: json['author'] ?? '',
      description: json['description'],
      password: json['password'],
      metadata: json['metadata'] ?? {},
      icon: json['icon'] != null ? base64Decode(json['icon']) : null,
      data: json['data'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'type': type.name,
      'name': name,
      'version': version,
      'author': author,
      'description': description,
      'metadata': metadata,
      'icon': icon != null ? base64Encode(icon!) : null,
      'data': data,
    };
  }
}

class DanFileParser {
  static const String _manifestFile = 'manifest.json';
  static const String _dataFile = 'data.json';
  static const String _iconFile = 'icon.png';

  static Future<DanFile> parse(Uint8List bytes, {String? password}) async {
    final archive = ZipDecoder().decodeBytes(bytes);

    String? manifestContent;
    String? dataContent;
    Uint8List? iconBytes;

    for (final file in archive) {
      if (file.isFile) {
        final content = file.content as Uint8List;
        if (file.name == _manifestFile) {
          manifestContent = utf8.decode(content);
        } else if (file.name == _dataFile) {
          dataContent = utf8.decode(content);
        } else if (file.name == _iconFile) {
          iconBytes = content;
        }
      }
    }

    if (manifestContent == null) {
      throw Exception('无效的.dan文件：缺少manifest.json');
    }

    Map<String, dynamic> manifest;
    try {
      manifest = json.decode(manifestContent) as Map<String, dynamic>;
    } catch (e) {
      throw Exception('无效的manifest.json格式');
    }

    if (manifest['encrypted'] == true) {
      if (password == null) {
        throw Exception('需要密码解密');
      }
      if (dataContent != null) {
        dataContent = _decrypt(dataContent, password);
      }
    }

    dynamic parsedData;
    if (dataContent != null) {
      try {
        parsedData = json.decode(dataContent);
      } catch (_) {
        parsedData = dataContent;
      }
    }

    return DanFile(
      type: DanFileType.values.firstWhere(
        (t) => t.name == manifest['type'],
        orElse: () => DanFileType.bookSource,
      ),
      name: manifest['name'] ?? '',
      version: manifest['version'] ?? '1.0.0',
      author: manifest['author'] ?? '',
      description: manifest['description'],
      password: password,
      metadata: manifest['metadata'] ?? {},
      icon: iconBytes,
      data: parsedData,
    );
  }

  static Future<Uint8List> create(DanFile danFile, {String? password}) async {
    final archive = Archive();

    final manifest = {
      'type': danFile.type.name,
      'name': danFile.name,
      'version': danFile.version,
      'author': danFile.author,
      'description': danFile.description,
      'encrypted': password != null,
      'metadata': danFile.metadata,
    };

    final manifestBytes = utf8.encode(json.encode(manifest));
    archive.addFile(ArchiveFile(_manifestFile, manifestBytes.length, manifestBytes));

    String dataContent = json.encode(danFile.data);
    if (password != null) {
      dataContent = _encrypt(dataContent, password);
    }
    final dataBytes = utf8.encode(dataContent);
    archive.addFile(ArchiveFile(_dataFile, dataBytes.length, dataBytes));

    if (danFile.icon != null) {
      archive.addFile(ArchiveFile(_iconFile, danFile.icon!.length, danFile.icon!));
    }

    final zipBytes = ZipEncoder().encode(archive);
    return Uint8List.fromList(zipBytes!);
  }

  static String _encrypt(String content, String password) {
    final key = _deriveKey(password);
    final iv = encrypt.IV.fromLength(16);
    final encrypter = encrypt.Encrypter(encrypt.AES(key));
    final encrypted = encrypter.encrypt(content, iv: iv);
    return encrypted.base64;
  }

  static String _decrypt(String content, String password) {
    final key = _deriveKey(password);
    final iv = encrypt.IV.fromLength(16);
    final encrypter = encrypt.Encrypter(encrypt.AES(key));
    final decrypted = encrypter.decrypt64(content, iv: iv);
    return decrypted;
  }

  static encrypt.Key _deriveKey(String password) {
    final bytes = utf8.encode(password);
    final hash = sha256.convert(bytes);
    return encrypt.Key(Uint8List.fromList(hash.bytes.sublist(0, 32)));
  }

  static String generateChecksum(Uint8List bytes) {
    final hash = sha256.convert(bytes);
    return hash.toString().substring(0, 16);
  }

  static bool validateChecksum(Uint8List bytes, String checksum) {
    return generateChecksum(bytes) == checksum;
  }
}

class BookSourceImporter {
  static Future<List<BookSource>> importFromDan(Uint8List bytes, {String? password}) async {
    final danFile = await DanFileParser.parse(bytes, password: password);

    if (danFile.type != DanFileType.bookSource) {
      throw Exception('不是书源文件');
    }

    final sources = <BookSource>[];

    if (danFile.data is List) {
      for (final item in danFile.data as List) {
        if (item is Map<String, dynamic>) {
          sources.add(BookSource.fromJson(item));
        }
      }
    } else if (danFile.data is Map<String, dynamic>) {
      sources.add(BookSource.fromJson(danFile.data as Map<String, dynamic>));
    }

    return sources;
  }

  static Future<List<BookSource>> importFromJson(String jsonContent) async {
    final sources = <BookSource>[];

    try {
      final data = json.decode(jsonContent);

      if (data is List) {
        for (final item in data) {
          if (item is Map<String, dynamic>) {
            sources.add(BookSource.fromJson(item));
          }
        }
      } else if (data is Map<String, dynamic>) {
        sources.add(BookSource.fromJson(data));
      }
    } catch (e) {
      throw Exception('JSON格式错误: $e');
    }

    return sources;
  }

  static Future<Uint8List> exportToDan(List<BookSource> sources, {String? password, String? name}) async {
    final danFile = DanFile(
      type: DanFileType.bookSource,
      name: name ?? '书源导出',
      version: '1.0.0',
      password: password,
      data: sources.map((s) => s.toJson()).toList(),
    );

    return DanFileParser.create(danFile, password: password);
  }

  static String exportToJson(List<BookSource> sources) {
    final data = sources.map((s) => s.toJson()).toList();
    return const JsonEncoder.withIndent('  ').convert(data);
  }
}

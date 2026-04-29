enum PluginType {
  readerEnhance,
  comicProcess,
  videoEnhance,
  audioEnhance,
  globalTheme,
  tts,
  translate,
  other,
}

class Plugin {
  final String id;
  final String name;
  final String version;
  final String? icon;
  final String? description;
  final PluginType type;
  final bool isEnabled;
  final DateTime addedTime;

  Plugin({
    required this.id,
    required this.name,
    required this.version,
    this.icon,
    this.description,
    required this.type,
    this.isEnabled = true,
    required this.addedTime,
  });

  Plugin copyWith({
    String? id,
    String? name,
    String? version,
    String? icon,
    String? description,
    PluginType? type,
    bool? isEnabled,
    DateTime? addedTime,
  }) {
    return Plugin(
      id: id ?? this.id,
      name: name ?? this.name,
      version: version ?? this.version,
      icon: icon ?? this.icon,
      description: description ?? this.description,
      type: type ?? this.type,
      isEnabled: isEnabled ?? this.isEnabled,
      addedTime: addedTime ?? this.addedTime,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'version': version,
      'icon': icon,
      'description': description,
      'type': type.index,
      'isEnabled': isEnabled,
      'addedTime': addedTime.toIso8601String(),
    };
  }

  factory Plugin.fromJson(Map<String, dynamic> json) {
    return Plugin(
      id: json['id'] as String,
      name: json['name'] as String,
      version: json['version'] as String,
      icon: json['icon'] as String?,
      description: json['description'] as String?,
      type: PluginType.values[json['type'] as int],
      isEnabled: json['isEnabled'] as bool? ?? true,
      addedTime: DateTime.parse(json['addedTime'] as String),
    );
  }
}

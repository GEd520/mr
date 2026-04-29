class Miniprogram {
  final String id;
  final String name;
  final String version;
  final String? icon;
  final String? description;
  final bool isEnabled;
  final int? size;
  final DateTime addedTime;

  Miniprogram({
    required this.id,
    required this.name,
    required this.version,
    this.icon,
    this.description,
    this.isEnabled = true,
    this.size,
    required this.addedTime,
  });

  Miniprogram copyWith({
    String? id,
    String? name,
    String? version,
    String? icon,
    String? description,
    bool? isEnabled,
    int? size,
    DateTime? addedTime,
  }) {
    return Miniprogram(
      id: id ?? this.id,
      name: name ?? this.name,
      version: version ?? this.version,
      icon: icon ?? this.icon,
      description: description ?? this.description,
      isEnabled: isEnabled ?? this.isEnabled,
      size: size ?? this.size,
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
      'isEnabled': isEnabled,
      'size': size,
      'addedTime': addedTime.toIso8601String(),
    };
  }

  factory Miniprogram.fromJson(Map<String, dynamic> json) {
    return Miniprogram(
      id: json['id'] as String,
      name: json['name'] as String,
      version: json['version'] as String,
      icon: json['icon'] as String?,
      description: json['description'] as String?,
      isEnabled: json['isEnabled'] as bool? ?? true,
      size: json['size'] as int?,
      addedTime: DateTime.parse(json['addedTime'] as String),
    );
  }
}

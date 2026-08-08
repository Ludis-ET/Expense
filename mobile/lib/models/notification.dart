class AppNotification {
  const AppNotification({
    required this.id,
    required this.type,
    required this.message,
    required this.readFlag,
    required this.createdAt,
    this.link,
  });

  final String id;
  final String type;
  final String message;
  final bool readFlag;
  final DateTime createdAt;
  final String? link;

  factory AppNotification.fromJson(Map<String, dynamic> json) => AppNotification(
        id: json['id'] as String,
        type: json['type'] as String? ?? 'general',
        message: json['message'] as String? ?? '',
        readFlag: json['readFlag'] as bool? ?? false,
        createdAt: DateTime.tryParse('${json['createdAt']}')?.toLocal() ?? DateTime.now(),
        link: json['link'] as String?,
      );

  AppNotification copyWith({bool? readFlag}) => AppNotification(
        id: id,
        type: type,
        message: message,
        readFlag: readFlag ?? this.readFlag,
        createdAt: createdAt,
        link: link,
      );
}

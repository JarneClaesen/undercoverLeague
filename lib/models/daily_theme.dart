import 'package:undercoverleague/models/game_settings.dart';

/// Today's preset word pool, the same for every lobby and server ("Shurima
/// Day"). Comes with the lobby view and from `GET /daily`. [filter] only
/// describes a pool: apply it with [GameSettings.withFilterOf] so the
/// host's rules stay.
class DailyTheme {
  final String id;
  final String title;
  final String description;
  final GameSettings filter;

  const DailyTheme({
    required this.id,
    required this.title,
    required this.description,
    required this.filter,
  });

  factory DailyTheme.fromJson(Map<String, dynamic> json) => DailyTheme(
        id: json['id'] as String? ?? '',
        title: json['title'] as String? ?? '',
        description: json['description'] as String? ?? '',
        filter: json['filter'] is Map ? GameSettings.fromJson((json['filter'] as Map).cast()) : const GameSettings(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'description': description,
        'filter': filter.toJson(),
      };

  /// An empty catalog has no theme; the server then sends the zero value.
  bool get isEmpty => id.isEmpty;

  @override
  bool operator ==(Object other) =>
      other is DailyTheme &&
      other.id == id &&
      other.title == title &&
      other.description == description &&
      other.filter == filter;

  @override
  int get hashCode => Object.hash(id, title, description, filter);
}

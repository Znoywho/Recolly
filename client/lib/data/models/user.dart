import 'json_utils.dart';

class User {
  const User({
    required this.id,
    required this.email,
    required this.displayName,
    this.avatarUrl,
    this.dateOfBirth,
    required this.timezone,
    required this.googleCalendarConnected,
    required this.createdAt,
    this.lastLoginAt,
  });

  factory User.fromJson(Json json) => User(
    id: json['id'] as String,
    email: json['email'] as String,
    displayName: json['display_name'] as String,
    avatarUrl: json['avatar_url'] as String?,
    dateOfBirth: parseDateOrNull(json['date_of_birth']),
    timezone: json['timezone'] as String,
    googleCalendarConnected: json['google_calendar_connected'] as bool,
    createdAt: parseDateTime(json['created_at']),
    lastLoginAt: parseDateTimeOrNull(json['last_login_at']),
  );

  final String id;
  final String email;
  final String displayName;
  final String? avatarUrl;
  final DateTime? dateOfBirth;

  /// IANA name, e.g. `Asia/Ho_Chi_Minh`.
  final String timezone;
  final bool googleCalendarConnected;
  final DateTime createdAt;
  final DateTime? lastLoginAt;

  Json toJson() => {
    'id': id,
    'email': email,
    'display_name': displayName,
    'avatar_url': avatarUrl,
    'date_of_birth': formatDateOrNull(dateOfBirth),
    'timezone': timezone,
    'google_calendar_connected': googleCalendarConnected,
    'created_at': formatDateTime(createdAt),
    'last_login_at': formatDateTimeOrNull(lastLoginAt),
  };
}

/// U2 `PATCH /users/me` body. Only provided fields are sent.
class UserUpdate {
  const UserUpdate({this.displayName, this.dateOfBirth, this.timezone});

  final String? displayName;
  final Nullable<DateTime>? dateOfBirth;
  final String? timezone;

  Json toJson() {
    final json = <String, Object?>{
      'display_name': ?displayName,
      'timezone': ?timezone,
    };
    putNullable(json, 'date_of_birth', dateOfBirth, formatDate);
    return json;
  }
}

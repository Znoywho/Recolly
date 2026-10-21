# Data layer (R06)

API client, DTOs and repositories for the endpoints in `docs/api-v1.md`, plus
mock repositories so screens can be built before the backend exists.

```dart
import 'package:client/data/data.dart';

final repos = AppRepositories.fromEnvironment(); // mock by default
final page = await repos.todos.listTodos(query: const TodoQuery(status: TodoStatus.todo));
```

| Folder | Content |
|---|---|
| `api/` | `ApiClient` (JSON, multipart upload, bearer token), `ApiException`, `AuthTokenStore` |
| `models/` | DTOs with `fromJson` / `toJson` (snake_case on the wire), enums, `ClockTime`, `Nullable` for PATCH |
| `repositories/` | One interface per domain + its `Api…` implementation |
| `mock/` | `Mock…` repositories returning fixed sample data |

## Switching to the real backend

```
flutter run --dart-define=USE_MOCK_API=false --dart-define=API_BASE_URL=http://10.0.2.2:8765/api/v1
```

## Conventions

- Datetimes are parsed to local time and sent as UTC ISO 8601.
- Errors are `ApiException` with `statusCode` and the backend `code`
  (e.g. `TODO_NOT_FOUND`); network failures have `statusCode == null`.
- PATCH: omitted field = unchanged; `Nullable(null)` = clear the field.
- Mock: todos, events, subjects and sleep logs keep in-memory edits; other
  endpoints return the same sample. An OCR photo whose filename contains
  `fail` returns `OCR_NO_TABLE_FOUND`.
- Not in R06: token refresh and secure storage (R07), OCR polling (R13/R16).

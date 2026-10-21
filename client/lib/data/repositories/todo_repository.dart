import '../api/api_client.dart';
import '../models/models.dart';

/// Todos and deadlines (D1–D5).
abstract interface class TodoRepository {
  Future<Paginated<Todo>> listTodos({
    TodoQuery query = const TodoQuery(),
    int? limit,
    String? cursor,
  });

  Future<Todo> createTodo(TodoCreate todo);

  Future<Todo> getTodo(String id);

  Future<Todo> updateTodo(String id, TodoUpdate update);

  Future<void> deleteTodo(String id);
}

class ApiTodoRepository implements TodoRepository {
  ApiTodoRepository(this._client);

  final ApiClient _client;

  @override
  Future<Paginated<Todo>> listTodos({
    TodoQuery query = const TodoQuery(),
    int? limit,
    String? cursor,
  }) async {
    final body = await _client.get(
      'todos',
      query: {...query.toQuery(), 'limit': limit, 'cursor': cursor},
    );
    return Paginated.fromJson(body, Todo.fromJson);
  }

  @override
  Future<Todo> createTodo(TodoCreate todo) async =>
      Todo.fromJson(await _client.post('todos', body: todo.toJson()) as Json);

  @override
  Future<Todo> getTodo(String id) async =>
      Todo.fromJson(await _client.get('todos/$id') as Json);

  @override
  Future<Todo> updateTodo(String id, TodoUpdate update) async => Todo.fromJson(
    await _client.patch('todos/$id', body: update.toJson()) as Json,
  );

  @override
  Future<void> deleteTodo(String id) => _client.delete('todos/$id');
}

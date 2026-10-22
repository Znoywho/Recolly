import 'dart:typed_data';

import '../api/api_client.dart';
import '../models/models.dart';

/// OCR upload and timetable CRUD (T1–T6).
abstract interface class TimetableRepository {
  /// T1: uploads a jpg/png/heic photo (max 10 MB). Returns a queued job.
  Future<OcrJob> uploadTimetablePhoto(
    Uint8List bytes, {
    required String filename,
  });

  /// T2: current job status, with parsed subjects once succeeded.
  Future<OcrJob> getOcrJob(String jobId);

  Future<List<Subject>> listSubjects();

  /// T4: bulk save after the user reviewed the OCR result. Also creates the
  /// recurring class events on the server.
  Future<List<Subject>> saveSubjects(
    List<SubjectDraft> subjects, {
    bool replaceExisting = false,
  });

  Future<Subject> updateSubject(String id, SubjectUpdate update);

  Future<void> deleteSubject(String id);
}

class ApiTimetableRepository implements TimetableRepository {
  ApiTimetableRepository(this._client);

  final ApiClient _client;

  @override
  Future<OcrJob> uploadTimetablePhoto(
    Uint8List bytes, {
    required String filename,
  }) async {
    final body = await _client.postMultipart(
      'ocr/timetable',
      field: 'image',
      bytes: bytes,
      filename: filename,
    );
    return OcrJob.fromJson(body as Json);
  }

  @override
  Future<OcrJob> getOcrJob(String jobId) async =>
      OcrJob.fromJson(await _client.get('ocr/jobs/$jobId') as Json);

  @override
  Future<List<Subject>> listSubjects() async =>
      parseItems(await _client.get('timetable'), Subject.fromJson);

  @override
  Future<List<Subject>> saveSubjects(
    List<SubjectDraft> subjects, {
    bool replaceExisting = false,
  }) async {
    final body = await _client.post(
      'timetable',
      body: {
        'subjects': [for (final s in subjects) s.toJson()],
        'replace_existing': replaceExisting,
      },
    );
    return parseItems(body, Subject.fromJson);
  }

  @override
  Future<Subject> updateSubject(String id, SubjectUpdate update) async =>
      Subject.fromJson(
        await _client.patch('timetable/$id', body: update.toJson()) as Json,
      );

  @override
  Future<void> deleteSubject(String id) => _client.delete('timetable/$id');
}

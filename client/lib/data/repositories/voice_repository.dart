import 'dart:typed_data';

import '../api/api_client.dart';
import '../models/models.dart';

/// Voice input (V1). The returned draft is not saved.
abstract interface class VoiceRepository {
  /// Uploads an m4a/wav/ogg recording (max 25 MB, 60s). [referenceTime]
  /// (device "now") resolves relative dates such as "thứ sáu".
  Future<VoiceTranscription> transcribe(
    Uint8List audio, {
    required String filename,
    DateTime? referenceTime,
  });
}

class ApiVoiceRepository implements VoiceRepository {
  ApiVoiceRepository(this._client);

  final ApiClient _client;

  @override
  Future<VoiceTranscription> transcribe(
    Uint8List audio, {
    required String filename,
    DateTime? referenceTime,
  }) async {
    final body = await _client.postMultipart(
      'voice/transcribe',
      field: 'audio',
      bytes: audio,
      filename: filename,
      fields: {
        if (referenceTime != null)
          'reference_time': formatDateTime(referenceTime),
      },
    );
    return VoiceTranscription.fromJson(body as Json);
  }
}

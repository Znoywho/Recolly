import 'package:client/data/data.dart';
import 'package:google_sign_in/google_sign_in.dart';

// GoogleSignIn.initialize must run only once in the whole app.
// Login (R07) and Google Calendar sheet (R32) both use this.
bool _googleReady = false;

Future<void> ensureGoogleReady() async {
  if (_googleReady) return;
  await GoogleSignIn.instance.initialize(
    serverClientId: ApiConfig.googleServerClientId,
  );
  _googleReady = true;
}

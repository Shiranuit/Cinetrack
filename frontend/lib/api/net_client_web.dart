import 'package:http/browser_client.dart';
import 'package:http/http.dart' as http;

/// Web: send credentials (the httpOnly refresh cookie) on cross-origin requests
/// to the API. Requires the server to allow the exact origin + credentials (CORS).
http.Client createNetClient() => BrowserClient()..withCredentials = true;

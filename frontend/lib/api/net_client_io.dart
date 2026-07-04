import 'package:http/http.dart' as http;

/// Native (mobile/desktop): a plain client. Auth travels in the Authorization
/// header; there are no browser cookies to manage.
http.Client createNetClient() => http.Client();

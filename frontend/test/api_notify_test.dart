import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:frontend/api/api_client.dart';
import 'package:frontend/api/models.dart';

/// `ApiClient` is also the app's "something changed, reload" signal: screens listen
/// to it and refetch. That makes the notification rule load-bearing — a READ that
/// notifies causes a screen to reload, which issues the read again, forever. So
/// only genuine writes may notify.
void main() {
  late HttpServer server;
  late ApiClient api;
  late List<String> hits;

  setUp(() async {
    hits = [];
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((req) async {
      hits.add('${req.method} ${req.uri.path}');
      req.response
        ..statusCode = 200
        ..headers.contentType = ContentType.json
        ..write(req.uri.path.endsWith('library-sections') ? '[]' : jsonEncode({'blocks': []}));
      // (The exact body doesn't matter here; these tests assert on method, path
      // and whether the change signal fired.)
      await req.response.close();
    });
    api = ApiClient(base: 'http://127.0.0.1:${server.port}');
  });

  tearDown(() async => server.close(force: true));

  test('a real write still fires it', () async {
    var notifications = 0;
    api.addListener(() => notifications++);

    await api.setProfileBlocks(['stats']);

    expect(hits, ['PUT /api/me/profile-blocks']);
    expect(notifications, 1, reason: 'writes must still tell open screens to refresh');
  });

  test('saving the Library layout does not fire it', () async {
    // The layout says which categories are DRAWN, not what is in them. Notifying
    // would make every switch flip in the customize sheet refetch the whole
    // library and movie list — and the sheet auto-saves, so that is per gesture.
    var notifications = 0;
    api.addListener(() => notifications++);

    await api.setLibrarySections(const [LibrarySection(builtin: 'watching')]);

    expect(hits, ['PUT /api/me/library-sections'], reason: 'the write still happens');
    expect(notifications, 0);
  });

  test('changing which category shows land in DOES fire it', () async {
    // The counterpart to the layout save: this one moves shows between
    // categories, so an open Library is showing the wrong ones until it reloads.
    var notifications = 0;
    api.addListener(() => notifications++);

    await api.setKeepUpcomingInToWatch(true);

    expect(hits, ['PUT /api/me/keep-upcoming-in-to-watch']);
    expect(notifications, 1);
  });
}

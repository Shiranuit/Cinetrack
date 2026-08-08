import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:frontend/api/api_client.dart';

/// `ApiClient` is also the app's "something changed, reload" signal: screens listen
/// to it and refetch. That makes the notification rule load-bearing — a READ that
/// notifies causes a screen to reload, which issues the read again, forever.
///
/// The Library hit exactly that: its custom rails are fetched with a POST (a batch
/// of filters), and every authenticated POST used to notify.
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
        // Shapes both endpoints under test accept.
        ..write(req.uri.path.contains('batch') ? '[]' : jsonEncode({'blocks': []}));
      await req.response.close();
    });
    api = ApiClient(base: 'http://127.0.0.1:${server.port}');
  });

  tearDown(() async => server.close(force: true));

  test('the batched library filter does not fire the change signal', () async {
    var notifications = 0;
    api.addListener(() => notifications++);

    await api.librarySectionsItems([
      (key: 'section-1|series', filters: const {'type': 'series', 'state': 'watching'}),
    ]);

    expect(hits, ['POST /api/library/filter/batch'], reason: 'one request, not a storm');
    expect(
      notifications,
      0,
      reason: 'notifying here makes the Library reload, which re-issues this very request',
    );
  });

  test('a real write still fires it', () async {
    var notifications = 0;
    api.addListener(() => notifications++);

    await api.setProfileBlocks(['stats']);

    expect(notifications, 1, reason: 'writes must still tell open screens to refresh');
  });

  test('an empty batch does not reach the network at all', () async {
    final result = await api.librarySectionsItems(const []);
    expect(result, isEmpty);
    expect(hits, isEmpty, reason: 'nothing to ask for');
  });
}

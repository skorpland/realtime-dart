import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:realtime_client/realtime_client.dart';
import 'package:test/test.dart';

void main() {
  late RealtimeClient client;
  late HttpServer mockServer;
  WebSocket? webSocket;
  bool hasListener = false;
  bool hasSentData = false;
  StreamSubscription<dynamic>? listener;

  // Version of realtime after adding broadcast and presence
  Future<void> handleMultitenantRealtimeRequests(HttpServer server) async {
    await for (final HttpRequest request in server) {
      final url = request.uri.toString();
      if (url.contains('realtime')) {
        webSocket = await WebSocketTransformer.upgrade(request);
        if (hasListener) {
          return;
        }
        hasListener = true;
        listener = webSocket!.listen((request) async {
          if (hasSentData) {
            return;
          }
          hasSentData = true;

          /// `filter` might be there or not depending on whether is a filter set
          /// to the realtime subscription, so include the filter if the request
          /// includes a filter.
          final requestJson = jsonDecode(request);
          final String? postgresFilter = requestJson['payload']['config']
                  ['postgres_changes']
              .first['filter'];

          final replyString = jsonEncode({
            'event': 'phx_reply',
            'payload': {
              'response': {
                'postgres_changes': [
                  {
                    'id': 77086988,
                    'event': 'INSERT',
                    'schema': 'public',
                    'table': 'todos',
                    if (postgresFilter != null) 'filter': postgresFilter,
                  },
                  {
                    'id': 25993878,
                    'event': 'UPDATE',
                    'schema': 'public',
                    'table': 'todos',
                    if (postgresFilter != null) 'filter': postgresFilter,
                  },
                  {
                    'id': 48673474,
                    'event': 'DELETE',
                    'schema': 'public',
                    'table': 'todos',
                    if (postgresFilter != null) 'filter': postgresFilter,
                  }
                ]
              },
              'status': 'ok'
            },
            'ref': '1',
            'topic': 'realtime:public:todos'
          });
          webSocket!.add(replyString);

          final topic = (jsonDecode(request as String) as Map)['topic'];

          // Send an insert event
          if (postgresFilter == null) {
            await Future.delayed(Duration(milliseconds: 300));
            final insertString = jsonEncode({
              'topic': topic,
              'event': 'postgres_changes',
              'ref': null,
              'payload': {
                'ids': [77086988],
                'data': {
                  'commit_timestamp': '2021-08-01T08:00:20Z',
                  'record': {'id': 3, 'task': 'task 3', 'status': 't'},
                  'schema': 'public',
                  'table': 'todos',
                  'type': 'INSERT',
                  if (postgresFilter != null) 'filter': postgresFilter,
                  'columns': [
                    {
                      'name': 'id',
                      'type': 'int4',
                      'type_modifier': 4294967295,
                    },
                    {
                      'name': 'task',
                      'type': 'text',
                      'type_modifier': 4294967295,
                    },
                    {
                      'name': 'status',
                      'type': 'bool',
                      'type_modifier': 4294967295,
                    },
                  ],
                },
              },
            });
            webSocket!.add(insertString);
          }

          // Send an update event for id = 2
          await Future.delayed(Duration(milliseconds: 10));
          final updateString = jsonEncode({
            'topic': topic,
            'ref': null,
            'event': 'postgres_changes',
            'payload': {
              'ids': [25993878],
              'data': {
                'columns': [
                  {'name': 'id', 'type': 'int4', 'type_modifier': 4294967295},
                  {'name': 'task', 'type': 'text', 'type_modifier': 4294967295},
                  {
                    'name': 'status',
                    'type': 'bool',
                    'type_modifier': 4294967295
                  },
                ],
                'commit_timestamp': '2021-08-01T08:00:30Z',
                'errors': null,
                'old_record': {'id': 2},
                'record': {'id': 2, 'task': 'task 2 updated', 'status': 'f'},
                'schema': 'public',
                'table': 'todos',
                'type': 'UPDATE',
                if (postgresFilter != null) 'filter': postgresFilter,
              },
            },
          });
          webSocket!.add(updateString);

          // Send delete event for id=2
          await Future.delayed(Duration(milliseconds: 10));
          final deleteString = jsonEncode({
            'ref': null,
            'topic': topic,
            'event': 'postgres_changes',
            'payload': {
              'data': {
                'columns': [
                  {'name': 'id', 'type': 'int4', 'type_modifier': 4294967295},
                  {'name': 'task', 'type': 'text', 'type_modifier': 4294967295},
                  {
                    'name': 'status',
                    'type': 'bool',
                    'type_modifier': 4294967295
                  },
                ],
                'commit_timestamp': '2022-09-14T02:12:52Z',
                'errors': null,
                'old_record': {'id': 2},
                'schema': 'public',
                'table': 'todos',
                'type': 'DELETE',
                if (postgresFilter != null) 'filter': postgresFilter,
              },
              'ids': [48673474]
            },
          });
          webSocket!.add(deleteString);
        });
      } else {
        request.response
          ..statusCode = HttpStatus.ok
          ..close();
      }
    }
  }

  tearDown(() async {
    await client.removeAllChannels();

    listener?.cancel();

    // Wait for the realtime updates to come through
    await Future.delayed(Duration(milliseconds: 100));

    await webSocket?.close();
    await mockServer.close();
  });

  group('Multitenant Realtime', () {
    setUp(() async {
      mockServer = await HttpServer.bind('localhost', 0);
      client = RealtimeClient(
        'ws://${mockServer.address.host}:${mockServer.port}/realtime/v1',
        params: {'apikey': 'powerbaseKey'},
      );
      hasListener = false;
      hasSentData = false;
      handleMultitenantRealtimeRequests(mockServer);
    });

    test('.on()', () {
      final streamController = StreamController<Map<String, dynamic>>();

      client.channel('public:todoos').on(RealtimeListenTypes.postgresChanges,
          ChannelFilter(event: '*', schema: 'public', table: 'todos'), (payload,
              [ref]) {
        streamController.add(payload);
      }).subscribe();

      expect(
        streamController.stream,
        emitsInOrder([
          {
            'schema': 'public',
            'table': 'todos',
            'commit_timestamp': '2021-08-01T08:00:20Z',
            'eventType': 'INSERT',
            'new': {'id': 3, 'task': 'task 3', 'status': true},
            'old': {},
            'errors': null
          },
          {
            'schema': 'public',
            'table': 'todos',
            'commit_timestamp': '2021-08-01T08:00:30Z',
            'eventType': 'UPDATE',
            'new': {'id': 2, 'task': 'task 2 updated', 'status': false},
            'old': {'id': 2},
            'errors': null
          },
          {
            'schema': 'public',
            'table': 'todos',
            'commit_timestamp': '2022-09-14T02:12:52Z',
            'eventType': 'DELETE',
            'new': {},
            'old': {'id': 2},
            'errors': null
          },
        ]),
      );
    });

    test('.on() with filter', () {
      final streamController = StreamController<Map<String, dynamic>>();

      client.channel('public:todoos').on(
          RealtimeListenTypes.postgresChanges,
          ChannelFilter(
              event: '*',
              schema: 'public',
              table: 'todos',
              filter: 'id=eq.2'), (payload, [ref]) {
        streamController.add(payload);
      }).subscribe();

      expect(
        streamController.stream,
        emitsInOrder([
          {
            'schema': 'public',
            'table': 'todos',
            'commit_timestamp': '2021-08-01T08:00:30Z',
            'eventType': 'UPDATE',
            'new': {'id': 2, 'task': 'task 2 updated', 'status': false},
            'old': {'id': 2},
            'errors': null
          },
          {
            'schema': 'public',
            'table': 'todos',
            'commit_timestamp': '2022-09-14T02:12:52Z',
            'eventType': 'DELETE',
            'new': {},
            'old': {'id': 2},
            'errors': null
          },
        ]),
      );
    });
  });

  // Version of realtime prior to adding broadcast and presence.
  // Will be deprecated at some point.
  Future<void> handleSingleTenantRealtimeRequests(HttpServer server) async {
    await for (final HttpRequest request in server) {
      final url = request.uri.toString();
      if (url.contains('realtime')) {
        webSocket = await WebSocketTransformer.upgrade(request);
        if (hasListener) {
          return;
        }
        hasListener = true;
        listener = webSocket!.listen((request) async {
          if (hasSentData) {
            return;
          }
          hasSentData = true;

          /// `filter` might be there or not depending on whether is a filter set
          /// to the realtime subscription, so include the filter if the request
          /// includes a filter.
          final requestJson = jsonDecode(request);

          final String? postgresFilter = requestJson['payload']['config']
                  ['postgres_changes']
              .first['filter'];

          final topic = requestJson['topic'];

          final replyString = jsonEncode({
            "event": "phx_reply",
            "payload": {"response": {}, "status": "ok"},
            "ref": "1",
            "topic": topic
          });
          webSocket!.add(replyString);

          // Send an insert event
          if (postgresFilter == null) {
            await Future.delayed(Duration(milliseconds: 300));
            final insertString = jsonEncode({
              "event": "INSERT",
              "payload": {
                "columns": [
                  {"name": "id", "type": "int4"},
                  {"name": "task", "type": "text"},
                  {"name": "status", "type": "bool"}
                ],
                "commit_timestamp": "2022-09-24T05:42:01.303668+00:00",
                "errors": null,
                "record": {"id": 1, "status": true, "task": "task 1"},
                "schema": "public",
                "table": "todos",
                "type": "INSERT"
              },
              "ref": null,
              "topic": topic
            });
            webSocket!.add(insertString);
          }

          // Send an update event for id = 2
          await Future.delayed(Duration(milliseconds: 10));
          final updateString = jsonEncode({
            "event": "UPDATE",
            "payload": {
              "columns": [
                {"name": "id", "type": "int4"},
                {"name": "task", "type": "text"},
                {"name": "status", "type": "bool"}
              ],
              "commit_timestamp": "2022-09-24T05:42:01.303668+00:00",
              "errors": null,
              "old_record": {"id": 2},
              "record": {"id": 2, "status": false, "task": "task 2 updated"},
              "schema": "public",
              "table": "todos",
              "type": "UPDATE"
            },
            "ref": null,
            "topic": topic
          });
          webSocket!.add(updateString);

          // Send delete event for id=2
          await Future.delayed(Duration(milliseconds: 10));
          final deleteString = jsonEncode({
            "event": "DELETE",
            "payload": {
              "columns": [
                {"name": "id", "type": "int4"},
                {"name": "task", "type": "text"},
                {"name": "status", "type": "bool"}
              ],
              "commit_timestamp": "2022-09-24T05:42:01.303668+00:00",
              "errors": null,
              "old_record": {"id": 2},
              "record": {},
              "schema": "public",
              "table": "todos",
              "type": "DELETE"
            },
            "ref": null,
            "topic": topic
          });
          webSocket!.add(deleteString);
        });
      } else {
        request.response
          ..statusCode = HttpStatus.ok
          ..close();
      }
    }
  }

  group('Singletenant Realtime', () {
    setUp(() async {
      mockServer = await HttpServer.bind('localhost', 0);
      client = RealtimeClient(
        'ws://${mockServer.address.host}:${mockServer.port}/realtime/v1',
        params: {'apikey': 'powerbaseKey'},
      );
      hasListener = false;
      hasSentData = false;
      handleSingleTenantRealtimeRequests(mockServer);
    });

    test('.on()', () {
      final streamController = StreamController<Map<String, dynamic>>();

      client.channel('public:todoos').on(RealtimeListenTypes.postgresChanges,
          ChannelFilter(event: '*', schema: 'public', table: 'todos'), (payload,
              [ref]) {
        streamController.add(payload);
      }).subscribe();

      expect(
        streamController.stream,
        emitsInOrder([
          {
            'schema': 'public',
            'table': 'todos',
            'commit_timestamp': '2022-09-24T05:42:01.303668+00:00',
            'eventType': 'INSERT',
            'new': {'id': 1, 'task': 'task 1', 'status': true},
            'old': {},
            'errors': null
          },
          {
            'schema': 'public',
            'table': 'todos',
            'commit_timestamp': '2022-09-24T05:42:01.303668+00:00',
            'eventType': 'UPDATE',
            'new': {'id': 2, 'task': 'task 2 updated', 'status': false},
            'old': {'id': 2},
            'errors': null
          },
          {
            'schema': 'public',
            'table': 'todos',
            'commit_timestamp': '2022-09-24T05:42:01.303668+00:00',
            'eventType': 'DELETE',
            'new': {},
            'old': {'id': 2},
            'errors': null
          },
        ]),
      );
    });

    test('.on() with filter', () {
      final streamController = StreamController<Map<String, dynamic>>();

      client.channel('public:todoos').on(
          RealtimeListenTypes.postgresChanges,
          ChannelFilter(
              event: '*',
              schema: 'public',
              table: 'todos',
              filter: 'id=eq.2'), (payload, [ref]) {
        streamController.add(payload);
      }).subscribe();

      expect(
        streamController.stream,
        emitsInOrder([
          {
            'schema': 'public',
            'table': 'todos',
            'commit_timestamp': '2022-09-24T05:42:01.303668+00:00',
            'eventType': 'UPDATE',
            'new': {'id': 2, 'task': 'task 2 updated', 'status': false},
            'old': {'id': 2},
            'errors': null
          },
          {
            'schema': 'public',
            'table': 'todos',
            'commit_timestamp': '2022-09-24T05:42:01.303668+00:00',
            'eventType': 'DELETE',
            'new': {},
            'old': {'id': 2},
            'errors': null
          },
        ]),
      );
    });
  });
}

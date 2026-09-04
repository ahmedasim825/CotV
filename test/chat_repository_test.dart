// The durable transcript behind Milo's memory.
//
// The ordering is the whole point of these tests. Hive returns values in
// key order and the keys are UUIDs, so "the last twelve turns" is only
// correct because the repository sorts by timestamp — and Milo's recall
// block would otherwise present the conversation shuffled.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';

import 'package:cotv/hive_registrar.g.dart';
import 'package:cotv/src/models/chat_message.dart';
import 'package:cotv/src/repositories/chat_repository.dart';

void main() {
  late Directory tempDir;
  late Box<ChatMessage> box;
  late ChatRepository repository;

  final start = DateTime(2026, 9, 2, 9);

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('cotv_chat_test_');
    Hive.init(tempDir.path);
    if (!Hive.isAdapterRegistered(10)) {
      Hive.registerAdapters();
    }
    box = await Hive.openBox<ChatMessage>('test_chat');
    repository = HiveChatRepository(box);
  });

  tearDown(() async {
    await box.close();
    await Hive.deleteBoxFromDisk('test_chat', path: tempDir.path);
    await tempDir.delete(recursive: true);
  });

  /// [count] alternating turns, `m0` oldest.
  Future<void> seed(int count) async {
    for (var i = 0; i < count; i++) {
      await repository.append(
        ChatMessage(
          id: 'm$i',
          isUser: i.isEven,
          text: 'turn $i',
          timestamp: start.add(Duration(minutes: i)),
        ),
      );
    }
  }

  test('recent returns the newest turns, oldest first', () async {
    await seed(20);

    final recent = repository.recent(4);
    expect([for (final m in recent) m.text],
        ['turn 16', 'turn 17', 'turn 18', 'turn 19']);
  });

  test('recent returns everything when there is less than asked for',
      () async {
    await seed(3);

    expect(repository.recent(12), hasLength(3));
    expect(repository.recent(12).first.text, 'turn 0');
  });

  test('orders by timestamp, not by the key it was stored under', () async {
    // Written out of order under keys that sort the wrong way — the shape
    // UUID keys produce in practice.
    await repository.append(ChatMessage(
      id: 'zzz',
      isUser: true,
      text: 'asked first',
      timestamp: start,
    ));
    await repository.append(ChatMessage(
      id: 'aaa',
      isUser: false,
      text: 'answered second',
      timestamp: start.add(const Duration(minutes: 1)),
    ));

    expect(
      [for (final m in repository.recent(10)) m.text],
      ['asked first', 'answered second'],
    );
  });

  test('recent(0) and a negative window return nothing', () async {
    await seed(5);

    expect(repository.recent(0), isEmpty);
    expect(repository.recent(-3), isEmpty);
  });

  test('count tracks the whole transcript, not the recall window', () async {
    await seed(25);

    expect(repository.count, 25);
    expect(repository.recent(12), hasLength(12));
  });

  test('appending the same id replaces rather than duplicates', () async {
    // The reply is stored under the panel's message id, and a turn is only
    // persisted once — but an id collision must overwrite, not fork.
    await repository.append(ChatMessage(
      id: 'reply',
      isUser: false,
      text: 'first',
      timestamp: start,
    ));
    await repository.append(ChatMessage(
      id: 'reply',
      isUser: false,
      text: 'second',
      timestamp: start,
    ));

    expect(repository.count, 1);
    expect(repository.recent(1).single.text, 'second');
  });

  test('clear empties the transcript', () async {
    await seed(5);
    await repository.clear();

    expect(repository.count, 0);
    expect(repository.recent(12), isEmpty);
  });
}

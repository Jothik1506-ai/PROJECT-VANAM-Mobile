import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:vanam_mobile/chat/chat_controller.dart';

class _FakePathProviderPlatform extends PathProviderPlatform {
  _FakePathProviderPlatform(this._path);
  final String _path;

  @override
  Future<String?> getApplicationSupportPath() async => _path;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('vanam_chat_test_');
    PathProviderPlatform.instance = _FakePathProviderPlatform(tempDir.path);
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  test('load() on a fresh device starts empty, not an error', () async {
    final controller = ChatController(fileName: 'chat.json');
    await controller.load();
    expect(controller.value, isEmpty);
  });

  test('sendLocalMessage appends and marks the message as mine', () async {
    final controller = ChatController(fileName: 'chat.json');
    await controller.load();

    await controller.sendLocalMessage(text: 'Dinner at 8', senderName: 'Amma');

    expect(controller.value, hasLength(1));
    expect(controller.value.single.text, 'Dinner at 8');
    expect(controller.value.single.senderName, 'Amma');
    expect(controller.value.single.isMine, isTrue);
  });

  test('blank messages are not sent', () async {
    final controller = ChatController(fileName: 'chat.json');
    await controller.load();

    await controller.sendLocalMessage(text: '   ', senderName: 'Amma');

    expect(controller.value, isEmpty);
  });

  test('falls back to "You" when sender name is blank', () async {
    final controller = ChatController(fileName: 'chat.json');
    await controller.load();

    await controller.sendLocalMessage(text: 'hi', senderName: '  ');

    expect(controller.value.single.senderName, 'You');
  });

  test('messages survive a restart (persist to disk, reload in a new '
      'controller instance)', () async {
    final first = ChatController(fileName: 'chat.json');
    await first.load();
    await first.sendLocalMessage(text: 'On my way home', senderName: 'Thammudu');
    await first.sendLocalMessage(text: 'See you soon!', senderName: 'You');

    // Simulate an app restart: a brand new controller, same backing file.
    final second = ChatController(fileName: 'chat.json');
    await second.load();

    expect(second.value, hasLength(2));
    expect(second.value.first.text, 'On my way home');
    expect(second.value.last.text, 'See you soon!');
  });

  test('a corrupt local file starts empty instead of crashing', () async {
    final file = File('${tempDir.path}${Platform.pathSeparator}chat.json');
    file.writeAsStringSync('{ not valid json at all');

    final controller = ChatController(fileName: 'chat.json');
    await controller.load();

    expect(controller.value, isEmpty);
  });

  test('different chat files stay isolated from each other', () async {
    final familyGroup = ChatController(fileName: 'family.json');
    final other = ChatController(fileName: 'other.json');
    await familyGroup.load();
    await other.load();

    await familyGroup.sendLocalMessage(text: 'group message', senderName: 'You');

    expect(familyGroup.value, hasLength(1));
    expect(other.value, isEmpty);
  });
}

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:comfer_wallpaper/services/wallpaper_service.dart';
import 'package:comfer_wallpaper/services/wallpaper_store.dart';

class Desktop implements WallpaperPlatform {
  Set<String> paths = {'/external/original.jpg'};
  bool fail = false;
  int applications = 0;
  Completer<void>? gate;
  @override
  Future<Set<String>> currentPaths() async => paths;
  @override
  Future<void> apply(String path) async {
    applications++;
    await gate?.future;
    if (fail) throw StateError('Desktop refused');
    paths = {path};
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late WallpaperStore store;
  late Desktop desktop;
  late WallpaperService service;
  var networkFails = false;
  var rejectImage = false;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('comfer-test-');
    store = WallpaperStore(directory);
    desktop = Desktop();
    networkFails = false;
    rejectImage = false;
    service = WallpaperService(
        store: store,
        platform: desktop,
        userId: 'test',
        validate: (_) async {
          if (rejectImage) throw const FormatException('Invalid image');
          return 'jpg';
        },
        client: MockClient((request) async {
          if (networkFails) return http.Response('unavailable', 503);
          return request.url.path == '/api'
              ? http.Response(
                  jsonEncode({'imageUrl': 'https://example.com/image.jpg'}),
                  200)
              : http.Response.bytes([1, 2, 3], 200);
        }));
    await service.initialize();
  });
  tearDown(() async {
    await service.close();
    await directory.delete(recursive: true);
  });

  test(
      'successful replacement leaves one owned image and preserves unknown files',
      () async {
    final unknown = File('${directory.path}/personal.jpg');
    await unknown.writeAsString('mine');
    await service.change();
    final previous = store.file(store.current!);
    await service.change();
    expect(await previous.exists(), isFalse);
    expect(store.owned, [store.current]);
    expect(desktop.paths, {store.file(store.current!).path});
    expect(await unknown.readAsString(), 'mine');
  });
  test('HTTP failure never applies an old wallpaper or advances success',
      () async {
    await service.change();
    final previous = store.current;
    final success = store.lastSuccess;
    networkFails = true;
    await expectLater(service.change(), throwsA(isA<HttpException>()));
    expect(desktop.applications, 1);
    expect(store.current, previous);
    expect(store.lastSuccess, success);
    expect(await store.file(previous!).exists(), isTrue);
  });
  test(
      'failed apply preserves old file and journal; recovery safely rolls forward',
      () async {
    await service.change();
    final previous = store.current;
    desktop.fail = true;
    await expectLater(service.change(), throwsStateError);
    expect(store.current, previous);
    expect(store.pending, isNotNull);
    expect(await store.file(previous!).exists(), isTrue);
    final candidate = store.pending;
    await expectLater(service.recover(), throwsStateError);
    expect(await store.file(previous).exists(), isTrue);
    desktop.fail = false;
    await service.recover();
    expect(store.pending, isNull);
    expect(store.current, candidate);
    expect(store.owned, [candidate]);
  });
  test('crash after OS apply is reconciled from desktop state', () async {
    await service.change();
    final old = store.current!;
    const candidate = 'comfer-recovered.jpg';
    await store.track(candidate);
    await store.file(candidate).writeAsString('image');
    await store.begin(candidate);
    desktop.paths = {store.file(candidate).path};
    await store.load();
    await service.recover();
    expect(store.current, candidate);
    expect(store.pending, isNull);
    expect(await store.file(old).exists(), isFalse);
  });
  test('concurrent requests share one operation', () async {
    desktop.gate = Completer<void>();
    final a = service.change();
    final b = service.change();
    expect(identical(a, b), isTrue);
    desktop.gate!.complete();
    await Future.wait([a, b]);
    expect(desktop.applications, 1);
  });
  test('corrupt manifest cannot escape managed directory', () async {
    await store.manifest.writeAsString(jsonEncode({
      'owned': ['../personal.jpg']
    }));
    await expectLater(store.load(), throwsFormatException);
    await expectLater(service.change(), throwsFormatException);
    expect(desktop.applications, 0);
  });
  test('cleanup refuses a symlink and preserves its target', () async {
    final target = File('${directory.path}/personal.jpg');
    await target.writeAsString('mine');
    const name = 'comfer-link.jpg';
    await store.track(name);
    await Link(store.file(name).path).create(target.path);
    await expectLater(store.cleanup({}), throwsA(isA<FileSystemException>()));
    expect(await target.readAsString(), 'mine');
  });
  test('real decoder rejects HTML disguised as an image', () async {
    final file = File('${directory.path}/invalid.jpg');
    await file.writeAsString('<html>error</html>');
    await expectLater(
        WallpaperService.validateImage(file), throwsFormatException);
  });
  test('real decoder accepts a valid PNG', () async {
    final file = File('${directory.path}/valid.png');
    await file
        .writeAsBytes(await File('assets/comfer_launcher.png').readAsBytes());
    expect(await WallpaperService.validateImage(file), 'png');
  });
  test('closed service refuses new downloads', () async {
    await service.close();
    await expectLater(service.change(), throwsStateError);
    expect(desktop.applications, 0);
  });
  test('invalid image never replaces the working wallpaper', () async {
    await service.change();
    final previous = store.current;
    rejectImage = true;
    await expectLater(service.change(), throwsFormatException);
    expect(store.current, previous);
    expect(store.owned, [previous]);
    expect(desktop.applications, 1);
  });
  test('missing current file makes the next startup immediately due', () async {
    await service.change();
    await store.file(store.current!).delete();
    await store.load();
    expect(store.current, isNull);
    expect(store.lastSuccess, isNull);
  });
}

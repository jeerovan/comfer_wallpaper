import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';
import 'wallpaper_store.dart';

abstract interface class WallpaperPlatform {
  Future<Set<String>> currentPaths();
  Future<void> apply(String path);
}

/// Adapters with multiple settings can require all settings to agree.
abstract interface class WallpaperConfirmation {
  bool confirms(Set<String> paths, String candidate);
}

class WallpaperService {
  WallpaperService(
      {required this.store,
      required this.platform,
      required this.userId,
      required this.client,
      DateTime Function()? now,
      Future<String> Function(File)? validate})
      : now = now ?? DateTime.now,
        validate = validate ?? validateImage;
  final WallpaperStore store;
  final WallpaperPlatform platform;
  final String userId;
  final http.Client client;
  final DateTime Function() now;
  final Future<String> Function(File) validate;
  Future<void>? _active;
  bool _closed = false;
  Completer<void>? _abort;
  String? cleanupWarning;

  Future<void> initialize() async {
    await store.load();
    await recover();
  }

  bool _confirms(Set<String> paths, String candidate) =>
      platform is WallpaperConfirmation
          ? (platform as WallpaperConfirmation).confirms(paths, candidate)
          : paths.contains(candidate);

  Future<bool> recover() async {
    var paths = await platform.currentPaths();
    final pending = store.pending;
    if (pending != null) {
      await store.requireRegular(pending);
      if (!_confirms(paths, store.file(pending).path)) {
        // A setter can complete asynchronously after a crash. Roll forward
        // rather than deleting an image the desktop may still be adopting.
        await platform.apply(store.file(pending).path);
        paths = await _confirmedPaths(store.file(pending).path);
      }
      await store.commit(pending, now());
    }
    await _cleanup(paths);
    return pending != null;
  }

  Future<void> _cleanup(Set<String> paths) async {
    try {
      await store.cleanup(paths);
      cleanupWarning = null;
    } catch (_) {
      cleanupWarning =
          'Wallpaper changed, but old-file cleanup needs another attempt.';
    }
  }

  Future<void> change() {
    if (_closed) {
      return Future.error(StateError('Wallpaper service is stopping'));
    }
    return _active ??= _change().whenComplete(() => _active = null);
  }

  Future<void> _change() async {
    // Reload before every transaction: an unreadable/corrupt journal must stop
    // writes, rather than being replaced by an empty in-memory state.
    await store.load();
    if (await recover()) return;
    if (cleanupWarning != null) {
      throw StateError(
          'Old wallpaper cleanup must succeed before downloading another image');
    }
    final uri = Uri.https('comfer.jeerovan.com', '/api', {
      'view': 'landscape',
      'name': userId,
      'hour': now().toUtc().hour.toString().padLeft(2, '0'),
    });
    final metadata = await _read(uri, 1024 * 1024);
    final json = jsonDecode(utf8.decode(metadata));
    final url = json is Map ? json['imageUrl'] : null;
    final imageUri = url is String ? Uri.tryParse(url) : null;
    if (imageUri == null ||
        imageUri.scheme != 'https' ||
        imageUri.host.isEmpty) {
      throw const FormatException(
          'The wallpaper API returned an invalid image URL');
    }
    final id = const Uuid().v4();
    final part = 'comfer-$id.part';
    await store.track(part);
    try {
      await _read(imageUri, 30 * 1024 * 1024, destination: store.file(part));
      if (_closed) throw StateError('Download cancelled');
      final extension = await validate(store.file(part));
      final candidate = 'comfer-$id.$extension';
      await store.track(candidate);
      await store.file(part).rename(store.file(candidate).path);
      if (_closed) throw StateError('Download cancelled');
      await store.begin(candidate);
      await platform.apply(store.file(candidate).path);
      final paths = await _confirmedPaths(store.file(candidate).path);
      await store.commit(candidate, now());
      await _cleanup(paths);
    } catch (_) {
      // If applying may have had side effects, leave the journal for recovery.
      // A subsequent read of platform state decides which files are safe to remove.
      if (store.pending == null) {
        try {
          await _cleanup(await platform.currentPaths());
        } catch (_) {/* Retry later. */}
      }
      rethrow;
    }
  }

  Future<Set<String>> _confirmedPaths(String candidate) async {
    var paths = await platform.currentPaths();
    for (var attempt = 0;
        !_confirms(paths, candidate) && attempt < 10;
        attempt++) {
      await Future<void>.delayed(const Duration(milliseconds: 200));
      paths = await platform.currentPaths();
    }
    if (!_confirms(paths, candidate)) {
      throw StateError('The desktop did not confirm the new wallpaper');
    }
    return paths;
  }

  Future<List<int>> _read(Uri uri, int maximum, {File? destination}) async {
    final abort = Completer<void>();
    _abort = abort;
    final deadline = Timer(const Duration(minutes: 2), () {
      if (!abort.isCompleted) abort.complete();
    });
    try {
      return await _readResponse(uri, maximum, abort.future, destination);
    } finally {
      deadline.cancel();
      if (!abort.isCompleted) abort.complete();
      if (identical(_abort, abort)) _abort = null;
    }
  }

  Future<List<int>> _readResponse(
      Uri uri, int maximum, Future<void> abort, File? destination) async {
    final response = await client
        .send(http.AbortableRequest('GET', uri, abortTrigger: abort))
        .timeout(const Duration(seconds: 20));
    if (response.statusCode != 200) {
      await response.stream.listen(null).cancel();
      throw HttpException('Wallpaper request failed (${response.statusCode})');
    }
    if ((response.contentLength ?? 0) > maximum) {
      await response.stream.listen(null).cancel();
      throw const FormatException('Wallpaper response is too large');
    }
    final bytes = <int>[];
    RandomAccessFile? output;
    var received = 0;
    try {
      output = await destination?.open(mode: FileMode.write);
      await for (final chunk
          in response.stream.timeout(const Duration(seconds: 20))) {
        if (_closed) throw StateError('Download cancelled');
        received += chunk.length;
        if (received > maximum) {
          throw const FormatException('Wallpaper response is too large');
        }
        if (output == null) {
          bytes.addAll(chunk);
        } else {
          await output.writeFrom(chunk);
        }
      }
      await output?.flush();
    } finally {
      await output?.close();
    }
    if (received == 0) {
      throw const FormatException('Wallpaper response is empty');
    }
    return bytes;
  }

  Future<void> close() async {
    _closed = true;
    if (_abort != null && !_abort!.isCompleted) _abort!.complete();
    client.close();
    try {
      await _active?.timeout(const Duration(seconds: 5));
    } catch (_) {/* Journal survives exit. */}
  }

  static Future<String> validateImage(File file) async {
    final bytes = await file.readAsBytes();
    final isPng = bytes.length >= 8 &&
        bytes[0] == 137 &&
        bytes[1] == 80 &&
        bytes[2] == 78 &&
        bytes[3] == 71;
    final isJpeg = bytes.length >= 3 &&
        bytes[0] == 255 &&
        bytes[1] == 216 &&
        bytes[2] == 255;
    if (!isPng && !isJpeg) {
      throw const FormatException('Only PNG and JPEG wallpapers are supported');
    }
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    ui.ImageDescriptor? descriptor;
    ui.Codec? codec;
    try {
      descriptor = await ui.ImageDescriptor.encoded(buffer);
      if (descriptor.width * descriptor.height > 50000000) {
        throw const FormatException('Wallpaper dimensions are too large');
      }
      codec = await descriptor.instantiateCodec();
      final frame = await codec.getNextFrame();
      frame.image.dispose();
    } finally {
      codec?.dispose();
      descriptor?.dispose();
      buffer.dispose();
    }
    return isPng ? 'png' : 'jpg';
  }
}

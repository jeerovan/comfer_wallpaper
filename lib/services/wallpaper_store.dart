import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;

/// A journal is written before applying an image, so a crash never makes its
/// ownership or possible use by the desktop ambiguous.
class WallpaperStore {
  WallpaperStore(this.directory);
  final Directory directory;
  Map<String, dynamic> _state = {};
  String? get current => _state['current'] as String?;
  String? get pending => _state['pending'] as String?;
  DateTime? get lastSuccess => DateTime.tryParse(_state['lastSuccess'] ?? '');
  List<String> get owned => List<String>.from(_state['owned'] ?? []);
  File get manifest => File(p.join(directory.path, 'state.json'));

  Future<void> load() async {
    await directory.create(recursive: true);
    if (await FileSystemEntity.type(directory.path, followLinks: false) !=
        FileSystemEntityType.directory) {
      throw const FileSystemException('Wallpaper directory must not be a link');
    }
    if (await manifest.exists()) {
      if (await FileSystemEntity.type(manifest.path, followLinks: false) !=
          FileSystemEntityType.file) {
        throw const FileSystemException(
            'Wallpaper manifest must not be a link');
      }
      _state =
          Map<String, dynamic>.from(jsonDecode(await manifest.readAsString()));
      for (final name in [
        ...owned,
        if (current != null) current!,
        if (pending != null) pending!
      ]) {
        file(name); // Validate all persisted paths before any use or deletion.
      }
      if (current != null) {
        final type = await FileSystemEntity.type(file(current!).path,
            followLinks: false);
        if (type == FileSystemEntityType.notFound) {
          await save({..._state, 'current': null, 'lastSuccess': null});
        } else if (type != FileSystemEntityType.file) {
          throw const FileSystemException(
              'Active wallpaper must not be a link');
        }
      }
    }
  }

  File file(String name) {
    if (!RegExp(r'^comfer-[a-zA-Z0-9-]+\.(png|jpg|part)$').hasMatch(name) ||
        p.basename(name) != name) {
      throw const FormatException('Invalid owned wallpaper filename');
    }
    return File(p.join(directory.path, name));
  }

  Future<void> save(Map<String, dynamic> state) async {
    final temporary = File('${manifest.path}.tmp');
    final type =
        await FileSystemEntity.type(temporary.path, followLinks: false);
    if (type != FileSystemEntityType.notFound &&
        type != FileSystemEntityType.file) {
      throw const FileSystemException('Temporary manifest must not be a link');
    }
    await temporary.writeAsString(jsonEncode(state), flush: true);
    await temporary.rename(manifest.path);
    _state = state;
  }

  Future<void> track(String name) => save({
        ..._state,
        'owned': {...owned, name}.toList()
      });
  Future<void> begin(String name) => save({..._state, 'pending': name});
  Future<void> commit(String name, DateTime time) => save({
        ..._state,
        'current': name,
        'pending': null,
        'lastSuccess': time.toUtc().toIso8601String(),
      });
  Future<void> clearPending() => save({..._state, 'pending': null});

  /// Never follow symlinks. Unknown files are never deleted.
  Future<void> cleanup(Set<String> desktopPaths) async {
    final keep = <String>[];
    for (final name in owned) {
      final target = file(name);
      if (name == current ||
          name == pending ||
          desktopPaths.contains(target.path)) {
        keep.add(name);
        continue;
      }
      final type = await FileSystemEntity.type(target.path, followLinks: false);
      if (type == FileSystemEntityType.file) {
        await target.delete();
      } else if (type != FileSystemEntityType.notFound) {
        throw const FileSystemException(
            'Refusing to clean a non-file wallpaper');
      }
    }
    await save({..._state, 'owned': keep});
  }

  Future<void> requireRegular(String name) async {
    if (await FileSystemEntity.type(file(name).path, followLinks: false) !=
        FileSystemEntityType.file) {
      throw const FileSystemException(
          'Wallpaper is missing or is not a regular file');
    }
  }
}

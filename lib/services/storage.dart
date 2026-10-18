import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../core/archive.dart';

/// Impostazioni dell'app (restano sul telefono, non si sincronizzano).
class Settings {
  bool driveEnabled = false;
  bool autoSync = true;
  bool autoAsn = false;
  bool ocrEnabled = true;
  bool skipDuplicates = true;
  String? driveAccount;
  int? lastSync;
  String? lastSyncError;

  Map<String, dynamic> toJson() => {
        'drive': driveEnabled,
        'autoSync': autoSync,
        'autoAsn': autoAsn,
        'ocr': ocrEnabled,
        'dup': skipDuplicates,
        'account': driveAccount,
        'lastSync': lastSync,
        'lastErr': lastSyncError,
      };

  static Settings fromJson(Map<String, dynamic> j) => Settings()
    ..driveEnabled = j['drive'] as bool? ?? false
    ..autoSync = j['autoSync'] as bool? ?? true
    ..autoAsn = j['autoAsn'] as bool? ?? false
    ..ocrEnabled = j['ocr'] as bool? ?? true
    ..skipDuplicates = j['dup'] as bool? ?? true
    ..driveAccount = j['account'] as String?
    ..lastSync = (j['lastSync'] as num?)?.toInt()
    ..lastSyncError = j['lastErr'] as String?;
}

/// File sul telefono: indice, impostazioni, PDF e anteprime.
class Storage {
  Storage._(this.root);

  final Directory root;

  static Future<Storage> open() async {
    final base = await getApplicationDocumentsDirectory();
    final root = Directory(p.join(base.path, 'paperdrive'));
    await Directory(p.join(root.path, 'docs')).create(recursive: true);
    await Directory(p.join(root.path, 'thumbs')).create(recursive: true);
    await Directory(p.join(root.path, 'tmp')).create(recursive: true);
    return Storage._(root);
  }

  String get docsDir => p.join(root.path, 'docs');
  String get thumbsDir => p.join(root.path, 'thumbs');
  String get tmpDir => p.join(root.path, 'tmp');
  File get _indexFile => File(p.join(root.path, 'index.json'));
  File get _settingsFile => File(p.join(root.path, 'settings.json'));

  File docFile(String fileName) => File(p.join(docsDir, fileName));
  File thumbFile(String docId) => File(p.join(thumbsDir, '$docId.png'));

  String tmpPath(String name) => p.join(tmpDir, name);

  Future<void> _writeAtomic(File f, String data) async {
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsString(data, flush: true);
    await tmp.rename(f.path);
  }

  Future<Archive> loadArchive() async {
    try {
      if (await _indexFile.exists()) {
        final j = jsonDecode(await _indexFile.readAsString());
        return Archive.fromJson((j as Map).cast<String, dynamic>());
      }
    } catch (_) {
      // Indice illeggibile: si riparte da uno nuovo, ma si conserva la copia.
      if (await _indexFile.exists()) {
        await _indexFile.copy('${_indexFile.path}.broken');
      }
    }
    return Archive.starter();
  }

  Future<void> saveArchive(Archive a) =>
      _writeAtomic(_indexFile, jsonEncode(a.toJson()));

  Future<Settings> loadSettings() async {
    try {
      if (await _settingsFile.exists()) {
        final j = jsonDecode(await _settingsFile.readAsString());
        return Settings.fromJson((j as Map).cast<String, dynamic>());
      }
    } catch (_) {}
    return Settings();
  }

  Future<void> saveSettings(Settings s) =>
      _writeAtomic(_settingsFile, jsonEncode(s.toJson()));

  /// Nomi dei PDF presenti sul telefono.
  Future<Set<String>> localFileNames() async {
    final out = <String>{};
    await for (final e in Directory(docsDir).list()) {
      if (e is File && e.path.endsWith('.pdf')) out.add(p.basename(e.path));
    }
    return out;
  }

  Future<void> clearTmp() async {
    final d = Directory(tmpDir);
    if (await d.exists()) {
      await for (final e in d.list()) {
        try {
          await e.delete(recursive: true);
        } catch (_) {}
      }
    }
  }
}

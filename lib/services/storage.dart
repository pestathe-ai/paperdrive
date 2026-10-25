import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../core/archive.dart';
import '../core/mail_rules.dart';

/// Impostazioni dell'app (restano sul telefono, non si sincronizzano).
class Settings {
  bool driveEnabled = false;
  bool autoSync = true;
  bool autoAsn = false;
  bool ocrEnabled = true;
  bool skipDuplicates = true;
  bool makeArchive = true;
  String? driveAccount;

  /// AI sul telefono: modello scaricato (id) e se usarlo all'importazione.
  String? aiModel;
  bool aiEnabled = false;

  /// Importa da sola la cartella "Da importare" su Drive all'apertura.
  bool autoImport = false;

  /// Tiene i PDF anche sul telefono (altrimenti solo l'elenco: i file
  /// restano su Drive e si scaricano quando si aprono).
  bool keepFilesLocal = false;

  /// Cartella Drive dell'archivio (la mia o una condivisa con me).
  String? driveFolderId;
  String? driveFolderOwner;
  bool driveShared = false;

  /// Posso modificare l'archivio condiviso (falso = sola lettura).
  bool driveCanEdit = true;
  int? lastSync;
  String? lastSyncError;

  Map<String, dynamic> toJson() => {
        'drive': driveEnabled,
        'autoSync': autoSync,
        'autoAsn': autoAsn,
        'ocr': ocrEnabled,
        'dup': skipDuplicates,
        'pdfa': makeArchive,
        'account': driveAccount,
        'folder': driveFolderId,
        'folderOwner': driveFolderOwner,
        'shared': driveShared,
        'canEdit': driveCanEdit,
        'lastSync': lastSync,
        'lastErr': lastSyncError,
        'aiModel': aiModel,
        'ai': aiEnabled,
        'autoImport': autoImport,
        'keepLocal': keepFilesLocal,
      };

  static Settings fromJson(Map<String, dynamic> j) => Settings()
    ..driveEnabled = j['drive'] as bool? ?? false
    ..autoSync = j['autoSync'] as bool? ?? true
    ..autoAsn = j['autoAsn'] as bool? ?? false
    ..ocrEnabled = j['ocr'] as bool? ?? true
    ..skipDuplicates = j['dup'] as bool? ?? true
    ..makeArchive = j['pdfa'] as bool? ?? true
    ..driveAccount = j['account'] as String?
    ..driveFolderId = j['folder'] as String?
    ..driveFolderOwner = j['folderOwner'] as String?
    ..driveShared = j['shared'] as bool? ?? false
    ..driveCanEdit = j['canEdit'] as bool? ?? true
    ..lastSync = (j['lastSync'] as num?)?.toInt()
    ..lastSyncError = j['lastErr'] as String?
    ..aiModel = j['aiModel'] as String?
    ..aiEnabled = j['ai'] as bool? ?? false
    ..autoImport = j['autoImport'] as bool? ?? false
    ..keepFilesLocal = j['keepLocal'] as bool? ?? false;
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
  File get _mailFile => File(p.join(root.path, 'mail.json'));
  File get _onDriveFile => File(p.join(root.path, 'ondrive.json'));

  /// File già caricati su Drive (per il simbolo e per liberare spazio).
  Future<Set<String>> loadOnDrive() async {
    try {
      if (await _onDriveFile.exists()) {
        return ((jsonDecode(await _onDriveFile.readAsString()) as List).map((e) => '$e')).toSet();
      }
    } catch (_) {}
    return <String>{};
  }

  Future<void> saveOnDrive(Set<String> names) => _writeAtomic(_onDriveFile, jsonEncode(names.toList()));

  /// Spazio occupato dai PDF sul telefono (byte).
  Future<int> docsSize() async {
    var n = 0;
    await for (final e in Directory(docsDir).list()) {
      if (e is File) n += await e.length();
    }
    return n;
  }

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

  Future<MailConfig> loadMail() async {
    try {
      if (await _mailFile.exists()) {
        final j = jsonDecode(await _mailFile.readAsString());
        return MailConfig.fromJson((j as Map).cast<String, dynamic>());
      }
    } catch (_) {}
    return MailConfig();
  }

  Future<void> saveMail(MailConfig c) =>
      _writeAtomic(_mailFile, jsonEncode(c.toJson()));

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

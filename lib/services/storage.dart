import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../core/archive.dart';
import '../core/mail_rules.dart';
import '../core/meaning.dart';

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

  /// Non fare mai domande: decide sempre l'app.
  bool neverAsk = false;

  /// Ultima riparazione delle cartelle su Drive (millisecondi).
  int? lastRepair;

  /// Passaggio alle cartelle "prima la persona" già fatto.
  bool personFirst = false;

  /// Somiglianza per significato (rete neurale EmbeddingGemma) installata e attiva.
  bool meaningEnabled = false;

  /// Dopo l'archiviazione su Drive elimina il file originale dal telefono.
  bool deleteOriginals = false;

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
        'meaning': meaningEnabled,
        'delOrig': deleteOriginals,
        'ai': aiEnabled,
        'autoImport': autoImport,
        'keepLocal': keepFilesLocal,
        'neverAsk': neverAsk,
        'repair': lastRepair,
        'personFirst': personFirst,
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
    ..meaningEnabled = j['meaning'] as bool? ?? false
    ..deleteOriginals = j['delOrig'] as bool? ?? false
    ..aiEnabled = j['ai'] as bool? ?? false
    ..autoImport = j['autoImport'] as bool? ?? false
    ..keepFilesLocal = j['keepLocal'] as bool? ?? false
    ..neverAsk = j['neverAsk'] as bool? ?? false
    ..lastRepair = (j['repair'] as num?)?.toInt()
    ..personFirst = j['personFirst'] as bool? ?? false;
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
  File get _meaningFile => File(p.join(root.path, 'meanings.json'));
  File get _originalsFile => File(p.join(root.path, 'originals.json'));

  /// File originali da eliminare dopo l'archiviazione: indirizzo → documenti.
  Future<Map<String, List<String>>> loadOriginals() async {
    try {
      if (await _originalsFile.exists()) {
        final j = (jsonDecode(await _originalsFile.readAsString()) as Map).cast<String, dynamic>();
        return {for (final e in j.entries) e.key: (e.value as List).map((x) => '$x').toList()};
      }
    } catch (_) {}
    return {};
  }

  Future<void> saveOriginals(Map<String, List<String>> m) => _writeAtomic(_originalsFile, jsonEncode(m));

  /// Vettori della rete neurale per documento (solo sul telefono).
  Future<MeaningStore> loadMeanings() async {
    try {
      if (await _meaningFile.exists()) {
        return MeaningStore.fromJson((jsonDecode(await _meaningFile.readAsString()) as Map).cast<String, dynamic>());
      }
    } catch (_) {}
    return MeaningStore();
  }

  Future<void> saveMeanings(MeaningStore m) => _writeAtomic(_meaningFile, jsonEncode(m.toJson()));

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

  /// Solo il nome del file: niente percorsi che escono dalla cartella.
  File docFile(String fileName) => File(p.join(docsDir, p.basename(fileName)));
  File thumbFile(String docId) => File(p.join(thumbsDir, '${p.basename(docId)}.png'));

  String tmpPath(String name) => p.join(tmpDir, name);

  /// Scritture in coda, una alla volta per file: due salvataggi insieme non
  /// possono mescolarsi né lasciare l'indice rovinato.
  final Map<String, Future<void>> _writing = {};
  int _tmpCounter = 0;

  Future<void> _writeAtomic(File f, String data) {
    final previous = _writing[f.path] ?? Future<void>.value();
    final next = previous.catchError((Object _) {}).then((_) async {
      final tmp = File('${f.path}.${++_tmpCounter}.tmp');
      await tmp.writeAsString(data, flush: true);
      await tmp.rename(f.path);
    });
    _writing[f.path] = next;
    return next;
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

  /// Le password delle caselle stanno nel portachiavi protetto di Android,
  /// non nel file.
  static const FlutterSecureStorage _secrets = FlutterSecureStorage();
  static String _passKey(String accountId) => 'mail-pass-$accountId';

  Future<MailConfig> loadMail() async {
    try {
      if (await _mailFile.exists()) {
        final j = jsonDecode(await _mailFile.readAsString());
        final c = MailConfig.fromJson((j as Map).cast<String, dynamic>());
        var legacy = false;
        for (final a in c.accounts) {
          if (a.password.isNotEmpty) {
            // Versione precedente: password nel file, si sposta ora.
            legacy = true;
            continue;
          }
          try {
            a.password = await _secrets.read(key: _passKey(a.id)) ?? '';
          } catch (_) {}
        }
        if (legacy) await saveMail(c);
        return c;
      }
    } catch (_) {}
    return MailConfig();
  }

  Future<void> saveMail(MailConfig c) async {
    final j = c.toJson();
    final safe = <String>{};
    for (final a in c.accounts) {
      try {
        await _secrets.write(key: _passKey(a.id), value: a.password);
        safe.add(a.id);
      } catch (_) {
        // Portachiavi non disponibile: la password resta nel file.
      }
    }
    for (final a in (j['accounts'] as List)) {
      if (safe.contains((a as Map)['id'])) a['pass'] = '';
    }
    await _writeAtomic(_mailFile, jsonEncode(j));
  }

  /// Nomi dei PDF presenti sul telefono.
  Future<Set<String>> localFileNames() async {
    final out = <String>{};
    await for (final e in Directory(docsDir).list()) {
      if (e is File && e.path.endsWith('.pdf')) out.add(p.basename(e.path));
    }
    return out;
  }

  /// Svuota i file temporanei. Durante l'uso toglie solo quelli vecchi
  /// ([all] solo all'avvio): un'altra importazione in corso potrebbe
  /// usare quelli recenti.
  Future<void> clearTmp({bool all = false}) async {
    final d = Directory(tmpDir);
    if (await d.exists()) {
      final limit = DateTime.now().subtract(const Duration(hours: 2));
      await for (final e in d.list()) {
        try {
          if (!all && (await e.stat()).modified.isAfter(limit)) continue;
          await e.delete(recursive: true);
        } catch (_) {}
      }
    }
  }
}

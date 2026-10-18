import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart' show FilePicker, FileType;
import 'package:material_ui/material_ui.dart';

import '../core/archive.dart';
import '../core/dates.dart';
import '../core/matching.dart';
import '../core/models.dart';
import '../core/search.dart';
import '../core/sync_merge.dart';
import '../services/drive_sync.dart';
import '../services/ingest.dart';
import '../services/storage.dart';

/// Stato dell'app: archivio, impostazioni e operazioni.
class AppState extends ChangeNotifier {
  late final Storage storage;
  late Archive archive;
  late Settings settings;
  late final Ingestor ingestor;
  late final DriveSync drive;
  final SearchIndex searchIndex = SearchIndex();

  bool ready = false;

  /// Messaggio dell'operazione in corso (importazione), o null.
  String? busy;
  bool syncing = false;
  String? syncStatus;

  Timer? _saveTimer;
  Timer? _syncTimer;
  bool _syncAgain = false;

  Future<void> init() async {
    storage = await Storage.open();
    archive = await storage.loadArchive();
    settings = await storage.loadSettings();
    ingestor = Ingestor(storage);
    drive = DriveSync(storage);
    await storage.clearTmp();
    ready = true;
    notifyListeners();
    if (settings.driveEnabled && settings.autoSync) {
      unawaited(syncNow(silent: true));
    }
  }

  /// Da chiamare dopo ogni modifica: salva e (se attivo) sincronizza.
  void changed({bool entities = false, bool sync = true}) {
    if (entities) searchIndex.clear();
    notifyListeners();
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 400), () {
      storage.saveArchive(archive);
    });
    if (sync && settings.driveEnabled && settings.autoSync) {
      _syncTimer?.cancel();
      _syncTimer = Timer(const Duration(seconds: 8), () => syncNow(silent: true));
    }
  }

  Future<void> saveSettings() async {
    await storage.saveSettings(settings);
    notifyListeners();
  }

  // ---------------------------------------------------------------------
  // Importazione

  /// Scansiona un documento con la fotocamera.
  Future<List<String>> scanDocument() async {
    final input = await ingestor.scan();
    if (input == null) return const [];
    return _ingestAll([input], fromScan: true);
  }

  /// Importa PDF o immagini dal telefono (anche da Drive o altre app).
  Future<List<String>> importFiles() async {
    final files = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf', 'jpg', 'jpeg', 'png', 'webp'],
    );
    if (files.isEmpty) return const [];
    final staged = <StagedInput>[];
    for (final f in files) {
      busy = 'Preparazione di ${f.name}…';
      notifyListeners();
      staged.add(await ingestor.stageFile(f.name, await f.readAsBytes()));
    }
    return _ingestAll(staged, fromScan: false);
  }

  Future<List<String>> _ingestAll(List<StagedInput> inputs, {required bool fromScan}) async {
    final messages = <String>[];
    try {
      for (var i = 0; i < inputs.length; i++) {
        final input = inputs[i];
        final prefix = inputs.length > 1 ? '(${i + 1}/${inputs.length}) ' : '';
        busy = '$prefix${input.originalName}: analisi…';
        notifyListeners();
        try {
          final doc = await ingestor.analyze(
            input,
            ocr: settings.ocrEnabled,
            status: (s) {
              busy = '$prefix$s';
              notifyListeners();
            },
          );
          final dup = archive.duplicateOf(doc.checksum);
          if (dup != null && settings.skipDuplicates) {
            messages.add('${input.originalName}: già presente come "${dup.title}"');
            continue;
          }
          _prepare(doc, fromScan: fromScan);
          await ingestor.commit(input, doc);
          archive.documents[doc.id] = doc;
          messages.add('Aggiunto: ${doc.title}');
          changed();
        } catch (e) {
          messages.add('${input.originalName}: errore ($e)');
        }
      }
    } finally {
      busy = null;
      notifyListeners();
      unawaited(storage.clearTmp());
    }
    return messages;
  }

  void _prepare(Document doc, {required bool fromScan}) {
    if (fromScan) {
      doc.title = suggestTitle(doc.content) ?? doc.originalName;
    }
    final date = detectDate(doc.content);
    if (date != null) doc.created = date;
    for (final t in archive.inboxTags) {
      doc.tagIds.add(t.id);
    }
    applyMatches(archive, doc);
    if (settings.autoAsn) doc.asn = archive.nextAsn();
    doc.touch();
  }

  /// Rilegge il testo del documento con l'OCR.
  Future<void> reprocess(Document d) async {
    final f = await ensureFile(d);
    if (f == null) throw Exception('File non disponibile');
    busy = 'Lettura del testo…';
    notifyListeners();
    try {
      final text = await ingestor.ocrPdf(f.path, progress: (i, n) {
        busy = 'Lettura del testo: pagina $i di $n';
        notifyListeners();
      });
      d.content = text;
      d.touch();
      changed();
    } finally {
      busy = null;
      notifyListeners();
      unawaited(storage.clearTmp());
    }
  }

  // ---------------------------------------------------------------------
  // Documenti

  File fileOf(Document d) => storage.docFile(d.fileName);
  File thumbOf(Document d) => storage.thumbFile(d.id);

  /// Il PDF del documento; se manca sul telefono lo scarica da Drive.
  Future<File?> ensureFile(Document d) async {
    final f = fileOf(d);
    if (await f.exists()) return f;
    if (!settings.driveEnabled) return null;
    final ok = await drive.fetchFile(d.fileName);
    if (!ok) return null;
    try {
      await ingestor.makeThumbnail(f.path, d.id);
    } catch (_) {}
    notifyListeners();
    return f;
  }

  void saveDocument(Document d) {
    d.touch();
    changed();
  }

  void moveToTrash(Iterable<Document> docs) {
    for (final d in docs) {
      d
        ..inTrash = true
        ..trashedAt = nowMs()
        ..touch();
    }
    changed();
  }

  void restore(Iterable<Document> docs) {
    for (final d in docs) {
      d
        ..inTrash = false
        ..trashedAt = null
        ..touch();
    }
    changed();
  }

  Future<void> deleteForever(Iterable<Document> docs) async {
    for (final d in docs.toList()) {
      archive.purge(d);
      final f = fileOf(d);
      if (await f.exists()) await f.delete();
      final t = thumbOf(d);
      if (await t.exists()) await t.delete();
    }
    changed();
  }

  void bulkAddTag(Iterable<Document> docs, String tagId) {
    for (final d in docs) {
      if (d.tagIds.add(tagId)) d.touch();
    }
    changed();
  }

  void bulkRemoveTag(Iterable<Document> docs, String tagId) {
    for (final d in docs) {
      if (d.tagIds.remove(tagId)) d.touch();
    }
    changed();
  }

  void bulkSetCorrespondent(Iterable<Document> docs, String? id) {
    for (final d in docs) {
      d
        ..correspondentId = id
        ..touch();
    }
    changed();
  }

  void bulkSetType(Iterable<Document> docs, String? id) {
    for (final d in docs) {
      d
        ..typeId = id
        ..touch();
    }
    changed();
  }

  /// Toglie i tag "inbox": il documento è stato esaminato.
  void markReviewed(Iterable<Document> docs) {
    final inbox = archive.inboxTags.map((t) => t.id).toSet();
    for (final d in docs) {
      if (d.tagIds.any(inbox.contains)) {
        d.tagIds.removeAll(inbox);
        d.touch();
      }
    }
    changed();
  }

  /// Applica di nuovo le regole automatiche. Restituisce quanti cambiano.
  int reapplyRules(Iterable<Document> docs, {bool overwrite = false}) {
    var n = 0;
    for (final d in docs) {
      if (applyMatches(archive, d, overwrite: overwrite)) n++;
    }
    if (n > 0) changed();
    return n;
  }

  List<Document> query(DocumentFilter f) => runFilter(archive, f, searchIndex);

  // ---------------------------------------------------------------------
  // Tag, corrispondenti, tipi, campi, viste

  void saveTag(Tag t) {
    t.modified = nowMs();
    archive.tags[t.id] = t;
    changed(entities: true);
  }

  void deleteTag(Tag t) {
    t
      ..deleted = true
      ..modified = nowMs();
    archive.detachTag(t.id);
    changed(entities: true);
  }

  void saveCorrespondent(NamedEntity e) {
    e.modified = nowMs();
    archive.correspondents[e.id] = e;
    changed(entities: true);
  }

  void deleteCorrespondent(NamedEntity e) {
    e
      ..deleted = true
      ..modified = nowMs();
    archive.detachCorrespondent(e.id);
    changed(entities: true);
  }

  void saveType(NamedEntity e) {
    e.modified = nowMs();
    archive.types[e.id] = e;
    changed(entities: true);
  }

  void deleteType(NamedEntity e) {
    e
      ..deleted = true
      ..modified = nowMs();
    archive.detachType(e.id);
    changed(entities: true);
  }

  void saveField(CustomField f) {
    f.modified = nowMs();
    archive.fields[f.id] = f;
    changed(entities: true);
  }

  void deleteField(CustomField f) {
    f
      ..deleted = true
      ..modified = nowMs();
    for (final d in archive.documents.values) {
      if (d.customFields.remove(f.id) != null) d.touch();
    }
    changed(entities: true);
  }

  void saveView(SavedView v) {
    v.modified = nowMs();
    archive.views[v.id] = v;
    changed();
  }

  void deleteView(SavedView v) {
    v
      ..deleted = true
      ..modified = nowMs();
    changed();
  }

  // ---------------------------------------------------------------------
  // Google Drive

  Future<void> connectDrive() async {
    final account = await drive.connect();
    settings
      ..driveEnabled = true
      ..driveAccount = account
      ..lastSyncError = null;
    await saveSettings();
    await syncNow();
  }

  Future<void> disconnectDrive() async {
    try {
      await drive.disconnect();
    } catch (_) {}
    settings
      ..driveEnabled = false
      ..driveAccount = null;
    await saveSettings();
  }

  /// Sincronizza con Drive. Restituisce un riepilogo o lancia un errore.
  Future<String> syncNow({bool silent = false}) async {
    if (!settings.driveEnabled) return 'Google Drive non collegato';
    if (syncing) {
      _syncAgain = true;
      return 'Sincronizzazione già in corso';
    }
    _syncTimer?.cancel();
    syncing = true;
    syncStatus = 'Sincronizzazione…';
    notifyListeners();
    try {
      await storage.saveArchive(archive);
      final out = await drive.sync(archive, status: (s) {
        syncStatus = s;
        notifyListeners();
      });
      // Le modifiche fatte durante la sincronizzazione non si perdono.
      final (merged, _) = mergeArchives(archive, out.archive);
      archive = merged;
      for (final id in out.downloadedIds) {
        final d = archive.documents[id];
        if (d == null) continue;
        try {
          await ingestor.makeThumbnail(fileOf(d).path, d.id);
        } catch (_) {}
      }
      searchIndex.clear();
      await storage.saveArchive(archive);
      settings
        ..lastSync = nowMs()
        ..lastSyncError = null;
      await storage.saveSettings(settings);
      final parts = <String>[
        if (out.uploaded > 0) '${out.uploaded} caricati',
        if (out.downloaded > 0) '${out.downloaded} scaricati',
        if (out.removed > 0) '${out.removed} eliminati',
      ];
      return parts.isEmpty ? 'Tutto già sincronizzato' : 'Sincronizzato: ${parts.join(', ')}';
    } catch (e) {
      settings.lastSyncError = '$e';
      await storage.saveSettings(settings);
      if (silent) return 'Errore: $e';
      rethrow;
    } finally {
      syncing = false;
      syncStatus = null;
      notifyListeners();
      if (_syncAgain) {
        _syncAgain = false;
        unawaited(syncNow(silent: true));
      }
    }
  }
}

/// Rende [AppState] disponibile alle schermate.
class AppScope extends InheritedNotifier<AppState> {
  const AppScope({super.key, required AppState state, required super.child})
      : super(notifier: state);

  static AppState of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppScope>()!.notifier!;

  static AppState read(BuildContext context) =>
      context.getInheritedWidgetOfExactType<AppScope>()!.notifier!;
}

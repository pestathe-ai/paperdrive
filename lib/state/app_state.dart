import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart' show FilePicker, FileType;
import 'package:material_ui/material_ui.dart';

import '../core/archive.dart';
import '../core/dates.dart';
import '../core/mail_rules.dart';
import '../core/matching.dart';
import '../core/models.dart';
import '../core/search.dart';
import '../core/sync_merge.dart';
import '../core/text_utils.dart';
import '../core/workflows.dart';
import '../services/drive_sync.dart';
import '../services/ingest.dart';
import '../services/mail_import.dart';
import '../services/storage.dart';

/// Esito dell'importazione di un singolo file.
class IngestResult {
  IngestResult(this.message, {this.doc, this.ok = true});
  final String message;
  final Document? doc;

  /// Importato o saltato come duplicato (falso = errore).
  final bool ok;
}

/// Stato dell'app: archivio, impostazioni e operazioni.
class AppState extends ChangeNotifier {
  late final Storage storage;
  late Archive archive;
  late Settings settings;
  late MailConfig mail;
  late final Ingestor ingestor;
  late final DriveSync drive;
  late final MailImporter mailImporter;
  final SearchIndex searchIndex = SearchIndex();

  bool ready = false;

  /// Messaggio dell'operazione in corso (importazione), o null.
  String? busy;
  bool syncing = false;
  String? syncStatus;
  bool checkingMail = false;

  Timer? _saveTimer;
  Timer? _syncTimer;
  bool _syncAgain = false;

  Future<void> init() async {
    storage = await Storage.open();
    archive = await storage.loadArchive();
    settings = await storage.loadSettings();
    mail = await storage.loadMail();
    ingestor = Ingestor(storage);
    drive = DriveSync(storage);
    mailImporter = MailImporter(ingestor);
    Session.user = settings.driveEnabled ? settings.driveAccount : null;
    await storage.clearTmp();
    ready = true;
    notifyListeners();
    unawaited(_startup());
  }

  Future<void> _startup() async {
    if (settings.driveEnabled && settings.autoSync) {
      await syncNow(silent: true);
    }
    if (mail.checkOnOpen && mail.rules.any((r) => r.enabled) && !readOnly) {
      await checkMail(silent: true);
    }
  }

  /// Archivio condiviso in sola lettura: niente modifiche.
  bool get readOnly =>
      settings.driveEnabled && settings.driveShared && !settings.driveCanEdit;

  /// Cartella Drive da usare (null = la mia, da trovare o creare).
  String? get _folder => settings.driveFolderId;

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

  Future<void> saveMail() async {
    await storage.saveMail(mail);
    notifyListeners();
  }

  // ---------------------------------------------------------------------
  // Importazione

  /// Scansiona un documento con la fotocamera.
  Future<List<String>> scanDocument() async {
    final input = await ingestor.scan();
    if (input == null) return const [];
    return _ingestAll([input]);
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
    return _ingestAll(staged);
  }

  Future<List<String>> _ingestAll(List<StagedInput> inputs) async {
    final messages = <String>[];
    try {
      for (var i = 0; i < inputs.length; i++) {
        final prefix = inputs.length > 1 ? '(${i + 1}/${inputs.length}) ' : '';
        final r = await _ingestOne(inputs[i], prefix: prefix);
        messages.add(r.message);
      }
    } finally {
      busy = null;
      notifyListeners();
      unawaited(storage.clearTmp());
    }
    return messages;
  }

  Future<IngestResult> _ingestOne(StagedInput input, {String prefix = '', MailItem? mailItem}) async {
    busy = '$prefix${input.originalName}: analisi…';
    notifyListeners();
    try {
      final analysis = await ingestor.analyze(
        input,
        ocr: settings.ocrEnabled,
        status: (s) {
          busy = '$prefix$s';
          notifyListeners();
        },
      );
      final doc = analysis.doc;
      final dup = archive.duplicateOf(doc.checksum);
      if (dup != null && settings.skipDuplicates) {
        return IngestResult('${input.originalName}: già presente come "${dup.title}"');
      }
      _prepare(doc, mailItem: mailItem);
      if (analysis.ocrPages.isNotEmpty && settings.makeArchive) {
        busy = '${prefix}Creazione della versione PDF/A…';
        notifyListeners();
      }
      await ingestor.commit(input, analysis, makeArchive: settings.makeArchive);
      archive.documents[doc.id] = doc;
      changed(entities: true);
      return IngestResult('Aggiunto: ${doc.title}', doc: doc);
    } catch (e) {
      return IngestResult('${input.originalName}: errore ($e)', ok: false);
    }
  }

  /// Corrispondente con questo nome (senza maiuscole/accenti), o uno nuovo.
  NamedEntity correspondentNamed(String name) {
    final n = normalize(name.trim());
    for (final c in archive.activeCorrespondents) {
      if (normalize(c.name) == n) return c;
    }
    final c = NamedEntity(name: name.trim());
    archive.correspondents[c.id] = c;
    return c;
  }

  void _prepare(Document doc, {MailItem? mailItem}) {
    if (doc.source == DocSource.scan) {
      doc.title = suggestTitle(doc.content) ?? doc.originalName;
    }
    final date = detectDate(doc.content);
    if (date != null) doc.created = date;
    for (final t in archive.inboxTags) {
      doc.tagIds.add(t.id);
    }
    if (mailItem != null) {
      final rule = mailItem.rule;
      if (rule.title == MailTitle.subject || mailItem.attachmentName == null) {
        doc.title = mailItem.info.subject;
      }
      if (mailItem.info.date != null && date == null) doc.created = mailItem.info.date!;
      for (final t in rule.tagIds) {
        if (archive.tag(t) != null) doc.tagIds.add(t);
      }
      if (rule.typeId != null && archive.type(rule.typeId) != null) doc.typeId = rule.typeId;
      switch (rule.correspondent) {
        case MailCorrespondent.none:
          break;
        case MailCorrespondent.sender:
          doc.correspondentId = correspondentNamed(senderName(mailItem.info)).id;
        case MailCorrespondent.fixed:
          if (archive.correspondent(rule.correspondentId) != null) {
            doc.correspondentId = rule.correspondentId;
          }
      }
      doc.notes.add(Note(
        text: 'Da email: "${mailItem.info.subject}" di '
            '${mailItem.info.fromName.isEmpty ? mailItem.info.from : mailItem.info.fromName}',
      ));
    }
    applyMatches(archive, doc);
    if (settings.autoAsn) doc.asn = archive.nextAsn();
    applyWorkflows(archive, doc, WorkflowTrigger.added, source: doc.source);
    doc.touch();
  }

  /// Rilegge il testo del documento con l'OCR e rifà la versione archiviata.
  Future<void> reprocess(Document d, {bool updateText = true}) async {
    final f = await ensureFile(d);
    if (f == null) throw Exception('File non disponibile');
    busy = 'Lettura del testo…';
    notifyListeners();
    try {
      final pages = await ingestor.ocrPdf(f.path, progress: (i, n) {
        busy = 'Lettura del testo: pagina $i di $n';
        notifyListeners();
      });
      if (updateText) d.content = Ingestor.joinText(pages);
      if (settings.makeArchive || !updateText) {
        busy = 'Creazione della versione PDF/A…';
        notifyListeners();
        await ingestor.saveArchive(d, pages);
      }
      d.touch();
      changed();
    } finally {
      busy = null;
      notifyListeners();
      unawaited(storage.clearTmp());
    }
  }

  // ---------------------------------------------------------------------
  // Posta

  Future<String> checkMail({bool silent = false}) async {
    if (checkingMail) return 'Controllo della posta già in corso';
    if (readOnly) return 'Archivio in sola lettura';
    checkingMail = true;
    notifyListeners();
    var added = 0;
    try {
      final log = await mailImporter.run(
        mail,
        (item) async {
          final r = await _ingestOne(item.input, mailItem: item);
          if (r.doc != null) added++;
          return r.ok;
        },
        status: (s) {
          busy = s;
          notifyListeners();
        },
      );
      final summary = added == 0
          ? 'Nessun nuovo documento dalla posta'
          : 'Dalla posta: $added nuovi documenti';
      mail
        ..lastCheck = nowMs()
        ..lastResult = [summary, ...log].join('\n');
      await storage.saveMail(mail);
      return summary;
    } catch (e) {
      mail.lastResult = 'Errore: $e';
      await storage.saveMail(mail);
      if (silent) return 'Errore: $e';
      rethrow;
    } finally {
      checkingMail = false;
      busy = null;
      notifyListeners();
      unawaited(storage.clearTmp());
    }
  }

  // ---------------------------------------------------------------------
  // Documenti

  File fileOf(Document d) => storage.docFile(d.fileName);
  File? archiveFileOf(Document d) => d.hasArchive ? storage.docFile(d.archiveFileName) : null;
  File thumbOf(Document d) => storage.thumbFile(d.id);

  Future<File?> _ensure(String name, {String? thumbFor}) async {
    final f = storage.docFile(name);
    if (await f.exists()) return f;
    if (!settings.driveEnabled) return null;
    final ok = await drive.fetchFile(name, folderId: _folder);
    if (!ok) return null;
    if (thumbFor != null) {
      try {
        await ingestor.makeThumbnail(f.path, thumbFor);
      } catch (_) {}
    }
    notifyListeners();
    return f;
  }

  /// Il PDF originale; se manca sul telefono lo scarica da Drive.
  Future<File?> ensureFile(Document d) => _ensure(d.fileName, thumbFor: d.id);

  /// La versione archiviata (PDF/A), se esiste.
  Future<File?> ensureArchive(Document d) async =>
      d.hasArchive ? _ensure(d.archiveFileName) : null;

  void saveDocument(Document d) {
    d.touch();
    changed();
  }

  /// Fine della modifica di un documento: esegue i flussi "modificato".
  void documentEdited(Document d) {
    if (applyWorkflows(archive, d, WorkflowTrigger.updated).isNotEmpty) changed();
  }

  void _edited(Iterable<Document> docs) {
    for (final d in docs) {
      applyWorkflows(archive, d, WorkflowTrigger.updated);
    }
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
      for (final name in d.fileNames) {
        final f = storage.docFile(name);
        if (await f.exists()) await f.delete();
      }
      final t = thumbOf(d);
      if (await t.exists()) await t.delete();
      archive.purge(d);
    }
    changed();
  }

  void bulkAddTag(Iterable<Document> docs, String tagId) {
    for (final d in docs) {
      if (d.tagIds.add(tagId)) d.touch();
    }
    _edited(docs);
  }

  void bulkRemoveTag(Iterable<Document> docs, String tagId) {
    for (final d in docs) {
      if (d.tagIds.remove(tagId)) d.touch();
    }
    _edited(docs);
  }

  void bulkSetCorrespondent(Iterable<Document> docs, String? id) {
    for (final d in docs) {
      d
        ..correspondentId = id
        ..touch();
    }
    _edited(docs);
  }

  void bulkSetType(Iterable<Document> docs, String? id) {
    for (final d in docs) {
      d
        ..typeId = id
        ..touch();
    }
    _edited(docs);
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
    _edited(docs);
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

  /// Esegue un flusso su documenti già in archivio. Restituisce quanti cambiano.
  int runWorkflowOn(Workflow w, Iterable<Document> docs) {
    var n = 0;
    for (final d in docs) {
      final ok = w.enabled &&
          workflowMatches(
            Workflow.fromJson(w.toJson())
              ..triggers = {WorkflowTrigger.updated}
              ..sources = {},
            d,
            WorkflowTrigger.updated,
          );
      if (ok && runActions(w, archive, d)) {
        d.touch();
        n++;
      }
    }
    if (n > 0) changed();
    return n;
  }

  List<Document> query(DocumentFilter f) => runFilter(archive, f, searchIndex);

  // ---------------------------------------------------------------------
  // Tag, corrispondenti, tipi, campi, viste, flussi

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

  void saveWorkflow(Workflow w) {
    w.modified = nowMs();
    archive.workflows[w.id] = w;
    changed();
  }

  void deleteWorkflow(Workflow w) {
    w
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
    Session.user = account;
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
    Session.user = null;
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
      final out = await drive.sync(archive, folderId: _folder, status: (s) {
        syncStatus = s;
        notifyListeners();
      });
      // Le modifiche fatte durante la sincronizzazione non si perdono.
      final (merged, _) = mergeArchives(archive, out.archive);
      archive = merged;
      for (final name in out.downloadedNames) {
        if (name.contains('.archive')) continue;
        try {
          await ingestor.makeThumbnail(storage.docFile(name).path, docIdOfFile(name));
        } catch (_) {}
      }
      searchIndex.clear();
      await storage.saveArchive(archive);
      settings
        ..driveFolderId = out.folderId
        ..driveCanEdit = out.canEdit
        ..driveFolderOwner = out.ownerEmail
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

  // ---------------------------------------------------------------------
  // Archivio condiviso

  Future<List<DriveMember>> members() => drive.members(_folder);

  Future<void> invite(String email, {required bool canEdit, String? message}) =>
      drive.invite(_folder, email, canEdit: canEdit, message: message);

  Future<void> setMemberRole(DriveMember m, {required bool canEdit}) =>
      drive.setRole(_folder, m.permissionId, canEdit: canEdit);

  Future<void> removeMember(DriveMember m) => drive.removeMember(_folder, m.permissionId);

  Future<List<SharedFolder>> sharedFolders() => drive.sharedFolders();

  /// Usa l'archivio condiviso da un'altra persona. I miei documenti locali
  /// vengono uniti a quell'archivio (se ho il permesso di modifica).
  Future<void> joinShared(SharedFolder f, {required bool keepMine}) async {
    if (!keepMine) await _clearLocal();
    settings
      ..driveFolderId = f.id
      ..driveFolderOwner = f.owner
      ..driveShared = true
      ..driveCanEdit = true;
    await saveSettings();
    await syncNow();
  }

  /// Torna al mio archivio personale.
  Future<void> leaveShared({required bool keepCopy}) async {
    if (!keepCopy) await _clearLocal();
    settings
      ..driveFolderId = null
      ..driveFolderOwner = null
      ..driveShared = false
      ..driveCanEdit = true;
    await saveSettings();
    await syncNow();
  }

  Future<void> _clearLocal() async {
    for (final name in await storage.localFileNames()) {
      try {
        await storage.docFile(name).delete();
      } catch (_) {}
    }
    for (final d in archive.documents.values) {
      try {
        final t = thumbOf(d);
        if (await t.exists()) await t.delete();
      } catch (_) {}
    }
    archive = Archive.starter();
    searchIndex.clear();
    await storage.saveArchive(archive);
    notifyListeners();
  }

  /// Crea un link pubblico al PDF (originale o archiviato).
  Future<String> createPublicLink(Document d, {bool archived = false}) async {
    if (!settings.driveEnabled) {
      throw Exception('Serve Google Drive collegato');
    }
    await syncNow(silent: true);
    final name = archived && d.hasArchive ? d.archiveFileName : d.fileName;
    final url = await drive.createPublicLink(_folder, name);
    d.shareLink = url;
    saveDocument(d);
    return url;
  }

  Future<void> revokePublicLink(Document d) async {
    for (final name in d.fileNames) {
      await drive.revokePublicLink(_folder, name);
    }
    d.shareLink = null;
    saveDocument(d);
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

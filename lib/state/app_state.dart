import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart' show FilePicker, FileType;
import 'package:enough_mail/enough_mail.dart' show ContentDisposition, MimeMessage;
import 'package:material_ui/material_ui.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../core/ai.dart';
import '../core/archive.dart';
import '../core/assistant.dart';
import '../core/classifier.dart';
import '../core/dates.dart';
import '../core/extract.dart' show detectIssuer;
import '../core/formats.dart';
import '../core/import_hint.dart';
import '../core/mail_rules.dart';
import '../core/matching.dart';
import '../core/models.dart';
import '../core/organize.dart';
import '../core/people.dart';
import '../core/starter.dart';
import '../core/search.dart';
import '../core/sync_merge.dart';
import '../core/text_utils.dart';
import '../core/workflows.dart';
import '../services/ai_assistant.dart';
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

  /// Classificatore automatico (come Paperless), addestrato sui documenti
  /// già esaminati. Null finché non ci sono dati.
  DocumentClassifier? classifier;
  bool training = false;
  Timer? _trainTimer;
  String? _trainedSignature;
  final SearchIndex searchIndex = SearchIndex();

  /// Modello linguistico sul telefono (facoltativo).
  final AiAssistant ai = AiAssistant();

  /// Importazione dalla cartella "Da importare" su Drive.
  bool importing = false;
  bool _stopImport = false;

  /// Il modello da usare all'importazione, se attivato e scaricato.
  AiModelOption? get aiModel => settings.aiEnabled ? aiModelById(settings.aiModel) : null;

  bool ready = false;

  /// Messaggio dell'operazione in corso (importazione), o null.
  String? busy;
  bool syncing = false;
  String? syncStatus;
  bool checkingMail = false;

  /// Esito dell'ultima importazione da "Condividi" (la home lo mostra).
  final ValueNotifier<List<String>?> shareResults = ValueNotifier(null);

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
    // Chi arriva da una versione precedente senza categorie le riceve subito.
    // e le regole predefinite non modificate si aggiornano.
    if (archive.activeTypes.isEmpty || archive.types.keys.any((k) => k.startsWith('st-'))) {
      addStarterEntities(archive);
      ensurePeopleEntities(archive);
      await storage.saveArchive(archive);
    }
    await storage.clearTmp();
    ready = true;
    notifyListeners();
    unawaited(_startup());
  }

  /// Firma di ciò che il classificatore impara: se non cambia, non si
  /// riaddestra (come il controllo "last_doc_change" di Paperless).
  String _trainingSignature() {
    final inbox = archive.inboxTags.map((t) => t.id).toSet();
    final b = StringBuffer();
    for (final d in archive.activeDocuments) {
      if (d.tagIds.any(inbox.contains)) continue;
      b
        ..write(d.id)
        ..write(d.correspondentId)
        ..write(d.typeId)
        ..write(d.storagePathId)
        ..write((d.tagIds.toList()..sort()).join(','))
        ..write(d.content.length);
    }
    for (final m in <Matchable>[
      ...archive.activeTags,
      ...archive.activeCorrespondents,
      ...archive.activeTypes,
      ...archive.activeStoragePaths,
    ]) {
      if (m.algorithm == MatchAlgorithm.auto) b.write(m.id);
    }
    return b.toString().hashCode.toString();
  }

  /// Riaddestra il classificatore in un processo separato.
  Future<void> retrain({bool force = false}) async {
    if (training) return;
    final sig = _trainingSignature();
    if (!force && sig == _trainedSignature) return;
    training = true;
    notifyListeners();
    try {
      final json = archive.toJson();
      classifier = await Isolate.run(() => DocumentClassifier.train(Archive.fromJson(json)));
      _trainedSignature = sig;
    } catch (_) {
      // Senza classificatore valgono comunque le regole.
    } finally {
      training = false;
      notifyListeners();
    }
  }

  void _scheduleTraining() {
    _trainTimer?.cancel();
    _trainTimer = Timer(const Duration(seconds: 20), () => retrain());
  }

  Future<void> _startup() async {
    unawaited(retrain());
    if (settings.driveEnabled && settings.autoSync) {
      await syncNow(silent: true);
    }
    if (mail.checkOnOpen && mail.rules.any((r) => r.enabled) && !readOnly) {
      await checkMail(silent: true);
    }
    if (settings.driveEnabled && settings.autoImport && !readOnly) {
      final msg = await importDriveInbox();
      if (!msg.contains('vuota')) shareResults.value = [msg];
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
    _scheduleTraining();
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
      allowedExtensions: pickerExtensions,
    );
    if (files.isEmpty) return const [];
    final staged = <StagedInput>[];
    final errors = <String>[];
    for (final f in files) {
      busy = 'Preparazione di ${f.name}…';
      notifyListeners();
      try {
        staged.addAll(await _stage(f.name, await f.readAsBytes()));
      } catch (e) {
        errors.add('${f.name}: $e');
      }
    }
    busy = null;
    return [...errors, ...await _ingestAll(staged)];
  }

  /// Prepara un file di qualsiasi formato supportato: PDF e immagini sul
  /// telefono; Word, Excel, PowerPoint e simili convertiti in PDF da Google
  /// Drive; email (.eml) col testo in PDF e gli allegati come documenti.
  Future<List<StagedInput>> _stage(
    String name,
    Uint8List? bytes, {
    DocSource source = DocSource.file,
    InboxFile? remote,
  }) async {
    switch (fileKind(name, mimeType: remote?.mimeType)) {
      case FileKind.office:
        if (!settings.driveEnabled) {
          throw Exception('Word, Excel e PowerPoint vengono convertiti in PDF da Google Drive: '
              'collega Drive dalle Impostazioni');
        }
        final pdf = await drive.convertToPdf(
          name: name,
          fileId: remote?.id,
          mimeType: remote?.mimeType,
          bytes: bytes,
          folderId: _folder,
        );
        final original = isGoogleNative(remote?.mimeType) ? '$name.pdf' : name;
        return [await ingestor.stagePdfBytes(pdf, original, source: source)];
      case FileKind.mail:
        final msg = MimeMessage.parseFromData(bytes!);
        final info = MailImporter.infoOf(msg);
        final out = <StagedInput>[
          await ingestor.textToPdf(
            name: name,
            title: info.subject,
            header: [
              ('Da', info.fromName.isEmpty ? info.from : '${info.fromName} <${info.from}>'),
              if (info.to.isNotEmpty) ('A', info.to),
              if (info.date != null) ('Data', info.date!.toLocal().toString().substring(0, 16)),
            ],
            body: info.body,
            source: source,
          ),
        ];
        final seen = <String>{};
        for (final ci in msg.findContentInfo(disposition: ContentDisposition.attachment)) {
          final fname = ci.fileName;
          if (fname == null || !seen.add(ci.fetchId) || !importableFile(fname)) continue;
          final data = msg.getPart(ci.fetchId)?.decodeContentBinary();
          if (data == null || data.isEmpty) continue;
          try {
            out.addAll(await _stage(fname, data, source: source));
          } catch (_) {
            // Un allegato illeggibile non blocca l'email.
          }
        }
        return out;
      case FileKind.unsupported:
        throw Exception('formato non supportato');
      default:
        return [await ingestor.stageFile(name, bytes!, source: source)];
    }
  }

  /// Divide con i codici a barre (se attivo) e importa ogni parte.
  Future<List<IngestResult>> _ingestSplitting(
    StagedInput input, {
    String prefix = '',
    MailItem? mailItem,
    List<String>? folders,
  }) async {
    final c = archive.config;
    var parts = <(StagedInput, int?)>[(input, null)];
    try {
      parts = await ingestor.splitByBarcodes(
        input,
        split: c.barcodeSplit,
        separator: c.separatorBarcode,
        readAsn: c.asnBarcode,
        asnPrefix: c.asnPrefix,
        status: (s) {
          busy = '$prefix$s';
          notifyListeners();
        },
      );
    } catch (_) {
      // Senza codici a barre si importa il file intero.
    }
    final out = <IngestResult>[];
    for (final (part, asn) in parts) {
      out.add(await _ingestOne(part, prefix: prefix, mailItem: mailItem, asn: asn, folders: folders));
    }
    return out;
  }

  Future<List<String>> _ingestAll(List<StagedInput> inputs) async {
    final messages = <String>[];
    // Prima di classificare, il classificatore deve conoscere le ultime correzioni.
    busy = 'Preparazione…';
    notifyListeners();
    await retrain();
    try {
      for (var i = 0; i < inputs.length; i++) {
        final prefix = inputs.length > 1 ? '(${i + 1}/${inputs.length}) ' : '';
        for (final r in await _ingestSplitting(inputs[i], prefix: prefix)) {
          messages.add(r.message);
        }
      }
    } finally {
      busy = null;
      notifyListeners();
      unawaited(storage.clearTmp());
      unawaited(ai.release());
    }
    return messages;
  }

  Future<IngestResult> _ingestOne(
    StagedInput input, {
    String prefix = '',
    MailItem? mailItem,
    int? asn,
    bool checkDuplicates = true,
    List<String>? folders,
  }) async {
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
      if (checkDuplicates && dup != null && settings.skipDuplicates) {
        return IngestResult('${input.originalName}: già presente come "${dup.title}"');
      }
      AiResult? aiResult;
      final model = aiModel;
      if (model != null && doc.content.trim().length >= 20) {
        busy = '$prefix${input.originalName}: l\'AI sta leggendo il documento…';
        notifyListeners();
        aiResult = await ai.analyze(model, buildAiPrompt(archive, doc));
      }
      _prepare(doc, mailItem: mailItem, asn: asn, ai: aiResult, folders: folders);
      if (analysis.ocrPages.isNotEmpty && settings.makeArchive) {
        busy = '${prefix}Creazione della versione PDF/A…';
        notifyListeners();
      }
      await ingestor.commit(input, analysis, makeArchive: settings.makeArchive);
      archive.documents[doc.id] = doc;
      changed(entities: true);
      final type = archive.type(doc.typeId)?.name;
      return IngestResult(
        'Archiviato: ${doc.title}${type == null ? '' : ' → $type/${doc.created.year}'}',
        doc: doc,
      );
    } catch (e) {
      return IngestResult('${input.originalName}: errore ($e)', ok: false);
    }
  }

  /// Se nessuna regola ha scelto il corrispondente, prova a riconoscere
  /// l'ente o l'azienda dal testo (banche, gestori, enti pubblici…).
  void _guessCorrespondent(Document doc) {
    if (archive.correspondent(doc.correspondentId) != null) return;
    final issuer = detectIssuer(doc.content);
    if (issuer != null) doc.correspondentId = correspondentNamed(issuer).id;
  }

  /// Corrispondente con questo nome (senza maiuscole/accenti), o uno nuovo.
  NamedEntity correspondentNamed(String name) {
    final n = normalize(name.trim());
    for (final c in archive.activeCorrespondents) {
      if (normalize(c.name) == n) return c;
    }
    final c = NamedEntity(name: name.trim(), algorithm: MatchAlgorithm.auto);
    archive.correspondents[c.id] = c;
    return c;
  }

  void _prepare(Document doc, {MailItem? mailItem, int? asn, AiResult? ai, List<String>? folders}) {
    if (doc.source == DocSource.scan) {
      doc.title = suggestTitle(doc.content) ?? doc.originalName;
    }
    final date = detectDate(doc.content);
    if (date != null) doc.created = date;
    // I documenti già ordinati a mano non sono "da esaminare".
    if (folders == null) {
      for (final t in archive.inboxTags) {
        doc.tagIds.add(t.id);
      }
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
    applyMatches(archive, doc, classifier: classifier);
    applyKindCategory(archive, doc);
    _guessCorrespondent(doc);
    if (ai != null) applyAiResult(archive, doc, ai, retitle: false);
    final title = autoTitle(archive, doc);
    if (title != null) doc.title = title;
    if (ai?.title != null && aiMayRetitle(archive, doc)) doc.title = ai!.title!;
    if (folders != null) applyFolderHint(archive, doc, folders);
    applyPeople(archive, doc, aiPerson: ai?.person, aiSpecialty: ai?.specialty, aiHealthKind: ai?.healthKind);
    if (asn != null) {
      doc.asn = asn;
    } else if (settings.autoAsn) {
      doc.asn = archive.nextAsn();
    }
    final flows = applyWorkflows(archive, doc, WorkflowTrigger.added, source: doc.source);
    doc.log('Aggiunto (${folders != null ? 'cartella "$inboxFolderName"${folders.isEmpty ? '' : ' / ${folders.join(' / ')}'}' : doc.source.label})'
        '${ai != null ? ', letto dall\'AI' : ''}'
        '${flows.isEmpty ? '' : ', flussi: ${flows.join(', ')}'}');
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
      if (updateText) {
        d.content = Ingestor.joinText(pages);
        d.log('Testo riletto con l\'OCR');
      }
      if (settings.makeArchive || !updateText) {
        busy = 'Creazione della versione PDF/A…';
        notifyListeners();
        await ingestor.saveArchive(d, pages);
        d.log('Versione PDF/A creata');
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

  /// Fine della modifica di un documento: registra la cronologia ed esegue
  /// i flussi "modificato".
  void documentEdited(Document d, Map<String, dynamic> before) {
    if (logChanges(archive, before, d)) d.userEdited = true;
    _runUpdatedFlows(d);
    changed();
  }

  void _runUpdatedFlows(Document d) {
    final snap = d.toJson();
    final flows = applyWorkflows(archive, d, WorkflowTrigger.updated);
    if (flows.isNotEmpty) logChanges(archive, snap, d, via: 'Flusso ${flows.join(', ')}');
  }

  /// Esegue una modifica su più documenti, con cronologia e flussi.
  void _bulk(Iterable<Document> docs, void Function(Document) change) {
    for (final d in docs) {
      final before = d.toJson();
      change(d);
      if (logChanges(archive, before, d)) {
        d.userEdited = true;
        d.touch();
        _runUpdatedFlows(d);
      }
    }
    changed();
  }

  void moveToTrash(Iterable<Document> docs) {
    for (final d in docs) {
      d
        ..inTrash = true
        ..trashedAt = nowMs()
        ..log('Spostato nel cestino')
        ..touch();
    }
    changed();
  }

  void restore(Iterable<Document> docs) {
    for (final d in docs) {
      d
        ..inTrash = false
        ..trashedAt = null
        ..log('Ripristinato dal cestino')
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

  void bulkAddTag(Iterable<Document> docs, String tagId) =>
      _bulk(docs, (d) => d.tagIds.add(tagId));

  void bulkRemoveTag(Iterable<Document> docs, String tagId) =>
      _bulk(docs, (d) => d.tagIds.remove(tagId));

  void bulkSetCorrespondent(Iterable<Document> docs, String? id) =>
      _bulk(docs, (d) => d.correspondentId = id);

  void bulkSetType(Iterable<Document> docs, String? id) => _bulk(docs, (d) => d.typeId = id);

  void bulkSetStoragePath(Iterable<Document> docs, String? id) =>
      _bulk(docs, (d) => d.storagePathId = id);

  /// Toglie i tag "inbox": il documento è stato esaminato.
  void markReviewed(Iterable<Document> docs) {
    final inbox = archive.inboxTags.map((t) => t.id).toSet();
    _bulk(docs, (d) => d.tagIds.removeAll(inbox));
  }

  /// Applica di nuovo le regole automatiche (e rifà il titolo automatico).
  /// Restituisce quanti documenti cambiano.
  int reapplyRules(Iterable<Document> docs, {bool overwrite = false, bool retitle = false}) {
    var n = 0;
    for (final d in docs) {
      final before = d.toJson();
      applyMatches(archive, d, overwrite: overwrite, classifier: classifier);
      applyKindCategory(archive, d);
      applyPeople(archive, d);
      if (retitle) _guessCorrespondent(d);
      if (retitle) {
        final t = autoTitle(archive, d);
        if (t != null) d.title = t;
      }
      if (logChanges(archive, before, d, via: 'Regole automatiche')) {
        d.touch();
        n++;
      }
    }
    if (n > 0) changed();
    return n;
  }

  /// File in attesa nella cartella "Da importare" (la crea se manca).
  Future<List<InboxFile>> driveInbox() => drive.listInbox(folderId: _folder);

  void stopImport() {
    _stopImport = true;
    notifyListeners();
  }

  /// Importa tutti i file della cartella "Da importare" su Drive, come la
  /// cartella di importazione di Paperless. Le sottocartelle diventano
  /// categoria, tag e anno; i file importati vanno nel cestino di Drive.
  Future<String> importDriveInbox() async {
    if (!settings.driveEnabled) return 'Collega prima Google Drive';
    if (readOnly) return 'Archivio in sola lettura';
    if (importing || busy != null) return 'C\'è già un\'importazione in corso';
    importing = true;
    _stopImport = false;
    busy = 'Cerco i file in "$inboxFolderName"…';
    notifyListeners();
    var done = 0, dup = 0, failed = 0, skipped = 0, total = 0;
    try {
      await WakelockPlus.enable();
    } catch (_) {}
    try {
      final files = await drive.listInbox(folderId: _folder);
      total = files.length;
      if (files.isEmpty) return 'La cartella "$inboxFolderName" è vuota';
      await retrain();
      for (var i = 0; i < files.length && !_stopImport; i++) {
        final f = files[i];
        final prefix = '(${i + 1}/${files.length}) ';
        final kind = fileKind(f.name, mimeType: f.mimeType);
        if (kind == FileKind.unsupported) {
          skipped++;
          continue;
        }
        busy = '$prefix${f.name}: ${kind == FileKind.office ? 'conversione in PDF' : 'download'}…';
        notifyListeners();
        try {
          final bytes = kind == FileKind.office ? null : await drive.downloadInboxFile(f.id);
          final results = <IngestResult>[];
          for (final staged in await _stage(f.name, bytes, remote: f)) {
            results.addAll(await _ingestSplitting(staged, prefix: prefix, folders: f.folders));
          }
          if (results.every((r) => r.ok)) {
            await drive.trashInboxFile(f.id);
            if (results.any((r) => r.doc != null)) {
              done++;
            } else {
              dup++;
            }
          } else {
            failed++;
          }
        } catch (_) {
          failed++;
        } finally {
          await storage.clearTmp();
        }
      }
      if (!_stopImport) {
        try {
          await drive.cleanInbox(folderId: _folder);
        } catch (_) {}
      }
    } on DriveAuthRequired {
      return 'Accesso a Drive scaduto: ricollega da Impostazioni';
    } catch (e) {
      return 'Errore: $e';
    } finally {
      importing = false;
      busy = null;
      try {
        await WakelockPlus.disable();
      } catch (_) {}
      unawaited(ai.release());
      notifyListeners();
    }
    final parts = <String>[
      '$done importati',
      if (dup > 0) '$dup già presenti',
      if (skipped > 0) '$skipped saltati (formato non supportato)',
      if (failed > 0) '$failed non riusciti (restano nella cartella)',
      if (_stopImport) 'interrotto: ${total - done - dup - skipped - failed} ancora da importare',
    ];
    return parts.join(' · ');
  }

  /// Fa rileggere il documento all'AI e applica categoria, mittente, data e
  /// titolo. Restituisce i campi cambiati, o null se l'AI non ha risposto.
  Future<List<String>?> aiReread(Document d) async {
    final model = aiModelById(settings.aiModel);
    if (model == null || d.content.trim().isEmpty) return null;
    busy = 'L\'AI sta leggendo il documento…';
    notifyListeners();
    try {
      final r = await ai.analyze(model, buildAiPrompt(archive, d));
      if (r == null) return null;
      final before = d.toJson();
      final fields = applyAiResult(archive, d, r, retitle: false);
      if (applyPeople(archive, d, aiPerson: r.person, aiSpecialty: r.specialty, aiHealthKind: r.healthKind)) {
        fields.add('persona');
      }
      // Chiesto esplicitamente: il titolo dell'AI, se non l'hai scritto tu.
      if (r.title != null && !d.titleEdited && r.title != d.title) {
        d.title = r.title!;
        fields.add('titolo');
      }
      if (logChanges(archive, before, d, via: 'AI')) {
        d.touch();
        changed(entities: true);
      }
      return fields;
    } finally {
      busy = null;
      notifyListeners();
      unawaited(ai.release());
    }
  }

  /// Assistente "Chiedi": capisce la domanda (regole + AI sul telefono, se
  /// scaricata), cerca e prepara la risposta.
  Future<(AskQuery, List<AskHit>, String)> ask(String question, {bool useAi = true}) async {
    var q = parseQuestion(archive, question);
    final model = aiModelById(settings.aiModel);
    if (useAi && model != null) {
      final raw = await ai.generate(model, buildAskPrompt(archive, question), maxOutputTokens: 160);
      if (raw != null) q = mergeAskResponse(archive, q, raw);
    }
    final hits = runAsk(archive, q, searchIndex);
    return (q, hits, answerText(archive, q, hits));
  }

  /// Domande aperte: documenti su cui l'app ha un dubbio.
  List<DocQuestion> get questions => openQuestions(archive);

  /// Risponde a una domanda: la scelta vale come correzione a mano, così
  /// l'app impara.
  void answerQuestion(DocQuestion q, String value) {
    final d = q.doc;
    final before = d.toJson();
    switch (q.kind) {
      case QuestionKind.person:
        if (value.isEmpty) {
          // Documento di tutta la casa: la sua categoria diventa comune.
          if (d.typeId != null) archive.config.sharedTypeIds.add(d.typeId!);
          archive.config.modified = nowMs();
        } else {
          d.customFields[personFieldId] = value;
        }
      case QuestionKind.category:
        d.typeId = value;
        applyPeople(archive, d);
        final t = autoTitle(archive, d);
        if (t != null && !d.titleEdited) d.title = t;
    }
    if (logChanges(archive, before, d, via: 'Risposta')) d.userEdited = true;
    d.touch();
    changed(entities: true);
  }

  /// Riassegna persona, specialità e tipo sanitario a tutti i documenti
  /// (dopo aver cambiato l'elenco delle persone). Non tocca i valori messi a
  /// mano. Restituisce quanti documenti cambiano.
  int reapplyPeople() {
    var n = 0;
    for (final d in archive.activeDocuments) {
      final before = d.toJson();
      if (applyPeople(archive, d) && logChanges(archive, before, d, via: 'Persone')) {
        d.touch();
        n++;
      }
    }
    changed(entities: true);
    return n;
  }

  /// Aggiunge le categorie predefinite che mancano.
  int addStarterCategories() {
    final n = addStarterEntities(archive);
    if (n > 0) changed(entities: true);
    return n;
  }

  void saveConfig() {
    archive.config.modified = nowMs();
    changed();
  }

  void saveStoragePath(StoragePath p) {
    p.modified = nowMs();
    archive.storagePaths[p.id] = p;
    changed(entities: true);
  }

  void deleteStoragePath(StoragePath p) {
    p
      ..deleted = true
      ..modified = nowMs();
    archive.detachStoragePath(p.id);
    changed(entities: true);
  }

  // ---------------------------------------------------------------------
  // Pagine: modifica, unione, divisione

  /// Riscrive il PDF con le pagine nell'ordine dato (indice, quarti di giro).
  Future<void> editPages(Document d, List<(int, int)> pages) async {
    final f = await ensureFile(d);
    if (f == null) throw Exception('File non disponibile');
    if (pages.isEmpty) throw Exception('Il documento deve avere almeno una pagina');
    busy = 'Modifica delle pagine…';
    notifyListeners();
    try {
      final before = d.toJson();
      final newPath = await ingestor.extractPages(
        f.path,
        [for (final (i, _) in pages) i],
        rotations: {for (final (i, r) in pages) i: r},
      );
      final oldFile = fileOf(d);
      d.fileRev += 1;
      await File(newPath).copy(fileOf(d).path);
      if (await oldFile.exists()) await oldFile.delete();
      final bytes = await fileOf(d).readAsBytes();
      d
        ..checksum = Ingestor.checksumOf(bytes)
        ..fileSize = bytes.length
        ..pageCount = pages.length;
      var (text, _) = await ingestor.pdfText(fileOf(d).path);
      final needsOcr = text.replaceAll(RegExp(r'\s'), '').length < 30;
      if ((needsOcr && settings.ocrEnabled) || d.hasArchive) {
        busy = 'Lettura del testo…';
        notifyListeners();
        final ocr = await ingestor.ocrPdf(fileOf(d).path);
        if (needsOcr) text = Ingestor.joinText(ocr);
        if (settings.makeArchive || d.hasArchive) await ingestor.saveArchive(d, ocr);
      }
      d.content = text;
      try {
        await ingestor.makeThumbnail(fileOf(d).path, d.id);
      } catch (_) {}
      logChanges(archive, before, d, via: 'Pagine');
      d.touch();
      changed();
    } finally {
      busy = null;
      notifyListeners();
      unawaited(storage.clearTmp());
    }
  }

  /// Unisce più documenti in uno nuovo (con i dati del primo).
  Future<Document?> mergeDocuments(List<Document> docs, {required bool trashOriginals}) async {
    if (docs.length < 2) return null;
    busy = 'Unione di ${docs.length} documenti…';
    notifyListeners();
    try {
      final paths = <String>[];
      for (final d in docs) {
        final f = await ensureFile(d);
        if (f == null) throw Exception('"${d.title}" non è disponibile');
        paths.add(f.path);
      }
      final merged = await ingestor.mergePdfs(paths);
      final first = docs.first;
      final r = await _ingestOne(
        StagedInput(pdfPath: merged, originalName: '${first.title}.pdf', source: DocSource.file),
        checkDuplicates: false,
      );
      final nd = r.doc;
      if (nd == null) throw Exception(r.message);
      _copyMetadata(first, nd);
      nd.tagIds.addAll(docs.expand((d) => d.tagIds));
      for (final d in docs.skip(1)) {
        if (d.content.isNotEmpty && !nd.content.contains(d.content)) {
          nd.content = '${nd.content}\n\n${d.content}'.trim();
        }
      }
      nd.log('Creato unendo: ${docs.map((d) => '"${d.title}"').join(', ')}');
      if (trashOriginals) moveToTrash(docs);
      nd.touch();
      changed();
      return nd;
    } finally {
      busy = null;
      notifyListeners();
      unawaited(storage.clearTmp());
    }
  }

  /// Divide un documento: ogni gruppo di pagine diventa un nuovo documento.
  Future<int> splitDocument(Document d, List<List<int>> groups, {required bool trashOriginal}) async {
    final f = await ensureFile(d);
    if (f == null) throw Exception('File non disponibile');
    var n = 0;
    try {
      for (var k = 0; k < groups.length; k++) {
        if (groups[k].isEmpty) continue;
        busy = 'Divisione: parte ${k + 1} di ${groups.length}…';
        notifyListeners();
        final path = await ingestor.extractPages(f.path, groups[k]);
        final r = await _ingestOne(
          StagedInput(pdfPath: path, originalName: '${d.title} (parte ${k + 1}).pdf', source: d.source),
          checkDuplicates: false,
        );
        final nd = r.doc;
        if (nd == null) continue;
        _copyMetadata(d, nd);
        nd.title = '${d.title} (parte ${k + 1})';
        nd.log('Creato dividendo "${d.title}"');
        nd.touch();
        n++;
      }
      if (trashOriginal && n > 0) moveToTrash([d]);
      changed();
      return n;
    } finally {
      busy = null;
      notifyListeners();
      unawaited(storage.clearTmp());
    }
  }

  void _copyMetadata(Document from, Document to) {
    to
      ..title = from.title
      ..created = from.created
      ..correspondentId = from.correspondentId ?? to.correspondentId
      ..typeId = from.typeId ?? to.typeId
      ..storagePathId = from.storagePathId ?? to.storagePathId
      ..tagIds = {...from.tagIds}
      ..customFields = {...from.customFields};
  }

  // ---------------------------------------------------------------------
  // Condividi verso l'app

  /// File ricevuti da "Condividi" o "Apri con": li archivia subito.
  Future<List<String>> importShared(List<(String, String)> files) async {
    if (files.isEmpty) return const [];
    if (readOnly) {
      final msg = ['Archivio in sola lettura: file non importati'];
      shareResults.value = msg;
      return msg;
    }
    final staged = <StagedInput>[];
    for (final (path, name) in files) {
      try {
        final bytes = await File(path).readAsBytes();
        staged.addAll(await _stage(name, bytes, source: DocSource.share));
      } catch (_) {}
      try {
        await File(path).delete();
      } catch (_) {}
    }
    final messages = await _ingestAll(staged);
    shareResults.value = messages;
    if (settings.driveEnabled) unawaited(syncNow(silent: true));
    return messages;
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
      final before = d.toJson();
      if (ok && runActions(w, archive, d)) {
        logChanges(archive, before, d, via: 'Flusso ${w.name}');
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
        if (archive.documents[docIdOfFile(name)]?.fileName != name) continue;
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
        if (out.organized > 0) '${out.organized} archiviati in cartelle',
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

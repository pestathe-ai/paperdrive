/// Organizzazione automatica: titolo, cartelle su Drive, cronologia,
/// documenti simili e divisione delle scansioni con codici a barre.
library;

import 'archive.dart';
import 'extract.dart';
import 'matching.dart' show cosine, matchText, termVector;
import 'models.dart';
import 'workflows.dart';

// ---------------------------------------------------------------------------
// Titolo automatico

/// Titolo automatico: il nome del file se è già descrittivo, altrimenti
/// costruito dal modello (tipo specifico, dettagli, importo, ente).
String? autoTitle(Archive a, Document d) {
  if (!a.config.autoTitle) return null;
  if (a.config.keepFileName) {
    final name = meaningfulFileName(d.originalName);
    if (name != null) return name;
  }
  if (a.type(d.typeId) == null &&
      a.correspondent(d.correspondentId) == null &&
      detectKind(d.content) == null) {
    return null;
  }
  final t = renderTitle(a.config.titleTemplate, a, d);
  return t.isEmpty ? null : t;
}

// ---------------------------------------------------------------------------
// Percorso su Drive

const Map<String, String> _emptyNames = {
  '{document_type}': 'Senza categoria',
  '{correspondent}': 'Senza corrispondente',
  '{asn}': 'Senza ASN',
  '{owner}': 'Sconosciuto',
};

/// Toglie i caratteri non ammessi nei nomi di file e cartelle.
String safeName(String s, {int max = 100}) {
  var out = s
      .replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1F]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  out = out.replaceAll(RegExp(r'^[.\s]+|[.\s]+$'), '');
  if (out.length > max) out = out.substring(0, max).trim();
  return out;
}

/// Modello di percorso usato per il documento.
String pathTemplateFor(Archive a, Document d) {
  final p = a.storagePath(d.storagePathId);
  final t = (p?.template ?? a.config.pathTemplate).trim();
  return t.isEmpty ? ArchiveConfig.defaultPathTemplate : t;
}

/// Cartelle e nome del file (senza .pdf) del documento su Drive.
/// I documenti nel cestino vanno nella cartella "Cestino".
(List<String>, String) drivePath(Archive a, Document d) {
  final rendered = fillPlaceholders(
    pathTemplateFor(a, d),
    a,
    d,
    empty: (k) => _emptyNames[k] ?? '',
    clean: (v) => v.replaceAll(RegExp(r'[/\\]'), '-'),
  );
  final parts = rendered
      .split('/')
      .map((p) => safeName(p))
      .where((p) => p.isNotEmpty)
      .toList();
  var name = parts.isEmpty ? '' : parts.removeLast();
  if (name.isEmpty) name = safeName(d.title.isEmpty ? d.id : d.title);
  final folders = parts.take(6).toList();
  if (d.inTrash) folders.insert(0, 'Cestino');
  return (folders, name);
}

/// Nome completo su Drive per un file del documento (originale o PDF/A).
String driveFileName(Archive a, Document d, {required bool archived}) {
  final (_, name) = drivePath(a, d);
  return archived ? '$name (PDF-A).pdf' : '$name.pdf';
}

// ---------------------------------------------------------------------------
// Cronologia

String _tagNames(Archive a, Iterable<String> ids) =>
    ids.map((t) => a.tag(t)?.name ?? '?').join(', ');

/// Descrive cosa è cambiato tra [before] (JSON del documento) e [after].
List<String> describeChanges(Archive a, Map<String, dynamic> before, Document after) {
  final b = Document.fromJson(before);
  final out = <String>[];
  if (b.title != after.title) out.add('Titolo: "${b.title}" → "${after.title}"');
  if (dateOnly(b.created) != dateOnly(after.created)) {
    out.add('Data: ${formatDate(b.created)} → ${formatDate(after.created)}');
  }
  if (b.correspondentId != after.correspondentId) {
    out.add('Corrispondente: ${a.correspondent(b.correspondentId)?.name ?? '—'} → '
        '${a.correspondent(after.correspondentId)?.name ?? '—'}');
  }
  if (b.typeId != after.typeId) {
    out.add('Tipo: ${a.type(b.typeId)?.name ?? '—'} → ${a.type(after.typeId)?.name ?? '—'}');
  }
  if (b.storagePathId != after.storagePathId) {
    out.add('Percorso: ${a.storagePath(b.storagePathId)?.name ?? 'predefinito'} → '
        '${a.storagePath(after.storagePathId)?.name ?? 'predefinito'}');
  }
  final added = after.tagIds.difference(b.tagIds);
  final removed = b.tagIds.difference(after.tagIds);
  if (added.isNotEmpty) out.add('Tag aggiunti: ${_tagNames(a, added)}');
  if (removed.isNotEmpty) out.add('Tag tolti: ${_tagNames(a, removed)}');
  if (b.asn != after.asn) out.add('ASN: ${b.asn ?? '—'} → ${after.asn ?? '—'}');
  for (final f in a.activeFields) {
    final x = b.customFields[f.id], y = after.customFields[f.id];
    if (x != y) out.add('${f.name}: ${x ?? '—'} → ${y ?? '—'}');
  }
  if (b.notes.length != after.notes.length) {
    out.add(after.notes.length > b.notes.length ? 'Nota aggiunta' : 'Nota eliminata');
  }
  if (b.content != after.content) out.add('Testo modificato');
  if (b.pageCount != after.pageCount || b.checksum != after.checksum) {
    out.add('Pagine modificate (${b.pageCount} → ${after.pageCount})');
  }
  if (b.inTrash != after.inTrash) out.add(after.inTrash ? 'Spostato nel cestino' : 'Ripristinato');
  return out;
}

/// Registra nella cronologia le differenze rispetto a [before].
bool logChanges(Archive a, Map<String, dynamic> before, Document after, {String? via}) {
  final changes = describeChanges(a, before, after);
  if (changes.isEmpty) return false;
  after.log('${via == null ? '' : '$via: '}${changes.join('; ')}');
  return true;
}

// ---------------------------------------------------------------------------
// Documenti simili

/// I documenti più simili a [d] per contenuto (somiglianza 0..1).
List<(Document, double)> similarDocuments(Archive a, Document d, {int limit = 6}) {
  final v = termVector(matchText(d));
  if (v.isEmpty) return const [];
  final out = <(Document, double)>[];
  for (final o in a.activeDocuments) {
    if (o.id == d.id) continue;
    final s = cosine(v, termVector(matchText(o)));
    if (s >= 0.15) out.add((o, s));
  }
  out.sort((x, y) => y.$2.compareTo(x.$2));
  return out.take(limit).toList();
}

// ---------------------------------------------------------------------------
// Codici a barre

/// Parte di una scansione divisa: pagine (indici da 0) ed eventuale ASN.
class SplitPart {
  SplitPart(this.pages, this.asn);
  final List<int> pages;
  final int? asn;
}

String _norm(String s) => s.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');

/// Numero ASN da un codice (es. `ASN00123` → 123), o null.
int? asnFromBarcode(String value, String prefix) {
  final v = _norm(value);
  final p = _norm(prefix);
  if (p.isEmpty || !v.startsWith(p)) return null;
  return int.tryParse(v.substring(p.length));
}

/// Divide le pagine dove trova il codice separatore (la pagina separatrice
/// viene scartata) e legge l'ASN da ogni parte.
List<SplitPart> planBarcodeSplit(
  List<List<String>> barcodesPerPage, {
  required bool split,
  required String separator,
  required bool readAsn,
  required String asnPrefix,
}) {
  final sep = _norm(separator);
  final parts = <SplitPart>[];
  var current = <int>[];
  int? asn;
  void close() {
    if (current.isNotEmpty) parts.add(SplitPart(current, asn));
    current = <int>[];
    asn = null;
  }

  for (var i = 0; i < barcodesPerPage.length; i++) {
    final codes = barcodesPerPage[i];
    if (split && sep.isNotEmpty && codes.any((c) => _norm(c) == sep)) {
      close();
      continue;
    }
    if (readAsn && asn == null) {
      for (final c in codes) {
        final n = asnFromBarcode(c, asnPrefix);
        if (n != null) {
          asn = n;
          break;
        }
      }
    }
    current.add(i);
  }
  close();
  return parts;
}

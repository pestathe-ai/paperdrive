/// Flussi di lavoro come in Paperless-ngx: quando succede qualcosa
/// (documento aggiunto o modificato) e le condizioni sono vere, esegue
/// delle azioni (titolo, tag, corrispondente, tipo, campi, ASN, note…).
library;

import 'archive.dart';
import 'extract.dart';
import 'matching.dart';
import 'models.dart';

enum WorkflowTrigger { added, updated }

extension WorkflowTriggerLabel on WorkflowTrigger {
  String get label => switch (this) {
        WorkflowTrigger.added => 'Documento aggiunto',
        WorkflowTrigger.updated => 'Documento modificato',
      };
}

class Workflow with Syncable implements Matchable {
  Workflow({
    String? id,
    required this.name,
    this.enabled = true,
    this.order = 0,
    Set<WorkflowTrigger>? triggers,
    Set<DocSource>? sources,
    this.filenamePattern = '',
    this.algorithm = MatchAlgorithm.none,
    this.pattern = '',
    this.caseInsensitive = true,
    Set<String>? hasTags,
    Set<String>? hasNotTags,
    this.ifCorrespondent,
    this.ifType,
    this.titleTemplate = '',
    Set<String>? addTags,
    Set<String>? removeTags,
    this.removeAllTags = false,
    this.setCorrespondent,
    this.setType,
    this.setStoragePath,
    Map<String, String>? setFields,
    this.assignAsn = false,
    this.markReviewed = false,
    this.addNote = '',
    int? modified,
    this.deleted = false,
  })  : id = id ?? newId(),
        triggers = triggers ?? {WorkflowTrigger.added},
        sources = sources ?? <DocSource>{},
        hasTags = hasTags ?? <String>{},
        hasNotTags = hasNotTags ?? <String>{},
        addTags = addTags ?? <String>{},
        removeTags = removeTags ?? <String>{},
        setFields = setFields ?? <String, String>{},
        modified = modified ?? nowMs();

  @override
  final String id;
  @override
  String name;
  bool enabled;

  /// Ordine di esecuzione (crescente).
  int order;

  // --- Quando
  Set<WorkflowTrigger> triggers;

  /// Provenienze ammesse (vuoto = tutte). Vale solo per "aggiunto".
  Set<DocSource> sources;

  // --- Condizioni (tutte devono essere vere)
  /// Nome del file originale, con * e ? (es. `*fattura*.pdf`). Vuoto = tutti.
  String filenamePattern;

  /// Condizione sul testo, con gli stessi algoritmi delle regole.
  @override
  MatchAlgorithm algorithm;
  @override
  String pattern;
  @override
  bool caseInsensitive;
  Set<String> hasTags;
  Set<String> hasNotTags;
  String? ifCorrespondent;
  String? ifType;

  // --- Azioni
  /// Nuovo titolo con segnaposti, es. `{correspondent} {created_year}-{created_month}`.
  String titleTemplate;
  Set<String> addTags;
  Set<String> removeTags;
  bool removeAllTags;
  String? setCorrespondent;
  String? setType;
  String? setStoragePath;
  Map<String, String> setFields;
  bool assignAsn;
  bool markReviewed;
  String addNote;

  @override
  int modified;
  @override
  bool deleted;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'on': enabled,
        'order': order,
        'triggers': triggers.map((t) => t.name).toList(),
        'sources': sources.map((t) => t.name).toList(),
        'file': filenamePattern,
        'algo': algorithm.name,
        'pattern': pattern,
        'ci': caseInsensitive,
        'has': hasTags.toList(),
        'hasNot': hasNotTags.toList(),
        if (ifCorrespondent != null) 'ifCorr': ifCorrespondent,
        if (ifType != null) 'ifType': ifType,
        'title': titleTemplate,
        'add': addTags.toList(),
        'remove': removeTags.toList(),
        'removeAll': removeAllTags,
        if (setCorrespondent != null) 'corr': setCorrespondent,
        if (setType != null) 'type': setType,
        if (setStoragePath != null) 'path': setStoragePath,
        'fields': setFields,
        'asn': assignAsn,
        'reviewed': markReviewed,
        'note': addNote,
        'mod': modified,
        if (deleted) 'del': true,
      };

  static Set<String> _set(Object? v) =>
      ((v as List?) ?? const []).map((e) => '$e').toSet();

  factory Workflow.fromJson(Map<String, dynamic> j) => Workflow(
        id: j['id'] as String,
        name: j['name'] as String? ?? '',
        enabled: j['on'] as bool? ?? true,
        order: (j['order'] as num?)?.toInt() ?? 0,
        triggers: _set(j['triggers'])
            .map((n) => WorkflowTrigger.values.where((t) => t.name == n))
            .expand((e) => e)
            .toSet(),
        sources: _set(j['sources'])
            .map((n) => DocSource.values.where((t) => t.name == n))
            .expand((e) => e)
            .toSet(),
        filenamePattern: j['file'] as String? ?? '',
        algorithm: MatchAlgorithm.values.firstWhere(
          (a) => a.name == j['algo'],
          orElse: () => MatchAlgorithm.none,
        ),
        pattern: j['pattern'] as String? ?? '',
        caseInsensitive: j['ci'] as bool? ?? true,
        hasTags: _set(j['has']),
        hasNotTags: _set(j['hasNot']),
        ifCorrespondent: j['ifCorr'] as String?,
        ifType: j['ifType'] as String?,
        titleTemplate: j['title'] as String? ?? '',
        addTags: _set(j['add']),
        removeTags: _set(j['remove']),
        removeAllTags: j['removeAll'] as bool? ?? false,
        setCorrespondent: j['corr'] as String?,
        setType: j['type'] as String?,
        setStoragePath: j['path'] as String?,
        setFields: ((j['fields'] as Map?) ?? const {})
            .map((k, v) => MapEntry('$k', '$v')),
        assignAsn: j['asn'] as bool? ?? false,
        markReviewed: j['reviewed'] as bool? ?? false,
        addNote: j['note'] as String? ?? '',
        modified: (j['mod'] as num?)?.toInt() ?? 0,
        deleted: j['del'] as bool? ?? false,
      );
}

/// Converte un modello con * e ? in espressione regolare (senza maiuscole).
RegExp globToRegExp(String glob) {
  final b = StringBuffer('^');
  for (final rune in glob.runes) {
    final c = String.fromCharCode(rune);
    if (c == '*') {
      b.write('.*');
    } else if (c == '?') {
      b.write('.');
    } else {
      b.write(RegExp.escape(c));
    }
  }
  b.write(r'$');
  return RegExp(b.toString(), caseSensitive: false);
}

/// Vero se le condizioni del flusso valgono per il documento.
bool workflowMatches(
  Workflow w,
  Document d,
  WorkflowTrigger trigger, {
  DocSource? source,
}) {
  if (!w.enabled || w.deleted || !w.triggers.contains(trigger)) return false;
  if (trigger == WorkflowTrigger.added &&
      w.sources.isNotEmpty &&
      (source == null || !w.sources.contains(source))) {
    return false;
  }
  if (w.filenamePattern.trim().isNotEmpty &&
      !globToRegExp(w.filenamePattern.trim()).hasMatch(d.originalName)) {
    return false;
  }
  if (w.algorithm != MatchAlgorithm.none &&
      w.algorithm != MatchAlgorithm.auto &&
      !matchesRule(w, matchText(d))) {
    return false;
  }
  if (!w.hasTags.every(d.tagIds.contains)) return false;
  if (w.hasNotTags.any(d.tagIds.contains)) return false;
  if (w.ifCorrespondent != null && d.correspondentId != w.ifCorrespondent) {
    return false;
  }
  if (w.ifType != null && d.typeId != w.ifType) return false;
  return true;
}

String _two(int v) => v.toString().padLeft(2, '0');

const List<String> _monthNames = [
  'gennaio', 'febbraio', 'marzo', 'aprile', 'maggio', 'giugno',
  'luglio', 'agosto', 'settembre', 'ottobre', 'novembre', 'dicembre',
];

/// Segnaposti disponibili nei titoli (con descrizione).
const Map<String, String> titlePlaceholders = {
  '{title}': 'titolo attuale',
  '{correspondent}': 'corrispondente',
  '{document_type}': 'tipo di documento',
  '{created}': 'data documento (aaaa-mm-gg)',
  '{created_year}': 'anno',
  '{created_month}': 'mese (01-12)',
  '{created_day}': 'giorno',
  '{added}': 'data di aggiunta',
  '{original_filename}': 'nome del file senza estensione',
  '{asn}': 'numero d\'archivio',
  '{owner}': 'chi l\'ha aggiunto',
  '{kind}': 'cosa è nello specifico (Bonifico, Visura catastale…)',
  '{details}': 'beneficiario, numero o comune',
  '{amount}': 'importo',
};

/// Valori dei segnaposti per un documento. Con [facts] legge anche dal
/// testo tipo specifico, dettagli e importo (più lento).
Map<String, String> placeholderValues(Archive a, Document d, {bool facts = false}) {
  final f = facts ? extractFacts(d.content) : null;
  final added = DateTime.fromMillisecondsSinceEpoch(d.added);
  var name = d.originalName;
  final dot = name.lastIndexOf('.');
  if (dot > 0) name = name.substring(0, dot);
  return <String, String>{
    '{title}': d.title,
    '{correspondent}': a.correspondent(d.correspondentId)?.name ?? '',
    '{document_type}': a.type(d.typeId)?.name ?? '',
    '{created}': dateOnly(d.created),
    '{created_year}': '${d.created.year}',
    '{created_month}': _two(d.created.month),
    '{created_day}': _two(d.created.day),
    '{added}': dateOnly(added),
    '{original_filename}': name,
    '{asn}': d.asn?.toString() ?? '',
    '{owner}': d.owner ?? '',
    // Nomi di Paperless-ngx.
    '{created_year_short}': '${d.created.year % 100}'.padLeft(2, '0'),
    '{created_month_name}': _monthNames[d.created.month - 1],
    '{created_month_name_short}': _monthNames[d.created.month - 1].substring(0, 3),
    '{added_year}': '${added.year}',
    '{added_month}': _two(added.month),
    '{added_day}': _two(added.day),
    '{filename}': name,
    '{owner_username}': d.owner ?? '',
    '{doc_title}': d.title,
    if (f != null) '{kind}': f.label ?? a.type(d.typeId)?.name ?? '',
    if (f != null) '{details}': f.details,
    if (f != null) '{amount}': f.amountUseful ? f.amount! : '',
  };
}

/// Sostituisce i segnaposti (anche `{campo:Nome}`); [empty] dà il testo per
/// un valore vuoto (di default resta vuoto).
String fillPlaceholders(
  String template,
  Archive a,
  Document d, {
  String Function(String key)? empty,
  String Function(String value)? clean,
}) {
  // Accetta anche la sintassi di Paperless-ngx: {{ correspondent }}.
  template = template.replaceAllMapped(
    RegExp(r'\{\{\s*([a-z_]+(?::[^}]+)?)\s*\}\}'),
    (m) => '{${m.group(1)}}',
  );
  final values = placeholderValues(
    a,
    d,
    facts: template.contains('{kind}') || template.contains('{details}') || template.contains('{amount}'),
  );
  String c(String v) => clean == null ? v : clean(v);
  var out = template;
  values.forEach((k, v) {
    out = out.replaceAll(k, v.isEmpty && empty != null ? empty(k) : c(v));
  });
  out = out.replaceAllMapped(RegExp(r'\{campo:([^}]+)\}'), (m) {
    final fieldName = m.group(1)!.trim().toLowerCase();
    for (final f in a.activeFields) {
      if (f.name.toLowerCase() == fieldName) {
        final v = d.customFields[f.id] ?? '';
        return v.isEmpty && empty != null ? empty(m.group(0)!) : c(v);
      }
    }
    return empty?.call(m.group(0)!) ?? '';
  });
  return out;
}

/// Sostituisce i segnaposti del titolo; anche `{campo:Nome}` per i campi
/// personalizzati.
String renderTitle(String template, Archive a, Document d) {
  var out = fillPlaceholders(template, a, d);
  // Spazi doppi e separatori rimasti soli quando un valore è vuoto.
  out = out.replaceAll(RegExp(r'\s{2,}'), ' ').trim();
  out = out.replaceAll(RegExp(r'^[-–_·,\s]+|[-–_·,\s]+$'), '');
  return out;
}

/// Esegue le azioni di un flusso. Restituisce vero se qualcosa cambia.
bool runActions(Workflow w, Archive a, Document d) {
  final before = d.toJson().toString();
  if (w.removeAllTags) d.tagIds.clear();
  d.tagIds.removeAll(w.removeTags);
  for (final t in w.addTags) {
    if (a.tag(t) != null) d.tagIds.add(t);
  }
  if (w.setCorrespondent != null && a.correspondent(w.setCorrespondent) != null) {
    d.correspondentId = w.setCorrespondent;
  }
  if (w.setType != null && a.type(w.setType) != null) d.typeId = w.setType;
  if (w.setStoragePath != null && a.storagePath(w.setStoragePath) != null) {
    d.storagePathId = w.setStoragePath;
  }
  w.setFields.forEach((k, v) {
    if (a.fields[k] != null && !a.fields[k]!.deleted) d.customFields[k] = v;
  });
  if (w.assignAsn && d.asn == null) d.asn = a.nextAsn();
  if (w.markReviewed) {
    d.tagIds.removeAll(a.inboxTags.map((t) => t.id));
  }
  if (w.addNote.trim().isNotEmpty &&
      !d.notes.any((n) => n.text == w.addNote.trim())) {
    d.notes.add(Note(text: w.addNote.trim()));
  }
  if (w.titleTemplate.trim().isNotEmpty) {
    final t = renderTitle(w.titleTemplate, a, d);
    if (t.isNotEmpty) d.title = t;
  }
  return d.toJson().toString() != before;
}

/// Esegue, in ordine, tutti i flussi applicabili. Restituisce i nomi di
/// quelli eseguiti.
List<String> applyWorkflows(
  Archive a,
  Document d,
  WorkflowTrigger trigger, {
  DocSource? source,
}) {
  final ran = <String>[];
  final flows = a.activeWorkflows;
  for (final w in flows) {
    if (workflowMatches(w, d, trigger, source: source)) {
      runActions(w, a, d);
      ran.add(w.name);
    }
  }
  if (ran.isNotEmpty) d.touch();
  return ran;
}

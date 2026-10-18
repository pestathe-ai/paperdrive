/// Modelli dell'archivio: documenti, tag, corrispondenti, tipi, campi
/// personalizzati e viste salvate. Tutto è serializzabile in JSON, così
/// l'indice può essere salvato sul telefono e su Google Drive.
library;

import 'dart:math';

final Random _rnd = Random.secure();

/// Identificativo casuale di 16 caratteri esadecimali.
String newId() {
  final b = StringBuffer();
  for (var i = 0; i < 16; i++) {
    b.write(_rnd.nextInt(16).toRadixString(16));
  }
  return b.toString();
}

int nowMs() => DateTime.now().millisecondsSinceEpoch;

/// Chi sta usando l'app (email Google), per proprietario e autore modifiche.
class Session {
  static String? user;
}

/// Da dove arriva un documento.
enum DocSource { scan, file, mail }

extension DocSourceLabel on DocSource {
  String get label => switch (this) {
        DocSource.scan => 'Scansione',
        DocSource.file => 'File importato',
        DocSource.mail => 'Email',
      };
}

/// Algoritmi di assegnazione automatica, come in Paperless-ngx.
enum MatchAlgorithm { none, any, all, literal, regex, fuzzy, auto }

extension MatchAlgorithmLabel on MatchAlgorithm {
  String get label => switch (this) {
        MatchAlgorithm.none => 'Nessuna',
        MatchAlgorithm.any => 'Una qualsiasi parola',
        MatchAlgorithm.all => 'Tutte le parole',
        MatchAlgorithm.literal => 'Testo esatto',
        MatchAlgorithm.regex => 'Espressione regolare',
        MatchAlgorithm.fuzzy => 'Approssimata',
        MatchAlgorithm.auto => 'Automatica (impara)',
      };

  String get help => switch (this) {
        MatchAlgorithm.none => 'Mai assegnato in automatico.',
        MatchAlgorithm.any =>
          'Assegnato se il documento contiene almeno una delle parole. Usa le virgolette per le frasi.',
        MatchAlgorithm.all =>
          'Assegnato se il documento contiene tutte le parole.',
        MatchAlgorithm.literal =>
          'Assegnato se il documento contiene esattamente questo testo.',
        MatchAlgorithm.regex =>
          'Assegnato se l\'espressione regolare trova una corrispondenza.',
        MatchAlgorithm.fuzzy =>
          'Assegnato se il documento contiene un testo molto simile (tollera errori di OCR).',
        MatchAlgorithm.auto =>
          'Impara dai documenti a cui l\'hai già assegnato a mano (servono almeno 2 documenti).',
      };

  bool get needsPattern =>
      this != MatchAlgorithm.none && this != MatchAlgorithm.auto;
}

MatchAlgorithm _algo(Object? v) => MatchAlgorithm.values.firstWhere(
      (a) => a.name == v,
      orElse: () => MatchAlgorithm.none,
    );

/// Elemento con nome e regola di assegnazione (tag, corrispondente, tipo).
abstract class Matchable {
  String get id;
  String get name;
  MatchAlgorithm get algorithm;
  String get pattern;
  bool get caseInsensitive;
}

/// Campi comuni per la sincronizzazione: data di modifica e cancellazione.
mixin Syncable {
  int get modified;
  bool get deleted;
  String get id;
}

class Tag with Syncable implements Matchable {
  Tag({
    String? id,
    required this.name,
    this.color = 0xFF4E7D5B,
    this.isInbox = false,
    this.algorithm = MatchAlgorithm.none,
    this.pattern = '',
    this.caseInsensitive = true,
    int? modified,
    this.deleted = false,
  })  : id = id ?? newId(),
        modified = modified ?? nowMs();

  @override
  final String id;
  @override
  String name;
  int color;
  bool isInbox;
  @override
  MatchAlgorithm algorithm;
  @override
  String pattern;
  @override
  bool caseInsensitive;
  @override
  int modified;
  @override
  bool deleted;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'color': color,
        'inbox': isInbox,
        'algo': algorithm.name,
        'pattern': pattern,
        'ci': caseInsensitive,
        'mod': modified,
        if (deleted) 'del': true,
      };

  factory Tag.fromJson(Map<String, dynamic> j) => Tag(
        id: j['id'] as String,
        name: j['name'] as String? ?? '',
        color: (j['color'] as num?)?.toInt() ?? 0xFF4E7D5B,
        isInbox: j['inbox'] as bool? ?? false,
        algorithm: _algo(j['algo']),
        pattern: j['pattern'] as String? ?? '',
        caseInsensitive: j['ci'] as bool? ?? true,
        modified: (j['mod'] as num?)?.toInt() ?? 0,
        deleted: j['del'] as bool? ?? false,
      );
}

/// Corrispondente o tipo di documento: stessa forma, solo un nome diverso.
class NamedEntity with Syncable implements Matchable {
  NamedEntity({
    String? id,
    required this.name,
    this.algorithm = MatchAlgorithm.none,
    this.pattern = '',
    this.caseInsensitive = true,
    int? modified,
    this.deleted = false,
  })  : id = id ?? newId(),
        modified = modified ?? nowMs();

  @override
  final String id;
  @override
  String name;
  @override
  MatchAlgorithm algorithm;
  @override
  String pattern;
  @override
  bool caseInsensitive;
  @override
  int modified;
  @override
  bool deleted;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'algo': algorithm.name,
        'pattern': pattern,
        'ci': caseInsensitive,
        'mod': modified,
        if (deleted) 'del': true,
      };

  factory NamedEntity.fromJson(Map<String, dynamic> j) => NamedEntity(
        id: j['id'] as String,
        name: j['name'] as String? ?? '',
        algorithm: _algo(j['algo']),
        pattern: j['pattern'] as String? ?? '',
        caseInsensitive: j['ci'] as bool? ?? true,
        modified: (j['mod'] as num?)?.toInt() ?? 0,
        deleted: j['del'] as bool? ?? false,
      );
}

enum CustomFieldType { text, number, money, date, boolean, url }

extension CustomFieldTypeLabel on CustomFieldType {
  String get label => switch (this) {
        CustomFieldType.text => 'Testo',
        CustomFieldType.number => 'Numero',
        CustomFieldType.money => 'Importo (€)',
        CustomFieldType.date => 'Data',
        CustomFieldType.boolean => 'Sì/No',
        CustomFieldType.url => 'Link',
      };
}

class CustomField with Syncable {
  CustomField({
    String? id,
    required this.name,
    this.type = CustomFieldType.text,
    int? modified,
    this.deleted = false,
  })  : id = id ?? newId(),
        modified = modified ?? nowMs();

  @override
  final String id;
  String name;
  CustomFieldType type;
  @override
  int modified;
  @override
  bool deleted;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'type': type.name,
        'mod': modified,
        if (deleted) 'del': true,
      };

  factory CustomField.fromJson(Map<String, dynamic> j) => CustomField(
        id: j['id'] as String,
        name: j['name'] as String? ?? '',
        type: CustomFieldType.values.firstWhere(
          (t) => t.name == j['type'],
          orElse: () => CustomFieldType.text,
        ),
        modified: (j['mod'] as num?)?.toInt() ?? 0,
        deleted: j['del'] as bool? ?? false,
      );
}

class Note {
  Note({String? id, required this.text, int? created})
      : id = id ?? newId(),
        created = created ?? nowMs();

  final String id;
  String text;
  final int created;

  Map<String, dynamic> toJson() => {'id': id, 'text': text, 'at': created};

  factory Note.fromJson(Map<String, dynamic> j) => Note(
        id: j['id'] as String?,
        text: j['text'] as String? ?? '',
        created: (j['at'] as num?)?.toInt(),
      );
}

class Document with Syncable {
  Document({
    String? id,
    required this.title,
    DateTime? created,
    int? added,
    this.correspondentId,
    this.typeId,
    Set<String>? tagIds,
    this.content = '',
    List<Note>? notes,
    this.asn,
    this.originalName = '',
    this.pageCount = 0,
    Map<String, String>? customFields,
    this.inTrash = false,
    this.trashedAt,
    this.checksum = '',
    this.fileSize = 0,
    this.source = DocSource.file,
    String? owner,
    this.modifiedBy,
    this.archiveRev = 0,
    this.archiveSize = 0,
    this.shareLink,
    int? modified,
    this.deleted = false,
  })  : id = id ?? newId(),
        owner = owner ?? Session.user,
        created = created ?? DateTime.now(),
        added = added ?? nowMs(),
        tagIds = tagIds ?? <String>{},
        notes = notes ?? <Note>[],
        customFields = customFields ?? <String, String>{},
        modified = modified ?? nowMs();

  @override
  final String id;
  String title;

  /// Data del documento (non di aggiunta): solo giorno, mese, anno.
  DateTime created;

  /// Quando è stato aggiunto all'archivio (millisecondi).
  final int added;
  String? correspondentId;
  String? typeId;
  Set<String> tagIds;

  /// Testo letto dal PDF o dall'OCR.
  String content;
  List<Note> notes;

  /// Numero di serie d'archivio (ASN), utile per ritrovare l'originale cartaceo.
  int? asn;
  String originalName;
  int pageCount;

  /// Valori dei campi personalizzati: id campo -> valore come testo.
  Map<String, String> customFields;

  /// Nel cestino (recuperabile).
  bool inTrash;
  int? trashedAt;
  String checksum;
  int fileSize;
  DocSource source;

  /// Email di chi ha aggiunto il documento.
  String? owner;

  /// Email di chi l'ha modificato per ultimo.
  String? modifiedBy;

  /// Versione archiviata (PDF/A ricercabile): 0 se non esiste.
  int archiveRev;
  int archiveSize;

  /// Link pubblico di Google Drive, se attivo.
  String? shareLink;
  @override
  int modified;

  /// Eliminato definitivamente: resta solo come segnaposto per la
  /// sincronizzazione, senza contenuto.
  @override
  bool deleted;

  String get fileName => '$id.pdf';

  bool get hasArchive => archiveRev > 0;

  String get archiveFileName => '$id.archive$archiveRev.pdf';

  /// Tutti i file di questo documento (originale ed eventuale archiviato).
  List<String> get fileNames => [fileName, if (hasArchive) archiveFileName];

  void touch() {
    modified = nowMs();
    modifiedBy = Session.user ?? modifiedBy;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'created': _dateOnly(created),
        'added': added,
        if (correspondentId != null) 'corr': correspondentId,
        if (typeId != null) 'type': typeId,
        'tags': tagIds.toList()..sort(),
        'content': content,
        if (notes.isNotEmpty) 'notes': notes.map((n) => n.toJson()).toList(),
        if (asn != null) 'asn': asn,
        'orig': originalName,
        'pages': pageCount,
        if (customFields.isNotEmpty) 'cf': customFields,
        if (inTrash) 'trash': true,
        if (trashedAt != null) 'trashAt': trashedAt,
        'sum': checksum,
        'size': fileSize,
        'src': source.name,
        if (owner != null) 'owner': owner,
        if (modifiedBy != null) 'modBy': modifiedBy,
        if (archiveRev > 0) 'arch': archiveRev,
        if (archiveSize > 0) 'archSize': archiveSize,
        if (shareLink != null) 'link': shareLink,
        'mod': modified,
        if (deleted) 'del': true,
      };

  factory Document.fromJson(Map<String, dynamic> j) => Document(
        id: j['id'] as String,
        title: j['title'] as String? ?? '',
        created: _parseDate(j['created'] as String?),
        added: (j['added'] as num?)?.toInt(),
        correspondentId: j['corr'] as String?,
        typeId: j['type'] as String?,
        tagIds: ((j['tags'] as List?) ?? const []).cast<String>().toSet(),
        content: j['content'] as String? ?? '',
        notes: ((j['notes'] as List?) ?? const [])
            .map((n) => Note.fromJson((n as Map).cast<String, dynamic>()))
            .toList(),
        asn: (j['asn'] as num?)?.toInt(),
        originalName: j['orig'] as String? ?? '',
        pageCount: (j['pages'] as num?)?.toInt() ?? 0,
        customFields:
            ((j['cf'] as Map?) ?? const {}).map((k, v) => MapEntry('$k', '$v')),
        inTrash: j['trash'] as bool? ?? false,
        trashedAt: (j['trashAt'] as num?)?.toInt(),
        checksum: j['sum'] as String? ?? '',
        fileSize: (j['size'] as num?)?.toInt() ?? 0,
        source: DocSource.values.firstWhere(
          (x) => x.name == j['src'],
          orElse: () => DocSource.file,
        ),
        modifiedBy: j['modBy'] as String?,
        archiveRev: (j['arch'] as num?)?.toInt() ?? 0,
        archiveSize: (j['archSize'] as num?)?.toInt() ?? 0,
        shareLink: j['link'] as String?,
        modified: (j['mod'] as num?)?.toInt() ?? 0,
        deleted: j['del'] as bool? ?? false,
      )..owner = j['owner'] as String?;
}

String _two(int v) => v.toString().padLeft(2, '0');

String dateOnly(DateTime d) => _dateOnly(d);

String _dateOnly(DateTime d) => '${d.year}-${_two(d.month)}-${_two(d.day)}';

DateTime _parseDate(String? s) {
  if (s == null) return DateTime.now();
  final p = s.split('-');
  if (p.length != 3) return DateTime.tryParse(s) ?? DateTime.now();
  return DateTime(int.parse(p[0]), int.parse(p[1]), int.parse(p[2]));
}

/// Formato italiano gg/mm/aaaa.
String formatDate(DateTime d) => '${_two(d.day)}/${_two(d.month)}/${d.year}';

enum SortField { created, added, title, asn }

extension SortFieldLabel on SortField {
  String get label => switch (this) {
        SortField.created => 'Data documento',
        SortField.added => 'Data aggiunta',
        SortField.title => 'Titolo',
        SortField.asn => 'ASN',
      };
}

/// Filtro dei documenti. Usato dalla ricerca e dalle viste salvate.
class DocumentFilter {
  DocumentFilter({
    this.query = '',
    Set<String>? tagIds,
    Set<String>? excludedTagIds,
    this.correspondentId,
    this.typeId,
    this.from,
    this.to,
    this.inboxOnly = false,
    this.untaggedOnly = false,
    this.mineOnly = false,
    this.sort = SortField.created,
    this.descending = true,
  })  : tagIds = tagIds ?? <String>{},
        excludedTagIds = excludedTagIds ?? <String>{};

  String query;
  Set<String> tagIds;
  Set<String> excludedTagIds;
  String? correspondentId;
  String? typeId;
  DateTime? from;
  DateTime? to;
  bool inboxOnly;
  bool untaggedOnly;

  /// Solo i documenti aggiunti da me (archivio condiviso).
  bool mineOnly;
  SortField sort;
  bool descending;

  bool get isEmpty =>
      query.trim().isEmpty &&
      tagIds.isEmpty &&
      excludedTagIds.isEmpty &&
      correspondentId == null &&
      typeId == null &&
      from == null &&
      to == null &&
      !inboxOnly &&
      !untaggedOnly &&
      !mineOnly;

  DocumentFilter copy() => DocumentFilter.fromJson(toJson());

  Map<String, dynamic> toJson() => {
        'q': query,
        'tags': tagIds.toList(),
        'xtags': excludedTagIds.toList(),
        if (correspondentId != null) 'corr': correspondentId,
        if (typeId != null) 'type': typeId,
        if (from != null) 'from': _dateOnly(from!),
        if (to != null) 'to': _dateOnly(to!),
        'inbox': inboxOnly,
        'untagged': untaggedOnly,
        'mine': mineOnly,
        'sort': sort.name,
        'desc': descending,
      };

  factory DocumentFilter.fromJson(Map<String, dynamic> j) => DocumentFilter(
        query: j['q'] as String? ?? '',
        tagIds: ((j['tags'] as List?) ?? const []).cast<String>().toSet(),
        excludedTagIds:
            ((j['xtags'] as List?) ?? const []).cast<String>().toSet(),
        correspondentId: j['corr'] as String?,
        typeId: j['type'] as String?,
        from: j['from'] == null ? null : _parseDate(j['from'] as String),
        to: j['to'] == null ? null : _parseDate(j['to'] as String),
        inboxOnly: j['inbox'] as bool? ?? false,
        untaggedOnly: j['untagged'] as bool? ?? false,
        mineOnly: j['mine'] as bool? ?? false,
        sort: SortField.values.firstWhere(
          (s) => s.name == j['sort'],
          orElse: () => SortField.created,
        ),
        descending: j['desc'] as bool? ?? true,
      );
}

class SavedView with Syncable {
  SavedView({
    String? id,
    required this.name,
    required this.filter,
    this.showOnHome = true,
    int? modified,
    this.deleted = false,
  })  : id = id ?? newId(),
        modified = modified ?? nowMs();

  @override
  final String id;
  String name;
  DocumentFilter filter;
  bool showOnHome;
  @override
  int modified;
  @override
  bool deleted;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'filter': filter.toJson(),
        'home': showOnHome,
        'mod': modified,
        if (deleted) 'del': true,
      };

  factory SavedView.fromJson(Map<String, dynamic> j) => SavedView(
        id: j['id'] as String,
        name: j['name'] as String? ?? '',
        filter: DocumentFilter.fromJson(
            ((j['filter'] as Map?) ?? const {}).cast<String, dynamic>()),
        showOnHome: j['home'] as bool? ?? true,
        modified: (j['mod'] as num?)?.toInt() ?? 0,
        deleted: j['del'] as bool? ?? false,
      );
}

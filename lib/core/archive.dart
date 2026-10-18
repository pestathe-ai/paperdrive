/// L'archivio completo (l'"indice"): tutti i documenti e le entità,
/// serializzato in un unico file JSON.
library;

import 'models.dart';
import 'workflows.dart';

class Archive {
  Archive({
    Map<String, Document>? documents,
    Map<String, Tag>? tags,
    Map<String, NamedEntity>? correspondents,
    Map<String, NamedEntity>? types,
    Map<String, CustomField>? fields,
    Map<String, SavedView>? views,
    Map<String, Workflow>? workflows,
  })  : workflows = workflows ?? {},
        documents = documents ?? {},
        tags = tags ?? {},
        correspondents = correspondents ?? {},
        types = types ?? {},
        fields = fields ?? {},
        views = views ?? {};

  static const int formatVersion = 1;

  final Map<String, Document> documents;
  final Map<String, Tag> tags;
  final Map<String, NamedEntity> correspondents;
  final Map<String, NamedEntity> types;
  final Map<String, CustomField> fields;
  final Map<String, SavedView> views;
  final Map<String, Workflow> workflows;

  static List<T> _alive<T extends Syncable>(Map<String, T> m) =>
      m.values.where((e) => !e.deleted).toList();

  static int _byName(String a, String b) =>
      a.toLowerCase().compareTo(b.toLowerCase());

  /// Documenti visibili (non eliminati e non nel cestino).
  List<Document> get activeDocuments =>
      documents.values.where((d) => !d.deleted && !d.inTrash).toList();

  List<Document> get trashedDocuments =>
      documents.values.where((d) => !d.deleted && d.inTrash).toList();

  List<Tag> get activeTags =>
      _alive(tags)..sort((a, b) => _byName(a.name, b.name));
  List<NamedEntity> get activeCorrespondents =>
      _alive(correspondents)..sort((a, b) => _byName(a.name, b.name));
  List<NamedEntity> get activeTypes =>
      _alive(types)..sort((a, b) => _byName(a.name, b.name));
  List<CustomField> get activeFields =>
      _alive(fields)..sort((a, b) => _byName(a.name, b.name));
  List<SavedView> get activeViews =>
      _alive(views)..sort((a, b) => _byName(a.name, b.name));
  List<Workflow> get activeWorkflows => _alive(workflows)
    ..sort((a, b) {
      final c = a.order.compareTo(b.order);
      return c != 0 ? c : _byName(a.name, b.name);
    });

  Tag? tag(String? id) {
    final t = id == null ? null : tags[id];
    return t == null || t.deleted ? null : t;
  }

  NamedEntity? correspondent(String? id) {
    final c = id == null ? null : correspondents[id];
    return c == null || c.deleted ? null : c;
  }

  NamedEntity? type(String? id) {
    final t = id == null ? null : types[id];
    return t == null || t.deleted ? null : t;
  }

  Iterable<Tag> get inboxTags => activeTags.where((t) => t.isInbox);

  /// Prossimo numero ASN libero.
  int nextAsn() {
    var max = 0;
    for (final d in documents.values) {
      if (!d.deleted && (d.asn ?? 0) > max) max = d.asn!;
    }
    return max + 1;
  }

  /// Documento attivo che ha già lo stesso contenuto (stesso checksum).
  Document? duplicateOf(String checksum) {
    if (checksum.isEmpty) return null;
    for (final d in documents.values) {
      if (!d.deleted && d.checksum == checksum) return d;
    }
    return null;
  }

  int countWithTag(String tagId) =>
      activeDocuments.where((d) => d.tagIds.contains(tagId)).length;
  int countWithCorrespondent(String id) =>
      activeDocuments.where((d) => d.correspondentId == id).length;
  int countWithType(String id) =>
      activeDocuments.where((d) => d.typeId == id).length;

  /// Elimina definitivamente un documento: resta un segnaposto vuoto
  /// perché anche gli altri dispositivi e Drive sappiano che è stato tolto.
  void purge(Document d) {
    d
      ..deleted = true
      ..inTrash = false
      ..content = ''
      ..title = ''
      ..notes = []
      ..tagIds = {}
      ..customFields = {}
      ..shareLink = null
      ..touch();
  }

  /// Toglie un tag, un corrispondente o un tipo cancellato dai documenti.
  void detachTag(String tagId) {
    for (final d in documents.values) {
      if (d.tagIds.remove(tagId)) d.touch();
    }
  }

  void detachCorrespondent(String id) {
    for (final d in documents.values) {
      if (d.correspondentId == id) {
        d
          ..correspondentId = null
          ..touch();
      }
    }
  }

  void detachType(String id) {
    for (final d in documents.values) {
      if (d.typeId == id) {
        d
          ..typeId = null
          ..touch();
      }
    }
  }

  Map<String, dynamic> toJson() => {
        'format': formatVersion,
        'app': 'paperdrive',
        'documents': documents.values.map((e) => e.toJson()).toList(),
        'tags': tags.values.map((e) => e.toJson()).toList(),
        'correspondents': correspondents.values.map((e) => e.toJson()).toList(),
        'types': types.values.map((e) => e.toJson()).toList(),
        'fields': fields.values.map((e) => e.toJson()).toList(),
        'views': views.values.map((e) => e.toJson()).toList(),
        'workflows': workflows.values.map((e) => e.toJson()).toList(),
      };

  static Map<String, T> _read<T extends Syncable>(
    Object? list,
    T Function(Map<String, dynamic>) f,
  ) {
    final out = <String, T>{};
    for (final raw in (list as List?) ?? const []) {
      final e = f((raw as Map).cast<String, dynamic>());
      out[e.id] = e;
    }
    return out;
  }

  factory Archive.fromJson(Map<String, dynamic> j) => Archive(
        documents: _read(j['documents'], Document.fromJson),
        tags: _read(j['tags'], Tag.fromJson),
        correspondents: _read(j['correspondents'], NamedEntity.fromJson),
        types: _read(j['types'], NamedEntity.fromJson),
        fields: _read(j['fields'], CustomField.fromJson),
        views: _read(j['views'], SavedView.fromJson),
        workflows: _read(j['workflows'], Workflow.fromJson),
      );

  /// Archivio iniziale con un tag "Da esaminare" (inbox), come Paperless.
  factory Archive.starter() {
    final a = Archive();
    final inbox = Tag(name: 'Da esaminare', color: 0xFFC62828, isInbox: true);
    a.tags[inbox.id] = inbox;
    return a;
  }
}

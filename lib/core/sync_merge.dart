/// Unione di due archivi (telefono e Google Drive): per ogni elemento vince
/// la versione modificata più di recente. Le cancellazioni sono segnaposti,
/// quindi si propagano anch'esse.
library;

import 'archive.dart';
import 'models.dart';

class MergeReport {
  int fromRemote = 0;
  int fromLocal = 0;

  /// Il risultato è diverso dall'archivio remoto (va ricaricato su Drive).
  bool get remoteChanged => fromLocal > 0;

  /// Il risultato è diverso dall'archivio locale.
  bool get localChanged => fromRemote > 0;
}

Map<String, T> _mergeMap<T extends Syncable>(
  Map<String, T> local,
  Map<String, T> remote,
  MergeReport r,
) {
  final out = <String, T>{};
  final ids = {...local.keys, ...remote.keys};
  for (final id in ids) {
    final l = local[id];
    final rm = remote[id];
    if (l == null) {
      out[id] = rm as T;
      r.fromRemote++;
    } else if (rm == null) {
      out[id] = l;
      r.fromLocal++;
    } else if (rm.modified > l.modified) {
      out[id] = rm;
      r.fromRemote++;
    } else if (l.modified > rm.modified) {
      out[id] = l;
      r.fromLocal++;
    } else {
      // Stessa data: una cancellazione vince.
      out[id] = rm.deleted && !l.deleted ? rm : l;
      if (l.deleted && !rm.deleted) r.fromLocal++;
      if (rm.deleted && !l.deleted) r.fromRemote++;
    }
  }
  return out;
}

/// Unisce [local] e [remote] in un nuovo archivio.
(Archive, MergeReport) mergeArchives(Archive local, Archive remote) {
  final r = MergeReport();
  final merged = Archive(
    documents: _mergeMap(local.documents, remote.documents, r),
    tags: _mergeMap(local.tags, remote.tags, r),
    correspondents: _mergeMap(local.correspondents, remote.correspondents, r),
    types: _mergeMap(local.types, remote.types, r),
    fields: _mergeMap(local.fields, remote.fields, r),
    views: _mergeMap(local.views, remote.views, r),
  );
  return (merged, r);
}

/// Piano dei file da spostare dopo l'unione.
class FilePlan {
  FilePlan({
    required this.upload,
    required this.download,
    required this.deleteRemote,
    required this.deleteLocal,
  });

  /// Documenti presenti sul telefono ma non su Drive.
  final List<Document> upload;

  /// Documenti presenti su Drive ma non sul telefono.
  final List<Document> download;

  /// Nomi di file su Drive da eliminare (documenti eliminati).
  final List<String> deleteRemote;

  /// Nomi di file sul telefono da eliminare.
  final List<String> deleteLocal;
}

/// Decide quali PDF caricare, scaricare o eliminare.
FilePlan planFiles(
  Archive merged, {
  required Set<String> localFiles,
  required Set<String> remoteFiles,
}) {
  final upload = <Document>[];
  final download = <Document>[];
  final deleteRemote = <String>[];
  final deleteLocal = <String>[];
  for (final d in merged.documents.values) {
    final name = d.fileName;
    final local = localFiles.contains(name);
    final remote = remoteFiles.contains(name);
    if (d.deleted) {
      if (remote) deleteRemote.add(name);
      if (local) deleteLocal.add(name);
    } else if (local && !remote) {
      upload.add(d);
    } else if (remote && !local) {
      download.add(d);
    }
  }
  return FilePlan(
    upload: upload,
    download: download,
    deleteRemote: deleteRemote,
    deleteLocal: deleteLocal,
  );
}

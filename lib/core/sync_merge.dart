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
    workflows: _mergeMap(local.workflows, remote.workflows, r),
    storagePaths: _mergeMap(local.storagePaths, remote.storagePaths, r),
    config: remote.config.modified > local.config.modified ? remote.config : local.config,
  );
  if (remote.config.modified > local.config.modified) r.fromRemote++;
  if (local.config.modified > remote.config.modified) r.fromLocal++;
  return (merged, r);
}

/// Piano dei file da spostare dopo l'unione (nomi di file).
class FilePlan {
  FilePlan({
    required this.upload,
    required this.download,
    required this.deleteRemote,
    required this.deleteLocal,
  });

  /// File presenti sul telefono ma non su Drive.
  final List<String> upload;

  /// File presenti su Drive ma non sul telefono.
  final List<String> download;

  /// File su Drive da eliminare (documenti eliminati o versioni superate).
  final List<String> deleteRemote;

  /// File sul telefono da eliminare.
  final List<String> deleteLocal;
}

/// Id del documento a cui appartiene un file (`<id>.pdf`, `<id>.archive3.pdf`).
String docIdOfFile(String name) {
  final dot = name.indexOf('.');
  return dot < 0 ? name : name.substring(0, dot);
}

/// Decide quali PDF caricare, scaricare o eliminare.
///
/// I file di documenti sconosciuti (non ancora nell'indice) restano intatti.
FilePlan planFiles(
  Archive merged, {
  required Set<String> localFiles,
  required Set<String> remoteFiles,
  bool canWrite = true,
}) {
  final upload = <String>[];
  final download = <String>[];
  final deleteRemote = <String>[];
  final deleteLocal = <String>[];
  final expected = <String>{};
  for (final d in merged.documents.values) {
    if (d.deleted) continue;
    for (final name in d.fileNames) {
      expected.add(name);
      final local = localFiles.contains(name);
      final remote = remoteFiles.contains(name);
      if (local && !remote && canWrite) upload.add(name);
      if (remote && !local) download.add(name);
    }
  }
  bool known(String name) => merged.documents.containsKey(docIdOfFile(name));
  for (final name in remoteFiles) {
    if (canWrite && known(name) && !expected.contains(name)) {
      deleteRemote.add(name);
    }
  }
  for (final name in localFiles) {
    if (known(name) && !expected.contains(name)) deleteLocal.add(name);
  }
  upload.sort();
  download.sort();
  deleteRemote.sort();
  deleteLocal.sort();
  return FilePlan(
    upload: upload,
    download: download,
    deleteRemote: deleteRemote,
    deleteLocal: deleteLocal,
  );
}

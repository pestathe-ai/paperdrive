import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;

import '../core/archive.dart';
import '../core/import_hint.dart' show inboxFolderName;
import '../core/models.dart';
import '../core/organize.dart';
import '../core/sync_merge.dart';
import 'storage.dart';

/// Serve l'accesso a Google (l'utente deve toccare "Collega").
class DriveAuthRequired implements Exception {
  @override
  String toString() =>
      'Serve l\'accesso a Google Drive: apri Impostazioni e tocca "Collega" (o "Ricollega").';
}

class SyncOutcome {
  SyncOutcome({
    required this.archive,
    required this.uploaded,
    required this.downloaded,
    required this.removed,
    required this.organized,
    required this.folderId,
    required this.canEdit,
    required this.ownerEmail,
    required this.downloadedNames,
  });
  final Archive archive;
  final int uploaded;
  final int downloaded;
  final int removed;

  /// File rinominati o spostati nelle cartelle giuste.
  final int organized;
  final String folderId;
  final bool canEdit;
  final String? ownerEmail;

  /// File appena scaricati (nomi interni, servono le anteprime).
  final List<String> downloadedNames;
}

/// Persona con accesso all'archivio condiviso.
class DriveMember {
  DriveMember({
    required this.permissionId,
    required this.email,
    required this.name,
    required this.role,
    required this.type,
  });
  final String permissionId;
  final String email;
  final String name;

  /// owner, writer, commenter, reader.
  final String role;

  /// user, group, domain, anyone.
  final String type;

  String get roleLabel => switch (role) {
        'owner' => 'Proprietario',
        'organizer' || 'fileOrganizer' || 'writer' => 'Può modificare',
        'commenter' || 'reader' => 'Solo lettura',
        _ => role,
      };
}

/// Cartella condivisa da un'altra persona.
class SharedFolder {
  SharedFolder(this.id, this.name, this.owner);
  final String id;
  final String name;
  final String owner;
}

/// Un file dell'archivio su Drive.
class _Remote {
  _Remote(this.id, this.name, this.parents, this.version, this.tagged);
  final String id;
  final String name;
  final List<String> parents;
  final String? version;

  /// Ha già le proprietà Paperdrive (altrimenti è un file della v0.1/v0.2).
  final bool tagged;
}

/// Sincronizza l'archivio con la cartella "Paperdrive" su Google Drive.
///
/// Sul telefono i file hanno nomi interni (`<id>.pdf`, `<id>.archive2.pdf`);
/// su Drive hanno nomi leggibili dentro cartelle come `Bolletta/2024/`.
/// Il legame è nelle proprietà del file su Drive (pdArchive, pdDoc, pdKind).
/// Un file da importare, con le cartelle (relative a "Da importare").
class InboxFile {
  InboxFile(this.id, this.name, this.folders);
  final String id;
  final String name;
  final List<String> folders;
}

class DriveSync {
  DriveSync(this.storage);

  final Storage storage;

  /// Accesso completo a Drive: serve per gli archivi condivisi da altri.
  static const List<String> scopes = [drive.DriveApi.driveScope];
  static const String folderName = 'Paperdrive';
  static const String indexName = 'paperdrive-index.json';
  static const String folderMime = 'application/vnd.google-apps.folder';
  static final RegExp _internalName = RegExp(r'^[A-Za-z0-9-]+(\.archive\d+)?\.pdf$');

  bool _initialized = false;
  String? _lastToken;

  Future<void> _init() async {
    if (_initialized) return;
    await GoogleSignIn.instance.initialize();
    _initialized = true;
  }

  Future<drive.DriveApi> _api({required bool interactive}) async {
    await _init();
    final client = GoogleSignIn.instance.authorizationClient;
    var auth = await client.authorizationForScopes(scopes);
    if (auth == null) {
      if (!interactive) throw DriveAuthRequired();
      auth = await client.authorizeScopes(scopes);
    }
    _lastToken = auth.accessToken;
    return drive.DriveApi(auth.authClient(scopes: scopes));
  }

  /// Ripete una volta se il token è scaduto.
  Future<T> _withApi<T>(Future<T> Function(drive.DriveApi) f, {bool interactive = false}) async {
    try {
      return await f(await _api(interactive: interactive));
    } on drive.DetailedApiRequestError catch (e) {
      if (e.status == 401 && _lastToken != null) {
        await GoogleSignIn.instance.authorizationClient
            .clearAuthorizationToken(accessToken: _lastToken!);
        return f(await _api(interactive: interactive));
      }
      rethrow;
    }
  }

  /// Chiede l'accesso (mostra la scelta dell'account) e restituisce l'email.
  Future<String?> connect() => _withApi((api) async {
        final about = await api.about.get($fields: 'user(emailAddress,displayName)');
        return about.user?.emailAddress ?? about.user?.displayName;
      }, interactive: true);

  Future<void> disconnect() async {
    await _init();
    try {
      await GoogleSignIn.instance.disconnect();
    } catch (_) {
      await GoogleSignIn.instance.signOut();
    }
  }

  static String _q(String s) => s.replaceAll(r'\', r'\\').replaceAll("'", r"\'");

  /// La mia cartella "Paperdrive" (creata se manca).
  Future<String> _ownFolder(drive.DriveApi api) async {
    final res = await api.files.list(
      q: "name = '${_q(folderName)}' and mimeType = '$folderMime' "
          "and 'me' in owners and trashed = false",
      spaces: 'drive',
      $fields: 'files(id,name)',
    );
    final found = res.files ?? const <drive.File>[];
    if (found.isNotEmpty && found.first.id != null) return found.first.id!;
    final created = await api.files.create(
      drive.File()
        ..name = folderName
        ..mimeType = folderMime,
      $fields: 'id',
    );
    return created.id!;
  }

  Future<List<drive.File>> _listAll(drive.DriveApi api, String q) async {
    final out = <drive.File>[];
    String? token;
    do {
      final res = await api.files.list(
        q: q,
        spaces: 'drive',
        pageSize: 1000,
        pageToken: token,
        $fields: 'nextPageToken, files(id,name,parents,properties,version,mimeType)',
      );
      out.addAll(res.files ?? const <drive.File>[]);
      token = res.nextPageToken;
    } while (token != null);
    return out;
  }

  static String? _logicalName(Map<String, String?>? props) {
    final doc = props?['pdDoc'];
    if (doc == null || doc.isEmpty) return null;
    final rev = props?['pdRev'] ?? '0';
    if (props?['pdKind'] == 'arch') return '$doc.archive$rev.pdf';
    return rev == '0' ? '$doc.pdf' : '$doc.v$rev.pdf';
  }

  /// Tutti i file dell'archivio, per nome interno; più l'indice.
  Future<(Map<String, _Remote>, _Remote?)> _remoteFiles(drive.DriveApi api, String root) async {
    final out = <String, _Remote>{};
    final tagged = await _listAll(
      api,
      "properties has { key='pdArchive' and value='${_q(root)}' } and trashed = false",
    );
    for (final f in tagged) {
      final name = _logicalName(f.properties);
      if (name == null || f.id == null) continue;
      out[name] = _Remote(f.id!, f.name ?? '', f.parents ?? const [], f.version, true);
    }
    _Remote? index;
    final top = await _listAll(api, "'${_q(root)}' in parents and trashed = false");
    for (final f in top) {
      final name = f.name ?? '';
      if (f.id == null) continue;
      if (name == indexName) {
        index = _Remote(f.id!, name, f.parents ?? const [], f.version, false);
      } else if (f.mimeType != folderMime &&
          _logicalName(f.properties) == null &&
          _internalName.hasMatch(name) &&
          !out.containsKey(name)) {
        // File delle versioni precedenti, ancora con il nome interno.
        out[name] = _Remote(f.id!, name, f.parents ?? const [], f.version, false);
      }
    }
    return (out, index);
  }

  Future<List<int>> _download(drive.DriveApi api, String id) async {
    final media = await api.files.get(
      id,
      downloadOptions: drive.DownloadOptions.fullMedia,
    ) as drive.Media;
    final bytes = <int>[];
    await for (final chunk in media.stream) {
      bytes.addAll(chunk);
    }
    return bytes;
  }

  drive.Media _media(List<int> bytes, String type) =>
      drive.Media(Stream.value(bytes), bytes.length, contentType: type);

  /// Elimina un file; se non è mio (archivio condiviso) lo toglie dalla cartella.
  Future<void> _remove(drive.DriveApi api, _Remote f) async {
    try {
      await api.files.delete(f.id);
    } on drive.DetailedApiRequestError catch (e) {
      if (e.status == 404) return;
      if (e.status == 403) {
        try {
          await api.files.update(drive.File(), f.id, removeParents: f.parents.join(','));
        } catch (_) {}
        return;
      }
      rethrow;
    }
  }

  /// Cartelle già trovate o create durante questa sincronizzazione.
  final Map<String, String> _folders = {};

  Future<String> _folderFor(drive.DriveApi api, String root, List<String> segments) async {
    var parent = root;
    var key = root;
    for (final seg in segments) {
      key = '$key/$seg';
      final cached = _folders[key];
      if (cached != null) {
        parent = cached;
        continue;
      }
      final res = await api.files.list(
        q: "'${_q(parent)}' in parents and name = '${_q(seg)}' "
            "and mimeType = '$folderMime' and trashed = false",
        spaces: 'drive',
        $fields: 'files(id)',
      );
      final found = res.files ?? const <drive.File>[];
      final id = found.isNotEmpty && found.first.id != null
          ? found.first.id!
          : (await api.files.create(
              drive.File()
                ..name = seg
                ..mimeType = folderMime
                ..parents = [parent],
              $fields: 'id',
            ))
              .id!;
      _folders[key] = id;
      parent = id;
    }
    return parent;
  }

  Map<String, String> _props(String root, Document d, bool archived) => {
        'pdArchive': root,
        'pdDoc': d.id,
        'pdKind': archived ? 'arch' : 'orig',
        'pdRev': archived ? '${d.archiveRev}' : '${d.fileRev}',
      };

  /// Dove deve stare un file su Drive: cartella e nome leggibile.
  Future<(String, String)> _placeOf(
    drive.DriveApi api,
    Archive a,
    String root,
    Document d,
    bool archived,
  ) async {
    final (folders, _) = drivePath(a, d);
    final name = driveFileName(a, d, archived: archived);
    final parent = a.config.organizeDrive ? await _folderFor(api, root, folders) : root;
    return (parent, name);
  }

  /// Esegue la sincronizzazione completa e restituisce l'archivio unito.
  Future<SyncOutcome> sync(
    Archive local, {
    required String? folderId,
    void Function(String)? status,
  }) =>
      _withApi((api) => _sync(api, local, folderId: folderId, status: status));

  Future<SyncOutcome> _sync(
    drive.DriveApi api,
    Archive local, {
    required String? folderId,
    void Function(String)? status,
  }) async {
    status?.call('Connessione a Google Drive…');
    _folders.clear();
    final root = folderId ?? await _ownFolder(api);
    final drive.File info;
    try {
      info = await api.files.get(
        root,
        $fields: 'id,trashed,capabilities(canEdit),owners(emailAddress,displayName)',
      ) as drive.File;
    } on drive.DetailedApiRequestError catch (e) {
      if (e.status == 404) {
        throw Exception('La cartella dell\'archivio non è più accessibile. '
            'Forse la condivisione è stata tolta: apri "Utenti e condivisione".');
      }
      rethrow;
    }
    final canWrite = info.capabilities?.canEdit ?? true;
    // La cartella "Da importare" c'è sempre, così si vede subito su Drive.
    if (canWrite) {
      try {
        await _folderFor(api, root, [inboxFolderName]);
      } catch (_) {}
    }
    final owners = info.owners ?? const <drive.User>[];
    final ownerEmail = owners.isEmpty ? null : owners.first.emailAddress;

    var current = local;
    var uploaded = 0, removed = 0, organized = 0;
    final downloadedNames = <String>[];
    for (var attempt = 0; attempt < 3; attempt++) {
      var (remoteFiles, index) = await _remoteFiles(api, root);

      status?.call('Confronto degli archivi…');
      Archive remote = Archive();
      String? remoteRaw;
      if (index != null) {
        remoteRaw = utf8.decode(await _download(api, index.id));
        remote = Archive.fromJson((jsonDecode(remoteRaw) as Map).cast<String, dynamic>());
      }
      final (merged, _) = mergeArchives(current, remote);
      current = merged;

      final plan = planFiles(
        merged,
        localFiles: await storage.localFileNames(),
        remoteFiles: remoteFiles.keys.toSet(),
        canWrite: canWrite,
      );

      var i = 0;
      for (final name in plan.upload) {
        i++;
        status?.call('Caricamento su Drive: $i di ${plan.upload.length}');
        final d = merged.documents[docIdOfFile(name)]!;
        final archived = name.contains('.archive');
        final (parent, driveName) = await _placeOf(api, merged, root, d, archived);
        final bytes = await storage.docFile(name).readAsBytes();
        final created = await api.files.create(
          drive.File()
            ..name = driveName
            ..parents = [parent]
            ..properties = _props(root, d, archived),
          uploadMedia: _media(bytes, 'application/pdf'),
          $fields: 'id',
        );
        remoteFiles[name] = _Remote(created.id!, driveName, [parent], null, true);
        uploaded++;
      }

      i = 0;
      for (final name in plan.download) {
        i++;
        status?.call('Download da Drive: $i di ${plan.download.length}');
        final bytes = await _download(api, remoteFiles[name]!.id);
        final target = storage.docFile(name);
        final tmp = File('${target.path}.part');
        await tmp.writeAsBytes(bytes, flush: true);
        await tmp.rename(target.path);
        downloadedNames.add(name);
      }

      for (final name in plan.deleteRemote) {
        await _remove(api, remoteFiles.remove(name)!);
        removed++;
      }
      for (final name in plan.deleteLocal) {
        final f = storage.docFile(name);
        if (await f.exists()) await f.delete();
        final owner = merged.documents[docIdOfFile(name)];
        if (owner == null || owner.deleted) {
          final thumb = storage.thumbFile(docIdOfFile(name));
          if (await thumb.exists()) await thumb.delete();
        }
        removed++;
      }

      // Ogni file nella sua cartella (categoria/anno) e con il nome giusto.
      if (canWrite) {
        for (final d in merged.documents.values) {
          if (d.deleted) continue;
          for (final name in d.fileNames) {
            final r = remoteFiles[name];
            if (r == null) continue;
            final archived = name.contains('.archive');
            final (parent, driveName) = await _placeOf(api, merged, root, d, archived);
            final moved = !(r.parents.length == 1 && r.parents.first == parent);
            if (r.name == driveName && !moved && r.tagged) continue;
            status?.call('Archiviazione: $driveName');
            try {
              await api.files.update(
                drive.File()
                  ..name = driveName
                  ..properties = _props(root, d, archived),
                r.id,
                addParents: moved ? parent : null,
                removeParents: moved && r.parents.isNotEmpty ? r.parents.join(',') : null,
                $fields: 'id',
              );
              organized++;
            } on drive.DetailedApiRequestError catch (e) {
              // File di un'altra persona che non posso spostare: resta dov'è.
              if (e.status != 403) rethrow;
            }
          }
        }
      }

      final mergedRaw = jsonEncode(merged.toJson());
      if (!canWrite || mergedRaw == remoteRaw) break;

      if (index != null) {
        // Qualcun altro ha aggiornato l'indice nel frattempo? Si riunisce.
        final now = await api.files.get(index.id, $fields: 'version') as drive.File;
        if (now.version != index.version && attempt < 2) {
          status?.call('Indice aggiornato da un altro dispositivo, nuova unione…');
          continue;
        }
      }
      status?.call('Salvataggio dell\'indice su Drive…');
      final bytes = utf8.encode(mergedRaw);
      if (index == null) {
        await api.files.create(
          drive.File()
            ..name = indexName
            ..parents = [root],
          uploadMedia: _media(bytes, 'application/json'),
          $fields: 'id',
        );
      } else {
        await api.files.update(
          drive.File(),
          index.id,
          uploadMedia: _media(bytes, 'application/json'),
          $fields: 'id',
        );
      }
      break;
    }

    return SyncOutcome(
      archive: current,
      uploaded: uploaded,
      downloaded: downloadedNames.length,
      removed: removed,
      organized: organized,
      folderId: root,
      canEdit: canWrite,
      ownerEmail: ownerEmail,
      downloadedNames: downloadedNames,
    );
  }

  Future<_Remote?> _find(drive.DriveApi api, String root, String logical) async {
    final (files, _) = await _remoteFiles(api, root);
    return files[logical];
  }

  /// Scarica un singolo PDF che manca sul telefono.
  Future<bool> fetchFile(String fileName, {required String? folderId}) =>
      _withApi((api) async {
        final root = folderId ?? await _ownFolder(api);
        final f = await _find(api, root, fileName);
        if (f == null) return false;
        final bytes = await _download(api, f.id);
        await storage.docFile(fileName).writeAsBytes(bytes, flush: true);
        return true;
      });

  // ------------------------------------------------------------------
  // Cartella di importazione ("Da importare")

  /// I file nella cartella "Da importare" (e sottocartelle), con le
  /// cartelle in cui stanno. La cartella viene creata se manca.
  Future<List<InboxFile>> listInbox({required String? folderId}) => _withApi((api) async {
        final root = folderId ?? await _ownFolder(api);
        final inbox = await _folderFor(api, root, [inboxFolderName]);
        final out = <InboxFile>[];
        Future<void> walk(String id, List<String> path) async {
          final items = await _listAll(api, "'${_q(id)}' in parents and trashed = false");
          for (final f in items) {
            if (f.id == null) continue;
            if (f.mimeType == folderMime) {
              if (path.length < 8) await walk(f.id!, [...path, f.name ?? '']);
            } else {
              out.add(InboxFile(f.id!, f.name ?? 'documento', path));
            }
          }
        }

        await walk(inbox, const []);
        out.sort((x, y) => '${x.folders.join('/')}/${x.name}'.compareTo('${y.folders.join('/')}/${y.name}'));
        return out;
      });

  Future<Uint8List> downloadInboxFile(String id) =>
      _withApi((api) async => Uint8List.fromList(await _download(api, id)));

  /// Sposta il file importato nel cestino di Drive (recuperabile per 30 giorni).
  Future<void> trashInboxFile(String id) => _withApi((api) async {
        try {
          await api.files.update(drive.File()..trashed = true, id);
        } on drive.DetailedApiRequestError catch (e) {
          if (e.status != 404) rethrow;
        }
      });

  /// Toglie le sottocartelle rimaste vuote in "Da importare".
  Future<void> cleanInbox({required String? folderId}) => _withApi((api) async {
        final root = folderId ?? await _ownFolder(api);
        final inbox = await _folderFor(api, root, [inboxFolderName]);
        Future<bool> clean(String id, {bool top = false}) async {
          final items = await _listAll(api, "'${_q(id)}' in parents and trashed = false");
          var empty = true;
          for (final f in items) {
            if (f.id == null) continue;
            if (f.mimeType == folderMime && await clean(f.id!)) continue;
            empty = false;
          }
          if (empty && !top) {
            try {
              await api.files.update(drive.File()..trashed = true, id);
            } catch (_) {
              return false;
            }
          }
          return empty;
        }

        await clean(inbox, top: true);
      });

  // ------------------------------------------------------------------
  // Condivisione

  Future<String> ownFolderId() => _withApi(_ownFolder);

  /// Cartelle condivise con me (di solito l'archivio Paperdrive di un altro).
  Future<List<SharedFolder>> sharedFolders() => _withApi((api) async {
        final res = await api.files.list(
          q: "sharedWithMe and mimeType = '$folderMime' and trashed = false",
          spaces: 'drive',
          pageSize: 200,
          $fields: 'files(id,name,owners(emailAddress,displayName))',
        );
        final out = <SharedFolder>[];
        for (final f in res.files ?? const <drive.File>[]) {
          final o = (f.owners ?? const <drive.User>[]);
          final owner = o.isEmpty ? '' : (o.first.displayName ?? o.first.emailAddress ?? '');
          out.add(SharedFolder(f.id!, f.name ?? '', owner));
        }
        out.sort((a, b) {
          final pa = a.name.toLowerCase().contains('paperdrive') ? 0 : 1;
          final pb = b.name.toLowerCase().contains('paperdrive') ? 0 : 1;
          return pa != pb ? pa.compareTo(pb) : a.name.compareTo(b.name);
        });
        return out;
      });

  Future<List<DriveMember>> members(String? folderId) => _withApi((api) async {
        final folder = folderId ?? await _ownFolder(api);
        final res = await api.permissions.list(
          folder,
          $fields: 'permissions(id,emailAddress,displayName,role,type)',
        );
        return [
          for (final p in res.permissions ?? const <drive.Permission>[])
            DriveMember(
              permissionId: p.id ?? '',
              email: p.emailAddress ?? '',
              name: p.displayName ??
                  p.emailAddress ??
                  (p.type == 'anyone' ? 'Chiunque abbia il link' : ''),
              role: p.role ?? '',
              type: p.type ?? '',
            ),
        ];
      });

  /// Invita una persona (riceve un'email da Google).
  Future<void> invite(String? folderId, String email, {required bool canEdit, String? message}) =>
      _withApi((api) async {
        final folder = folderId ?? await _ownFolder(api);
        await api.permissions.create(
          drive.Permission()
            ..type = 'user'
            ..role = canEdit ? 'writer' : 'reader'
            ..emailAddress = email.trim(),
          folder,
          sendNotificationEmail: true,
          emailMessage: message,
        );
      });

  Future<void> setRole(String? folderId, String permissionId, {required bool canEdit}) =>
      _withApi((api) async {
        final folder = folderId ?? await _ownFolder(api);
        await api.permissions.update(
          drive.Permission()..role = canEdit ? 'writer' : 'reader',
          folder,
          permissionId,
        );
      });

  Future<void> removeMember(String? folderId, String permissionId) => _withApi((api) async {
        final folder = folderId ?? await _ownFolder(api);
        await api.permissions.delete(folder, permissionId);
      });

  /// Crea un link pubblico (chiunque abbia il link può vedere) per un file.
  Future<String> createPublicLink(String? folderId, String fileName) => _withApi((api) async {
        final root = folderId ?? await _ownFolder(api);
        final f = await _find(api, root, fileName);
        if (f == null) {
          throw Exception('Il file non è ancora su Drive: sincronizza e riprova.');
        }
        await api.permissions.create(
          drive.Permission()
            ..type = 'anyone'
            ..role = 'reader',
          f.id,
        );
        final meta = await api.files.get(f.id, $fields: 'webViewLink') as drive.File;
        return meta.webViewLink ?? 'https://drive.google.com/file/d/${f.id}/view';
      });

  Future<void> revokePublicLink(String? folderId, String fileName) => _withApi((api) async {
        final root = folderId ?? await _ownFolder(api);
        final f = await _find(api, root, fileName);
        if (f == null) return;
        final perms = await api.permissions.list(f.id, $fields: 'permissions(id,type)');
        for (final p in perms.permissions ?? const <drive.Permission>[]) {
          if (p.type == 'anyone' && p.id != null) {
            await api.permissions.delete(f.id, p.id!);
          }
        }
      });
}

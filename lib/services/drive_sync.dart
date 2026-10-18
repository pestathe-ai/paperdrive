import 'dart:convert';
import 'dart:io';

import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;

import '../core/archive.dart';
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
    required this.folderId,
    required this.canEdit,
    required this.ownerEmail,
    required this.downloadedNames,
  });
  final Archive archive;
  final int uploaded;
  final int downloaded;
  final int removed;
  final String folderId;
  final bool canEdit;
  final String? ownerEmail;

  /// File appena scaricati (servono le anteprime).
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

/// Cartella "Paperdrive" condivisa da un'altra persona.
class SharedFolder {
  SharedFolder(this.id, this.name, this.owner);
  final String id;
  final String name;
  final String owner;
}

/// Sincronizza l'archivio con una cartella "Paperdrive" su Google Drive e
/// gestisce la condivisione con altre persone.
class DriveSync {
  DriveSync(this.storage);

  final Storage storage;

  /// Accesso completo a Drive: serve per gli archivi condivisi da altri.
  static const List<String> scopes = [drive.DriveApi.driveScope];
  static const String folderName = 'Paperdrive';
  static const String indexName = 'paperdrive-index.json';
  static const String folderMime = 'application/vnd.google-apps.folder';

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

  static String _escape(String s) => s.replaceAll("'", "\\'");

  /// La mia cartella "Paperdrive" (creata se manca).
  Future<String> _ownFolder(drive.DriveApi api) async {
    final res = await api.files.list(
      q: "name = '${_escape(folderName)}' and mimeType = '$folderMime' "
          "and 'me' in owners and trashed = false",
      spaces: 'drive',
      $fields: 'files(id,name,parents)',
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

  Future<Map<String, (String, String?)>> _listFolder(drive.DriveApi api, String folder) async {
    final out = <String, (String, String?)>{};
    String? token;
    do {
      final res = await api.files.list(
        q: "'$folder' in parents and trashed = false",
        spaces: 'drive',
        pageSize: 1000,
        pageToken: token,
        $fields: 'nextPageToken, files(id,name,version)',
      );
      for (final f in res.files ?? const <drive.File>[]) {
        if (f.name != null && f.id != null) out[f.name!] = (f.id!, f.version);
      }
      token = res.nextPageToken;
    } while (token != null);
    return out;
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
  Future<void> _remove(drive.DriveApi api, String id, String folder) async {
    try {
      await api.files.delete(id);
    } on drive.DetailedApiRequestError catch (e) {
      if (e.status == 404) return;
      if (e.status == 403) {
        try {
          await api.files.update(drive.File(), id, removeParents: folder);
        } catch (_) {}
        return;
      }
      rethrow;
    }
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
    final folder = folderId ?? await _ownFolder(api);
    final drive.File info;
    try {
      info = await api.files.get(
        folder,
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
    final owners = info.owners ?? const <drive.User>[];
    final ownerEmail = owners.isEmpty ? null : owners.first.emailAddress;

    var current = local;
    var uploaded = 0, removed = 0;
    final downloadedNames = <String>[];
    for (var attempt = 0; attempt < 3; attempt++) {
      final remoteFiles = await _listFolder(api, folder);

      status?.call('Confronto degli archivi…');
      Archive remote = Archive();
      String? remoteRaw;
      final index = remoteFiles[indexName];
      if (index != null) {
        remoteRaw = utf8.decode(await _download(api, index.$1));
        remote = Archive.fromJson((jsonDecode(remoteRaw) as Map).cast<String, dynamic>());
      }
      final (merged, _) = mergeArchives(current, remote);
      current = merged;

      final plan = planFiles(
        merged,
        localFiles: await storage.localFileNames(),
        remoteFiles: remoteFiles.keys.where((n) => n.endsWith('.pdf')).toSet(),
        canWrite: canWrite,
      );

      var i = 0;
      for (final name in plan.upload) {
        i++;
        status?.call('Caricamento su Drive: $i di ${plan.upload.length}');
        final bytes = await storage.docFile(name).readAsBytes();
        await api.files.create(
          drive.File()
            ..name = name
            ..parents = [folder],
          uploadMedia: _media(bytes, 'application/pdf'),
          $fields: 'id',
        );
        uploaded++;
      }

      i = 0;
      for (final name in plan.download) {
        i++;
        status?.call('Download da Drive: $i di ${plan.download.length}');
        final bytes = await _download(api, remoteFiles[name]!.$1);
        final target = storage.docFile(name);
        final tmp = File('${target.path}.part');
        await tmp.writeAsBytes(bytes, flush: true);
        await tmp.rename(target.path);
        downloadedNames.add(name);
      }

      for (final name in plan.deleteRemote) {
        await _remove(api, remoteFiles[name]!.$1, folder);
        removed++;
      }
      for (final name in plan.deleteLocal) {
        final f = storage.docFile(name);
        if (await f.exists()) await f.delete();
        if (!name.contains('.archive')) {
          final thumb = storage.thumbFile(docIdOfFile(name));
          if (await thumb.exists()) await thumb.delete();
        }
        removed++;
      }

      final mergedRaw = jsonEncode(merged.toJson());
      if (!canWrite || mergedRaw == remoteRaw) break;

      if (index != null) {
        // Qualcun altro ha aggiornato l'indice nel frattempo? Si riunisce.
        final now = await api.files.get(index.$1, $fields: 'version') as drive.File;
        if (now.version != index.$2 && attempt < 2) {
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
            ..parents = [folder],
          uploadMedia: _media(bytes, 'application/json'),
          $fields: 'id',
        );
      } else {
        await api.files.update(
          drive.File(),
          index.$1,
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
      folderId: folder,
      canEdit: canWrite,
      ownerEmail: ownerEmail,
      downloadedNames: downloadedNames,
    );
  }

  /// Scarica un singolo PDF che manca sul telefono.
  Future<bool> fetchFile(String fileName, {required String? folderId}) =>
      _withApi((api) async {
        final folder = folderId ?? await _ownFolder(api);
        final files = await _listFolder(api, folder);
        final f = files[fileName];
        if (f == null) return false;
        final bytes = await _download(api, f.$1);
        await storage.docFile(fileName).writeAsBytes(bytes, flush: true);
        return true;
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
        // Prima quelle che si chiamano Paperdrive.
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
              name: p.displayName ?? p.emailAddress ?? (p.type == 'anyone' ? 'Chiunque abbia il link' : ''),
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
        final folder = folderId ?? await _ownFolder(api);
        final files = await _listFolder(api, folder);
        final f = files[fileName];
        if (f == null) {
          throw Exception('Il file non è ancora su Drive: sincronizza e riprova.');
        }
        await api.permissions.create(
          drive.Permission()
            ..type = 'anyone'
            ..role = 'reader',
          f.$1,
        );
        final meta = await api.files.get(f.$1, $fields: 'webViewLink') as drive.File;
        return meta.webViewLink ?? 'https://drive.google.com/file/d/${f.$1}/view';
      });

  Future<void> revokePublicLink(String? folderId, String fileName) => _withApi((api) async {
        final folder = folderId ?? await _ownFolder(api);
        final files = await _listFolder(api, folder);
        final f = files[fileName];
        if (f == null) return;
        final perms = await api.permissions.list(f.$1, $fields: 'permissions(id,type)');
        for (final p in perms.permissions ?? const <drive.Permission>[]) {
          if (p.type == 'anyone' && p.id != null) {
            await api.permissions.delete(f.$1, p.id!);
          }
        }
      });
}

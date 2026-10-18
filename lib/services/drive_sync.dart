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
  String toString() => 'Serve l\'accesso a Google Drive: apri Impostazioni e tocca "Collega".';
}

class SyncOutcome {
  SyncOutcome(this.archive, this.uploaded, this.downloaded, this.removed);
  final Archive archive;
  final int uploaded;
  final int downloaded;
  final int removed;

  /// Nomi dei PDF appena scaricati (servono le anteprime).
  final List<String> downloadedIds = [];
}

/// Sincronizza l'archivio con una cartella "Paperdrive" su Google Drive.
///
/// Usa solo il permesso `drive.file`: l'app vede esclusivamente i file che
/// ha creato lei, non il resto del Drive.
class DriveSync {
  DriveSync(this.storage);

  final Storage storage;

  static const List<String> scopes = [drive.DriveApi.driveFileScope];
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

  /// Chiede l'accesso (mostra la scelta dell'account) e restituisce l'email.
  Future<String?> connect() async {
    final api = await _api(interactive: true);
    final about = await api.about.get($fields: 'user(emailAddress,displayName)');
    await _folderId(api);
    return about.user?.emailAddress ?? about.user?.displayName;
  }

  Future<void> disconnect() async {
    await _init();
    try {
      await GoogleSignIn.instance.disconnect();
    } catch (_) {
      await GoogleSignIn.instance.signOut();
    }
  }

  static String _escape(String s) => s.replaceAll("'", "\\'");

  Future<String> _folderId(drive.DriveApi api) async {
    final res = await api.files.list(
      q: "name = '${_escape(folderName)}' and mimeType = '$folderMime' and trashed = false",
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

  Future<Map<String, String>> _listFolder(drive.DriveApi api, String folder) async {
    final out = <String, String>{};
    String? token;
    do {
      final res = await api.files.list(
        q: "'$folder' in parents and trashed = false",
        spaces: 'drive',
        pageSize: 1000,
        pageToken: token,
        $fields: 'nextPageToken, files(id,name)',
      );
      for (final f in res.files ?? const <drive.File>[]) {
        if (f.name != null && f.id != null) out[f.name!] = f.id!;
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

  /// Esegue la sincronizzazione completa e restituisce l'archivio unito.
  Future<SyncOutcome> sync(
    Archive local, {
    void Function(String)? status,
  }) async {
    try {
      return await _sync(local, status: status);
    } on drive.DetailedApiRequestError catch (e) {
      if (e.status == 401 && _lastToken != null) {
        // Token scaduto: lo si scarta e si riprova una volta.
        await GoogleSignIn.instance.authorizationClient
            .clearAuthorizationToken(accessToken: _lastToken!);
        return _sync(local, status: status);
      }
      rethrow;
    }
  }

  Future<SyncOutcome> _sync(Archive local, {void Function(String)? status}) async {
    status?.call('Connessione a Google Drive…');
    final api = await _api(interactive: false);
    final folder = await _folderId(api);
    final remoteFiles = await _listFolder(api, folder);

    status?.call('Confronto degli archivi…');
    Archive remote = Archive();
    String? remoteRaw;
    final indexId = remoteFiles[indexName];
    if (indexId != null) {
      remoteRaw = utf8.decode(await _download(api, indexId));
      remote = Archive.fromJson(
          (jsonDecode(remoteRaw) as Map).cast<String, dynamic>());
    }
    final (merged, _) = mergeArchives(local, remote);

    final plan = planFiles(
      merged,
      localFiles: await storage.localFileNames(),
      remoteFiles: remoteFiles.keys.where((n) => n.endsWith('.pdf')).toSet(),
    );

    var i = 0;
    for (final d in plan.upload) {
      i++;
      status?.call('Caricamento su Drive: $i di ${plan.upload.length}');
      final bytes = await storage.docFile(d.fileName).readAsBytes();
      await api.files.create(
        drive.File()
          ..name = d.fileName
          ..parents = [folder],
        uploadMedia: _media(bytes, 'application/pdf'),
        $fields: 'id',
      );
    }

    final downloaded = <String>[];
    i = 0;
    for (final d in plan.download) {
      i++;
      status?.call('Download da Drive: $i di ${plan.download.length}');
      final bytes = await _download(api, remoteFiles[d.fileName]!);
      final target = storage.docFile(d.fileName);
      final tmp = File('${target.path}.part');
      await tmp.writeAsBytes(bytes, flush: true);
      await tmp.rename(target.path);
      downloaded.add(d.id);
    }

    for (final name in plan.deleteRemote) {
      try {
        await api.files.delete(remoteFiles[name]!);
      } on drive.DetailedApiRequestError catch (e) {
        if (e.status != 404) rethrow;
      }
    }
    for (final name in plan.deleteLocal) {
      final f = storage.docFile(name);
      if (await f.exists()) await f.delete();
      final thumb = storage.thumbFile(name.replaceAll('.pdf', ''));
      if (await thumb.exists()) await thumb.delete();
    }

    final mergedRaw = jsonEncode(merged.toJson());
    if (mergedRaw != remoteRaw) {
      status?.call('Salvataggio dell\'indice su Drive…');
      final bytes = utf8.encode(mergedRaw);
      if (indexId == null) {
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
          indexId,
          uploadMedia: _media(bytes, 'application/json'),
          $fields: 'id',
        );
      }
    }

    return SyncOutcome(
      merged,
      plan.upload.length,
      plan.download.length,
      plan.deleteRemote.length + plan.deleteLocal.length,
    )..downloadedIds.addAll(downloaded);
  }

  /// Scarica un singolo PDF che manca sul telefono.
  Future<bool> fetchFile(String fileName) async {
    final api = await _api(interactive: false);
    final folder = await _folderId(api);
    final files = await _listFolder(api, folder);
    final id = files[fileName];
    if (id == null) return false;
    final bytes = await _download(api, id);
    await storage.docFile(fileName).writeAsBytes(bytes, flush: true);
    return true;
  }
}

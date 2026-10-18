import 'package:material_ui/material_ui.dart';

import '../services/drive_sync.dart';
import '../state/app_state.dart';
import 'settings_screen.dart';
import 'widgets.dart';

/// Più utenti: chi può vedere o modificare l'archivio, e archivi condivisi
/// da altre persone.
class SharingScreen extends StatefulWidget {
  const SharingScreen({super.key});

  @override
  State<SharingScreen> createState() => _SharingScreenState();
}

class _SharingScreenState extends State<SharingScreen> {
  Future<List<DriveMember>>? _members;
  bool working = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final app = AppScope.read(context);
    if (_members == null && app.settings.driveEnabled) _members = app.members();
  }

  void _reload() => setState(() => _members = AppScope.read(context).members());

  Future<void> _run(Future<void> Function() f, String ok) async {
    setState(() => working = true);
    try {
      await f();
      if (mounted) showMessage(context, ok);
    } catch (e) {
      if (mounted) showMessage(context, 'Errore: $e');
    } finally {
      if (mounted) {
        setState(() => working = false);
        _reload();
      }
    }
  }

  Future<void> invite(AppState app) async {
    final email = TextEditingController();
    final msg = TextEditingController(text: 'Ti invito al mio archivio documenti Paperdrive.');
    var canEdit = true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setD) => AlertDialog(
          title: const Text('Invita una persona'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: email,
                  autofocus: true,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(labelText: 'Email Google'),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Può modificare'),
                  subtitle: Text(canEdit ? 'Aggiunge e modifica documenti' : 'Solo lettura'),
                  value: canEdit,
                  onChanged: (v) => setD(() => canEdit = v),
                ),
                TextField(
                  controller: msg,
                  maxLines: 3,
                  decoration: const InputDecoration(labelText: 'Messaggio'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Annulla')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Invita')),
          ],
        ),
      ),
    );
    final address = email.text.trim();
    final message = msg.text.trim();
    email.dispose();
    msg.dispose();
    if (ok != true || !address.contains('@')) return;
    await _run(
      () => app.invite(address, canEdit: canEdit, message: message.isEmpty ? null : message),
      'Invito inviato a $address',
    );
  }

  Future<void> join(AppState app) async {
    setState(() => working = true);
    List<SharedFolder> folders;
    try {
      folders = await app.sharedFolders();
    } catch (e) {
      if (mounted) showMessage(context, 'Errore: $e');
      return;
    } finally {
      if (mounted) setState(() => working = false);
    }
    if (!mounted) return;
    if (folders.isEmpty) {
      showMessage(context, 'Nessuna cartella condivisa con te. Chiedi all\'altra persona di invitarti.');
      return;
    }
    final chosen = await showModalBottomSheet<SharedFolder>(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text('Scegli l\'archivio condiviso con te'),
            ),
            for (final f in folders)
              ListTile(
                leading: const Icon(Icons.folder_shared_outlined),
                title: Text(f.name),
                subtitle: Text('di ${f.owner}'),
                onTap: () => Navigator.pop(c, f),
              ),
          ],
        ),
      ),
    );
    if (chosen == null || !mounted) return;
    final mine = app.archive.activeDocuments.length;
    var keepMine = false;
    if (mine > 0) {
      final r = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('I tuoi documenti'),
          content: Text('Hai $mine documenti su questo telefono. Vuoi aggiungerli all\'archivio '
              'di ${chosen.owner}? Altrimenti verranno tolti dal telefono (restano nel tuo Drive).'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c), child: const Text('Annulla')),
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Non aggiungerli')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Aggiungili')),
          ],
        ),
      );
      if (r == null) return;
      keepMine = r;
    }
    await _run(() => app.joinShared(chosen, keepMine: keepMine), 'Ora usi l\'archivio di ${chosen.owner}');
  }

  Future<void> leave(AppState app) async {
    final r = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Tornare al tuo archivio?'),
        content: const Text('Puoi tenere sul telefono una copia dei documenti condivisi '
            '(verranno caricati anche nel tuo Drive) oppure toglierli.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Annulla')),
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Toglili')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Tieni una copia')),
        ],
      ),
    );
    if (r == null) return;
    await _run(() => app.leaveShared(keepCopy: r), 'Sei tornato al tuo archivio');
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final s = app.settings;
    final theme = Theme.of(context);
    if (!s.driveEnabled) {
      return Scaffold(
        appBar: AppBar(title: const Text('Utenti e condivisione')),
        body: EmptyState(
          icon: Icons.group_outlined,
          text: 'Per condividere l\'archivio con altre persone serve Google Drive.',
          action: FilledButton(
            onPressed: () => Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
            child: const Text('Collega Google Drive'),
          ),
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Utenti e condivisione')),
      floatingActionButton: s.driveShared && !s.driveCanEdit
          ? null
          : FloatingActionButton.extended(
              onPressed: working ? null : () => invite(app),
              icon: const Icon(Icons.person_add_alt),
              label: const Text('Invita'),
            ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 96),
        children: [
          if (working) const LinearProgressIndicator(minHeight: 2),
          ListTile(
            leading: Icon(s.driveShared ? Icons.folder_shared_outlined : Icons.folder_outlined),
            title: Text(s.driveShared
                ? 'Archivio di ${s.driveFolderOwner ?? 'un\'altra persona'}'
                : 'Il tuo archivio personale'),
            subtitle: Text(s.driveShared
                ? (s.driveCanEdit ? 'Puoi aggiungere e modificare' : 'Sola lettura')
                : 'Cartella "Paperdrive" nel tuo Drive · tu: ${s.driveAccount ?? ''}'),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Wrap(
              spacing: 8,
              children: [
                if (!s.driveShared)
                  OutlinedButton.icon(
                    onPressed: working ? null : () => join(app),
                    icon: const Icon(Icons.login),
                    label: const Text('Usa un archivio condiviso con me'),
                  )
                else
                  OutlinedButton.icon(
                    onPressed: working ? null : () => leave(app),
                    icon: const Icon(Icons.logout),
                    label: const Text('Torna al mio archivio'),
                  ),
              ],
            ),
          ),
          const Divider(height: 32),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text('Chi ha accesso', style: theme.textTheme.titleMedium),
          ),
          FutureBuilder<List<DriveMember>>(
            future: _members,
            builder: (c, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              if (snap.hasError) {
                return ListTile(
                  leading: Icon(Icons.error_outline, color: theme.colorScheme.error),
                  title: const Text('Impossibile leggere le persone'),
                  subtitle: Text('${snap.error}'),
                  trailing: IconButton(icon: const Icon(Icons.refresh), onPressed: _reload),
                );
              }
              final list = snap.data ?? const <DriveMember>[];
              final canManage = !s.driveShared;
              return Column(
                children: [
                  for (final m in list)
                    ListTile(
                      leading: CircleAvatar(
                        child: Text((m.name.isEmpty ? '?' : m.name[0]).toUpperCase()),
                      ),
                      title: Text(m.name.isEmpty ? m.email : m.name),
                      subtitle: Text([
                        if (m.email.isNotEmpty && m.email != m.name) m.email,
                        m.roleLabel,
                        if (m.email == s.driveAccount) 'tu',
                      ].join(' · ')),
                      trailing: !canManage || m.role == 'owner'
                          ? null
                          : PopupMenuButton<String>(
                              onSelected: (v) {
                                switch (v) {
                                  case 'edit':
                                    _run(() => app.setMemberRole(m, canEdit: true), 'Ora può modificare');
                                  case 'read':
                                    _run(() => app.setMemberRole(m, canEdit: false), 'Ora è in sola lettura');
                                  case 'remove':
                                    _run(() => app.removeMember(m), 'Accesso tolto');
                                }
                              },
                              itemBuilder: (_) => const [
                                PopupMenuItem(value: 'edit', child: Text('Può modificare')),
                                PopupMenuItem(value: 'read', child: Text('Solo lettura')),
                                PopupMenuItem(value: 'remove', child: Text('Togli accesso')),
                              ],
                            ),
                    ),
                ],
              );
            },
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'Come funziona: l\'archivio è la cartella "Paperdrive" su Google Drive. '
              'Chi inviti riceve un\'email da Google; poi, nella sua app Paperdrive, apre '
              '"Utenti e condivisione" e sceglie "Usa un archivio condiviso con me". '
              'Ogni documento ricorda chi l\'ha aggiunto e chi l\'ha modificato per ultimo. '
              'I permessi li applica Google Drive: chi ha accesso vede tutti i documenti dell\'archivio.',
              style: theme.textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

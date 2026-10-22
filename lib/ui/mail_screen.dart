import 'package:material_ui/material_ui.dart';

import '../core/mail_rules.dart';
import '../core/models.dart';
import '../services/mail_import.dart';
import '../state/app_state.dart';
import 'widgets.dart';

/// Account email e regole di importazione.
class MailScreen extends StatelessWidget {
  const MailScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final cfg = app.mail;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Importazione da email')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 48),
        children: [
          if (app.busy != null && app.checkingMail)
            Column(children: [
              const LinearProgressIndicator(minHeight: 2),
              Padding(padding: const EdgeInsets.all(8), child: Text(app.busy!)),
            ]),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text(
              'D. Paper Lab legge le caselle con IMAP e importa gli allegati (PDF e immagini) '
              'o il testo dei messaggi che rispettano le tue regole. Il controllo avviene '
              'all\'apertura dell\'app e quando tocchi "Controlla ora".',
              style: theme.textTheme.bodySmall,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: FilledButton.icon(
              onPressed: app.checkingMail || cfg.rules.isEmpty || app.readOnly
                  ? null
                  : () async {
                      try {
                        final r = await app.checkMail();
                        if (context.mounted) showMessage(context, r);
                      } catch (e) {
                        if (context.mounted) showMessage(context, 'Errore: $e');
                      }
                    },
              icon: const Icon(Icons.mark_email_read_outlined),
              label: const Text('Controlla ora'),
            ),
          ),
          SwitchListTile(
            title: const Text('Controlla all\'apertura dell\'app'),
            value: cfg.checkOnOpen,
            onChanged: (v) {
              cfg.checkOnOpen = v;
              app.saveMail();
            },
          ),
          if (cfg.lastResult != null)
            ListTile(
              leading: const Icon(Icons.history),
              title: Text(cfg.lastCheck == null
                  ? 'Ultimo controllo'
                  : 'Ultimo controllo: ${formatDate(DateTime.fromMillisecondsSinceEpoch(cfg.lastCheck!))} '
                      '${TimeOfDay.fromDateTime(DateTime.fromMillisecondsSinceEpoch(cfg.lastCheck!)).format(context)}'),
              subtitle: Text(cfg.lastResult!),
            ),
          const Divider(),
          ListTile(
            title: Text('Account', style: theme.textTheme.titleMedium),
            trailing: TextButton.icon(
              icon: const Icon(Icons.add),
              label: const Text('Aggiungi'),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const MailAccountEditor()),
              ),
            ),
          ),
          if (cfg.accounts.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Text('Nessun account. Aggiungi la casella da cui importare.'),
            ),
          for (final acc in cfg.accounts)
            ListTile(
              leading: const Icon(Icons.alternate_email),
              title: Text(acc.name),
              subtitle: Text('${acc.email} · ${acc.host}'),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => MailAccountEditor(account: acc)),
              ),
            ),
          const Divider(),
          ListTile(
            title: Text('Regole', style: theme.textTheme.titleMedium),
            trailing: TextButton.icon(
              icon: const Icon(Icons.add),
              label: const Text('Aggiungi'),
              onPressed: cfg.accounts.isEmpty
                  ? null
                  : () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => MailRuleEditor(
                            rule: MailRule(name: '', accountId: cfg.accounts.first.id),
                            isNew: true,
                          ),
                        ),
                      ),
            ),
          ),
          if (cfg.rules.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Text('Nessuna regola. Esempio: dalla cartella INBOX, mittente "enel", '
                  'importa gli allegati PDF, tag "Bollette", poi segna come letto.'),
            ),
          for (final r in cfg.rules)
            ListTile(
              leading: Switch(
                value: r.enabled,
                onChanged: (v) {
                  r.enabled = v;
                  app.saveMail();
                },
              ),
              title: Text(r.name),
              subtitle: Text(
                '${cfg.account(r.accountId)?.name ?? '?'} · ${r.folder} · ultimi ${r.maxAgeDays} giorni'
                '${r.fromFilter.isEmpty ? '' : ' · da "${r.fromFilter}"'}'
                '${r.subjectFilter.isEmpty ? '' : ' · oggetto "${r.subjectFilter}"'}',
              ),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => MailRuleEditor(rule: MailRule.fromJson(r.toJson())),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class MailAccountEditor extends StatefulWidget {
  const MailAccountEditor({super.key, this.account});

  final MailAccount? account;

  @override
  State<MailAccountEditor> createState() => _MailAccountEditorState();
}

class _MailAccountEditorState extends State<MailAccountEditor> {
  late final name = TextEditingController(text: widget.account?.name ?? '');
  late final email = TextEditingController(text: widget.account?.email ?? '');
  late final host = TextEditingController(text: widget.account?.host ?? '');
  late final port = TextEditingController(text: '${widget.account?.port ?? 993}');
  late final user = TextEditingController(text: widget.account?.username ?? '');
  late final pass = TextEditingController(text: widget.account?.password ?? '');
  late bool ssl = widget.account?.ssl ?? true;
  bool working = false;
  bool showPass = false;
  String? result;

  @override
  void dispose() {
    for (final c in [name, email, host, port, user, pass]) {
      c.dispose();
    }
    super.dispose();
  }

  MailAccount _build() => MailAccount(
        id: widget.account?.id,
        name: name.text.trim().isEmpty ? email.text.trim() : name.text.trim(),
        email: email.text.trim(),
        host: host.text.trim(),
        port: int.tryParse(port.text.trim()) ?? 993,
        ssl: ssl,
        username: user.text.trim().isEmpty ? email.text.trim() : user.text.trim(),
        password: pass.text,
      );

  Future<void> discover() async {
    final e = email.text.trim();
    if (!e.contains('@')) return;
    setState(() => working = true);
    final s = await discoverImap(e);
    if (!mounted) return;
    setState(() {
      working = false;
      if (s != null) {
        host.text = s.host;
        port.text = '${s.port}';
        ssl = s.ssl;
        if (user.text.isEmpty) user.text = e;
        result = 'Server trovato: ${s.host}';
      } else {
        result = 'Server non trovato in automatico: inseriscilo a mano.';
      }
    });
  }

  Future<void> test() async {
    setState(() {
      working = true;
      result = null;
    });
    try {
      final boxes = await MailImporter.testAccount(_build());
      result = 'Accesso riuscito. Cartelle: ${boxes.take(12).join(', ')}${boxes.length > 12 ? '…' : ''}';
    } catch (e) {
      result = 'Accesso non riuscito: $e';
    }
    if (mounted) setState(() => working = false);
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.account == null ? 'Nuovo account' : 'Modifica account'),
        actions: [
          if (widget.account != null)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: () async {
                if (!await confirm(context,
                    title: 'Eliminare l\'account?',
                    message: 'Verranno eliminate anche le sue regole.',
                    ok: 'Elimina',
                    danger: true)) {
                  return;
                }
                app.mail.accounts.removeWhere((a) => a.id == widget.account!.id);
                app.mail.rules.removeWhere((r) => r.accountId == widget.account!.id);
                await app.saveMail();
                if (context.mounted) Navigator.pop(context);
              },
            ),
          TextButton(
            onPressed: () async {
              final a = _build();
              if (a.email.isEmpty || a.host.isEmpty || a.password.isEmpty) {
                showMessage(context, 'Servono email, server e password');
                return;
              }
              final list = app.mail.accounts;
              final i = list.indexWhere((x) => x.id == a.id);
              if (i >= 0) {
                list[i] = a;
              } else {
                list.add(a);
              }
              await app.saveMail();
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('Salva'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: email,
            keyboardType: TextInputType.emailAddress,
            decoration: InputDecoration(
              labelText: 'Indirizzo email',
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                tooltip: 'Trova il server',
                icon: const Icon(Icons.travel_explore),
                onPressed: working ? null : discover,
              ),
            ),
            onEditingComplete: () {
              if (host.text.isEmpty) discover();
            },
          ),
          const SizedBox(height: 12),
          TextField(
            controller: pass,
            obscureText: !showPass,
            decoration: InputDecoration(
              labelText: 'Password (per Gmail: password per le app)',
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                icon: Icon(showPass ? Icons.visibility_off : Icons.visibility),
                onPressed: () => setState(() => showPass = !showPass),
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: name,
            decoration: const InputDecoration(labelText: 'Nome (facoltativo)', border: OutlineInputBorder()),
          ),
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: const Text('Server IMAP'),
            subtitle: Text(host.text.isEmpty ? 'Da trovare' : '${host.text}:${port.text}'),
            initiallyExpanded: widget.account != null,
            children: [
              TextField(
                controller: host,
                decoration: const InputDecoration(labelText: 'Server (es. imap.gmail.com)', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: port,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Porta', border: OutlineInputBorder()),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Connessione sicura (SSL/TLS)'),
                value: ssl,
                onChanged: (v) => setState(() => ssl = v),
              ),
              TextField(
                controller: user,
                decoration: const InputDecoration(
                  labelText: 'Nome utente (vuoto = indirizzo email)',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: working ? null : test,
            icon: working
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.wifi_tethering),
            label: const Text('Prova l\'accesso'),
          ),
          if (result != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(result!)),
          const SizedBox(height: 24),
          Text(
            'Gmail: attiva la verifica in due passaggi, poi crea una "password per le app" '
            'su myaccount.google.com/apppasswords e usala qui. '
            'Outlook/Hotmail personali non accettano più la password semplice via IMAP. '
            'La password resta solo su questo telefono, nello spazio privato dell\'app.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class MailRuleEditor extends StatefulWidget {
  const MailRuleEditor({super.key, required this.rule, this.isNew = false});

  final MailRule rule;
  final bool isNew;

  @override
  State<MailRuleEditor> createState() => _MailRuleEditorState();
}

class _MailRuleEditorState extends State<MailRuleEditor> {
  MailRule get r => widget.rule;
  late final name = TextEditingController(text: r.name);
  late final folder = TextEditingController(text: r.folder);
  late final from = TextEditingController(text: r.fromFilter);
  late final to = TextEditingController(text: r.toFilter);
  late final subject = TextEditingController(text: r.subjectFilter);
  late final body = TextEditingController(text: r.bodyFilter);
  late final att = TextEditingController(text: r.attachmentFilter);
  late final age = TextEditingController(text: '${r.maxAgeDays}');
  late final moveTo = TextEditingController(text: r.moveTo);

  @override
  void dispose() {
    for (final c in [name, folder, from, to, subject, body, att, age, moveTo]) {
      c.dispose();
    }
    super.dispose();
  }

  Widget _field(TextEditingController c, String label, {String? hint}) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextField(
          controller: c,
          decoration: InputDecoration(labelText: label, hintText: hint, border: const OutlineInputBorder()),
        ),
      );

  Widget _section(String t) => Padding(
        padding: const EdgeInsets.fromLTRB(0, 16, 0, 8),
        child: Text(t, style: Theme.of(context).textTheme.titleMedium),
      );

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final a = app.archive;
    final tags = r.tagIds.map(a.tag).whereType<Tag>().toList();
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isNew ? 'Nuova regola' : 'Modifica regola'),
        actions: [
          if (!widget.isNew)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: () async {
                if (!await confirm(context, title: 'Eliminare la regola?', ok: 'Elimina', danger: true)) return;
                app.mail.rules.removeWhere((x) => x.id == r.id);
                app.mail.processed.remove(r.id);
                await app.saveMail();
                if (context.mounted) Navigator.pop(context);
              },
            ),
          TextButton(
            onPressed: () async {
              if (name.text.trim().isEmpty) {
                showMessage(context, 'Dai un nome alla regola');
                return;
              }
              r
                ..name = name.text.trim()
                ..folder = folder.text.trim().isEmpty ? 'INBOX' : folder.text.trim()
                ..fromFilter = from.text.trim()
                ..toFilter = to.text.trim()
                ..subjectFilter = subject.text.trim()
                ..bodyFilter = body.text.trim()
                ..attachmentFilter = att.text.trim()
                ..maxAgeDays = int.tryParse(age.text.trim()) ?? 30
                ..moveTo = moveTo.text.trim();
              final list = app.mail.rules;
              final i = list.indexWhere((x) => x.id == r.id);
              if (i >= 0) {
                list[i] = r;
              } else {
                list.add(r);
              }
              await app.saveMail();
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('Salva'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 48),
        children: [
          _field(name, 'Nome della regola'),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Attiva'),
            value: r.enabled,
            onChanged: (v) => setState(() => r.enabled = v),
          ),
          DropdownButtonFormField<String>(
            initialValue: app.mail.account(r.accountId) == null ? null : r.accountId,
            decoration: const InputDecoration(labelText: 'Account', border: OutlineInputBorder()),
            items: [
              for (final acc in app.mail.accounts)
                DropdownMenuItem(value: acc.id, child: Text(acc.name)),
            ],
            onChanged: (v) => setState(() => r.accountId = v ?? r.accountId),
          ),
          const SizedBox(height: 12),
          _field(folder, 'Cartella', hint: 'INBOX'),
          _section('Filtri (vuoti = qualsiasi)'),
          _field(from, 'Il mittente contiene', hint: 'es. enel.it'),
          _field(to, 'Il destinatario contiene'),
          _field(subject, 'L\'oggetto contiene', hint: 'es. fattura'),
          _field(body, 'Il testo contiene'),
          _field(att, 'Nome dell\'allegato', hint: 'es. *.pdf  oppure  fattura*'),
          TextField(
            controller: age,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Solo messaggi degli ultimi N giorni', border: OutlineInputBorder()),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Solo messaggi non letti'),
            value: r.onlyUnread,
            onChanged: (v) => setState(() => r.onlyUnread = v),
          ),
          _section('Cosa importare'),
          for (final c in MailConsume.values)
            RadioListTile<MailConsume>(
              contentPadding: EdgeInsets.zero,
              title: Text(c.label),
              value: c,
              groupValue: r.consume,
              onChanged: (v) => setState(() => r.consume = v ?? r.consume),
            ),
          _section('Dopo l\'importazione'),
          for (final x in MailAfter.values)
            RadioListTile<MailAfter>(
              contentPadding: EdgeInsets.zero,
              title: Text(x.label),
              value: x,
              groupValue: r.after,
              onChanged: (v) => setState(() => r.after = v ?? r.after),
            ),
          if (r.after == MailAfter.move) _field(moveTo, 'Cartella di destinazione', hint: 'es. Archiviate'),
          _section('Assegna al documento'),
          DropdownButtonFormField<MailTitle>(
            initialValue: r.title,
            decoration: const InputDecoration(labelText: 'Titolo', border: OutlineInputBorder()),
            items: [for (final t in MailTitle.values) DropdownMenuItem(value: t, child: Text(t.label))],
            onChanged: (v) => setState(() => r.title = v ?? r.title),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<MailCorrespondent>(
            initialValue: r.correspondent,
            decoration: const InputDecoration(labelText: 'Corrispondente', border: OutlineInputBorder()),
            items: [
              for (final t in MailCorrespondent.values) DropdownMenuItem(value: t, child: Text(t.label)),
            ],
            onChanged: (v) => setState(() => r.correspondent = v ?? r.correspondent),
          ),
          if (r.correspondent == MailCorrespondent.fixed)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Corrispondente scelto'),
              subtitle: Text(a.correspondent(r.correspondentId)?.name ?? 'Tocca per scegliere'),
              onTap: () async {
                final c = await pickCorrespondent(context, r.correspondentId);
                if (c != null) setState(() => r.correspondentId = c.id);
              },
            ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Tipo di documento'),
            subtitle: Text(a.type(r.typeId)?.name ?? 'Nessuno (decidono le regole)'),
            onTap: () async {
              final t = await pickType(context, r.typeId);
              if (t != null) setState(() => r.typeId = t.id);
            },
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Tag'),
            subtitle: tags.isEmpty
                ? const Text('Nessuno')
                : Wrap(spacing: 4, runSpacing: 4, children: [for (final t in tags) TagChip(t, small: true)]),
            onTap: () async {
              final t = await pickTags(context, r.tagIds);
              if (t != null) setState(() => r.tagIds = t);
            },
          ),
          const SizedBox(height: 8),
          Text(
            'Dopo l\'importazione valgono anche le regole automatiche e i flussi di lavoro '
            '(provenienza "Email"). Ogni messaggio viene elaborato una volta sola.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

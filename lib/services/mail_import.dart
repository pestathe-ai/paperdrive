import 'package:enough_mail/enough_mail.dart'
    show ContentDisposition, Discover, ImapClient, MessageSequence, MimeMessage;

import '../core/mail_rules.dart';
import '../core/models.dart' show DocSource;
import 'ingest.dart';

/// Un file da importare, con il messaggio e la regola da cui proviene.
class MailItem {
  MailItem(this.rule, this.info, this.input, {required this.attachmentName});
  final MailRule rule;
  final MailInfo info;
  final StagedInput input;

  /// Nome dell'allegato, o null per il testo dell'email.
  final String? attachmentName;
}

/// Impostazioni IMAP trovate in automatico da un indirizzo email.
class DiscoveredServer {
  DiscoveredServer(this.host, this.port, this.ssl);
  final String host;
  final int port;
  final bool ssl;
}

Future<DiscoveredServer?> discoverImap(String email) async {
  try {
    final config = await Discover.discover(email);
    final s = config?.preferredIncomingImapServer;
    if (s == null) return null;
    return DiscoveredServer(s.hostname, s.port, s.isSecureSocket);
  } catch (_) {
    return null;
  }
}

/// Legge le caselle email con IMAP e passa gli allegati all'archivio.
class MailImporter {
  MailImporter(this.ingestor);

  final Ingestor ingestor;

  static String _stripHtml(String html) => html
      .replaceAll(RegExp(r'<(script|style)[^>]*>.*?</\1>', caseSensitive: false, dotAll: true), ' ')
      .replaceAll(RegExp(r'<br\s*/?>|</p>|</div>|</tr>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'<[^>]+>'), ' ')
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll(RegExp(r'[ \t]+'), ' ')
      .replaceAll(RegExp(r'\n\s*\n\s*\n+'), '\n\n')
      .trim();

  static MailInfo infoOf(MimeMessage m) {
    final from = m.from?.isNotEmpty == true ? m.from!.first : null;
    final body = m.decodeTextPlainPart() ?? _stripHtml(m.decodeTextHtmlPart() ?? '');
    return MailInfo(
      from: from?.email ?? '',
      fromName: from?.personalName ?? '',
      to: (m.to ?? const []).map((a) => a.email).join(', '),
      subject: m.decodeSubject() ?? '(senza oggetto)',
      body: body,
      date: m.decodeDate(),
    );
  }

  /// Prova la connessione e restituisce le cartelle disponibili.
  static Future<List<String>> testAccount(MailAccount a) async {
    final client = ImapClient(isLogEnabled: false);
    try {
      await client.connectToServer(a.host, a.port, isSecure: a.ssl);
      await client.login(a.username, a.password);
      final boxes = await client.listMailboxes(recursive: true);
      return boxes.map((b) => b.path).toList()..sort();
    } finally {
      try {
        await client.logout();
      } catch (_) {}
      try {
        await client.disconnect();
      } catch (_) {}
    }
  }

  /// Esegue tutte le regole attive. [handle] riceve ogni file da importare
  /// e restituisce vero se è stato importato (o saltato come duplicato).
  Future<List<String>> run(
    MailConfig cfg,
    Future<bool> Function(MailItem) handle, {
    void Function(String)? status,
  }) async {
    final log = <String>[];
    for (final account in cfg.accounts) {
      final rules = cfg.rules.where((r) => r.enabled && r.accountId == account.id).toList();
      if (rules.isEmpty) continue;
      final client = ImapClient(isLogEnabled: false);
      try {
        status?.call('Posta: connessione a ${account.name}…');
        await client.connectToServer(account.host, account.port, isSecure: account.ssl);
        await client.login(account.username, account.password);
        for (final rule in rules) {
          try {
            final n = await _runRule(client, cfg, rule, handle, status);
            log.add('${rule.name}: $n file importati');
          } catch (e) {
            log.add('${rule.name}: errore ($e)');
          }
        }
      } catch (e) {
        log.add('${account.name}: accesso non riuscito ($e)');
      } finally {
        try {
          await client.logout();
        } catch (_) {}
        try {
          await client.disconnect();
        } catch (_) {}
      }
    }
    return log;
  }

  Future<int> _runRule(
    ImapClient client,
    MailConfig cfg,
    MailRule rule,
    Future<bool> Function(MailItem) handle,
    void Function(String)? status,
  ) async {
    final box = await client.selectMailboxByPath(rule.folder.isEmpty ? 'INBOX' : rule.folder);
    final validity = box.uidValidity ?? 0;
    final done = cfg.processed.putIfAbsent(rule.id, () => <String>{});
    final search = await client.uidSearchMessages(
      searchCriteria: imapCriteria(rule, DateTime.now()),
    );
    final uids = search.matchingSequence?.toList() ?? const <int>[];
    final todo = uids.where((u) => !done.contains('$validity:$u')).toList();
    var imported = 0;
    var i = 0;
    for (final uid in todo) {
      i++;
      status?.call('Posta "${rule.name}": messaggio $i di ${todo.length}');
      final seq = MessageSequence.fromIds([uid], isUid: true);
      final fetched = await client.uidFetchMessages(seq, 'BODY.PEEK[]');
      if (fetched.messages.isEmpty) continue;
      final msg = fetched.messages.first;
      final info = infoOf(msg);
      var handledAll = true;
      var any = false;
      if (mailMatches(rule, info)) {
        final items = <MailItem>[];
        if (rule.consume != MailConsume.body) {
          final infos = [
            ...msg.findContentInfo(disposition: ContentDisposition.attachment),
            ...msg.findContentInfo(disposition: ContentDisposition.inline),
          ];
          final seen = <String>{};
          for (final ci in infos) {
            final name = ci.fileName;
            if (name == null || !seen.add(ci.fetchId) || !attachmentMatches(rule, name)) {
              continue;
            }
            final bytes = msg.getPart(ci.fetchId)?.decodeContentBinary();
            if (bytes == null || bytes.isEmpty) continue;
            final input = await ingestor.stageFile(name, bytes, source: DocSource.mail);
            items.add(MailItem(rule, info, input, attachmentName: name));
          }
        }
        if (rule.consume != MailConsume.attachments) {
          final input = await ingestor.textToPdf(
            name: '${info.subject}.pdf',
            title: info.subject,
            header: [
              ('Da', info.fromName.isEmpty ? info.from : '${info.fromName} <${info.from}>'),
              if (info.to.isNotEmpty) ('A', info.to),
              if (info.date != null) ('Data', info.date!.toLocal().toString().substring(0, 16)),
            ],
            body: info.body,
          );
          items.add(MailItem(rule, info, input, attachmentName: null));
        }
        for (final item in items) {
          any = true;
          final ok = await handle(item);
          if (ok) {
            imported++;
          } else {
            handledAll = false;
          }
        }
      }
      if (!handledAll) continue; // si riproverà la prossima volta
      done.add('$validity:$uid');
      if (any) {
        try {
          switch (rule.after) {
            case MailAfter.nothing:
              break;
            case MailAfter.markRead:
              await client.uidMarkSeen(seq);
            case MailAfter.flag:
              await client.uidMarkFlagged(seq);
            case MailAfter.move:
              if (rule.moveTo.trim().isNotEmpty) {
                await client.uidMove(seq, targetMailboxPath: rule.moveTo.trim());
              }
          }
        } catch (_) {
          // L'importazione è riuscita: l'azione sul messaggio è secondaria.
        }
      }
    }
    return imported;
  }
}


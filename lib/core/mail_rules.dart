/// Account e regole di posta (come le "Regole email" di Paperless-ngx).
/// Restano solo su questo telefono: contengono la password.
library;

import 'models.dart';
import 'text_utils.dart';
import 'workflows.dart' show globToRegExp;

class MailAccount {
  MailAccount({
    String? id,
    required this.name,
    required this.email,
    required this.host,
    this.port = 993,
    this.ssl = true,
    required this.username,
    required this.password,
  }) : id = id ?? newId();

  final String id;
  String name;
  String email;
  String host;
  int port;
  bool ssl;
  String username;
  String password;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'email': email,
        'host': host,
        'port': port,
        'ssl': ssl,
        'user': username,
        'pass': password,
      };

  factory MailAccount.fromJson(Map<String, dynamic> j) => MailAccount(
        id: j['id'] as String?,
        name: j['name'] as String? ?? '',
        email: j['email'] as String? ?? '',
        host: j['host'] as String? ?? '',
        port: (j['port'] as num?)?.toInt() ?? 993,
        ssl: j['ssl'] as bool? ?? true,
        username: j['user'] as String? ?? '',
        password: j['pass'] as String? ?? '',
      );
}

/// Cosa fare con il messaggio dopo averlo importato.
enum MailAfter { nothing, markRead, move, flag }

extension MailAfterLabel on MailAfter {
  String get label => switch (this) {
        MailAfter.nothing => 'Niente',
        MailAfter.markRead => 'Segna come letto',
        MailAfter.move => 'Sposta in un\'altra cartella',
        MailAfter.flag => 'Contrassegna con stella',
      };
}

/// Cosa importare da ogni messaggio.
enum MailConsume { attachments, body, both }

extension MailConsumeLabel on MailConsume {
  String get label => switch (this) {
        MailConsume.attachments => 'Solo gli allegati (PDF e immagini)',
        MailConsume.body => 'Solo il testo dell\'email (come PDF)',
        MailConsume.both => 'Allegati e testo dell\'email',
      };
}

enum MailTitle { subject, filename }

extension MailTitleLabel on MailTitle {
  String get label => switch (this) {
        MailTitle.subject => 'Oggetto dell\'email',
        MailTitle.filename => 'Nome dell\'allegato',
      };
}

enum MailCorrespondent { none, sender, fixed }

extension MailCorrespondentLabel on MailCorrespondent {
  String get label => switch (this) {
        MailCorrespondent.none => 'Nessuno (decidono le regole)',
        MailCorrespondent.sender => 'Mittente dell\'email',
        MailCorrespondent.fixed => 'Uno scelto da me',
      };
}

class MailRule {
  MailRule({
    String? id,
    required this.name,
    required this.accountId,
    this.enabled = true,
    this.folder = 'INBOX',
    this.fromFilter = '',
    this.toFilter = '',
    this.subjectFilter = '',
    this.bodyFilter = '',
    this.attachmentFilter = '',
    this.maxAgeDays = 30,
    this.onlyUnread = false,
    this.consume = MailConsume.attachments,
    this.after = MailAfter.markRead,
    this.moveTo = '',
    this.title = MailTitle.subject,
    this.correspondent = MailCorrespondent.sender,
    this.correspondentId,
    this.typeId,
    Set<String>? tagIds,
  })  : id = id ?? newId(),
        tagIds = tagIds ?? <String>{};

  final String id;
  String name;
  String accountId;
  bool enabled;
  String folder;

  // Filtri (vuoti = qualsiasi). Testo contenuto, senza maiuscole/accenti.
  String fromFilter;
  String toFilter;
  String subjectFilter;
  String bodyFilter;

  /// Nome dell'allegato con * e ? (es. `*.pdf`, `fattura*`).
  String attachmentFilter;
  int maxAgeDays;
  bool onlyUnread;

  MailConsume consume;
  MailAfter after;
  String moveTo;

  MailTitle title;
  MailCorrespondent correspondent;
  String? correspondentId;
  String? typeId;
  Set<String> tagIds;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'account': accountId,
        'on': enabled,
        'folder': folder,
        'from': fromFilter,
        'to': toFilter,
        'subject': subjectFilter,
        'body': bodyFilter,
        'att': attachmentFilter,
        'age': maxAgeDays,
        'unread': onlyUnread,
        'consume': consume.name,
        'after': after.name,
        'moveTo': moveTo,
        'title': title.name,
        'corrMode': correspondent.name,
        if (correspondentId != null) 'corr': correspondentId,
        if (typeId != null) 'type': typeId,
        'tags': tagIds.toList(),
      };

  static T _enum<T extends Enum>(List<T> values, Object? name, T fallback) =>
      values.firstWhere((v) => v.name == name, orElse: () => fallback);

  factory MailRule.fromJson(Map<String, dynamic> j) => MailRule(
        id: j['id'] as String?,
        name: j['name'] as String? ?? '',
        accountId: j['account'] as String? ?? '',
        enabled: j['on'] as bool? ?? true,
        folder: j['folder'] as String? ?? 'INBOX',
        fromFilter: j['from'] as String? ?? '',
        toFilter: j['to'] as String? ?? '',
        subjectFilter: j['subject'] as String? ?? '',
        bodyFilter: j['body'] as String? ?? '',
        attachmentFilter: j['att'] as String? ?? '',
        maxAgeDays: (j['age'] as num?)?.toInt() ?? 30,
        onlyUnread: j['unread'] as bool? ?? false,
        consume: _enum(MailConsume.values, j['consume'], MailConsume.attachments),
        after: _enum(MailAfter.values, j['after'], MailAfter.markRead),
        moveTo: j['moveTo'] as String? ?? '',
        title: _enum(MailTitle.values, j['title'], MailTitle.subject),
        correspondent:
            _enum(MailCorrespondent.values, j['corrMode'], MailCorrespondent.sender),
        correspondentId: j['corr'] as String?,
        typeId: j['type'] as String?,
        tagIds: ((j['tags'] as List?) ?? const []).map((e) => '$e').toSet(),
      );
}

/// Dati essenziali di un messaggio, per i filtri.
class MailInfo {
  MailInfo({
    required this.from,
    this.fromName = '',
    this.to = '',
    required this.subject,
    this.body = '',
    this.date,
  });

  final String from;
  final String fromName;
  final String to;
  final String subject;
  final String body;
  final DateTime? date;
}

bool _contains(String haystack, String needle) =>
    needle.trim().isEmpty || normalize(haystack).contains(normalize(needle.trim()));

/// Vero se il messaggio supera i filtri della regola (allegati esclusi).
bool mailMatches(MailRule r, MailInfo m) =>
    _contains('${m.fromName} <${m.from}>', r.fromFilter) &&
    _contains(m.to, r.toFilter) &&
    _contains(m.subject, r.subjectFilter) &&
    _contains(m.body, r.bodyFilter);

const Set<String> importableExtensions = {'.pdf', '.jpg', '.jpeg', '.png', '.webp'};

/// Vero se l'allegato va importato secondo la regola.
bool attachmentMatches(MailRule r, String fileName) {
  final lower = fileName.toLowerCase();
  final dot = lower.lastIndexOf('.');
  if (dot < 0 || !importableExtensions.contains(lower.substring(dot))) {
    return false;
  }
  final f = r.attachmentFilter.trim();
  return f.isEmpty || globToRegExp(f).hasMatch(fileName);
}

/// Criterio di ricerca IMAP per la regola (es. `SINCE 18-Sep-2026 UNSEEN`).
String imapCriteria(MailRule r, DateTime now) {
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  final since = now.subtract(Duration(days: r.maxAgeDays < 1 ? 1 : r.maxAgeDays));
  final parts = ['SINCE ${since.day}-${months[since.month - 1]}-${since.year}'];
  if (r.onlyUnread) parts.add('UNSEEN');
  return parts.join(' ');
}

/// Nome da usare come corrispondente per un mittente.
String senderName(MailInfo m) {
  final n = m.fromName.trim().replaceAll('"', '');
  if (n.isNotEmpty) return n;
  final at = m.from.indexOf('@');
  if (at > 0) {
    final domain = m.from.substring(at + 1).split('.');
    if (domain.length >= 2) {
      final d = domain[domain.length - 2];
      return d.isEmpty ? m.from : '${d[0].toUpperCase()}${d.substring(1)}';
    }
  }
  return m.from;
}

/// Impostazioni di posta salvate sul telefono.
class MailConfig {
  final List<MailAccount> accounts = [];
  final List<MailRule> rules = [];

  /// Messaggi già elaborati: id regola -> chiavi `uidvalidity:uid`.
  final Map<String, Set<String>> processed = {};
  bool checkOnOpen = true;
  int? lastCheck;
  String? lastResult;

  MailAccount? account(String id) {
    for (final a in accounts) {
      if (a.id == id) return a;
    }
    return null;
  }

  Map<String, dynamic> toJson() => {
        'accounts': accounts.map((a) => a.toJson()).toList(),
        'rules': rules.map((r) => r.toJson()).toList(),
        'processed': processed.map((k, v) => MapEntry(k, v.toList())),
        'onOpen': checkOnOpen,
        'last': lastCheck,
        'result': lastResult,
      };

  static MailConfig fromJson(Map<String, dynamic> j) {
    final c = MailConfig();
    for (final a in (j['accounts'] as List?) ?? const []) {
      c.accounts.add(MailAccount.fromJson((a as Map).cast<String, dynamic>()));
    }
    for (final r in (j['rules'] as List?) ?? const []) {
      c.rules.add(MailRule.fromJson((r as Map).cast<String, dynamic>()));
    }
    ((j['processed'] as Map?) ?? const {}).forEach((k, v) {
      c.processed['$k'] = ((v as List?) ?? const []).map((e) => '$e').toSet();
    });
    c.checkOnOpen = j['onOpen'] as bool? ?? true;
    c.lastCheck = (j['last'] as num?)?.toInt();
    c.lastResult = j['result'] as String?;
    return c;
  }
}

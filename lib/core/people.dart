/// Persone della famiglia e documenti sanitari: a chi è intestato un
/// documento, la specialità medica e se è un referto o una prescrizione.
/// Servono a dividere l'archivio per persona (es.
/// `Sanità/Maria/Cardiologia/Referti/2026/03 Marzo/…`).
library;

import 'archive.dart';
import 'models.dart';
import 'text_utils.dart';

/// Una persona della famiglia.
class Person {
  Person({required this.name, this.aliases = const []});

  /// Come compare nelle cartelle (es. "Maria" o "Maria Rossi").
  String name;

  /// Altri modi in cui compare nei documenti: nome e cognome completo,
  /// codice fiscale, soprannomi.
  List<String> aliases;

  Map<String, dynamic> toJson() => {'name': name, if (aliases.isNotEmpty) 'aka': aliases};

  factory Person.fromJson(Map<String, dynamic> j) => Person(
        name: j['name'] as String? ?? '',
        aliases: ((j['aka'] as List?) ?? const []).map((e) => '$e').toList(),
      );
}

/// Campi personalizzati (con id fissi, uguali su tutti i telefoni).
const String personFieldId = 'cf-persona';
const String specialtyFieldId = 'cf-specialita';
const String healthKindFieldId = 'cf-tiposan';

/// Tipo e percorso predefiniti della sanità.
const String healthTypeId = 'st-sanita';
const String healthPathId = 'st-path-sanita';
const String healthPathTemplate =
    'Sanità/{persona}/{specialita}/{tipo_sanitario}/{created_year}/{mese}/{title} {data}';

/// Categorie che riguardano tutta la casa: niente cartella per persona.
const Set<String> defaultSharedTypeIds = {'st-bolletta', 'st-casa'};

/// Crea i campi Persona, Specialità e Tipo sanitario e il percorso della
/// sanità, se mancano. Restituisce quanti ne ha aggiunti.
int ensurePeopleEntities(Archive a) {
  var n = 0;
  for (final (id, name) in const [
    (personFieldId, 'Persona'),
    (specialtyFieldId, 'Specialità'),
    (healthKindFieldId, 'Tipo sanitario'),
  ]) {
    if (a.fields.containsKey(id)) continue;
    a.fields[id] = CustomField(id: id, name: name, modified: 1);
    n++;
  }
  // Data alla fine del nome del file invece che all'inizio (versioni < 0.13).
  for (final p in a.storagePaths.values) {
    if (p.template.endsWith('/{created} {title}')) {
      p.template = '${p.template.substring(0, p.template.length - '{created} {title}'.length)}{title} {data}';
      n++;
    }
  }
  if (!a.storagePaths.containsKey(healthPathId)) {
    a.storagePaths[healthPathId] = StoragePath(
      id: healthPathId,
      name: 'Sanità per persona',
      template: healthPathTemplate,
      modified: 1,
    );
    n++;
  }
  return n;
}

String _flat(String s) => normalize(s).replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();

final RegExp _cfRe = RegExp(r'^[A-Z]{6}\d{2}[A-Z]\d{2}[A-Z]\d{3}[A-Z]$');

/// Punteggio con cui [p] compare nel testo (0 = non compare).
int _personScore(Person p, String flatText, String compactUpper, String headFlat) {
  var best = 0;
  for (final raw in [p.name, ...p.aliases]) {
    final alias = raw.trim();
    if (alias.isEmpty) continue;
    final cf = alias.toUpperCase().replaceAll(' ', '');
    if (_cfRe.hasMatch(cf)) {
      if (compactUpper.contains(cf)) best = best < 100 ? 100 : best;
      continue;
    }
    final words = _flat(alias).split(' ').where((w) => w.length >= 2).toList();
    if (words.isEmpty) continue;
    if (words.length == 1) {
      // Un nome solo è debole: vale solo come parola intera.
      if (' $flatText '.contains(' ${words.first} ')) best = best < 10 ? 10 : best;
      continue;
    }
    // Nome e cognome, anche invertiti ("ROSSI MARIO").
    final fwd = words.join(' ');
    final rev = words.reversed.join(' ');
    if (' $flatText '.contains(' $fwd ') || ' $flatText '.contains(' $rev ')) {
      var s = 50;
      if (' $headFlat '.contains(' $fwd ') || ' $headFlat '.contains(' $rev ')) s += 10;
      if (s > best) best = s;
    }
  }
  return best;
}

/// La persona a cui è intestato il documento, tra quelle della famiglia.
/// Null se nessuna compare (o se è ambiguo).
Person? detectPerson(List<Person> people, String text) {
  if (people.isEmpty || text.isEmpty) return null;
  final flatText = _flat(text);
  final compact = text.toUpperCase().replaceAll(RegExp(r'\s+'), '');
  // Le righe vicine a "paziente", "assistito", "intestatario" contano di più.
  final lines = text.split('\n');
  final head = StringBuffer();
  for (var i = 0; i < lines.length; i++) {
    if (RegExp(r'paziente|assistit|intestat|sig\.?r?a?\b|nome e cognome|cognome e nome|beneficiario|dipendente|alunn|studente',
            caseSensitive: false)
        .hasMatch(lines[i])) {
      head.writeln(lines[i]);
      if (i + 1 < lines.length) head.writeln(lines[i + 1]);
    }
  }
  final headFlat = _flat(head.toString());
  Person? best;
  var bestScore = 0, second = 0;
  for (final p in people) {
    final s = _personScore(p, flatText, compact, headFlat);
    if (s > bestScore) {
      second = bestScore;
      bestScore = s;
      best = p;
    } else if (s > second) {
      second = s;
    }
  }
  if (bestScore == 0 || bestScore == second) return null;
  return best;
}

/// Specialità mediche: nome della cartella e parole che la indicano.
const List<(String, List<String>)> specialties = [
  ('Analisi di laboratorio', ['emocromo', 'analisi del sangue', 'esami ematochimici', 'laboratorio analisi', 'esame urine', 'colesterolo', 'glicemia', 'emoglobina', 'trigliceridi', 'creatinina', 'valori di riferimento', 'medicina di laboratorio', 'patologia clinica']),
  ('Cardiologia', ['cardiolog', 'elettrocardiogramma', 'ecocardiogramma', 'ecg', 'holter', 'pressione arteriosa', 'aritmia', 'test da sforzo']),
  ('Radiologia', ['radiolog', 'radiografia', 'rx ', 'tac', 'tomografia', 'risonanza magnetica', 'rmn', 'ecografia', 'mammografia', 'diagnostica per immagini', 'moc ']),
  ('Oculistica', ['oculist', 'oftalmolog', 'visus', 'acuità visiva', 'fondo oculare', 'lenti', 'tonometria']),
  ('Dermatologia', ['dermatolog', 'nevi', 'mappatura nei', 'dermatoscopia', 'cute']),
  ('Ortopedia', ['ortoped', 'frattura', 'menisco', 'legamento', 'colonna vertebrale', 'lombalgia', 'protesi d']),
  ('Ginecologia', ['ginecolog', 'ostetric', 'pap test', 'gravidanza', 'ecografia pelvica', 'mammella']),
  ('Pediatria', ['pediatr', 'bilancio di salute', 'vaccinazion']),
  ('Dentista', ['odontoiat', 'dentist', 'igiene dentale', 'carie', 'ortodonz', 'impianto dentale', 'devitalizzazione']),
  ('Neurologia', ['neurolog', 'elettroencefalogramma', 'eeg', 'cefalea', 'emicrania']),
  ('Gastroenterologia', ['gastroenterolog', 'gastroscopia', 'colonscopia', 'endoscopia digestiva']),
  ('Urologia', ['urolog', 'prostat', 'psa ']),
  ('Otorinolaringoiatria', ['otorino', 'audiometri', 'orecchio', 'tonsill']),
  ('Endocrinologia', ['endocrinolog', 'tiroide', 'tsh', 'diabetolog']),
  ('Pneumologia', ['pneumolog', 'spirometri', 'polmon']),
  ('Allergologia', ['allergolog', 'prick test', 'allergi']),
  ('Fisioterapia', ['fisioterap', 'riabilitazion', 'fisiatr', 'tecar', 'osteopat']),
  ('Psicologia', ['psicolog', 'psichiatr', 'psicoterap']),
  ('Medicina generale', ['medico di medicina generale', 'medico di base', 'medico curante', 'mmg']),
];

/// La specialità medica del documento, o null.
String? detectSpecialty(String text) {
  final t = ' ${normalize(text)} ';
  final head = ' ${normalize(text.split('\n').take(15).join(' '))} ';
  String? best;
  var bestScore = 0;
  for (final (name, words) in specialties) {
    var s = 0;
    for (final w in words) {
      // Inizio di parola ("cardiolog" → cardiologia); le parole corte
      // (tac, ecg, tsh…) devono essere intere.
      final nw = normalize(w).trim();
      final re = RegExp('(?<![a-z0-9])${RegExp.escape(nw)}${nw.length <= 4 ? '(?![a-z0-9])' : ''}');
      if (re.hasMatch(t)) s += re.hasMatch(head) ? 3 : 1;
    }
    if (s > bestScore) {
      bestScore = s;
      best = name;
    }
  }
  return best;
}

/// Che documento sanitario è: "Referti", "Prescrizioni" o "Altro".
String healthKind(String text) {
  final t = normalize(text);
  final head = normalize(text.split('\n').take(15).join(' '));
  int score(List<String> words) {
    var s = 0;
    for (final w in words) {
      if (head.contains(w)) s += 3;
      if (t.contains(w)) s += 1;
    }
    return s;
  }

  final prescr = score(['ricetta', 'prescrizione', 'impegnativa', 'promemoria per l\'assistito', 'nre ', 'si prescrive', 'farmaci prescritti', 'codice esenzione']);
  final referto = score(['referto', 'esito', 'risultati', 'conclusioni', 'diagnosi', 'lettera di dimissione', 'relazione clinica', 'anamnesi', 'esame obiettivo', 'valori di riferimento']);
  if (prescr == 0 && referto == 0) return 'Altro';
  return prescr > referto ? 'Prescrizioni' : 'Referti';
}

/// Assegna persona e, per la sanità, specialità, tipo e percorso. Non
/// tocca i valori già impostati a mano. Restituisce true se cambia qualcosa.
bool applyPeople(Archive a, Document d, {String? aiPerson, String? aiSpecialty, String? aiHealthKind}) {
  ensurePeopleEntities(a);
  var changed = false;
  void setField(String id, String? v) {
    if (v == null || v.isEmpty) return;
    if ((d.customFields[id] ?? '').isNotEmpty) return;
    d.customFields[id] = v;
    changed = true;
  }

  final people = a.config.people;
  Person? fromAi;
  if (aiPerson != null) {
    final n = _flat(aiPerson);
    for (final p in people) {
      if ([p.name, ...p.aliases].any((x) => _flat(x) == n || (n.isNotEmpty && ' $n '.contains(' ${_flat(p.name)} ')))) {
        fromAi = p;
        break;
      }
    }
  }
  setField(personFieldId, (detectPerson(people, d.content) ?? fromAi)?.name);

  if (d.typeId != healthTypeId && d.storagePathId == healthPathId) {
    d.storagePathId = null;
    changed = true;
  }
  if (d.typeId == healthTypeId) {
    setField(specialtyFieldId, detectSpecialty(d.content) ?? _cleanAi(aiSpecialty));
    final kind = healthKind(d.content);
    setField(healthKindFieldId, kind == 'Altro' ? (_healthKindFromAi(aiHealthKind) ?? kind) : kind);
    if (d.storagePathId == null && a.storagePath(healthPathId) != null) {
      d.storagePathId = healthPathId;
      changed = true;
    }
  }
  return changed;
}

String? _cleanAi(String? s) {
  if (s == null) return null;
  final t = s.trim();
  if (t.isEmpty || t.length > 40) return null;
  return t[0].toUpperCase() + t.substring(1);
}

String? _healthKindFromAi(String? s) {
  if (s == null) return null;
  final n = normalize(s);
  if (n.contains('prescri') || n.contains('ricett') || n.contains('impegnativ')) return 'Prescrizioni';
  if (n.contains('referto') || n.contains('esito') || n.contains('esame')) return 'Referti';
  return null;
}

/// Il valore di {persona} nei percorsi: vuoto per le categorie comuni a
/// tutta la casa (bollette, casa…), così non si crea la cartella.
String personFolder(Archive a, Document d) {
  if (d.typeId != null && a.config.sharedTypeIds.contains(d.typeId)) return '';
  return d.customFields[personFieldId] ?? '';
}

const List<String> _monthNamesCap = [
  'Gennaio', 'Febbraio', 'Marzo', 'Aprile', 'Maggio', 'Giugno',
  'Luglio', 'Agosto', 'Settembre', 'Ottobre', 'Novembre', 'Dicembre',
];

/// "03 Marzo": cartella del mese, in ordine e leggibile.
String monthFolder(DateTime d) => '${d.month.toString().padLeft(2, '0')} ${_monthNamesCap[d.month - 1]}';

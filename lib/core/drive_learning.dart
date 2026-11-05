/// Correzioni fatte fuori dall'app (su Google Drive) o scrivendo a mano la
/// cartella di un documento: l'app le interpreta e impara.
///
/// - `Tasse/2026` → categoria Tasse.
/// - `Sanità/Luca/…` → persona Luca.
/// - `Casa/Box via Roma/2026` → categoria Casa e una sottocartella "Box via
///   Roma" che diventa un percorso: i documenti simili ci finiranno da soli.
library;

import 'dart:typed_data';

import 'ai.dart' show correctedExample, findByName;
import 'matching.dart' show Idf, cosine, termVector, weightedVector;
import 'meaning.dart' show blendSimilarity, meaningCosine, meaningScore;
import 'archive.dart';
import 'models.dart';
import 'organize.dart' show drivePath;
import 'people.dart';
import 'workflows.dart' show stripLeadingDate;
import 'text_utils.dart';

final RegExp _yearRe = RegExp(r'^(19|20)\d{2}$');
final RegExp _monthRe = RegExp(
  r'^(\d{1,2}\s*[-_.]?\s*)?(gennaio|febbraio|marzo|aprile|maggio|giugno|luglio|agosto|settembre|ottobre|novembre|dicembre)?$',
  caseSensitive: false,
);

bool _isMonth(String s) {
  var t = s.trim();
  if (t.isEmpty) return false;
  // "Marzo 2026", "03-2026", "2026 03": il mese con l'anno è una data.
  final withYear = RegExp(r'^(?:(19|20)\d{2}\s*[-_. ]\s*)?(.+?)(?:\s*[-_. ]\s*(19|20)\d{2})?$').firstMatch(t);
  if (withYear != null && (withYear[1] != null || withYear[3] != null)) t = withYear[2]!.trim();
  if (t.isEmpty) return false;
  final m = _monthRe.firstMatch(t);
  if (m == null) return false;
  // "03", "3", "03 Marzo", "Marzo": numero 1-12 o nome del mese.
  final num = int.tryParse((m[1] ?? '').replaceAll(RegExp(r'[^0-9]'), ''));
  return m[2] != null || (num != null && num >= 1 && num <= 12 && m[1]!.trim().length <= 2);
}

String _cap(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

/// Il titolo dal nome del file su Drive: senza ".pdf", " (PDF-A)" e la data
/// che l'app mette davanti.
String titleFromDriveName(String name) {
  var t = name.trim();
  t = t.replaceFirst(RegExp(r'\.pdf$', caseSensitive: false), '');
  t = t.replaceFirst(RegExp(r'\s*\(PDF-A\)$'), '');
  t = stripLeadingDate(t);
  t = t.replaceFirst(RegExp(r'\s+(\d{2}-\d{2}-\d{4}|\d{4}-\d{2}-\d{2})$'), '');
  return t.trim();
}

/// Applica una cartella scelta a mano ([folders], dalla cartella principale
/// in giù, senza il nome del file) e/o un nuovo nome del file. Il documento
/// conta come corretto a mano. Restituisce i campi cambiati.
List<String> applyFolderCorrection(Archive a, Document d, {List<String>? folders, String? fileName}) {
  ensurePeopleEntities(a);
  final changed = <String>[];

  if (fileName != null) {
    final t = titleFromDriveName(fileName);
    final (_, expected) = drivePath(a, d);
    if (t.isNotEmpty && t != d.title && titleFromDriveName(expected) != t) {
      d.title = t;
      d.titleEdited = true;
      changed.add('titolo');
    }
  }

  if (folders != null) {
    var segs = folders.map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
    // Rimesso in "Da importare": non è una categoria, si ignora lo spostamento.
    if (segs.isNotEmpty && const {'da importare', 'pdf-a'}.contains(normalize(segs.first))) segs = const [];
    if (segs.isNotEmpty && normalize(segs.first) != 'cestino') {
      // Il documento resta esattamente dove l'hai messo (anche se l'anno
      // della cartella non è quello del documento).
      final pin = [for (final s in segs) s];
      final same = d.pinnedFolder != null && d.pinnedFolder!.join('/') == pin.join('/');
      if (!same) {
        d.pinnedFolder = pin;
        changed.add('cartella');
      }
    }
    if (segs.isNotEmpty && normalize(segs.first) == 'cestino') {
      if (!d.inTrash) {
        d
          ..inTrash = true
          ..trashedAt = nowMs();
        changed.add('cestino');
      }
      return changed;
    }
    if (d.inTrash) {
      d
        ..inTrash = false
        ..trashedAt = null;
      changed.add('ripristinato');
    }
    if (segs.isNotEmpty) {
      // Persona: una cartella col nome di una persona della famiglia, in
      // qualsiasi punto (anche in cima: "Domenico/Sanità/…").
      Person? personOf(String s) {
        final n = normalize(s);
        for (final p in a.config.people) {
          if (normalize(p.name) == n || p.aliases.any((x) => normalize(x) == n)) return p;
        }
        return null;
      }

      bool dateSeg(String s) => _yearRe.hasMatch(s) || _isMonth(s);
      // Categoria: la prima cartella che è una categoria esistente; se non ce
      // n'è, la prima che non è persona né data (creata nuova).
      var catIdx = -1;
      NamedEntity? type;
      for (var i = 0; i < segs.length; i++) {
        if (personOf(segs[i]) != null || dateSeg(segs[i])) continue;
        final t = findByName(a.activeTypes, segs[i]);
        if (t != null) {
          catIdx = i;
          type = t;
          break;
        }
      }
      if (type == null) {
        for (var i = 0; i < segs.length; i++) {
          if (personOf(segs[i]) != null || dateSeg(segs[i])) continue;
          catIdx = i;
          type = NamedEntity(name: _cap(segs[i]), algorithm: MatchAlgorithm.auto);
          a.types[type.id] = type;
          break;
        }
      }
      if (type != null && d.typeId != type.id) {
        d.typeId = type.id;
        changed.add('categoria');
      }

      // Le altre cartelle: anni, mesi, persona, specialità, referti… o
      // sottocartelle personali. La categoria è scritta per esteso: la
      // sottocartella vale solo lì.
      final template = <String>[];
      final custom = <String>[];
      String? person;
      for (var i = 0; i < segs.length; i++) {
        final s = segs[i];
        final n = normalize(s);
        if (i == catIdx) {
          template.add(type!.name);
          continue;
        }
        if (_yearRe.hasMatch(s)) {
          template.add('{created_year}');
          continue;
        }
        if (_isMonth(s)) {
          template.add('{mese}');
          continue;
        }
        final p = personOf(s);
        if (p != null) {
          person = p.name;
          // In una categoria di tutta la casa la persona non compare nel
          // percorso: il nome resta scritto per esteso ("Casa/Via
          // alessandrina/…" deve restare così).
          if (a.config.sharedTypeIds.contains(d.typeId)) {
            template.add(s);
            custom.add(s);
          } else {
            template.add('{persona}');
          }
          continue;
        }
        if (d.typeId == healthTypeId) {
          if (n == 'referti' || n == 'prescrizioni' || n == 'altro') {
            if (d.customFields[healthKindFieldId] != _cap(n)) changed.add('tipo sanitario');
            d.customFields[healthKindFieldId] = _cap(n);
            template.add('{tipo_sanitario}');
            continue;
          }
          if (specialties.any((e) => normalize(e.$1) == n)) {
            final spec = specialties.firstWhere((e) => normalize(e.$1) == n).$1;
            if (d.customFields[specialtyFieldId] != spec) changed.add('specialità');
            d.customFields[specialtyFieldId] = spec;
            template.add('{specialita}');
            continue;
          }
        }
        template.add(s);
        custom.add(s);
      }
      if (person != null && d.customFields[personFieldId] != person) {
        d.customFields[personFieldId] = person;
        changed.add('persona');
      }

      // Persona prima della categoria ("Domenico/Sanità/…"): un ordine tuo,
      // da usare anche per i documenti nuovi.
      final pi = template.indexOf('{persona}');
      final personFirst = pi >= 0 && catIdx >= 0 && pi < catIdx;
      if (custom.isEmpty && !personFirst) {
        // Struttura standard: basta il modello generale (o quello della sanità).
        final want = d.typeId == healthTypeId ? healthPathId : null;
        if (d.storagePathId != want && (want == null || a.storagePath(want) != null)) {
          d.storagePathId = want;
          changed.add('cartella');
        }
      } else {
        // Sottocartella personale: diventa un percorso che l'app impara.
        final tpl = '${template.join('/')}/{title} {data}';
        var path = a.activeStoragePaths.where((p) => p.template == tpl).firstOrNull;
        if (path == null) {
          // Niente classificatore: ci vanno solo i documenti molto simili
          // (applyLearnedFolder) o quelli che sposti tu.
          path = StoragePath(name: custom.join(' / '), template: tpl, learned: true);
          a.storagePaths[path.id] = path;
        }
        if (d.storagePathId != path.id) {
          d.storagePathId = path.id;
          changed.add('cartella');
        }
      }
    }
  }
  if (changed.isNotEmpty) d.userEdited = true;
  return changed;
}

/// Percorsi imparati delle versioni precedenti con "{persona}" dopo la
/// categoria (es. "Casa/{persona}/…" quando "Via Alessandrina" è tra le
/// persone): nelle categorie di tutta la casa la persona non compare nel
/// percorso, quindi la cartella spariva e i file finivano in "Casa/…".
/// Ora il nome si scrive per esteso, preso dai documenti di quel percorso.
int fixPersonInPaths(Archive a) {
  var n = 0;
  for (final p in a.storagePaths.values) {
    if (p.deleted || p.id == healthPathId || !isLearnedPath(p)) continue;
    final segs = p.template.split('/');
    final i = segs.indexOf('{persona}');
    if (i <= 0) continue;
    final counts = <String, int>{};
    for (final d in a.activeDocuments) {
      final who = d.customFields[personFieldId] ?? '';
      if (d.storagePathId == p.id && who.isNotEmpty && a.config.sharedTypeIds.contains(d.typeId)) {
        counts[who] = (counts[who] ?? 0) + 1;
      }
    }
    if (counts.isEmpty) continue;
    final who = counts.entries.reduce((x, y) => x.value >= y.value ? x : y).key;
    segs[i] = who;
    p
      ..template = segs.join('/')
      ..name = p.name.isEmpty ? who : (p.name.contains(who) ? p.name : '$who / ${p.name}')
      ..modified = nowMs();
    n++;
  }
  return n;
}

/// Toglie le sottocartelle imparate rimaste senza documenti: succede
/// quando sposti su Drive un'intera cartella (es. "Lavori condominiali"
/// dentro "Via alessandrina"). Il vecchio percorso non deve più attirare i
/// documenti nuovi e ricreare la cartella vecchia. Restituisce quante.
int retireEmptyLearnedPaths(Archive a) {
  final used = <String>{
    for (final d in a.documents.values)
      if (!d.deleted) ...[?d.storagePathId, ?d.suggestedPathId, ...?d.suggestedPaths],
  };
  var n = 0;
  for (final p in a.storagePaths.values) {
    if (p.deleted || p.id == healthPathId || p.learned == false || !isLearnedPath(p)) continue;
    if (used.contains(p.id)) continue;
    p
      ..deleted = true
      ..modified = nowMs();
    n++;
  }
  return n;
}

/// La cartella attuale del documento, da mostrare e modificare
/// (es. "Casa/Box via Roma/2026").
String folderOf(Archive a, Document d) => drivePath(a, d).$1.join('/');

/// Se un documento simile corretto a mano sta in una sottocartella
/// personale, ci va anche questo (stessa categoria). Restituisce true se
/// cambia.
bool applyLearnedFolder(Archive a, Document d) => applySubfolder(a, d) == SubfolderDecision.assigned;

/// Esito della scelta della sottocartella.
enum SubfolderDecision { none, assigned, ask }

/// Le parole che distinguono i documenti di una sottocartella dagli altri
/// della stessa categoria (es. per il box: "box", "roma", "posto",
/// "condominio"), con il loro peso.
Map<String, double> folderProfile(Archive a, StoragePath p, String typeId) {
  final inside = <Set<String>>[];
  final outside = <Set<String>>[];
  for (final d in a.activeDocuments) {
    if (d.typeId != typeId || d.content.isEmpty) continue;
    final words = weightedVector(d.content, Idf.of(a)).keys.toSet();
    if (d.storagePathId == p.id) {
      inside.add(words);
    } else {
      outside.add(words);
    }
  }
  if (inside.isEmpty) return const {};
  final df = <String, int>{};
  for (final w in inside) {
    for (final x in w) {
      df[x] = (df[x] ?? 0) + 1;
    }
  }
  final out = <String, double>{};
  df.forEach((w, n) {
    final fin = n / inside.length;
    final fout = outside.isEmpty ? 0.0 : outside.where((o) => o.contains(w)).length / outside.length;
    final score = fin - fout;
    if (score >= 0.4 && w.length >= 3) out[w] = score;
  });
  final top = out.entries.toList()..sort((x, y) => y.value.compareTo(x.value));
  return Map.fromEntries(top.take(15));
}

/// Quanto il documento corrisponde al profilo della sottocartella (0..1).
double folderMatch(Map<String, double> profile, Document d) {
  if (profile.isEmpty) return 0;
  final words = termVector(d.content).keys.toSet();
  var got = 0.0, total = 0.0;
  profile.forEach((w, s) {
    total += s;
    if (words.contains(w)) got += s;
  });
  return total == 0 ? 0 : got / total;
}

/// Quanto ogni tua sottocartella (della stessa categoria) è adatta al
/// documento, dalla migliore. Conta:
/// - quanto somiglia ai documenti che ci hai messo tu (a parole e, se c'è la
///   rete neurale, per significato);
/// - le parole che distinguono quella sottocartella dalle altre;
/// - lo stesso mittente (es. l'amministratore di quel palazzo);
/// - l'indicazione dell'AI, che legge il documento con l'elenco delle tue
///   sottocartelle.
List<(StoragePath, double)> rankSubfolders(
  Archive a,
  Document d, {
  String? aiHint,
  Float32List? meaning,
  Float32List? Function(Document)? meaningOf,
}) {
  final type = d.typeId;
  if (type == null) return const [];
  final idf = Idf.of(a);
  final v = weightedVector(d.content, idf);
  final hint = aiHint == null ? '' : normalize(aiHint.replaceFirst(RegExp(r'^[^:/]*:\s*'), '')).trim();
  final out = <(StoragePath, double)>[];
  for (final p in a.activeStoragePaths) {
    if (p.id == healthPathId || !isLearnedPath(p) || !learnedPathFits(a, p, d)) continue;
    final examples = [
      for (final o in a.activeDocuments)
        if (o.id != d.id && o.storagePathId == p.id && o.typeId == type && !o.inTrash) o,
    ];
    if (examples.isEmpty && hint.isEmpty) continue;
    // Somiglianza con i documenti della cartella: media dei due più simili.
    final sims = <double>[];
    for (final o in examples) {
      final words = v.isEmpty ? 0.0 : cosine(v, weightedVector(o.content, idf));
      final om = meaningOf?.call(o);
      final m = meaning != null && om != null ? meaningScore(meaningCosine(meaning, om)) : null;
      sims.add(blendSimilarity(words, m));
    }
    sims.sort((x, y) => y.compareTo(x));
    final near = sims.isEmpty ? 0.0 : (sims.length == 1 ? sims.first * 0.9 : (sims[0] + sims[1]) / 2);
    final nearScore = ((near - 0.15) / 0.45).clamp(0.0, 1.0);
    final profile = folderMatch(folderProfile(a, p, type), d);
    var score = 0.55 * nearScore + 0.45 * profile;
    if (d.correspondentId != null && examples.any((o) => o.correspondentId == d.correspondentId)) score += 0.15;
    if (hint.length >= 3) {
      final name = normalize(p.name);
      final last = normalize(p.name.split('/').last.trim());
      if (name == hint || hint.endsWith(name) || (last.length >= 3 && hint.endsWith(last))) {
        score += 0.35;
      } else if (name.contains(hint) || hint.contains(name)) {
        score += 0.15;
      }
    }
    out.add((p, score));
  }
  out.sort((x, y) => y.$2.compareTo(x.$2));
  return out;
}

/// Sceglie la sottocartella imparata per un documento nuovo: se è sicura la
/// assegna; se è in bilico la propone ([Document.suggestedPathId]) perché
/// l'app ne chieda conferma (con [ask] falso decide da sola). Sicura vuol
/// dire: punteggio alto e nettamente migliore della seconda (due palazzi
/// diversi non si confondono).
SubfolderDecision applySubfolder(
  Archive a,
  Document d, {
  bool ask = true,
  String? aiHint,
  Float32List? meaning,
  Float32List? Function(Document)? meaningOf,
}) {
  if (d.storagePathId != null || d.typeId == null) return SubfolderDecision.none;
  // Quasi uguale a un documento che hai messo tu in una sottocartella.
  final (example, score) = correctedExample(a, d, min: 0.6);
  final exPath = a.storagePath(example?.storagePathId);
  if (example != null &&
      exPath != null &&
      exPath.id != healthPathId &&
      example.typeId == d.typeId &&
      learnedPathFits(a, exPath, d) &&
      (d.correspondentId == null ||
          example.correspondentId == null ||
          d.correspondentId == example.correspondentId ||
          score >= 0.8)) {
    d.storagePathId = exPath.id;
    return SubfolderDecision.assigned;
  }
  final ranked = rankSubfolders(a, d, aiHint: aiHint, meaning: meaning, meaningOf: meaningOf);
  if (ranked.isEmpty) return SubfolderDecision.none;
  final (best, bestScore) = ranked.first;
  final second = ranked.length > 1 ? ranked[1].$2 : 0.0;
  final clear = bestScore - second >= 0.15;
  // Con una sola cartella possibile serve più sicurezza; con più cartelle
  // basta che una sia nettamente migliore delle altre.
  final margin = bestScore - second;
  final need = ranked.length == 1 ? 0.6 : (margin >= 0.3 ? 0.45 : 0.55);
  if ((bestScore >= need && clear) || (!ask && bestScore >= 0.4 && clear)) {
    d.storagePathId = best.id;
    return SubfolderDecision.assigned;
  }
  if (ask && bestScore >= 0.25) {
    d
      ..suggestedPathId = best.id
      ..suggestedPaths = [for (final (p, s) in ranked.take(3)) if (s >= 0.2) p.id];
    return SubfolderDecision.ask;
  }
  return SubfolderDecision.none;
}

/// Una sottocartella creata spostando i file (percorso senza
/// classificatore, con cartelle scritte per esteso).
bool isLearnedPath(StoragePath p) =>
    p.learned ??
    (p.algorithm == MatchAlgorithm.none &&
        p.template.split('/').any((seg) => seg.isNotEmpty && !seg.contains('{')));

/// Una sottocartella imparata vale solo per la sua categoria: un documento
/// di un'altra categoria non ci finisce (es. un'iscrizione all'asilo nella
/// cartella del box).
bool learnedPathFits(Archive a, StoragePath p, Document d) {
  if (!isLearnedPath(p)) return true;
  final segs = p.template.split('/');
  if (segs.first == '{document_type}') return true; // percorsi vecchi: vedi migrateLearnedPaths
  final t = a.type(d.typeId);
  if (t == null) return false;
  // La categoria è una delle cartelle scritte per esteso (anche dopo la
  // persona: "{persona}/Sanità/…").
  return segs.any((seg) => !seg.contains('{') && normalize(seg) == normalize(t.name));
}

/// Percorsi imparati delle versioni precedenti ("{document_type}/…"): la
/// categoria diventa quella dei documenti che ci hai messo tu.
int migrateLearnedPaths(Archive a) {
  var n = 0;
  for (final p in a.storagePaths.values) {
    if (p.deleted || !isLearnedPath(p) || !p.template.startsWith('{document_type}/')) continue;
    final counts = <String, int>{};
    for (final d in a.activeDocuments) {
      if (d.storagePathId == p.id && d.userEdited && d.typeId != null) {
        counts[d.typeId!] = (counts[d.typeId!] ?? 0) + 1;
      }
    }
    if (counts.isEmpty) continue;
    final best = counts.entries.reduce((x, y) => x.value >= y.value ? x : y).key;
    final name = a.type(best)?.name;
    if (name == null) continue;
    p
      ..template = '$name${p.template.substring('{document_type}'.length)}'
      ..modified = nowMs();
    n++;
  }
  return n;
}

/// Toglie le sottocartelle imparate che non c'entrano con la categoria.
bool dropUnfitPath(Archive a, Document d) {
  final p = a.storagePath(d.storagePathId);
  if (p == null || learnedPathFits(a, p, d)) return false;
  d.storagePathId = null;
  return true;
}

/// Categorie create per sbaglio col nome di una persona (versioni < 0.17.2,
/// spostando file in cartelle "Domenico/…"): i loro documenti prendono la
/// persona e la categoria vera, la categoria sbagliata si toglie.
/// Restituisce i documenti da riclassificare.
List<Document> fixPersonTypes(Archive a) {
  final out = <Document>[];
  for (final t in a.activeTypes.toList()) {
    if (t.id.startsWith('st-')) continue;
    final n = normalize(t.name);
    final p = a.config.people
        .where((p) => normalize(p.name) == n || p.aliases.any((x) => normalize(x) == n))
        .firstOrNull;
    if (p == null) continue;
    for (final d in a.activeDocuments.where((d) => d.typeId == t.id)) {
      if ((d.customFields[personFieldId] ?? '').isEmpty) d.customFields[personFieldId] = p.name;
      d.typeId = null;
      final pin = d.pinnedFolder;
      if (pin != null && pin.isNotEmpty) applyFolderCorrection(a, d, folders: pin);
      d.touch();
      out.add(d);
    }
    t
      ..deleted = true
      ..modified = nowMs();
  }
  return out;
}

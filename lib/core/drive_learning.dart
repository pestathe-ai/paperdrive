/// Correzioni fatte fuori dall'app (su Google Drive) o scrivendo a mano la
/// cartella di un documento: l'app le interpreta e impara.
///
/// - `Tasse/2026` → categoria Tasse.
/// - `Sanità/Luca/…` → persona Luca.
/// - `Casa/Box via Roma/2026` → categoria Casa e una sottocartella "Box via
///   Roma" che diventa un percorso: i documenti simili ci finiranno da soli.
library;

import 'ai.dart' show correctedExample, findByName;
import 'matching.dart' show Idf, termVector, weightedVector;
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
  final t = s.trim();
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
      // Categoria: la prima cartella (creata se non esiste).
      var type = findByName(a.activeTypes, segs.first);
      if (type == null) {
        type = NamedEntity(name: _cap(segs.first), algorithm: MatchAlgorithm.auto);
        a.types[type.id] = type;
      }
      if (d.typeId != type.id) {
        d.typeId = type.id;
        changed.add('categoria');
      }

      // Le altre cartelle: anni, mesi, persona, specialità, referti… o
      // sottocartelle personali.
      // La categoria scritta per esteso: la sottocartella vale solo lì.
      final template = <String>[type.name];
      final custom = <String>[];
      String? person;
      for (final s in segs.skip(1)) {
        final n = normalize(s);
        if (_yearRe.hasMatch(s)) {
          template.add('{created_year}');
          continue;
        }
        if (_isMonth(s)) {
          template.add('{mese}');
          continue;
        }
        final p = a.config.people.where((p) => normalize(p.name) == n).firstOrNull;
        if (p != null) {
          person = p.name;
          template.add('{persona}');
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

      if (custom.isEmpty) {
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
          path = StoragePath(name: custom.join(' / '), template: tpl);
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

/// Sceglie la sottocartella imparata per un documento nuovo: se è sicura la
/// assegna; se è in bilico la propone ([Document.suggestedPathId]) perché
/// l'app ne chieda conferma (con [ask] falso decide da sola).
SubfolderDecision applySubfolder(Archive a, Document d, {bool ask = true, String? aiHint}) {
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
  // Le parole tipiche delle tue sottocartelle (e il suggerimento dell'AI).
  StoragePath? best;
  var bestScore = 0.0;
  for (final p in a.activeStoragePaths) {
    if (!isLearnedPath(p) || !learnedPathFits(a, p, d)) continue;
    var s = folderMatch(folderProfile(a, p, d.typeId!), d);
    if (aiHint != null && normalize(p.name).contains(normalize(aiHint))) s += 0.3;
    if (aiHint != null && normalize(aiHint).contains(normalize(p.name))) s += 0.3;
    if (s > bestScore) {
      bestScore = s;
      best = p;
    }
  }
  if (best == null) return SubfolderDecision.none;
  if (bestScore >= 0.6 || (!ask && bestScore >= 0.4)) {
    d.storagePathId = best.id;
    return SubfolderDecision.assigned;
  }
  if (ask && bestScore >= 0.3) {
    d.suggestedPathId = best.id;
    return SubfolderDecision.ask;
  }
  return SubfolderDecision.none;
}

/// Una sottocartella creata spostando i file (percorso senza
/// classificatore, con cartelle scritte per esteso).
bool isLearnedPath(StoragePath p) =>
    p.algorithm == MatchAlgorithm.none &&
    p.template.split('/').any((seg) => seg.isNotEmpty && !seg.contains('{'));

/// Una sottocartella imparata vale solo per la sua categoria: un documento
/// di un'altra categoria non ci finisce (es. un'iscrizione all'asilo nella
/// cartella del box).
bool learnedPathFits(Archive a, StoragePath p, Document d) {
  if (!isLearnedPath(p)) return true;
  final first = p.template.split('/').first;
  if (first.contains('{')) return true; // percorsi vecchi: vedi migrateLearnedPaths
  final t = a.type(d.typeId);
  return t != null && normalize(t.name) == normalize(first);
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

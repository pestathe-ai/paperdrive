import 'package:flutter_test/flutter_test.dart';
import 'package:paperdrive/core/archive.dart';
import 'package:paperdrive/core/drive_learning.dart';
import 'package:paperdrive/core/models.dart';
import 'package:paperdrive/core/organize.dart';
import 'package:paperdrive/core/people.dart';

void main() {
  Archive archive() {
    final a = Archive.starter();
    a.config.people.addAll([Person(name: 'Maria'), Person(name: 'Luca')]);
    ensurePeopleEntities(a);
    return a;
  }

  test('titolo dal nome del file', () {
    expect(titleFromDriveName('2026-03-05 Bolletta luce Enel.pdf'), 'Bolletta luce Enel');
    expect(titleFromDriveName('Spese box (PDF-A).pdf'), 'Spese box');
    expect(titleFromDriveName('Bolletta luce Enel 05-03-2026 (PDF-A).pdf'), 'Bolletta luce Enel');
  });

  test('sottocartella personale: diventa un percorso', () {
    final a = archive();
    final d = Document(title: 'Spese condominiali box', content: 'Condominio via Roma 12 box auto rata', created: DateTime(2026, 4, 2), typeId: 'st-banca');
    final ch = applyFolderCorrection(a, d, folders: ['Casa', 'Box via Roma', '2026']);
    expect(ch, containsAll(['categoria', 'cartella']));
    expect(d.typeId, 'st-casa');
    expect(d.userEdited, isTrue);
    final (folders, name) = drivePath(a, d);
    expect(folders, ['Casa', 'Box via Roma', '2026']);
    expect(name, 'Spese condominiali box 02-04-2026');
    // Un altro anno va nella cartella dell'anno giusto.
    d.created = DateTime(2027, 1, 10);
    expect(drivePath(a, d).$1, ['Casa', 'Box via Roma', '2027']);
  });

  test('i documenti simili finiscono nella stessa sottocartella', () {
    final a = archive();
    final first = Document(title: 'Rata box marzo', content: 'Condominio via Roma 12 box auto rata marzo 2026', typeId: 'st-casa');
    a.documents[first.id] = first;
    applyFolderCorrection(a, first, folders: ['Casa', 'Box via Roma', '2026']);
    final next = Document(title: 'Rata box aprile', content: 'Condominio via Roma 12 box auto rata aprile 2026', typeId: 'st-casa', created: DateTime(2026, 4, 1));
    expect(applyLearnedFolder(a, next), isTrue);
    expect(drivePath(a, next).$1, ['Casa', 'Box via Roma', '2026']);
  });

  test('persona, categoria nuova, cestino e rinomina', () {
    final a = archive();
    final d = Document(title: 'Cedolino', content: 'cedolino', created: DateTime(2026, 3, 1), typeId: 'st-paga');
    applyFolderCorrection(a, d, folders: ['Busta paga', 'Luca', '2026']);
    expect(d.customFields[personFieldId], 'Luca');
    expect(d.storagePathId, isNull);
    applyFolderCorrection(a, d, folders: ['Animali', '2026']);
    expect(a.type(d.typeId)?.name, 'Animali');
    applyFolderCorrection(a, d, fileName: '2026-03-01 Ricevuta veterinario Fido.pdf');
    expect(d.title, 'Ricevuta veterinario Fido');
    expect(d.titleEdited, isTrue);
    applyFolderCorrection(a, d, folders: ['Cestino', 'Animali', '2026']);
    expect(d.inTrash, isTrue);
  });

  test('sanità con la struttura standard', () {
    final a = archive();
    final d = Document(title: 'Referto', content: 'referto', created: DateTime(2026, 3, 12), typeId: healthTypeId);
    applyFolderCorrection(a, d, folders: ['Sanità', 'Maria', 'Cardiologia', 'Referti', '2026', '03 Marzo']);
    expect(d.storagePathId, healthPathId);
    expect(d.customFields[specialtyFieldId], 'Cardiologia');
    expect(drivePath(a, d).$1, ['Sanità', 'Maria', 'Cardiologia', 'Referti', '2026', '03 Marzo']);
  });

  test('data alla fine, mai due volte', () {
    final a = archive();
    final d = Document(title: 'Etichetta Vinted 11-10-2026', created: DateTime(2026, 10, 11), typeId: 'st-garanzia');
    expect(drivePath(a, d).$2, 'Etichetta Vinted 11-10-2026');
    d.title = 'Etichetta Vinted';
    expect(drivePath(a, d).$2, 'Etichetta Vinted 11-10-2026');
  });

  test('data all\'inizio del titolo spostata alla fine', () {
    final a = archive();
    final d = Document(title: '2023-05-12 Verbale assemblea', created: DateTime(2023, 5, 12), typeId: 'st-casa');
    expect(drivePath(a, d).$2, 'Verbale assemblea 12-05-2023');
    d.title = '12.05.2023_Verbale assemblea';
    expect(drivePath(a, d).$2, 'Verbale assemblea 12-05-2023');
    expect(titleFromDriveName('20230512 Verbale.pdf'), 'Verbale');
  });

  test('vecchi percorsi con la data davanti vengono aggiornati', () {
    final p = StoragePath.fromJson({'id': 'x', 'name': 'Box', 'tpl': '{document_type}/Box/{created_year}/{created} {title}'});
    expect(p.template, '{document_type}/Box/{created_year}/{title} {data}');
  });

  test('una sottocartella imparata vale solo per la sua categoria', () {
    final a = archive();
    final box = Document(title: 'Rata box', content: 'condominio box rata', created: DateTime(2026, 5, 1), typeId: 'st-casa');
    a.documents[box.id] = box;
    applyFolderCorrection(a, box, folders: ['Casa', 'Lavori condominiali', '2026', 'Box']);
    final asilo = Document(title: 'Iscrizione asilo', content: 'asilo nido iscrizione', created: DateTime(2026, 5, 25), typeId: 'st-scuola')
      ..storagePathId = box.storagePathId;
    expect(drivePath(a, asilo).$1, ['Scuola e studio', '2026']);
    expect(dropUnfitPath(a, asilo), isTrue);
    expect(asilo.storagePathId, isNull);
  });

  test('i vecchi percorsi imparati prendono la categoria dei tuoi documenti', () {
    final a = archive();
    final p = StoragePath(name: 'Box', template: '{document_type}/{created_year}/Box/{title} {data}');
    a.storagePaths[p.id] = p;
    final d = Document(title: 'Rata', typeId: 'st-casa', userEdited: true, created: DateTime(2026))..storagePathId = p.id;
    a.documents[d.id] = d;
    expect(migrateLearnedPaths(a), 1);
    expect(p.template, startsWith('Casa/'));
    final asilo = Document(title: 'Asilo', typeId: 'st-scuola', created: DateTime(2026))..storagePathId = p.id;
    expect(drivePath(a, asilo).$1, ['Scuola e studio', '2026']);
  });
}

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
    expect(name, '2026-04-02 Spese condominiali box');
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
}

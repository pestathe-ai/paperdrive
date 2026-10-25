import 'package:flutter_test/flutter_test.dart';
import 'package:paperdrive/core/archive.dart';
import 'package:paperdrive/core/models.dart';
import 'package:paperdrive/core/organize.dart';
import 'package:paperdrive/core/people.dart';

// Documenti di fantasia, con nomi e codici fiscali inventati.
const refertoCardio = 'OSPEDALE SAN GERARDO\nU.O. CARDIOLOGIA\nREFERTO ECOCARDIOGRAMMA\n'
    'Paziente: ROSSI MARIA nata il 01/01/1980\nC.F. RSSMRA80A41F205X\n'
    'Data esame 12/03/2026\nConclusioni: funzione sistolica conservata.';
const ricetta = 'SERVIZIO SANITARIO NAZIONALE\nRICETTA ELETTRONICA - PROMEMORIA PER L\'ASSISTITO\n'
    'Cognome e nome: BIANCHI LUCA\nPrescrizione: visita oculistica\nData 02/02/2026';
const bolletta = 'Enel Energia\nBolletta luce\nIntestatario: Rossi Maria\nTotale da pagare 84,20 euro\n05/03/2026';
const busta = 'Cedolino paga marzo 2026\nDipendente: ROSSI MARIA\nNetto in busta 1.500,00';

void main() {
  final people = [
    Person(name: 'Maria', aliases: ['Maria Rossi', 'RSSMRA80A41F205X']),
    Person(name: 'Luca', aliases: ['Luca Bianchi']),
  ];

  test('chi è intestato', () {
    expect(detectPerson(people, refertoCardio)?.name, 'Maria');
    expect(detectPerson(people, ricetta)?.name, 'Luca');
    expect(detectPerson(people, 'Fattura senza nomi'), isNull);
    // Solo codice fiscale.
    expect(detectPerson(people, 'Assistito RSSMRA 80A41 F205X')?.name, 'Maria');
  });

  test('specialità e referto o prescrizione', () {
    expect(detectSpecialty(refertoCardio), 'Cardiologia');
    expect(healthKind(refertoCardio), 'Referti');
    expect(healthKind(ricetta), 'Prescrizioni');
    expect(detectSpecialty(ricetta), 'Oculistica');
    expect(healthKind('Fattura n. 12 visita'), 'Altro');
  });

  group('cartelle', () {
    Archive archive() {
      final a = Archive.starter();
      a.config.people.addAll(people);
      ensurePeopleEntities(a);
      return a;
    }

    test('sanità per persona, specialità, referti, anno e mese', () {
      final a = archive();
      final d = Document(
        title: 'Ecocardiogramma San Gerardo',
        content: refertoCardio,
        created: DateTime(2026, 3, 12),
        typeId: healthTypeId,
      );
      applyPeople(a, d);
      final (folders, name) = drivePath(a, d);
      expect(folders, ['Sanità', 'Maria', 'Cardiologia', 'Referti', '2026', '03 Marzo']);
      expect(name, 'Ecocardiogramma San Gerardo 12-03-2026');
    });

    test('lavoro per persona, bollette comuni', () {
      final a = archive();
      final paga = Document(title: 'Busta paga marzo', content: busta, created: DateTime(2026, 3, 31), typeId: 'st-paga');
      applyPeople(a, paga);
      expect(drivePath(a, paga).$1, ['Busta paga', 'Maria', '2026']);
      final luce = Document(title: 'Bolletta luce', content: bolletta, created: DateTime(2026, 3, 5), typeId: 'st-bolletta');
      applyPeople(a, luce);
      expect(luce.customFields[personFieldId], 'Maria');
      expect(drivePath(a, luce).$1, ['Bolletta', '2026']);
    });

    test('valore scelto a mano non viene cambiato', () {
      final a = archive();
      final d = Document(title: 't', content: refertoCardio, typeId: healthTypeId)
        ..customFields[personFieldId] = 'Luca';
      applyPeople(a, d);
      expect(d.customFields[personFieldId], 'Luca');
    });

    test('senza persone: percorso come prima', () {
      final a = Archive.starter();
      final d = Document(title: 'Bolletta luce', content: bolletta, created: DateTime(2026, 3, 5), typeId: 'st-bolletta');
      applyPeople(a, d);
      expect(drivePath(a, d).$1, ['Bolletta', '2026']);
    });

    test('il vecchio modello di percorso passa a quello con la persona', () {
      final c = ArchiveConfig.fromJson({'path': ArchiveConfig.oldPathTemplate});
      expect(c.pathTemplate, ArchiveConfig.defaultPathTemplate);
      final c2 = ArchiveConfig.fromJson({...c.toJson(), 'people': [people.first.toJson()]});
      expect(c2.people.single.aliases, contains('RSSMRA80A41F205X'));
    });
  });
}

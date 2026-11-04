import 'package:flutter_test/flutter_test.dart';
import 'package:paperdrive/core/amounts.dart';
import 'package:paperdrive/core/models.dart';

void main() {
  test('importi scritti in modi diversi', () {
    expect(parseEuro('1.234,56 €'), 1234.56);
    expect(parseEuro('18.94'), 18.94);
    expect(parseEuro('47,82'), 47.82);
    expect(parseEuro('150'), 150);
    expect(parseEuro('abc'), isNull);
    expect(parseEuro('0,00'), isNull);
  });

  test('l\'AI vale solo se la cifra compare nel testo', () {
    final d = Document(title: 'Iscrizione asilo', content: 'Prot. 123 Retta mensile settembre 350,00 euro Quota iscrizione 50,00');
    expect(fillAmount(d, ai: '350,00'), isTrue);
    expect(d.amount, 350);
    final e = Document(title: 'x', content: 'Totale 20,00 euro');
    fillAmount(e, ai: '999,00');
    expect(e.amount, 20);
  });

  test('sugli scontrini vince la lettura dell\'app', () {
    final d = Document(title: 'x', content: 'DOCUMENTO COMMERCIALE\nFARMACO 16,95\n16,95\nTOTALE COMPLESSIVO\n47,82\n47,82');
    fillAmount(d, ai: '16,95');
    expect(d.amount, 47.82);
  });

  test('scritto a mano: l\'app non lo cambia più', () {
    final d = Document(title: 'x', content: 'Totale 20,00 euro', amount: 25, amountEdited: true);
    expect(fillAmount(d), isFalse);
    expect(amountFor(d), 25);
    final none = Document(title: 'x', content: 'Totale 20,00 euro', amountEdited: true);
    expect(amountFor(none), isNull);
  });

  test('si salva con il documento', () {
    final d = Document(title: 'x', amount: 12.5, amountEdited: true);
    final back = Document.fromJson(d.toJson());
    expect(back.amount, 12.5);
    expect(back.amountEdited, isTrue);
  });
}

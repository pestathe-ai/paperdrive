/// Categorie predefinite (tipi di documento con regole) per partire subito:
/// l'app sa riconoscere bollette, fatture, buste paga, referti…
library;

import 'archive.dart';
import 'models.dart';
import 'text_utils.dart';

/// (id fisso, nome, parole chiave per la regola "una qualsiasi parola").
const List<(String, String, String)> starterTypes = [
  ('st-bolletta', 'Bolletta',
      'bolletta "energia elettrica" "gas naturale" kwh smc "servizio idrico" "consumi fatturati" "fornitura di" pod pdr'),
  ('st-fattura', 'Fattura',
      'fattura "fattura elettronica" imponibile "partita iva" "p.iva" "aliquota iva"'),
  ('st-scontrino', 'Scontrino e ricevuta',
      'scontrino "documento commerciale" ricevuta "ricevuta di pagamento" "pagamento elettronico"'),
  ('st-banca', 'Banca',
      '"estratto conto" "conto corrente" bonifico iban "saldo contabile" "carta di credito" mutuo "rendiconto"'),
  ('st-paga', 'Busta paga',
      '"busta paga" cedolino retribuzione "netto in busta" "netto da pagare" cud "certificazione unica" tfr'),
  ('st-tasse', 'Tasse',
      'f24 "agenzia delle entrate" "modello 730" "730/2" imu tari "codice tributo" "cartella di pagamento" "dichiarazione dei redditi" pagopa'),
  ('st-sanita', 'Sanità',
      'referto ricetta "ticket sanitario" asl "azienda sanitaria" ospedale ambulatorio "visita specialistica" "esame del sangue" diagnosi farmacia'),
  ('st-assicurazione', 'Assicurazione',
      'polizza assicurazione assicurativa "premio annuo" sinistro "rc auto" quietanza'),
  ('st-contratto', 'Contratto',
      'contratto "le parti" "si conviene" "si stipula" "letto, confermato e sottoscritto" clausola locazione'),
  ('st-auto', 'Auto e veicoli',
      '"bollo auto" "tassa automobilistica" revisione "carta di circolazione" libretto targa tagliando'),
  ('st-casa', 'Casa',
      'condominio condominiale "spese condominiali" catasto "atto di compravendita" rogito affitto canone'),
  ('st-scuola', 'Scuola e studio',
      'scuola iscrizione pagella "anno scolastico" università ateneo "certificato di laurea" esame'),
  ('st-lavoro', 'Lavoro',
      '"lettera di assunzione" "contratto di lavoro" dimissioni curriculum inail'),
  ('st-garanzia', 'Garanzia e acquisti',
      'garanzia "numero d\'ordine" "conferma d\'ordine" spedizione "numero di serie" manuale'),
];

const String starterInboxId = 'st-inbox';

/// Aggiunge il tag "Da esaminare" e le categorie predefinite che mancano.
/// Restituisce quante categorie sono state aggiunte.
int addStarterEntities(Archive a) {
  if (!a.tags.containsKey(starterInboxId) && a.inboxTags.isEmpty) {
    a.tags[starterInboxId] = Tag(
      id: starterInboxId,
      name: 'Da esaminare',
      color: 0xFFC62828,
      isInbox: true,
      modified: 1,
    );
  }
  final existing = a.activeTypes.map((t) => normalize(t.name)).toSet();
  var added = 0;
  for (final (id, name, pattern) in starterTypes) {
    if (a.types.containsKey(id) || existing.contains(normalize(name))) continue;
    a.types[id] = NamedEntity(
      id: id,
      name: name,
      algorithm: MatchAlgorithm.any,
      pattern: pattern,
      modified: 1,
    );
    added++;
  }
  return added;
}

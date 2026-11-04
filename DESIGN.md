# D. Paper Lab — come decide dove va un documento

Documento di progetto del motore di catalogazione (versione 0.19). Descrive
le scelte fatte e perché. Il codice è in `lib/core/`.

## Obiettivo

Un archivio personale che si ordina da solo **come lo ordinerebbe chi lo
usa**, partendo da pochissimi esempi, sul telefono, senza server e senza
mandare i documenti a nessuno. Ogni decisione deve essere spiegabile ("l'ho
messo qui perché somiglia a questi documenti") e ogni correzione deve contare
subito.

## Le quattro fonti, in ordine di fiducia

1. **Regole scritte dall'utente** (`matching.dart`, `ruleStrength`). Sono
   una scelta esplicita: vincono sempre.
2. **Apprendimento per esempi** (`learner.dart`). Vince sulle regole
   predefinite solo se è sicuro (fiducia ≥ 0.6).
3. **Regole predefinite** (`starter.dart`, `extract.dart`): parole chiave e
   tipi di documento comuni in Italia (bollette, referti, buste paga…), per
   avere un archivio sensato dal primo giorno.
4. **AI sul telefono** (`ai.dart`): un modello linguistico locale legge il
   documento e propone categoria, mittente, titolo, persona e sottocartella.
   Non scavalca le scelte dell'utente né gli esempi molto simili.

Quando nessuna fonte è abbastanza sicura, l'app **chiede** (scheda "Da
sistemare") invece di indovinare. Si può spegnere ("Chiedimi quando non è
sicura").

## Regole a parole chiave

Il testo viene ridotto a **parole normalizzate** (minuscole, senza accenti,
solo lettere e numeri) una volta sola (`TextWords`). Le regole lavorano su
parole intere, non su pezzi di caratteri:

| Modo | Corrisponde se | Forza |
|---|---|---|
| Una qualsiasi parola | almeno una parola/frase chiave compare | 1 − 0,5ⁿ (n = parole trovate): più parole, più pertinente |
| Tutte le parole | tutte compaiono | 1 |
| Frase esatta | la sequenza di parole compare (con maiuscole esatte se richiesto) | 1 |
| Espressione regolare | l'espressione trova qualcosa | 1 |
| Tollerante | ogni parola compare, anche con errori dell'OCR | 0,9 |

**Tollerante** ammette, per ogni parola, una distanza di modifica di circa
una lettera ogni quattro (nessun errore sotto le 4 lettere, al massimo 3), con
un calcolo che si ferma appena il limite è superato. Così "AGENZlA" (l al
posto di I) corrisponde ad "Agenzia", ma "IVA" non corrisponde a "IVB".

## Apprendimento per esempi

Invece di addestrare un modello statistico (che con pochi documenti
sbaglia e non sa spiegare le sue scelte), l'app tiene i documenti sistemati
come **esempi** e, per un documento nuovo, chiede ai più simili.

1. **Esempi**: documenti già esaminati o corretti a mano.
2. **Somiglianza**: ogni documento diventa un vettore di parole pesate per
   rarità nell'archivio (`Idf`): il nome e l'indirizzo dell'utente, presenti
   ovunque, non contano; contano le parole tipiche. Numeri, codici e date
   sono esclusi. Si confronta con il coseno.
3. **Vicini**: i 7 esempi più simili con somiglianza ≥ 0,25.
4. **Voto**: ogni vicino vota la sua etichetta con peso = somiglianza².
   Vince l'etichetta con almeno metà del peso, sostenuta da almeno due
   vicini (o da uno quasi identico, ≥ 0,75).
5. **Fiducia** = quota del voto × (0,5 + somiglianza massima / 2). Sotto
   0,3 non risponde.
6. **Tag**: un tag è proposto se ha almeno metà del peso dei vicini e
   almeno due esempi.
7. Con meno di 6 esempi l'app non propone nulla.

Vantaggi: nessun addestramento lungo, ogni correzione è subito un esempio,
e `Learner.similar` dice quali documenti hanno deciso.

## Le cartelle dell'utente

- **Struttura**: prima la persona, poi la categoria, poi l'anno
  (`Nina/Scuola e studio/2026`). Ciò che è di tutta la casa sta in cima.
- **Spostamenti su Drive** (file o cartelle intere) e cartelle scritte
  nell'app diventano correzioni (`drive_learning.dart`): persona, categoria e
  sottocartelle vengono riconosciute ovunque si trovino nel percorso, e il
  documento resta esattamente dove l'utente l'ha messo.
- **Sottocartelle personali** ("Casa/Via alessandrina/Box"): valgono solo
  per la loro categoria. Un documento nuovo ci va se contiene le parole che
  distinguono quella sottocartella dal resto della categoria, se l'AI la
  indica, o se è quasi uguale a un documento che l'utente ci ha messo; nei
  casi in bilico l'app chiede.

## Cosa non fa

- Non manda i documenti fuori dal telefono (a parte Google Drive
  dell'utente e la conversione in PDF dei file Office, fatta da Drive).
- Non inventa date: la data proposta dall'AI vale solo se compare nel testo.

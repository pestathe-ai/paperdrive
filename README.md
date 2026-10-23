# D. Paper Lab

*un'app Dom Studio* (nome interno del progetto: Paperdrive).

Archivio di documenti per Android ispirato a [Paperless-ngx](https://docs.paperless-ngx.com/):
scansioni e PDF con OCR, tag, corrispondenti, tipi, ricerca nel testo e regole
automatiche. Niente server da mantenere: tutto gira sul telefono e si
sincronizza su **Google Drive**. L'APK viene compilato da GitHub Actions.

## Funzioni

### AI sul telefono (v0.8)

Da *Impostazioni → AI sul telefono* si scarica una volta un modello linguistico gratuito
(**Gemma 4 E2B** di Google, 2,6 GB, oppure Qwen 2.5 1.5B, 1,6 GB) che gira sulla GPU del telefono
con LiteRT-LM. Ogni documento aggiunto viene letto dal modello, che ne capisce tipo, categoria,
mittente, data e gli dà un nome specifico (es. `Etichetta spedizione Vinted InPost`). Nessun
documento esce dal telefono e funziona senza internet.

Precedenza: regole scritte dall'utente e documenti simili corretti a mano > AI > regole
predefinite. La data dell'AI viene usata solo se compare davvero nel testo. Dal menu di un
documento: *Rileggi con l'AI*. Richiede Android 11+ e un telefono arm64.

### Chiedi e Domande per te (v0.11)

- **Chiedi** (icona ✦ in alto): domande in italiano, anche dettate col microfono della tastiera.
  "Ultima bolletta della luce", "referto cardiologico di Maria", "quanto ho speso dal dentista nel 2025".
  Le regole capiscono categoria, persona, specialità, mittente, anno e mese; l'AI sul telefono (se
  scaricata) completa le domande più libere. Risponde con i documenti, il più recente, il conteggio o
  il totale degli importi.
- **Domande per te**: quando non riconosce la categoria o non sa di chi è un documento personale,
  l'app chiede invece di sbagliare cartella. Ogni risposta vale come correzione e le insegna.

### Persone e sanità (v0.10)

In *Persone della famiglia* si inseriscono i nomi (con nome e cognome e codice fiscale). I documenti
vanno nella cartella della persona (`Lavoro/Maria/2026`); la sanità è divisa per persona, specialità,
referti/prescrizioni, anno e mese (`Sanità/Maria/Cardiologia/Referti/2026/03 Marzo`). Bollette e
casa restano comuni.

### Cartella di importazione su Drive (v0.9)

Come la *consume folder* di Paperless: copia i documenti (anche intere cartelle, per esempio da
Dropbox) in `Paperdrive/Da importare` su Google Drive e premi *Menu → Importa da Drive* (oppure
attiva l'importazione automatica all'apertura). Ogni file viene letto, classificato e archiviato,
poi spostato nel cestino di Drive. L'ordine fatto a mano viene rispettato: la prima cartella
diventa la categoria, le sottocartelle i tag, una cartella con l'anno dà l'anno, un nome di file
già chiaro resta il titolo. L'app impara da questi documenti come classifichi e rinomini.

### Impara dalle correzioni (v0.7)

Quando correggi categoria, mittente o titolo di un documento, l'app impara: i documenti simili
successivi vengono classificati e rinominati allo stesso modo.

### Fedele a Paperless-ngx (v0.6)

La logica di classificazione è portata dal codice di Paperless-ngx:
- **Regole** come `matching.py`: Una qualsiasi parola, Tutte le parole, Testo esatto, Regex, Approssimata (somiglianza ≥ 90, senza punteggiatura), Automatica.
- **Classificatore automatico** come `classifier.py`: impara dai documenti già esaminati (senza tag *Da esaminare*), solo per le etichette con algoritmo *Automatica*; parole e coppie di parole → rete neurale con 100 neuroni nascosti; soglia 0.3 per corrispondente/tipo/percorso, 0.5 per i tag. Si riaddestra da solo dopo le modifiche.
- **Suggerimenti** nel dettaglio del documento, come nell'interfaccia di Paperless.
- **Segnaposti** anche con la sintassi di Paperless (`{{ correspondent }}`, `{{ created_year }}`, `{{ created_month_name }}`…).
- I nuovi tag, corrispondenti e tipi usano *Automatica*, come nell'interfaccia di Paperless.

### Archiviazione automatica (v0.3)

Ogni documento che **scansioni**, **importi**, ricevi per **email** o **condividi verso Paperdrive** da un'altra app (menu *Condividi* o *Apri con*, anche più file insieme) viene, senza altri passaggi:

1. **letto** (testo del PDF o OCR, con versione PDF/A ricercabile);
2. **diviso** se nella scansione c'è un foglio separatore con codice a barre (PATCH T) e numerato con l'**ASN** letto dall'etichetta;
3. **classificato**: categoria (14 categorie predefinite già pronte: Bolletta, Fattura, Scontrino, Banca, Busta paga, Tasse, Sanità, Assicurazione, Contratto, Auto, Casa, Scuola, Lavoro, Garanzia), corrispondente, tag, percorso; vince la regola più pertinente;
4. **rinominato** con un modello, es. `Bolletta Enel 03-2024`;
5. **archiviato su Google Drive** in cartelle per categoria e anno, es. `Paperdrive/Bolletta/2024/2024-03-05 Bolletta Enel 03-2024.pdf` (modello modificabile, più *percorsi* personalizzati come in Paperless). Se cambi categoria o titolo, il file su Drive viene spostato e rinominato.

Tutto si regola da *Menu → Archiviazione automatica*, con anteprima del risultato.

### Altre funzioni

- **Modifica pagine**: ruota, elimina, riordina; **dividi** un documento in più parti; **unisci** più documenti (selezione multipla).
- **Cronologia** di ogni documento (chi ha cambiato cosa e quando) e **documenti simili**.
- **Scansione** con lo scanner di documenti di Google (ritaglio, raddrizzamento, più pagine) e **importazione** di PDF e immagini.
- **OCR sul telefono** (ML Kit, testo latino): i PDF digitali usano il loro testo, quelli scansionati vengono letti pagina per pagina.
- **Versione archiviata PDF/A** (novità v0.2): per scansioni e foto viene creato un PDF/A-3b con il testo dell'OCR invisibile sopra l'immagine, quindi ricercabile e copiabile in qualsiasi lettore PDF. Validato con veraPDF in CI.
- **Data del documento** riconosciuta dal testo, con le altre date trovate proposte con un tocco.
- **Tag**, **corrispondenti**, **tipi di documento**, **campi personalizzati**, **note**, **numero d'archivio (ASN)**, tag **"Da esaminare"**.
- **Regole automatiche** come Paperless: una parola, tutte, testo esatto, regex, approssimata e automatica (impara dai documenti già classificati).
- **Flussi di lavoro** (novità v0.2): quando un documento viene *aggiunto* (da scansione, file o email) o *modificato*, se valgono le condizioni (nome file con `*`, testo, tag presenti/assenti, corrispondente, tipo) esegue le azioni: titolo con segnaposti (`{correspondent}`, `{created_year}`, `{campo:Importo}`…), aggiungi/togli tag, corrispondente, tipo, campi, ASN, segna esaminato, nota. Ordine trascinabile ed esecuzione sui documenti esistenti.
- **Importazione da email** (novità v0.2): account IMAP (server trovato in automatico dall'indirizzo), regole con filtri su mittente, destinatario, oggetto, testo, nome allegato, età e non letti; importa allegati e/o il testo del messaggio come PDF; assegna tag, tipo, corrispondente (anche dal mittente); poi segna come letto, sposta o contrassegna. Ogni messaggio viene elaborato una volta sola.
- **Più utenti** (novità v0.2): invita altre persone all'archivio (modifica o sola lettura) direttamente dall'app; chi è invitato sceglie "Usa un archivio condiviso con me". Ogni documento ricorda chi l'ha aggiunto e chi l'ha modificato; filtro "Solo aggiunti da me"; modalità sola lettura. **Link pubblici** a singoli documenti, revocabili.
- **Ricerca** nel testo con frasi, esclusioni, `tag:`, `da:`, `tipo:`, `asn:`, `anno:`; **filtri**, **viste salvate**, **modifica multipla**, **cestino**, duplicati saltati.
- **Google Drive**: cartella `Paperdrive` con i PDF e l'indice; più telefoni e più persone sullo stesso archivio, con unione delle modifiche.

## Collegare Google Drive (una volta sola, ~10 minuti)

Google richiede che ogni app che usa Drive sia registrata. Dal browser:

1. Vai su <https://console.cloud.google.com/> e crea un progetto (es. "Paperdrive").
2. **API e servizi → Libreria**: cerca **Google Drive API** e premi **Abilita**.
3. **API e servizi → Schermata consenso OAuth** (o "Google Auth Platform"): tipo **Esterno**, nome app "Paperdrive", la tua email. In **Pubblico / Utenti di test** aggiungi il tuo indirizzo Gmail.
4. **Credenziali → Crea credenziali → ID client OAuth → Android**:
   - Nome pacchetto: `dev.paperdrive.paperdrive`
   - Impronta SHA-1: `28:64:55:35:6C:77:EA:5D:30:D8:50:F4:CD:62:3D:38:89:CC:81:FD`
5. Nell'app: **Impostazioni → Collega Google Drive**. Google mostrerà "app non verificata": tocca *Avanzate* → *Vai a Paperdrive*.

Dalla v0.2 l'app chiede l'accesso completo a Drive (serve per gli archivi condivisi da altre persone): chi aveva collegato la v0.1 deve toccare **Ricollega**.
Chi viene invitato a un archivio condiviso deve essere aggiunto anche lui tra gli **utenti di test** del progetto Google Cloud.

Entrambi i valori si possono copiare anche da *Impostazioni → Dati per Google Cloud*.
L'app usa la cartella `Paperdrive` (e quelle che altre persone condividono con te) e non tocca il resto del Drive.

## Limiti noti

- Solo Android 11+ (arm64). OCR per alfabeto latino.
- La posta viene controllata all'apertura dell'app e con "Controlla ora", non in background ad app chiusa.
- Gmail richiede una *password per le app*; gli account Outlook/Hotmail personali non accettano più la password via IMAP.
- La password email è salvata nello spazio privato dell'app sul telefono (non cifrata a parte).
- In un archivio condiviso i permessi li applica Google Drive: chi ha accesso vede tutti i documenti (niente documenti privati per singolo utente).
- La versione PDF/A viene creata per scansioni, foto e PDF senza testo; per i PDF digitali si può crearla dal menu del documento.
- L'indice è un unico file JSON: pensato per centinaia/qualche migliaio di documenti. Se due persone modificano lo stesso documento quasi insieme, vince l'ultima modifica.
- Non presenti: OCR per alfabeti non latini, API per altre app.
- La firma dell'APK è una chiave di sviluppo pubblica (vedi `tool/signing/`).

## Sviluppo

Il codice Flutter è in `lib/`; la logica pura (regole, date, ricerca, unione dell'archivio) è in `lib/core/` ed è coperta dai test in `test/`.
La cartella `android/` viene generata in CI da `tool/setup_platforms.sh`.
Ogni push su `main` compila l'APK e lo pubblica nelle *Releases*.

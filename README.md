# Paperdrive

Archivio di documenti per Android ispirato a [Paperless-ngx](https://docs.paperless-ngx.com/):
scansioni e PDF con OCR, tag, corrispondenti, tipi, ricerca nel testo e regole
automatiche. Niente server da mantenere: tutto gira sul telefono e si
sincronizza su **Google Drive**. L'APK viene compilato da GitHub Actions.

## Funzioni (v0.1)

- **Scansione** con lo scanner di documenti di Google (ritaglio, raddrizzamento, più pagine) e **importazione** di PDF e immagini.
- **OCR sul telefono** (ML Kit, testo latino): i PDF digitali usano il loro testo, quelli scansionati vengono letti pagina per pagina.
- **Data del documento** riconosciuta dal testo (05/03/2024, 2024-03-05, 12 marzo 2024, March 3, 2024…), con le altre date trovate proposte con un tocco.
- **Tag** colorati, **corrispondenti**, **tipi di documento**, **campi personalizzati** (testo, numero, importo, data, sì/no, link), **note**, **numero d'archivio (ASN)**.
- **Tag "Da esaminare"** (inbox) aggiunto a ogni nuovo documento.
- **Regole automatiche** come Paperless: una parola, tutte le parole, testo esatto, espressione regolare, approssimata (tollera errori OCR) e **automatica** (impara dai documenti già classificati). Pulsante "Prova sui documenti" e "Applica ai documenti esistenti".
- **Ricerca** nel testo, titolo, note e nomi; frasi tra virgolette, esclusioni (`-bozza`), `tag:casa`, `da:enel`, `tipo:fattura`, `asn:12`, `anno:2024`.
- **Filtri** (tag inclusi/esclusi, corrispondente, tipo, intervallo di date, senza tag) e **viste salvate** mostrate in alto.
- **Modifica multipla**: tieni premuto per selezionare, poi tag, corrispondente, tipo, regole, cestino.
- **Cestino** con ripristino; duplicati saltati in automatico (MD5).
- **Google Drive**: cartella `Paperdrive` con i PDF e l'indice `paperdrive-index.json`. Più telefoni possono usare lo stesso archivio: vince la modifica più recente.
- Anteprima PDF, condivisione, tema chiaro/scuro.

## Collegare Google Drive (una volta sola, ~10 minuti)

Google richiede che ogni app che usa Drive sia registrata. Dal browser:

1. Vai su <https://console.cloud.google.com/> e crea un progetto (es. "Paperdrive").
2. **API e servizi → Libreria**: cerca **Google Drive API** e premi **Abilita**.
3. **API e servizi → Schermata consenso OAuth** (o "Google Auth Platform"): tipo **Esterno**, nome app "Paperdrive", la tua email. In **Pubblico / Utenti di test** aggiungi il tuo indirizzo Gmail.
4. **Credenziali → Crea credenziali → ID client OAuth → Android**:
   - Nome pacchetto: `dev.paperdrive.paperdrive`
   - Impronta SHA-1: `28:64:55:35:6C:77:EA:5D:30:D8:50:F4:CD:62:3D:38:89:CC:81:FD`
5. Nell'app: **Impostazioni → Collega Google Drive**.

Entrambi i valori si possono copiare anche da *Impostazioni → Dati per Google Cloud*.
L'app usa solo il permesso `drive.file`: vede esclusivamente i file che ha creato.

## Limiti noti

- Solo Android. OCR per alfabeto latino.
- L'indice è un unico file JSON: pensato per centinaia/qualche migliaio di documenti.
- Se due telefoni modificano **lo stesso** documento quasi nello stesso momento, vince l'ultima modifica.
- Non ancora presenti rispetto a Paperless-ngx: importazione da email, cartella di importazione automatica, flussi di lavoro (workflow), percorsi di archiviazione, più utenti e permessi, condivisione via link, versione PDF/A archiviata.
- La firma dell'APK è una chiave di sviluppo pubblica (vedi `tool/signing/`): adatta all'uso personale, non al Play Store.

## Sviluppo

Il codice Flutter è in `lib/`; la logica pura (regole, date, ricerca, unione dell'archivio) è in `lib/core/` ed è coperta dai test in `test/`.
La cartella `android/` viene generata in CI da `tool/setup_platforms.sh`.
Ogni push su `main` compila l'APK e lo pubblica nelle *Releases*.

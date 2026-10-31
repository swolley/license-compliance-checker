# license-compliance-checker v2: controllo licenze agnostico, in bash

Data: 2026-10-31. Stato: bozza da rivedere.

## 1. Obiettivo

Trasformare il tool (oggi PHP, solo `composer.lock` e `node_modules`) in un controllo di licenze valido per qualsiasi progetto: C++, Python, Java, Rust, PHP, Node, con submodule o cartelle di terze parti. Non deve richiedere PHP né un gestore di pacchetti. Dato un progetto, dice quali dipendenze hanno una licenza compatibile con quella del progetto, quali no e quali vanno verificate a mano.

Successo: lo stesso comando, senza configurazione, produce un esito sensato su un progetto npm, uno composer, uno Cargo e uno C++ con `vendors/`; una licenza non riconosciuta non diventa mai un "ok".

## 2. Decisioni prese

- Implementazione in **bash 4.4 o superiore**, uno script unico `check-licenses`.
- **`jq` obbligatorio**. È dichiarato nel README (requisiti) e lo script esce con errore chiaro se manca.
- Si controllano **tutti i riferimenti a file di licenza ovunque siano** nell'albero, non solo i percorsi dei gestori di pacchetti.
- Il file di configurazione passa a un formato a righe leggibile da bash. Il vecchio `license-compliance.php` non si legge più; si fornisce una conversione una tantum.
- Stesso repo e stesso nome, versione major nuova (2.0.0). Composer non è più il canale unico di installazione.
- Supporto: Linux e macOS (con bash 4.4 o superiore da Homebrew), Windows tramite Git Bash.

## 3. Architettura

Uno script con quattro funzioni, ciascuna con un solo compito:

| Funzione | Compito | Dipende da |
|----------|---------|------------|
| `discover` | Percorre l'albero e produce le voci `{nome, versione, percorso, licenza dichiarata, fonte}` | filesystem, `jq` |
| `detect` | Per i file di testo di licenza ricava l'identificatore SPDX | testo del file |
| `evaluate` | Confronta ogni voce con la matrice e assegna `ok`, `vietata` o `da verificare` | matrice, config |
| `report` | Stampa la tabella o il JSON e fissa il codice di uscita | esiti |

### 3.1 discover

Esclusioni di default: `.git`, `build`, `dist`, `node_modules/.cache`. Si aggiungono o tolgono dalla config. Fonti riconosciute:

- File `LICENSE*`, `LICENCE*`, `COPYING*`, `UNLICENSE*`, `NOTICE*` in qualsiasi cartella. La voce prende il nome dalla cartella che li contiene (o dal manifest vicino, se c'è).
- Header `SPDX-License-Identifier:` nei file sorgente (prime 30 righe).
- Manifest, letti con `jq` dove sono JSON: `package.json` (anche dentro `node_modules`), `composer.lock`. Per i formati non JSON (`Cargo.toml`, `pyproject.toml`, `pom.xml`) si estrae solo il campo licenza con `grep`/`sed`.
- `.gitmodules`: ogni submodule è una voce; se il suo contenuto è presente si cerca la licenza come sopra, altrimenti è `da verificare`.

Una cartella con file di licenza e manifest dà una sola voce; se le due fonti non coincidono, la voce è `da verificare` con la causa nel rapporto.

### 3.2 detect

Corrispondenza su frasi caratteristiche di ogni licenza, valutate in un ordine che evita le confusioni (LGPL e AGPL prima di GPL, Apache prima di MIT, ecc.). Il file `LICENSES/<id>.txt` (stile REUSE) dichiara direttamente l'identificatore dal nome. Se nessuna frase corrisponde, il risultato è "sconosciuta", mai un valore indovinato.

### 3.3 evaluate

Resta la logica attuale:

- licenza esatta (`MIT`), wildcard (`BSD-*`), vincolo di versione (`GPL->=3.0`), gruppi (`@permissive`, anche annidati);
- espressioni SPDX con `AND` (tutte ammesse) e `OR` (almeno una ammessa);
- licenza vuota o `UNKNOWN` mai ammessa.

La matrice chiave per licenza del progetto. La licenza del progetto si legge da: opzione `--project-license`, config, `package.json`/`composer.json`, `LICENSE` della radice, `LICENSES/`. Se non è rilevabile: errore, codice 2.

### 3.4 report

Tabella a colori su TTY (colori disattivati altrimenti), colonna `Fonte` (file o manifest da cui viene la licenza). Con `--json` stampa le voci con tutti i campi.

## 4. Configurazione

File `.license-compliance` nella radice del progetto (o percorso con `--config`), una direttiva per riga, `#` per i commenti:

```
project-license  GPL-3.0-or-later
exclude          vendors/tests
include          node_modules/.cache
allow            some-package  LicenseRef-Custom   # eccezione per una dipendenza
group            permissive    MIT ISC BSD-* Apache-*
matrix           GPL-3.0-or-later  @permissive GPL->=3.0
```

La matrice e i gruppi di default sono incorporati nello script (quelli di oggi, tradotti). La config del progetto li estende o li sostituisce per chiave.

## 5. Errori e codici di uscita

- 0: nessuna voce `vietata`.
- 1: almeno una voce `vietata`. Con `--strict` anche una `da verificare`.
- 2: errore d'uso (jq assente, bash troppo vecchio, licenza del progetto non rilevabile, config non valida).

## 6. Test

- bats. Prima i test, poi il codice: ogni funzione ha test che prima falliscono.
- Cartella `tests/fixtures/` con progetti minimi: npm, composer, Cargo, C++ con `vendors/` e file `LICENSE`, submodule senza licenza, conflitto tra manifest e testo, espressione `AND`/`OR`, header SPDX.
- Test di integrazione dell'intero comando per ogni fixture (codice di uscita e output).
- CI su Linux e macOS.

## 7. Rilascio e migrazione

- Branch `feat/generic-bash-checker`, release 2.0.0 con lo script come asset; installazione con `curl` o copia dello script.
- `bin/check-licenses` PHP, `src/`, `composer.json` e i test Pest escono dal repo; il vecchio comportamento resta nella 1.x.
- Nessuno script di conversione: il README ha una tabella che mappa `license_families`, `groups` e `compatibility` di `license-compliance.php` sulle direttive di `.license-compliance`.
- README riscritto: requisiti (bash 4.4, jq), uso, formato della config, esempi per ecosistema.

## 8. Fuori ambito

- Risoluzione di dipendenze transitive non presenti su disco (lo script legge ciò che è installato o vendorizzato).
- Verifica legale delle licenze: lo strumento segnala, non dà consulenza.
- Provider dedicati per ogni ecosistema oltre ai manifest elencati; si aggiungono dopo, se serve.

## 9. Decisioni aperte

- Nessuna al momento.

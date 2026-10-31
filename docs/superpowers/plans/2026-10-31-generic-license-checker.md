# license-compliance-checker v2: piano di implementazione

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Sostituire il checker PHP con uno script bash agnostico che controlla le licenze di qualsiasi progetto.

**Architecture:** Uno script `check-licenses` con quattro stadi (`discover`, `detect`, `evaluate`, `report`) che si passano record TSV a 6 campi. Il motore delle regole è il porting della logica PHP esistente. I test sono in bats; lo script si può caricare con `LCC_SOURCE_ONLY=1` per chiamare le singole funzioni.

**Tech Stack:** bash 4.4+, jq, bats-core, GitHub Actions (Linux e macOS).

**Spec:** `docs/superpowers/specs/2026-10-31-generic-license-checker-design.md`

## Global Constraints

- Bash 4.4 o superiore, `jq` obbligatorio: se manca uno dei due, messaggio chiaro ed exit 2.
- Codici di uscita: 0 nessuna voce `vietata`; 1 almeno una `vietata` (con `--strict` anche `da verificare`); 2 errore d'uso.
- Esiti per voce: `ok`, `forbidden`, `review` (in italiano nella spec: `vietata`, `da verificare`). Una licenza non riconosciuta, vuota o `UNKNOWN` non è mai `ok`.
- Config di progetto: `.license-compliance` nella radice (o `--config`), una direttiva per riga, `#` per i commenti. Direttive: `project-license`, `exclude`, `include`, `allow`, `group`, `matrix`.
- Esclusioni di default: `.git`, `build`, `dist`, `node_modules/.cache`.
- File di licenza riconosciuti: `LICENSE*`, `LICENCE*`, `COPYING*`, `UNLICENSE*`, `NOTICE*`; header `SPDX-License-Identifier:` nelle prime 30 righe dei sorgenti.
- Record TSV a 6 campi, in quest'ordine: `name`, `version`, `path`, `license`, `source` (`file`, `header`, `manifest`, `submodule`), `note`.
- Branch `feat/generic-bash-checker`; versione 2.0.0; messaggi di commit in inglese, senza riga `Co-Authored-By`; commenti nel codice in inglese.
- Linux e macOS in CI; Windows tramite Git Bash. Nessun tag né push senza richiesta esplicita.

## Review Focus

- Percorsi con spazi (es. `The Stripper.vst3/`) o caratteri strani: la scoperta e il report non devono spezzare i nomi. Test in Task 5.
- Link simbolici che puntano a una cartella antenata: nessun ciclo infinito, nessun seguire i symlink. Test in Task 5.
- File `LICENSE` vuoto, binario o enorme: esito `review`, non un errore né un'attesa lunga. Test in Task 4.
- `node_modules` con migliaia di pacchetti: i `package.json` si leggono con poche invocazioni di `jq`, non una per pacchetto. Test in Task 6.
- Progetto senza alcuna dipendenza: messaggio "nessuna dipendenza trovata" ed exit 0, non un errore. Test in Task 8.

---

### Task 1: Scheletro dello script e harness di test

**Files:**
- Create: `check-licenses` (eseguibile), `tests/bats/helper.bash`, `tests/bats/cli.bats`

**Interfaces:**
- Produces: `lcc_require_env`, `lcc_parse_args "$@"` (imposta `LCC_PATH`, `LCC_CONFIG`, `LCC_PROJECT_LICENSE_OPT`, `LCC_JSON`, `LCC_STRICT`), `main "$@"`. Con `LCC_SOURCE_ONLY=1` lo script definisce le funzioni e non esegue `main`. `helper.bash` espone `load_lcc` (source dello script) e `make_project <dir>`.

- [x] **Step 1: Write the failing tests** in `cli.bats`: `missing jq exits 2 with a message naming jq` (PATH ristretto senza jq: `status` 2, output contiene `jq`); `unknown option exits 2`; `--help exits 0 and lists --path, --config, --project-license, --json, --strict`; `--path to a missing directory exits 2`.
- [x] **Step 2: Run** `bats tests/bats/cli.bats`. Expected: FAIL, script assente. Se `bats` manca: `sudo pacman -S bats` in locale (la CI lo installa da apt/brew).
- [x] **Step 3: Implement** lo scheletro con `set -euo pipefail`, versione `2.0.0` in `--version`, e la guardia `LCC_SOURCE_ONLY`.
- [x] **Step 4: Run** i test. Expected: PASS.
- [x] **Step 5: Commit** `feat: skeleton of the bash checker with option parsing and environment checks`.

### Task 2: Configurazione e valori di default

**Files:**
- Modify: `check-licenses`
- Test: `tests/bats/config.bats`

**Interfaces:**
- Produces: `lcc_load_defaults`, `lcc_load_config <file>`. Riempiono `LCC_PROJECT_LICENSE`, array `LCC_EXCLUDE`, `LCC_INCLUDE`, array associativi `LCC_ALLOW` (nome dipendenza → licenze separate da spazio), `LCC_GROUPS`, `LCC_MATRIX` (licenza del progetto → pattern/gruppi separati da spazio), `LCC_FAMILIES` (id SPDX → `famiglia versione`).

- [x] **Step 1: Write the failing tests**: `defaults contain the permissive group and the MIT row`; `defaults keep the GPL-2.0-only row restricted to GPL-<=2.0`; `blank lines and comments are ignored`; `group in the project config replaces the default group of the same name`; `matrix line extends the default matrix`; `allow line is stored per dependency`; `unknown directive exits 2 and names the line number`.
- [x] **Step 2: Run** `bats tests/bats/config.bats`. Expected: FAIL.
- [x] **Step 3: Implement** i default traducendo `config/license-compliance.php` (famiglie, gruppi `permissive`, `permissive-no-strong-copyleft`, `proprietary-allowed`, tutta la tabella `compatibility`) in `lcc_load_defaults`. Parser riga per riga con `read -r directive rest`; l'ultimo valore per chiave vince.
- [x] **Step 4: Run** i test. Expected: PASS.
- [x] **Step 5: Commit** `feat: project config format and built-in license matrix`.

### Task 3: Motore delle regole

**Files:**
- Modify: `check-licenses`
- Test: `tests/bats/matrix.bats`

**Interfaces:**
- Consumes: `LCC_GROUPS`, `LCC_MATRIX`, `LCC_FAMILIES` (Task 2).
- Produces: `lcc_expand_patterns <pattern...>` (stampa i pattern piatti e unici, uno per riga; i gruppi `@nome` si espandono ricorsivamente, i cicli si interrompono), `lcc_license_matches <license> <pattern...>` (exit 0/1), `lcc_is_allowed <expression> <pattern...>` (exit 0/1), `lcc_patterns_for <project-license>` (stampa i pattern espansi; exit 1 se non c'è la riga di matrice).

- [x] **Step 1: Write the failing tests** (porting dei test PHP): `BSD-* matches BSD-3-Clause`; `exact MIT matches MIT only`; `GPL->=3.0 matches GPL-3.0-only and GPL-3.0-or-later but not GPL-2.0-only`; `GPL-<=2.0 matches GPL-2.0-only and not GPL-3.0-only`; `Apache-<=1.1 matches Apache-1.1 and not Apache-2.0`; `MIT AND ISC is allowed when both match`; `MIT AND Foo is refused`; `Foo OR MIT is allowed`; `UNKNOWN and empty are refused`; `nested groups expand`; `cyclic groups terminate`; `lcc_patterns_for fails for a license without a matrix row`.
- [x] **Step 2: Run** `bats tests/bats/matrix.bats`. Expected: FAIL.
- [x] **Step 3: Implement** le funzioni. Il confronto di versione usa `sort -V` (niente float in bash); `AND`/`OR` si valutano dopo il tentativo sull'espressione intera, come nel PHP.
- [x] **Step 4: Run** i test. Expected: PASS.
- [x] **Step 5: Commit** `feat: matrix engine with groups, version constraints and AND/OR`.

### Task 4: Rilevamento della licenza dal testo

**Files:**
- Modify: `check-licenses`
- Test: `tests/bats/detect.bats`, `tests/fixtures/texts/` (un file per licenza)

**Interfaces:**
- Produces: `lcc_detect_text <file>` (stampa l'id SPDX; exit 1 se sconosciuta, senza stampare), `lcc_license_from_filename <path>` (per `LICENSES/<id>.txt` stampa `<id>`), `lcc_detect_spdx_header <file>` (stampa l'espressione dell'header nelle prime 30 righe; exit 1 se assente).

- [x] **Step 1: Write the failing tests**: un test per `MIT`, `ISC`, `Apache-2.0`, `BSD-2-Clause`, `BSD-3-Clause` (distinta dal 2 per "Neither the name of"), `MPL-2.0`, `Unlicense`, `CC0-1.0`, `LGPL-2.1-only`, `LGPL-3.0-only`, `AGPL-3.0-only`, `GPL-2.0-only`, `GPL-3.0-only`; `GPL text with "any later version" yields -or-later`; `LGPL is not detected as GPL`; `empty file is unknown`; `binary file is unknown and returns quickly`; `file of 50 MB is read only in its head` (limite 16 KB, il test misura che termini); `LICENSES/MIT.txt gives MIT`; `SPDX header "MIT OR Apache-2.0" is returned as is`; `header after line 30 is ignored`.
- [x] **Step 2: Run** `bats tests/bats/detect.bats`. Expected: FAIL.
- [x] **Step 3: Implement** con una tabella ordinata (id, frase caratteristica, regex): LGPL e AGPL prima di GPL, Apache prima di MIT. Lettura con `head -c 16384`; i file binari (`grep -qI` fallisce) danno "sconosciuta". Il testo GPL senza la formula "any later version" dà `-only`.
- [x] **Step 4: Run** i test. Expected: PASS.
- [x] **Step 5: Commit** `feat: license detection from text, filename and SPDX headers`.

### Task 5: Scoperta dei file di licenza e dei submodule

**Files:**
- Modify: `check-licenses`
- Test: `tests/bats/discover.bats`, `tests/fixtures/discover/`

**Interfaces:**
- Consumes: `LCC_EXCLUDE`, `LCC_INCLUDE` (Task 2); `lcc_detect_text`, `lcc_detect_spdx_header`, `lcc_license_from_filename` (Task 4).
- Produces: `lcc_discover <root>` (stampa i record TSV a 6 campi con `source` `file`, `header` o `submodule`; `license` vuota se non riconosciuta; un `LICENSE` nella radice è la licenza del progetto e non produce record).

- [x] **Step 1: Write the failing tests**: `finds LICENSE in a nested vendors directory and names the record after the directory`; `skips .git, build and dist by default`; `include removes a default exclusion`; `exclude adds a path`; `header record is one per directory and license`; `submodule from .gitmodules without checkout is a record with empty license and source submodule`; `submodule with checkout takes the license from its LICENSE file`; `directory names with spaces and a tab stay in one field` (fixture `The Stripper.vst3/LICENSE`, il tab sostituito nel campo con uno spazio); `symlink to an ancestor directory does not loop and is not followed`.
- [x] **Step 2: Run** `bats tests/bats/discover.bats`. Expected: FAIL.
- [x] **Step 3: Implement** con `find -P ... -print0` e `read -r -d ''`; le esclusioni con `-prune`. Gli header con `grep -rIn --exclude-dir`, tenendo solo le righe con numero ≤ 30.
- [x] **Step 4: Run** i test. Expected: PASS.
- [x] **Step 5: Commit** `feat: discover license files, SPDX headers and submodules anywhere in the tree`.

### Task 6: Manifest e unione delle fonti

**Files:**
- Modify: `check-licenses`
- Test: `tests/bats/manifests.bats`, `tests/fixtures/manifests/`

**Interfaces:**
- Consumes: record di Task 5.
- Produces: `lcc_read_package_json <file...>` (record `source=manifest`; legge `license` stringa, oggetto `{type}` e array `licenses`, uniti con ` OR `), `lcc_read_composer_lock <file>` (pacchetti e dev, `license` array unito con ` OR `), `lcc_read_flat_manifest <file>` (`Cargo.toml`, `pyproject.toml`, `pom.xml`: estrae solo il campo licenza con `sed`), `lcc_record_key <name> <path>` (toglie il prefisso `node_modules/` o `vendor/`), `lcc_merge_records` (legge i record da stdin; stessa chiave → una sola voce con `source` combinata; licenze diverse → licenza del manifest e `note` = `declared X, text says Y`).

- [x] **Step 1: Write the failing tests**: `package.json string, object and array license forms`; `scoped package @scope/name keeps its name`; `composer.lock reads packages and packages-dev`; `Cargo.toml license field`; `pyproject.toml license field`; `pom.xml license name`; `manifest and LICENSE agreeing give one record`; `manifest and LICENSE disagreeing give one record with a note`; `2000 package.json files are read with at most 5 jq invocations` (shim di `jq` in `PATH` che conta le chiamate).
- [x] **Step 2: Run** `bats tests/bats/manifests.bats`. Expected: FAIL.
- [x] **Step 3: Implement**. I `package.json` si leggono con `find -print0 | xargs -0 jq -r` in un'unica invocazione per lotto, con `input_filename` per il percorso. `lcc_discover` chiama i lettori dei manifest e `lcc_merge_records`.
- [x] **Step 4: Run** i test. Expected: PASS.
- [x] **Step 5: Commit** `feat: read manifests and merge them with license files`.

### Task 7: Licenza del progetto e valutazione

**Files:**
- Modify: `check-licenses`
- Test: `tests/bats/evaluate.bats`

**Interfaces:**
- Consumes: `lcc_patterns_for`, `lcc_is_allowed` (Task 3), record uniti (Task 6), `LCC_ALLOW` (Task 2).
- Produces: `lcc_detect_project_license <root>` (ordine: `--project-license`, config, `license` di `package.json`/`composer.json`, `LICENSE` della radice, `LICENSES/`; exit 1 se assente), `lcc_evaluate` (legge i record da stdin, scrive gli stessi con due campi in più: `status` e `reason`).

- [x] **Step 1: Write the failing tests**: `option beats config beats package.json beats root LICENSE`; `LICENSES directory with a single license is used`; `no detectable project license exits 2 with the documented message`; `allowed license gives ok`; `recognized but not allowed gives forbidden`; `empty or UNKNOWN license gives review`; `note about disagreement gives review even when the license is allowed`; `allow line turns a forbidden dependency into ok`; `project license without a matrix row exits 2`.
- [x] **Step 2: Run** `bats tests/bats/evaluate.bats`. Expected: FAIL.
- [x] **Step 3: Implement** le due funzioni. Una voce `submodule` o `header` senza licenza è `review` con motivo `license not recognized`.
- [x] **Step 4: Run** i test. Expected: PASS.
- [x] **Step 5: Commit** `feat: project license detection and evaluation with exceptions`.

### Task 8: Report e codici di uscita

**Files:**
- Modify: `check-licenses`
- Test: `tests/bats/report.bats`

**Interfaces:**
- Consumes: record valutati (Task 7).
- Produces: `lcc_report_table`, `lcc_report_json` (array JSON di oggetti con `name`, `version`, `path`, `license`, `source`, `note`, `status`, `reason`), `lcc_exit_code` (0/1 secondo `LCC_STRICT`); `main` collega tutti gli stadi.

- [x] **Step 1: Write the failing tests**: `table has columns Name, Version, License, Check, Source`; `colors are off when stdout is not a TTY`; `--json output is valid and parses with jq`; `exit 0 when all ok`; `exit 1 with a forbidden entry`; `review entries exit 0 without --strict and 1 with it`; `project with no dependencies prints "no dependencies found" and exits 0`; `long names are truncated in the table but not in --json`.
- [x] **Step 2: Run** `bats tests/bats/report.bats`. Expected: FAIL.
- [x] **Step 3: Implement** la tabella con `printf` a larghezze fisse (come `print_table` del PHP); colori solo se `[[ -t 1 ]]`.
- [x] **Step 4: Run** i test. Expected: PASS.
- [x] **Step 5: Commit** `feat: table and JSON report with exit codes and --strict`.

### Task 9: Test end-to-end sulle fixture

**Files:**
- Create: `tests/fixtures/e2e/{npm,composer,cargo,cpp-vendors,submodule-no-license,conflict,spdx-expr,spdx-header,project-with-spaces}/`, `tests/bats/e2e.bats`

**Interfaces:**
- Consumes: il comando completo `./check-licenses --path <fixture>`.

- [x] **Step 1: Write the failing tests**, uno per fixture, con codice di uscita e righe attese: `npm project with an MIT dependency exits 0`; `npm project with a proprietary dependency under an MIT project exits 1`; `composer lock with GPL-3.0-only dependency under MIT project is forbidden`; `cargo project reads Cargo.toml`; `C++ project with vendors/ and mixed LICENSE files reports each`; `submodule without license is review`; `manifest/text disagreement is review and fails with --strict`; `AND/OR expressions evaluate`; `SPDX header only project`; `project path with spaces`.
- [x] **Step 2: Run** `bats tests/bats/e2e.bats`. Expected: FAIL solo per le fixture mancanti; creare le fixture, poi rieseguire.
- [x] **Step 3: Fix** i difetti emersi negli stadi precedenti (ognuno con il test che lo riproduce nel file dello stadio).
- [x] **Step 4: Run** `bats tests/bats`. Expected: tutti PASS.
- [x] **Step 5: Commit** `test: end-to-end fixtures for npm, composer, cargo, C++ vendors and edge cases`.

### Task 10: CI, documentazione e rimozione del PHP

**Files:**
- Create: `.github/workflows/tests.yml`
- Modify: `README.md`, `CHANGELOG.md`, `.gitignore`
- Delete: `bin/`, `src/`, `config/`, `composer.json`, `composer.lock`, `phpunit.xml`, `tests/Pest.php`, `tests/bootstrap.php`, `tests/Integration/`, `tests/Unit/`

- [x] **Step 1: Write** il workflow: matrice `ubuntu-latest` e `macos-latest`, su macOS `brew install bash bats-core jq`, su Linux `apt-get install -y bats jq`; esegue `bats tests/bats` e `shellcheck check-licenses`.
- [x] **Step 2: Remove** i file PHP; il vecchio comportamento resta nella 1.x (tag esistenti).
- [x] **Step 3: Rewrite** `README.md`: requisiti (bash 4.4+, `jq`, in evidenza), installazione con `curl`, uso, formato di `.license-compliance` con un esempio per ecosistema, tabella di conversione dal vecchio `license-compliance.php` (`license_families`, `groups`, `compatibility`). `CHANGELOG.md`: voce 2.0.0 con le modifiche incompatibili.
- [x] **Step 4: Run** `bats tests/bats` e `./check-licenses --path .` sul repo stesso. Expected: test PASS; il comando termina con un esito coerente.
- [x] **Step 5: Commit** `feat!: generic bash license checker, remove the PHP implementation`.

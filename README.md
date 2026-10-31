# license-compliance-checker

[![Tests](https://github.com/swolley/license-compliance-checker/actions/workflows/tests.yml/badge.svg)](https://github.com/swolley/license-compliance-checker/actions/workflows/tests.yml)

Check the licenses of a project's dependencies against the project license. One bash script, any ecosystem:
it looks at every license file, SPDX header, submodule and package manifest in the tree, so it works the same on a
C++ project with `vendors/`, an npm or Composer project, a Rust or Python one.

## Requirements

- **bash 4.4 or later** (macOS ships 3.2: `brew install bash`; on Windows use Git Bash)
- **[jq](https://jqlang.github.io/jq/)** (`apt install jq`, `brew install jq`, `pacman -S jq`). The script stops with a clear error if jq is missing.

## Installation

```bash
curl -fsSL https://raw.githubusercontent.com/swolley/license-compliance-checker/master/check-licenses -o check-licenses
chmod +x check-licenses
```

Or copy the file into your project (for example `scripts/check-licenses`). No Composer, npm or PHP needed.

## Usage

```bash
./check-licenses                      # check the current directory
./check-licenses --path ../project    # check another project
./check-licenses --json               # machine-readable report
./check-licenses --strict             # also fail on entries that need manual review
./check-licenses --project-license GPL-3.0-or-later
```

Options: `--path DIR`, `--config FILE`, `--project-license ID`, `--json`, `--strict`, `--version`, `--help`.

Exit codes: `0` no forbidden entry; `1` at least one forbidden entry (with `--strict` also a `review` one); `2` usage error (jq missing, bad config, project license not detectable, unknown project license in the matrix).

### What is checked

| Source | What is read |
|--------|--------------|
| License files | `LICENSE*`, `LICENCE*`, `COPYING*`, `UNLICENSE*` (and `NOTICE*` when nothing else is there) in any directory; the SPDX id is recognized from the text |
| `LICENSES/` (REUSE) | the id comes from the file name (`LICENSES/MIT.txt`) and is attributed to the parent directory |
| SPDX headers | `SPDX-License-Identifier:` in the first 30 lines of any text file, one entry per directory and expression |
| Submodules | every `path` in `.gitmodules`; without a license file the entry is `review` |
| Manifests | `package.json` (also in `node_modules`), `composer.lock`, and `Cargo.toml`, `pyproject.toml`, `pom.xml` below the root |

A directory with both a manifest and a license file is one entry. If the two disagree the declared license is kept and the entry is `review` with a note (`declared X, text says Y`).
The project's own root `package.json`, `Cargo.toml`, `pyproject.toml`, `pom.xml` and `LICENSE` are not dependencies.
By default `.git`, `build`, `dist` and `node_modules/.cache` are skipped, at any depth.

Every entry gets a status: `ok`, `forbidden` (a recognized license that the matrix does not allow) or `review` (license not found or not recognized, disagreeing sources, an expression too complex to evaluate).
A license that is not recognized is never reported as `ok`.

### The project license

In order: `--project-license`, `project-license` in the config, `license` of `package.json` or `composer.json`, the root `LICENSE` file, the root `LICENSES/` directory.
With several licenses in `LICENSES/`, every dependency must be allowed by each of them.

## Configuration

`.license-compliance` in the project root (or `--config FILE`). One directive per line, `#` starts a comment:

```
project-license  GPL-3.0-or-later
exclude          vendors/tests               # skip a path (a bare name matches at any depth)
include          build                       # stop skipping a default exclusion
allow            some-package  LicenseRef-Custom   # accept these licenses for one dependency ("*" = any)
group            permissive    MIT ISC BSD-* Apache-*
matrix           GPL-3.0-or-later  @permissive GPL->=3.0
```

`matrix` maps a project license to the patterns allowed for its dependencies. A pattern is an exact SPDX id (`MIT`), a wildcard (`BSD-*`), a version constraint (`GPL->=3.0`, `Apache-<=1.1`) or a group (`@permissive`, groups can contain groups). SPDX expressions in dependencies are evaluated with `AND` and `OR` (`AND` binds tighter); a single pair of outer parentheses is accepted, nested ones make the entry `review`.
`group` and `matrix` lines replace the built-in entry of the same name or add a new one. The built-in matrix is the one of version 1 (groups `permissive`, `permissive-no-strong-copyleft`, `proprietary-allowed`) plus `Unlicense`; see the top of the script.

### Migrating from 1.x

Version 1 was a PHP package configured by `license-compliance.php`. Translate it like this:

| 1.x (`license-compliance.php`) | 2.x (`.license-compliance`) |
|--------------------------------|-----------------------------|
| `'groups' => ['name' => ['A', 'B-*']]` | `group name A B-*` |
| `'compatibility' => ['MIT' => ['@permissive']]` | `matrix MIT @permissive` |
| `'license_families'` | built in, no directive |

The Composer package is gone: download the script as shown above. The 1.x line keeps working from its tags.

## Examples

```bash
# C++ project with vendored libraries and git submodules
./check-licenses --project-license GPL-3.0-or-later

# Node project in CI: fail on anything that needs a human look
./check-licenses --strict

# Composer project that must stay closed source
./check-licenses --project-license proprietary --json | jq '.[] | select(.status != "ok")'
```

## Development

```bash
bats tests/bats          # test suite (bats-core)
shellcheck -x check-licenses
```

Source: [github.com/swolley/license-compliance-checker](https://github.com/swolley/license-compliance-checker). Design: `docs/superpowers/specs/`, plan: `docs/superpowers/plans/`.

## License

MIT

# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [2.0.0] - 2026-10-31

### Changed

- **Breaking:** rewritten as a single bash script (`check-licenses`, bash 4+ and `jq`); PHP and Composer are no longer needed and the Composer package is removed (1.x stays available from its tags).
- **Breaking:** the config is `.license-compliance` (one directive per line: `project-license`, `exclude`, `include`, `allow`, `group`, `matrix`); `license-compliance.php` is no longer read. See "Migrating from 1.x" in the README.
- The built-in matrix is the 1.x one, plus `Unlicense`.
- npm licenses are read from the `package.json` files in `node_modules` (no more `npx license-checker`).
- The report is a table with a status per entry (`ok`, `forbidden`, `review`) and the reasons; `--json` prints it as JSON.

### Added

- Language-agnostic discovery: license files, `LICENSES/` (REUSE), SPDX headers, `.gitmodules` entries and the manifests `package.json`, `composer.lock`, `Cargo.toml`, `pyproject.toml`, `pom.xml`, anywhere in the tree (default exclusions `.git`, `build`, `dist`, `node_modules/.cache`).
- `review` status for licenses that are not recognized, for manifest/text disagreements and for expressions too complex to evaluate; `--strict` makes it fail.
- `allow` directive for per-dependency exceptions, `--project-license`, `--config`, `--json`, `--strict`.
- License text detection by characteristic phrases (LGPL and AGPL before GPL, BSD-2/3 by the no-endorsement clause, ...).
- SPDX expressions: `AND` binds tighter than `OR`, one pair of outer parentheses is accepted.

## [1.0.0] - 2025-02-27

### Added

- CLI `check-licenses` to verify Composer and npm dependency licenses against the project license.
- Config lookup order: `project/scripts/license-compliance.php`, `project/config/license-compliance.php`, package default config.
- License matrix syntax: exact SPDX ids, wildcards (`BSD-*`), version constraints (`GPL->=3.0`), and `@group` references.
- Project license detection from `composer.json`, `package.json`, or `LICENSE` file (AGPL, GPL, MIT, BSD 2/3/4-Clause, Apache 1.0/1.1/2.0, proprietary, CC0, CC-BY variants).
- Composer dependencies from `composer.lock` (packages and packages-dev).
- npm dependencies via `npx license-checker` when `package.json` and `node_modules` exist.
- Optional project config to allow only compatible dependency licenses per project license.
- Exit codes: 0 (OK), 1 (some dependencies not allowed), 2 (error: invalid path, no config, no project license).
- Test suite (Pest) with 100% code coverage.

[Unreleased]: https://github.com/swolley/license-compliance-checker/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/swolley/license-compliance-checker/releases/tag/v1.0.0

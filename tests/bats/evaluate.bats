setup() {
    load helper
    load_lcc
    lcc_load_defaults
    TEXTS="$LCC_ROOT/tests/fixtures/texts"
    P="$BATS_TEST_TMPDIR/proj"
    mkdir -p "$P"
    LCC_PROJECT_LICENSE_OPT=""
    LCC_PROJECT_LICENSE=""
}

mkrec() { # name version path license source note
    printf '%s%s%s%s%s%s%s%s%s%s%s\n' "$1" "$LCC_FS" "$2" "$LCC_FS" "$3" "$LCC_FS" "$4" "$LCC_FS" "$5" "$LCC_FS" "$6"
}

field() { cut -d "$LCC_FS" -f "$2" <<<"$1"; }

evaluate_one() { # project license, then mkrec args
    local proj="$1"
    shift
    LCC_PROJECT_LICENSE="$proj"
    mkrec "$@" | lcc_evaluate
}

@test "project license: option beats config beats package.json beats root LICENSE" {
    cp "$TEXTS/ISC.txt" "$P/LICENSE"
    run lcc_detect_project_license "$P"
    [ "$output" = "ISC" ]
    printf '{"name":"me","license":"MIT"}\n' >"$P/package.json"
    run lcc_detect_project_license "$P"
    [ "$output" = "MIT" ]
    LCC_PROJECT_LICENSE="Apache-2.0"
    run lcc_detect_project_license "$P"
    [ "$output" = "Apache-2.0" ]
    LCC_PROJECT_LICENSE_OPT="GPL-3.0-only"
    run lcc_detect_project_license "$P"
    [ "$output" = "GPL-3.0-only" ]
}

@test "composer.json license is used when it is a single entry" {
    printf '{"name":"a/b","license":["MIT"]}\n' >"$P/composer.json"
    run lcc_detect_project_license "$P"
    [ "$status" -eq 0 ]
    [ "$output" = "MIT" ]
}

@test "package.json 'SEE LICENSE IN' falls through to the LICENSE file" {
    printf '{"name":"me","license":"SEE LICENSE IN LICENSE"}\n' >"$P/package.json"
    cp "$TEXTS/ISC.txt" "$P/LICENSE"
    run lcc_detect_project_license "$P"
    [ "$output" = "ISC" ]
}

@test "LICENSES directory with a single license is used" {
    mkdir -p "$P/LICENSES"
    cp "$TEXTS/MPL-2.0.txt" "$P/LICENSES/MPL-2.0.txt"
    run lcc_detect_project_license "$P"
    [ "$status" -eq 0 ]
    [ "$output" = "MPL-2.0" ]
}

@test "LICENSES directory with several licenses gives them joined with AND" {
    mkdir -p "$P/LICENSES"
    cp "$TEXTS/MIT.txt" "$P/LICENSES/MIT.txt"
    cp "$TEXTS/ISC.txt" "$P/LICENSES/ISC.txt"
    run lcc_detect_project_license "$P"
    [ "$status" -eq 0 ]
    [ "$output" = "ISC AND MIT" ]
}

@test "with several project licenses a dependency must be allowed by all of them" {
    run evaluate_one "MIT AND UNLICENSED" dep 1.0 dep GPL-3.0-only manifest ""
    [ "$(field "$output" 7)" = "forbidden" ]
    run evaluate_one "MIT AND UNLICENSED" dep 1.0 dep ISC manifest ""
    [ "$(field "$output" 7)" = "ok" ]
}

@test "a project license of a multi-license set without a matrix row exits 2" {
    run evaluate_one "MIT AND Nonexistent-1.0" dep 1.0 dep ISC manifest ""
    [ "$status" -eq 2 ]
    [[ "$output" == *"Nonexistent-1.0"* ]]
}

@test "no detectable project license exits 2 with the documented message" {
    run lcc_resolve_project_license "$P"
    [ "$status" -eq 2 ]
    [[ "$output" == *"Could not detect the project license"* ]]
    [[ "$output" == *"--project-license"* ]]
}

@test "project license without a matrix row exits 2" {
    run evaluate_one Nonexistent-1.0 dep 1.0 dep MIT file ""
    [ "$status" -eq 2 ]
    [[ "$output" == *"Nonexistent-1.0"* ]]
}

@test "allowed license gives ok" {
    run evaluate_one MIT dep 1.0 dep ISC manifest ""
    [ "$(field "$output" 7)" = "ok" ]
}

@test "recognized but not allowed gives forbidden" {
    run evaluate_one proprietary dep 1.0 dep GPL-3.0-only manifest ""
    [ "$(field "$output" 7)" = "forbidden" ]
    [[ "$(field "$output" 8)" == *"GPL-3.0-only"* ]]
}

@test "not allowed and not a known license gives review" {
    run evaluate_one proprietary dep 1.0 dep LicenseRef-Mine manifest ""
    [ "$(field "$output" 7)" = "review" ]
}

@test "empty or UNKNOWN license gives review" {
    run evaluate_one MIT a "" a "" file ""
    [ "$(field "$output" 7)" = "review" ]
    run evaluate_one MIT a "" a UNKNOWN manifest ""
    [ "$(field "$output" 7)" = "review" ]
}

@test "a note gives review even when the license is allowed" {
    run evaluate_one MIT dep 1.0 dep MIT manifest+file "declared MIT, text says ISC"
    [ "$(field "$output" 7)" = "review" ]
    [[ "$(field "$output" 8)" == *"text says ISC"* ]]
}

@test "undecidable parentheses give review" {
    run evaluate_one MIT dep 1.0 dep "(MIT OR Foo) AND ISC" manifest ""
    [ "$(field "$output" 7)" = "review" ]
}

@test "allow line turns a forbidden dependency into ok" {
    LCC_ALLOW[dep]="GPL-3.0-only"
    run evaluate_one proprietary dep 1.0 dep GPL-3.0-only manifest ""
    [ "$(field "$output" 7)" = "ok" ]
    [[ "$(field "$output" 8)" == *"config"* ]]
}

@test "allow line only covers the listed licenses" {
    LCC_ALLOW[dep]="ISC"
    run evaluate_one proprietary dep 1.0 dep GPL-3.0-only manifest ""
    [ "$(field "$output" 7)" = "forbidden" ]
}

@test "allow line with * covers any license, including an unknown one" {
    LCC_ALLOW[vendors/x]="*"
    run evaluate_one proprietary vendors/x "" vendors/x "" submodule "no license file found"
    [ "$(field "$output" 7)" = "ok" ]
}

@test "evaluated records keep the six input fields" {
    run evaluate_one MIT dep 1.0 dep/LICENSE MIT file ""
    [ "$(field "$output" 1)" = "dep" ]
    [ "$(field "$output" 2)" = "1.0" ]
    [ "$(field "$output" 3)" = "dep/LICENSE" ]
    [ "$(field "$output" 4)" = "MIT" ]
    [ "$(field "$output" 5)" = "file" ]
}

@test "a license token that looks like a glob is not expanded against the working directory" {
    mkdir "$BATS_TEST_TMPDIR/cwd"
    cd "$BATS_TEST_TMPDIR/cwd"
    touch MIT
    run evaluate_one proprietary dep 1.0 dep "*" manifest ""
    [ "$(field "$output" 7)" = "review" ]
}

@test "README in the root LICENSES directory does not become part of the project license" {
    mkdir -p "$P/LICENSES"
    cp "$TEXTS/MIT.txt" "$P/LICENSES/MIT.txt"
    printf 'This folder holds the licenses.\n' >"$P/LICENSES/README.md"
    run lcc_detect_project_license "$P"
    [ "$output" = "MIT" ]
}

@test "under a GPL-3.0 or AGPL-3.0 project a GPL-2.0-only dependency is forbidden" {
    local proj
    for proj in GPL-3.0-only GPL-3.0-or-later AGPL-3.0-or-later; do
        run evaluate_one "$proj" dep 1.0 dep GPL-2.0-only file ""
        [ "$(field "$output" 7)" = "forbidden" ] || { echo "$proj accepted GPL-2.0-only"; false; }
    done
}

@test "under a GPL-3.0 project GPL-2.0-or-later, GPL-3.0, AGPL-3.0, LGPL, MPL and permissive licenses are ok" {
    local lic
    for lic in GPL-2.0-or-later GPL-3.0-only GPL-3.0-or-later AGPL-3.0-or-later LGPL-2.1-only LGPL-3.0-only MPL-2.0 MIT Apache-2.0 BSD-3-Clause ISC Zlib Unlicense; do
        run evaluate_one GPL-3.0-or-later dep 1.0 dep "$lic" file ""
        [ "$(field "$output" 7)" = "ok" ] || { echo "$lic not ok under GPL-3.0-or-later"; false; }
    done
}

@test "a license the matrix does not know, such as OFL-1.1, needs review and is not forbidden" {
    run evaluate_one GPL-3.0-or-later dep 1.0 dep OFL-1.1 file ""
    [ "$(field "$output" 7)" = "review" ]
}

@test "several license files in a directory are only informational when every license is allowed" {
    run evaluate_one GPL-3.0-or-later dep 1.0 dep "Apache-2.0 AND MPL-2.0" file "multiple license files"
    [ "$(field "$output" 7)" = "ok" ]
    [[ "$(field "$output" 8)" == *"multiple license files"* ]]
}

@test "several license files with one forbidden license are forbidden" {
    run evaluate_one proprietary dep 1.0 dep "MIT AND GPL-3.0-only" file "multiple license files"
    [ "$(field "$output" 7)" = "forbidden" ]
}

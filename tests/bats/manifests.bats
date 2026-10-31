setup() {
    load helper
    load_lcc
    lcc_load_defaults
    TEXTS="$LCC_ROOT/tests/fixtures/texts"
    P="$BATS_TEST_TMPDIR/proj"
    mkdir -p "$P"
}

rec() { cut -d "$LCC_FS" -f "$2" <<<"$1"; }

pkg() { # dir, json
    mkdir -p "$P/$1"
    printf '%s\n' "$2" >"$P/$1/package.json"
}

@test "package.json license as string, object and array" {
    pkg a '{"name":"a","version":"1.0.0","license":"MIT"}'
    pkg b '{"name":"b","version":"2.0.0","license":{"type":"ISC","url":"x"}}'
    pkg c '{"name":"c","version":"3.0.0","licenses":[{"type":"MIT"},{"type":"Apache-2.0"}]}'
    cd "$P"
    run lcc_read_package_json a/package.json b/package.json c/package.json
    [ "$status" -eq 0 ]
    [ "$(sed -n 1p <<<"$output")" = "a${LCC_FS}1.0.0${LCC_FS}a/package.json${LCC_FS}MIT${LCC_FS}manifest${LCC_FS}" ]
    [ "$(rec "$(sed -n 2p <<<"$output")" 4)" = "ISC" ]
    [ "$(rec "$(sed -n 3p <<<"$output")" 4)" = "MIT OR Apache-2.0" ]
}

@test "package.json parenthesized expression loses the outer parentheses" {
    pkg a '{"name":"a","version":"1.0.0","license":"(MIT OR Apache-2.0)"}'
    cd "$P"
    run lcc_read_package_json a/package.json
    [ "$(rec "$output" 4)" = "MIT OR Apache-2.0" ]
}

@test "scoped package @scope/name keeps its name" {
    pkg node_modules/@scope/name '{"name":"@scope/name","version":"1.2.3","license":"MIT"}'
    cd "$P"
    run lcc_read_package_json node_modules/@scope/name/package.json
    [ "$(rec "$output" 1)" = "@scope/name" ]
}

@test "an invalid package.json is skipped and the others are still read" {
    pkg bad '{ not json'
    pkg good '{"name":"good","version":"1.0.0","license":"MIT"}'
    cd "$P"
    run lcc_read_package_json bad/package.json good/package.json
    [[ "$output" == *"good${LCC_FS}1.0.0"* ]]
}

@test "composer.lock reads packages and packages-dev" {
    cat >"$P/composer.lock" <<'JSON'
{"packages":[{"name":"vendor/one","version":"v1.0.0","license":["MIT"]}],
 "packages-dev":[{"name":"vendor/two","version":"2.0.0","license":["MIT","GPL-3.0-or-later"]}]}
JSON
    cd "$P"
    run lcc_read_composer_lock composer.lock
    [ "$status" -eq 0 ]
    [ "$(wc -l <<<"$output")" -eq 2 ]
    [ "$(rec "$(sed -n 1p <<<"$output")" 1)" = "vendor/one" ]
    [ "$(rec "$(sed -n 2p <<<"$output")" 4)" = "MIT OR GPL-3.0-or-later" ]
}

@test "Cargo.toml license field" {
    mkdir -p "$P/crates/foo"
    printf '[package]\nname = "foo"\nversion = "0.3.1"\nlicense = "MIT OR Apache-2.0"\n' >"$P/crates/foo/Cargo.toml"
    cd "$P"
    run lcc_read_flat_manifest crates/foo/Cargo.toml
    [ "$(rec "$output" 1)" = "foo" ]
    [ "$(rec "$output" 2)" = "0.3.1" ]
    [ "$(rec "$output" 4)" = "MIT OR Apache-2.0" ]
    [ "$(rec "$output" 5)" = "manifest" ]
}

@test "pyproject.toml license field, plain and table form" {
    mkdir -p "$P/py1" "$P/py2"
    printf '[project]\nname = "p1"\nversion = "1.0"\nlicense = "BSD-3-Clause"\n' >"$P/py1/pyproject.toml"
    printf '[project]\nname = "p2"\nversion = "2.0"\nlicense = { text = "MIT" }\n' >"$P/py2/pyproject.toml"
    cd "$P"
    run lcc_read_flat_manifest py1/pyproject.toml
    [ "$(rec "$output" 4)" = "BSD-3-Clause" ]
    run lcc_read_flat_manifest py2/pyproject.toml
    [ "$(rec "$output" 4)" = "MIT" ]
}

@test "pom.xml license name is mapped to an SPDX id when known" {
    mkdir -p "$P/jar"
    printf '<project>\n <licenses>\n  <license>\n   <name>The Apache Software License, Version 2.0</name>\n  </license>\n </licenses>\n</project>\n' >"$P/jar/pom.xml"
    cd "$P"
    run lcc_read_flat_manifest jar/pom.xml
    [ "$(rec "$output" 4)" = "Apache-2.0" ]
}

@test "manifest and LICENSE agreeing give one record" {
    pkg node_modules/dep '{"name":"dep","version":"1.0.0","license":"MIT"}'
    cp "$TEXTS/MIT.txt" "$P/node_modules/dep/LICENSE"
    run lcc_discover "$P"
    [ "$(wc -l <<<"$output")" -eq 1 ]
    [ "$(rec "$output" 1)" = "dep" ]
    [ "$(rec "$output" 2)" = "1.0.0" ]
    [ "$(rec "$output" 4)" = "MIT" ]
    [ "$(rec "$output" 5)" = "manifest+file" ]
    [ "$(rec "$output" 6)" = "" ]
}

@test "manifest and LICENSE disagreeing give one record with a note" {
    pkg node_modules/dep '{"name":"dep","version":"1.0.0","license":"MIT"}'
    cp "$TEXTS/ISC.txt" "$P/node_modules/dep/LICENSE"
    run lcc_discover "$P"
    [ "$(wc -l <<<"$output")" -eq 1 ]
    [ "$(rec "$output" 4)" = "MIT" ]
    [[ "$(rec "$output" 6)" == *"declared MIT"* ]]
    [[ "$(rec "$output" 6)" == *"text says ISC"* ]]
}

@test "the root package.json is the project itself and gives no record" {
    printf '{"name":"me","version":"1.0.0","license":"MIT"}\n' >"$P/package.json"
    run lcc_discover "$P"
    [ -z "$output" ]
}

@test "composer.lock packages merge with their vendor directory" {
    printf '{"packages":[{"name":"acme/lib","version":"1.0.0","license":["MIT"]}]}\n' >"$P/composer.lock"
    mkdir -p "$P/vendor/acme/lib"
    cp "$TEXTS/MIT.txt" "$P/vendor/acme/lib/LICENSE"
    run lcc_discover "$P"
    [ "$(wc -l <<<"$output")" -eq 1 ]
    [ "$(rec "$output" 1)" = "acme/lib" ]
    [ "$(rec "$output" 5)" = "manifest+file" ]
}

@test "2000 package.json files are read with at most 5 jq invocations" {
    mkdir -p "$BATS_TEST_TMPDIR/bin"
    count="$BATS_TEST_TMPDIR/jq-count"
    : >"$count"
    real_jq="$(command -v jq)"
    printf '#!/bin/bash\necho x >>"%s"\nexec "%s" "$@"\n' "$count" "$real_jq" >"$BATS_TEST_TMPDIR/bin/jq"
    chmod +x "$BATS_TEST_TMPDIR/bin/jq"
    for i in $(seq 1 2000); do
        mkdir -p "$P/node_modules/pkg$i"
        printf '{"name":"pkg%s","version":"1.0.0","license":"MIT"}\n' "$i" >"$P/node_modules/pkg$i/package.json"
    done
    PATH="$BATS_TEST_TMPDIR/bin:$PATH" run lcc_discover "$P"
    [ "$status" -eq 0 ]
    [ "$(wc -l <<<"$output")" -eq 2000 ]
    [ "$(wc -l <"$count")" -le 5 ]
}

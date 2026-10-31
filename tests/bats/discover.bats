setup() {
    load helper
    load_lcc
    lcc_load_defaults
    TEXTS="$LCC_ROOT/tests/fixtures/texts"
    P="$BATS_TEST_TMPDIR/proj"
    mkdir -p "$P"
}

put_license() { # dir, id [, file name]
    mkdir -p "$P/$1"
    cp "$TEXTS/$2.txt" "$P/$1/${3:-LICENSE}"
}

# field N (1-based) of a record line
rec() { cut -d "$LCC_FS" -f "$2" <<<"$1"; }

@test "finds LICENSE in a nested vendors directory and names the record after the directory" {
    put_license . GPL-3.0-only
    put_license vendors/foo MIT
    run lcc_discover "$P"
    [ "$status" -eq 0 ]
    [ "$(wc -l <<<"$output")" -eq 1 ]
    [ "$(rec "$output" 1)" = "vendors/foo" ]
    [ "$(rec "$output" 2)" = "" ]
    [ "$(rec "$output" 3)" = "vendors/foo/LICENSE" ]
    [ "$(rec "$output" 4)" = "MIT" ]
    [ "$(rec "$output" 5)" = "file" ]
    [ "$(rec "$output" 6)" = "" ]
}

@test "the root LICENSE is the project license and gives no record" {
    put_license . MIT
    run lcc_discover "$P"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "skips .git, build and dist by default, at any depth" {
    put_license .git/x MIT
    put_license build/x MIT
    put_license dist/x MIT
    put_license vendors/lib/build/y MIT
    run lcc_discover "$P"
    [ -z "$output" ]
}

@test "include removes a default exclusion" {
    put_license build/x MIT
    LCC_INCLUDE=(build)
    run lcc_discover "$P"
    [ "$(rec "$output" 1)" = "build/x" ]
}

@test "exclude adds a path" {
    put_license vendors/tests MIT
    put_license vendors/real MIT
    LCC_EXCLUDE+=(vendors/tests)
    run lcc_discover "$P"
    [ "$(wc -l <<<"$output")" -eq 1 ]
    [ "$(rec "$output" 1)" = "vendors/real" ]
}

@test "header records are one per directory and license" {
    mkdir -p "$P/src"
    printf '// SPDX-License-Identifier: MIT\n' >"$P/src/a.c"
    printf '// SPDX-License-Identifier: MIT\n' >"$P/src/b.c"
    printf '// SPDX-License-Identifier: Apache-2.0\n' >"$P/src/c.c"
    printf '// SPDX-License-Identifier: MIT\n' >"$P/top.c"
    run lcc_discover "$P"
    [ "$(wc -l <<<"$output")" -eq 2 ]
    [[ "$output" == *"src${LCC_FS}${LCC_FS}src/a.c${LCC_FS}MIT${LCC_FS}header"* ]]
    [[ "$output" == *"${LCC_FS}Apache-2.0${LCC_FS}header"* ]]
}

@test "submodule from .gitmodules without checkout is a record with empty license and source submodule" {
    printf '[submodule "vendors/x"]\n\tpath = vendors/x\n\turl = https://example.com/x.git\n' >"$P/.gitmodules"
    run lcc_discover "$P"
    [ "$(wc -l <<<"$output")" -eq 1 ]
    [ "$(rec "$output" 1)" = "vendors/x" ]
    [ "$(rec "$output" 4)" = "" ]
    [ "$(rec "$output" 5)" = "submodule" ]
    [ -n "$(rec "$output" 6)" ]
}

@test "submodule with checkout takes the license from its LICENSE file" {
    printf '[submodule "vendors/x"]\n\tpath = vendors/x\n\turl = https://example.com/x.git\n' >"$P/.gitmodules"
    put_license vendors/x BSD-3-Clause
    run lcc_discover "$P"
    [ "$(wc -l <<<"$output")" -eq 1 ]
    [ "$(rec "$output" 4)" = "BSD-3-Clause" ]
    [ "$(rec "$output" 5)" = "submodule" ]
}

@test "directory names with spaces and a tab stay in one field" {
    put_license "The Stripper.vst3" MIT
    put_license $'a\tb' ISC
    run lcc_discover "$P"
    [ "$(wc -l <<<"$output")" -eq 2 ]
    [[ "$output" == *"The Stripper.vst3${LCC_FS}"* ]]
    [[ "$output" == *"a b${LCC_FS}"* ]]
}

@test "symlink to an ancestor directory does not loop and is not followed" {
    put_license sub MIT
    ln -s .. "$P/sub/loop"
    mkdir -p "$BATS_TEST_TMPDIR/elsewhere"
    cp "$TEXTS/ISC.txt" "$BATS_TEST_TMPDIR/elsewhere/LICENSE"
    ln -s "$BATS_TEST_TMPDIR/elsewhere" "$P/linked"
    start=$SECONDS
    run lcc_discover "$P"
    [ $((SECONDS - start)) -lt 5 ]
    [ "$(wc -l <<<"$output")" -eq 1 ]
    [ "$(rec "$output" 1)" = "sub" ]
}

@test "multiple license files in one directory are combined with AND and noted" {
    put_license dep MIT LICENSE-MIT
    put_license dep Apache-2.0 LICENSE-APACHE
    run lcc_discover "$P"
    [ "$(wc -l <<<"$output")" -eq 1 ]
    [ "$(rec "$output" 4)" = "Apache-2.0 AND MIT" ]
    [ "$(rec "$output" 6)" = "multiple license files" ]
}

@test "two files with the same license give one id and no note" {
    put_license dep MIT LICENSE
    put_license dep MIT COPYING
    run lcc_discover "$P"
    [ "$(rec "$output" 4)" = "MIT" ]
    [ "$(rec "$output" 6)" = "" ]
}

@test "NOTICE alone is a record with unknown license, next to LICENSE it is ignored" {
    mkdir -p "$P/a" "$P/b"
    echo "Some notice" >"$P/a/NOTICE"
    put_license b MIT
    echo "Some notice" >"$P/b/NOTICE"
    run lcc_discover "$P"
    [ "$(wc -l <<<"$output")" -eq 2 ]
    [[ "$output" == *"a${LCC_FS}${LCC_FS}a/NOTICE${LCC_FS}${LCC_FS}file"* ]]
    [[ "$output" == *"b${LCC_FS}${LCC_FS}b/LICENSE${LCC_FS}MIT${LCC_FS}file${LCC_FS}"* ]]
}

@test "files named like source code are not license files" {
    mkdir -p "$P/node_modules/license-checker"
    echo "x" >"$P/node_modules/license-checker/license-checker.js"
    echo "x" >"$P/node_modules/license-checker/licenses.json"
    run lcc_discover "$P"
    [ -z "$output" ]
}

@test "a LICENSES directory attributes REUSE files to its parent from the file name" {
    put_license . MIT
    mkdir -p "$P/LICENSES" "$P/vendors/x/LICENSES"
    cp "$TEXTS/MIT.txt" "$P/LICENSES/MIT.txt"
    cp "$TEXTS/ISC.txt" "$P/vendors/x/LICENSES/ISC.txt"
    run lcc_discover "$P"
    [ "$(wc -l <<<"$output")" -eq 1 ]
    [ "$(rec "$output" 1)" = "vendors/x" ]
    [ "$(rec "$output" 4)" = "ISC" ]
}

@test "a README note next to the license files is not a license file" {
    put_license dep MPL-2.0 COPYING.MPL2
    printf 'Primarily MPL2 licensed. See COPYING.MPL2.\n' >"$P/dep/COPYING.README"
    run lcc_discover "$P"
    [ "$(wc -l <<<"$output")" -eq 1 ]
    [ "$(rec "$output" 4)" = "MPL-2.0" ]
    [ "$(rec "$output" 6)" = "" ]
}

setup() {
    load helper
    load_lcc
    TEXTS="$LCC_ROOT/tests/fixtures/texts"
}

assert_detects() { # expected id, fixture file
    run lcc_detect_text "$TEXTS/$2"
    [ "$status" -eq 0 ]
    [ "$output" = "$1" ]
}

@test "detects MIT" { assert_detects MIT MIT.txt; }
@test "detects ISC" { assert_detects ISC ISC.txt; }
@test "detects 0BSD" { assert_detects 0BSD 0BSD.txt; }
@test "detects Apache-2.0" { assert_detects Apache-2.0 Apache-2.0.txt; }
@test "detects BSD-2-Clause" { assert_detects BSD-2-Clause BSD-2-Clause.txt; }
@test "detects BSD-3-Clause by the no-endorsement clause" { assert_detects BSD-3-Clause BSD-3-Clause.txt; }
@test "detects MPL-2.0" { assert_detects MPL-2.0 MPL-2.0.txt; }
@test "detects Unlicense" { assert_detects Unlicense Unlicense.txt; }
@test "detects CC0-1.0" { assert_detects CC0-1.0 CC0-1.0.txt; }
@test "detects LGPL-2.1-only" { assert_detects LGPL-2.1-only LGPL-2.1-only.txt; }
@test "detects LGPL-3.0-only and not GPL even though it quotes the GPL" { assert_detects LGPL-3.0-only LGPL-3.0-only.txt; }
@test "detects AGPL-3.0-only" { assert_detects AGPL-3.0-only AGPL-3.0-only.txt; }
@test "detects GPL-2.0-only" { assert_detects GPL-2.0-only GPL-2.0-only.txt; }
@test "detects GPL-3.0-only" { assert_detects GPL-3.0-only GPL-3.0-only.txt; }
@test "GPL text with 'any later version' yields -or-later" { assert_detects GPL-3.0-or-later GPL-3.0-or-later.txt; }

@test "unrecognized text is unknown and prints nothing" {
    printf 'All rights reserved. Do not copy.\n' >"$BATS_TEST_TMPDIR/LICENSE"
    run lcc_detect_text "$BATS_TEST_TMPDIR/LICENSE"
    [ "$status" -eq 1 ]
    [ -z "$output" ]
}

@test "empty file is unknown" {
    : >"$BATS_TEST_TMPDIR/LICENSE"
    run lcc_detect_text "$BATS_TEST_TMPDIR/LICENSE"
    [ "$status" -eq 1 ]
    [ -z "$output" ]
}

@test "binary file is unknown and returns quickly" {
    head -c 200000 /dev/urandom >"$BATS_TEST_TMPDIR/LICENSE"
    start=$SECONDS
    run lcc_detect_text "$BATS_TEST_TMPDIR/LICENSE"
    [ "$status" -eq 1 ]
    [ $((SECONDS - start)) -lt 5 ]
}

@test "file of 50 MB is read only in its head" {
    { cat "$TEXTS/MIT.txt"; head -c 52428800 /dev/zero | tr '\0' 'a'; } >"$BATS_TEST_TMPDIR/LICENSE"
    start=$SECONDS
    run lcc_detect_text "$BATS_TEST_TMPDIR/LICENSE"
    [ $((SECONDS - start)) -lt 5 ]
    [ "$status" -eq 0 ]
    [ "$output" = "MIT" ]
}

@test "LICENSES/MIT.txt gives MIT from the file name" {
    run lcc_license_from_filename "/p/LICENSES/MIT.txt"
    [ "$status" -eq 0 ]
    [ "$output" = "MIT" ]
    run lcc_license_from_filename "/p/LICENSES/LicenseRef-Mine.txt"
    [ "$output" = "LicenseRef-Mine" ]
}

@test "file name outside a LICENSES directory gives nothing" {
    run lcc_license_from_filename "/p/docs/MIT.txt"
    [ "$status" -eq 1 ]
}

@test "SPDX header expression is returned as is" {
    printf '// SPDX-License-Identifier: MIT OR Apache-2.0\nint main(){}\n' >"$BATS_TEST_TMPDIR/a.c"
    run lcc_detect_spdx_header "$BATS_TEST_TMPDIR/a.c"
    [ "$status" -eq 0 ]
    [ "$output" = "MIT OR Apache-2.0" ]
}

@test "SPDX header inside a block comment loses the closing marker" {
    printf '/* SPDX-License-Identifier: GPL-3.0-or-later */\n' >"$BATS_TEST_TMPDIR/a.c"
    run lcc_detect_spdx_header "$BATS_TEST_TMPDIR/a.c"
    [ "$output" = "GPL-3.0-or-later" ]
}

@test "SPDX header after line 30 is ignored" {
    { seq 1 30; echo '# SPDX-License-Identifier: MIT'; } >"$BATS_TEST_TMPDIR/a.sh"
    run lcc_detect_spdx_header "$BATS_TEST_TMPDIR/a.sh"
    [ "$status" -eq 1 ]
}

@test "MPL-2.0 text that names the GNU licenses as secondary licenses is still MPL-2.0" {
    assert_detects MPL-2.0 MPL-2.0-secondary.txt
}

@test "a text that only mentions the GPL far from its start is not a GPL text" {
    { printf 'Custom license of Acme Corp. All rights reserved.\n\n'; printf 'Some terms apply here.\n%.0s' $(seq 1 40); printf 'This work may also be used under the GNU General Public License version 3.\n'; } >"$BATS_TEST_TMPDIR/LICENSE"
    run lcc_detect_text "$BATS_TEST_TMPDIR/LICENSE"
    [ "$status" -eq 1 ]
}

@test "the SPDX tag quoted in prose is not a header" {
    printf 'The `SPDX-License-Identifier:` tag in the first 30 lines of each file is read.\n' >"$BATS_TEST_TMPDIR/doc.md"
    run lcc_detect_spdx_header "$BATS_TEST_TMPDIR/doc.md"
    [ "$status" -eq 1 ]
    printf '# SPDX-License-Identifier: in the first lines of the file\n' >"$BATS_TEST_TMPDIR/doc2.md"
    run lcc_detect_spdx_header "$BATS_TEST_TMPDIR/doc2.md"
    [ "$status" -eq 1 ]
}

@test "SPDX header with WITH exception and parentheses is accepted" {
    printf '// SPDX-License-Identifier: (GPL-2.0-only WITH Classpath-exception-2.0 OR MIT)\n' >"$BATS_TEST_TMPDIR/a.java"
    run lcc_detect_spdx_header "$BATS_TEST_TMPDIR/a.java"
    [ "$status" -eq 0 ]
    [ "$output" = "(GPL-2.0-only WITH Classpath-exception-2.0 OR MIT)" ]
}

@test "full license texts keep their id" {
    local id
    for id in GPL-2.0-only GPL-3.0-only LGPL-2.1-only LGPL-3.0-only AGPL-3.0-only MPL-2.0 Apache-2.0; do
        run lcc_detect_text "$TEXTS/full/$id.txt"
        [ "$status" -eq 0 ]
        [ "$output" = "$id" ] || { echo "$id detected as $output"; false; }
    done
}

@test "README in a LICENSES directory is not a license id" {
    run lcc_license_from_filename "/p/LICENSES/README.md"
    [ "$status" -eq 1 ]
    run lcc_license_from_filename "/p/LICENSES/readme.txt"
    [ "$status" -eq 1 ]
}

@test "detects BSD-4-Clause by the advertising clause even though it has the no-endorsement clause too" {
    assert_detects BSD-4-Clause BSD-4-Clause.txt
}

@test "look-alike licenses are not read as MIT or BSD" {
    local id
    for id in BSL-1.0 PHP-3.01 ZPL-2.1; do
        run lcc_detect_text "$TEXTS/full/$id.txt"
        [ "$status" -eq 0 ]
        [ "$output" = "$id" ] || { echo "$id detected as $output"; false; }
    done
}

@test "zlib license is recognized" {
    run lcc_detect_text "$TEXTS/full/Zlib.txt"
    [ "$status" -eq 0 ]
    [ "$output" = "Zlib" ]
}

@test "SIL OFL 1.1 is recognized and not read as MIT" {
    run lcc_detect_text "$TEXTS/full/OFL-1.1.txt"
    [ "$status" -eq 0 ]
    [ "$output" = "OFL-1.1" ]
}

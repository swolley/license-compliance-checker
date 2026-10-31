setup() {
    load helper
    load_lcc
    lcc_load_defaults
    TEXTS="$LCC_ROOT/tests/fixtures/texts"
    P="$BATS_TEST_TMPDIR/proj"
    mkdir -p "$P"
    LCC_STRICT=0
}

erec() { # name version path license source note status reason
    printf '%s%s%s%s%s%s%s%s%s%s%s%s%s%s%s\n' "$1" "$LCC_FS" "$2" "$LCC_FS" "$3" "$LCC_FS" "$4" "$LCC_FS" "$5" "$LCC_FS" "$6" "$LCC_FS" "$7" "$LCC_FS" "$8"
}

sample() {
    erec dep-a 1.0.0 dep-a/LICENSE MIT file "" ok "allowed for MIT"
    erec dep-b 2.0.0 dep-b/LICENSE GPL-3.0-only manifest "" forbidden "GPL-3.0-only is not allowed"
    erec dep-c "" dep-c LicenseRef-X submodule "" review "unrecognized license: LicenseRef-X"
}

@test "table has columns Name, Version, License, Check, Source" {
    run lcc_report_table < <(sample)
    [ "$status" -eq 0 ]
    header="$(sed -n 1p <<<"$output")"
    for col in Name Version License Check Source; do
        [[ "$header" == *"$col"* ]]
    done
    [[ "$output" == *"dep-a"*"MIT"* ]]
}

@test "table lists the reason of every entry that is not ok and a summary" {
    run lcc_report_table < <(sample)
    [[ "$output" == *"forbidden"*"dep-b"*"GPL-3.0-only is not allowed"* ]]
    [[ "$output" == *"review"*"dep-c"* ]]
    [[ "$output" == *"3 dependencies: 1 ok, 1 forbidden, 1 review"* ]]
}

@test "colors are off when stdout is not a TTY" {
    run lcc_report_table < <(sample)
    [[ "$output" != *$'\e'* ]]
}

@test "--json output is valid and parses with jq" {
    run lcc_report_json < <(sample)
    [ "$status" -eq 0 ]
    [ "$(jq 'length' <<<"$output")" -eq 3 ]
    [ "$(jq -r '.[1].status' <<<"$output")" = "forbidden" ]
    [ "$(jq -r '.[1] | keys | join(",")' <<<"$output")" = "license,name,note,path,reason,source,status,version" ]
}

@test "long names are truncated in the table but not in --json" {
    long="$(printf 'n%.0s' $(seq 1 80))"
    rec="$(erec "$long" 1 p MIT file "" ok r)"
    run lcc_report_table <<<"$rec"
    [[ "$output" != *"$long"* ]]
    run lcc_report_json <<<"$rec"
    [ "$(jq -r '.[0].name' <<<"$output")" = "$long" ]
}

@test "exit 0 when all ok" {
    run lcc_exit_code < <(erec a 1 p MIT file "" ok r)
    [ "$status" -eq 0 ]
}

@test "exit 1 with a forbidden entry" {
    run lcc_exit_code < <(sample)
    [ "$status" -eq 1 ]
}

@test "review entries exit 0 without --strict and 1 with it" {
    run lcc_exit_code < <(erec a 1 p "" file "" review r)
    [ "$status" -eq 0 ]
    LCC_STRICT=1
    run lcc_exit_code < <(erec a 1 p "" file "" review r)
    [ "$status" -eq 1 ]
}

@test "project with no dependencies prints a message and exits 0" {
    run "$LCC_ROOT/check-licenses" --path "$P" --project-license MIT
    [ "$status" -eq 0 ]
    [[ "$output" == *"no dependencies found"* ]]
}

@test "project with no dependencies gives an empty JSON array with --json" {
    run "$LCC_ROOT/check-licenses" --path "$P" --project-license MIT --json
    [ "$status" -eq 0 ]
    [ "$output" = "[]" ]
}

@test "full run: allowed dependency exits 0 and is listed" {
    cp "$TEXTS/MIT.txt" "$P/LICENSE"
    mkdir -p "$P/node_modules/dep"
    printf '{"name":"dep","version":"1.0.0","license":"ISC"}\n' >"$P/node_modules/dep/package.json"
    run "$LCC_ROOT/check-licenses" --path "$P"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Project license: MIT"* ]]
    [[ "$output" == *"dep"*"ISC"* ]]
}

@test "full run: forbidden dependency exits 1" {
    mkdir -p "$P/node_modules/dep"
    printf '{"name":"dep","version":"1.0.0","license":"GPL-3.0-only"}\n' >"$P/node_modules/dep/package.json"
    run "$LCC_ROOT/check-licenses" --path "$P" --project-license proprietary
    [ "$status" -eq 1 ]
}

@test "full run: --config is read and a missing --config exits 2" {
    printf 'project-license proprietary\nallow dep GPL-3.0-only\n' >"$BATS_TEST_TMPDIR/cfg"
    mkdir -p "$P/node_modules/dep"
    printf '{"name":"dep","version":"1.0.0","license":"GPL-3.0-only"}\n' >"$P/node_modules/dep/package.json"
    run "$LCC_ROOT/check-licenses" --path "$P" --config "$BATS_TEST_TMPDIR/cfg"
    [ "$status" -eq 0 ]
    run "$LCC_ROOT/check-licenses" --path "$P" --config "$BATS_TEST_TMPDIR/missing"
    [ "$status" -eq 2 ]
}

@test "full run: .license-compliance in the project root is picked up" {
    printf 'project-license proprietary\n' >"$P/.license-compliance"
    mkdir -p "$P/node_modules/dep"
    printf '{"name":"dep","version":"1.0.0","license":"GPL-3.0-only"}\n' >"$P/node_modules/dep/package.json"
    run "$LCC_ROOT/check-licenses" --path "$P"
    [ "$status" -eq 1 ]
}

@test "full run: undetectable project license exits 2" {
    run "$LCC_ROOT/check-licenses" --path "$P"
    [ "$status" -eq 2 ]
}

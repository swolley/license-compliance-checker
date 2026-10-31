setup() {
    load helper
    load fixtures
    P="$BATS_TEST_TMPDIR/project with spaces"
}

# run the CLI in JSON mode on a fixture
cli_json() { run "$LCC_ROOT/check-licenses" --path "$P" --json "$@"; }

status_of() { jq -r --arg n "$1" '.[] | select(.name == $n) | .status' <<<"$output"; }

@test "npm project with ISC and MIT dependencies exits 0" {
    fx_npm "$P"
    cli_json
    [ "$status" -eq 0 ]
    [ "$(jq length <<<"$output")" -eq 2 ]
    [ "$(status_of ok-dep)" = "ok" ]
    [ "$(status_of @s/scoped)" = "ok" ]
}

@test "npm project: a GPL dependency under an UNLICENSED project is forbidden" {
    fx_npm_forbidden "$P"
    cli_json
    [ "$status" -eq 1 ]
    [ "$(status_of gpl-dep)" = "forbidden" ]
    [ "$(status_of mit-dep)" = "ok" ]
}

@test "composer lock: GPL package forbidden under a proprietary project, sources merged with vendor/" {
    fx_composer "$P"
    cli_json
    [ "$status" -eq 1 ]
    [ "$(status_of acme/gpl)" = "forbidden" ]
    [ "$(status_of acme/mit)" = "ok" ]
    [ "$(jq -r '.[] | select(.name == "acme/mit") | .source' <<<"$output")" = "manifest+file" ]
}

@test "cargo vendor directory: MIT OR Apache-2.0 is read from Cargo.toml and allowed" {
    fx_cargo "$P"
    cli_json
    [ "$status" -eq 0 ]
    [ "$(jq -r '.[0].license' <<<"$output")" = "MIT OR Apache-2.0" ]
    [ "$(jq -r '.[0].status' <<<"$output")" = "ok" ]
}

@test "C++ project with vendors reports each directory, the custom license needs review" {
    fx_cpp_vendors "$P"
    cli_json
    [ "$status" -eq 0 ]
    [ "$(jq length <<<"$output")" -eq 4 ]
    [ "$(status_of vendors/airwindows)" = "ok" ]
    [ "$(status_of vendors/dusk-audio)" = "ok" ]
    [ "$(status_of vendors/mystery)" = "review" ]
}

@test "C++ project with vendors: --strict fails on the review entry" {
    fx_cpp_vendors "$P"
    cli_json --strict
    [ "$status" -eq 1 ]
}

@test "submodule without license is review: exit 0, exit 1 with --strict" {
    fx_submodule_no_license "$P"
    cli_json --project-license MIT
    [ "$status" -eq 0 ]
    [ "$(status_of vendors/x)" = "review" ]
    cli_json --project-license MIT --strict
    [ "$status" -eq 1 ]
}

@test "manifest and text disagreement is review and fails with --strict" {
    fx_conflict "$P"
    cli_json
    [ "$status" -eq 0 ]
    [ "$(status_of dep)" = "review" ]
    [[ "$(jq -r '.[0].reason' <<<"$output")" == *"text says ISC"* ]]
    cli_json --strict
    [ "$status" -eq 1 ]
}

@test "AND and OR expressions evaluate: OR with an allowed side passes, AND with a forbidden side fails" {
    fx_spdx_expr "$P"
    cli_json
    [ "$status" -eq 1 ]
    [ "$(status_of dual)" = "ok" ]
    [ "$(status_of both)" = "forbidden" ]
}

@test "SPDX header only project gives a header record" {
    fx_spdx_header "$P"
    cli_json
    [ "$status" -eq 0 ]
    [ "$(jq -r '.[0].source' <<<"$output")" = "header" ]
    [ "$(jq -r '.[0].name' <<<"$output")" = "src" ]
    [ "$(jq -r '.[0].status' <<<"$output")" = "ok" ]
}

@test "project path with spaces and a bundle directory with spaces" {
    fx_spaces "$P"
    cli_json
    [ "$status" -eq 0 ]
    [ "$(jq -r '.[0].name' <<<"$output")" = "The Stripper.vst3" ]
    [ "$(jq -r '.[0].license' <<<"$output")" = "ISC" ]
}

@test "table output of a real run lists every dependency" {
    fx_cpp_vendors "$P"
    run "$LCC_ROOT/check-licenses" --path "$P"
    [ "$status" -eq 0 ]
    [[ "$output" == *"vendors/airwindows"* ]]
    [[ "$output" == *"4 dependencies: 3 ok, 0 forbidden, 1 review"* ]]
}

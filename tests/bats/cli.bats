setup() {
    load helper
}

@test "missing jq exits 2 with a message naming jq" {
    mkdir -p "$BATS_TEST_TMPDIR/bin"
    run env -i PATH="$BATS_TEST_TMPDIR/bin" "$BASH" "$LCC_ROOT/check-licenses" --path "$BATS_TEST_TMPDIR"
    [ "$status" -eq 2 ]
    [[ "$output" == *jq* ]]
}

@test "unknown option exits 2" {
    run "$LCC_ROOT/check-licenses" --nope
    [ "$status" -eq 2 ]
}

@test "--help exits 0 and lists the options" {
    run "$LCC_ROOT/check-licenses" --help
    [ "$status" -eq 0 ]
    for opt in --path --config --project-license --json --strict; do
        [[ "$output" == *"$opt"* ]]
    done
}

@test "--path to a missing directory exits 2" {
    run "$LCC_ROOT/check-licenses" --path "$BATS_TEST_TMPDIR/does-not-exist"
    [ "$status" -eq 2 ]
}

setup() {
    load helper
    load_lcc
    lcc_load_defaults
}

write_config() {
    printf '%s\n' "$@" >"$BATS_TEST_TMPDIR/.license-compliance"
    echo "$BATS_TEST_TMPDIR/.license-compliance"
}

@test "defaults contain the permissive group and the MIT row" {
    [[ " ${LCC_GROUPS[permissive]} " == *" MIT "* ]]
    [ "${LCC_MATRIX[MIT]}" = "@permissive" ]
    [ "${LCC_FAMILIES[GPL-3.0-or-later]}" = "GPL 3.0" ]
}

@test "defaults keep the GPL-2.0-only row restricted to GPL-<=2.0" {
    [[ " ${LCC_MATRIX[GPL-2.0-only]} " == *" GPL-<=2.0 "* ]]
    [[ " ${LCC_MATRIX[GPL-2.0-only]} " != *" GPL-* "* ]]
}

@test "default exclusions are .git build dist node_modules/.cache" {
    [ "${LCC_EXCLUDE[*]}" = ".git build dist node_modules/.cache" ]
}

@test "blank lines and comments are ignored" {
    f=$(write_config "" "# a comment" "project-license MIT   # trailing comment")
    lcc_load_config "$f"
    [ "$LCC_PROJECT_LICENSE" = "MIT" ]
}

@test "group in the project config replaces the default group of the same name" {
    f=$(write_config "group permissive MIT ISC")
    lcc_load_config "$f"
    [ "${LCC_GROUPS[permissive]}" = "MIT ISC" ]
}

@test "matrix line extends the default matrix" {
    f=$(write_config "matrix LicenseRef-Mine MIT ISC")
    lcc_load_config "$f"
    [ "${LCC_MATRIX[LicenseRef-Mine]}" = "MIT ISC" ]
    [ "${LCC_MATRIX[MIT]}" = "@permissive" ]
}

@test "exclude lines are appended and include lines are recorded" {
    f=$(write_config "exclude vendors/tests" "include build")
    lcc_load_config "$f"
    [[ " ${LCC_EXCLUDE[*]} " == *" vendors/tests "* ]]
    [ "${LCC_INCLUDE[*]}" = "build" ]
}

@test "allow line is stored per dependency" {
    f=$(write_config "allow some-package LicenseRef-Custom GPL-3.0-only")
    lcc_load_config "$f"
    [ "${LCC_ALLOW[some-package]}" = "LicenseRef-Custom GPL-3.0-only" ]
}

@test "unknown directive exits 2 and names the line number" {
    f=$(write_config "project-license MIT" "" "frobnicate yes")
    run lcc_load_config "$f"
    [ "$status" -eq 2 ]
    [[ "$output" == *":3:"* ]]
    [[ "$output" == *frobnicate* ]]
}

@test "directive without a value exits 2" {
    f=$(write_config "exclude")
    run lcc_load_config "$f"
    [ "$status" -eq 2 ]
}

setup() {
    load helper
    load_lcc
    lcc_load_defaults
}

assert_match() { run lcc_license_matches "$@"; [ "$status" -eq 0 ]; }
refute_match() { run lcc_license_matches "$@"; [ "$status" -eq 1 ]; }
assert_allowed() { run lcc_is_allowed "$@"; [ "$status" -eq 0 ]; }
refute_allowed() { run lcc_is_allowed "$@"; [ "$status" -eq 1 ]; }

@test "BSD-* matches BSD-3-Clause" {
    assert_match BSD-3-Clause 'BSD-*'
    refute_match ISC 'BSD-*'
}

@test "exact MIT matches MIT only" {
    assert_match MIT MIT
    refute_match MIT-0 MIT
}

@test "GPL->=3.0 matches GPL-3.0-only and GPL-3.0-or-later but not GPL-2.0-only" {
    assert_match GPL-3.0-only 'GPL->=3.0'
    assert_match GPL-3.0-or-later 'GPL->=3.0'
    refute_match GPL-2.0-only 'GPL->=3.0'
}

@test "GPL-<=2.0 matches GPL-2.0-only and not GPL-3.0-only" {
    assert_match GPL-2.0-only 'GPL-<=2.0'
    refute_match GPL-3.0-only 'GPL-<=2.0'
}

@test "Apache-<=1.1 matches Apache-1.1 and not Apache-2.0" {
    assert_match Apache-1.1 'Apache-<=1.1'
    refute_match Apache-2.0 'Apache-<=1.1'
}

@test "strict comparators exclude the boundary" {
    refute_match GPL-3.0-only 'GPL->3.0'
    assert_match GPL-3.0-only 'GPL-<3.1'
    refute_match GPL-3.0-only 'GPL-<3.0'
}

@test "version constraint needs a known family" {
    refute_match Unknown-9.0 'Unknown->=1.0'
}

@test "MIT AND ISC is allowed when both match" {
    assert_allowed "MIT AND ISC" MIT ISC
}

@test "MIT AND Foo is refused" {
    refute_allowed "MIT AND Foo" MIT ISC
}

@test "Foo OR MIT is allowed" {
    assert_allowed "Foo OR MIT" MIT
}

@test "Foo OR Bar is refused" {
    refute_allowed "Foo OR Bar" MIT
}

@test "UNKNOWN and empty are refused" {
    refute_allowed UNKNOWN 'UNKNOWN' MIT
    refute_allowed "" MIT
    refute_allowed "   " MIT
}

@test "nested groups expand" {
    LCC_GROUPS[inner]="MIT ISC"
    LCC_GROUPS[outer]="@inner Apache-*"
    run lcc_expand_patterns @outer
    [ "$status" -eq 0 ]
    [ "$output" = $'MIT\nISC\nApache-*' ]
}

@test "cyclic groups terminate" {
    LCC_GROUPS[a]="@b X"
    LCC_GROUPS[b]="@a Y"
    run lcc_expand_patterns @a
    [ "$status" -eq 0 ]
    [ "$output" = $'Y\nX' ]
}

@test "expanded patterns are unique and unknown groups are ignored" {
    run lcc_expand_patterns MIT MIT @nope ISC
    [ "$output" = $'MIT\nISC' ]
}

@test "lcc_patterns_for expands the row of the project license" {
    run lcc_patterns_for MIT
    [ "$status" -eq 0 ]
    [[ "$output" == *$'\nMIT'* ]] || [[ "$output" == MIT* ]]
    [[ "$output" == *"GPL-*"* ]]
}

@test "lcc_patterns_for fails for a license without a matrix row" {
    run lcc_patterns_for Nonexistent-1.0
    [ "$status" -eq 1 ]
}

@test "pattern globs are not expanded against the working directory" {
    cd "$BATS_TEST_TMPDIR"
    touch BSD-fake
    run lcc_expand_patterns @permissive
    [[ "$output" == *"BSD-*"* ]]
    [[ "$output" != *"BSD-fake"* ]]
}

@test "outer parentheses are stripped" {
    assert_allowed "(MIT OR Foo)" MIT
    refute_allowed "(Foo OR Bar)" MIT
}

@test "AND binds tighter than OR" {
    assert_allowed "Foo OR MIT AND ISC" MIT ISC
    refute_allowed "Foo OR MIT AND Bar" MIT ISC
}

@test "nested parentheses are undecidable and exit 2" {
    run lcc_is_allowed "(MIT OR Foo) AND ISC" MIT ISC
    [ "$status" -eq 2 ]
}

@test "a wildcard pattern does not accept a compound expression" {
    refute_allowed "BSD-3-Clause AND CC-BY-NC-4.0" 'BSD-*'
    refute_allowed "GPL-3.0-only AND LicenseRef-Proprietary" 'GPL-*'
    refute_match "BSD-3-Clause AND CC-BY-NC-4.0" 'BSD-*'
}

@test "a license with an exception is not accepted by a wildcard" {
    refute_allowed "Apache-2.0 WITH LLVM-exception" 'Apache-*'
}

# Shared helpers for the bats suites.
LCC_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"

# Load the script's functions without running main.
load_lcc() {
    # shellcheck source=/dev/null
    LCC_SOURCE_ONLY=1 source "$LCC_ROOT/check-licenses"
}

make_project() {
    mkdir -p "$1"
}

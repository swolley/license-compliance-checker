# Builders of small projects for the end-to-end tests. Each takes the directory to create.
TEXTS="$LCC_ROOT/tests/fixtures/texts"

fx_license() { # dir, license fixture id [, file name]
    mkdir -p "$1"
    cp "$TEXTS/$2.txt" "$1/${3:-LICENSE}"
}

fx_pkg() { # dir, name, version, license expression [, license text id]
    mkdir -p "$1"
    printf '{"name":"%s","version":"%s","license":"%s"}\n' "$2" "$3" "$4" >"$1/package.json"
    if [[ -n "${5:-}" ]]; then fx_license "$1" "$5"; fi
}

fx_npm() { # MIT project with ISC and MIT dependencies
    mkdir -p "$1"
    printf '{"name":"me","version":"1.0.0","license":"MIT"}\n' >"$1/package.json"
    fx_pkg "$1/node_modules/ok-dep" ok-dep 1.0.0 ISC ISC
    fx_pkg "$1/node_modules/@s/scoped" @s/scoped 2.1.0 MIT MIT
}

fx_npm_forbidden() { # UNLICENSED project with a GPL dependency
    mkdir -p "$1"
    printf '{"name":"me","version":"1.0.0","license":"UNLICENSED"}\n' >"$1/package.json"
    fx_pkg "$1/node_modules/gpl-dep" gpl-dep 3.0.0 GPL-3.0-only GPL-3.0-only
    fx_pkg "$1/node_modules/mit-dep" mit-dep 1.0.0 MIT MIT
}

fx_composer() { # proprietary project, one GPL and one MIT package
    mkdir -p "$1"
    printf '{"name":"me/app","license":"proprietary"}\n' >"$1/composer.json"
    printf '{"packages":[{"name":"acme/gpl","version":"1.0.0","license":["GPL-3.0-only"]},{"name":"acme/mit","version":"2.0.0","license":["MIT"]}],"packages-dev":[]}\n' >"$1/composer.lock"
    fx_license "$1/vendor/acme/gpl" GPL-3.0-only
    fx_license "$1/vendor/acme/mit" MIT
}

fx_cargo() { # MIT project with a vendored dual-licensed crate
    fx_license "$1" MIT
    mkdir -p "$1/vendor/foo"
    printf '[package]\nname = "foo"\nversion = "0.3.1"\nlicense = "MIT OR Apache-2.0"\n' >"$1/vendor/foo/Cargo.toml"
}

fx_cpp_vendors() { # GPL project with C++ vendors, one of them with a custom license
    fx_license "$1" GPL-3.0-only
    fx_license "$1/vendors/airwindows" MIT
    fx_license "$1/vendors/dusk-audio" GPL-3.0-only
    fx_license "$1/vendors/vst3sdk" GPL-3.0-only
    mkdir -p "$1/vendors/mystery"
    printf 'All rights reserved. Internal use only.\n' >"$1/vendors/mystery/LICENSE"
}

fx_submodule_no_license() {
    mkdir -p "$1"
    printf '[submodule "vendors/x"]\n\tpath = vendors/x\n\turl = https://example.com/x.git\n' >"$1/.gitmodules"
}

fx_conflict() { # manifest says MIT, the text is ISC
    mkdir -p "$1"
    printf '{"name":"me","license":"MIT"}\n' >"$1/package.json"
    fx_pkg "$1/node_modules/dep" dep 1.0.0 MIT ISC
}

fx_spdx_expr() { # proprietary project: OR with an allowed side, AND with a forbidden side
    mkdir -p "$1"
    printf '{"name":"me","license":"UNLICENSED"}\n' >"$1/package.json"
    fx_pkg "$1/node_modules/dual" dual 1.0.0 "(MIT OR GPL-3.0-only)"
    fx_pkg "$1/node_modules/both" both 1.0.0 "MIT AND GPL-3.0-only"
}

fx_spdx_header() {
    fx_license "$1" MIT
    mkdir -p "$1/src"
    printf '// SPDX-License-Identifier: MIT\nint main() { return 0; }\n' >"$1/src/main.c"
}

fx_spaces() { # path with spaces and a bundle directory with spaces
    fx_license "$1" MIT
    fx_license "$1/The Stripper.vst3" ISC
}

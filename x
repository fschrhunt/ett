#!/bin/sh
# Compile-check ett without starting its listener or registering hotkeys.
set -eu
cd "$(dirname "$0")"

usage() {
    echo 'usage: ./x [check|build|shell|help]' >&2
    echo 'check (default): shell syntax and a release build; requires macOS and Xcode tools' >&2
    exit "${1:-2}"
}

command=${1-check}
if [ "$#" -gt 0 ]; then shift; fi
[ "$#" -eq 0 ] || usage
case "$command" in
    check) ./x shell; ./x build ;;
    shell) sh -n x ;;
    build)
        [ "$(uname -s)" = Darwin ] || {
            echo 'build: macOS and Xcode command line tools are required' >&2
            exit 2
        }
        scratch=$(mktemp -d "${TMPDIR:-/tmp}/ett-check.XXXXXXXX")
        trap 'rm -rf "$scratch"' EXIT
        trap 'exit 130' INT
        trap 'exit 143' TERM
        swift build --scratch-path "$scratch" -c release
        ;;
    help|-h|--help) usage 0 ;;
    *) usage ;;
esac

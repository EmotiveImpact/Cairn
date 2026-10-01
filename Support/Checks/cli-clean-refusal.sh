#!/bin/sh
# Run after building Cairn. The impossible category makes this safe even if
# a future change accidentally reaches candidate collection before refusal.
set -eu

binary=${1:-.build/debug/Cairn}
invalid_category=__cairn_cli_refusal_fixture_no_such_category__

for confirmation in --yes -y; do
    set +e
    output=$("$binary" clean --safe "$confirmation" --category "$invalid_category" 2>&1)
    result=$?
    set -e
    if [ "$result" -ne 2 ]; then
        printf 'FAIL: %s returned %s instead of 2\n%s\n' "$confirmation" "$result" "$output" >&2
        exit 1
    fi
    case "$output" in
        *"CLI cleanup is preview-only"*) ;;
        *) printf 'FAIL: %s did not explain the refusal\n%s\n' "$confirmation" "$output" >&2; exit 1 ;;
    esac
    case "$output" in
        *"Unknown category"*) printf 'FAIL: %s reached candidate collection\n' "$confirmation" >&2; exit 1 ;;
    esac
done

printf 'CLI confirmed cleanup refused before scanning (2 cases).\n'

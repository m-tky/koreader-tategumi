#!/usr/bin/env bash

set -uo pipefail

max_attempts="${BUILD_MAX_ATTEMPTS:-2}"
attempt=1

while true; do
    echo "Build attempt ${attempt}/${max_attempts}: $*"
    if "$@"; then
        exit 0
    else
        status=$?
    fi

    if [ "${attempt}" -ge "${max_attempts}" ]; then
        echo "Build failed after ${attempt} attempts (exit ${status})." >&2
        exit "${status}"
    fi

    # The build system already retries individual clones. A second top-level
    # attempt reuses completed work and recovers when an external host was
    # unreachable for the duration of all of those clone attempts.
    delay=$((attempt * 15))
    echo "Build attempt ${attempt} failed (exit ${status}); retrying in ${delay}s." >&2
    sleep "${delay}"
    attempt=$((attempt + 1))
done

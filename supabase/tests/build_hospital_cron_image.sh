#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
work_dir=$(mktemp -d)
trap 'rm -rf "$work_dir"' EXIT
curl --fail --location --retry 2 --connect-timeout 15 --max-time 120 'https://codeload.github.com/citusdata/pg_cron/tar.gz/refs/tags/v1.6.7' -o "$work_dir/pg_cron.tar.gz"
printf '%s  %s\n' 'd950bc29155f31017567e23a31d268ff672e98276c0e9d062512fb7870351f03' "$work_dir/pg_cron.tar.gz" | sha256sum --check --status
cp supabase/tests/postgres-cron.Dockerfile "$work_dir/Dockerfile"
docker build --network host -t vetdosis-postgres17-cron:test "$work_dir"

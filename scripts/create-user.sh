#!/usr/bin/env bash
# Create a user account when self-serve sign-up is disabled (invite-only).
# Runs the create_user CLI INSIDE the backend container — the DB isn't exposed to
# the network — reusing the app's Argon2id + PASSWORD_PEPPER hashing.
#
#   scripts/create-user.sh <email> <password> [screen_name]
#
# Override the compose invocation with DC=... if your paths differ.
set -euo pipefail

DC="${DC:-docker compose -f production.docker-compose.yaml --env-file .env.production}"

if [ "$#" -lt 2 ]; then
  echo "usage: $0 <email> <password> [screen_name]" >&2
  exit 1
fi

exec $DC exec -T backend create_user "$@"

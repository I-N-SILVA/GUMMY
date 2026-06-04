#!/bin/bash
# Installs project dependencies so linters and tests work in Claude Code on the web.
# Idempotent and non-interactive. Safe to run multiple times.
set -euo pipefail

# Only run in the remote (web) environment; local setups manage their own deps.
if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ]; then
  exit 0
fi

cd "${CLAUDE_PROJECT_DIR:-.}"

# Select the Ruby pinned in .ruby-version when rbenv manages it, and persist it
# for the rest of the session so later shells inherit the same runtime.
if command -v rbenv >/dev/null 2>&1; then
  eval "$(rbenv init - bash)"
  if [ -n "${CLAUDE_ENV_FILE:-}" ]; then
    echo "export PATH=\"$(rbenv root)/shims:\$PATH\"" >> "$CLAUDE_ENV_FILE"
  fi
fi

# JavaScript/TypeScript dependencies — enables eslint, tsc, and prettier.
echo "==> Installing JS dependencies (npm install)…"
npm install --no-audit --no-fund

# Ruby dependencies — enables rubocop and rspec. The project pins a specific
# Ruby (.ruby-version); if the runtime doesn't satisfy it, skip rather than
# fail the whole hook so the JS toolchain is still ready.
if command -v bundle >/dev/null 2>&1; then
  # The mysql2 gem (a transitive dependency) compiles against the MySQL client
  # headers. Install them best-effort when missing so bundle install can build.
  if ! pkg-config --exists mysqlclient 2>/dev/null && command -v apt-get >/dev/null 2>&1; then
    echo "==> Installing MySQL client headers for native gems…"
    apt-get update -qq && apt-get install -y --no-install-recommends default-libmysqlclient-dev pkg-config ||
      echo "WARNING: could not install MySQL client headers; mysql2 may fail to build." >&2
  fi

  echo "==> Installing Ruby dependencies (bundle install)…"
  if bundle install --jobs 4 --retry 3; then
    echo "==> Ruby dependencies installed."
  else
    echo "WARNING: bundle install failed with $(ruby -v 2>/dev/null). Ruby tooling (rubocop/rspec) will be unavailable this session; the JS toolchain is unaffected." >&2
  fi
fi

echo "==> Dependency setup complete."

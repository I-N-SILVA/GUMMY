#!/bin/bash
# Installs project dependencies so linters and tests work in Claude Code on the web.
# Idempotent and non-interactive. Safe to run multiple times.
set -euo pipefail

# Only run in the remote (web) environment; local setups manage their own deps.
if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ]; then
  exit 0
fi

cd "${CLAUDE_PROJECT_DIR:-.}"

RUBY_VERSION_REQUIRED="$(cat .ruby-version 2>/dev/null || echo "")"
TOOLCACHE_RUBY="/opt/hostedtoolcache/Ruby/${RUBY_VERSION_REQUIRED}/x64"

persist_path() {
  if [ -n "${CLAUDE_ENV_FILE:-}" ]; then
    echo "export PATH=\"$1:\$PATH\"" >> "$CLAUDE_ENV_FILE"
  fi
  export PATH="$1:$PATH"
}

# rbenv builds Ruby from source at cache.ruby-lang.org, which the sandbox network
# policy blocks. GitHub is reachable, so fall back to the prebuilt tarball that
# ruby/ruby-builder publishes for the same Ubuntu release.
setup_ruby() {
  if [ -z "$RUBY_VERSION_REQUIRED" ]; then
    return
  fi

  if [ -x "${TOOLCACHE_RUBY}/bin/ruby" ]; then
    persist_path "${TOOLCACHE_RUBY}/bin"
    echo "==> Ruby ${RUBY_VERSION_REQUIRED} already present."
    return
  fi

  if command -v rbenv >/dev/null 2>&1 && rbenv versions --bare 2>/dev/null | grep -qx "$RUBY_VERSION_REQUIRED"; then
    eval "$(rbenv init - bash)"
    persist_path "$(rbenv root)/shims"
    return
  fi

  local codename tarball
  codename="$(. /etc/os-release 2>/dev/null && echo "${VERSION_ID:-24.04}")"
  tarball="https://github.com/ruby/ruby-builder/releases/download/toolcache/ruby-${RUBY_VERSION_REQUIRED}-ubuntu-${codename}.tar.gz"

  echo "==> Installing prebuilt Ruby ${RUBY_VERSION_REQUIRED}…"
  mkdir -p "$TOOLCACHE_RUBY"
  if curl -fsSL --max-time 300 "$tarball" | tar -xz -C "$TOOLCACHE_RUBY" --strip-components=1; then
    persist_path "${TOOLCACHE_RUBY}/bin"
    echo "==> Ruby $("${TOOLCACHE_RUBY}/bin/ruby" -v 2>/dev/null) installed."
  else
    echo "WARNING: could not install Ruby ${RUBY_VERSION_REQUIRED}; Ruby tooling will be unavailable." >&2
    rm -rf "$TOOLCACHE_RUBY"
  fi
}

# RSpec needs MySQL and Redis. Elasticsearch and MongoDB are also required by the
# suite but their download hosts are blocked, so specs touching search or the
# Mongo-backed models cannot run here. See docs/payments/testing-pix-and-brl.md.
setup_datastores() {
  if command -v apt-get >/dev/null 2>&1 && ! command -v mysqld >/dev/null 2>&1; then
    echo "==> Installing MySQL server…"
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq mysql-server >/dev/null 2>&1 ||
      echo "WARNING: could not install MySQL server." >&2
  fi

  if command -v mysqld >/dev/null 2>&1; then
    mkdir -p /var/run/mysqld && chown mysql:mysql /var/run/mysqld 2>/dev/null || true
    mysqladmin status >/dev/null 2>&1 || service mysql start >/dev/null 2>&1 || true

    # .env.test expects root/password over TCP; a fresh install uses auth_socket.
    if mysqladmin status >/dev/null 2>&1 && ! mysql -h 127.0.0.1 -u root -ppassword -e "SELECT 1" >/dev/null 2>&1; then
      mysql -u root <<'SQL' >/dev/null 2>&1 || true
ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY 'password';
CREATE USER IF NOT EXISTS 'root'@'127.0.0.1' IDENTIFIED WITH mysql_native_password BY 'password';
GRANT ALL PRIVILEGES ON *.* TO 'root'@'127.0.0.1' WITH GRANT OPTION;
FLUSH PRIVILEGES;
SQL
    fi
  fi

  if command -v redis-server >/dev/null 2>&1 && ! redis-cli ping >/dev/null 2>&1; then
    echo "==> Starting Redis…"
    redis-server --daemonize yes --port 6379 >/dev/null 2>&1 || true
  fi
}

setup_ruby

echo "==> Installing JS dependencies (npm install)…"
npm install --no-audit --no-fund

if command -v bundle >/dev/null 2>&1; then
  # The mysql2 gem compiles against the MySQL client headers.
  if ! pkg-config --exists mysqlclient 2>/dev/null && command -v apt-get >/dev/null 2>&1; then
    echo "==> Installing MySQL client headers for native gems…"
    apt-get update -qq && apt-get install -y --no-install-recommends default-libmysqlclient-dev pkg-config ||
      echo "WARNING: could not install MySQL client headers; mysql2 may fail to build." >&2
  fi

  echo "==> Installing Ruby dependencies (bundle install)…"
  if bundle install --jobs 4 --retry 3; then
    echo "==> Ruby dependencies installed."

    setup_datastores

    if mysqladmin status >/dev/null 2>&1; then
      echo "==> Preparing test database…"
      RAILS_ENV=test bundle exec rails db:prepare >/dev/null 2>&1 ||
        echo "WARNING: could not prepare the test database." >&2
    fi
  else
    echo "WARNING: bundle install failed with $(ruby -v 2>/dev/null). Ruby tooling (rubocop/rspec) will be unavailable this session; the JS toolchain is unaffected." >&2
  fi
fi

echo "==> Dependency setup complete."

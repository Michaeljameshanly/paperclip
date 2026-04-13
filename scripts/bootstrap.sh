#!/bin/sh
# bootstrap.sh — runs after the Paperclip server starts and generates the
# first admin invite URL via `paperclipai auth bootstrap-ceo`.
#
# Executed as the `node` user (via docker-entrypoint.sh) in a background
# subshell so it never blocks or kills the server process.

set -e

BOOTSTRAP_WAIT_SECONDS="${BOOTSTRAP_WAIT_SECONDS:-120}"
BOOTSTRAP_POLL_INTERVAL="${BOOTSTRAP_POLL_INTERVAL:-3}"
PORT="${PORT:-3100}"
HEALTH_URL="http://127.0.0.1:${PORT}/api/health"

# ── 1. Wait for server health ─────────────────────────────────────────────────
echo ""
echo "┌──────────────────────────────────────────────────────────────────────────┐"
echo "│  Paperclip Bootstrap: waiting for server to be ready...                  │"
echo "└──────────────────────────────────────────────────────────────────────────┘"

elapsed=0
while true; do
  if curl -sf --max-time 3 "${HEALTH_URL}" > /dev/null 2>&1; then
      echo "[bootstrap] Server is healthy after ${elapsed}s."
          break
            fi
              if [ "${elapsed}" -ge "${BOOTSTRAP_WAIT_SECONDS}" ]; then
                  echo "[bootstrap] ERROR: Server not ready after ${BOOTSTRAP_WAIT_SECONDS}s. Aborting."
                      exit 1
                        fi
                          sleep "${BOOTSTRAP_POLL_INTERVAL}"
                            elapsed=$((elapsed + BOOTSTRAP_POLL_INTERVAL))
                            done

                            # ── 2. Check if already bootstrapped ─────────────────────────────────────────
                            HEALTH_JSON="$(curl -sf --max-time 5 "${HEALTH_URL}" 2>/dev/null || echo '{}')"
                            BOOTSTRAP_STATUS="$(echo "${HEALTH_JSON}" | grep -o '"bootstrapStatus":"[^"]*"' | cut -d'"' -f4 || echo 'unknown')"

                            if [ "${BOOTSTRAP_STATUS}" = "ready" ]; then
                              echo "[bootstrap] Instance already bootstrapped. Skipping."
                                exit 0
                                fi

                                echo ""
                                echo "┌──────────────────────────────────────────────────────────────────────────┐"
                                echo "│  Paperclip Bootstrap: generating first admin invite URL...               │"
                                echo "└──────────────────────────────────────────────────────────────────────────┘"

                                # ── 3. Ensure config.json exists (required by CLI) ────────────────────────────
                                PAPERCLIP_HOME="${PAPERCLIP_HOME:-/paperclip}"
                                CONFIG_DIR="${PAPERCLIP_HOME}/instances/default"
                                CONFIG_FILE="${CONFIG_DIR}/config.json"

                                if [ ! -f "${CONFIG_FILE}" ]; then
                                  echo "[bootstrap] Config file missing at ${CONFIG_FILE}. Creating from environment..."
                                    mkdir -p "${CONFIG_DIR}"

                                      PUBLIC_URL="${PAPERCLIP_PUBLIC_URL:-${PAPERCLIP_AUTH_PUBLIC_BASE_URL:-${BETTER_AUTH_URL:-}}}"
                                        STORAGE_DIR="${PAPERCLIP_STORAGE_LOCAL_DIR:-${CONFIG_DIR}/data/storage}"

                                          node -e "
                                          const cfg = {
                                            server: {
                                                deploymentMode: 'authenticated',
                                                    exposure: 'public',
                                                        port: parseInt(process.env.PORT || '3100'),
                                                            host: '0.0.0.0',
                                                                bind: 'lan',
                                                                    serveUi: true,
                                                                        allowedHostnames: []
                                                                          },
                                                                            database: {
                                                                                mode: 'postgres',
                                                                                    connectionString: process.env.DATABASE_URL
                                                                                      },
                                                                                        auth: {
                                                                                            baseUrlMode: 'explicit',
                                                                                                publicBaseUrl: process.env.PAPERCLIP_PUBLIC_URL || process.env.PAPERCLIP_AUTH_PUBLIC_BASE_URL || process.env.BETTER_AUTH_URL || ''
                                                                                                  },
                                                                                                    logging: {
                                                                                                        mode: 'stdout',
                                                                                                            logDir: process.env.PAPERCLIP_HOME ? process.env.PAPERCLIP_HOME + '/instances/default/logs' : '/paperclip/instances/default/logs'
                                                                                                              },
                                                                                                                storage: {
                                                                                                                    provider: 'local-disk',
                                                                                                                        localDisk: {
                                                                                                                              dir: process.env.PAPERCLIP_STORAGE_LOCAL_DIR || '/paperclip/instances/default/data/storage'
                                                                                                                                  }
                                                                                                                                    },
                                                                                                                                      secrets: {
                                                                                                                                          provider: 'local-encrypted',
                                                                                                                                              localEncrypted: {
                                                                                                                                                    strictMode: false,
                                                                                                                                                          keyFilePath: (process.env.PAPERCLIP_HOME || '/paperclip') + '/instances/default/secrets/master.key'
                                                                                                                                                              }
                                                                                                                                                                }
                                                                                                                                                                };
                                                                                                                                                                require('fs').writeFileSync('${CONFIG_FILE}', JSON.stringify(cfg, null, 2), {mode: 0o600});
                                                                                                                                                                console.log('[bootstrap] Config written to ${CONFIG_FILE}');
                                                                                                                                                                "
                                                                                                                                                                  echo "[bootstrap] Config file created."
                                                                                                                                                                  else
                                                                                                                                                                    echo "[bootstrap] Config file already exists at ${CONFIG_FILE}."
                                                                                                                                                                    fi
                                                                                                                                                                    
                                                                                                                                                                    # ── 4. Run bootstrap-ceo ──────────────────────────────────────────────────────
                                                                                                                                                                    cd /app
                                                                                                                                                                    attempt=0
                                                                                                                                                                    max_attempts=5
                                                                                                                                                                    BOOTSTRAP_OUTPUT=""
                                                                                                                                                                    
                                                                                                                                                                    echo "[bootstrap] Running auth bootstrap-ceo (up to ${max_attempts} attempts)..."
                                                                                                                                                                    
                                                                                                                                                                    while [ "${attempt}" -lt "${max_attempts}" ]; do
                                                                                                                                                                      attempt=$((attempt + 1))
                                                                                                                                                                        echo "[bootstrap] Attempt ${attempt}/${max_attempts}..."
                                                                                                                                                                          BOOTSTRAP_OUTPUT="$(node cli/node_modules/tsx/dist/cli.mjs cli/src/index.ts auth bootstrap-ceo 2>&1)"
                                                                                                                                                                            exit_code=$?
                                                                                                                                                                            
                                                                                                                                                                              if [ "${exit_code}" -eq 0 ] && echo "${BOOTSTRAP_OUTPUT}" | grep -q "http"; then
                                                                                                                                                                                  echo "[bootstrap] Bootstrap succeeded on attempt ${attempt}."
                                                                                                                                                                                      break
                                                                                                                                                                                        fi
                                                                                                                                                                                        
                                                                                                                                                                                          if [ "${attempt}" -lt "${max_attempts}" ]; then
                                                                                                                                                                                              echo "[bootstrap] Output: ${BOOTSTRAP_OUTPUT}"
                                                                                                                                                                                                  echo "[bootstrap] Retrying in 5s..."
                                                                                                                                                                                                      sleep 5
                                                                                                                                                                                                        fi
                                                                                                                                                                                                        done
                                                                                                                                                                                                        
                                                                                                                                                                                                        echo ""
                                                                                                                                                                                                        echo "╔══════════════════════════════════════════════════════════════════════════╗"
                                                                                                                                                                                                        echo "║                    PAPERCLIP ADMIN INVITE URL                           ║"
                                                                                                                                                                                                        echo "╚══════════════════════════════════════════════════════════════════════════╝"
                                                                                                                                                                                                        echo "${BOOTSTRAP_OUTPUT}" | while IFS= read -r line; do
                                                                                                                                                                                                          printf "║  %-70s  ║\n" "${line}"
                                                                                                                                                                                                          done
                                                                                                                                                                                                          echo "╔══════════════════════════════════════════════════════════════════════════╝"
                                                                                                                                                                                                          echo ""
                                                                                                                                                                                                          echo "[bootstrap] Open the invite URL above in your browser to create the first admin account."
                                                                                                                                                                                                          echo "[bootstrap] The URL expires in 72 hours."

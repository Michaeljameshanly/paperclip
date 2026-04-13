#!/bin/sh
# bootstrap.sh - runs after the Paperclip server starts and generates the
# first admin invite URL via `paperclipai auth bootstrap-ceo`.
#
# This script is executed as the `node` user (via docker-entrypoint.sh) in a
# background subshell so it never blocks or kills the server process.
#
# Environment variables honoured:
#   BOOTSTRAP_WAIT_SECONDS  Max seconds to wait for the server to be ready (default: 120)
#   BOOTSTRAP_POLL_INTERVAL Seconds between health-check polls (default: 3)
#   PORT                    Server port (default: 3100)

set -e

BOOTSTRAP_WAIT_SECONDS="${BOOTSTRAP_WAIT_SECONDS:-120}"
BOOTSTRAP_POLL_INTERVAL="${BOOTSTRAP_POLL_INTERVAL:-3}"
PORT="${PORT:-3100}"
HEALTH_URL="http://127.0.0.1:${PORT}/api/health"

# -- Wait for the server to be healthy ────────────────────────────────────────
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

                                    # -- Check if bootstrap is already done ───────────────────────────────────────
                                    HEALTH_JSON="$(curl -sf --max-time 5 "${HEALTH_URL}" 2>/dev/null || echo '{}')"
                                    BOOTSTRAP_STATUS="$(echo "${HEALTH_JSON}" | grep -o '"bootstrapStatus":"[^"]*"' | cut -d'"' -f4 || echo 'unknown')"

                                    if [ "${BOOTSTRAP_STATUS}" = "ready" ]; then
                                      echo "[bootstrap] Instance already bootstrapped (bootstrapStatus=ready). Skipping."
                                        exit 0
                                        fi

                                        echo ""
                                        echo "┌──────────────────────────────────────────────────────────────────────────┐"
                                        echo "│  Paperclip Bootstrap: generating first admin invite URL...               │"
                                        echo "└──────────────────────────────────────────────────────────────────────────┘"

                                        # -- Ensure config.json exists (required by CLI auth bootstrap-ceo) ───────────
                                        PAPERCLIP_HOME="${PAPERCLIP_HOME:-/paperclip}"
                                        CONFIG_DIR="${PAPERCLIP_HOME}/instances/default"
                                        CONFIG_FILE="${CONFIG_DIR}/config.json"

                                        if [ ! -f "${CONFIG_FILE}" ]; then
                                          echo "[bootstrap] Config file not found at ${CONFIG_FILE}. Creating minimal config..."
                                            mkdir -p "${CONFIG_DIR}"

                                              # Resolve public URL from env vars (used for auth base URL)
                                                PUBLIC_URL="${PAPERCLIP_PUBLIC_URL:-${PAPERCLIP_AUTH_PUBLIC_BASE_URL:-${BETTER_AUTH_URL:-${BETTER_AUTH_BASE_URL:-}}}}"

                                                  # Resolve storage dir
                                                    STORAGE_DIR="${PAPERCLIP_STORAGE_LOCAL_DIR:-${CONFIG_DIR}/data/storage}"

                                                      cat > "${CONFIG_FILE}" << ENDOFCONFIG
                                                      {
                                                        "server": {
                                                            "deploymentMode": "authenticated",
                                                                "exposure": "public",
                                                                    "port": ${PORT},
                                                                        "host": "0.0.0.0",
                                                                            "bind": "lan",
                                                                                "serveUi": true,
                                                                                    "allowedHostnames": []
                                                                                      },
                                                                                        "database": {
                                                                                            "mode": "postgres",
                                                                                                "connectionString": "${DATABASE_URL}"
                                                                                                  },
                                                                                                    "auth": {
                                                                                                        "baseUrlMode": "explicit",
                                                                                                            "publicBaseUrl": "${PUBLIC_URL}"
                                                                                                              },
                                                                                                                "logging": {
                                                                                                                    "mode": "stdout",
                                                                                                                        "logDir": "${CONFIG_DIR}/logs"
                                                                                                                          },
                                                                                                                            "storage": {
                                                                                                                                "provider": "local-disk",
                                                                                                                                    "localDisk": {
                                                                                                                                          "dir": "${STORAGE_DIR}"
                                                                                                                                              }
                                                                                                                                                },
                                                                                                                                                  "secrets": {
                                                                                                                                                      "provider": "local-encrypted",
                                                                                                                                                          "localEncrypted": {
                                                                                                                                                                "strictMode": false,
                                                                                                                                                                      "keyFilePath": "${CONFIG_DIR}/secrets/master.key"
                                                                                                                                                                          }
                                                                                                                                                                            }
                                                                                                                                                                            }
                                                                                                                                                                            ENDOFCONFIG
                                                                                                                                                                              chmod 600 "${CONFIG_FILE}"
                                                                                                                                                                                echo "[bootstrap] Config file created at ${CONFIG_FILE}"
                                                                                                                                                                                else
                                                                                                                                                                                  echo "[bootstrap] Config file already exists at ${CONFIG_FILE}"
                                                                                                                                                                                  fi
                                                                                                                                                                                  
                                                                                                                                                                                  # -- Run bootstrap command ─────────────────────────────────────────────────────
                                                                                                                                                                                  cd /app
                                                                                                                                                                                  attempt=0
                                                                                                                                                                                  max_attempts=5
                                                                                                                                                                                  BOOTSTRAP_OUTPUT=
                                                                                                                                                                                  
                                                                                                                                                                                  echo "[bootstrap] Running bootstrap command (will retry up to ${max_attempts} times)..."
                                                                                                                                                                                  
                                                                                                                                                                                  while [ "${attempt}" -lt "${max_attempts}" ]; do
                                                                                                                                                                                    attempt=$((attempt + 1))
                                                                                                                                                                                      echo "[bootstrap] Attempt ${attempt}/${max_attempts}..."
                                                                                                                                                                                        BOOTSTRAP_OUTPUT="$(node cli/node_modules/tsx/dist/cli.mjs cli/src/index.ts auth bootstrap-ceo 2>&1)"
                                                                                                                                                                                          exit_code=$?
                                                                                                                                                                                          
                                                                                                                                                                                            if [ "${exit_code}" -eq 0 ] && [ -n "${BOOTSTRAP_OUTPUT}" ]; then
                                                                                                                                                                                                # Check if the output contains an actual URL (not an error message)
                                                                                                                                                                                                    if echo "${BOOTSTRAP_OUTPUT}" | grep -q "http"; then
                                                                                                                                                                                                          echo "[bootstrap] Bootstrap command succeeded on attempt ${attempt}."
                                                                                                                                                                                                                break
                                                                                                                                                                                                                    fi
                                                                                                                                                                                                                      fi
                                                                                                                                                                                                                      
                                                                                                                                                                                                                        if [ "${attempt}" -lt "${max_attempts}" ]; then
                                                                                                                                                                                                                            echo "[bootstrap] Command output was: ${BOOTSTRAP_OUTPUT}"
                                                                                                                                                                                                                                echo "[bootstrap] Retrying in 5s..."
                                                                                                                                                                                                                                    sleep 5
                                                                                                                                                                                                                                      fi
                                                                                                                                                                                                                                      done
                                                                                                                                                                                                                                      
                                                                                                                                                                                                                                      echo ""
                                                                                                                                                                                                                                      echo "╔══════════════════════════════════════════════════════════════════════════╗"
                                                                                                                                                                                                                                      echo "║                     PAPERCLIP ADMIN INVITE URL                          ║"
                                                                                                                                                                                                                                      echo "╚══════════════════════════════════════════════════════════════════════════╝"
                                                                                                                                                                                                                                      echo "${BOOTSTRAP_OUTPUT}" | while IFS= read -r line; do
                                                                                                                                                                                                                                        printf "║  %-60s  ║\n" "${line}"
                                                                                                                                                                                                                                        done
                                                                                                                                                                                                                                        echo "╔══════════════════════════════════════════════════════════════════════════╝"
                                                                                                                                                                                                                                        echo ""
                                                                                                                                                                                                                                        echo "[bootstrap] Copy the invite URL above and open it in your browser to create the first admin account."
                                                                                                                                                                                                                                        echo "[bootstrap] The URL expires in 72 hours. Run 'paperclipai auth bootstrap-ceo --force' to generate a new one."

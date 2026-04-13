#!/bin/sh
# bootstrap.sh — runs after the Paperclip server starts and generates the
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
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║ Paperclip Bootstrap: waiting for server to be ready... ║"
echo "╚══════════════════════════════════════════════════════════════╝"

elapsed=0
while true; do
  if curl -sf --max-time 3 "${HEALTH_URL}" > /dev/null 2>&1; then
      echo "[bootstrap] Server is healthy after ${elapsed}s."
          break
            fi

              if [ "${elapsed}" -ge "${BOOTSTRAP_WAIT_SECONDS}" ]; then
                  echo "[bootstrap] ERROR: Server did not become healthy within ${BOOTSTRAP_WAIT_SECONDS}s. Skipping bootstrap."
                      exit 0
                        fi

                          sleep "${BOOTSTRAP_POLL_INTERVAL}"
                            elapsed=$((elapsed + BOOTSTRAP_POLL_INTERVAL))
                            done

                            # -- Check whether bootstrap is still needed ───────────────────────────────────
                            HEALTH_JSON="$(curl -sf --max-time 5 "${HEALTH_URL}" 2>/dev/null || echo '{}')"
                            BOOTSTRAP_STATUS="$(echo "${HEALTH_JSON}" | grep -o '"bootstrapStatus":"[^"]*"' | cut -d'"' -f4)"
                            INVITE_ACTIVE="$(echo "${HEALTH_JSON}" | grep -o '"bootstrapInviteActive":[a-z]*' | cut -d':' -f2)"

                            if [ "${BOOTSTRAP_STATUS}" = "ready" ]; then
                              echo "[bootstrap] Instance already has an admin user — skipping bootstrap."
                                exit 0
                                fi

                                if [ "${INVITE_ACTIVE}" = "true" ]; then
                                  echo "[bootstrap] A bootstrap invite is already active — re-running to display the URL."
                                  fi

                                  # -- Run the bootstrap command ─────────────────────────────────────────────────
                                  echo ""
                                  echo "╔══════════════════════════════════════════════════════════════╗"
                                  echo "║ Paperclip Bootstrap: generating first admin invite URL... ║"
                                  echo "╚══════════════════════════════════════════════════════════════╝"

                                  # Run from /app so pnpm workspace resolution works correctly.
                                  cd /app

                                  # Retry the bootstrap command until it succeeds or we hit the max attempts.
                                  # The command may fail if the server hasn't finished initializing its config.
                                  max_attempts=30
                                  attempt=0
                                  BOOTSTRAP_OUTPUT=""

                                  echo "[bootstrap] Running bootstrap command (will retry up to ${max_attempts} times)..."

                                  while [ "${attempt}" -lt "${max_attempts}" ]; do
                                    attempt=$((attempt + 1))
                                      echo "[bootstrap] Attempt ${attempt}/${max_attempts}..."
                                                BOOTSTRAP_OUTPUT="$(node cli/node_modules/tsx/dist/cli.mjs cli/src/index.ts auth bootstrap-ceo 2>&1)"
                                          exit_code=$?

                                            if [ "${exit_code}" -eq 0 ] && [ -n "${BOOTSTRAP_OUTPUT}" ]; then
                                                echo "[bootstrap] Bootstrap command succeeded on attempt ${attempt}."
                                                    break
                                                      fi

                                                        if [ "${attempt}" -lt "${max_attempts}" ]; then
                                                            echo "[bootstrap] Command failed or empty output (exit: ${exit_code}). Retrying in 5s..."
                                                                echo "[bootstrap] Output was: ${BOOTSTRAP_OUTPUT}"
                                                                    sleep 5
                                                                      fi
                                                                      done

                                                                      echo ""
                                                                      echo "╔══════════════════════════════════════════════════════════════╗"
                                                                      echo "║                 PAPERCLIP ADMIN INVITE URL                  ║"
                                                                      echo "╠══════════════════════════════════════════════════════════════╣"
                                                                      echo "${BOOTSTRAP_OUTPUT}" | while IFS= read -r line; do
                                                                        printf "║ %-60s ║\n" "${line}"
                                                                        done
                                                                        echo "╚══════════════════════════════════════════════════════════════╝"
                                                                        echo ""
                                                                        echo "[bootstrap] Copy the invite URL above and open it in your browser to create the first admin account."
                                                                        echo "[bootstrap] The URL expires in 72 hours. Run 'paperclipai auth bootstrap-ceo --force' to generate a new one."
                                                                        echo ""

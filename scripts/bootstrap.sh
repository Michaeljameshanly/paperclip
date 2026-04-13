#!/bin/sh
# bootstrap.sh — runs after the Paperclip server starts and generates the
# first admin invite URL via direct DB insertion (bypassing CLI TTY issues).
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
echo "│ Paperclip Bootstrap: waiting for server to be ready...                  │"
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
                                echo "│ Paperclip Bootstrap: generating first admin invite URL...               │"
                                echo "└──────────────────────────────────────────────────────────────────────────┘"

                                # ── 3. Ensure config.json exists (required by CLI) ────────────────────────────
                                PAPERCLIP_HOME="${PAPERCLIP_HOME:-/paperclip}"
                                CONFIG_DIR="${PAPERCLIP_HOME}/instances/default"
                                CONFIG_FILE="${CONFIG_DIR}/config.json"

                                if [ ! -f "${CONFIG_FILE}" ]; then
                                  echo "[bootstrap] Config file missing at ${CONFIG_FILE}. Creating from environment..."
                                    mkdir -p "${CONFIG_DIR}"
                                      node -e "
                                        const cfg = {
                                            server: { deploymentMode: 'authenticated', exposure: 'public', port: parseInt(process.env.PORT || '3100'), host: '0.0.0.0', bind: 'lan', serveUi: true, allowedHostnames: [] },
                                                database: { mode: 'postgres', connectionString: process.env.DATABASE_URL },
                                                    auth: { baseUrlMode: 'explicit', publicBaseUrl: process.env.PAPERCLIP_PUBLIC_URL || process.env.PAPERCLIP_AUTH_PUBLIC_BASE_URL || process.env.BETTER_AUTH_URL || '' },
                                                        logging: { mode: 'stdout', logDir: (process.env.PAPERCLIP_HOME || '/paperclip') + '/instances/default/logs' },
                                                            storage: { provider: 'local-disk', localDisk: { dir: process.env.PAPERCLIP_STORAGE_LOCAL_DIR || '/paperclip/instances/default/data/storage' } },
                                                                secrets: { provider: 'local-encrypted', localEncrypted: { strictMode: false, keyFilePath: (process.env.PAPERCLIP_HOME || '/paperclip') + '/instances/default/secrets/master.key' } }
                                                                  };
                                                                    require('fs').writeFileSync('${CONFIG_FILE}', JSON.stringify(cfg, null, 2), {mode: 0o600});
                                                                      console.log('[bootstrap] Config written to ${CONFIG_FILE}');
                                                                        "
                                                                          echo "[bootstrap] Config file created."
                                                                          else
                                                                            echo "[bootstrap] Config file already exists at ${CONFIG_FILE}."
                                                                            fi

                                                                            # ── 4. Generate bootstrap invite via direct Node.js DB script ─────────────────
                                                                            cd /app
                                                                            echo "[bootstrap] Running direct DB bootstrap (Node.js)..."

                                                                            node -e "
                                                                            const crypto = require('crypto');
                                                                            const path = require('path');
                                                                            const fs = require('fs');

                                                                            async function findPostgres() {
                                                                              // Try direct path first
                                                                                const direct = '/app/node_modules/postgres';
                                                                                  if (fs.existsSync(direct + '/src/index.js')) return direct;
                                                                                    // Try to find in pnpm virtual store
                                                                                      const pnpmStore = '/app/node_modules/.pnpm';
                                                                                        if (fs.existsSync(pnpmStore)) {
                                                                                            const dirs = fs.readdirSync(pnpmStore).filter(d => d.startsWith('postgres@'));
                                                                                                if (dirs.length > 0) {
                                                                                                      return path.join(pnpmStore, dirs[0], 'node_modules', 'postgres');
                                                                                                          }
                                                                                                            }
                                                                                                              return null;
                                                                                                              }
                                                                                                              
                                                                                                              async function main() {
                                                                                                                const dbUrl = process.env.DATABASE_URL;
                                                                                                                  if (!dbUrl) { process.stderr.write('ERROR: DATABASE_URL not set\n'); process.exit(1); }
                                                                                                                  
                                                                                                                    const publicUrl = (process.env.PAPERCLIP_PUBLIC_URL || process.env.PAPERCLIP_AUTH_PUBLIC_BASE_URL || process.env.BETTER_AUTH_URL || 'http://localhost:3100').replace(/\/+$/, '');
                                                                                                                    
                                                                                                                      const pgPath = await findPostgres();
                                                                                                                        if (!pgPath) { process.stderr.write('ERROR: postgres package not found\n'); process.exit(1); }
                                                                                                                        
                                                                                                                          process.stderr.write('[bootstrap] Found postgres at: ' + pgPath + '\n');
                                                                                                                            const postgres = require(pgPath);
                                                                                                                              const sql = postgres(dbUrl, { max: 1, idle_timeout: 10, connect_timeout: 10 });
                                                                                                                              
                                                                                                                                try {
                                                                                                                                    // Check if admin already exists
                                                                                                                                        const admins = await sql\`SELECT id FROM instance_user_roles WHERE role = \${'instance_admin'} LIMIT 1\`;
                                                                                                                                            if (admins.length > 0) {
                                                                                                                                                  process.stdout.write('ALREADY_BOOTSTRAPPED\n');
                                                                                                                                                        return;
                                                                                                                                                            }
                                                                                                                                                            
                                                                                                                                                                // Revoke existing pending bootstrap invites
                                                                                                                                                                    await sql\`UPDATE invites SET revoked_at = NOW(), updated_at = NOW() WHERE invite_type = \${'bootstrap_ceo'} AND revoked_at IS NULL AND accepted_at IS NULL AND expires_at > NOW()\`;
                                                                                                                                                                    
                                                                                                                                                                        // Create new invite token
                                                                                                                                                                            const token = 'pcp_bootstrap_' + crypto.randomBytes(24).toString('hex');
                                                                                                                                                                                const tokenHash = crypto.createHash('sha256').update(token).digest('hex');
                                                                                                                                                                                    const expiresAt = new Date(Date.now() + 72 * 60 * 60 * 1000);
                                                                                                                                                                                    
                                                                                                                                                                                        await sql\`INSERT INTO invites (invite_type, token_hash, allowed_join_types, expires_at, invited_by_user_id) VALUES (\${'bootstrap_ceo'}, \${tokenHash}, \${'human'}, \${expiresAt}, \${'system'})\`;
                                                                                                                                                                                        
                                                                                                                                                                                            const inviteUrl = publicUrl + '/invite/' + token;
                                                                                                                                                                                                process.stdout.write(inviteUrl + '\n');
                                                                                                                                                                                                  } finally {
                                                                                                                                                                                                      await sql.end({ timeout: 5 }).catch(() => {});
                                                                                                                                                                                                        }
                                                                                                                                                                                                        }
                                                                                                                                                                                                        
                                                                                                                                                                                                        main().catch(err => {
                                                                                                                                                                                                          process.stderr.write('ERROR: ' + err.message + '\n' + (err.stack || '') + '\n');
                                                                                                                                                                                                            process.exit(1);
                                                                                                                                                                                                            });
                                                                                                                                                                                                            " > /tmp/bootstrap_url.txt 2>/tmp/bootstrap_err.txt
                                                                                                                                                                                                            node_exit=$?
                                                                                                                                                                                                            
                                                                                                                                                                                                            bootstrap_err="$(cat /tmp/bootstrap_err.txt 2>/dev/null || true)"
                                                                                                                                                                                                            bootstrap_url="$(cat /tmp/bootstrap_url.txt 2>/dev/null | tr -d '\n' || true)"
                                                                                                                                                                                                            
                                                                                                                                                                                                            if [ -n "${bootstrap_err}" ]; then
                                                                                                                                                                                                              echo "[bootstrap] Node output: ${bootstrap_err}"
                                                                                                                                                                                                              fi
                                                                                                                                                                                                              
                                                                                                                                                                                                              echo ""
                                                                                                                                                                                                              echo "╔══════════════════════════════════════════════════════════════════════════╗"
                                                                                                                                                                                                              echo "║               PAPERCLIP ADMIN INVITE URL                               ║"
                                                                                                                                                                                                              echo "╠══════════════════════════════════════════════════════════════════════════╣"
                                                                                                                                                                                                              
                                                                                                                                                                                                              if [ "${node_exit}" -eq 0 ] && echo "${bootstrap_url}" | grep -q "http"; then
                                                                                                                                                                                                                printf "║  %-72s║\n" "${bootstrap_url}"
                                                                                                                                                                                                                  echo "╚══════════════════════════════════════════════════════════════════════════╝"
                                                                                                                                                                                                                    echo ""
                                                                                                                                                                                                                      echo "[bootstrap] Open the invite URL above in your browser to create the first admin account."
                                                                                                                                                                                                                        echo "[bootstrap] The URL expires in 72 hours."
                                                                                                                                                                                                                        elif [ "${node_exit}" -eq 0 ] && echo "${bootstrap_url}" | grep -q "ALREADY_BOOTSTRAPPED"; then
                                                                                                                                                                                                                          printf "║  %-72s║\n" "Admin already exists - instance is ready."
                                                                                                                                                                                                                            echo "╚══════════════════════════════════════════════════════════════════════════╝"
                                                                                                                                                                                                                            else
                                                                                                                                                                                                                              printf "║  %-72s║\n" "ERROR: Failed to generate invite URL (exit ${node_exit})"
                                                                                                                                                                                                                                echo "╚══════════════════════════════════════════════════════════════════════════╝"
                                                                                                                                                                                                                                  echo "[bootstrap] URL output: ${bootstrap_url}"
                                                                                                                                                                                                                                  fi

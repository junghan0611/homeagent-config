#!/usr/bin/env bash
# smhub/tune.sh — apply the low-spec tuning this board needs, reproducibly.
#
# WHY THIS EXISTS. The vendor ships zigbee2mqtt with stock settings and covers
# the consequences with a restart ladder (Z2M_WATCHDOG, upstream index.js:9-21)
# rather than tuning for one core and 488M. On this board that shows up as
# ASH_NCP_FATAL_ERROR during pairing: the interview burst pins the single core,
# the host's ACKs go out late, and the NCP gives up (docs: smhub/RUNBOOK.md §6.5).
#
# So this file is the tuning, in the repo, applied by script instead of by hand.
# It is idempotent, it says what it changed, and `--revert` undoes all of it.
# The vendor's own files are never edited: the OpenRC env goes into a NEW file
# at /etc/conf.d/zigbee2mqtt (which openrc-run sources by design), and the yaml
# is edited in place so its owner survives (a redirect+mv makes it root-owned
# and z2m then dies with EACCES on the next join -- learned the hard way).
#
# ⚠️ THIS IS NOT OWNED BY THE .ipk. A factory reset or a vendor OTA that rewrites
# these paths drops it, and re-running this script is the recovery. Making the
# image or an idempotent postinst own it is issue #8's axis, not this script's.
#
# Usage:
#   SMHUB_SSH=smlight@<device> ./smhub/tune.sh            # apply
#   SMHUB_SSH=smlight@<device> ./smhub/tune.sh --revert   # undo
#   SMHUB_SSH=smlight@<device> ./smhub/tune.sh --show     # report only, no change
#   SMHUB_SSH=smlight@<device> ./smhub/tune.sh --ash-on   # ASH observation window ON
#   SMHUB_SSH=smlight@<device> ./smhub/tune.sh --ash-off  # ...and back to the tuned baseline
#
# ASH OBSERVATION (--ash-on / --ash-off, added 2026-09-14).
#   The hourly [ASH COUNTERS] / [NCP COUNTERS] lines are logger.info calls
#   (emberAdapter.js:135,550 on the device's herdsman 10.8.0), so at
#   `log_level: warning` they do not exist -- the tuning above deliberately
#   hides the one diagnostic this board needs. These two modes own that
#   trade-off instead of leaving it to a hand edit.
#
#   ⚠️ --ash-on raises log_level ONLY. It also *forces* log_output back to
#   [console] if something added `file`, because console lands on /tmp (tmpfs)
#   while the file sink lands on /mnt/user (eMMC) -- a blocking write on the
#   loop that owes the NCP an ACK, on flash. That is the invariant the header
#   above calls "so the path does not move", and it was broken by hand once
#   (2026-09-14, RUNBOOK §6.5.2c). The console sink already keeps the counters
#   in /tmp/zigbee2mqtt.log; the only thing `file` buys is surviving a reboot,
#   and that is not worth moving the write path.
#
#   ⛔ Do not leave --ash-on across a pairing burst. Measured: ~89 info lines in
#   the 30s before a crash at 17 devices, versus ~0 at 2 idle devices.
set -euo pipefail

REPO_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." &>/dev/null && pwd)"
SMHUB_SSH="${SMHUB_SSH:-}"
SMHUB_SSH_KEY="${SMHUB_SSH_KEY:-$REPO_DIR/.sshkey/id_ed25519}"
SUDO_PW="${SMHUB_SUDO_PW:-smlight}"     # vendor default; see PRIVATE.md
MODE="${1:-apply}"

[ -n "$SMHUB_SSH" ] || { echo "[tune] ERROR: SMHUB_SSH is not set (user@host)." >&2; exit 1; }

# --- what we set, and why. Each line is one lever with one reason. -----------
#
#  log_level: warning
#      logger.ts:192-199 skips the message lambda entirely below the level, so
#      formatting, colorize and the write syscall all disappear. At info this
#      board logged ~89 lines in the 30s before a crash, and stdout is a regular
#      file (/tmp, via /var/log symlink) which Node backs with SyncWriteStream
#      (is_main_thread.js:50-66) -- a blocking write on the very loop that owes
#      the NCP an ACK. Kept log_output at [console] so the path does not move.
#
#  --v8-pool-size=0
#      node_platform.cc:83-87 defaults the V8 worker pool to 4 and only consults
#      core count when the value is < 1. Four workers contending for one core is
#      pure loss; 0 resolves to 1.
#
#  --max-old-space-size=128 / --max-semi-space-size=2
#      Measured on the device: V8 sets heap_size_limit to 259 MB here, 53% of a
#      488 MB board, so it never feels pressure and defers collection until a
#      long stop-the-world. Smaller heap = shorter worst-case pause, which is
#      what ASH dies on (six consecutive misses, ash.ts:145-149 / consts.ts:29).
#      Upstream does the same thing below 600 MB (z2m index.js:84-90).
#
Z2M_YAML=/opt/zigbee2mqtt/data/configuration.yaml
CONF_D=/etc/conf.d/zigbee2mqtt
NODE_OPTS='--v8-pool-size=0 --max-old-space-size=128 --max-semi-space-size=2'

run() { ssh -i "$SMHUB_SSH_KEY" -o BatchMode=yes "$SMHUB_SSH" "$@"; }

# Ship the script, then run it. `sudo -S` reads the password from ITS stdin, so
# piping a heredoc into `... | sudo -S sh -s` feeds sudo and leaves the script
# unread -- the body silently never runs (learned 2026-09-08).
run_root() {
  local tmp="/tmp/.tune-$$.sh"
  ssh -i "$SMHUB_SSH_KEY" -o BatchMode=yes "$SMHUB_SSH" "cat > $tmp"
  ssh -i "$SMHUB_SSH_KEY" -o BatchMode=yes "$SMHUB_SSH" \
      "echo '$SUDO_PW' | sudo -S sh $tmp; rc=\$?; rm -f $tmp; exit \$rc"
}

show() {
  echo "[tune] current state on $SMHUB_SSH"
  run "
    echo '--- log_level / log_output'
    grep -E '^  log_level:|^  log_output:' $Z2M_YAML || echo '  (none)'
    sed -n '/^  log_output:/,+2p' $Z2M_YAML | grep -E '^    -' || true
    echo '--- adapter_concurrent'
    grep -E '^  adapter_concurrent:' $Z2M_YAML || echo '  (unset -> ember default 16)'
    echo '--- $CONF_D'
    [ -f $CONF_D ] && cat $CONF_D || echo '  (absent -> no NODE_OPTIONS)'
    echo '--- yaml owner (must be smlight)'
    ls -l $Z2M_YAML
    echo '--- running NODE_OPTIONS'
    P=\$(pgrep -f '^/opt/bin/node /opt/bin/zigbee2mqtt' | head -1)
    [ -n \"\$P\" ] && (tr '\\0' '\\n' < /proc/\$P/environ 2>/dev/null | grep '^NODE_OPTIONS=' || echo '  (not in env / unreadable)')
  "
}

if [ "$MODE" = "--show" ]; then show; exit 0; fi

# --- ASH observation window ---------------------------------------------------
# Owns exactly two things: log_level, and the log_output path invariant.
# Everything else (NODE_OPTIONS, adapter_concurrent) is left as it is.
if [ "$MODE" = "--ash-on" ] || [ "$MODE" = "--ash-off" ]; then
  if [ "$MODE" = "--ash-on" ]; then LVL=info; else LVL=warning; fi
  echo "[tune] ASH observation -> log_level: $LVL  on $SMHUB_SSH"
  run_root <<EOS
set -e
cp -a $Z2M_YAML $Z2M_YAML.bak-ash-\$(date +%s)

if grep -q '^  log_level:' $Z2M_YAML; then
  sed -i 's/^  log_level: .*/  log_level: $LVL/' $Z2M_YAML
else
  sed -i '/^advanced:/a\  log_level: $LVL' $Z2M_YAML
fi

# The path invariant: console only. A stray 'file' sink moves writes to eMMC.
if grep -q '^    - file\$' $Z2M_YAML; then
  sed -i '/^    - file\$/d' $Z2M_YAML
  echo "  removed log_output 'file' sink (path invariant: console/tmpfs only)"
fi

chown smlight:smlight $Z2M_YAML
rc-service zigbee2mqtt restart >/dev/null 2>&1
EOS
  echo "[tune] restarted; waiting for z2m"
  for _ in $(seq 1 30); do
    run 'ss -ltn | grep -qw 8080' 2>/dev/null && break
    sleep 5
  done
  show
  echo
  if [ "$MODE" = "--ash-on" ]; then
    echo "[tune] first [ASH COUNTERS] lands one hour after adapter start, not on the clock hour."
    echo "[tune]   read:  grep -o '\[ASH COUNTERS\].*' /var/log/zigbee2mqtt.log"
    echo "[tune]   ⛔ turn this off before a pairing burst:  ./smhub/tune.sh --ash-off"
  fi
  exit 0
fi

if [ "$MODE" = "--revert" ]; then
  echo "[tune] reverting on $SMHUB_SSH"
  run_root <<EOS
set -e
[ -f $CONF_D ] && rm -f $CONF_D && echo "  removed $CONF_D"
sed -i 's/^  log_level: warning\$/  log_level: info/' $Z2M_YAML
chown smlight:smlight $Z2M_YAML
rc-service zigbee2mqtt restart >/dev/null 2>&1
echo "  z2m restarted"
EOS
  sleep 30; show; exit 0
fi

echo "[tune] applying on $SMHUB_SSH"
run_root <<EOS
set -e
cp -a $Z2M_YAML $Z2M_YAML.bak-tune-\$(date +%s)

# 1. log level -- in place, so the owner is preserved
if grep -q '^  log_level:' $Z2M_YAML; then
  sed -i 's/^  log_level: .*/  log_level: warning/' $Z2M_YAML
else
  sed -i '/^advanced:/a\\  log_level: warning' $Z2M_YAML
fi

# 2. OpenRC env -- a NEW file openrc-run sources; the vendor init is untouched
cat > $CONF_D <<'CONF'
# homeagent-config: low-spec tuning for one core / 488M. See smhub/tune.sh.
# Remove this file and restart zigbee2mqtt to revert.
export NODE_OPTIONS='$NODE_OPTS'
CONF
chmod 0644 $CONF_D

chown smlight:smlight $Z2M_YAML
rc-service zigbee2mqtt restart >/dev/null 2>&1
EOS

echo "[tune] restarted; waiting for z2m to come back"
for _ in $(seq 1 30); do
  run 'ss -ltn | grep -qw 8080' 2>/dev/null && break
  sleep 5
done
show
echo
echo "[tune] verdict: NODE_OPTIONS must appear in the running env above."
echo "[tune] revert:  SMHUB_SSH=$SMHUB_SSH ./smhub/tune.sh --revert"

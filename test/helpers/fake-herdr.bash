# A fake herdr at HERDR_BIN_PATH that answers from files under $HOME/fake: no server, and no
# call reaches any herdr. Load it after common.bash and call fake_herdr after isolate.
# A call no reply answers fails the test: it exits 97 and lands in guard-refusals, which
# unisolate reports.

# fake_herdr: installs the fake and answers the two calls every script makes.
fake_herdr() {
  mkdir -p "$HOME/fake"
  cat > "$HOME/fake/herdr" <<'FAKE'
#!/usr/bin/env bash
d="$HOME/fake"
n=$(( $(cat "$d/n" 2>/dev/null || echo 0) + 1 )); echo "$n" > "$d/n"
echo "$*" >> "$d/calls"
for k in "$n" "${1:-}_${2:-}_${3:-}" "${1:-}_${2:-}" default; do
  [ -e "$d/$k.rc" ] && break
  k=""
done
if [ -z "$k" ]; then
  echo "fake herdr: no reply for 'herdr $*'" >&2
  echo "herdr $*: no reply" >> "$HOME/guard-refusals"
  exit 97
fi
rc=$(cat "$d/$k.rc")
if [ "$rc" = 0 ]; then cat "$d/$k.out"; else cat "$d/$k.out" >&2; fi
exit "$rc"
FAKE
  chmod +x "$HOME/fake/herdr"
  export HERDR_BIN_PATH="$HOME/fake/herdr"
  reply plugin_config-dir 0 ''
  reply notification_show 0 ''
}

# reply <call number | command words joined by _ (three, or two) | default> <exit code> <text>:
# what the fake answers, looked up in that order.
reply() { printf '%s\n' "$3" > "$HOME/fake/$1.out"; echo "$2" > "$HOME/fake/$1.rc"; }

# calls: every call the fake got, one per line.
calls() { cat "$HOME/fake/calls" 2>/dev/null || true; }

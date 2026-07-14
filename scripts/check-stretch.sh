#!/bin/bash
# backprompt — props your back by running in the backdrop of your prompts.
# Zero-token stretch reminders for Claude Code.
#
# Runs on UserPromptSubmit and SessionStart. Every invocation is an
# "activity ping" used to estimate continuous desk time; when a stretch
# is due, one pre-rendered card is emitted as a hook systemMessage
# (shown to the user, never added to model context).
#
# Contract: this script must never block or break a session — every
# path exits 0, and any unexpected failure means "no card this time".

BP_DIR="${BACKPROMPT_DIR:-$HOME/.backprompt}"
PLUGIN_ROOT="$(cd "$(dirname "$0")/.." && pwd)" || exit 0
CARDS_DIR="$PLUGIN_ROOT/cards"

# "now" = on-demand (/backprompt:now): skip all timing checks, always show
# a card, print plain text instead of hook JSON. Also works while paused —
# an explicit request outranks the kill switch.
MODE="${1:-hook}"

# Hard kill switch: `touch ~/.backprompt/off` pauses everything ambient.
[ "$MODE" != "now" ] && [ -e "$BP_DIR/off" ] && exit 0

mkdir -p "$BP_DIR" 2>/dev/null || exit 0

# ---- defaults (override with KEY=VALUE lines in ~/.backprompt/config) ----
MIN_DESK_MINUTES=50    # continuous desk time before the first card
INTERVAL_MINUTES=120   # desk time between cards
GAP_RESET_MINUTES=25   # an activity gap this long counts as a real break
COLOR=1                # set COLOR=0 if your terminal shows garbage codes

[ -f "$BP_DIR/config" ] && . "$BP_DIR/config" 2>/dev/null
[ -n "${NO_COLOR:-}" ] && COLOR=0
# On-demand output may be piped into a transcript — only color a real tty.
[ "$MODE" = "now" ] && [ ! -t 1 ] && COLOR=0

if [ "$COLOR" = "1" ]; then
  E=$(printf '\033')
  C_BORDER="${E}[38;5;73m"    # muted teal frame
  C_ART="${E}[38;5;222m"      # blond, obviously
  C_TITLE="${E}[1;38;5;220m"  # bold gold title
  C_DIM="${E}[38;5;245m"      # gray footer
  C_RESET="${E}[0m"
else
  C_BORDER=""; C_ART=""; C_TITLE=""; C_DIM=""; C_RESET=""
fi

NOW=$(date +%s)

# ---- state ----
LAST_PING=0
DESK_START=$NOW
LAST_CARD=0
CORE_INDEX=0
EXTRA_INDEX=0
POOL="core"
INTRO_SHOWN=0
[ -f "$BP_DIR/state" ] && . "$BP_DIR/state" 2>/dev/null

# One reminder across many parallel sessions: a lock directory arbitrates.
# If another session holds a fresh lock, it owns this ping — bail quietly.
LOCK="$BP_DIR/lock"
if ! mkdir "$LOCK" 2>/dev/null; then
  if [ -n "$(find "$LOCK" -maxdepth 0 -mmin +2 2>/dev/null)" ]; then
    rmdir "$LOCK" 2>/dev/null
    mkdir "$LOCK" 2>/dev/null || exit 0
  else
    exit 0
  fi
fi
trap 'rmdir "$LOCK" 2>/dev/null' EXIT

save_state() {
  {
    echo "LAST_PING=$LAST_PING"
    echo "DESK_START=$DESK_START"
    echo "LAST_CARD=$LAST_CARD"
    echo "CORE_INDEX=$CORE_INDEX"
    echo "EXTRA_INDEX=$EXTRA_INDEX"
    echo "POOL=$POOL"
    echo "INTRO_SHOWN=$INTRO_SHOWN"
  } > "$BP_DIR/state.tmp" 2>/dev/null && mv -f "$BP_DIR/state.tmp" "$BP_DIR/state" 2>/dev/null
}

# The mascot rides along on every card. Loaded once; passed to awk via the
# environment because `awk -v` mangles the backslashes ASCII art is made of.
MASCOT_CONTENT=$(cat "$CARDS_DIR/mascot.art" 2>/dev/null)

# Render a text file (title line + instructions) into a framed, colored
# block with the mascot. Narrow mascots (≤30 cols) sit beside the text;
# wide ones go on top with the text below. A leading blank line drops the
# frame below the "hook says:" prefix Claude Code prepends to systemMessages.
# args: $1 = text file (or - for stdin), $2 = header, $3 = footer
render_card() {
  MASCOT_ART="$MASCOT_CONTENT" awk \
      -v cb="$C_BORDER" -v ca="$C_ART" -v ct="$C_TITLE" -v cd="$C_DIM" -v r="$C_RESET" \
      -v header="$2" -v footer="$3" '
    BEGIN {
      nart = split(ENVIRON["MASCOT_ART"], art, "\n")
      aw = 6
      for (i = 1; i <= nart; i++) if (length(art[i]) > aw) aw = length(art[i])
    }
    { body[++nbody] = $0 }
    END {
      print ""
      print cb "╭─ " r ct "backprompt" r cb " ── " header " ─────────────╴" r
      print cb "│" r
      if (aw > 30) {
        for (i = 1; i <= nart; i++)
          print cb "│" r "  " ca art[i] r
        print cb "│" r
        for (i = 1; i <= nbody; i++) {
          col = (i == 1) ? ct : r
          print cb "│" r "  " col body[i] r
        }
      } else {
        n = (nart > nbody) ? nart : nbody
        for (i = 1; i <= n; i++) {
          a = (i <= nart) ? art[i] : ""
          b = (i <= nbody) ? body[i] : ""
          col = (i == 1) ? ct : r
          printf "%s│%s  %s%-*s%s  %s%s%s\n", cb, r, ca, aw, a, r, col, b, r
        }
      }
      print cb "│" r
      print cb "╰─╴ " cd footer r
    }
  ' "$1"
}

# Emit $1 as {"systemMessage": "..."} — JSON output keeps the card out of
# the model's context (plain stdout on UserPromptSubmit would be injected).
# ESC bytes become \\u001b escapes so the JSON stays valid with colors embedded.
emit() {
  printf '%s\n' "$1" | awk '
    BEGIN { printf "{\"systemMessage\":\""; esc = sprintf("%c", 27) }
    { gsub(/\\/, "\\\\"); gsub(/"/, "\\\""); gsub(esc, "\\u001b"); printf "%s\\n", $0 }
    END { printf "\"}" }
  '
}

# A long silence since the last ping means a real break happened away from
# the desk — restart the sitting clock instead of nagging a rested human.
if [ "$LAST_PING" -gt 0 ] && [ $((NOW - LAST_PING)) -ge $((GAP_RESET_MINUTES * 60)) ]; then
  DESK_START=$NOW
fi
LAST_PING=$NOW

# First run ever: introduce yourself once, then stay quiet until due.
if [ "$INTRO_SHOWN" != "1" ] && [ "$MODE" != "now" ]; then
  INTRO_SHOWN=1
  save_state
  MSG=$(printf '%s\n' \
    'hi! one 30-second seated stretch' \
    'every couple hours of desk time —' \
    'shown while Claude is working and' \
    "you're waiting anyway." \
    | render_card - "props your back, runs in the backdrop" "pause anytime: touch ~/.backprompt/off")
  emit "$MSG"
  exit 0
fi

# ---- is a stretch due? (on-demand skips the wait) ----
if [ "$MODE" != "now" ]; then
  if [ $((NOW - DESK_START)) -lt $((MIN_DESK_MINUTES * 60)) ]; then save_state; exit 0; fi
  if [ "$LAST_CARD" -gt 0 ] && [ $((NOW - LAST_CARD)) -lt $((INTERVAL_MINUTES * 60)) ]; then save_state; exit 0; fi
fi

# Two pools, strict alternation: a core (spine/posture) card, then one
# extra (rest of the body), then core again. The plugin is named after
# your back — you are never more than one card away from a back stretch.
CORE_CARDS=("$CARDS_DIR"/core/*.txt)
EXTRA_CARDS=("$CARDS_DIR"/extras/*.txt)
[ -f "${CORE_CARDS[0]}" ] || CORE_CARDS=()
[ -f "${EXTRA_CARDS[0]}" ] || EXTRA_CARDS=()

CARD_FILE=""
if [ "$POOL" = "extras" ] && [ ${#EXTRA_CARDS[@]} -gt 0 ]; then
  CARD_FILE="${EXTRA_CARDS[$((EXTRA_INDEX % ${#EXTRA_CARDS[@]}))]}"
  EXTRA_INDEX=$(( (EXTRA_INDEX + 1) % ${#EXTRA_CARDS[@]} ))
  POOL="core"
elif [ ${#CORE_CARDS[@]} -gt 0 ]; then
  CARD_FILE="${CORE_CARDS[$((CORE_INDEX % ${#CORE_CARDS[@]}))]}"
  CORE_INDEX=$(( (CORE_INDEX + 1) % ${#CORE_CARDS[@]} ))
  POOL="extras"
elif [ ${#EXTRA_CARDS[@]} -gt 0 ]; then
  CARD_FILE="${EXTRA_CARDS[$((EXTRA_INDEX % ${#EXTRA_CARDS[@]}))]}"
  EXTRA_INDEX=$(( (EXTRA_INDEX + 1) % ${#EXTRA_CARDS[@]} ))
fi
if [ -z "$CARD_FILE" ]; then save_state; exit 0; fi

LAST_CARD=$NOW
save_state

if [ "$INTERVAL_MINUTES" -ge 60 ]; then
  NEXT_STR="~$((INTERVAL_MINUTES / 60))h"
else
  NEXT_STR="~${INTERVAL_MINUTES}m"
fi

if [ "$MODE" = "now" ]; then
  MSG=$(render_card "$CARD_FILE" "on-demand stretch" \
    "yes. · the ambient timer resets from here")
  printf '%s\n' "$MSG"
else
  MSG=$(render_card "$CARD_FILE" "free stretch break" \
    "yes. · next: after $NEXT_STR desk time · pause: touch ~/.backprompt/off")
  emit "$MSG"
fi

exit 0

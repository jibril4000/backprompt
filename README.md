# backprompt

**Props your back by running in the backdrop of your prompts.** (Say it
three times fast.)

A Claude Code plugin that shows you one 30-second seated stretch a few
times a day — timed for the moment you hit enter and Claude starts working,
i.e. time you were going to spend waiting anyway.

```
╭─ backprompt ── free stretch break ─────────────╴
│
│  ▓▓▓▓   ▓▓▓   ▓▓▓  ▓   ▓    ▓▓▓▓  ▓▓▓▓   ▓▓▓  ▓   ▓ ▓▓▓▓  ▓▓▓▓▓
│  ▓   ▓ ▓   ▓ ▓     ▓  ▓     ▓   ▓ ▓   ▓ ▓   ▓ ▓▓ ▓▓ ▓   ▓   ▓
│  ▓▓▓▓  ▓▓▓▓▓ ▓     ▓▓▓      ▓▓▓▓  ▓▓▓▓  ▓   ▓ ▓ ▓ ▓ ▓▓▓▓    ▓
│  ▓   ▓ ▓   ▓ ▓     ▓  ▓     ▓     ▓  ▓  ▓   ▓ ▓   ▓ ▓       ▓
│  ▓▓▓▓  ▓   ▓  ▓▓▓  ▓   ▓    ▓     ▓   ▓  ▓▓▓  ▓   ▓ ▓       ▓
│
│  SEATED TWIST · 30s
│  Sit tall, right hand to left knee. Twist left and
│  look over your shoulder. 15s, then switch sides.
│
╰─╴ yes. · next: after ~2h desk time · pause: touch ~/.backprompt/off
```

Rendered in color: teal frame, gold banner and title. Set `COLOR=0` in
`~/.backprompt/config` (or export `NO_COLOR`) for plain text.

## Design principles

- **Zero tokens.** Everything runs as local hook scripts with pre-rendered
  cards. The model is never invoked; cards are shown via `systemMessage`,
  which is never added to Claude's context.
- **Zero interruption.** Cards appear right after you submit a prompt, while
  Claude churns — stretching costs you no productivity.
- **Zero guilt.** Ignoring a card *is* the snooze. No streaks, no
  confirmations, no nagging.
- **Sitting-time aware.** Reminders trigger on accumulated *desk time*, not
  wall-clock time. Walk away for 25+ minutes and the sitting clock resets —
  you already took a break.
- **Never breaks your session.** The hook script exits 0 on every path.

## Defaults

| Behavior | Default |
|---|---|
| First card after | 50 min of continuous desk time |
| Between cards | 2 h of desk time |
| Break detection | 25 min activity gap resets the sitting clock |

No daily cap and no "active hours" — if you're at the desk, you've earned
the stretch, whatever the clock says. The desk-time interval is the only
rate limit, and it's the honest one.

## Install

```
/plugin marketplace add /path/to/spine
/plugin install backprompt@backprompt-market
/reload-plugins
```

Or for a single-session test drive: `claude --plugin-dir /path/to/spine`

On first run you'll get a one-time hello card; after that it stays quiet
until a stretch is actually due.

## Configure

Optional — create `~/.backprompt/config` with any of:

```bash
MIN_DESK_MINUTES=50
INTERVAL_MINUTES=120
GAP_RESET_MINUTES=25
COLOR=1
```

## Pause / resume

```bash
touch ~/.backprompt/off   # pause — no commands, no tokens
rm ~/.backprompt/off      # resume
```

## The deck

19 cards in two pools that **strictly alternate**: one `core` card
(spine/posture — twists, cat-cow, chest opener, forward fold, chin tucks,
hips), then one `extras` card (wrists, hands, shoulders, hamstrings,
ankles, eyes, breathing, glutes), then core again. The plugin is named
after your back: you are never more than one card away from a back
stretch, no matter how big the deck grows.

## Add your own stretches

Drop a `.txt` file in `cards/core/` (spine/posture) or `cards/extras/`
(everything else) — first line is the title, the rest is the instructions
(keep lines under ~50 characters). Each pool rotates in filename order.

```
REACH & LEAN · 30s
Interlace fingers, palms to the ceiling, reach
tall. Lean left 15s, then right 15s.
```

## Change the banner

The art in `cards/mascot.art` appears on every card. Replace it with any
ASCII art. Narrow art (≤30 columns) sits beside the instructions; wider
art goes on top with the instructions below.

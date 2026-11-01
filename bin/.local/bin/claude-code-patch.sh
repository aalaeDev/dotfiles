#!/usr/bin/env bash

# Keeps Claude Code clean in Code OSS. Updates replace all of these files, so a systemd path unit
# runs this again after each one (systemd/.config/systemd/user/claude-code-patch.path).
#   - Appends claude-webview.css to the extension's webview stylesheet
#   - Lets Filetree draw on the vscode surface, which it skips upstream
#   - Draws Skins' usage band as bars and quiets its tables, and makes the orange logo neutral
#   - Gives Savvy Progress a slim expandable bar above the prompt, for main steps and subagents
#   - Groups the chat under those steps: claude-webview.js
#
#   claude-code-patch.sh            Apply to every installed version; changes nothing if already applied
#   claude-code-patch.sh --restore  Take the stylesheet back out and undo the mod patches
#   claude-code-patch.sh --skin     Make the matugen palette the active Skins skin (matugen post_hook)

set -uo pipefail

# --- Configuration ---
CSS="$HOME/dotfiles/Code/.config/Code/claude-webview.css"
JS="$HOME/dotfiles/Code/.config/Code/claude-webview.js"
EXTENSIONS="$HOME/.vscode-oss/extensions"
PLUGINS="$HOME/.claude/plugins"
SKIN_PALETTE="$HOME/.cache/claude-skin.json"
BEGIN="/* dotfiles:claude-webview begin */"
END="/* dotfiles:claude-webview end */"

# upstream text, then ours. A line that matches neither means upstream moved on
FILETREE_PATCHES=(
    "if (e.surface !== 'terminal' && e.surface !== 'desktop') return next(e)"
    "if (e.surface !== 'terminal' && e.surface !== 'desktop' && e.surface !== 'vscode') return next(e)"
    "(noNerd || e.surface === 'desktop'))"
    "(noNerd || e.surface === 'desktop' || e.surface === 'vscode'))"
    "const light = !themeMtime && e.surface !== 'desktop' && lightTerminal"
    "const light = !themeMtime && e.surface !== 'desktop' && e.surface !== 'vscode' && lightTerminal"
    "nativeScroll = e.surface === 'desktop'"
    "nativeScroll = e.surface === 'desktop' || e.surface === 'vscode'"
    "(e.surface === 'desktop' ? 3 : 2)"
    "(e.surface === 'desktop' || e.surface === 'vscode' ? 3 : 2)"
)
# Skins' usage band: thin bars like the sidebar's, instead of rings
SKINS_PATCHES=(
    'const content = (meter: Meter) => RING_R * 2 + 12 + measure(meterText(meter), false, TEXT_SIZE)'
    'const content = (meter: Meter) => Math.max(110, 8 + measure(meterText(meter), false, TEXT_SIZE))'
    'const x = (starts[i] ?? 0) + RING_R + 4'
    'const x = (starts[i] ?? 0) + 2, barWidth = (widths[i] ?? 0) - 8'
    '`<circle cx="${x}" cy="15" r="${RING_R}" fill="none" stroke="${palette.muted}" stroke-opacity=".25" stroke-width="3"/>`,'
    '`<rect x="${x}" y="20" width="${barWidth}" height="4" rx="2" fill="${palette.muted}" fill-opacity=".18"/>`,'
    '`<circle class="fill" cx="${x}" cy="15" r="${RING_R}" fill="none" stroke="${color}" stroke-width="3" stroke-linecap="round" stroke-dasharray="${filled} ${circumference}" transform="rotate(-90 ${x} 15)" style="--len:${filled}"/>`,'
    '`<rect x="${x}" y="20" width="${(barWidth * meter.percent) / 100}" height="4" rx="2" fill="${color}"/>`,'
    '`<text x="${x + RING_R + 8}" y="19.5" font-size="${TEXT_SIZE}">'
    '`<text x="${x}" y="13" font-size="${TEXT_SIZE}">'
)
# Skins' text tables: a quiet frame and header, no zebra rows. Outside the terminal the browser wraps
# cells, because counting characters would break words in its proportional font
TABLE_PATCHES=(
    '<Box flexDirection="column" borderStyle="round" borderColor={palette.muted}>'
    '<Box flexDirection="column" borderStyle="round" borderColor={palette.surface}>'
    '{rows.map((cells, i) => row(cells, false, i % 2 === 1 ? palette.zebra : undefined))}'
    '{rows.map(cells => row(cells, false, undefined))}'
    '{wrapLines(cell, widths[i] ?? 0, Infinity).map(line => ('
    '{(look.svg === undefined ? wrapLines(cell, widths[i] ?? 0, Infinity) : [cell]).map(line => ('
    '<Text color={palette.fg} bold={isHeader} wrap="truncate-end">'
    "<Text color={isHeader ? palette.muted : palette.fg} bold={isHeader && look.svg === undefined} wrap={look.svg === undefined ? 'truncate-end' : 'wrap'}>"
)
# Skins' usage band: collapsible, with a quiet Compact. The state lasts between sessions
BAND_PATCHES=(
    'export function usageBand(look: Look, meters: readonly Meter[], canCompact: boolean, compact: () => void) {'
    'export function usageBand(look: Look, meters: readonly Meter[], canCompact: boolean, compact: () => void, collapse?: { open: boolean; toggle: () => void }) {'
    '<Box flexDirection="row" alignItems="center" columnGap={2} paddingRight={5}>'
    '<Box flexDirection="row" alignItems="center" columnGap={2} paddingRight={look.svg === undefined ? 5 : 0}>
      {collapse === undefined ? (
        ""
      ) : (
        <Button key={collapse.open ? "usage-open" : "usage-closed"} label={collapse.open ? "▾" : "▸"} plain dimColor onPress={collapse.toggle} />
      )}'
    '{meterView(look, meters)}'
    '{meterView(look, collapse?.open === false ? meters.filter(meter => meter.label === "context") : meters)}'
    '{canCompact && isNudge ? <Text'
    '{canCompact && isNudge && look.svg === undefined ? <Text'
    'const builds = meters.map(meter => ({ meter, built: usageSvg([meter], palette, true) }))'
    'const { Box } = look.ui

    return meters.map(meter => (
      <Box key={`usage-${meter.label}`} flexGrow={1} width={0} minWidth={12} flexDirection="column">
        <Box flexDirection="row" flexWrap="nowrap" justifyContent="space-between" columnGap={1}>
          <Text color={palette.muted} wrap="truncate-end">
            {`${meter.label === "context" ? "Context" : meter.label}${meter.resets === undefined ? "" : ` · ${meter.resets}`}`}
          </Text>
          <Text color={palette.fg}>{`${meter.percent}%`}</Text>
        </Box>
        <Box width="100%" height={0.25} marginTop={0.25} overflow="hidden" flexDirection="column">
          <Box width={`${meter.percent}%`} height={0.25} backgroundColor={meter.percent >= 80 ? palette.err : palette.user} />
        </Box>
      </Box>
    ))
    const builds = meters.map(meter => ({ meter, built: usageSvg([meter], palette, true) }))'
)
BAND_STATE_PATCHES=(
    'const kind = kindOf(e.props.tool)'
    'if (e.props.tool === "mcp__claude-widget__step" && e.surface !== "terminal") {
      const { Text } = $.ui.resolve(e)
      const input = (e.props.input ?? {}) as { done?: number; total?: number; note?: string }
      stepTotal = input.total ?? stepTotal
      const done = input.done ?? 0
      return done >= stepTotal && stepTotal > 0 ? (
        <Text dimColor>Steps done</Text>
      ) : (
        <Text>
          <Text bold>{`Step ${done + 1}/${stepTotal || "?"}`}</Text>
          {input.note ? `  ${input.note}` : ""}
        </Text>
      )
    }

    const kind = kindOf(e.props.tool)'
    'const usageAtom = atom('
    'let stepTotal = 0
const bandOpenAtom = atom({ plugin: "skins", key: "bandOpen" } as const, true)
const usageAtom = atom('
    'await update($, customAtom, () => custom)'
    'const storedBandOpen = (await $.store.get("bandOpen")) !== false
  await update($, bandOpenAtom, () => storedBandOpen)
  await update($, customAtom, () => custom)'
    'const isCompacting = await read($, compactingAtom)'
    'const isCompacting = await read($, compactingAtom)
    const bandOpen = await read($, bandOpenAtom)'
    'active.prefs.compact && !e.props.isWorking && !isCompacting, compact)'
    'active.prefs.compact && !e.props.isWorking && !isCompacting, compact, {
          open: bandOpen,
          toggle: () => {
            void update($, bandOpenAtom, () => !bandOpen)
            void $.store.set("bandOpen", !bandOpen)
          },
        })'
)
# Savvy Progress: outside the terminal, a slim bar for my main steps and any subagents. A savvy-flow
# keeps its own row. VS Code reports itself as desktop in this slot, so this can't test for vscode
SAVVY_BAND=$(cat <<'TSX'
const BAND_LINGER_MS = 20_000
const BAND_GROUP_GAP_MS = 60_000
const MAIN_STEP_TOOL = 'mcp__claude-widget__step'
type MainSteps = { done: number; total: number; notes: string[]; at: number }
const mainSteps = atom({ plugin: 'savvy-progress', key: 'mainSteps' } as const, null)
let bandAccent = ''
let bandHideTimer = false
const ESTIMATE_MIN_SAMPLES = 10
const ESTIMATE_TAU_S = 60
let turnStart: number | null = null
let turnHistory: number[] = []
let turnTick = false

// Keeps the elapsed time live. Started from an event, as Savvy's own clock is: work a draw starts may
// not outlast the draw. Writing the clock is what redraws the band, because the band reads it
function startTurnTick($: EngineInterface): void {
  if (turnTick) return
  turnTick = true
  $.clock.every(1000, () => {
    if (turnStart === null) return
    void (async () => {
      const at = await $.clock.now()
      await update($, now, () => at)
    })()
  })
}

// Seconds per finished turn, written by claude-widget.sh for the Waybar pill
async function loadTurnHistory($: EngineInterface): Promise<void> {
  try {
    const home = await $.env.get('HOME')
    const cache = (await $.env.get('XDG_CACHE_HOME')) || `${home}/.cache`
    const text = String(await $.fs.read(`${cache}/rice/claude-turns`))
    turnHistory = text.split('\n').filter(Boolean).map(Number).filter(Number.isFinite)
  } catch {
    turnHistory = []
  }
}

// The same estimate as the pill in claude-widget.sh: with enough history, the share of past turns already
// over by now; without, a curve that slows as it rises. In steps of 5, and never past 95
function estimatePercent(elapsedS: number): number {
  const raw =
    turnHistory.length >= ESTIMATE_MIN_SAMPLES
      ? (turnHistory.filter(t => t <= elapsedS).length / turnHistory.length) * 100
      : (1 - Math.exp(-elapsedS / ESTIMATE_TAU_S)) * 100
  return Math.min(95, Math.round(raw / 5) * 5)
}

// The wallpaper's accent, from the palette matugen writes for Skins
async function bandColor($: EngineInterface): Promise<string> {
  if (bandAccent) return bandAccent
  bandAccent = ACCENT
  try {
    const palette = JSON.parse(String(await $.fs.read(`${await $.env.get('HOME')}/.cache/claude-skin.json`)))
    if (typeof palette.user === 'string') bandAccent = palette.user
  } catch {}
  return bandAccent
}

// The latest run of agents: an agent that started long after the others ended begins a new one
function bandGroup(list: readonly AgentRun[]): AgentRun[] {
  const sorted = [...list].sort((a, b) => a.startedAt - b.startedAt)
  const group: AgentRun[] = []
  let earliest = Infinity
  for (const a of sorted.reverse()) {
    if (group.length > 0 && a.status !== 'running' && (a.endedAt ?? a.startedAt) < earliest - BAND_GROUP_GAP_MS) break
    group.unshift(a)
    earliest = Math.min(earliest, a.startedAt)
  }
  return group
}

async function recordMainStep($: EngineInterface, e: any): Promise<void> {
  if (e.agentId) return
  const input = e.input ?? e
  const at = await $.clock.now()
  await update($, mainSteps, (prev: MainSteps | null) => {
    const done = typeof input.done === 'number' ? input.done : (prev?.done ?? 0)
    const total = typeof input.total === 'number' ? input.total : (prev?.total ?? 0)
    const fresh = prev === null || done === 0 || done < prev.done
    const notes = fresh ? [] : [...prev.notes]
    if (typeof input.note === 'string' && input.note && notes.at(-1) !== input.note && done < total) notes.push(input.note)
    return { done, total, notes, at }
  })
  }

// A slim line above the prompt, like the Claude card in the notification center: my main steps, then
// any subagents. The chevron opens both into rows.
async function agentsBand($: EngineInterface, e: any, next: (e: any) => unknown) {
  const drawn: any = await Promise.resolve(next(e)).catch(() => null)
  const below = drawn && typeof drawn === 'object' && drawn.type !== 'engine' ? drawn : null
  const p: any = await read($, panel)
  const group = bandGroup((await read($, agents)).filter((a: AgentRun) => a.startedAt > (p.bandHiddenAt ?? 0)))
  const at = await $.clock.now()
  const running = group.filter(a => a.status === 'running')
  const lastEnd = Math.max(0, ...group.map(a => a.endedAt ?? 0))
  await read($, now)
  const stored = (await read($, mainSteps)) as MainSteps | null
  const stepsDone = stored !== null && stored.total > 0 && stored.done >= stored.total
  const steps = stored !== null && stored.total > 0 && stored.at > (p.bandHiddenAt ?? 0) && (!stepsDone || at - stored.at <= BAND_LINGER_MS) ? stored : null
  const agentsShown = group.length > 0 && (running.length > 0 || Boolean(p.bandOpen) || at - lastEnd <= BAND_LINGER_MS)
  const isWorking = Boolean(e.props.isWorking)
  if (!isWorking) turnStart = null
  else if (turnStart === null) {
    turnStart = at
    await loadTurnHistory($)
  }
  const estimating = steps === null && isWorking && turnStart !== null
  if (steps === null && !agentsShown && !estimating) return drawn
  if (((steps !== null && stepsDone) || (agentsShown && running.length === 0)) && !bandHideTimer) {
    bandHideTimer = true
    $.clock.after(BAND_LINGER_MS + 500, () => {
      bandHideTimer = false
      $.ui.invalidate('ui.render')
    })
  }

  const { Box, Text, Button } = $.ui.resolve(e) as any
  const color = await bandColor($)
  const open = Boolean(p.bandOpen)
  const toggle = () => update($, panel, (prev: any) => ({ ...prev, bandOpen: !prev.bandOpen }))
  const hide = () => update($, panel, (prev: any) => ({ ...prev, bandOpen: false, bandHiddenAt: at }))
  const line = (name: string, word: string, share: number, count: string, canHide: boolean, canOpen = true) => (
    <Box key={`dot-line-${name}`} flexDirection="row" flexWrap="nowrap" alignItems="center" columnGap={1}>
      {canOpen ? <Button key={`dot-${name}-${open ? 'open' : 'closed'}`} label={open ? '▾' : '▸'} plain dimColor onPress={toggle} /> : ''}
      <Box flexShrink={1}>
        <Text wrap="truncate-end">{word}</Text>
      </Box>
      <Box flexGrow={1} width={0} minWidth={8} height={0.25} overflow="hidden" flexDirection="column">
        <Box width={`${Math.round(Math.min(1, share) * 100)}%`} height={0.25} backgroundColor={color} />
      </Box>
      <Text dimColor>{count}</Text>
      {canHide ? <Button key={`dot-hide-${name}`} label="✕" plain dimColor onPress={hide} /> : ''}
    </Box>
  )
  const rows: unknown[] = []
  if (steps !== null) {
    const current = steps.notes.at(-1)
    rows.push(line('steps', stepsDone ? 'Steps done' : `Step ${steps.done + 1}/${steps.total}${current ? ` · ${current}` : ''}`, steps.done / steps.total, `${steps.done}/${steps.total}`, stepsDone))
    if (open) {
      steps.notes.forEach((note, i) => {
        const isDone = stepsDone || i < steps.notes.length - 1
        rows.push(
          <Box key={`dot-step-${i}`} flexDirection="row" columnGap={1} paddingLeft={4}>
            <Text color={isDone ? 'green' : color}>{isDone ? '✓' : '●'}</Text>
            <Text dimColor={isDone} wrap="truncate-end">{note}</Text>
          </Box>,
        )
      })
    }
  }
  // No steps reported: an estimate, marked ~ as on the pill. Nothing to expand
  if (estimating) {
    const percent = estimatePercent((at - (turnStart as number)) / 1000)
    rows.push(line('work', `Working · ${fmtTime(at - (turnStart as number))}`, percent / 100, `~${percent}%`, false, false))
  }
  if (agentsShown) {
    const finished = group.length - running.length
    const share = group.reduce((sum, a) => sum + (progressOf(a) ?? 0), 0) / group.length
    const word = running.length > 0 ? `${running.length} ${running.length === 1 ? 'agent' : 'agents'} running` : `${group.length} ${group.length === 1 ? 'agent' : 'agents'} done`
    const cost = group.reduce((sum, a) => sum + a.costUsd, 0)
    rows.push(line('agents', word, Math.max(running.length > 0 ? 0.05 : 0, share), `${finished}/${group.length} · ≈${fmtCost(cost)}`, running.length === 0))
    if (open) {
      for (const a of group) {
        rows.push(
          <Box key={a.id} flexDirection="row" columnGap={1} paddingLeft={4}>
            <Text color={a.status === 'failed' ? 'red' : a.status === 'done' ? 'green' : color}>{STATUS_GLYPH[a.status]}</Text>
            <Text wrap="truncate-end">{a.description || a.type}</Text>
            <Text dimColor wrap="truncate-end">{`${runModel(a)} · ${fmtTokens(a.contextTokens)} · ${fmtTime(elapsed(a, at))}`}</Text>
          </Box>,
        )
      }
      rows.push(
        <Box key="dot-panel" paddingLeft={4}>
          <Button key="band-panel" label="Open panel" plain dimColor onPress={() => void togglePane($)} />
        </Box>,
      )
    }
  }
  return (
    <Box flexDirection="column" rowGap={0.25}>
      {rows}
      {below}
    </Box>
  )
}
TSX
)
SAVVY_PATCHES=(
    "on('agent.spawn', async (\$, e, next) => {"
    "on('tool.call', { tool: MAIN_STEP_TOOL }, async (\$, e, next) => {
    startTurnTick(\$)
    await recordMainStep(\$, e)
    return next(e)
  })

  // A new request starts its own steps
  on('prompt.submit', async (\$, e, next) => {
    startTurnTick(\$)
    if (e.origin?.kind !== 'plugin') await update(\$, mainSteps, () => null)
    return next(e)
  })

  on('agent.spawn', async (\$, e, next) => {"
    'async function togglePane($: EngineInterface): Promise<boolean> {'
    "$SAVVY_BAND

async function togglePane(\$: EngineInterface): Promise<boolean> {"
    'if (f === null || e.props.hasSurvey) return next(e)'
    "if (f === null && !e.props.hasSurvey && e.surface !== 'terminal') return agentsBand(\$, e, next)
    if (f === null || e.props.hasSurvey) return next(e)"
)
# Neutral, because the workbench draws these icons and they can't read the theme. The pending dot stays blue
LOGO_PATCHES=('fill="#D97757"' 'fill="#c3c6cf"')

# --- Helpers ---
# Prints the stylesheet without our block
strip_block() {
    awk -v begin="$BEGIN" -v end="$END" '$0 == begin { skip = 1; next } $0 == end { skip = 0; next } !skip' "$1"
}

# Replaces the file only when its contents differ, so a run with nothing to do touches nothing
write_if_changed() {
    local file=$1 new=$2
    cmp -s "$new" "$file" && { rm -f "$new"; return 0; }
    cat "$new" > "$file"
    rm -f "$new"
    echo "patched $file"
}

# $1 is the extension's file, $2 ours to append
patch_stylesheet() {
    local file=$1 ours=$2 new
    new=$(mktemp)
    { strip_block "$file"; printf '%s\n' "$BEGIN"; cat "$ours"; printf '%s\n' "$END"; } > "$new"
    write_if_changed "$file" "$new"
}

restore_stylesheet() {
    local file=$1 new
    new=$(mktemp)
    strip_block "$file" > "$new"
    write_if_changed "$file" "$new"
}

# $1 is apply or restore, $2 the file, and the rest upstream/ours pairs
patch_mod() {
    local mode=$1 file=$2
    shift 2
    python3 -I - "$mode" "$file" "$@" <<'EOF'
import sys

mode, path, *pairs = sys.argv[1:]
text = original = open(path, encoding="utf-8").read()
for upstream, ours in zip(pairs[::2], pairs[1::2]):
    if ours in text:
        if mode == "restore":
            text = text.replace(ours, upstream)
    elif upstream not in text:
        print(f"skipped, upstream changed: {upstream!r} in {path}", file=sys.stderr)
    elif mode == "apply":
        text = text.replace(upstream, ours)
if text != original:
    open(path, "w", encoding="utf-8").write(text)
    print(f"patched {path}")
EOF
}

patch_all() {
    local mode=$1 file
    shopt -s nullglob
    for file in "$EXTENSIONS"/anthropic.claude-code-*/webview/index.css; do
        if [[ "$mode" == apply ]]; then
            patch_stylesheet "$file" "$CSS"
        else
            restore_stylesheet "$file"
        fi
    done
    for file in "$EXTENSIONS"/anthropic.claude-code-*/webview/index.js; do
        if [[ "$mode" == apply ]]; then
            patch_stylesheet "$file" "$JS"
        else
            restore_stylesheet "$file"
        fi
    done
    for file in "$PLUGINS"/cache/claude-code-filetree/filetree/*/hooks/register.tsx; do
        patch_mod "$mode" "$file" "${FILETREE_PATCHES[@]}"
    done
    for file in "$PLUGINS"/cache/hellosverre-mods/skins/*/hooks/svg-usage.ts; do
        patch_mod "$mode" "$file" "${SKINS_PATCHES[@]}"
    done
    for file in "$PLUGINS"/cache/hellosverre-mods/skins/*/hooks/rows.tsx; do
        patch_mod "$mode" "$file" "${TABLE_PATCHES[@]}" "${BAND_PATCHES[@]}"
    done
    for file in "$PLUGINS"/cache/hellosverre-mods/skins/*/hooks/register.tsx; do
        patch_mod "$mode" "$file" "${BAND_STATE_PATCHES[@]}"
    done
    for file in "$PLUGINS"/cache/claude-kit/savvy-progress/*/hooks/register.tsx; do
        patch_mod "$mode" "$file" "${SAVVY_PATCHES[@]}"
    done
    for file in "$EXTENSIONS"/anthropic.claude-code-*/resources/claude-logo{,-done,-pending}.svg; do
        patch_mod "$mode" "$file" "${LOGO_PATCHES[@]}"
    done
}

# Only these two keys change, because the file also holds Skins' other settings. Skins reads it
# when a session starts, so the colors reach new sessions
apply_skin() {
    local file new
    shopt -s nullglob
    for file in "$PLUGINS"/store/skins_hellosverre-mods-*.json; do
        new=$(mktemp)
        jq --slurpfile palette "$SKIN_PALETTE" \
            '.custom.matugen = {name: "matugen", label: "matugen", base: "tokyo-night", palette: $palette[0], spinner: [], done: []} | .prefs.skin = "matugen"' \
            "$file" > "$new" || { rm -f "$new"; return 1; }
        write_if_changed "$file" "$new"
    done
}

# --- Main ---
case "${1:-}" in
    --restore) patch_all restore ;;
    --skin) apply_skin ;;
    "") patch_all apply ;;
    *) echo "usage: ${0##*/} [--restore | --skin]" >&2; exit 2 ;;
esac

// Limits on the desktop — one card per login, Claude and Codex: the 5-hour window, the week, and
// Fable's own week where the login has one (`fable_week`, bin/account). Every row `account limits
// --all --parked` lists is drawn: the registry's, parked ones too (`enabled: false`, tagged "off":
// a login the owner runs by hand still spends its week, 2026-10-18), and every login Orca
// holds or uses once `account orca-sync` has read it back, its Codex/ChatGPT ones included (the owner,
// 2026-10-16); an `account orca off` login stays hidden. Every other agent Orca reads limits for —
// Antigravity, Cursor — gets a card from Orca's own reading (`--orca`, the owner 2026-10-20: "add
// antigravity from orca … automate this"), its quota buckets as bars: one signed in to Orca shows
// up here by itself, and `account orca off <agent>` hides its card. A plan draws the windows it
// has: Codex prolite has a week and no 5-hour window. The file keeps its old name: Übersicht keys a
// widget's position and state by it, and bootstrap.sh links it by name.
// Seen with the Show Desktop gesture (thumb and three fingers spread), no click (the owner, 2026-10-07:
// "free, desktop only" over a paid Notification Center widget). Übersicht runs `command`;
// bootstrap.sh links this file into its widgets folder when Übersicht is installed.
//
// The data is `bin/account limits --all --parked --orca --json`: a zero-token get_usage probe per Claude login and
// `codex app-server`'s account/rateLimits/read per Codex one (no model call, free, ~4 s and ~1 s,
// cached 60 s — bin/account's header), so a 10-minute refresh costs nothing. It probes the primary
// checkout's account, never a worktree's. Übersicht's shell has a bare PATH, and the probes run
// `claude` and `codex`, hence ~/.local/bin and /opt/homebrew/bin. bin/account is lighthouse's, run
// through the core's `regatta <tool>` from the checkout the config dir's `home` file names (no
// overlay path; that file is the main checkout's, never a worktree's).
// Unverified (review 2026-10-10): that makes 12 headless `claude` starts an hour per login, parked
// ones too (a failing one waits out its probe timeout, the card with it), in config dirs
// live sessions also write, and the probe records exhaustions pick reads. Whether a probe writes
// `.claude.json` at all, and so could race a session's write, is not probed — diff it
// structurally around one probe before raising the frequency.
//
// No `<>…</>` fragments: Übersicht 1.6.82 throws on them at render, and its server dies mapping
// that error ("Line numbers must be >= 1" in source-map), taking every widget down until the app
// restarts (2026-10-07). After any edit, check `pgrep -f "node-arm64.*server.js"` still answers.
// A link made into the widgets folder while Übersicht runs is never loaded: its watcher takes a
// created symlink for a folder and fails to read it, silently, so the card vanished when
// bootstrap.sh re-pointed the link at this checkout (2026-10-20, five days into the app's run).
// A link loads at the app's start only; ground truth is `claude-limits-jsx` in the `widgets` of
// its server's `/state/`. Anything on stderr turns the command's whole reply into an error (the
// server's /run/ answers 500 at the first stderr byte), so the command must keep stderr quiet.
import { css } from "uebersicht";

export const command =
  'PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/bin:/bin" /usr/bin/python3 ' +
  '"$(head -1 "${REGATTA_CONFIG:-$HOME/.config/regatta}/home")/modules/regatta/bin/regatta" ' +
  'account limits --all --parked --orca --json';

export const refreshFrequency = 10 * 60 * 1000;

// Lower left, where a native desktop widget would sit (the owner, 2026-10-08; it was centred because
// Show Desktop pushes windows to the edges): the native widgets' 16 pt inset and their 344 pt
// column (two small widgets and a 16 pt gap), measured off a screenshot of the laptop's desktop.
// The Dock is on the left and auto-hides here, so nothing reserves that corner.
export const className = `
  left: 16px;
  bottom: 16px;
  font: 13px -apple-system, "SF Pro Text", sans-serif;
  color: #f2f2f2;
`;

// Opaque, as a native widget with desktop tinting off (the owner, 2026-10-08: no transparency).
const card = css`
  background: #1c1c1e;
  border: 0.5px solid rgba(255, 255, 255, 0.1);
  border-radius: 22px;
  padding: 16px 18px 6px;
  box-sizing: border-box;
  width: 344px;
  box-shadow: 0 4px 16px rgba(0, 0, 0, 0.3);
`;
const row = css`margin: 4px 0 12px;`;
const head = css`display: flex; justify-content: space-between; font-weight: 600; margin-bottom: 6px;`;
const dim = css`color: #9a9aa0; font-weight: 400; font-size: 11px;`;
const line = css`display: grid; grid-template-columns: 38px 1fr 40px; align-items: center; gap: 8px; margin: 3px 0;`;
// An Orca agent's buckets carry names ("Claude and GPT models"), wider than "5h" or "week".
const wide = css`display: grid; grid-template-columns: 96px 1fr 40px; align-items: center; gap: 8px; margin: 3px 0;`;
const track = css`position: relative; height: 6px; border-radius: 3px; background: rgba(255, 255, 255, 0.14);`;
const tick = css`position: absolute; top: -3px; width: 2px; height: 12px; background: #f2f2f2; opacity: 0.7;`;
const pct = css`text-align: right; font-variant-numeric: tabular-nums;`;

const WEEK = 7 * 24 * 3600;
// Red at 90 % and up; amber at any point ahead of the clock — earlier than the tier check, which
// calls a week tight only 10 points ahead of pace or at 80 % (hooks/tier_check.py).
const colour = (p, pace) => (p >= 90 ? "#ff5f57" : pace != null && p > pace ? "#febc2e" : "#28c840");

const ago = (s) => {
  const m = Math.round((Date.now() / 1000 - s) / 60);
  return m < 1 ? "now" : m < 60 ? `${m} min ago` : `${Math.round(m / 60)} h ago`;
};
// A reset today shows its time alone; any other day, past or ahead, names the day too, and one
// more than a week ahead (Cursor's month, via Orca) its date, as bin/account's when() does.
const until = (t) => {
  if (!t) return "";
  const d = new Date(t * 1000);
  const hm = d.toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" });
  if (d.toDateString() === new Date().toDateString()) return hm;
  return (t - Date.now() / 1000 < 7 * 86400
    ? d.toLocaleDateString([], { weekday: "short" })
    : d.toLocaleDateString([], { month: "short", day: "numeric" })) + " " + hm;
};

// A window whose reset has passed since the reading (an offline laptop, a stale cache) shows no
// figure: the old one belongs to a window that is over.
const Bar = ({ name, p, resets, pace, cls = line }) =>
  p == null || (resets && resets < Date.now() / 1000) ? (
    <div className={cls}>
      <span className={dim}>{name}</span>
      <span className={dim}>{p == null ? "no reading" : "reset since this reading"}</span>
      <span />
    </div>
  ) : (
  <div className={cls}>
    <span className={dim}>{name}</span>
    <div className={track} title={resets ? `resets ${until(resets)}` : ""}>
      <div style={{ width: `${Math.min(p, 100)}%`, height: "100%", borderRadius: 3, background: colour(p, pace) }} />
      {pace != null && <div className={tick} style={{ left: `${pace}%` }} />}
    </div>
    <span className={pct}>{p}%</span>
  </div>
  );

export const render = ({ output, error }) => {
  // The first frame renders before the probe (~4 s) answers.
  if (!output && !error) return <div className={card}><span className={dim}>Limits: reading…</span></div>;
  let rows;
  try {
    rows = JSON.parse(output);
  } catch (e) {
    return <div className={card}>Limits: no reading<div className={dim}>{String(error || e).slice(0, 200)}</div></div>;
  }
  // Anything but a list would throw below, and a throw in render takes Übersicht's server down
  // (the header). A same_as row repeats another login's figures; a row not set up here never reads.
  const shown = Array.isArray(rows) ? rows.filter((a) => a && !a.same_as && a.here !== false) : [];
  if (!shown.length) return <div className={card}><span className={dim}>Limits: no login to show (bin/account limits --all --parked --orca)</span></div>;
  const now = Date.now() / 1000;
  return (
    <div className={card}>
      {shown.map((a) => {
        const l = a.limits || {};
        // How far through its window a bar is (a week, or a bucket's own span): the tick it is judged against.
        const paceOf = (resets, span = WEEK) => (resets ? Math.max(0, Math.min(100, Math.round((100 * (now - (resets - span))) / span))) : null);
        // An Orca agent's quota buckets stand in for its week (Antigravity's week is its fuller bucket).
        const bs = Array.isArray(l.buckets) ? l.buckets.filter((b) => b && b.name) : [];
        const short = (n) => String(n).replace(/\s+models$/i, "");
        const bucketResets = bs.length && new Set(bs.map((b) => b.resets)).size === 1 ? [["quota", bs[0].resets]] : bs.map((b) => [short(b.name), b.resets]);
        // Any other window Orca reads for it (a month), beside the week, never in its place.
        const ws = Array.isArray(l.windows) ? l.windows.filter((w) => w && w.name) : [];
        return (
          <div key={a.label} className={row}>
            <div className={head}>
              <span>{a.label}{a.primary ? " ★" : ""}{a.enabled === false ? " — off" : ""}{(l.locked || []).length ? " — locked" : ""}{a.report ? <span className={dim}> via Orca</span> : null}</span>
              <span className={dim}>{a.sampled ? ago(a.sampled) : "never sampled"}</span>
            </div>
            {l.five_hour == null && l.seven_day == null && !bs.length && !ws.length ? (
              <div className={dim}>unknown — {a.why || "no reading"}</div>
            ) : (
              <div>
                {/* Only the windows the plan has: Codex prolite has no 5-hour one (bin/account parse_codex). */}
                {l.five_hour != null && <Bar name="5h" p={l.five_hour} resets={l.five_hour_resets} />}
                {/* A Claude login always has a 5-hour window: a missing one is a lost reading, said so. */}
                {l.five_hour == null && a.provider === "claude" && <div className={dim}>5h unknown</div>}
                {l.seven_day != null && !bs.length && <Bar name="week" p={l.seven_day} resets={l.seven_day_resets} pace={paceOf(l.seven_day_resets)} />}
                {bs.map((b) => <Bar key={b.name} cls={wide} name={short(b.name)} p={b.percent} resets={b.resets} pace={paceOf(b.resets, b.window_s || WEEK)} />)}
                {ws.map((w) => <Bar key={w.name} name={w.name} p={w.percent} resets={w.resets} pace={paceOf(w.resets, w.window_s || WEEK)} />)}
                {l.fable_week != null && <Bar name="Fable" p={l.fable_week} resets={l.fable_week_resets} pace={paceOf(l.fable_week_resets)} />}
                {/* A rolled window has no reset time (bin/account rolled()): name only the ones known. */}
                <div className={dim}>{[["5h", l.five_hour_resets]].concat(bs.length ? bucketResets : [["week", l.seven_day_resets]], ws.map((w) => [w.name, w.resets])).filter(([, t]) => t).map(([n, t]) => `${n} resets ${until(t)}`).join(" · ")}</div>
              </div>
            )}
          </div>
        );
      })}
    </div>
  );
};

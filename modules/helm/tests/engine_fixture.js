/* engine_fixture.js — the Engine room's sources (carried from docs/engine-room-2026-11-02/prototype/engine-fixture.js for
   S3's helm cases; the landing entry became a finish, as finish-as-task made it, and the typed pin carries S4's
   pin_login), each in the shape its real tool prints (read from the source, with a
   real capture where a read is safe: tools/captures/), synthetic names only (hosts host-N and node-N, logins acct-N, repos
   and topics made up). Five documents, as S3's poll would hand them to the adapter (adapter.js):
     hosts    lighthouse's `hosts --json` (S2, the engine-room-s2 branch at 2a0a6016, bin/hosts read()
              :446-463): {at, here, hosts{<name>: row | {host, no_sample}}, queue{entries[], dropped, fence_unreadable,
              unreadable}, logins[], records, ref}. A row is sample() :358-367 (host, os, cores, ram_gb, at, load, mem,
              limits, headroom, slots, fence, runs | null, records, role?, history) plus `source`; no `checks` and no
              `procs` (the schema names procs; sample() never writes it). An entry is ENTRY_KEYS :55-56 plus qid, repo
              and after[] (topics); `needs` is a list (dispatch-queue :2552), `refused_by` {host: epoch} (:885). Three
              keys S3 adds to ENTRY_KEYS are carried where the design needs them and left off one entry, as a row today
              would: pin_kind (dispatch-queue :2543: "typed" | "login" | ""), pinned_why (held_here's words, :3771) and by.
              A login is LOGIN_KEYS :57 + limits LIMIT_KEYS :58; `why` in account's judge words (bin/account :2130-2160).
     ops      lighthouse's `ops status --json` (bin/ops cmd_status :1114-1131): {row, age_s, stale, line, sig}; the row
              sample() :907-950: as_of, host, partial, why{}, registry, queue, slots, load, mem, check {slots_busy,
              waiting} (:608), budget per account (read_budget :692-711: ok → state, used, week_used, unit, net_amount,
              cap, share; else state absent|refused|unread and why), weeks, cost, token, took_s
     budgets  the config dir's lighthouse/ci-budgets.json (ops :59-63, the real file's shape read 2026-11-02 with its
              names dropped: tools/captures/ci-budgets.shape.txt): {reserve, accounts{key: {provider, user|org|org_slug,
              month_minutes|month_credits, week_share, reserve?, margin?}}}
     alarms   the log dir's ci-budget-alarms.json (ops budget_alarms :811, :827): {key: {level, issue, since}}
     intake   `ops intake --json` (ops cmd_intake :1703-1709, open_items :1669-1671): {open: [{repo, slug, number, kind,
              label, created, author, url, scope}], why, sig}; kinds KINDS :1157 + other; authors self|member|stranger|bot
   The night: host-a full by its cap (headroom judges memory only, so its room reads true) and holding 28 stale peer
   records; host-b (the laptop) swapping at 110 MB/s over its 10 (tools/captures/headroom.json, the real reading of
   2026-11-02, the host renamed); node-1 with room and one reservation; host-c (a scope host) with no sample for 3 h;
   node-2 whose memory did not read and whose runs are unknown (no dispatch-rc there); host-e whose row does not parse;
   one run and two entries in a confidential scope, counted and never listed; one entry 20 h behind a held pin on
   host-c; one pinned by a typed --pin; one pinned with no kind the row can tell; one refused three times; a finish pinned
   to this host (held, as every pinned finish is); a claimed entry running on node-1; acct-c resting, acct-d's week spent, acct-e parked; the
   hosted-VM budget into its reserve, one budget with no token. ENGINE_SRC_OFF: the two desk documents as this laptop
   printed them on 2026-11-02 (tools/captures/ops-status.json, ops-intake.json), their paths cut. */
window.ENGINE_SRC = (function () {
  // the prototype's night (2026-11-01 22:28 in the viewer's zone), or ENGINE_NOW: test_engine.sh renders the page at today's clock
  var NOW = window.ENGINE_NOW || Math.round(new Date(2026, 10, 1, 22, 28).getTime() / 1000);
  var m = function (min) { return NOW - min * 60; }, h = function (hrs) { return NOW - Math.round(hrs * 3600); };
  var LIM = { avail: 15, swap: 8, rate: 8, load_max: 1.2 };
  return {
    hosts: {
      at: NOW, here: 'host-a',
      hosts: {
        'host-a': { host: 'host-a', role: 'dispatch host', os: 'macOS', cores: 24, ram_gb: 192, at: m(2), source: 'here',
          load: { l1: 19.4, l5: 18.7, l15: 17.2, per_core_5m: 0.78 }, mem: { avail: 31, swap_gb: 0.2, rate: 0, swap_total_gb: 1 },
          limits: { avail: 15, swap: 8, rate: 8, cap: 3, load_max: 1.2 },
          headroom: { room: true, reason: 'room: 31 % free, 0.2 GB swap, 0 MB/s swapping', near: ['cap'] },
          slots: { busy: 3, cap: 3, reserved: 0 },
          fence: { confined: 1, unreadable: false },
          runs: [
            { topic: 'lease-renewal-s5', repo: 'reef', login: 'acct-a', started: h(1.9), state: 'busy', session: 'b1c2d3e4', prio: 'force' },
            { topic: 'budget-holds-s2', repo: 'dock', login: 'acct-b', started: h(0.7), state: 'busy', session: 'c2d3e4f5', prio: 'normal' },
            { topic: 'mirror-retention-s3-fix', repo: 'cove', login: null, started: h(3.4), state: 'waiting', session: 'd3e4f5a6', prio: 'low' }
          ],
          records: { stale: 28, oldest_days: 3 },
          history: [[h(8), 0.41, 52, 0], [h(7), 0.44, 50, 0], [h(6), 0.52, 47, 0], [h(5), 0.61, 44, 0], [h(4), 0.66, 40, 0], [h(3), 0.71, 38, 0], [h(2), 0.74, 35, 0], [h(1), 0.77, 33, 0], [m(2), 0.78, 31, 0]] },
        'host-b': { host: 'host-b', role: 'laptop', os: 'macOS', cores: 10, ram_gb: 32, at: m(4), source: 'ref',
          load: { l1: 6.1, l5: 5.4, l15: 4.9, per_core_5m: 0.54 }, mem: { avail: 35, swap_gb: 13.83, rate: 110.3, swap_total_gb: 16 },
          limits: { avail: 25, rate: 10, cap: 2, load_max: 1.2 },                         // the real line: no swap rule (headroom.json)
          headroom: { room: false, reason: 'no room: 110.3 MB/s swapping, over 10 MB/s', near: ['rate'] },
          slots: { busy: 1, cap: 2, reserved: 0 },
          fence: { confined: 0, unreadable: false },
          runs: [{ topic: 'night-digest-s4', repo: 'tide', login: 'acct-c', started: h(0.4), state: 'busy', session: 'e4f5a6b7', prio: 'high' }],
          records: { stale: 0, oldest_days: 0 },
          history: [[h(8), 0.22, 48, 0], [h(7), 0.25, 45, 0], [h(6), 0.31, 41, 0.4], [h(5), 0.38, 40, 2.1], [h(4), 0.47, 38, 5.8], [h(3), 0.5, 37, 9.4], [h(2), 0.52, 36, 40.1], [h(1), 0.53, 35, 88.6], [m(4), 0.54, 35, 110.3]] },
        'node-1': { host: 'node-1', role: 'linux node', os: 'Linux', cores: 16, ram_gb: 64, at: m(1), source: 'ref',
          load: { l1: 6.8, l5: 6.5, l15: 5.1, per_core_5m: 0.41 }, mem: { avail: 58, swap_gb: 0, rate: 0, swap_total_gb: 4 },
          limits: { avail: 15, swap: 8, rate: 8, cap: 4, load_max: 1.2 },
          headroom: { room: true, reason: 'room: 58 % free, 0 GB swap, 0 MB/s swapping', near: [] },
          slots: { busy: 3, cap: 4, reserved: 1 },                                        // busy counts the reservation (dispatch :747)
          fence: { confined: 0, unreadable: false },
          runs: [
            { topic: 'receipt-ladder-s4', repo: 'harbor', login: 'acct-a', started: m(17), state: 'busy', session: 'f5a6b7c8', prio: 'normal' },
            { topic: 'night-digest-s3', repo: 'tide', login: 'acct-b', started: h(1.8), state: 'busy', session: 'a6b7c8d9', prio: 'normal' }
          ],
          records: { stale: 0, oldest_days: 0 },
          history: [[h(8), 0.12, 71, 0], [h(7), 0.18, 69, 0], [h(6), 0.2, 68, 0], [h(5), 0.33, 63, 0], [h(4), 0.35, 62, 0], [h(3), 0.4, 60, 0], [h(2), 0.44, 58, 0], [h(1), 0.4, 58, 0], [m(1), 0.41, 58, 0]] },
        'host-c': { host: 'host-c', role: 'scope host', os: 'macOS', cores: 4, ram_gb: 16, at: h(3.2), source: 'ref',
          load: { l1: 1.1, l5: 0.9, l15: 0.8, per_core_5m: 0.22 }, mem: { avail: 44, swap_gb: 0.9, rate: 0, swap_total_gb: 2 },
          limits: { avail: 15, swap: 8, rate: 8, cap: 1, load_max: 1.2 },
          headroom: { room: true, reason: 'room: 44 % free, 0.9 GB swap, 0 MB/s swapping', near: [] },
          slots: { busy: 0, cap: 1, reserved: 0 },
          fence: { confined: 0, unreadable: false },
          runs: [], records: { stale: 0, oldest_days: 0 },
          history: [[h(8), 0.2, 45, 0], [h(6), 0.21, 44, 0], [h(3.2), 0.22, 44, 0]] },
        'node-2': { host: 'node-2', os: 'Linux', cores: 8, ram_gb: 32, at: m(9), source: 'ref',                   // no role, no dispatch-rc: runs unknown
          load: { l1: 0.4, l5: 0.3, l15: 0.3, per_core_5m: 0.04 }, mem: { swap_total_gb: 0 },
          limits: { avail: 15, swap: 8, rate: 8, cap: 2, load_max: 1.2 },
          headroom: { room: null, reason: 'memory unreadable here (FileNotFoundError: <path>)', near: [] },
          slots: { busy: 0, cap: 2, reserved: 0 },
          fence: { confined: 0, unreadable: false, runs_unread: true },
          runs: null, records: { stale: 0, oldest_days: 0 },
          history: [[m(9), 0.04, null, null]] },
        'host-e': { host: 'host-e', no_sample: 'its row does not parse' }
      },
      queue: {
        entries: [
          { qid: 'fleet:lease-renewal-s6', key: 'reef:lease-renewal-s6', topic: 'lease-renewal-s6', repo: 'reef', state: 'queued', priority: 'force', kind: 'step', host: 'host-a', pin_kind: 'typed', pin_login: false, by: 'b1c2d3e4', prefer: '', prefer_off: null, running_on: null, queued_at: m(12), put_at: m(12), claimed_at: null, claimed_by: null, attempts: 2, needs: [], after: [], last_refusal: 'the run cap (3 of 3 busy at its start)', refused_by: { 'host-a': m(10) } },
          { qid: 'fleet:night-digest-s5', key: 'tide:night-digest-s5', topic: 'night-digest-s5', repo: 'tide', state: 'queued', priority: 'high', kind: 'step', host: '', pin_kind: '', by: 'e4f5a6b7', prefer: '', prefer_off: null, running_on: null, queued_at: m(40), put_at: m(40), claimed_at: null, claimed_by: null, attempts: 3, needs: ['macos'], after: [], last_refusal: 'the run cap (2 of 2 busy at its start)', refused_by: { 'host-b': m(31), 'host-a': m(22) } },
          { qid: 'fleet:slot-scheduler-s6', key: 'dock:slot-scheduler-s6', topic: 'slot-scheduler-s6', repo: 'dock', state: 'queued', priority: 'high', kind: 'step', host: '', pin_kind: '', by: '', prefer: '', prefer_off: null, running_on: null, queued_at: m(55), put_at: m(55), claimed_at: null, claimed_by: null, attempts: 0, needs: [], after: ['slot-scheduler-s5'], last_refusal: null, refused_by: {} },
          { qid: 'fleet:receipt-ladder-s4', key: 'harbor:receipt-ladder-s4', topic: 'receipt-ladder-s4', repo: 'harbor', state: 'running', priority: 'normal', kind: 'step', host: '', pin_kind: '', by: 'f5a6b7c8', prefer: 'node-1', prefer_off: null, running_on: 'node-1', queued_at: m(26), put_at: m(26), claimed_at: m(17), claimed_by: 'node-1', attempts: 1, needs: [], after: [], last_refusal: null, refused_by: {} },
          { qid: 'fleet:intake-lanes-s3', key: 'lantern:intake-lanes-s3', topic: 'intake-lanes-s3', repo: 'lantern', state: 'queued', priority: 'normal', kind: 'step', host: '', pin_kind: '', by: '', prefer: '', prefer_off: null, running_on: null, queued_at: m(21), put_at: m(21), claimed_at: null, claimed_by: null, attempts: 0, needs: [], after: [], last_refusal: null, refused_by: {} },
          { qid: 'fleet:fleet-queue-s5-fix', key: 'quay:fleet-queue-s5-fix', topic: 'fleet-queue-s5-fix', repo: 'quay', state: 'queued', priority: 'normal', kind: 'fix', host: 'host-c', pin_kind: '', pinned_why: 'answers wait in its worktree here (pending-answers)', by: 'a1b2c3d4', prefer: '', prefer_off: null, running_on: null, queued_at: h(20.3), put_at: h(20.3), claimed_at: null, claimed_by: null, attempts: 0, needs: [], after: [], last_refusal: null, refused_by: {} },
          { qid: 'fleet:mirror-retention-s2', key: 'cove:mirror-retention-s2', topic: 'mirror-retention-s2', repo: 'cove', state: 'queued', priority: 'low', kind: 'step', host: '', pin_kind: '', by: '', prefer: 'host-a', prefer_off: h(1.6), running_on: null, queued_at: h(2.1), put_at: h(2.1), claimed_at: null, claimed_by: null, attempts: 1, needs: [], after: [], last_refusal: 'the run cap (3 of 3 busy at its start)', refused_by: {} },
          { qid: 'fleet:budget-holds-s3', key: 'dock:budget-holds-s3', topic: 'budget-holds-s3', repo: 'dock', state: 'queued', priority: 'low', kind: 'step', host: '', pin_kind: '', by: '', prefer: '', prefer_off: null, running_on: null, queued_at: h(1.4), put_at: h(1.4), claimed_at: null, claimed_by: null, attempts: 0, needs: [], after: ['budget-holds-s2'], last_refusal: null, refused_by: {} },
          { qid: 'fleet:lantern-s2', key: 'lantern:lantern-s2', topic: 'lantern-s2', repo: 'lantern', state: 'queued', priority: 'low', kind: 'step', host: 'host-b', prefer: '', prefer_off: null, running_on: null, queued_at: m(48), put_at: m(48), claimed_at: null, claimed_by: null, attempts: 0, needs: [], after: [], last_refusal: null, refused_by: {} },   // a row as S2 prints it today: pinned, its kind not carried
          { qid: 'fleet:harbor-lights-land', key: 'harbor:harbor-lights-land', topic: 'harbor-lights-land', repo: 'harbor', state: 'queued', priority: 'low', kind: 'finish', host: 'host-a', pin_kind: 'typed', pin_login: false, by: 'c3d4e5f6', prefer: '', prefer_off: null, running_on: null, queued_at: m(33), put_at: m(33), claimed_at: null, claimed_by: null, attempts: 0, needs: [], after: [], last_refusal: null, refused_by: {} }
        ],
        dropped: 2, fence_unreadable: false, unreadable: false
      },
      logins: [
        { label: 'acct-a', eligible: true, enabled: true, primary: true, provider: 'claude', parked: false, why: 'week 54% < 90% (week-max), 5h 31% ≤ 90%', sampled: m(4), overage: false, limits: { plan: 'max', five_hour: 31, five_hour_resets: h(-3.2), seven_day: 54, seven_day_resets: h(-77), fable_week: 61, fable_week_resets: h(-77), locked: false, extra_usage: false } },
        { label: 'acct-b', eligible: true, enabled: true, primary: false, provider: 'claude', parked: false, why: 'week 41% < 90% (week-max), 5h 12% under 70% (runs whatever the pace)', sampled: m(4), overage: false, limits: { plan: 'max', five_hour: 12, five_hour_resets: h(-4.1), seven_day: 41, seven_day_resets: h(-77), fable_week: 40, fable_week_resets: h(-77), locked: false, extra_usage: false } },
        { label: 'acct-c', eligible: false, enabled: true, primary: false, provider: 'claude', parked: false, why: '5h 94% > 90%, over pace 62%; resets 00:20', sampled: m(4), overage: false, limits: { plan: 'max', five_hour: 94, five_hour_resets: h(-1.9), seven_day: 77, seven_day_resets: h(-77), fable_week: 70, fable_week_resets: h(-77), locked: false, extra_usage: false } },
        { label: 'acct-d', eligible: false, enabled: true, primary: false, provider: 'claude', parked: false, why: 'week 91% ≥ 90% (week-max); resets Thu 06:00', sampled: m(4), overage: false, limits: { plan: 'max', five_hour: 48, five_hour_resets: h(-1.2), seven_day: 91, seven_day_resets: h(-55), fable_week: 55, fable_week_resets: h(-55), locked: false, extra_usage: false } },
        { label: 'acct-e', eligible: false, enabled: false, primary: false, provider: 'claude', parked: true, why: 'parked (enabled: false in accounts.json)', sampled: h(30), overage: false, limits: { plan: 'pro', five_hour: 0, five_hour_resets: null, seven_day: 12, seven_day_resets: h(-77), fable_week: null, fable_week_resets: null, locked: false, extra_usage: false } }
      ],
      records: { stale: 28, oldest_days: 3 },
      ref: { unreadable: null, offline: null }
    },
    ops: {
      row: {
        as_of: m(6), host: 'host-a', partial: false, why: { 'token.project': 'GitHub\'s GraphQL refused the Projects read (not accessible)' }, registry: 'ok',
        queue: { pending: 8, by_priority: { force: 1, high: 2, normal: 2, low: 3 }, live: 1 },
        slots: { busy: 3, max: 3 }, load: { per_core: 0.78, cores: 24 }, mem: { avail: 31, swap_gb: 0.2, rate: 0, room: true },
        check: { slots_busy: 1, waiting: 2 },
        budget: {
          'hosted-vms': { state: 'ok', used: 24600, week_used: 5740, unit: 'credits', net_amount: 0, cap: 30000, share: 0.82 },
          'runner-minutes': { state: 'ok', used: 1840, week_used: 980, unit: 'minutes', net_amount: 0, cap: 3000, share: 0.613 },
          'org-minutes': { state: 'absent', why: 'no GITHUB_TOKEN in <path>' }
        },
        weeks: { 'acct-a': { weekly: 54, five_hour: 31, fable: 61, locked: false, eligible: true, sampled: m(4), here: true } },
        cost: { week_list: 212.4, week_effective: 3.93 }, token: { plan: 'ok', project: 'refused' }, took_s: 4.2
      },
      age_s: 360, stale: false, line: 'queue 8 pending (1 force, 2 high, 2 normal, 3 low), 1 live · slots 3 of 3 · load 0.78/core · mem 31 % free · checks 1 busy, 2 waiting · budget hosted-vms 82 %, runner-minutes 61 %, org-minutes absent · token plan ok, project refused', sig: '3c9e1a7f'
    },
    budgets: {
      reserve: 0.2,
      accounts: {
        'hosted-vms': { provider: 'circleci', org_slug: 'gh/acct-org', month_credits: 30000, week_share: 0.3, margin: 0.1 },
        'runner-minutes': { provider: 'github', user: 'acct-user', month_minutes: 3000, week_share: 0.35 },
        'org-minutes': { provider: 'github', org: 'acct-org', month_minutes: 50000, week_share: 0.35 }
      }
    },
    alarms: {
      'hosted-vms': { level: 'reserve', issue: 91, since: h(3.1) },
      'runner-minutes': { level: 'ok', issue: null, since: h(40) }
    },
    intake: {
      open: [
        { repo: 'acct-owner/regatta-logbook', slug: 'acct-owner/regatta-logbook', number: 88, kind: 'deadman', label: 'deadman', created: m(36), author: 'bot', url: 'https://github.com/acct-owner/regatta-logbook/issues/88', scope: null },
        { repo: 'acct-owner/regatta-logbook', slug: 'acct-owner/regatta-logbook', number: 90, kind: 'stall', label: 'stall', created: h(1.4), author: 'self', url: 'https://github.com/acct-owner/regatta-logbook/issues/90', scope: null },
        { repo: 'acct-owner/regatta-logbook', slug: 'acct-owner/regatta-logbook', number: 91, kind: 'budget', label: 'budget', created: h(3.1), author: 'self', url: 'https://github.com/acct-owner/regatta-logbook/issues/91', scope: null },
        { repo: 'acct-owner/inbox', slug: 'acct-owner/inbox', number: 93, kind: 'contact', label: null, created: h(5), author: 'stranger', url: 'https://github.com/acct-owner/inbox/issues/93', scope: null },
        { repo: 'acct-owner/inbox', slug: 'acct-owner/inbox', number: 95, kind: 'contact', label: null, created: h(9.5), author: 'stranger', url: 'https://github.com/acct-owner/inbox/issues/95', scope: null },
        { repo: 'harbor', slug: 'acct-owner/harbor', number: 96, kind: 'bug', label: 'bug', created: h(11), author: 'member', url: 'https://github.com/acct-owner/harbor/issues/96', scope: null },
        { repo: 'harbor', slug: 'acct-owner/harbor', number: 97, kind: 'other', label: 'question', created: null, author: 'member', url: 'https://github.com/acct-owner/harbor/issues/97', scope: null }
      ],
      why: null, sig: '7f3a1c9e2b4d6a80'
    }
  };
})();
/* the desk's two documents where no desk has run (this laptop, 2026-11-02; tools/captures/ops-status.json and
   ops-intake.json, the home folder cut to <home>): what the page gets on a host that is not lighthouse/ops-host */
window.ENGINE_SRC_OFF = {
  ops: { row: null, why: 'no sample yet at <home>/ops.jsonl (the desk\'s job writes it: `ops sample`)' },
  intake: { open: [], sig: '4f53cda18c2baa0c', why: 'no intake yet at <home>/intake-state.json (the desk\'s job writes it: `ops ingest`)' }
};

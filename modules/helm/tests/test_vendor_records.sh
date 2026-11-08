#!/usr/bin/env bash
# Vendor run records on local and ssh readers. Scratch HOME and repo only;
# the adapter raises if a vendor record tries to read a Claude transcript.
set -eu
B="$(cd "$(dirname "$0")/../bin" && pwd)"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
export HOME="$T/home" REGATTA_CONFIG="$T/config" PYTHONPYCACHEPREFIX="$T/pycache"
export REGATTA_HOME="$(cd "$B/../../.." && pwd)"
for v in $(env | sed -nE 's/^((CLAUDE|DISPATCH|PLAN|STALLS|HELM|SKIPPER)_[A-Za-z0-9_]*)=.*/\1/p'); do unset "$v"; done
unset REGATTA_UNATTENDED WEEKLY_RUN CLAUDECODE
mkdir -p "$HOME"
. "$(dirname "$0")/config_fixture.sh"; fixture_config "$REGATTA_CONFIG" || exit 1
printf '[user]\nname = test\nemail = test@example.invalid\n[init]\ndefaultBranch = main\n' > "$T/gitconfig"
export GIT_CONFIG_GLOBAL="$T/gitconfig"
QR="$T/repo"; QB=claude/test/vendor
git init -q -b main "$QR"
git -C "$QR" commit -q --allow-empty -m init
git -C "$QR" checkout -qb "$QB"
echo "vendor records: live between turns, record ends and replies on peers"
cat > "$T/vendor-records.py" <<'PY'
import json, os, subprocess, sys
from types import SimpleNamespace
from unittest.mock import patch
sys.path.insert(0,sys.argv[1])
import stalls
st={"mode":"vendor","agent":"antigravity","session":"vendor-run","pid":os.getpid(),"turn_pid":None,
    "repo":sys.argv[2],"wt":sys.argv[2],"branch":sys.argv[3],"topic":"vendor-build","started":1,
    "last_answer":"This text is still between turns."}
def no_transcript(*a,**kw): raise AssertionError("a vendor has no Claude transcript")
ad=SimpleNamespace(status=no_transcript,list=lambda:[],last_reply=no_transcript)
def view(alive,watcher=False):
    d=stalls.facts([("vendor.json",st)],ad,lambda s:alive,lambda s:not watcher,())
    d["raw"]={"vendor.json":dict(st)}
    return d
def judge(d,queued=None,queued_out=None):
    return stalls.judge_runs("buildbox-agy",d,[("buildbox-agy","vendor.json",dict(st))],set(),set(),100,
                             queued=queued,queued_out=queued_out)
assert judge(view(True)) == ([],[])  # turn_pid=None never means gone
st.update(ended=50,outcome="clean",end_reason="review and check clean",last_answer="A vendor answer without a closing line.")
s,u=judge(view(False))
assert len(s)==1 and s[0]["class"]=="S6" and s[0]["action"]=="raise" and not u
assert s[0]["rule"]=="done, no hand-over: it waits for /finish",s[0]
st["watcher"]=os.getpid()   # dispatch's shell still runs the hand-over: no launch yet is no stall
assert judge(view(False,watcher=True)) == ([],[])
st["ended"]=100-stalls.HANDOVER_GRACE-1   # the same live shell, past the grace: a hung hand-over raises
s,u=judge(view(False,watcher=True)); assert len(s)==1 and s[0]["class"]=="S6",s
st["ended"]=50
s,u=judge(view(False))   # the same recorded watcher, gone: no live hand-over, so it raises
assert len(s)==1 and s[0]["class"]=="S6" and s[0]["rule"]=="done, no hand-over: it waits for /finish",s[0]
st.pop("watcher")
handover_line=stalls.helmlib._common().HANDOVER_LINE
st.update(outcome="clean",launch="declined: its brief names open steps: docs/plan.md S2 — build it",
          last_answer=handover_line)
s,u=judge(view(False))
assert len(s)==1 and s[0]["class"]=="S6" and s[0]["action"]=="raise" and not u
assert s[0]["rule"]=="closing line: hand-over, its launch never started",s[0]
assert any("declined: its brief names open steps" in line for line in s[0]["evidence"]),s[0]
st.update(outcome="clean",launch="no launch — no hand-over: the mode is ask, the owner lands it; to land: run /finish on this branch",
          last_answer=handover_line)
s,u=judge(view(False))
assert len(s)==1 and s[0]["rule"]=="done, no hand-over: it waits for /finish",s[0]
st.update(outcome="clean",ending="requeued by dispatch --requeue",end_reason="requeued by dispatch --requeue",
          launch="no launch — it was requeued (dispatch --requeue): the session that continues it lands it; to land: let the queued or scheduled build finish, then hand over its result",
          last_answer="Done.")
s,u=judge(view(False),queued=lambda r,b,**kw:False)
assert len(s)==1 and s[0]["rule"]=="done, no hand-over: it waits for /finish",s[0]
assert any("it was requeued (dispatch --requeue)" in line for line in s[0]["evidence"]),s[0]
st.pop("ending",None)
st.update(outcome="clean",launch="",next_scheduled=True)
assert judge(view(False)) == ([],[])
st.pop("next_scheduled",None)
st.update(outcome="fallback",exit=3,end_reason="vendor pre-flight fallback")
assert judge(view(False)) == ([],[])
for patch_fields in ({"outcome":"held","exit":4,"end_reason":"vendor start refused","retry_claude":False},
                     {"outcome":"failed","exit":4,"end_reason":"refused for now: before any vendor turn: fetch","retry_claude":False},
                     {"outcome":"failed","exit":1,"end_reason":"the builder committed nothing","retry_claude":True}):
    st.update(**patch_fields)
    qout=[]
    assert judge(view(False),queued=lambda r,b,**kw:True,queued_out=qout) == ([],[])
    assert len(qout)==1 and qout[0]["branch"]==st["branch"]
    s,u=judge(view(False),queued=lambda r,b,**kw:False)
    assert len(s)==1 and s[0]["class"]=="S1" and s[0]["action"]=="raise" and not u
st.update(outcome="failed",exit=1,retry_claude=False,end_reason="vendor process failed")
s,u=judge(view(False)); assert len(s)==1 and s[0]["action"]=="raise" and not u
st.update(outcome="clean",launch="queued: finish")
assert judge(view(False)) == ([],[])
# The peer probe embeds facts(), so it must work without the local imports too.
rc=stalls._load_bin("dispatch-rc")
source=stalls.probe_source(rc)
assert '"last_answer" in st' in source
peer=os.path.join(os.environ["HOME"],"Library/Logs/claude-weekly/run-seed-runs")
os.makedirs(peer,exist_ok=True)
with open(os.path.join(peer,"vendor.json"),"w") as f: json.dump(st,f)
r=subprocess.run([sys.executable,"-c",source,"[]"],capture_output=True,text=True)
assert r.returncode==0,r.stderr
assert json.loads(r.stdout)["records"]["vendor.json"]["status"]["last_message"]==st["last_answer"]
with patch.dict(os.environ,STALLS_PEERS=""):
    assert stalls.peers()=={}
with patch.dict(os.environ):
    os.environ.pop("STALLS_PEERS",None)
    def cfg_lines(key):
        if key=="wharf-runs/ssh":
            return ["buildbox:","buildbox-ssh","# peer note"]
        if key=="regatta/fleet-ssh":
            return ["buildbox-antigravity:","antigravity@buildbox","# remote builder",
                    "buildbox-codex: codex@buildbox-ssh # remote builder alias",
                    "laptop-antigravity:","antigravity@localhost","# local builder",
                    "laptop-codex: codex@::1 # local ipv6 loopback",
                    "foreign-local:antigravity@localhost",
                    "foreign-v4:codex@127.0.0.1",
                    "foreign-v6:antigravity@::1",
                    "secnode-agent:secnode-ssh","laptop-peer:laptop-peer-ssh","other-user:bob@localhost"]
        return []
    with patch.object(stalls.helmlib._common(),"config_lines",side_effect=cfg_lines), \
            patch.object(stalls.helmlib,"host",return_value="laptop"):
        assert stalls.peers()=={"buildbox":"buildbox-ssh",
                                "buildbox-antigravity":"antigravity@buildbox",
                                "buildbox-codex":"codex@buildbox-ssh",
                                "laptop-antigravity":"antigravity@localhost",
                                "laptop-codex":"codex@::1"},stalls.peers()
    with patch.object(stalls.helmlib._common(),"config_lines",side_effect=cfg_lines), \
            patch.object(stalls.helmlib,"host",return_value="buildbox"):
        assert stalls.peers()=={"buildbox-antigravity":"antigravity@buildbox",
                                "buildbox-codex":"codex@buildbox-ssh"},stalls.peers()

import stalls_tick
s_agy={"class":"S6","host":"buildbox-antigravity","repo":"repo","topic":"vendor-build","branch":"claude/test/vendor",
       "key":["buildbox-antigravity","repo","vendor-build",None],"key_kind":"step","action":"raise","raise_to":"owner",
       "rule":"done, no hand-over: it waits for /finish","evidence":["record vendor.json"],"title":"repo · vendor-build",
       "plan":"ship-1","manager":"skipper-1","session":"vendor-run"}
s_cdx=dict(s_agy,host="buildbox-codex",key=["buildbox-codex","repo","vendor-build",None])
s_far=dict(s_agy,host="laptop",key=["laptop","repo","vendor-build",None])
s_other=dict(s_agy,host="otherbox-antigravity",key=["otherbox-antigravity","repo","vendor-build",None])
res_yard={"stalls":[s_agy,s_cdx,s_far,s_other],"unsure":[],"self_judging":[],"registry_torn":False,
          "hosts":["buildbox","buildbox-antigravity","buildbox-codex","laptop","otherbox-antigravity"],"notes":[]}
with patch.object(stalls_tick.helmlib,"host",return_value="buildbox"), \
        patch.object(stalls_tick.helmlib,"yard_hosts",return_value=({"buildbox"},False)):
    assert stalls.self_judging()==(set(),False)
    assert stalls_tick.acted_elsewhere(res_yard)=={"laptop","otherbox-antigravity"}
    mem=stalls_tick.Memory([])
    decs=[(s_agy,{"action":"raise","why":"vendor agy"},True),
          (s_cdx,{"action":"raise","why":"vendor cdx"},True),
          (s_far,{"action":"raise","why":"far"},True)]
    w,_=stalls_tick.wanted(res_yard,decs,mem,1000)
    assert {v["key"][0] for v in w.values()}=={"buildbox-antigravity","buildbox-codex"},w
    reported=[]
    log_file=os.path.join(os.environ["HOME"],"yard-stalls.jsonl")
    with patch.dict(os.environ,STALLS_LOG=log_file), \
            patch.object(stalls_tick,"mode",return_value=("armed","armed for test")), \
            patch.object(stalls_tick.stalls,"judge",return_value=dict(res_yard,stalls=[s_agy,s_far])), \
            patch.object(stalls_tick,"skipper_road",return_value={"plan":"ship-1"}), \
            patch.object(stalls_tick,"report",side_effect=lambda road,topic,status,prog:(reported.append((topic,status,prog)) or 0)), \
            patch.object(stalls_tick,"escalate",side_effect=lambda r,d,m,t,**kw:[x[0]["host"] for x in d]):
        out=stalls_tick.tick(dry_run=False,peer=True)
    assert [x[0]["host"] for x in out["decisions"]]==["buildbox-antigravity"],out["decisions"]
    assert out["escalations"]==["buildbox-antigravity"],out["escalations"]
    assert len(reported)==1 and reported[0][:2]==("vendor-build","blocked"),reported
    assert len(stalls_tick.read_log(log_file))==1
with patch.object(stalls_tick.helmlib,"host",return_value="laptop"), \
        patch.object(stalls_tick.helmlib,"yard_hosts",return_value=({"buildbox"},False)):
    assert stalls.self_judging()==({"buildbox"},False)
    res_lap=dict(res_yard,self_judging=["buildbox"])
    assert stalls_tick.acted_elsewhere(res_lap)=={"buildbox","buildbox-antigravity","buildbox-codex"}
print("vendor records: passed")
PY
python3 "$T/vendor-records.py" "$B" "$QR" "$QB"

import json, os
here = os.path.dirname(os.path.abspath(__file__))
M = ('Base directory for this skill', 'Another Claude session', 'Stop hook feedback', 'You are an unattended',
     'You adjudicate', 'Review branch', 'Continue from where', '15-minute report', 'War-room', '[Image',
     'Finish the current', '/code-review', 'Load the EnterWorktree', '[Request interrupted', 'Caveat:',
     'This session is being continued', 'Review the branch', 'Hook ')
out = open(os.path.join(here, 'human.jsonl'), 'w')
n = 0
for l in open(os.path.join(here, 'prompts.jsonl')):
    r = json.loads(l)
    x = r['x']
    if x.startswith(M):
        continue
    if len(x.split()) > 220:
        continue
    out.write(l)
    n += 1
print(n)

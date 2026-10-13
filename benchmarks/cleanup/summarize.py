import json,pathlib,statistics,re
p=pathlib.Path(__file__).parent
def norm(s): return re.sub(r'[^a-z0-9\s]','',s.lower()).split()
for f in p.glob('*.jsonl'):
 rows=[json.loads(l) for l in f.read_text().splitlines() if l.startswith('{')]
 if not rows: continue
 warm=[r for r in rows if r['round']==1]
 print(f.name,'calls',len(rows),'exact_words',sum(norm(r['output'])==norm(r['expected']) for r in rows),'first',round(rows[0]['seconds'],3))
 if warm: print('warm median',round(statistics.median(r['seconds'] for r in warm),3),'max',round(max(r['seconds'] for r in warm),3))
 for r in rows:
  if r['round']==0: print(r['id'],round(r['seconds'],3),r['output'])

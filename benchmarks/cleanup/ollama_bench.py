import json,time,urllib.request,pathlib,sys
p=pathlib.Path(__file__).parent
model=sys.argv[1]
cases=json.loads((p/'cases.json').read_text())
for r in range(2):
 for ident,source,expected in cases:
  body={'model':model,'messages':[{'role':'system','content':(p/'prompt.txt').read_text()},{'role':'user','content':'<transcript>'+source+'</transcript>'}],'stream':False,'think':False,'keep_alive':'10m','options':{'temperature':0,'seed':42,'num_ctx':4096,'num_predict':300}}
  start=time.perf_counter()
  with urllib.request.urlopen(urllib.request.Request('http://localhost:11434/api/chat',data=json.dumps(body).encode(),headers={'Content-Type':'application/json'}),timeout=180) as f: result=json.load(f)
  print(json.dumps({'model':model,'round':r,'id':ident,'input':source,'expected':expected,'output':result['message']['content'],'seconds':time.perf_counter()-start,'load_seconds':result.get('load_duration',0)/1e9,'prompt_seconds':result.get('prompt_eval_duration',0)/1e9,'generation_seconds':result.get('eval_duration',0)/1e9,'tokens':result.get('eval_count'),'done_reason':result.get('done_reason')}),flush=True)

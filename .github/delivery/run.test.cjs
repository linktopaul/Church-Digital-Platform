'use strict';
const test=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const vm=require('node:vm');
const planner=require('./planner.cjs');
function fixture({dryRun=false,failLabels=false,comments=[],checks=[],adopt=false}={}){
 const config={version:1,maxActive:1,maxPerAgent:{jules:1},enabledAgents:['jules'],tasks:[{issue:1,agent:'jules',ready:true,dependencies:[],owns:['feature/'],branch:'feature-one',...(adopt?{pullRequest:2}:{})}],leases:adopt?[{issue:1,agent:'jules',status:'active'}]:[]};
 const calls=[];let report;const failures=[];
 const issue={number:1,state:'open',labels:[]};
 const rest={issues:{listForRepo:async()=>[issue],listComments:async()=>comments,get:async()=>({data:issue}),createComment:async a=>{calls.push(['comment',a]);},addLabels:async()=>{calls.push(['labels']);if(failLabels)throw Error('permission denied');}},pulls:{list:async()=>adopt?[{number:2,head:{sha:'abc',ref:'feature-one'}}]:[]},checks:{listForRef:async()=>checks}};
 const github={rest,paginate:async(fn,args)=>fn(args)};
 const summary={addHeading(){return this;},addRaw(){return this;},addCodeBlock(){return this;},async write(){}};
 const module={exports:{}};
 vm.runInNewContext(fs.readFileSync('.github/delivery/run.cjs','utf8'),{module,exports:module.exports,require:name=>name==='./planner.cjs'?planner:name==='node:fs'?{readFileSync:()=>JSON.stringify(config),mkdirSync(){},writeFileSync:(_,body)=>{report=JSON.parse(body);}}:require(name),Date,Map,JSON});
 return {execute:()=>module.exports.run({github,context:{repo:{owner:'owner',repo:'repo'}},core:{summary,setFailed:m=>failures.push(m)},dryRun}),calls,failures,report:()=>report};
}
test('dry run performs no mutation',async()=>{const f=fixture({dryRun:true});await f.execute();assert.equal(f.calls.length,0);assert.equal(f.report().decision.dispatch.length,1);});
test('intent is persisted before triggering Jules',async()=>{const f=fixture();await f.execute();assert.deepEqual(f.calls.map(c=>c[0]),['comment','labels']);assert.match(f.calls[0][1].body,/"status":"dispatched"/);});
test('label failure retains dispatch record and reports failure',async()=>{const f=fixture({failLabels:true});await f.execute();assert.equal(f.calls[0][0],'comment');assert.equal(f.failures.length,1);assert.match(f.report().actions[0].status,/lease retained/);});
test('non-owner acceptance cannot release ownership',async()=>{const f=fixture({adopt:true,comments:[{user:{login:'other'},body:'<!-- delivery-state:v1 {"issue":1,"agent":"jules","status":"accepted","evidence":["https://github.com/o/r/pull/1"]} -->'}]});await f.execute();assert.equal(f.report().leases[0].status,'active');});
test('malformed owner state prevents dispatch',async()=>{const f=fixture({comments:[{user:{login:'owner'},body:'<!-- delivery-state:v1 {bad} -->'}]});await f.execute();assert.equal(f.calls.length,0);assert.equal(f.failures.length,1);});
test('missing review and aggregate gate do not summon implementer',async()=>{const f=fixture({adopt:true,checks:[{id:1,name:'Review acceptance',conclusion:'action_required'},{id:2,name:'gate',conclusion:'failure'}]});await f.execute();assert.equal(f.calls.length,0);});
test('actual failing feature check gets one bounded follow-up',async()=>{const f=fixture({adopt:true,checks:[{id:1,name:'Flutter mobile checks',conclusion:'failure',html_url:'https://github.com/o/r/actions/runs/1'}]});await f.execute();assert.equal(f.calls.length,1);assert.match(f.calls[0][1].body,/EXISTING session/);});

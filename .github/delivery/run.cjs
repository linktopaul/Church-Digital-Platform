'use strict';
// Trusted-main entrypoint invoked only by the metadata coordinator workflow.
const {plan}=require('./planner.cjs');
const fs=require('node:fs');
const MARK='delivery-state:v1';
function readRecord(body){const m=(body||'').match(/<!-- delivery-state:v1 (\{[^\n]*\}) -->/);if(!m)return null;return JSON.parse(m[1]);}
async function run({github,context,core,dryRun=false}){
 const config=JSON.parse(fs.readFileSync('.github/delivery/plan.json','utf8'));
 if(config.version!==1)throw Error('Unsupported delivery plan version');
 const {owner,repo}=context.repo;
 const [issues,pulls]=await Promise.all([
  github.paginate(github.rest.issues.listForRepo,{owner,repo,state:'all',per_page:100}),
  github.paginate(github.rest.pulls.list,{owner,repo,state:'open',base:'main',per_page:100})
 ]);
 const leaseMap=new Map(config.leases.map(x=>[x.issue,x]));
 const discussions=new Map(); const problems=[];
 for(const task of config.tasks){
  const comments=await github.paginate(github.rest.issues.listComments,{owner,repo,issue_number:task.issue,per_page:100});
  discussions.set(task.issue,comments);
  for(const c of comments){
   // Owner token comments only. A PR author/bot cannot release another worker.
   if(c.user?.login?.toLowerCase()!==owner.toLowerCase())continue;
   let record;try{record=readRecord(c.body);}catch{problems.push('Malformed owner assignment on #'+task.issue);continue;}
   if(!record)continue;
   if(record.issue!==task.issue||record.agent!==task.agent||!['active','dispatched','blocked','handoff','accepted'].includes(record.status)){
    problems.push('Invalid owner assignment on #'+task.issue);continue;
   }
   if(record.status==='accepted'&&(!Array.isArray(record.evidence)||!record.evidence.length||record.evidence.some(x=>typeof x!=='string'||!/^https:\/\/github.com\//.test(x)))){
    problems.push('Acceptance needs GitHub evidence on #'+task.issue);continue;
   }
   leaseMap.set(task.issue,record);
  }
 }
 const leases=[...leaseMap.values()];
 const decision=plan({tasks:config.tasks,issues,pulls,leases,maxActive:config.maxActive,maxPerAgent:config.maxPerAgent,enabledAgents:config.enabledAgents});
 decision.alerts.push(...problems);
 if(decision.alerts.length)decision.dispatch=[];
 const actions=[];
 if(!dryRun&&!decision.alerts.length){
  for(const selected of decision.dispatch){
   const task=config.tasks.find(t=>t.issue===selected.issue);
   // Recheck live task/labels/PRs immediately before recording intent.
   const current=(await github.rest.issues.get({owner,repo,issue_number:task.issue})).data;
   if(current.state!=='open'||current.labels.some(l=>['jules','in-progress','blocked'].includes(l.name)))continue;
   const liveComments=await github.paginate(github.rest.issues.listComments,{owner,repo,issue_number:task.issue,per_page:100});
   if(liveComments.some(c=>c.user?.login?.toLowerCase()===owner.toLowerCase()&&(c.body||'').includes('<!-- '+MARK+' ')))continue;
   const livePulls=await github.paginate(github.rest.pulls.list,{owner,repo,state:'open',base:'main',per_page:100});
   if(livePulls.some(p=>p.head?.ref===task.branch))continue;
   // Persist intent BEFORE triggering agent: failures retain the lease, no blind retry.
   const record={issue:task.issue,agent:task.agent,status:'dispatched',...(task.branch?{branch:task.branch}:{}),at:new Date().toISOString()};
   await github.rest.issues.createComment({owner,repo,issue_number:task.issue,body:'<!-- '+MARK+' '+JSON.stringify(record)+' -->\nDelivery assignment: '+task.agent+'. One session only. File ownership: '+task.owns.join(', ')+'. Dependencies accepted. Inspect existing activity before coding; preserve other agents\' work. Report session and branch here. No deployment, credentials, paid API, authentication bypass or parent closure. No automatic lease expiry or retry.'});
   try{
    if(task.agent!=='jules')throw Error('Codex unattended adapter is disabled; use explicit handoff');
    await github.rest.issues.addLabels({owner,repo,issue_number:task.issue,labels:['ready-for-dev','jules']});
    actions.push({issue:task.issue,status:'dispatch requested; awaiting agent acknowledgement'});
   }catch(error){actions.push({issue:task.issue,status:'dispatch failed; lease retained',error:error.message});core.setFailed('Dispatch failed for #'+task.issue+'; inspect retained lease before any retry');}
  }
 }
 // Bounded, owner-routed feedback; never start another coding session.
 if(!dryRun&&!decision.alerts.length){
  for(const task of config.tasks){
   const lease=leaseMap.get(task.issue);
   if(task.agent!=='jules'||!lease||!['active','dispatched','blocked'].includes(lease.status)||!task.pullRequest)continue;
   const pr=pulls.find(p=>p.number===task.pullRequest);
   if(!pr||pr.draft||(task.branch&&pr.head.ref!==task.branch))continue;
   const checks=await github.paginate(github.rest.checks.listForRef,{owner,repo,ref:pr.head.sha,per_page:100});
   const latest=new Map();for(const check of checks)if(!latest.has(check.name)||check.id>latest.get(check.name).id)latest.set(check.name,check);
   const failures=[...latest.values()].filter(c=>['failure','timed_out','action_required'].includes(c.conclusion));
   if(!failures.length)continue;
   const comments=await github.paginate(github.rest.issues.listComments,{owner,repo,issue_number:pr.number,per_page:100});
   const marker='<!-- delivery-feedback:'+pr.head.sha+' -->';
   if(comments.some(c=>(c.body||'').includes(marker)))continue;
   // Respect existing human/supervisor reminders within 24h; do not spam unchanged work.
   if(comments.some(c=>c.user?.login?.toLowerCase()===owner.toLowerCase()&&(c.body||'').includes('@jules')&&Date.now()-Date.parse(c.created_at)<86400000))continue;
   await github.rest.issues.createComment({owner,repo,issue_number:pr.number,body:marker+'\n@jules Continue the EXISTING session for child #'+task.issue+'; do not start a duplicate. Current head '+pr.head.sha+' has unresolved checks: '+failures.map(c=>c.name+' ('+c.conclusion+') '+c.html_url).join('; ')+'. Inspect current logs/review threads, fix within assigned files, add regression evidence, and push to this branch. Report exact blockers. No parent closure, paid service, credentials, deployment or weakened protections.'});
   actions.push({issue:task.issue,pullRequest:pr.number,status:'one bounded existing-session follow-up'});
  }
 }
 const report={version:1,generatedAt:new Date().toISOString(),dryRun,limits:{maxActive:config.maxActive,maxPerAgent:config.maxPerAgent},codexDispatch:'disabled: environment integration not verified; no automatic coding mentions',leases,decision,actions};
 fs.mkdirSync('delivery-report',{recursive:true});
 fs.writeFileSync('delivery-report/status.json',JSON.stringify(report,null,2));
 await core.summary.addHeading('Delivery coordinator').addRaw('Owner assignments and accepted dependencies govern dispatch. Existing leases never expire automatically. Codex unattended dispatch is disabled.\n').addCodeBlock(JSON.stringify(report,null,2),'json').write();
 if(decision.alerts.length)core.setFailed('Assignment integrity errors: '+decision.alerts.join('; '));
 return report;
}
module.exports={run,readRecord};

'use strict';

const HOLDING = new Set(['active', 'dispatched', 'blocked']);
const STATUSES = new Set([...HOLDING, 'handoff', 'accepted']);
const positive = n => Number.isSafeInteger(n) && n > 0;
const agentName = x => typeof x === 'string' && /^[a-z][a-z0-9-]*$/.test(x);
const optionalText = x => x === undefined || (typeof x === 'string' && x.trim());
const safePath = p =>
  typeof p === 'string' && p.length <= 240 && !p.startsWith('/') &&
  !/[\\:*?[\]{}\s]/.test(p) &&
  p.replace(/\/$/, '').split('/').every(s => s && s !== '.' && s !== '..');

function overlaps(a, b) {
  return a === b || (a.endsWith('/') && b.startsWith(a)) ||
    (b.endsWith('/') && a.startsWith(b));
}
function conflicts(a, b) {
  return a.owns.some(x => b.owns.some(y => overlaps(x, y)));
}
function fail(tasks, message) {
  return {
    dispatch: [],
    blocked: Array.isArray(tasks) ? tasks.filter(t => positive(t?.issue))
      .map(t => ({ issue: t.issue, reason: 'invalid configuration' })) : [],
    alerts: [message]
  };
}

function plan(input) {
  const { tasks, issues, pulls, leases, maxActive, maxPerAgent, enabledAgents } = input || {};
  if (![tasks, issues, pulls, leases, enabledAgents].every(Array.isArray) ||
      !positive(maxActive) || !maxPerAgent ||
      typeof maxPerAgent !== 'object' || Array.isArray(maxPerAgent)) {
    return fail(tasks, 'Invalid coordinator inputs or capacity settings.');
  }
  const byTask = new Map();
  for (const t of tasks) {
    if (!t || !positive(t.issue) || byTask.has(t.issue) ||
        !agentName(t.agent) || typeof t.ready !== 'boolean' ||
        !Array.isArray(t.dependencies) ||
        !t.dependencies.every(n => positive(n) && n !== t.issue) ||
        new Set(t.dependencies).size !== t.dependencies.length ||
        !Array.isArray(t.owns) || !t.owns.length || !t.owns.every(safePath) ||
        new Set(t.owns).size !== t.owns.length ||
        !optionalText(t.branch) || !optionalText(t.session)) {
      return fail(tasks, 'Invalid or duplicate task, dependency, ownership path, or identifier.');
    }
    byTask.set(t.issue, t);
  }
  const visiting = new Set(), visited = new Set();
  function cyclic(number) {
    if (visiting.has(number)) return true;
    if (visited.has(number)) return false;
    visiting.add(number);
    for (const dependency of byTask.get(number).dependencies) {
      if (!byTask.has(dependency) || cyclic(dependency)) return true;
    }
    visiting.delete(number);
    visited.add(number);
    return false;
  }
  if (tasks.some(t => cyclic(t.issue))) {
    return fail(tasks, 'Unknown dependency or dependency cycle.');
  }
  if (new Set(enabledAgents).size !== enabledAgents.length ||
      !enabledAgents.every(agentName) ||
      !tasks.every(t => positive(maxPerAgent[t.agent])) ||
      !Object.entries(maxPerAgent).every(([a, n]) => agentName(a) && positive(n))) {
    return fail(tasks, 'Invalid agent configuration or per-agent capacity.');
  }
  const byIssue = new Map();
  for (const issue of issues) {
    if (!issue || !positive(issue.number) || byIssue.has(issue.number) ||
        !['open', 'closed'].includes(issue.state) || !Array.isArray(issue.labels) ||
        !issue.labels.every(l => typeof l === 'string' || (l && typeof l.name === 'string'))) {
      return fail(tasks, 'Invalid or duplicate issue snapshot.');
    }
    byIssue.set(issue.number, issue);
  }
  if (!pulls.every(p => p && ['open', 'closed'].includes(p.state) &&
      (p.title === undefined || typeof p.title === 'string') &&
      (p.body == null || typeof p.body === 'string') &&
      (p.head?.ref === undefined || typeof p.head.ref === 'string'))) {
    return fail(tasks, 'Invalid pull request snapshot.');
  }
  const byLease = new Map();
  for (const lease of leases) {
    const task = byTask.get(lease?.issue);
    if (!task || byLease.has(lease.issue) || lease.agent !== task.agent ||
        !STATUSES.has(lease.status) ||
        !optionalText(lease.branch) || !optionalText(lease.session)) {
      return fail(tasks, 'Invalid, duplicate, or mismatched assignment lease.');
    }
    byLease.set(lease.issue, lease);
  }
  const alerts = [];
  const held = leases.filter(l => HOLDING.has(l.status)).map(l => byTask.get(l.issue));
  for (let i = 0; i < held.length; i++) {
    for (let j = i + 1; j < held.length; j++) {
      if (conflicts(held[i], held[j])) {
        alerts.push('Existing ownership conflict: #' + held[i].issue + ' and #' + held[j].issue + '.');
      }
    }
  }
  if (alerts.length) {
    return { dispatch: [], blocked: tasks.map(t => ({
      issue: t.issue, reason: 'existing ownership conflict'
    })), alerts };
  }
  const counts = Object.create(null);
  for (const t of held) counts[t.agent] = (counts[t.agent] || 0) + 1;
  const openPulls = pulls.filter(p => p.state === 'open');
  const dispatch = [], blocked = [], selected = [];
  const enabled = new Set(enabledAgents);
  for (const t of [...tasks].sort((a, b) => a.issue - b.issue)) {
    const issue = byIssue.get(t.issue);
    let reason;
    if (byLease.has(t.issue)) reason = 'assignment history exists; explicit reconciliation required';
    else if (!issue || issue.state !== 'open' || issue.pull_request) reason = 'issue is not open';
    else if (!t.ready) reason = 'task is not opted in';
    else if (!enabled.has(t.agent)) reason = t.agent + ' dispatch is unavailable';
    else if (issue.labels.some(l =>
      ['jules', 'in-progress', 'blocked'].includes((typeof l === 'string' ? l : l.name).toLowerCase()))) {
      reason = 'existing dispatch, session, or blocked label';
    } else if (openPulls.some(p => {
      if (t.branch && p.head?.ref === t.branch) return true;
      const refs = [...((p.title || '') + '\n' + (p.body || '')).matchAll(
        /\b(?:close[sd]?|fix(?:es|ed)?|resolve[sd]?)\s+(?:[\w.-]+\/[\w.-]+)?#(\d+)\b/gi
      )];
      return refs.some(m => Number(m[1]) === t.issue);
    })) reason = 'existing pull request';
    else if (t.dependencies.some(n => byLease.get(n)?.status !== 'accepted')) {
      reason = 'dependency lacks explicit acceptance';
    } else if (held.concat(selected).some(other => conflicts(t, other))) {
      reason = 'file ownership conflict';
    } else if (held.length + selected.length >= maxActive) reason = 'global capacity reached';
    else if ((counts[t.agent] || 0) >= maxPerAgent[t.agent]) reason = 'agent capacity reached';
    if (reason) blocked.push({ issue: t.issue, reason });
    else {
      dispatch.push({ issue: t.issue, agent: t.agent });
      selected.push(t);
      counts[t.agent] = (counts[t.agent] || 0) + 1;
    }
  }
  return { dispatch, blocked, alerts };
}

module.exports = { plan };

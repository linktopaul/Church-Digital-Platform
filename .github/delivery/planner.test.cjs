'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { plan } = require('./planner.cjs');

const task = (issue, extra = {}) => ({
  issue, agent: 'jules', ready: true,
  dependencies: [], owns: ['features/' + issue + '/'], ...extra
});
const issue = (number, extra = {}) => ({
  number, state: 'open', labels: [], ...extra
});
const lease = (number, extra = {}) => ({
  issue: number, agent: 'jules', status: 'active', ...extra
});
const fixture = extra => ({
  tasks: [task(1)], issues: [issue(1)], pulls: [], leases: [],
  maxActive: 4, maxPerAgent: { jules: 3, codex: 1 },
  enabledAgents: ['jules'], ...extra
});
const scheduled = input => plan(input).dispatch.map(t => t.issue);

test('dispatches an eligible task without mutating inputs', () => {
  const input = fixture(), before = JSON.stringify(input);
  assert.deepEqual(scheduled(input), [1]);
  assert.equal(JSON.stringify(input), before);
});

test('closed dependency is insufficient; explicit acceptance unlocks it', () => {
  const input = fixture({
    tasks: [task(1, { ready: false }), task(2, { dependencies: [1] })],
    issues: [issue(1, { state: 'closed' }), issue(2)]
  });
  assert.deepEqual(scheduled(input), []);
  input.leases = [lease(1, { status: 'accepted' })];
  assert.deepEqual(scheduled(input), [2]);
});

test('active and blocked leases retain ownership indefinitely', () => {
  for (const status of ['active', 'dispatched', 'blocked']) {
    const result = plan(fixture({
      tasks: [task(1, { owns: ['shared/'] }), task(2, { owns: ['shared/file.dart'] })],
      issues: [issue(1), issue(2)], leases: [lease(1, { status })]
    }));
    assert.deepEqual(result.dispatch, []);
    assert.match(result.blocked.find(x => x.issue === 2).reason, /ownership/);
  }
});

test('overlap in a proposed batch allows only the first task', () => {
  assert.deepEqual(scheduled(fixture({
    tasks: [task(2, { owns: ['a/b.dart'] }), task(1, { owns: ['a/'] })],
    issues: [issue(1), issue(2)]
  })), [1]);
});

test('directory matching respects path boundaries', () => {
  assert.deepEqual(scheduled(fixture({
    tasks: [task(1, { owns: ['api/'] }), task(2, { owns: ['api2/file.js'] })],
    issues: [issue(1), issue(2)]
  })), [1, 2]);
});

test('global and per-agent capacity include existing leases', () => {
  const input = fixture({
    tasks: [task(1), task(2), task(3)],
    issues: [issue(1), issue(2), issue(3)], leases: [lease(1)], maxActive: 2
  });
  assert.deepEqual(scheduled(input), [2]);
  input.maxActive = 4;
  input.maxPerAgent.jules = 1;
  assert.deepEqual(scheduled(input), []);
});

test('disabled Codex is queued rather than dispatched', () => {
  const result = plan(fixture({ tasks: [task(1, { agent: 'codex' })] }));
  assert.deepEqual(result.dispatch, []);
  assert.match(result.blocked[0].reason, /unavailable/);
});

test('assignment history prevents implicit redispatch or handoff', () => {
  for (const status of ['active', 'dispatched', 'blocked', 'accepted', 'handoff']) {
    assert.deepEqual(scheduled(fixture({ leases: [lease(1, { status })] })), []);
  }
});

test('open PR branch or closing reference prevents duplicate dispatch', () => {
  for (const pull of [
    { state: 'open', body: 'Fixes #1' },
    { state: 'open', title: 'Resolves owner/repo#1' },
    { state: 'open', head: { ref: 'agent/task-1' } }
  ]) {
    assert.deepEqual(scheduled(fixture({
      tasks: [task(1, { branch: 'agent/task-1' })], pulls: [pull]
    })), []);
  }
  assert.deepEqual(scheduled(fixture({
    pulls: [{ state: 'closed', body: 'Fixes #1' }]
  })), [1]);
});

test('dispatch, in-progress and blocked labels prevent dispatch', () => {
  for (const label of ['jules', { name: 'in-progress' }, { name: 'blocked' }]) {
    assert.deepEqual(scheduled(fixture({ issues: [issue(1, { labels: [label] })] })), []);
  }
});

test('invalid paths or duplicate ownership records fail closed', () => {
  for (const owns of [[], ['../secret'], ['/root'], ['a/../b'], ['a/**'], ['a\\b']]) {
    const result = plan(fixture({ tasks: [task(1, { owns })] }));
    assert.deepEqual(result.dispatch, []);
    assert.ok(result.alerts.length);
  }
  for (const extra of [
    { tasks: [task(1), task(1)] },
    { leases: [lease(1), lease(1)] },
    { leases: [lease(1, { agent: 'codex' })] }
  ]) assert.ok(plan(fixture(extra)).alerts.length);
});

test('existing conflicting leases suppress unrelated new work', () => {
  const result = plan(fixture({
    tasks: [task(1, { owns: ['a/'] }), task(2, { owns: ['a/x'] }), task(3)],
    issues: [issue(1), issue(2), issue(3)], leases: [lease(1), lease(2)]
  }));
  assert.deepEqual(result.dispatch, []);
  assert.match(result.alerts[0], /#1 and #2/);
});

test('unknown dependencies and cycles fail closed', () => {
  for (const tasks of [
    [task(1, { dependencies: [99] })],
    [task(1, { dependencies: [2] }), task(2, { dependencies: [1] })]
  ]) {
    const result = plan(fixture({ tasks }));
    assert.deepEqual(result.dispatch, []);
    assert.match(result.alerts[0], /dependency/);
  }
});

test('invalid snapshots fail closed', () => {
  for (const extra of [
    { issues: [issue(1), issue(1)] },
    { pulls: [{ state: 'unknown' }] },
    { maxActive: 0 },
    { enabledAgents: ['jules', 'jules'] }
  ]) {
    const result = plan(fixture(extra));
    assert.deepEqual(result.dispatch, []);
    assert.ok(result.alerts.length);
  }
});

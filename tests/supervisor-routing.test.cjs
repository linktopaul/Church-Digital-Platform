const {readFileSync} = require('node:fs');
const {test} = require('node:test');
const assert = require('node:assert/strict');

// Execute the actual inspection script with GitHub fixtures, so routing and
// independent review dispatch are checked together without issuing API calls.
const workflow = readFileSync('.github/workflows/mvp-cloud-supervisor.yml', 'utf8');
const script = workflow.split('          script: |\n')[1]
  .split('      - name: Send actionable feedback')[0]
  .split('\n').map(line => line.slice(12)).join('\n');
const AsyncFunction = Object.getPrototypeOf(async function () {}).constructor;
const inspect = new AsyncFunction('github', 'context', 'core', script);

async function route(comments, body = '', author = 'linktopaul') {
  let actions;
  const pr = {number: 50, user: {login: author}, body, mergeable: false,
    head: {sha: 'current', repo: {full_name: 'linktopaul/Church-Digital-Platform'}}};
  const pulls = {
    list: async () => [pr], get: async () => ({data: pr}),
    listCommits: async () => [{parents: [{}]}],
  };
  const github = {
    paginate: async (fn, args) => fn(args),
    rest: {pulls, actions: {createWorkflowDispatch: async () => {}},
      checks: {listForRef: async () => ({data: {check_runs: [{name: 'test', conclusion: 'failure'}]}})},
      issues: {listComments: async () => comments}},
  };
  await inspect(github, {repo: {owner: 'linktopaul', repo: 'Church-Digital-Platform'}}, {
    setOutput: (_, value) => { actions = JSON.parse(value); },
    summary: {addRaw: async () => {}, write: async () => {}},
  });
  return actions.map(a => a.body);
}
const marker = '<!-- implementation-owner:codex -->';
for (const [name, comments, body, author, expectJules] of [
  ['owner comment', [{user: {login: 'linktopaul'}, body: marker}], '', 'linktopaul', false],
  ['non-owner comment', [{user: {login: 'other'}, body: marker}], '', 'linktopaul', true],
  ['unmarked PR', [], '', 'linktopaul', true],
  ['owner PR body', [], marker, 'linktopaul', false],
  ['non-owner PR body', [], marker, 'other', true],
]) {
  test(name + ' routes implementation while preserving independent review', async () => {
    const actions = await route(comments, body, author);
    assert.equal(actions.some(body => body.includes('@jules')), expectJules);
    assert.equal(actions.filter(body => body.includes('@codex review')).length, 1);
    assert.equal(actions.some(body => body.includes('@codex address')), false);
  });
}

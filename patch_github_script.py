import re

with open('.github/workflows/pr-review-merge-gate.yml', 'r') as f:
    content = f.read()

# Replace the enablePullRequestAutoMerge mutation call to handle the "Pull request is in clean status" error
# and ignore it, as it means the auto-merge is already enabled or can't be enabled anymore (e.g. already merged/clean)
new_script_snippet = """
              if (!fresh.auto_merge) {
                try {
                  await github.graphql('mutation($id:ID!){enablePullRequestAutoMerge(input:{pullRequestId:$id,mergeMethod:SQUASH}){pullRequest{number}}}',{id:pull.node_id});
                } catch (e) {
                  if (e.message && e.message.includes('Pull request is in clean status')) {
                    core.info('PR #' + pull.number + ' auto-merge not updated (already in clean status).');
                  } else {
                    throw e;
                  }
                }
              }
"""

content = content.replace(
    "if (!fresh.auto_merge) await github.graphql('mutation($id:ID!){enablePullRequestAutoMerge(input:{pullRequestId:$id,mergeMethod:SQUASH}){pullRequest{number}}}',{id:pull.node_id});",
    new_script_snippet.strip()
)

with open('.github/workflows/pr-review-merge-gate.yml', 'w') as f:
    f.write(content)

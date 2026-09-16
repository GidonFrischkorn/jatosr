#!/usr/bin/env bash
#
# Apply the repository's branch model: merge settings, the default branch and
# the protection rulesets.
#
# Run it once `develop` exists on GitHub, and again whenever a file in
# .github/rulesets/ changes. It is idempotent: a ruleset whose name already
# exists on the remote is updated in place rather than duplicated.
#
#   ./.github/apply-repo-protection.sh --dry-run    # show what would change
#   ./.github/apply-repo-protection.sh              # apply every ruleset
#   ./.github/apply-repo-protection.sh .github/rulesets/main-gate.json   # one
#
# Requires the `gh` CLI, authenticated with an account that has admin rights
# on the repository (`gh auth status` must show the `repo` scope).
#
# WHY EACH BRANCH HAS TWO RULESETS. A bypass actor bypasses everything in a
# ruleset at once. Nobody can approve their own pull request, so while the
# package has one developer every merge needs the admin bypass for the
# approval rule, and in a single ruleset that bypass would also skip the
# required checks. The "review" ruleset holds only the approval requirement
# and can be bypassed on a pull request; the "gate" ruleset holds the checks,
# thread resolution, merge methods and history protection and has no bypass
# actors at all. Actor 5 / RepositoryRole is GitHub's base "admin" role.
#
# A repository admin can always edit or disable a ruleset in Settings > Rules,
# so nothing here can lock anyone out. That is also the emergency exit when a
# required check is broken for reasons outside the package.

set -euo pipefail

DRY_RUN=false
FILES=()

for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=true ;;
    -h|--help) sed -n '2,29p' "$0" | sed -E 's/^# ?//'; exit 0 ;;
    *) FILES+=("$arg") ;;
  esac
done

if [ ${#FILES[@]} -eq 0 ]; then
  FILES=("$(dirname "$0")"/rulesets/*.json)
fi

command -v gh >/dev/null 2>&1 || { echo "error: the gh CLI is not installed" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "error: jq is not installed" >&2; exit 1; }
gh auth status >/dev/null 2>&1 || { echo "error: gh is not authenticated" >&2; exit 1; }

REPO=$(gh repo view --json nameWithOwner --jq .nameWithOwner)
echo "repository: $REPO"
echo

# The develop rulesets and the default branch both need the branch to exist;
# `develop` is created from `main` by a push, not by this script.
if ! gh api "repos/$REPO/branches/develop" --silent 2>/dev/null; then
  echo "error: branch 'develop' does not exist on $REPO; create it first:" >&2
  echo "       git fetch origin && git push origin origin/main:refs/heads/develop" >&2
  exit 1
fi

# ---------------------------------------------------------------- repo settings
# Squash merges keep develop at one commit per unit of work. Merge commits are
# needed for release/ and hotfix/ branches into main and for sync/ branches
# into develop, so that develop always contains main. Rebase merges rewrite
# commits and would break that, so they are off. Which method each branch
# accepts is narrowed further by its gate ruleset.
echo "== repository settings =="
if [ "$DRY_RUN" = true ]; then
  current=$(gh api "repos/$REPO" --jq '"default_branch=\(.default_branch) squash=\(.allow_squash_merge) merge_commit=\(.allow_merge_commit) rebase=\(.allow_rebase_merge) delete_branch=\(.delete_branch_on_merge) update_branch=\(.allow_update_branch) auto_merge=\(.allow_auto_merge)"')
  echo "current:    $current"
  echo "would set:  default_branch=develop squash=true merge_commit=true rebase=false delete_branch=true update_branch=true auto_merge=true"
else
  gh api --method PATCH "repos/$REPO" \
    -f default_branch=develop \
    -F allow_squash_merge=true \
    -F allow_merge_commit=true \
    -F allow_rebase_merge=false \
    -F delete_branch_on_merge=true \
    -F allow_update_branch=true \
    -F allow_auto_merge=true \
    --jq '"default_branch=\(.default_branch) squash=\(.allow_squash_merge) merge_commit=\(.allow_merge_commit) rebase=\(.allow_rebase_merge) delete_branch=\(.delete_branch_on_merge) update_branch=\(.allow_update_branch) auto_merge=\(.allow_auto_merge)"'
fi
echo

# -------------------------------------------------------------------- rulesets
for file in "${FILES[@]}"; do
  [ -f "$file" ] || { echo "error: no such file: $file" >&2; exit 1; }
  name=$(jq -r .name "$file")
  echo "== ruleset: $name  ($file) =="

  existing=$(gh api "repos/$REPO/rulesets" --jq ".[] | select(.name == \"$name\") | .id" | head -n 1)

  if [ "$DRY_RUN" = true ]; then
    if [ -n "$existing" ]; then
      echo "would update existing ruleset $existing"
    else
      echo "would create a new ruleset"
    fi
    jq -r '
      "  applies to:  \(.conditions.ref_name.include | join(", "))",
      (if (.bypass_actors | length) == 0 then "  bypass:      none"
       else (.bypass_actors[] | "  bypass:      \(.actor_type) id=\(.actor_id) (\(.bypass_mode))") end),
      (.rules[] | "  rule:        \(.type)"),
      (.rules[] | select(.type == "required_status_checks")
         | .parameters.required_status_checks[]
         | "  must pass:   \(.context)  [app \(.integration_id // "any")]")' "$file"
    echo
    continue
  fi

  if [ -n "$existing" ]; then
    id=$(gh api --method PUT "repos/$REPO/rulesets/$existing" --input "$file" --jq .id)
    echo "updated ruleset $id"
  else
    id=$(gh api --method POST "repos/$REPO/rulesets" --input "$file" --jq .id)
    echo "created ruleset $id"
  fi

  # Read the ruleset back rather than trusting the payload: this is where a
  # wrong bypass actor, a dropped bypass mode or a mistyped status-check
  # context becomes visible.
  gh api "repos/$REPO/rulesets/$id" --jq '
    "  enforcement: \(.enforcement)",
    "  applies to:  \(.conditions.ref_name.include | join(", "))",
    (if ((.bypass_actors // []) | length) == 0 then "  bypass:      none"
     else (.bypass_actors[] | "  bypass:      \(.actor_type) id=\(.actor_id) (\(.bypass_mode))") end),
    (.rules[] | "  rule:        \(.type)"),
    (.rules[] | select(.type == "pull_request")
       | "  merge via:   \(.parameters.allowed_merge_methods | join(", "))  approvals=\(.parameters.required_approving_review_count)"),
    (.rules[] | select(.type == "required_status_checks")
       | .parameters.required_status_checks[]
       | "  must pass:   \(.context)  [app \(.integration_id // "any")]")'
  echo
done

if [ "$DRY_RUN" = false ]; then
  cat <<'EOF'
Done. Confirm by hand:

  1. Every "must pass" context above matches a check name that actually runs
     on pull requests into that branch. A context that never reports leaves
     pull requests waiting for a check that will never arrive.
  2. The review rulesets show a bypass row for RepositoryRole id=5 in
     pull_request mode; the gate rulesets show "bypass: none".
  3. `gh api repos/OWNER/REPO/rules/branches/develop` lists the rules of both
     the review and the gate ruleset.
EOF
fi

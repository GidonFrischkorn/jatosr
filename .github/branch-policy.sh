#!/usr/bin/env bash
#
# Check a pull request's source branch against the branch model in
# .github/CONTRIBUTING.md. Run by .github/workflows/branch-policy.yaml, whose
# `branch-policy` job is a required check on main and develop.
#
#   branch-policy.sh <base> <head> <head repo> <this repo> <head sha>
#
# The sync/ check needs `origin/main` and the head commit in the local clone
# (the workflow checks out with fetch-depth: 0).

set -euo pipefail

if [ $# -ne 5 ]; then
  echo "usage: branch-policy.sh <base> <head> <head repo> <this repo> <head sha>" >&2
  exit 2
fi

base=$1
head=$2
head_repo=$3
repo=$4
head_sha=$5

fail() {
  echo "::error title=branch policy::$1"
  exit 1
}

# main and develop are never merged as branches of this repository: a release
# is cut to release/, and develop takes main in through a sync/ branch. That
# keeps both out of reach of delete-branch-on-merge. A fork's own main is an
# ordinary contribution branch.
if [ "$head_repo" = "$repo" ]; then
  case "$head" in
    main | develop)
      fail "'$head' cannot be the source of a pull request. Cut release/X.Y.Z from develop, or sync/vX.Y.Z to bring main into develop."
      ;;
  esac
fi

if [ "$base" = main ]; then
  case "$head" in
    release/* | hotfix/*) ;;
    *)
      fail "Only release/* and hotfix/* branches merge into main; '$head' should target develop."
      ;;
  esac
  if [ "$head_repo" != "$repo" ]; then
    fail "Release and hotfix branches must be branches of $repo, not of a fork ($head_repo)."
  fi
fi

case "$head" in
  sync/*)
    if [ "$base" != develop ]; then
      fail "sync/* branches bring main into develop; this one targets '$base'."
    fi
    if ! git merge-base --is-ancestor origin/main "$head_sha"; then
      fail "'$head' does not contain origin/main. Recreate it with: git switch -c $head origin/develop && git merge --no-ff origin/main"
    fi
    ;;
esac

echo "ok: $head ($head_repo) -> $base"

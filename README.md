Hello!

# Getting Started

Run `./install.sh`. Warning, it hasn't been tested too thoroughly! Report any issues you find in this repo please!


# Git Config Things

### How can I see which git-config files are included in my repo?

```
git config --get-all --show-origin --show-scope include.path
```

Example:

```
% git config --get-all --show-origin --show-scope include.path
global  file:/Users/you/.gitconfig       /Users/you/.gitconfig.git-stuff-tracking
local   file:.git/config                 /Users/you/.gitconfig.git-stuff-aliases
```

### I don't want an included gitconfig file anymore. How do I remove it?

First find out where it's included (local, global, or both -- possibly more than once) with the command above. Then:

- If it's included once, unset it: `git config --unset --local include.path <literal-path>` (or `--global`).
- If it's included more than once, `--unset` will error -- use `--unset-all` instead. Be careful to pass the exact path you want to remove, or you might remove more than you meant to.

### Something in an included gitconfig sets a value I don't like. How do I override it?

Don't edit the included file directly if it's meant to stay in sync with something else (like a file an installer manages that is symlinked from another repo). Instead, override it: git-config uses a "last value wins" strategy, and `include.path` files are expanded in place, right where the `[include]` line appears.

Git always processes your global config (`~/.gitconfig`) first, then your repo's local config (`<repo>/.git/config`) -- expanding any `include.path` entries inline, in order, as it goes.

For example, say your local `.git/config` has:

```
...
[alias]
  aa = !sh -c 'echo 0'
[include]
  path = /path/to/gc-1
  path = /path/to/gc-2
[alias]
  aa = !sh -c 'echo 3'
...
```

...and `gc-1` sets `aa = !sh -c 'echo 1'`, `gc-2` sets `aa = !sh -c 'echo 2'`. `aa` is now defined four times. Running `git aa` gives `echo 3`, because it comes last. Comment that one out and you'd get `echo 2`; swap the order of the two `path` lines and you'd get `echo 1` instead. Whoever comes last, wins.

**To override one value:** find out where it currently comes from with `git config --show-origin --show-scope <key>`, then set your own value after it, in a scope that's processed later:

```
git config --local <key> <your-value>   # wins over anything in this repo's includes
git config --global <key> <your-value>  # wins over anything in your global includes
```

Common candidates: `branch.autosetupmerge`, `branch.autosetuprebase`, `push.default`, `commit.template`, `alias.<name>`.

**To override several values across many repos:** create a `~/.gitconfig-overrides` file with whatever settings you want, then set up a one-time alias:

```
git config --global alias.override "config --local --add include.path $HOME/.gitconfig-overrides"
```

Now, in any repo where you want your overrides to take effect, just run `git override` once -- it appends your overrides file to that repo's local `include.path` list, so it gets processed last and wins. (This only works locally -- global config is already processed before local, so a global-scope version of this trick can't win against a repo's local includes.)

### How do I unset a value that comes from an included file, instead of overriding it?

You can't `--unset` it directly -- `include.path` files are merged in dynamically, not copied in. Instead, override it explicitly with your own value (including an empty one, if the key allows it), using the same technique as above.

### How can I see my full, effective git configuration?

```
git config --list --show-scope --show-origin
```

This prints every key/value in your configuration, along with its scope (worktree/local/global/system) and which file it came from. Dump it to a file if that's easier to page through:

```
git config --list --show-scope --show-origin > configdump.txt
```

# Branch Tracking: The Dirty Details

A branch's "upstream" is two config keys, `branch.<name>.remote` + `branch.<name>.merge` (`branch.<name>.remote` can be a literal `.`, meaning "this local repo," not an actual remote). Together they decide where bare `git pull` pulls from and what `git status`/`git branch -vv` measure ahead/behind against. See them with `git branch -vv`, or read the raw keys with `git config branch.<name>.remote` / `git config branch.<name>.merge`.

There are two patterns for what ends up in those keys:

- **Local parent tracking** -- branches track the local branch they were created from.
- **Remote branch tracking** -- branches track the remote branch of the same name.

Here's exactly what happens under each, for the two things you actually do -- checking out a branch, and creating one:

**Local parent tracking:**
1. Checking out a branch that doesn't exist locally, but does exist as `origin/<name>` -- your new local branch tracks that remote branch.
2. Creating a new branch off a local branch -- your new branch tracks the local branch it was created from.

```
% git checkout an-existing-remote-branch
branch 'an-existing-remote-branch' set up to track 'origin/an-existing-remote-branch' by rebasing.
Switched to a new branch 'an-existing-remote-branch'

% git checkout parent
Switched to branch 'parent'
Your branch is up to date with 'main'.
% git checkout -b child
branch 'child' set up to track 'parent' by rebasing.
Switched to a new branch 'child'
```

**Remote branch tracking:**
1. Checking out a branch that doesn't exist locally, but does exist as `origin/<name>` -- same as above, your new local branch tracks that remote branch.
2. Creating a new branch off a local branch -- your new branch tracks **nothing**. Try to push it and you'll get an error:

```
% git checkout -b new-branch
Switched to a new branch 'new-branch'
% git push
fatal: The current branch new-branch has no upstream branch.
To push the current branch and set the remote as upstream, use

    git push --set-upstream origin new-branch
```

That error is doing a lot of quiet work: it's *telling you* to run `git push -u origin new-branch`, which sets the upstream to the same-named remote branch. Do that enough times across enough branches and you end up with "all my branches track their same-named remote" -- not because git set it up that way, but because the push error nudged you into setting it up that way, one branch at a time. Case 1 (checking out an existing remote branch) is identical either way; the two patterns only diverge on case 2 (creating a new branch), and remote tracking's case 2 is really "no tracking, plus a habit."

## The config that produces each pattern

`branch.autoSetupMerge` controls case 2 above -- what a *newly created* branch tracks. Per `git help config`, defaulting to `true`:

- `false` -- no automatic setup, ever.
- **`true` (the default)** -- automatic setup only when the branch you're creating *from* is itself a remote-tracking branch. This is case 1, always. It does **not** cover creating a branch off a local branch -- that's exactly the "tracks nothing, hits the push error" case above.
- `always` -- same as `true`, but *also* sets up tracking when the starting point is a local branch (case 2, local-parent style). This is local parent tracking.
- `inherit` -- copies the starting point's own tracking config to the new branch, instead of tracking the starting point itself.
- `simple` -- like `true`, but only when the new branch's name also matches the remote branch's name.

```
git config branch.autoSetupMerge always
```

`branch.autoSetupRebase` is a separate concern entirely -- it doesn't decide *what* gets tracked, only whether `git pull` rebases onto the upstream instead of merging, for a branch that already has one set up. Defaults to `never`:

- `never` (the default) -- `git pull` merges.
- `local` -- rebase, but only for branches tracking another local branch.
- `remote` -- rebase, but only for branches tracking a remote-tracking branch.
- `always` -- rebase for both.

```
git config branch.autoSetupRebase always
```

This repo's `.gitconfig.git-stuff-tracking` sets both to `always`: new branches track their local parent, and `git pull` rebases onto it instead of leaving merge commits in the middle of a stack.

## Living with local parent tracking

Since `git pull`/`git status` now compare against your local parent instead of `origin`, you lose the at-a-glance "am I behind the remote?" check, and you can't rely on bare `git push`/`git pull` to reach GitHub (the upstream isn't `origin`, so a plain `git push` has nowhere sensible on GitHub to go). This repo's `pup`/`pown` aliases talk to the same-named remote branch explicitly, without touching the branch's actual tracking config:

```
[alias]
  pup  = "!git push origin \"$(git rev-parse --abbrev-ref HEAD)\""
  pown = "!git pull origin \"$(git rev-parse --abbrev-ref HEAD)\""
```

One wrinkle: some PR-creation flows call `git push -u origin <branch>` under the hood when opening a pull request, which explicitly overwrites the upstream to the same-named remote branch -- silently flipping a local-parent-tracked branch to remote tracking. If your PR tooling does that, re-point it back afterward with `git branch --set-upstream-to=<local-parent>`. Driving PR creation by hand (e.g. `gh pr create`, as this repo's own workflow assumes) doesn't touch tracking at all.

# Not Yours and the Order of Git Configs
###### id-6d95

Put stuff here...

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

# Branch Tracking: Remote vs. Local Parent, and the `autoSetup*` Config

Every branch has an upstream. The upstream controls two things: where `git pull` (no arguments) pulls from, and what "ahead/behind" is measured against. There are two patterns for setting it, and which one you're in changes what `git pull` actually does -- so it's worth knowing which you're using.

### Remote branch tracking (git's default)

Each local branch tracks the remote branch of the same name. `git pull` and `git push` talk straight to `origin/<same-name>`. This is what most people are used to, and it needs no extra aliases.

It makes a stack of branches clunky, though: there's no local record of "this branch was built on top of that one," so there's no easy way to pull changes up through a stack, and tooling can only reconstruct as much of your branch tree as you have open pull-requests for.

### Local parent tracking (better for stacks)

Each local branch tracks the local branch it was created from -- its parent. `git pull` on a branch brings in changes from its parent, which is exactly what you want when syncing a stack. Because the parentage lives in your local upstreams (not on GitHub), your whole branch tree can be reconstructed straight from `git branch -vv` -- even branches that don't have an open PR yet.

The one real downside: `git pull` no longer points at the remote, so plain `git status` won't tell you how far ahead/behind `origin` you are. Two small aliases fix that -- this repo installs them as `pup`/`pown`:

```
[alias]
  pup  = "!git push origin \"$(git rev-parse --abbrev-ref HEAD)\""
  pown = "!git pull origin \"$(git rev-parse --abbrev-ref HEAD)\""
```

### Comparing the two

| | Local parent tracking | Remote branch tracking |
|---|---|---|
| Sync with the remote | `pup` / `pown` | `pull` / `push` |
| Bring changes up the stack | yes -- plain `git pull` | no easy way |
| See ahead/behind vs. the remote | no | yes |
| See ahead/behind vs. the local parent | yes | no |
| Reconstruct your whole stack from local state | yes | only as high as your open PRs go |

With `pup`/`pown` in your pocket, local parent tracking gets all the upside (effortless stacks, full tree reconstruction) with none of the "less typing" advantage remote tracking used to have over it. That's the recommendation: use local parent tracking, and keep `pup`/`pown` handy.

### The two config options that produce it

`branch.autoSetupMerge` controls what a newly created branch tracks:

- `true` (git's default): remote branch tracking, as above. Checking out a branch based on a remote-tracking branch tracks that remote branch; a brand-new local branch tracks nothing until you push it with `-u`.
- `always`: local parent tracking. A new branch tracks whatever local branch it was created from.

```
git config branch.autoSetupMerge always
```

With `always`, checking out an existing remote branch still tracks the remote, as expected -- but `git switch -c child` off a local `parent` branch makes `child` track `parent` instead.

`branch.autoSetupRebase` controls whether `git pull` rebases onto the upstream or creates a merge commit. For a stack, you almost always want rebase -- a merge commit partway up a stack makes history messy and later rebases harder.

```
git config branch.autoSetupRebase always
```

Set together, they give the full local-parent-tracking experience: `git pull` cleanly rebases your branch onto its parent, no merge commits. This repo's own `.gitconfig.git-stuff-tracking` sets both.

### One wrinkle

Some PR-creation flows silently re-point a branch's upstream to the same-named remote branch (a `git push -u origin <branch>` under the hood) the moment you open a pull-request -- flipping you back to remote tracking without telling you. If your PR tooling does that, you'll want a step that restores the local-parent upstream after PR creation. Driving PR creation by hand (e.g. `gh pr create`, as this repo's own workflow assumes) doesn't have this problem -- your upstreams are left alone.

# Not Yours and the Order of Git Configs
###### id-6d95

Put stuff here...

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

# Branch Tracking 

(What "Tracking" Actually Is, and the `autoSetup*` Config)

## What tracking actually is

"Tracking" isn't a mode or a mystery -- it's two config keys per branch:

- `branch.<name>.remote` -- which remote to fetch/push. It can also be `.` (a literal dot), which means "this local repository," not a remote at all.
- `branch.<name>.merge` -- which ref on that remote is the upstream `pull` merges from.

Together these two are what git calls a branch's upstream (its `@{upstream}`). You can read them directly:

```
git config branch.<name>.remote
git config branch.<name>.merge
```

or see them rendered for every branch at once with `git branch -vv`, or resolve the symbolic name with `git rev-parse --abbrev-ref <name>@{upstream}`.

Critically, `branch.<name>.remote` doesn't have to point at an actual remote. Per `git help config`: *"If you wish to setup `git pull` so that it merges into `<name>` from another branch in the local repository, you can point `branch.<name>.merge` to the desired branch, and use the relative path setting `.` for `branch.<name>.remote`."* That `.` trick -- tracking a **local** branch as your upstream -- is the entire mechanism behind what people call "local parent tracking." It's not a separate git feature; it's the same two keys, just pointed at `.` instead of `origin`.

## How tracking gets set up

Two ways:

- **Explicitly**, any time: `git branch --set-upstream-to=<upstream> [<branch>]` (or `-u` on `push`/`branch`), or the `--track`/`--no-track` flags on `branch`/`checkout`/`switch`.
- **Automatically**, at branch-creation time, governed by `branch.autoSetupMerge`.

## `branch.autoSetupMerge` (defaults to `true`)

This is the one that decides whether a brand-new branch gets an upstream at all, and from what. Per `git help config`, the valid values are:

- `false` -- no automatic setup, ever.
- **`true` (the default)** -- automatic setup happens **only when the starting point you're branching from is itself a remote-tracking branch** (e.g. `git switch -c foo origin/foo`). Branch off a plain local branch and, under the default, **nothing gets tracked at all** -- no upstream is set until you explicitly push with `-u` or set one by hand.
- `always` -- same as `true`, but also covers the case where the starting point is a local branch. Branch off local `parent` and the new branch tracks `parent` (via the `.` mechanism above); branch off `origin/foo` and it tracks that, same as `true` would.
- `inherit` -- if the starting point already has a tracking configuration, copy it to the new branch instead of tracking the starting point itself.
- `simple` -- automatic setup only when the starting point is a remote-tracking branch *and* the new branch has the same name as it.

The popular notion that "my branch tracks `origin/<same-name>` automatically" isn't actually produced by this default. It's usually the result of running `git push -u origin <branch>` at some point (which sets the upstream explicitly, as a side effect of the push), or of `git checkout <branch>` DWIM-creating a local branch from a uniquely-matching `origin/<branch>`. Plain branch-creation off another local branch, under the git default, tracks nothing.

```
git config branch.autoSetupMerge always
```

## `branch.autoSetupRebase` (defaults to `never`)

This one is unrelated to *what* gets tracked -- it only controls `branch.<name>.rebase`, i.e. whether `git pull` rebases onto the upstream instead of creating a merge commit, for branches that already have (or are getting) an upstream set up. Valid values:

- `never` (the default) -- never auto-set `rebase = true`.
- `local` -- auto-set it only when the tracked upstream is another local branch.
- `remote` -- auto-set it only when the tracked upstream is a remote-tracking branch.
- `always` -- auto-set it in both cases.

```
git config branch.autoSetupRebase always
```

## Putting it together

`autoSetupMerge` and `autoSetupRebase` are two independent axes -- one decides *whom* a new branch tracks, the other decides *how* `pull` integrates from whatever it tracks. Setting both to `always` doesn't, by itself, "create local parent tracking": it means (1) branching off a local branch will track that local branch as the upstream, via the `.`-remote mechanism above, and (2) `pull` will rebase rather than merge against whatever the upstream turns out to be, local or remote. The actual stack-friendly workflow -- where `git pull` on any branch in your stack rebases it onto the branch below -- only emerges if you also consistently branch each new piece off the local branch beneath it. This repo's `.gitconfig.git-stuff-tracking` sets both to `always` for exactly that reason.

One consequence worth knowing: since the upstream is just `branch.<name>.remote` + `branch.<name>.merge`, plain `git status`/`git pull` on a locally-tracked branch will compare against its local parent, not `origin`. Two small aliases in this repo, `pup`/`pown`, exist to talk to the same-named remote branch on demand without touching the branch's actual tracking config:

```
[alias]
  pup  = "!git push origin \"$(git rev-parse --abbrev-ref HEAD)\""
  pown = "!git pull origin \"$(git rev-parse --abbrev-ref HEAD)\""
```

## One wrinkle

Some PR-creation flows call `git push -u origin <branch>` under the hood when opening a pull request, which explicitly overwrites `branch.<name>.remote`/`.merge` to point at the same-named remote branch -- silently replacing a local-parent upstream with a remote one. If your PR tooling does that, you'll want to re-point the upstream back afterward with `git branch --set-upstream-to=<local-parent>`. Driving PR creation by hand (e.g. `gh pr create`, as this repo's own workflow assumes) doesn't touch tracking at all -- your upstreams are left exactly as you set them.

# Not Yours and the Order of Git Configs
###### id-6d95

Put stuff here...

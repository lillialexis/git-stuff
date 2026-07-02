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


# Not Yours and the Order of Git Configs
###### id-6d95

Put stuff here...

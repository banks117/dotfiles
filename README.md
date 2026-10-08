# Dotfiles

Uses GNU stow which is a symlink manager to easily setup and manage dotfiles on a system.

## What's Included

**Configurations:** Zsh, Neovim, WezTerm, Starship prompt, Git, GitHub CLI, Claude Code, EditorConfig

**CLI Tools:** bat, fzf, fd, ripgrep, zoxide, git-delta

**macOS Apps:** WezTerm, Firefox, Rectangle, Maccy, Notion, DBeaver, KeepingYouAwake

## Setup

Clone the repo in your home directory:
```
git clone git@github.com:brandonmbanks/dotfiles.git
cd dotfiles
```

Run the setup script to install Homebrew, packages, and configure macOS settings:
```
./setup.sh
```

Then use stow to symlink the dotfiles:
```
stow .
```

Stow will error when files on your computer have identical locations and names to files in the `dotfiles` directory. Stow doesn’t want to overwrite your local files.

Back up the files if they’re useful, delete them if they aren’t.

Run `stow .` again until you don’t get any errors.

You can also use `stow --adopt .` to move the conflicting file into the `dotfiles` directory. This will overwrite the file in the `dotfiles` directory.

Your dotfile setup is complete!

Treat your dotfile management system like any other Git project. Make any changes in the `dotfiles` directory.

### Work config file
Optionally, create a file in your home directory called `workconfig.zsh`. Here you will add any exports or PATH changes only needed for a work machine.

```
touch ~/workconfig.zsh
```

### Work Claude Code settings
`~/.claude/settings.json` is generated rather than stowed. `.claude/sync-settings.sh`
builds it from the tracked `.claude/settings.json`, plus `~/.claude/work.settings.json`
if it exists. Put work-only settings (plugins, marketplaces, extra hooks or
permissions) in the overlay. It lives outside the repo, so it is never tracked.

Objects merge key by key and arrays are appended, so the overlay only needs what it
adds. Rerun the script after editing either file:

```
~/.claude/sync-settings.sh
```

Changes made through Claude Code itself (`/model`, `/config`, plugin installs) only
land in the generated file, so copy anything worth keeping into the base or overlay.

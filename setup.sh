#!/bin/bash
set -e

if ! which -s brew; then
    # Install Homebrew
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
else
    echo "brew already installed"
fi

# install all brew packages
if [ ! -f "Brewfile" ]; then
    echo "Error: Brewfile not found"
    exit 1
fi
brew bundle

# apple settings
# trackpad tap to click
defaults write com.apple.driver.AppleBluetoothMultitouch.trackpad Clicking -bool true
defaults write com.apple.AppleMultitouchTrackpad Clicking -bool true
# fix scroll direction
defaults write -g com.apple.swipescrolldirection -bool NO
# enable key repeat
defaults write -g InitialKeyRepeat -int 15
defaults write -g KeyRepeat -int 2
# auto hide dock
defaults write com.apple.dock autohide -bool true
# adjust dock icons size (default is 64)
# defaults write com.apple.dock tilesize -int 64
# show battery percentage
defaults write com.apple.controlcenter BatteryShowPercentage -bool true
# allow quitting finder
defaults write com.apple.finder QuitMenuItem -bool true
# set finder to column view
defaults write com.apple.Finder FXPreferredViewStyle -string "clmv"
# show all filename extensions
defaults write NSGlobalDomain AppleShowAllExtensions -bool true

# restart affected apps to apply settings
killall ControlCenter Finder Dock 2>/dev/null || true

# update settings
/System/Library/PrivateFrameworks/SystemAdministration.framework/Resources/activateSettings -u

# install volta
if ! which -s volta; then
    curl https://get.volta.sh | bash
else
    echo "volta already installed"
fi

# install mise (manages go, node, etc.)
if ! which -s mise; then
    curl https://mise.run | sh
else
    echo "mise already installed"
fi

# install zap (--keep preserves existing .zshrc)
# https://github.com/zap-zsh/zap?tab=readme-ov-file#install
if [ ! -d "$HOME/.local/share/zap" ]; then
    curl -s https://raw.githubusercontent.com/zap-zsh/zap/master/install.zsh | zsh -s -- --branch release-v1 --keep
else
    echo "zap already installed"
fi

if [ ! -d "wezterm-icon" ]; then
    git clone https://github.com/mikker/wezterm-icon.git
    cd wezterm-icon
    make install
    cd ..
else
    echo "wezterm-icon already exists, skipping clone"
fi

# symlink dotfiles
stow .

# build ~/.claude/settings.json (base + optional work overlay)
./.claude/sync-settings.sh

#!/bin/bash

set -e

source ~/.dotfiles/functions/bash_support.sh
echodo ln -sf ~/.dotfiles/Brewfile ~/Brewfile
echodo ln -sf ~/.dotfiles/Brewfile.lock.json ~/Brewfile.lock.json
echodo ln -sf ~/.dotfiles/bashrc ~/.bashrc
echodo ln -sf ~/.dotfiles/bash_profile ~/.bash_profile
echodo ln -sf ~/.dotfiles/gemrc ~/.gemrc
echodo ln -sf ~/.dotfiles/gitconfig ~/.gitconfig
echodo ln -sf ~/.dotfiles/gitignore ~/.gitignore
echodo ln -sf ~/.dotfiles/gemrc ~/.gemrc
echodo ln -sf ~/.dotfiles/irbrc ~/.irbrc
echodo ln -sf ~/.dotfiles/bundle_config ~/.bundle/config

if [ ! -d ~/.dotfiles/locals ]; then
	echodo mkdir ~/.dotfiles/locals
fi

./update.sh

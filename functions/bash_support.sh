C_RED="\033[1;31m"
C_GREEN="\033[1;32m"
C_YELLOW="\033[0;33m"
C_BLUE="\033[1;34m"
C_AQUA="\033[1;36m"
C_GREY="\033[1;90m"

C_RESET="\033[0m"

# `resource` reload bash profile
function resource(){
  echodo source ~/.bash_profile
}

function resource_if_modified_since(){
  if (( $* < $(last_bash_profile_modification) )) ; then
    resource
  fi
}

function last_bash_profile_modification(){
  stat -f %m ~/.dotfiles/{bash_profile,functions/*.sh,locals/git-completion.bash} | sort -rn | head -n 1
}

function escape_spaces() {
  sed -E 's/([^\]) /\1\\ /g'
}

function escape_brackets() {
  sed -E 's/([^\])([()])/\1\\\2/g'
}

function quote_lines() {
  while read -r line; do
    echo "\"$line\""
  done
}

function echodo(){
  ( echo -e "$C_GREY$*$C_RESET" )>/dev/tty
  eval $*
}

function echoerr(){
  ( echo -e "$C_RED$*$C_RESET" )>&2
  return 1
}

function alias_frequency() {
  history | sed -E "s/ *[0-9]+\*? *[0-9 :-]+ *//" | sort | uniq -c | sort -rn | head -50
}

alias default_latest_ruby="ls ~/.rubies | grep ruby- | sort -t- -k2,2 -n | tail -1 | cut -d '/' -f 1 > ~/.ruby-version"

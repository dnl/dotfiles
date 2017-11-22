export VERTICAL='bikeexchange'
alias sverticals="subl -nw ~/.dotfiles/locals/verticals"
alias vertical_rows="cat ~/.dotfiles/locals/verticals"

alias missing_verticals='comm -13 <(long_verticals | sort ) <(marketplacer verticals | sort)'

function short_vertical() {
  vertical_field '$1' $*
}

function long_vertical() {
  vertical_field '$2' $*
}

function vertical_row_number() {
  vertical_field 'NR' $*
}

function vertical_prod_server() {
  vertical_field '$3' $*
}
function vertical_staging_server() {
  vertical_field '$4' $*
}
function vertical_demo_server() {
  vertical_field '$5' $*
}

function vertical_field() {
  local vertical=${2:-$VERTICAL}
  local column=$1
  vertical_rows | awk -F' *: *' "/^$vertical|: $vertical/ {print $column; count++; if(count=1) exit}"
}


function v(){
  local maybe_vertical=$1
  if [[ ! -z $maybe_vertical ]]; then
    local vertical=$(long_vertical $maybe_vertical)
    if [ -z "$vertical" ]; then
      echoerr "No such vertical"
    elif [[ "$vertical" != "$VERTICAL" ]]; then
      echodo export VERTICAL=$vertical && title Terminal
    fi
  fi
}

function vdl() {
  v $* && echodo "yes | DISABLE_MARKETPLACER_CLI_PRODUCTION_CHECK=1 m database update $VERTICAL" && rds
}
function vdlr() {
  vdl $* && reindex_all
}
function reindex_all() {
  echodo "rails r 'ES::Indexer.reindex_all'"
}


function vrd() {
  v $* && rd
}

function vrds(){
  v $* && rds
}

function vrc() {
  if (( $# == 2 )); then
    v $1 && remote_console $2
  else
    v $1 && rc
  fi
}

function remote_console() {
  local server=$1

  case $server in
    "prod") local host=$(vertical_prod_server);;
    "demo") local host=$(vertical_demo_server);;
    "staging") local host=$(vertical_staging_server);;
    "office") local host="office.int";;
    *) local host=$server;;
  esac

  if [[ -z "$host" ]]; then
    echoerr "No $server server set up for $VERTICAL"
  else
    title "Console $server" && echodo script/console $host $VERTICAL
  fi
}

function prepare_app_with_webkit() {
  ys
  prepare_app
  wait_for_ports 3808
}

function prepare_app() {
  ( ports_respond 3306 || echodo docker start m-mysql & )
  ( ports_respond 6379 || brew services start redis & )
  pgrep sidekiq >/dev/null || echodo "ttab -G 'title Sidekiq; bundle exec sidekiq; exit'"
  ( ports_respond 1080 || echodo mailcatcher & )
  wait_for_ports 3306 1080 6379
}

function vrs() {
  local path="$2"
  local vertical_or_path="$1"

  if [[ -z "$path" ]]; then
    if [[ "$vertical_or_path" =~ ^/.* ]]; then
      local path="$vertical_or_path"
      local vertical=""
    else
      local path="/"
      local vertical=$vertical_or_path
    fi
  fi
  prepare_app_with_webkit
  local row=$((($(vertical_row_number $vertical) - 1)))
  v $vertical && rs $row $VERTICAL $path
}

function vrt() {
  if [[ "$*" == *"/features/"* ]]; then
    prepare_app_with_webkit
  else
    prepare_app
  fi
  rt $*
}

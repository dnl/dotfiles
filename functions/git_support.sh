# source ./bash_support.sh

function git_untracked(){
  git ls-files --others --exclude-standard
}

function git_track_untracked(){
  if [[ ! -z "$(git_untracked)" ]]; then
    echodo git add -N $(git_untracked | quote_lines)
  fi
}

function git_untrack_new_blank() {
  local newblank=$(git diff --cached --numstat --no-renames --diff-filter=A | awk -F'\t' '/^0\t0\t/ { print $3 }' | quote_lines)
  if [[ ! -z "$newblank" ]]; then
    echodo git reset -- $newblank
  fi
}

function git_modified(){
  eval git diff --name-only --cached --diff-filter=ACM "${@/#/\*.}"
}

# this is horrifying
# I would like to pass line numbers to rubocop but they don't want you to do that because that's not _really_ going to catch all the issue, especially spacing issues
# but it's at least (roughly) consistent with what rubocop does with pronto
function rubocop_only_changed_lines(){
  local modified_grep_arguments_with_line_numbers=$(for file in $(git_modified rb); do git blame -fs -M -C ..HEAD "$file"; done | awk -F' ' '/^0+ / {printf " -e \"" $2 "\033[0m:" $3+0 ":\""}')
  if [[ ! -z "$modified_grep_arguments_with_line_numbers" ]]; then
    echodo bundle exec rubocop --force-exclusion --except Metrics/AbcSize,Metrics/PerceivedComplexity,Metrics/CyclomaticComplexity --color $(git_modified rb) |
      eval grep -A 2 -F $modified_grep_arguments_with_line_numbers |
      awk '
        BEGIN {num_printed = 0}
        {
          if(NR==1 || prev=="--" || (prev_printed==1 && substr($0,1,1) == " ")) {
            prev_printed=1;
            print $0;
            num_printed++
          } else {
            prev_printed=0
          };
          prev=$0
        };
        END { exit num_printed }'
  fi
}



function git_handle_conflicts {
  # store merge flags
  cp .git/MERGE_MSG /tmp/conflict_MERGE_MSG
  local merge_head=$(cat .git/MERGE_HEAD)

  # prepare working directory for interactive add
  git_prepare_content_conflicts
  git_prepare_their_deletions
  git_prepare_our_deletions

  # interactive add
  git_track_untracked
  git add -p

  # clean up un-added
  git_untrack_new_blank

  git stash save --keep-index --include-untracked --quiet
  comm -12 <(git_status_filtered ?? | sort) <(git_status_filtered 'D ' | sort) | xargs rm

  # restore merge flags
  cp /tmp/conflict_MERGE_MSG .git/MERGE_MSG
  echo -e $merge_head > .git/MERGE_HEAD
}

function git_status_filtered() {
  git status --porcelain | grep -F "$* " | colrm 1 3 | quote_lines
}

function git_conflicts_with_line_numbers(){
  git_status_filtered UU | xargs grep -nHoE -m 1 '^<{6}|={6}|>{6}' | cut -d: -f1-2 | quote_lines
}

function git_prepare_content_conflicts() {
  git_open_conflicts
  git_status_filtered UU | xargs git add
}

function git_prepare_their_deletions() {
  local conflicted=$(git_status_filtered UD)
  if [[ ! -z "$conflicted" ]]; then
    git rm $conflicted
    git reset --quiet -- $conflicted # so we can interactively add the removal in the git add conflicts step
  fi
}

function git_prepare_our_deletions() {
  local conflicted=$(git_status_filtered DU)
  if [[ ! -z "$conflicted" ]]; then
    git add $conflicted
    git reset --quiet -- $conflicted # so we can interactively re-add in the git add conflicts step
    git add -N $conflicted
  fi
}

function git_open_conflicts() {
  local active_conflicts=$(git_conflicts_with_line_numbers)
  if [[ ! -z "$active_conflicts" ]]; then
    git_edit $active_conflicts && git_open_conflicts
  fi
}

function git_edit() {
  echodo $(git config core.editor) "$@"
}

# TODO: remove switching to master if I don't have to
function git_purge() {
  echodo git checkout master
  echodo git fetch -p

  local local_merged=$(git_non_release_branch_list --merged)
  [ ! -z "$local_merged" ] && echodo git branch -d $local_merged
  local tracking_merged=$(git_non_release_branch_list -r --merged)
  [ ! -z "$tracking_merged" ] && echodo git branch -rd $tracking_merged

  gbb
}

function git_non_release_branch() {
  if (git_current_branch | grep -qEx $(git_release_branch_match)); then
    echoerr "can't do that on a release branch"
  fi
}

# `git_current_branch [optional_prefix]` the current branch name possibly with a prefix
function git_current_branch() {
  git rev-parse --symbolic-full-name --abbrev-ref HEAD 2>/dev/null
}

function git_prompt_current_branch() {
  local branch
  branch=$(git_current_branch)
  if [[ $branch == 'HEAD' ]]; then
    branch=$(git branch --format='%(refname:short)' --contains HEAD | grep -Evx "($(git_release_branch_match)|\\(HEAD detached at.*)")
    branch="$branch[$(git rev-parse --short HEAD)]"
  fi
  [[ ! -z $branch ]] && echo "$1$branch"
}

function git_current_repo() {
  basename "$(git config --get remote.origin.url 2>/dev/null)" .git
}

function git_log_range() {
  local from=$1
  local to=${2:-HEAD}
  [[ "$from" != "$(git_current_branch)" ]] && echo "$from".."$to"
}

function git_branch_list() {
  git branch --all --list --format="%(refname:short)" $*
}

function git_release_branch_list() {
  git_branch_list "$@" | grep -Ex "$(git_release_branch_match)"
}

function git_non_release_branch_list() {
  git_branch_list "$@" | grep -Evx "$(git_release_branch_match)"
}

function git_force_pull_release_branches() {
  local branches;
  branches=$(git_release_branch_list origin/* | colrm 1 7)
  if [[ ! -z "$branches" ]]; then
    echodo git fetch --force origin $branches
  fi
}

function git_release_branch_match() {
  case $(git_current_repo) in
    marketplacer) echo '(origin/)?(master$|release/.*)';;
    dotfiles)     echo 'origin/master';;
    *)            echo '(origin/)?master';;
  esac
}

# `git_rebasable` checks that no commits added since this was branched from master have been merged into release/*
# `git_rebasable commit-ish` checks that no commits added since `commit-ish` have been merged into something release-ish
function git_rebasable() {
  git_non_release_branch
  git_force_pull_release_branches
  git_rebasable_quick
}

function git_rebasable_quick() {
  git_non_release_branch
  local base=${1:-master}
  local since_base=$(git rev-list --count "$base"..HEAD)
  local unmerged_since_base=$(git rev-list --count $(git_release_branch_list | sed 's/$/..HEAD/'))
  if (( $since_base > $unmerged_since_base )); then
    echoerr some commits were merged to a release branch, only merge from now on
  fi
}

function git_rebase_i() {
  GIT_SEQUENCE_EDITOR=: echodo git rebase --interactive --autosquash --autostash "$@"
}

function git_system() {
  local path=$(git rev-parse --show-toplevel)
  if [[ "$path" == $HOME/.gem ]] || [[ "$path" == $HOME/Library ]] || [[ "$path" != $HOME/* ]]; then
    true
  else
    false
  fi
}

function git_authors() {
  echodo git shortlog -sen && echodo git shortlog -secn
}

function git_status_clean() {
  if [[ -z "$(git status --porcelain 2>/dev/null)" ]]; then
    true
  else
    false
  fi
}

function git_status_color() {
  if git_status_clean; then
    printf "$C_GREEN" ""
  else
    printf "$C_RED" ""
  fi
}

function git_changed_files() {
  git diff-tree -r --name-only --no-commit-id ORIG_HEAD HEAD
}

function git_file_changed() {
  git_changed_files | grep -xE "$1"
}

function git_unstage() {
  local has_staged=$(git diff --cached --numstat --no-renames | grep -Ev "^0\t0\t")
  if [[ ! -z "$has_staged" ]]; then
    echodo git reset --quiet -- && git_track_untracked
  fi
}

function git_stash() {
  git_untrack_new_blank && echodo git stash -u "$@"
}

function git_uncommit() {
  echodo git reset --quiet HEAD^ --
}
function git_fake_auto_stash() {
  if [[ ! -z "$(git diff)$(git ls-files --others --exclude-standard)" ]]; then
    if [[ ! -z "$(git diff --cached)" ]]; then
      git commit --no-verify --quiet --message "fake autostash index"
      git_untrack_new_blank
      echodo git stash save --include-untracked --quiet "fake autostash"
      git reset --soft HEAD^ --quiet
    else
      echodo git stash save --include-untracked --quiet "fake autostash"
    fi
  fi
}

function git_fake_auto_stash_pop() {
  while [[ "$(git stash list -n 1)" = "stash@{0}: On $(git_current_branch): fake autostash" ]]; do
    echodo git add .
    echodo git stash apply --index
    local conflicts=$(git grep -lE '^<{6}|>{6}' | quote_lines)
    if [[ ! -z "$conflicts" ]]; then
      echodo git checkout --theirs $conflicts
    fi
    echodo git stash drop --quiet
    echodo git reset --quiet --
  done
}

function git_undo () {
  echodo git stash save --include-untracked --quiet
  echodo git reset --hard HEAD@{1}
}

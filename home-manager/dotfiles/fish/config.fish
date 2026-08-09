set -U fish_greeting

alias cat="bat"
alias file="mediainfo"
alias nixfmt-aligned="~/.config/scripts/nixfmt-aligned"

set -q KREW_ROOT; and set -gx PATH $PATH $KREW_ROOT/.krew/bin; or set -gx PATH $PATH $HOME/.krew/bin
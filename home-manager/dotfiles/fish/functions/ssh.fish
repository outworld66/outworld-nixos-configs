function ssh --description 'ssh with xterm-ghostty terminfo upload'
    # agterm/ghostty TERM is missing on most hosts, making less warn
    # "terminal is not fully functional". Upload our terminfo entry
    # before connecting (ghostty docs, same fix as alacritty uses):
    #   infocmp -x xterm-ghostty | ssh HOST -- tic -x -
    # Best effort: first non-option arg is assumed to be the host
    # (ssh -p 2222 host misparses), BatchMode skips password prompts,
    # any failure is ignored — the real ssh below always runs.
    if test "$TERM" = xterm-ghostty
        for arg in $argv
            if test -n "$arg"; and not string match -q -- '-*' $arg
                infocmp -x xterm-ghostty | command ssh -T \
                    -o BatchMode=yes -o ConnectTimeout=3 \
                    $arg -- 'tic -xe xterm-ghostty -' >/dev/null 2>&1
                break
            end
        end
    end
    command ssh $argv
end

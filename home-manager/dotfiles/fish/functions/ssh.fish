function ssh --description 'ssh with TERM downgraded to xterm-256color'
    # agterm/ghostty sets TERM=xterm-ghostty, which is missing on most
    # remote hosts — ncurses programs exit with "Error opening terminal".
    # Downgrade TERM for the ssh child only; local apps keep full ghostty.
    if test "$TERM" = xterm-ghostty
        set -lx TERM xterm-256color
    end
    command ssh $argv
end

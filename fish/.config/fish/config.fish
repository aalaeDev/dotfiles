if status is-interactive
    # Commands to run in interactive sessions can go here
    # Each kitty window gets its own tmux session; exiting tmux closes the
    # window, and closing the window destroys the session (destroy-unattached)
    if not set -q TMUX; and test "$TERM" = xterm-kitty
        tmux new-session; and exit
    end

    # fetch
end

alias c='clear'                                                        # but don't use this one tho! just press `CLTR+l`
alias l='eza -lh --icons=auto'                                         # long list
alias ls='eza -1 --icons=auto'                                         # short list
alias ll='eza -lha --icons=auto --sort=name --group-directories-first' # long list all
alias ld='eza -lhD --icons=auto'                                       # long list dirs
alias lt='eza --icons=auto --tree'                                     # list folder as tree
alias un='$aurhelper -Rns'                                             # uninstall package
alias up='$aurhelper -Syu'                                             # update system/package/aur
alias pl='$aurhelper -Qs'                                              # list installed package
alias pa='$aurhelper -Ss'                                              # list available package
alias pc='$aurhelper -Sc'                                              # remove unused cache
alias po='$aurhelper -Qtdq | $aurhelper -Rns -'                        # remove unused packages, also try > $aurhelper -Qqd | $aurhelper -Rsu --print -
alias vc='code'                                                        # gui code editor
alias neofetch='ff'

# fastfetch with a logo that keeps animating while you type; the animation
# stops before the next command runs or the screen clears, since either
# moves the logo away from where it is drawn
function ff --description 'fastfetch with an animated logo'
    fetch $argv; and set -g __fetch_running 1
end
function __fetch_stop --on-event fish_preexec
    set -q __fetch_running; or return
    set -e __fetch_running
    set -l pidfile $XDG_RUNTIME_DIR/fetch-(path basename (tty)).pid
    test -f $pidfile; and kill (cat $pidfile) 2>/dev/null
    rm -f $pidfile
end
bind ctrl-l '__fetch_stop; commandline -f clear-screen'

# git: abbreviations expand in place, so the full command stays in history
abbr -a gs 'git status --short --branch'
abbr -a gl 'git log --graph --format="%C(auto)%h%d %s %C(dim)%cr" -20'
abbr -a gd 'git diff'
abbr -a lg 'lazygit'

starship init fish | source
set -U fish_greeting ""

#!/usr/bin/env bash
# Bash completions for `just` — garbanzo-ai
#
# Install (add to ~/.bashrc):
#   source /path/to/garbanzo-ai/scripts/just-completions.bash
#
# Or run:  just completions-install

_just_completions() {
    local cur
    COMPREPLY=()
    cur="${COMP_WORDS[COMP_CWORD]}"

    # Only complete the first argument (the recipe name)
    if [[ ${COMP_CWORD} -eq 1 ]]; then
        # Dynamically fetch recipes; skip private ones (prefixed with _)
        local recipes
        recipes=$(just --list 2>/dev/null \
            | awk 'NR>1 && $1 !~ /^_/ { print $1 }')
        COMPREPLY=($(compgen -W "$recipes" -- "$cur"))
    fi
}

complete -F _just_completions just

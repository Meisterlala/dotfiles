#!/bin/bash

# Usage: ./complete.sh "sed --r"
input="$1"
source /usr/share/bash-completion/bash_completion

# Extract command + args
read -ra words <<< "$input"
cmd="${words[0]}"
args="${words[*]:1}"
COMP_LINE="$input"
COMP_POINT="${#COMP_LINE}"

get_completions() {
    local cmd_name="$1"
    shift
    local line="$*"

    # Setup completion variables
    COMPREPLY=()
    COMP_LINE="$line"
    COMP_POINT=${#COMP_LINE}

    # Split line into words array
    IFS=' ' read -r -a COMP_WORDS <<< "$COMP_LINE"

    # Add empty word if line ends with space (new word being typed)
    [[ "${COMP_LINE: -1}" == " " ]] && COMP_WORDS+=("")

    COMP_CWORD=$(( ${#COMP_WORDS[@]} - 1 ))

    # Find completion function for the command
    local completion_func
    completion_func=$(complete -p "$cmd_name" 2>/dev/null | awk '{print $(NF-1)}')

    # Load completion if not found
    if [[ -z $completion_func ]]; then
        _completion_loader "$cmd_name"
        completion_func=$(complete -p "$cmd_name" 2>/dev/null | awk '{print $(NF-1)}')
    fi

    # If no completion found, exit
    [[ -z $completion_func ]] && return 1

    # Previous word for function param
    local prev_word=""
    if (( COMP_CWORD > 0 )); then
        prev_word="${COMP_WORDS[COMP_CWORD-1]}"
    fi

    # Call the completion function (fills COMPREPLY)
    "$completion_func" "${COMP_WORDS[@]}" "${COMP_WORDS[COMP_CWORD]}" "$prev_word"

    # Print sorted unique completions
    printf '%s\n' "${COMPREPLY[@]}" | LC_ALL=C sort -u
}

get_completions "$1" "$2"



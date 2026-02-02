if status is-interactive
    # Commands to run in interactive sessions can go here
end

# Initialize zoxide if installed
if command -q zoxide
    zoxide init fish --cmd cd | source
end

# Initialize carapace if installed
if command -q carapace
    carapace _carapace fish | source
end

# Aliases for eza if installed
if command -q eza
    abbr -a l 'eza -lh --icons --grid --group-directories-first'
    abbr -a ll 'eza -lah --icons --grid --group-directories-first'
    abbr -a tree 'eza --tree --icons'
end

# Initialize direnv if installed
if command -q direnv
    direnv hook fish | source
end


# Set up fzf
set -g fzf_history_opts --with-nth=4..

# Set up tide prompt
set -g tide_right_prompt_items status cmd_duration context jobs direnv bun node python rustc java php pulumi ruby go gcloud distrobox toolbox terraform aws nix_shell crystal elixir zig

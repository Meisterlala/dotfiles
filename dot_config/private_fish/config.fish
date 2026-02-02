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


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
    alias ls 'eza -h --icons --grid'
    abbr -a ll 'eza -lah --icons --grid'
    abbr -a tree 'eza --tree --icons'
end

# Initialize direnv if installed
if command -q direnv
    direnv hook fish | source
end

# Greeting
set -g fish_greeting ''

# Set up fzf
set -g fzf_history_opts --with-nth=4..

# Set up tide prompt
set -g tide_right_prompt_items status cmd_duration context jobs direnv bun node python rustc java php pulumi ruby go gcloud distrobox toolbox terraform aws nix_shell crystal elixir zig

# Catppuccin Frappé Palette
set -g ct_rosewater f2d5cf
set -g ct_flamingo eebebe
set -g ct_pink f4b8e4
set -g ct_mauve ca9ee6
set -g ct_red e78284
set -g ct_maroon ea999c
set -g ct_peach ef9f76
set -g ct_yellow e5c890
set -g ct_green a6d189
set -g ct_teal 81c8be
set -g ct_sky 99d1db
set -g ct_sapphire 85c1dc
set -g ct_blue 8caaee
set -g ct_lavender babbf1
set -g ct_text c6d0f5
set -g ct_subtext1 b5bfe2
set -g ct_subtext0 a5adce
set -g ct_overlay2 949cbb
set -g ct_overlay1 838ba7
set -g ct_overlay0 737994
set -g ct_surface2 626880
set -g ct_surface1 51576d
set -g ct_surface0 414559
set -g ct_base 303446
set -g ct_mantle 292c3c
set -g ct_crust 232634


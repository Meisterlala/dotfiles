function no_color --description 'Disable terminal color theming for this Fish session'
    set -gx NO_COLOR 1
    fish_config theme choose none
end

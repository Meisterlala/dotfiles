# delegate completions to kubectl-gadget when subcommand is "gadget"
complete -c kubectl -n '__fish_seen_subcommand_from gadget' -f -a '(__kubectl_gadget_perform_completion)'

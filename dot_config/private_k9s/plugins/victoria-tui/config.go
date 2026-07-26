package main

import (
	"errors"
	"fmt"
	"regexp"
	"strconv"
)

type config struct {
	context string
	scope   string
	query   string
	mode    string
}

func parseConfig(args []string) (config, error) {
	if len(args) < 4 {
		return config{}, errors.New("usage: victoria-tui <context> <--container|--pod|--deployment|--node|--namespace> <values...> <raw|table>")
	}
	cfg := config{context: args[0]}
	selector := args[1]
	values := args[2:]
	quote := strconv.Quote
	switch selector {
	case "--container":
		if len(values) != 4 {
			return config{}, errors.New("container requires namespace, pod, container and mode")
		}
		cfg.scope, cfg.mode = "container", values[3]
		cfg.query = "namespace:=" + quote(values[0]) + " and pod:=" + quote(values[1]) + " and container:=" + quote(values[2])
	case "--pod":
		if len(values) != 3 {
			return config{}, errors.New("pod requires namespace, pod and mode")
		}
		cfg.scope, cfg.mode = "pod", values[2]
		cfg.query = "namespace:=" + quote(values[0]) + " and pod:=" + quote(values[1])
	case "--deployment":
		if len(values) != 3 {
			return config{}, errors.New("deployment requires namespace, name and mode")
		}
		cfg.scope, cfg.mode = "deployment", values[2]
		pattern := "^" + regexp.QuoteMeta(values[1]) + "-[a-z0-9]+-[a-z0-9]+$"
		cfg.query = "namespace:=" + quote(values[0]) + " and pod:~" + quote(pattern)
	case "--node":
		if len(values) != 2 {
			return config{}, errors.New("node requires name and mode")
		}
		cfg.scope, cfg.mode = "node", values[1]
		cfg.query = "node:=" + quote(values[0])
	case "--namespace":
		if len(values) != 2 {
			return config{}, errors.New("namespace requires name and mode")
		}
		cfg.scope, cfg.mode = "namespace", values[1]
		cfg.query = "namespace:=" + quote(values[0])
	default:
		return config{}, fmt.Errorf("unknown selector %q", selector)
	}
	if cfg.mode != "raw" && cfg.mode != "table" {
		return config{}, fmt.Errorf("unknown mode %q", cfg.mode)
	}
	return cfg, nil
}

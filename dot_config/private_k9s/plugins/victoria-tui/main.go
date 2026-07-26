package main

import (
	"context"
	"fmt"
	"net/http"
	"os"
	"os/signal"
	"syscall"

	"github.com/gdamore/tcell/v2"
	"github.com/rivo/tview"
)

func main() {
	tview.Styles.PrimitiveBackgroundColor = tcell.ColorDefault
	cfg, err := parseConfig(os.Args[1:])
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(2)
	}
	ctx, cancel := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	backend, err := newBackend(cfg.context)
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
	defer backend.close()
	defer cancel()
	httpClient := &http.Client{Transport: &http.Transport{MaxIdleConns: 4, MaxIdleConnsPerHost: 4}}
	v := newViewer(cfg, &client{http: httpClient, baseURL: backend.baseURL, query: cfg.query}, backend, cancel)
	if err := v.run(ctx); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
	cancel()
}

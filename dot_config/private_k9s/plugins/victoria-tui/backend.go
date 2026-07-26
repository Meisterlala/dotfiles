package main

import (
	"bytes"
	"context"
	"fmt"
	"io"
	"net"
	"net/http"
	"os/exec"
	"strconv"
	"strings"
	"sync"
	"syscall"
	"time"
)

type backend struct {
	context string
	port    int
	baseURL string
	mu      sync.Mutex
	cmd     *exec.Cmd
	done    chan error
}

func newBackend(kubeContext string) (*backend, error) {
	listener, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		return nil, err
	}
	port := listener.Addr().(*net.TCPAddr).Port
	if err := listener.Close(); err != nil {
		return nil, err
	}
	return &backend{context: kubeContext, port: port, baseURL: "http://127.0.0.1:" + strconv.Itoa(port)}, nil
}

func (b *backend) ensure(ctx context.Context) error {
	b.mu.Lock()
	defer b.mu.Unlock()
	if backendHealthy(b.baseURL) {
		return nil
	}
	b.stopLocked()
	args := []string{}
	if b.context != "" {
		args = append(args, "--context", b.context)
	}
	args = append(args, "port-forward", "-n", "victoria-metrics", "service/vlsingle-logs", fmt.Sprintf("%d:9428", b.port), "--address", "127.0.0.1")
	cmd := exec.CommandContext(ctx, "kubectl", args...)
	var stderr bytes.Buffer
	cmd.Stdout, cmd.Stderr = io.Discard, &stderr
	if err := cmd.Start(); err != nil {
		return err
	}
	b.cmd, b.done = cmd, make(chan error, 1)
	go func(done chan<- error) { done <- cmd.Wait() }(b.done)
	for range 50 {
		if backendHealthy(b.baseURL) {
			return nil
		}
		select {
		case err := <-b.done:
			b.cmd, b.done = nil, nil
			return fmt.Errorf("kubectl port-forward exited: %v: %s", err, strings.TrimSpace(stderr.String()))
		case <-ctx.Done():
			b.stopLocked()
			return ctx.Err()
		case <-time.After(100 * time.Millisecond):
		}
	}
	b.stopLocked()
	return fmt.Errorf("VictoriaLogs port-forward did not become ready: %s", strings.TrimSpace(stderr.String()))
}

func (b *backend) close() { b.mu.Lock(); defer b.mu.Unlock(); b.stopLocked() }
func (b *backend) stopLocked() {
	if b.cmd == nil {
		return
	}
	_ = b.cmd.Process.Signal(syscall.SIGTERM)
	select {
	case <-b.done:
	case <-time.After(2 * time.Second):
		_ = b.cmd.Process.Kill()
		<-b.done
	}
	b.cmd, b.done = nil, nil
}

func backendHealthy(baseURL string) bool {
	client := http.Client{Timeout: 300 * time.Millisecond}
	resp, err := client.Get(baseURL + "/health")
	if err != nil {
		return false
	}
	_ = resp.Body.Close()
	return resp.StatusCode == http.StatusOK
}

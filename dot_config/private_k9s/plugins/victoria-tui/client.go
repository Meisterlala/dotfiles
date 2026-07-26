package main

import (
	"bufio"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strconv"
	"strings"
)

const (
	initialSize = 10
	pageSize    = 10
)

type entry map[string]any

func (e entry) id() string {
	return stringValue(e["_stream_id"]) + "\x00" + stringValue(e["_time"]) + "\x00" + stringValue(e["_msg"])
}
func (e entry) timestamp() string { return stringValue(e["_time"]) }

type client struct {
	http    *http.Client
	baseURL string
	query   string
}

func (c *client) page(ctx context.Context, end string, limit int) ([]entry, error) {
	values := url.Values{"query": {c.query}, "limit": {strconv.Itoa(limit)}}
	if end != "" {
		values.Set("end", end)
	} else {
		values.Set("start", "1h")
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, c.baseURL+"/select/logsql/query?"+values.Encode(), nil)
	if err != nil {
		return nil, err
	}
	resp, err := c.http.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		body, _ := io.ReadAll(io.LimitReader(resp.Body, 4096))
		return nil, fmt.Errorf("VictoriaLogs query: %s: %s", resp.Status, strings.TrimSpace(string(body)))
	}
	return decodeEntries(resp.Body)
}

func (c *client) tail(ctx context.Context, onEntry func(entry)) error {
	values := url.Values{"query": {c.query}}
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, c.baseURL+"/select/logsql/tail?"+values.Encode(), nil)
	if err != nil {
		return err
	}
	resp, err := c.http.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		body, _ := io.ReadAll(io.LimitReader(resp.Body, 4096))
		return fmt.Errorf("VictoriaLogs tail: %s: %s", resp.Status, strings.TrimSpace(string(body)))
	}
	scanner := bufio.NewScanner(resp.Body)
	scanner.Buffer(make([]byte, 64*1024), 4*1024*1024)
	for scanner.Scan() {
		var item entry
		if json.Unmarshal(scanner.Bytes(), &item) == nil {
			onEntry(item)
		}
	}
	if err := scanner.Err(); err != nil {
		return err
	}
	if ctx.Err() != nil {
		return ctx.Err()
	}
	return io.ErrUnexpectedEOF
}

func decodeEntries(r io.Reader) ([]entry, error) {
	scanner := bufio.NewScanner(r)
	scanner.Buffer(make([]byte, 64*1024), 4*1024*1024)
	var entries []entry
	for scanner.Scan() {
		var item entry
		if err := json.Unmarshal(scanner.Bytes(), &item); err != nil {
			return nil, err
		}
		entries = append(entries, item)
	}
	return entries, scanner.Err()
}

package main

import (
	"context"
	"fmt"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/gdamore/tcell/v2"
	"github.com/rivo/tview"
)

func TestTailStreamsOnlyNewEntries(t *testing.T) {
	var startOffset string
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		startOffset = r.URL.Query().Get("start_offset")
		w.WriteHeader(http.StatusOK)
	}))
	defer server.Close()
	c := &client{http: server.Client(), baseURL: server.URL, query: "*"}
	_ = c.tail(context.Background(), func(entry) {})
	if startOffset != "" {
		t.Fatalf("tail unexpectedly requested history: %q", startOffset)
	}
}

func TestParseDeployment(t *testing.T) {
	cfg, err := parseConfig([]string{"cluster", "--deployment", "habits", "habits-api", "table"})
	if err != nil {
		t.Fatal(err)
	}
	if cfg.scope != "deployment" || cfg.mode != "table" {
		t.Fatalf("unexpected config: %#v", cfg)
	}
	if !strings.Contains(cfg.query, `pod:~"^habits-api-[a-z0-9]+-[a-z0-9]+$"`) {
		t.Fatalf("query is not rollout-safe: %s", cfg.query)
	}
}

func TestSourceJSONExcludesMetadata(t *testing.T) {
	item := entry{
		"_msg": "api request slow", "_time": "now", "_stream": "stream",
		"namespace": "habits", "pod": "habits-api-x", "container": "habits-api",
		"kubernetes.pod_node_name": "odin", "duration_ms": "157", "level": "warn",
		"method": "GET", "path": "/api/punishments/status", "status": "200",
	}
	got := sourceJSON(item)
	for _, excluded := range []string{"_time", "_stream", "namespace", "pod", "container", "kubernetes"} {
		if strings.Contains(got, excluded) {
			t.Fatalf("output contains %q: %s", excluded, got)
		}
	}
	for _, expected := range []string{`"message":"api request slow"`, `"level":"WARN"`, `"method":"GET"`} {
		if !strings.Contains(got, expected) {
			t.Fatalf("output lacks %q: %s", expected, got)
		}
	}
}

func TestColumnsKeepScopeContext(t *testing.T) {
	items := []entry{{"pod": "p", "container": "c", "_msg": "hello", "level": "info", "kubernetes.pod_name": "p"}}
	columns := discoverColumns(items, "deployment")
	got := strings.Join(columns, ",")
	if got != "pod,container,level,_msg" {
		t.Fatalf("unexpected columns: %s", got)
	}
}

func TestNewFieldsAppendWithoutReorderingColumns(t *testing.T) {
	current := []string{"pod", "container", "level", "_msg"}
	entries := []entry{{"pod": "p", "container": "c", "level": "info", "_msg": "hello", "trace_id": "abc"}}
	got := strings.Join(mergeColumns(current, discoverColumns(entries, "deployment")), ",")
	if got != "pod,container,level,_msg,trace_id" {
		t.Fatalf("new field did not append stably: %s", got)
	}
}

func TestPausedViewAppendsWithoutMovingSelection(t *testing.T) {
	v := newViewer(config{scope: "deployment", mode: "table"}, nil, nil, func() {})
	v.following = false
	v.addEntries([]entry{
		{"_stream_id": "1", "_time": "2026-01-01T00:00:00Z", "_msg": "first"},
		{"_stream_id": "2", "_time": "2026-01-01T00:00:01Z", "_msg": "second"},
	}, false)
	oldStart := v.entryStartRow()
	v.table.Select(oldStart, 0)
	v.table.SetOffset(1, 0)
	v.addEntries([]entry{{"_stream_id": "3", "_time": "2026-01-01T00:00:02Z", "_msg": "third"}}, false)
	row, _ := v.table.GetSelection()
	if row != v.entryStartRow() {
		t.Fatalf("selection jumped from paused row: %d", row)
	}
	if len(v.entries) != 3 {
		t.Fatalf("live entry was not appended: %d entries", len(v.entries))
	}
	offset, _ := v.table.GetOffset()
	expectedOffset := 1 + v.entryStartRow() - oldStart
	if offset != expectedOffset {
		t.Fatalf("viewport shifted while paused: %d", offset)
	}
}

func TestLiveEntriesAlwaysAppend(t *testing.T) {
	v := newViewer(config{scope: "pod", mode: "raw"}, nil, nil, func() {})
	v.addEntries([]entry{{"_stream_id": "1", "_time": "2026-01-01T00:00:10Z", "_msg": "existing"}}, true)
	v.addEntries([]entry{{"_stream_id": "2", "_time": "2026-01-01T00:00:01Z", "_msg": "delayed live"}}, false)
	if got := stringValue(v.entries[len(v.entries)-1]["_msg"]); got != "delayed live" {
		t.Fatalf("live entry was not appended: %s", got)
	}
}

func TestSteadyLiveAppendKeepsExistingTableCells(t *testing.T) {
	v := newViewer(config{scope: "pod", mode: "raw"}, nil, nil, func() {})
	items := make([]entry, 12)
	for i := range items {
		items[i] = entry{"_stream_id": fmt.Sprint(i), "_time": fmt.Sprintf("2026-01-01T00:00:%02dZ", i), "_msg": fmt.Sprint(i)}
	}
	v.addEntries(items, true)
	v.following = false
	first := v.table.GetCell(v.rowForEntry(0), 0)
	v.addEntries([]entry{{"_stream_id": "live", "_time": "2026-01-01T00:01:00Z", "_msg": "live"}}, false)
	if v.table.GetCell(v.rowForEntry(0), 0) != first {
		t.Fatal("steady live append rebuilt existing table cells")
	}
}

func TestWrappedLinesAreCached(t *testing.T) {
	v := newViewer(config{scope: "pod", mode: "raw"}, nil, nil, func() {})
	v.wrap = true
	v.wrapWidth = 20
	v.addEntries([]entry{{"_stream_id": "1", "_time": "2026-01-01T00:00:00Z", "_msg": "a sufficiently long message to wrap"}}, true)
	first, second := v.rawLines(0), v.rawLines(0)
	if len(first) == 0 || &first[0] != &second[0] {
		t.Fatal("wrapped lines were recalculated instead of reused")
	}
}

func TestVisibleColumns(t *testing.T) {
	got := strings.Join(visibleColumns([]string{"pod", "container", "level"}, map[string]bool{"container": true}), ",")
	if got != "pod,level" {
		t.Fatalf("unexpected visible columns: %s", got)
	}
}

func TestToggleAllColumns(t *testing.T) {
	columns := []string{"pod", "container", "level"}
	hidden := map[string]bool{"container": true}
	toggleAllColumns(columns, hidden)
	if len(hidden) != 0 {
		t.Fatalf("hidden columns were not shown: %#v", hidden)
	}
	toggleAllColumns(columns, hidden)
	for _, column := range columns {
		if !hidden[column] {
			t.Fatalf("column %q was not hidden: %#v", column, hidden)
		}
	}
}

func TestColumnMarkersHaveFixedWidth(t *testing.T) {
	if len(columnMarkerVisible) != len(columnMarkerHidden) {
		t.Fatalf("marker widths differ: %q and %q", columnMarkerVisible, columnMarkerHidden)
	}
	visible, hidden := tview.TaggedStringWidth(columnMarker(false)), tview.TaggedStringWidth(columnMarker(true))
	if visible != hidden || visible != 5 {
		t.Fatalf("rendered marker widths differ: %d and %d", visible, hidden)
	}
}

func TestNewLiveIndicatorClearsWhenBottomIsVisible(t *testing.T) {
	v := newViewer(config{scope: "pod", mode: "raw"}, nil, nil, func() {})
	items := make([]entry, 12)
	for i := range items {
		items[i] = entry{"_stream_id": fmt.Sprint(i), "_time": fmt.Sprintf("2026-01-01T00:00:%02dZ", i), "_msg": fmt.Sprint(i)}
	}
	v.addEntries(items, true)
	v.following = false
	v.table.Select(0, 0)
	v.table.SetOffset(0, 0)
	v.addEntries([]entry{{"_stream_id": "live", "_time": "2026-01-01T00:01:00Z", "_msg": "live"}}, false)
	if !strings.Contains(v.status.GetText(true), "↓ new logs") {
		t.Fatal("new-live indicator is missing")
	}
	v.table.SetOffset(3, 0)
	v.updateStatus("")
	if strings.Contains(v.status.GetText(true), "↓ new logs") {
		t.Fatal("new-live indicator remained after the last row became visible")
	}
}

func TestPausedStatusIsNotShown(t *testing.T) {
	v := newViewer(config{scope: "pod", mode: "raw"}, nil, nil, func() {})
	v.loading = false
	v.connection = "connected"
	v.following = false
	v.updateStatus("")
	if strings.Contains(v.status.GetText(true), "paused") {
		t.Fatal("paused status is visible")
	}
}

func TestWrapModeIsRawOnlyAndOffByDefault(t *testing.T) {
	v := newViewer(config{scope: "pod", mode: "raw"}, nil, nil, func() {})
	v.loading = false
	v.connection = "connected"
	v.wrapWidth = 20
	v.entries = []entry{{"_stream_id": "1", "_msg": "a message long enough to wrap across several display rows"}}
	v.rebuild()
	v.updateStatus("")
	if v.wrap || !strings.Contains(v.topBar.GetText(true), "Wrap:Off") || !strings.Contains(v.status.GetText(true), "s/c/t/w") || strings.Contains(v.status.GetText(true), "h columns") {
		t.Fatal("raw wrap control is not shown as off by default")
	}
	if event := v.handleKey(tcell.NewEventKey(tcell.KeyRune, 'h', tcell.ModNone)); event == nil {
		t.Fatal("column menu key was handled in raw mode")
	}
	v.handleKey(tcell.NewEventKey(tcell.KeyRune, 'w', tcell.ModNone))
	if !v.wrap || v.renderedRowCount() <= len(v.entries) {
		t.Fatal("wrap mode did not create additional display rows")
	}
	v.columnsOn = true
	v.updateStatus("")
	if strings.Contains(v.topBar.GetText(true), "Wrap:") || strings.Contains(v.status.GetText(true), "/w") || !strings.Contains(v.status.GetText(true), "h columns") {
		t.Fatal("wrap controls are visible in column mode")
	}
	if event := v.handleKey(tcell.NewEventKey(tcell.KeyRune, 'w', tcell.ModNone)); event == nil || !v.wrap {
		t.Fatal("wrap key was handled in column mode")
	}
}

func TestWrappedSelectionCoversEntryAndArrowsJumpEntries(t *testing.T) {
	v := newViewer(config{scope: "pod", mode: "raw"}, nil, nil, func() {})
	v.wrap = true
	v.wrapWidth = 24
	v.entries = []entry{
		{"_stream_id": "1", "_msg": "first message long enough to occupy multiple rows"},
		{"_stream_id": "2", "_msg": "second message long enough to occupy multiple rows"},
	}
	v.rebuild()
	firstRow := v.rowForEntry(0)
	v.table.Select(firstRow, 0)
	_, _, selectedAttrs := v.selected.Decompose()
	for row := firstRow; row < v.rowForEntry(1); row++ {
		_, _, attrs := v.table.GetCell(row, 0).Style.Decompose()
		if attrs != selectedAttrs {
			t.Fatalf("wrapped row %d is not selected", row)
		}
	}
	v.handleKey(tcell.NewEventKey(tcell.KeyDown, 0, tcell.ModNone))
	row, _ := v.table.GetSelection()
	want := v.rowForEntry(1) + v.entryRowCount(1) - 1
	if row != want {
		t.Fatalf("down did not reveal the complete wrapped entry: got %d, want %d", row, want)
	}
}

func TestBackendUsesRandomLocalPort(t *testing.T) {
	backend, err := newBackend("test")
	if err != nil {
		t.Fatal(err)
	}
	if backend.port <= 1024 || !strings.HasPrefix(backend.baseURL, "http://127.0.0.1:") {
		t.Fatalf("unexpected backend address: %s", backend.baseURL)
	}
}

func TestMouseOffsetPrefetchesBeforeTop(t *testing.T) {
	if !shouldPrefetch(20, 24) {
		t.Fatal("expected prefetch within one viewport of the top")
	}
	if shouldPrefetch(25, 24) {
		t.Fatal("prefetched too early")
	}
}

func TestFooterOrderAndConnectionStatus(t *testing.T) {
	v := newViewer(config{scope: "pod", mode: "table"}, nil, nil, func() {})
	v.loading = false
	v.connection = "connected :45678"
	v.entries = make([]entry, 12)
	v.updateStatus("")
	text := v.status.GetText(true)
	keys := strings.Index(text, "q quit")
	count := strings.Index(text, "12 logs")
	status := strings.Index(text, "following")
	if keys < 0 || count <= keys || status <= count {
		t.Fatalf("unexpected footer order: %s", text)
	}
	if strings.Contains(text, "connected") {
		t.Fatalf("normal connection state leaked into footer: %s", text)
	}
	v.connection = "reconnecting"
	v.updateStatus("")
	if !strings.Contains(v.status.GetText(true), "reconnecting") {
		t.Fatal("reconnecting state missing from footer")
	}
}

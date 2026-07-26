package main

import (
	"encoding/json"
	"fmt"
	"sort"
	"strings"

	"github.com/gdamore/tcell/v2"
	"github.com/rivo/tview"
)

const (
	columnMarkerVisible = " [X] "
	columnMarkerHidden  = " [ ] "
)

var metadataFields = map[string]bool{
	"_stream": true, "_stream_id": true, "_time": true,
	"app": true, "collector": true, "container": true,
	"namespace": true, "node": true, "pod": true,
	"source_type": true, "timestamp": true,
}

func columnMarker(hidden bool) string {
	if hidden {
		return tview.Escape(columnMarkerHidden)
	}
	return tview.Escape(columnMarkerVisible)
}

// toggleAllColumns shows every discovered column if one is hidden; otherwise it hides all.
func toggleAllColumns(columns []string, hidden map[string]bool) {
	for _, column := range columns {
		if hidden[column] {
			clear(hidden)
			return
		}
	}
	for _, column := range columns {
		hidden[column] = true
	}
}

func discoverColumns(entries []entry, scope string) []string {
	all := make(map[string]bool)
	for _, item := range entries {
		for key := range item {
			all[key] = true
		}
	}
	var contextColumns []string
	switch scope {
	case "pod":
		contextColumns = []string{"container"}
	case "deployment", "namespace":
		contextColumns = []string{"pod", "container"}
	case "node":
		contextColumns = []string{"namespace", "pod", "container"}
	}
	columns := make([]string, 0, len(all))
	for _, key := range contextColumns {
		if all[key] {
			columns = append(columns, key)
		}
	}
	var application []string
	for key := range all {
		if metadataFields[key] || strings.HasPrefix(key, "kubernetes.") || contains(contextColumns, key) {
			continue
		}
		application = append(application, key)
	}
	sort.Slice(application, func(i, j int) bool {
		left, right := application[i], application[j]
		if left == "_msg" {
			left = "message"
		}
		if right == "_msg" {
			right = "message"
		}
		return left < right
	})
	return append(columns, application...)
}

func mergeColumns(current, discovered []string) []string {
	merged := append([]string(nil), current...)
	for _, column := range discovered {
		if !contains(merged, column) {
			merged = append(merged, column)
		}
	}
	return merged
}
func visibleColumns(columns []string, hidden map[string]bool) []string {
	visible := make([]string, 0, len(columns))
	for _, column := range columns {
		if !hidden[column] {
			visible = append(visible, column)
		}
	}
	return visible
}

func sourceJSON(item entry) string {
	clean := make(entry)
	for key, value := range item {
		if metadataFields[key] || strings.HasPrefix(key, "kubernetes.") {
			continue
		}
		if key == "_msg" {
			clean["message"] = value
			continue
		}
		if key == "level" {
			clean[key] = strings.ToUpper(stringValue(value))
			continue
		}
		clean[key] = value
	}
	data, _ := json.Marshal(clean)
	return string(data)
}

func displayValue(value any) string {
	if value == nil {
		return ""
	}
	switch typed := value.(type) {
	case map[string]any, []any:
		data, _ := json.Marshal(typed)
		return strings.ReplaceAll(string(data), "|", " ")
	default:
		return strings.NewReplacer("|", " ", "\n", " ", "\r", " ", "\t", " ").Replace(fmt.Sprint(value))
	}
}
func header(name string) string {
	if name == "_msg" {
		return "MESSAGE"
	}
	return strings.ToUpper(strings.TrimLeft(name, "_"))
}

func levelColor(level string) tcell.Color {
	switch strings.ToLower(level) {
	case "panic", "fatal":
		return tcell.NewRGBColor(255, 85, 85)
	case "error":
		return tcell.NewRGBColor(255, 140, 100)
	case "warn", "warning":
		return tcell.NewRGBColor(255, 215, 80)
	case "info":
		return tcell.NewRGBColor(100, 220, 255)
	case "debug", "trace":
		return tcell.NewRGBColor(175, 185, 205)
	default:
		return tcell.NewRGBColor(205, 180, 255)
	}
}

func contains(values []string, target string) bool {
	for _, value := range values {
		if value == target {
			return true
		}
	}
	return false
}
func stringValue(value any) string {
	if value == nil {
		return ""
	}
	return fmt.Sprint(value)
}
func onOff(enabled bool) string {
	if enabled {
		return "[green]On[-]"
	}
	return "[gray]Off[-]"
}
func shouldPrefetch(offset, visibleRows int) bool { return offset <= visibleRows }

package main

import (
	"context"
	"errors"
	"fmt"
	"sort"
	"strings"
	"time"

	"github.com/gdamore/tcell/v2"
	"github.com/rivo/tview"
)

type viewer struct {
	app        *tview.Application
	table      *tview.Table
	topBar     *tview.TextView
	status     *tview.TextView
	root       *tview.Flex
	pages      *tview.Pages
	client     *client
	backend    *backend
	config     config
	entries    []entry
	seen       map[string]bool
	columns    []string
	hidden     map[string]bool
	loading    bool
	hasMore    bool
	following  bool
	columnsOn  bool
	timestamps bool
	wrap       bool
	ready      bool
	rebuilding bool
	ctx        context.Context
	cancel     context.CancelFunc
	connection string
	newBelow   bool
	wrapWidth  int
	selected   tcell.Style
}

func newViewer(cfg config, c *client, backend *backend, cancel context.CancelFunc) *viewer {
	selected := tcell.StyleDefault.Reverse(true).Bold(true)
	v := &viewer{app: tview.NewApplication(), table: tview.NewTable().SetSelectable(true, true).SetSelectedStyle(selected), topBar: tview.NewTextView().SetDynamicColors(true).SetTextAlign(tview.AlignCenter), status: tview.NewTextView().SetDynamicColors(true), client: c, backend: backend, config: cfg, seen: make(map[string]bool), hidden: make(map[string]bool), loading: true, hasMore: true, following: true, columnsOn: cfg.mode == "table", cancel: cancel, selected: selected}
	v.table.SetBorder(false)
	v.table.SetSelectionChangedFunc(func(row, _ int) {
		if v.rebuilding {
			return
		}
		v.styleRawSelection(v.entryIndexAtRow(row))
		v.following = row >= v.lastRow()
		if v.ready && row <= v.prefetchRow() {
			v.loadOlder(v.ctx)
		}
		v.updateStatus("")
	})
	v.table.SetInputCapture(v.handleKey)
	v.table.SetMouseCapture(func(action tview.MouseAction, event *tcell.EventMouse) (tview.MouseAction, *tcell.EventMouse) {
		if action == tview.MouseScrollUp || action == tview.MouseScrollDown {
			if action == tview.MouseScrollUp {
				v.following = false
			}
			go v.app.QueueUpdateDraw(func() {
				v.prefetchFromOffset()
				v.updateStatus("")
			})
		}
		return action, event
	})
	v.root = tview.NewFlex().SetDirection(tview.FlexRow).AddItem(v.topBar, 1, 0, false).AddItem(v.table, 0, 1, true).AddItem(v.status, 1, 0, false)
	v.table.SetBackgroundColor(tcell.ColorDefault)
	v.topBar.SetBackgroundColor(tcell.ColorDefault)
	v.status.SetBackgroundColor(tcell.ColorDefault)
	v.root.SetBackgroundColor(tcell.ColorDefault)
	v.pages = tview.NewPages().AddPage("logs", v.root, true, true)
	v.pages.SetBackgroundColor(tcell.ColorDefault)
	v.app.SetRoot(v.pages, true).EnableMouse(true)
	v.app.SetBeforeDrawFunc(func(screen tcell.Screen) bool {
		width, _ := screen.Size()
		if v.wrap && !v.columnsOn && width != v.wrapWidth {
			row, _ := v.table.GetSelection()
			index := v.entryIndexAtRow(row)
			v.wrapWidth = width
			v.rebuildKeepingSelection(index)
		}
		return false
	})
	v.connection = "waiting for port-forward"
	v.updateStatus("loading recent logs")
	return v
}

func (v *viewer) run(ctx context.Context) error { v.ctx = ctx; go v.connect(ctx); return v.app.Run() }
func (v *viewer) connect(ctx context.Context) {
	initialized := false
	for ctx.Err() == nil {
		if initialized {
			v.setConnection("reconnecting")
		} else {
			v.setConnection(fmt.Sprintf("opening port-forward :%d", v.backend.port))
		}
		if err := v.backend.ensure(ctx); err != nil {
			if ctx.Err() != nil {
				return
			}
			v.setConnection("reconnecting: " + err.Error())
			select {
			case <-ctx.Done():
				return
			case <-time.After(time.Second):
				continue
			}
		}
		v.setConnection(fmt.Sprintf("connected :%d", v.backend.port))
		if !initialized {
			initialized = true
			go v.loadInitial(ctx)
		}
		err := v.client.tail(ctx, func(item entry) { v.app.QueueUpdateDraw(func() { v.addEntries([]entry{item}, false) }) })
		if ctx.Err() != nil || errors.Is(err, context.Canceled) {
			return
		}
	}
}
func (v *viewer) setConnection(status string) {
	v.app.QueueUpdateDraw(func() { v.connection = status; v.updateStatus("") })
}
func (v *viewer) loadInitial(ctx context.Context) {
	items, err := v.client.page(ctx, "", initialSize)
	v.app.QueueUpdateDraw(func() {
		v.loading = false
		if err != nil {
			v.updateStatus(err.Error())
			return
		}
		v.hasMore = true
		v.addEntries(items, true)
		v.following = true
		v.table.Select(v.lastRow(), 0)
		v.ready = true
		v.updateStatus("")
		if v.renderedRowCount() < v.visibleDataRows() {
			v.loadOlder(ctx)
		}
	})
}
func (v *viewer) loadOlder(ctx context.Context) {
	if v.loading || !v.hasMore {
		return
	}
	v.loading = true
	end := time.Now().UTC().Format(time.RFC3339Nano)
	if len(v.entries) > 0 {
		end = v.entries[0].timestamp()
	}
	v.updateStatus("loading older logs")
	go func() {
		items, err := v.client.page(ctx, end, pageSize)
		v.app.QueueUpdateDraw(func() {
			v.loading = false
			if err != nil {
				v.updateStatus(err.Error())
				return
			}
			v.hasMore = len(items) == pageSize
			v.addEntries(items, true)
			v.updateStatus("")
			if v.hasMore && v.renderedRowCount() < v.visibleDataRows() {
				v.loadOlder(ctx)
			}
		})
	}()
}

func (v *viewer) addEntries(items []entry, older bool) {
	selectedID := ""
	selectedLine := 0
	row, _ := v.table.GetSelection()
	offsetRow, offsetColumn := v.table.GetOffset()
	oldEntryStart := v.entryStartRow()
	oldRenderedRows := v.renderedRowCount()
	if index := v.entryIndexAtRow(row); index >= 0 {
		selectedID = v.entries[index].id()
		selectedLine = row - v.rowForEntry(index)
	}
	fresh := make([]entry, 0, len(items))
	for _, item := range items {
		id := item.id()
		if v.seen[id] {
			continue
		}
		v.seen[id] = true
		fresh = append(fresh, item)
	}
	added := len(fresh)
	if added == 0 {
		return
	}
	if older {
		sort.SliceStable(fresh, func(i, j int) bool { return fresh[i].timestamp() < fresh[j].timestamp() })
		v.entries = append(fresh, v.entries...)
	} else {
		v.entries = append(v.entries, fresh...)
	}
	v.rebuild()
	if v.following && !older {
		v.newBelow = false
		v.table.Select(v.lastRow(), 0)
		v.styleRawSelection(v.entryIndexAtRow(v.lastRow()))
		v.updateStatus("")
		return
	}
	if selectedID != "" {
		for i, item := range v.entries {
			if item.id() == selectedID {
				lines := v.entryRowCount(i)
				if selectedLine >= lines {
					selectedLine = lines - 1
				}
				v.table.Select(v.rowForEntry(i)+selectedLine, 0)
				break
			}
		}
	}
	offsetRow += v.entryStartRow() - oldEntryStart
	if older {
		offsetRow += v.renderedRowCount() - oldRenderedRows
	}
	if offsetRow < 0 {
		offsetRow = 0
	}
	v.table.SetOffset(offsetRow, offsetColumn)
	if !older && !v.following {
		v.newBelow = !v.bottomVisible()
	}
	selectedRow, _ := v.table.GetSelection()
	v.styleRawSelection(v.entryIndexAtRow(selectedRow))
	v.updateStatus("")
}

func (v *viewer) rebuild() {
	v.rebuilding = true
	defer func() { v.rebuilding = false }()
	v.table.Clear()
	v.table.SetFixed(v.headerRows(), 0)
	entryStart := v.entryStartRow()
	for row := v.headerRows(); row < entryStart; row++ {
		v.table.SetCell(row, 0, tview.NewTableCell(" ").SetSelectable(false))
	}
	if !v.columnsOn {
		row := entryStart
		for _, item := range v.entries {
			for _, line := range v.rawLines(item) {
				v.table.SetCell(row, 0, tview.NewTableCell(line).SetExpansion(1))
				row++
			}
		}
		return
	}
	v.columns = mergeColumns(v.columns, discoverColumns(v.entries, v.config.scope))
	renderColumns := visibleColumns(v.columns, v.hidden)
	if v.timestamps {
		renderColumns = append([]string{"_time"}, renderColumns...)
	}
	for column, name := range renderColumns {
		v.table.SetCell(0, column, tview.NewTableCell(header(name)).SetSelectable(false).SetAttributes(tcell.AttrBold))
	}
	for row, item := range v.entries {
		for column, name := range renderColumns {
			cell := tview.NewTableCell(displayValue(item[name]))
			if name == "level" {
				cell.SetTextColor(levelColor(stringValue(item[name])))
			}
			v.table.SetCell(row+entryStart, column, cell)
		}
	}
}

func (v *viewer) handleKey(event *tcell.EventKey) *tcell.EventKey {
	row, column := v.table.GetSelection()
	entryIndex := v.entryIndexAtRow(row)
	switch event.Key() {
	case tcell.KeyCtrlC:
		v.cancel()
		v.app.Stop()
		return nil
	case tcell.KeyHome:
		v.following = false
		v.table.Select(v.entryStartRow(), column)
		v.loadOlder(v.ctx)
		return nil
	case tcell.KeyEnd:
		v.following = true
		v.newBelow = false
		v.table.Select(v.lastRow(), column)
		v.updateStatus("")
		return nil
	case tcell.KeyUp, tcell.KeyPgUp:
		v.following = false
		if row <= v.prefetchRow() {
			v.loadOlder(v.ctx)
		}
		if event.Key() == tcell.KeyUp && v.wrap && !v.columnsOn {
			if entryIndex > 0 {
				v.table.Select(v.rowForEntry(entryIndex-1), column)
			}
			return nil
		}
	case tcell.KeyDown:
		if v.wrap && !v.columnsOn {
			if entryIndex >= 0 && entryIndex+1 < len(v.entries) {
				next := entryIndex + 1
				v.table.Select(v.rowForEntry(next)+v.entryRowCount(next)-1, column)
			}
			return nil
		}
	}
	switch event.Rune() {
	case 'q':
		v.cancel()
		v.app.Stop()
		return nil
	case 'g':
		v.following = false
		v.table.Select(v.entryStartRow(), column)
		v.loadOlder(v.ctx)
		return nil
	case 'G':
		v.following = true
		v.newBelow = false
		v.table.Select(v.lastRow(), column)
		v.updateStatus("")
		return nil
	case 's':
		v.following = !v.following
		if v.following {
			v.newBelow = false
			v.table.Select(v.lastRow(), column)
		}
		v.updateStatus("")
		return nil
	case 'c':
		v.columnsOn = !v.columnsOn
		v.rebuildKeepingSelection(entryIndex)
		v.updateStatus("")
		return nil
	case 't':
		v.timestamps = !v.timestamps
		v.rebuildKeepingSelection(entryIndex)
		v.updateStatus("")
		return nil
	case 'w':
		if v.columnsOn {
			return event
		}
		v.wrap = !v.wrap
		v.rebuildKeepingSelection(entryIndex)
		v.updateStatus("")
		return nil
	case 'h':
		if !v.columnsOn {
			return event
		}
		v.openColumnMenu()
		return nil
	}
	return event
}
func (v *viewer) headerRows() int {
	if v.columnsOn {
		return 1
	}
	return 0
}
func (v *viewer) lastRow() int {
	last := v.renderedRowCount() - 1 + v.entryStartRow()
	if last < 0 {
		return 0
	}
	return last
}
func (v *viewer) updateStatus(message string) {
	if v.newBelow && (v.following || v.bottomVisible()) {
		v.newBelow = false
	}
	state := ""
	if v.following {
		state = "following"
	}
	if v.loading || v.connection == "waiting for port-forward" || strings.HasPrefix(v.connection, "opening port-forward") {
		state = "loading"
	}
	if strings.HasPrefix(v.connection, "reconnecting") {
		state = "reconnecting"
	}
	if message != "" && state != "reconnecting" {
		state = message
	}
	wrapState := ""
	wrapKey := ""
	columnHelp := ""
	if !v.columnsOn {
		wrapState = "    [::b]Wrap[::-]:" + onOff(v.wrap)
		wrapKey = "/w"
	} else {
		columnHelp = "  [::b]h[::-] columns"
	}
	v.topBar.SetText(fmt.Sprintf("[mediumorchid::b]Logs(%s)[tail][-::-]    [::b]Autoscroll[::-]:%s    [::b]ColumnMode[::-]:%s    [::b]Timestamps[::-]:%s%s", v.config.scope, onOff(v.following), onOff(v.columnsOn), onOff(v.timestamps), wrapState))
	indicator := ""
	if v.newBelow {
		indicator = "  ·  [green::b]↓ new logs[-::-]"
	}
	status := ""
	if state != "" {
		status = "  ·  [yellow]" + tview.Escape(state) + "[-]"
	}
	v.status.SetText(fmt.Sprintf(" [::b]q[::-] quit  [::b]↑/↓[::-] scroll  [::b]g/G[::-] ends  [::b]s/c/t%s[::-] toggle%s  ·  [::b]%d logs[::-]%s%s", wrapKey, columnHelp, len(v.entries), indicator, status))
}

func (v *viewer) openColumnMenu() {
	v.columns = mergeColumns(v.columns, discoverColumns(v.entries, v.config.scope))
	menu := tview.NewTable().SetSelectable(true, false).SetSelectedStyle(tcell.StyleDefault.Reverse(true).Bold(true))
	menu.SetBorder(true).SetTitle(" Columns ").SetBorderColor(tcell.ColorMediumPurple)
	menu.SetBackgroundColor(tcell.ColorDefault)
	menu.SetFixed(0, 1)
	menu.SetEvaluateAllRows(true)
	refresh := func() {
		menu.Clear()
		for row, column := range v.columns {
			menu.SetCell(row, 0, tview.NewTableCell(columnMarker(v.hidden[column])).SetTextColor(tcell.ColorMediumPurple))
			menu.SetCell(row, 1, tview.NewTableCell(header(column)).SetExpansion(1))
		}
	}
	closeMenu := func() { v.pages.RemovePage("columns"); v.app.SetFocus(v.table) }
	toggleRow := func() {
		row, _ := menu.GetSelection()
		if row >= 0 && row < len(v.columns) {
			v.hidden[v.columns[row]] = !v.hidden[v.columns[row]]
			refresh()
			v.rebuild()
			menu.Select(row, 0)
		}
	}
	menu.SetInputCapture(func(event *tcell.EventKey) *tcell.EventKey {
		switch event.Key() {
		case tcell.KeyEscape:
			closeMenu()
			return nil
		case tcell.KeyEnter:
			toggleRow()
			return nil
		}
		switch event.Rune() {
		case ' ', 'x':
			toggleRow()
			return nil
		case 'a':
			toggleAllColumns(v.columns, v.hidden)
			refresh()
			v.rebuild()
			return nil
		case 'q', 'h':
			closeMenu()
			return nil
		}
		return event
	})
	refresh()
	menu.Select(0, 0)
	help := tview.NewTextView().SetDynamicColors(true).SetTextAlign(tview.AlignCenter)
	help.SetBackgroundColor(tcell.ColorDefault)
	help.SetText("[::b]Space/Enter[::-] toggle   [::b]a[::-] show/hide all   [::b]Esc/q/h[::-] close")
	panel := tview.NewFlex().SetDirection(tview.FlexRow).AddItem(menu, 0, 1, true).AddItem(help, 1, 0, false)
	panel.SetBackgroundColor(tcell.ColorDefault)
	width, height := 44, len(v.columns)+3
	if height > 24 {
		height = 24
	}
	modal := tview.NewGrid().SetRows(0, height, 0).SetColumns(0, width, 0).AddItem(panel, 1, 1, 1, 1, 0, 0, true)
	modal.SetBackgroundColor(tcell.ColorDefault)
	v.pages.AddPage("columns", modal, true, true)
	v.app.SetFocus(menu)
}

func (v *viewer) prefetchRow() int { return v.entryStartRow() + v.visibleRows() }
func (v *viewer) prefetchFromOffset() {
	row, _ := v.table.GetOffset()
	if v.ready && shouldPrefetch(row, v.visibleRows()) {
		v.loadOlder(v.ctx)
	}
}
func (v *viewer) visibleRows() int {
	_, _, _, height := v.table.GetInnerRect()
	if height < 10 {
		height = 10
	}
	return height
}
func (v *viewer) visibleDataRows() int {
	rows := v.visibleRows() - v.headerRows()
	if rows < 1 {
		return 1
	}
	return rows
}
func (v *viewer) rawLines(item entry) []string {
	text := sourceJSON(item)
	if v.timestamps {
		text = item.timestamp() + "  " + text
	}
	if !v.wrap {
		return []string{text}
	}
	width := v.wrapWidth
	if width <= 0 {
		_, _, width, _ = v.table.GetInnerRect()
	}
	if width <= 0 {
		width = 80
	}
	lines := tview.WordWrap(text, width)
	if len(lines) == 0 {
		return []string{""}
	}
	return lines
}
func (v *viewer) renderedRowCount() int {
	if v.columnsOn {
		return len(v.entries)
	}
	rows := 0
	for _, item := range v.entries {
		rows += len(v.rawLines(item))
	}
	return rows
}
func (v *viewer) entryRowCount(index int) int {
	if index < 0 || index >= len(v.entries) {
		return 0
	}
	if v.columnsOn {
		return 1
	}
	return len(v.rawLines(v.entries[index]))
}
func (v *viewer) entryIndexAtRow(row int) int {
	logicalRow := row - v.entryStartRow()
	if logicalRow < 0 {
		return -1
	}
	if v.columnsOn {
		if logicalRow < len(v.entries) {
			return logicalRow
		}
		return -1
	}
	for index, item := range v.entries {
		lines := len(v.rawLines(item))
		if logicalRow < lines {
			return index
		}
		logicalRow -= lines
	}
	return -1
}
func (v *viewer) rowForEntry(index int) int {
	if index < 0 {
		index = 0
	}
	if index > len(v.entries) {
		index = len(v.entries)
	}
	row := v.entryStartRow()
	if v.columnsOn {
		return row + index
	}
	for _, item := range v.entries[:index] {
		row += len(v.rawLines(item))
	}
	return row
}
func (v *viewer) styleRawSelection(selectedIndex int) {
	if v.columnsOn || !v.wrap {
		return
	}
	normal := tcell.StyleDefault.Foreground(tview.Styles.PrimaryTextColor).Background(tview.Styles.PrimitiveBackgroundColor)
	row := v.entryStartRow()
	for index, item := range v.entries {
		isSelected := index == selectedIndex
		for range v.rawLines(item) {
			cell := v.table.GetCell(row, 0)
			if isSelected {
				cell.SetStyle(v.selected).SetSelectedStyle(v.selected).SetTransparency(false)
			} else {
				cell.SetStyle(normal).SetSelectedStyle(v.selected).SetTransparency(true)
			}
			row++
		}
	}
}
func (v *viewer) bottomVisible() bool {
	offset, _ := v.table.GetOffset()
	first := v.headerRows() + offset
	return v.lastRow() < first+v.visibleDataRows()
}
func (v *viewer) entryStartRow() int {
	padding := v.visibleDataRows() - v.renderedRowCount()
	if padding < 0 {
		padding = 0
	}
	return v.headerRows() + padding
}
func (v *viewer) rebuildKeepingSelection(index int) {
	if index < 0 {
		index = 0
	}
	v.rebuild()
	v.table.Select(v.rowForEntry(index), 0)
	v.styleRawSelection(index)
}

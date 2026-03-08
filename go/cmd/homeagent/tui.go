package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"strings"
	"time"

	"github.com/charmbracelet/bubbles/key"
	"github.com/charmbracelet/bubbles/list"
	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
	"github.com/spf13/cobra"
)

func tuiCmd() *cobra.Command {
	cmd := &cobra.Command{
		Use:   "tui",
		Short: "터미널 대시보드",
		Long:  "bubbletea 기반 TUI. 디바이스 리스트, 상태, 제어를 터미널에서.",
		RunE:  runTUI,
	}
	cmd.Flags().String("server", "http://localhost:8080", "HomeAgent 서버 주소")
	return cmd
}

// --- Styles ---

var (
	appStyle = lipgloss.NewStyle().Padding(1, 2)

	titleStyle = lipgloss.NewStyle().
			Foreground(lipgloss.Color("#FFFDF5")).
			Background(lipgloss.Color("#6124DF")).
			Padding(0, 1)

	statusBarStyle = lipgloss.NewStyle().
			Foreground(lipgloss.AdaptiveColor{Light: "#343433", Dark: "#C1C6B2"}).
			Background(lipgloss.AdaptiveColor{Light: "#D9DCCF", Dark: "#353533"})

	activeTabStyle = lipgloss.NewStyle().
			Bold(true).
			Foreground(lipgloss.Color("#FFFDF5")).
			Background(lipgloss.Color("#6124DF")).
			Padding(0, 1)

	inactiveTabStyle = lipgloss.NewStyle().
				Foreground(lipgloss.AdaptiveColor{Light: "#343433", Dark: "#C1C6B2"}).
				Padding(0, 1)

	detailStyle = lipgloss.NewStyle().
			Border(lipgloss.RoundedBorder()).
			BorderForeground(lipgloss.Color("#6124DF")).
			Padding(1, 2)

	onlineStyle  = lipgloss.NewStyle().Foreground(lipgloss.Color("#04B575"))
	offlineStyle = lipgloss.NewStyle().Foreground(lipgloss.Color("#FF4672"))
	feedbackOK   = lipgloss.NewStyle().Foreground(lipgloss.Color("#04B575")).Bold(true)
	feedbackErr  = lipgloss.NewStyle().Foreground(lipgloss.Color("#FF4672")).Bold(true)
)

// --- Messages ---

type devicesFetchedMsg struct {
	devices []deviceItem
	err     error
}

type commandResultMsg struct {
	msg string
	err error
}

type tickMsg time.Time

// --- Model ---

type tab int

const (
	tabDevices tab = iota
	tabEvents
	tabChat
)

type tuiModel struct {
	serverURL  string
	activeTab  tab
	deviceList list.Model
	width      int
	height     int
	quitting   bool
	feedback   string // 하단 피드백 메시지
	connected  bool   // 서버 연결 상태
}

// deviceItem implements list.Item
type deviceItem struct {
	nodeID    int
	name      string
	room      string
	devType   string
	available bool
	state     map[string]interface{}
}

func (d deviceItem) Title() string {
	var icon string
	if d.available {
		icon = onlineStyle.Render("●")
	} else {
		icon = offlineStyle.Render("○")
	}
	return fmt.Sprintf("%s %s", icon, d.name)
}

func (d deviceItem) Description() string {
	return fmt.Sprintf("%s · %s · %s", d.room, d.devType, stateString(d.devType, d.state))
}

func (d deviceItem) FilterValue() string { return d.name }

func stateString(devType string, state map[string]interface{}) string {
	if state == nil {
		return "—"
	}
	switch devType {
	case "contact_sensor":
		if v, ok := state["contact"]; ok {
			if v == true {
				return "열림"
			}
			return "닫힘"
		}
	case "on_off_plug", "on_off_light":
		if v, ok := state["on"]; ok {
			if v == true {
				return "켜짐"
			}
			return "꺼짐"
		}
		if v, ok := state["on_off"]; ok {
			if v == true {
				return "켜짐"
			}
			return "꺼짐"
		}
	case "dimmable_light":
		s := ""
		if v, ok := state["on_off"]; ok && v == true {
			s = "켜짐"
		} else {
			s = "꺼짐"
		}
		if v, ok := state["level"]; ok {
			s += fmt.Sprintf(" L:%v", v)
		}
		return s
	case "door_lock":
		if v, ok := state["locked"]; ok && v == true {
			return "🔒 잠김"
		}
		return "🔓 열림"
	}
	// fallback: JSON
	b, _ := json.Marshal(state)
	s := string(b)
	if len(s) > 30 {
		s = s[:30] + "…"
	}
	return s
}

func initialModel(serverURL string) tuiModel {
	delegate := list.NewDefaultDelegate()
	l := list.New([]list.Item{}, delegate, 0, 0)
	l.Title = "디바이스"
	l.SetShowStatusBar(false)
	l.SetFilteringEnabled(true)
	l.KeyMap.Quit = key.NewBinding(key.WithKeys("q"), key.WithHelp("q", "quit"))

	return tuiModel{
		serverURL:  serverURL,
		activeTab:  tabDevices,
		deviceList: l,
		feedback:   "서버 연결 중...",
	}
}

// --- API calls ---

func fetchDevices(serverURL string) tea.Cmd {
	return func() tea.Msg {
		client := &http.Client{Timeout: 5 * time.Second}
		resp, err := client.Get(serverURL + "/api/devices")
		if err != nil {
			return devicesFetchedMsg{err: err}
		}
		defer resp.Body.Close()

		body, _ := io.ReadAll(resp.Body)

		var rawDevices []struct {
			NodeID    int                    `json:"node_id"`
			Name      string                 `json:"name"`
			Room      string                 `json:"room"`
			Type      string                 `json:"type"`
			Available bool                   `json:"available"`
			State     map[string]interface{} `json:"state"`
		}
		if err := json.Unmarshal(body, &rawDevices); err != nil {
			return devicesFetchedMsg{err: err}
		}

		items := make([]deviceItem, len(rawDevices))
		for i, d := range rawDevices {
			items[i] = deviceItem{
				nodeID:    d.NodeID,
				name:      d.Name,
				room:      d.Room,
				devType:   d.Type,
				available: d.Available,
				state:     d.State,
			}
		}
		return devicesFetchedMsg{devices: items}
	}
}

func sendCommand(serverURL string, nodeID int, command string) tea.Cmd {
	return func() tea.Msg {
		payload, _ := json.Marshal(map[string]interface{}{
			"node_id": nodeID,
			"command": command,
		})
		client := &http.Client{Timeout: 10 * time.Second}
		resp, err := client.Post(serverURL+"/api/devices/command", "application/json",
			bytes.NewReader(payload))
		if err != nil {
			return commandResultMsg{err: err}
		}
		defer resp.Body.Close()

		body, _ := io.ReadAll(resp.Body)
		if resp.StatusCode != http.StatusOK {
			return commandResultMsg{err: fmt.Errorf("%s", string(body))}
		}
		return commandResultMsg{msg: fmt.Sprintf("✅ Node %d: %s", nodeID, command)}
	}
}

func tickEvery(d time.Duration) tea.Cmd {
	return tea.Every(d, func(t time.Time) tea.Msg {
		return tickMsg(t)
	})
}

// --- Tea interface ---

func (m tuiModel) Init() tea.Cmd {
	return tea.Batch(
		fetchDevices(m.serverURL),
		tickEvery(5*time.Second),
	)
}

func (m tuiModel) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch msg := msg.(type) {

	case devicesFetchedMsg:
		if msg.err != nil {
			m.feedback = feedbackErr.Render(fmt.Sprintf("연결 실패: %v", msg.err))
			m.connected = false
			return m, nil
		}
		m.connected = true
		items := make([]list.Item, len(msg.devices))
		for i, d := range msg.devices {
			items[i] = d
		}
		m.deviceList.SetItems(items)
		m.feedback = fmt.Sprintf("디바이스 %d개 로드됨", len(msg.devices))
		return m, nil

	case commandResultMsg:
		if msg.err != nil {
			m.feedback = feedbackErr.Render(fmt.Sprintf("명령 실패: %v", msg.err))
		} else {
			m.feedback = feedbackOK.Render(msg.msg)
		}
		// 명령 후 디바이스 새로고침
		return m, fetchDevices(m.serverURL)

	case tickMsg:
		// 5초마다 디바이스 상태 갱신
		return m, tea.Batch(
			fetchDevices(m.serverURL),
			tickEvery(5*time.Second),
		)

	case tea.KeyMsg:
		// 리스트 필터링 중이면 키바인딩 무시
		if m.deviceList.FilterState() == list.Filtering {
			break
		}

		switch msg.String() {
		case "q", "ctrl+c":
			m.quitting = true
			return m, tea.Quit

		case "tab":
			m.activeTab = (m.activeTab + 1) % 3
			return m, nil
		case "shift+tab":
			m.activeTab = (m.activeTab + 2) % 3
			return m, nil

		case "r", "R":
			m.feedback = "새로고침..."
			return m, fetchDevices(m.serverURL)

		// 디바이스 제어 키바인딩
		case "o": // on
			if item, ok := m.deviceList.SelectedItem().(deviceItem); ok {
				m.feedback = fmt.Sprintf("Node %d: on 전송중...", item.nodeID)
				return m, sendCommand(m.serverURL, item.nodeID, "on")
			}
		case "f": // off
			if item, ok := m.deviceList.SelectedItem().(deviceItem); ok {
				m.feedback = fmt.Sprintf("Node %d: off 전송중...", item.nodeID)
				return m, sendCommand(m.serverURL, item.nodeID, "off")
			}
		}

	case tea.WindowSizeMsg:
		m.width = msg.Width
		m.height = msg.Height
		listWidth := msg.Width/2 - 4
		listHeight := msg.Height - 8
		if listHeight < 5 {
			listHeight = 5
		}
		m.deviceList.SetSize(listWidth, listHeight)
	}

	// 디바이스 탭일 때만 리스트 업데이트
	if m.activeTab == tabDevices {
		var cmd tea.Cmd
		m.deviceList, cmd = m.deviceList.Update(msg)
		return m, cmd
	}

	return m, nil
}

func (m tuiModel) View() string {
	if m.quitting {
		return "👋 HomeAgent TUI 종료\n"
	}

	// 탭 바
	tabs := []string{"Devices", "Events", "Chat"}
	var tabBar strings.Builder
	for i, t := range tabs {
		if tab(i) == m.activeTab {
			tabBar.WriteString(activeTabStyle.Render(t))
		} else {
			tabBar.WriteString(inactiveTabStyle.Render(t))
		}
		tabBar.WriteString(" ")
	}

	// 타이틀
	connIcon := offlineStyle.Render("⊘")
	if m.connected {
		connIcon = onlineStyle.Render("⦿")
	}
	title := titleStyle.Render(fmt.Sprintf(" HomeAgent %s ", version)) + " " + connIcon

	// 메인 컨텐츠
	var content string
	switch m.activeTab {
	case tabDevices:
		content = m.devicesView()
	case tabEvents:
		content = m.eventsView()
	case tabChat:
		content = m.chatView()
	}

	// 상태 바
	helpText := "Tab:전환 r:새로고침 o:켜기 f:끄기 /:검색 q:종료"
	status := statusBarStyle.Render(fmt.Sprintf(" %s │ %s ", m.serverURL, helpText))

	// 피드백
	fb := ""
	if m.feedback != "" {
		fb = "  " + m.feedback
	}

	return appStyle.Render(
		lipgloss.JoinVertical(lipgloss.Left,
			title,
			tabBar.String(),
			"",
			content,
			"",
			fb,
			status,
		),
	)
}

func (m tuiModel) devicesView() string {
	listView := m.deviceList.View()

	// 선택된 디바이스 상세
	detail := "디바이스를 선택하세요"
	if item, ok := m.deviceList.SelectedItem().(deviceItem); ok {
		availText := offlineStyle.Render("오프라인")
		if item.available {
			availText = onlineStyle.Render("온라인")
		}

		stateJSON, _ := json.MarshalIndent(item.state, "", "  ")

		detailWidth := m.width/2 - 6
		if detailWidth < 20 {
			detailWidth = 20
		}

		detail = detailStyle.Width(detailWidth).Render(fmt.Sprintf(
			"Node %d — %s\n\n"+
				"Type:      %s\n"+
				"Room:      %s\n"+
				"Status:    %s\n"+
				"State:     %s\n\n"+
				"[o] 켜기  [f] 끄기",
			item.nodeID, item.name,
			item.devType, item.room,
			availText,
			string(stateJSON),
		))
	}

	return lipgloss.JoinHorizontal(lipgloss.Top, listView, "  ", detail)
}

func (m tuiModel) eventsView() string {
	return detailStyle.Render("🔴 실시간 이벤트 (SSE 연결 예정)\n\n구현 예정: 서버 SSE → 터미널 이벤트 로그")
}

func (m tuiModel) chatView() string {
	return detailStyle.Render("💬 LLM 채팅 (구현 예정)\n\n\"플러그 꺼줘\" → POST /api/chat → 응답 표시")
}

func runTUI(cmd *cobra.Command, args []string) error {
	serverURL, _ := cmd.Flags().GetString("server")

	p := tea.NewProgram(
		initialModel(serverURL),
		tea.WithAltScreen(),
	)

	if _, err := p.Run(); err != nil {
		fmt.Fprintf(os.Stderr, "TUI 오류: %v\n", err)
		return err
	}
	return nil
}

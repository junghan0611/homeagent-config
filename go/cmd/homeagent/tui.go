package main

import (
	"fmt"
	"os"
	"strings"

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
)

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
}

// deviceItem implements list.Item
type deviceItem struct {
	nodeID    int
	name      string
	room      string
	devType   string
	available bool
	state     string
}

func (d deviceItem) Title() string {
	icon := "●"
	if !d.available {
		icon = "○"
	}
	return fmt.Sprintf("%s %s", icon, d.name)
}
func (d deviceItem) Description() string {
	return fmt.Sprintf("%s · %s · %s", d.room, d.devType, d.state)
}
func (d deviceItem) FilterValue() string { return d.name }

func initialModel(serverURL string) tuiModel {
	// 초기 디바이스 (서버 연결 전 placeholder)
	items := []list.Item{
		deviceItem{nodeID: 1, name: "현관문 센서", room: "현관", devType: "contact_sensor", available: true, state: "닫힘"},
		deviceItem{nodeID: 7, name: "화장실 센서", room: "화장실", devType: "contact_sensor", available: true, state: "닫힘"},
		deviceItem{nodeID: 8, name: "거실 플러그", room: "거실", devType: "on_off_plug", available: true, state: "켜짐"},
	}

	delegate := list.NewDefaultDelegate()
	l := list.New(items, delegate, 0, 0)
	l.Title = "디바이스"
	l.SetShowStatusBar(false)
	l.SetFilteringEnabled(true)
	l.KeyMap.Quit = key.NewBinding(key.WithKeys("q"), key.WithHelp("q", "quit"))

	return tuiModel{
		serverURL:  serverURL,
		activeTab:  tabDevices,
		deviceList: l,
	}
}

func (m tuiModel) Init() tea.Cmd {
	return nil
}

func (m tuiModel) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.KeyMsg:
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
		}

	case tea.WindowSizeMsg:
		m.width = msg.Width
		m.height = msg.Height
		// 리스트에 사이즈 절반 할당
		listWidth := msg.Width/2 - 4
		listHeight := msg.Height - 8
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
	title := titleStyle.Render(fmt.Sprintf(" HomeAgent %s ", version))

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
	status := statusBarStyle.Render(fmt.Sprintf(" %s │ Tab: 전환 │ q: 종료 ", m.serverURL))

	return appStyle.Render(
		lipgloss.JoinVertical(lipgloss.Left,
			title,
			tabBar.String(),
			"",
			content,
			"",
			status,
		),
	)
}

func (m tuiModel) devicesView() string {
	// split view: 리스트 | 상세
	listView := m.deviceList.View()

	// 선택된 디바이스 상세
	detail := "디바이스를 선택하세요"
	if item, ok := m.deviceList.SelectedItem().(deviceItem); ok {
		detail = detailStyle.Render(fmt.Sprintf(
			"Node %d — %s\n\nType: %s\nRoom: %s\nAvailable: %v\nState: %s\n\n[o]n  [f]off  [l]evel  [c]olor",
			item.nodeID, item.name,
			item.devType, item.room,
			item.available, item.state,
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

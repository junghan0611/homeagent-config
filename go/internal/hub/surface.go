package hub

import (
	"encoding/json"
	"fmt"
	"net/http"
	"time"
)

// A2UI component types
type comp map[string]interface{}

func text(variant, t string) comp {
	return comp{"type": "Text", "props": comp{"variant": variant, "text": t}}
}
func icon(name string, size int, color string) comp {
	return comp{"type": "Icon", "props": comp{"name": name, "size": size, "color": color}}
}
func row(gap int, children ...comp) comp {
	return comp{"type": "Row", "props": comp{"gap": gap}, "children": children}
}
func column(gap int, children ...comp) comp {
	return comp{"type": "Column", "props": comp{"gap": gap}, "children": children}
}
func card(variant string, children ...comp) comp {
	return comp{"type": "Card", "props": comp{"variant": variant}, "children": children}
}
func divider() comp { return comp{"type": "Divider"} }

type timeTheme struct {
	greeting string
	icon     string
	accent   string // primary accent
	bg       string // card background hint
	mood     string
}

func getTimeTheme(hour int) timeTheme {
	switch {
	case hour >= 5 && hour < 9: // 새벽~아침
		return timeTheme{"좋은 아침이에요 ☀️", "sunrise", "#FF9800", "#2a1f0a", "morning"}
	case hour >= 9 && hour < 12: // 오전
		return timeTheme{"활기찬 오전이에요 🌤️", "sun", "#FFC107", "#2a220a", "forenoon"}
	case hour >= 12 && hour < 14: // 점심
		return timeTheme{"점심시간이에요 🍽️", "sun", "#FF5722", "#2a150a", "noon"}
	case hour >= 14 && hour < 18: // 오후
		return timeTheme{"나른한 오후예요 🌇", "sun", "#03A9F4", "#0a1a2a", "afternoon"}
	case hour >= 18 && hour < 21: // 저녁
		return timeTheme{"편안한 저녁이에요 🌆", "home", "#7C4DFF", "#1a0a2a", "evening"}
	case hour >= 21 && hour < 23: // 밤
		return timeTheme{"고요한 밤이에요 🌙", "home", "#5C6BC0", "#0a0a2a", "night"}
	default: // 심야
		return timeTheme{"깊은 밤이에요 🌑", "lock", "#37474F", "#0a0a14", "latenight"}
	}
}

func (h *Hub) buildHomeSurface() map[string]interface{} {
	now := time.Now().In(time.FixedZone("KST", 9*3600))
	hour := now.Hour()
	theme := getTimeTheme(hour)
	timeStr := now.Format("15:04")
	dateStr := now.Format("2006년 1월 2일 월요일")
	// Fix: Korean weekday
	weekdays := map[string]string{
		"Monday": "월요일", "Tuesday": "화요일", "Wednesday": "수요일",
		"Thursday": "목요일", "Friday": "금요일", "Saturday": "토요일", "Sunday": "일요일",
	}
	for en, ko := range weekdays {
		if now.Weekday().String() == en {
			dateStr = now.Format("2006년 1월 2일 ") + ko
		}
	}

	// Header card: time + greeting
	headerCard := card("elevated",
		row(12,
			icon(theme.icon, 32, theme.accent),
			column(4,
				text("h3", timeStr),
				text("caption", dateStr),
			),
		),
		divider(),
		text("body", theme.greeting),
	)

	// Device summary
	h.mu.RLock()
	defer h.mu.RUnlock()

	var deviceRows []comp
	openDoors := 0
	activePlugs := 0

	for _, d := range h.devices {
		var iconName, color, stateText string
		switch d.Type {
		case "contact_sensor":
			if v, ok := d.State["contact"]; ok && v == true {
				iconName, color, stateText = "door", "#F44336", "열림"
				openDoors++
			} else {
				iconName, color, stateText = "door", "#4CAF50", "닫힘"
			}
		case "on_off_plug":
			if v, ok := d.State["on"]; ok && v == true {
				iconName, color, stateText = "plug", "#FF9800", "켜짐"
				activePlugs++
			} else {
				iconName, color, stateText = "plug", "#6b7280", "꺼짐"
			}
		case "on_off_light":
			if v, ok := d.State["on"]; ok && v == true {
				iconName, color, stateText = "light", "#FFC107", "켜짐"
				activePlugs++
			} else {
				iconName, color, stateText = "light", "#6b7280", "꺼짐"
			}
		default:
			iconName, color, stateText = "sensor", "#6b7280", "알 수 없음"
		}

		label := d.Name
		if d.Room != "" {
			label = fmt.Sprintf("%s · %s", d.Room, d.Name)
		}
		deviceRows = append(deviceRows, row(10,
			icon(iconName, 20, color),
			text("body", label),
			text("caption", stateText),
		))
	}

	// Status summary
	summaryText := "모든 것이 정상이에요 ✅"
	if openDoors > 0 && (hour >= 22 || hour < 6) {
		summaryText = fmt.Sprintf("⚠️ 문 %d개가 열려있어요! 확인해 주세요.", openDoors)
	} else if openDoors > 0 {
		summaryText = fmt.Sprintf("🚪 문 %d개 열림 · 🔌 활성 %d개", openDoors, activePlugs)
	} else if activePlugs > 0 {
		summaryText = fmt.Sprintf("🔌 활성 기기 %d개", activePlugs)
	}

	deviceCardChildren := []comp{
		row(8, icon("home", 20, theme.accent), text("h5", "우리 집 현황")),
		text("caption", summaryText),
		divider(),
	}
	deviceCardChildren = append(deviceCardChildren, deviceRows...)

	devCard := card("outlined", deviceCardChildren...)

	return map[string]interface{}{
		"surfaceId":  "home",
		"components": []comp{headerCard, devCard},
		"theme": map[string]string{
			"accent": theme.accent,
			"bg":     theme.bg,
			"mood":   theme.mood,
		},
	}
}

func (h *Hub) handleHomeSurface(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(h.buildHomeSurface())
}

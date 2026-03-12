package hub

import (
	"os"
	"path/filepath"
	"runtime"
	"testing"
)

// writeMockScript creates a temporary script that outputs the given text.
// Returns the script path. Caller should defer os.Remove.
func writeMockScript(t *testing.T, output string, exitCode int) string {
	t.Helper()
	if runtime.GOOS == "windows" {
		t.Skip("skipping on Windows")
	}

	dir := t.TempDir()
	path := filepath.Join(dir, "mock-ot-ctl")

	content := "#!/bin/sh\n"
	if output != "" {
		content += "printf '%s' '" + output + "'\n"
	}
	if exitCode != 0 {
		content += "exit " + string(rune('0'+exitCode)) + "\n"
	}

	if err := os.WriteFile(path, []byte(content), 0755); err != nil {
		t.Fatal(err)
	}
	return path
}

func TestGetOTBRDataset_ValidHex(t *testing.T) {
	// ot-ctl typically outputs: "<hex>\nDone\n"
	hex := "0e080000000000010000000300001235060004001fffe00208dead00beef00cafe0708fddead00beef00000510112233445566778899aabbccddeeff030f4f70656e5468726561642d3132333401021234041061e1206d2c2b46e079eb775f41fc72190c0402a0f7f8"
	script := writeMockScript(t, hex+"\nDone\n", 0)

	dataset, err := getOTBRDataset(script)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if dataset != hex {
		t.Errorf("expected %q, got %q", hex, dataset)
	}
}

func TestGetOTBRDataset_HexOnly(t *testing.T) {
	// Some ot-ctl versions output hex without "Done"
	hex := "0e080000000000010000"
	script := writeMockScript(t, hex+"\n", 0)

	dataset, err := getOTBRDataset(script)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if dataset != hex {
		t.Errorf("expected %q, got %q", hex, dataset)
	}
}

func TestGetOTBRDataset_EmptyOutput(t *testing.T) {
	// ot-ctl returns empty when no active dataset
	script := writeMockScript(t, "", 0)

	dataset, err := getOTBRDataset(script)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if dataset != "" {
		t.Errorf("expected empty dataset, got %q", dataset)
	}
}

func TestGetOTBRDataset_CommandNotFound(t *testing.T) {
	// ot-ctl binary doesn't exist
	_, err := getOTBRDataset("/nonexistent/ot-ctl")
	if err == nil {
		t.Fatal("expected error for missing ot-ctl")
	}
}

func TestGetOTBRDataset_CommandFails(t *testing.T) {
	// ot-ctl exits with non-zero code
	dir := t.TempDir()
	path := filepath.Join(dir, "mock-ot-ctl")
	if err := os.WriteFile(path, []byte("#!/bin/sh\nexit 1\n"), 0755); err != nil {
		t.Fatal(err)
	}

	_, err := getOTBRDataset(path)
	if err == nil {
		t.Fatal("expected error for failing ot-ctl")
	}
}

func TestGetOTBRDataset_WhitespaceHandling(t *testing.T) {
	// ot-ctl output with extra whitespace/newlines
	hex := "0e080000000000010000"
	script := writeMockScript(t, "  "+hex+"  \n  Done  \n\n", 0)

	dataset, err := getOTBRDataset(script)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if dataset != hex {
		t.Errorf("expected %q, got %q", hex, dataset)
	}
}

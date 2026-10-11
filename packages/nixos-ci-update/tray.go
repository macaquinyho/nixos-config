package main

import (
	"encoding/json"
	"fmt"
	"log"
	"os"
	"os/exec"
	"path/filepath"
	"sync"
	"time"

	"fyne.io/systray"
)

type tray struct {
	cfg *config

	mu     sync.Mutex
	latest *build
	busy   string // what's running, or the last error
	ready  string // the system downloaded and diffed, waiting to be switched to

	status, running, latestItem  *systray.MenuItem
	download, changes, switchNow *systray.MenuItem
}

// running is the rev and date of the booted configuration, written to /etc by the NixOS module.
func running() string {
	var sys struct {
		Rev  string `json:"rev"`
		Date int64  `json:"date"`
	}
	data, err := os.ReadFile("/etc/nixos-ci-update/system.json")
	if err != nil || json.Unmarshal(data, &sys) != nil {
		return "unknown"
	}
	return fmt.Sprintf("%.10s (%s)", sys.Rev, time.Unix(sys.Date, 0).Format("2006-01-02 15:04"))
}

func (t *tray) render() {
	t.mu.Lock()
	defer t.mu.Unlock()
	current, _ := filepath.EvalSymlinks("/run/current-system")

	title := "Not checked yet"
	latest := "Latest: unknown"
	available, ready := false, false
	if t.latest != nil {
		latest = fmt.Sprintf("Latest: %.10s (%s)", t.latest.Rev, t.latest.Date.Format("2006-01-02 15:04"))
		available = t.latest.Path != current
		ready = available && t.ready == t.latest.Path
		switch {
		case !available:
			title = "Up to date"
		case ready:
			title = "Ready to switch"
		default:
			title = "Update available"
		}
	}
	if t.busy != "" {
		title = t.busy
	}

	if available {
		systray.SetIconName("nix-snowflake")
	} else {
		systray.SetIconName("nix-snowflake-white")
	}
	systray.SetTooltip(title + "\nRunning: " + running() + "\n" + latest)
	t.status.SetTitle(title)
	t.running.SetTitle("Running: " + running())
	t.latestItem.SetTitle(latest)
	setEnabled(t.download, available && !ready)
	setEnabled(t.changes, ready)
	setEnabled(t.switchNow, ready)
}

func setEnabled(item *systray.MenuItem, enabled bool) {
	if enabled {
		item.Enable()
	} else {
		item.Disable()
	}
}

// do runs an action in the background, showing label until it finishes and its error after.
func (t *tray) do(label string, action func() error) {
	t.mu.Lock()
	t.busy = label
	t.mu.Unlock()
	t.render()
	go func() {
		err := action()
		t.mu.Lock()
		t.busy = ""
		if err != nil {
			log.Print(err)
			t.busy = "Failed: " + err.Error()
		}
		t.mu.Unlock()
		t.render()
	}()
}

func (t *tray) check() error {
	b, err := latestBuild(t.cfg)
	if err != nil {
		return err
	}
	t.mu.Lock()
	t.latest = b
	t.mu.Unlock()
	return nil
}

func diffPath() string { return filepath.Join(os.TempDir(), "nixos-ci-update.diff") }

// downloadAndDiff substitutes the new system and shows what changes.
func (t *tray) downloadAndDiff() error {
	t.mu.Lock()
	path := t.latest.Path
	t.mu.Unlock()
	if out, err := exec.Command(t.cfg.NixStore, "--realise", path).CombinedOutput(); err != nil {
		return fmt.Errorf("downloading: %s", out)
	}
	current, _ := filepath.EvalSymlinks("/run/current-system")
	diff, err := exec.Command(t.cfg.Dix, "--color", "always", current, path).Output()
	if err != nil {
		return fmt.Errorf("dix: %w", err)
	}
	if err := os.WriteFile(diffPath(), diff, 0o644); err != nil {
		return err
	}
	t.mu.Lock()
	t.ready = path
	t.mu.Unlock()
	t.inTerminal("less", "-R", diffPath())
	return nil
}

func (t *tray) switchTo() error {
	t.mu.Lock()
	path := t.ready
	t.mu.Unlock()
	return startSwitch(path)
}

func (t *tray) inTerminal(args ...string) {
	go func() {
		out, err := exec.Command(t.cfg.Terminal, args...).CombinedOutput()
		if err != nil {
			log.Printf("%s %v: %v: %s", t.cfg.Terminal, args, err, out)
		}
	}()
}

func onClick(item *systray.MenuItem, f func()) {
	go func() {
		for range item.ClickedCh {
			f()
		}
	}()
}

func runTray(cfg *config) {
	t := &tray{cfg: cfg}
	systray.Run(func() {
		systray.SetTitle("NixOS updates")
		systray.SetIconThemePath(cfg.IconThemePath)
		info := func() *systray.MenuItem {
			item := systray.AddMenuItem("", "")
			item.Disable()
			return item
		}
		t.status, t.running, t.latestItem = info(), info(), info()
		systray.AddSeparator()
		checkNow := systray.AddMenuItem("Check now", "")
		t.download = systray.AddMenuItem("Download and show changes", "")
		t.changes = systray.AddMenuItem("Show changes", "")
		t.switchNow = systray.AddMenuItem("Switch", "")
		switchLog := systray.AddMenuItem("Show switch log", "")

		onClick(checkNow, func() { t.do("Checking…", t.check) })
		onClick(t.download, func() { t.do("Downloading…", t.downloadAndDiff) })
		onClick(t.changes, func() { t.inTerminal("less", "-R", diffPath()) })
		onClick(t.switchNow, func() { t.do("Switching…", t.switchTo) })
		onClick(switchLog, func() { t.inTerminal("journalctl", "-fu", "nixos-ci-switch@*") })

		go func() {
			// systray drops whatever is set while it starts up, so wait a bit before the first render
			time.Sleep(2 * time.Second)
			t.do("Checking…", t.check)
			for range time.Tick(time.Hour) {
				t.do("Checking…", t.check)
			}
		}()
		go func() {
			// picks up a switch done outside the tray
			for range time.Tick(time.Minute) {
				t.render()
			}
		}()
	}, nil)
}

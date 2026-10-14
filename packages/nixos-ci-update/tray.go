package main

import (
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

	mu      sync.Mutex
	latest  *build
	running *build // nil when CI never built the current system
	checked string // the current system when last checked
	busy    string // what's running, or the last error
	ready   string // the system downloaded and diffed, waiting to be switched to

	status, runningItem, latestItem *systray.MenuItem
	download, changes, switchNow    *systray.MenuItem
}

func currentSystem() string {
	current, _ := filepath.EvalSymlinks("/run/current-system")
	return current
}

func describe(b *build) string {
	return fmt.Sprintf("%.10s (%s)", b.Rev, b.Date.Format("2006-01-02 15:04"))
}

func (t *tray) render() {
	t.mu.Lock()
	defer t.mu.Unlock()
	current := currentSystem()

	title := "Not checked yet"
	running := "Running: unknown"
	latest := "Latest: unknown"
	available, ready := false, false
	if t.latest != nil && t.checked == current {
		latest = "Latest: " + describe(t.latest)
		available = t.latest.Path != current
		ready = available && t.ready == t.latest.Path
		switch {
		case !available:
			title = "Up to date"
		case t.running == nil:
			title = "Running a build CI didn't make: push, rebase or wait for CI"
			running = "Running: local build"
		case ready:
			title = "Ready to switch"
		default:
			title = "Update available"
		}
		if t.running != nil {
			running = "Running: " + describe(t.running)
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
	systray.SetTooltip(title + "\n" + running + "\n" + latest)
	t.status.SetTitle(title)
	t.runningItem.SetTitle(running)
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
	current := currentSystem()
	latest, running, err := builds(t.cfg, current)
	if err != nil {
		return err
	}
	t.mu.Lock()
	t.latest, t.running, t.checked = latest, running, current
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
	diff, err := exec.Command(t.cfg.Dix, "--color", "always", currentSystem(), path).Output()
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
		t.status, t.runningItem, t.latestItem = info(), info(), info()
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
				t.mu.Lock()
				stale := t.latest != nil && t.busy == "" && t.checked != currentSystem()
				t.mu.Unlock()
				if stale {
					t.do("Checking…", t.check)
				}
			}
		}()
	}, nil)
}

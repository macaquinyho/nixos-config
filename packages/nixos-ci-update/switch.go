package main

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"time"

	"github.com/godbus/dbus/v5"
)

// startSwitch asks systemd, and so polkit, to start nixos-ci-switch@HASH, and waits for it.
func startSwitch(path string) error {
	conn, err := dbus.ConnectSystemBus()
	if err != nil {
		return err
	}
	defer conn.Close()
	unit := "nixos-ci-switch@" + filepath.Base(path)[:32] + ".service"
	systemd := conn.Object("org.freedesktop.systemd1", "/org/freedesktop/systemd1")

	// Object.Call drops this flag, and without it polkit refuses instead of prompting
	args := []any{unit, "replace"}
	call := <-conn.Send(&dbus.Message{
		Type:  dbus.TypeMethodCall,
		Flags: dbus.FlagAllowInteractiveAuthorization,
		Headers: map[dbus.HeaderField]dbus.Variant{
			dbus.FieldDestination: dbus.MakeVariant("org.freedesktop.systemd1"),
			dbus.FieldPath:        dbus.MakeVariant(systemd.Path()),
			dbus.FieldInterface:   dbus.MakeVariant("org.freedesktop.systemd1.Manager"),
			dbus.FieldMember:      dbus.MakeVariant("StartUnit"),
			dbus.FieldSignature:   dbus.MakeVariant(dbus.SignatureOf(args...)),
		},
		Body: args,
	}, make(chan *dbus.Call, 1)).Done
	if call.Err != nil {
		return call.Err
	}

	var unitPath dbus.ObjectPath
	if err := systemd.Call("org.freedesktop.systemd1.Manager.GetUnit", 0, unit).Store(&unitPath); err != nil {
		return err
	}
	for {
		time.Sleep(2 * time.Second)
		state, err := conn.Object("org.freedesktop.systemd1", unitPath).GetProperty("org.freedesktop.systemd1.Unit.ActiveState")
		if err != nil {
			return err
		}
		switch state.Value() {
		case "failed":
			return fmt.Errorf("the switch failed, see its log")
		case "activating":
		default:
			return nil
		}
	}
}

var storeHash = regexp.MustCompile(`^[0-9a-z]{32}$`)

// switchTo runs as root. Paths built locally are unsigned, so it only switches to CI's systems.
func switchTo(hash string) error {
	if !storeHash.MatchString(hash) {
		return fmt.Errorf("not a store path hash: %q", hash)
	}
	matches, _ := filepath.Glob("/nix/store/" + hash + "-nixos-system-*")
	if len(matches) != 1 {
		return fmt.Errorf("no NixOS system with hash %s", hash)
	}
	if err := run("nix", "store", "verify", "--no-contents", "--sigs-needed", "1", matches[0]); err != nil {
		return err
	}
	return run("nixos-rebuild", "switch", "--store-path", matches[0])
}

func run(name string, args ...string) error {
	cmd := exec.Command(name, args...)
	cmd.Stdout, cmd.Stderr = os.Stdout, os.Stderr
	if err := cmd.Run(); err != nil {
		return fmt.Errorf("%s: %w", name, err)
	}
	return nil
}

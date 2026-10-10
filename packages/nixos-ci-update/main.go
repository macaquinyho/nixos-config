// Command nixos-ci-update shows a tray icon to switch to the system CI built from the latest commit.
//
//	nixos-ci-update tray CONFIG   the tray, run as the user
//	nixos-ci-update switch HASH   run as root by nixos-ci-switch@HASH.service
package main

import (
	"encoding/json"
	"log"
	"os"
)

type config struct {
	RepoURL       string `json:"repoUrl"`
	Branch        string `json:"branch"`
	Host          string `json:"host"`
	TokenUser     string `json:"tokenUser"`
	TokenFile     string `json:"tokenFile"`
	NixStore      string `json:"nixStore"`
	Dix           string `json:"dix"`
	Terminal      string `json:"terminal"`
	IconThemePath string `json:"iconThemePath"`
}

func main() {
	if len(os.Args) != 3 {
		log.Fatal("usage: nixos-ci-update tray CONFIG | switch HASH")
	}
	switch os.Args[1] {
	case "tray":
		data, err := os.ReadFile(os.Args[2])
		if err != nil {
			log.Fatal(err)
		}
		var cfg config
		if err := json.Unmarshal(data, &cfg); err != nil {
			log.Fatal(err)
		}
		runTray(&cfg)
	case "switch":
		if err := switchTo(os.Args[2]); err != nil {
			log.Fatal(err)
		}
	default:
		log.Fatalf("unknown command %q", os.Args[1])
	}
}

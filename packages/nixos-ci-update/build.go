package main

import (
	"context"
	"fmt"
	"os"
	"strings"
	"time"

	"github.com/go-git/go-git/v5/plumbing"
	"github.com/go-git/go-git/v5/plumbing/format/packfile"
	"github.com/go-git/go-git/v5/plumbing/object"
	"github.com/go-git/go-git/v5/plumbing/protocol/packp"
	"github.com/go-git/go-git/v5/plumbing/protocol/packp/capability"
	"github.com/go-git/go-git/v5/plumbing/transport"
	githttp "github.com/go-git/go-git/v5/plumbing/transport/http"
	"github.com/go-git/go-git/v5/storage/memory"
)

// CI adds a note to every commit it builds, with a "host /nix/store/..." line per host.
const notesRef = plumbing.ReferenceName("refs/notes/ci")

// build is the newest commit on the branch that CI built.
type build struct {
	Rev  string
	Date time.Time
	Path string
}

// latestBuild fetches only the notes and the branch's last 50 commit objects, no files.
func latestBuild(cfg *config) (*build, error) {
	token, err := os.ReadFile(cfg.TokenFile)
	if err != nil {
		return nil, err
	}
	auth := &githttp.BasicAuth{Username: cfg.TokenUser, Password: strings.TrimSpace(string(token))}
	ep, err := transport.NewEndpoint(strings.TrimPrefix(cfg.RepoURL, "git+"))
	if err != nil {
		return nil, err
	}
	sess, err := githttp.DefaultClient.NewUploadPackSession(ep, auth)
	if err != nil {
		return nil, err
	}
	defer sess.Close()
	adv, err := sess.AdvertisedReferences()
	if err != nil {
		return nil, err
	}
	refs, err := adv.AllReferences()
	if err != nil {
		return nil, err
	}
	tip, ok := refs[plumbing.NewBranchReferenceName(cfg.Branch)]
	if !ok {
		return nil, fmt.Errorf("no branch %s", cfg.Branch)
	}
	notesTip, ok := refs[notesRef]
	if !ok {
		return nil, fmt.Errorf("CI hasn't noted any build yet")
	}

	st := memory.NewStorage()
	fetch := func(want plumbing.Hash, depth int, filter packp.Filter) error {
		req := packp.NewUploadPackRequestFromCapabilities(adv.Capabilities)
		req.Wants = []plumbing.Hash{want}
		req.Depth = packp.DepthCommits(depth)
		req.Filter = filter
		req.Capabilities.Set(capability.Shallow)
		if filter != "" {
			req.Capabilities.Set(capability.Filter)
		}
		// without side-band the response is the bare pack
		req.Capabilities.Delete(capability.Sideband64k)
		req.Capabilities.Delete(capability.Sideband)
		resp, err := sess.UploadPack(context.Background(), req)
		if err != nil {
			return err
		}
		defer resp.Close()
		return packfile.UpdateObjectStorage(st, resp)
	}
	if err := fetch(notesTip.Hash(), 1, ""); err != nil {
		return nil, fmt.Errorf("fetching the notes: %w", err)
	}
	if err := fetch(tip.Hash(), 50, packp.FilterTreeDepth(0)); err != nil {
		return nil, fmt.Errorf("fetching %s: %w", cfg.Branch, err)
	}

	notesCommit, err := object.GetCommit(st, notesTip.Hash())
	if err != nil {
		return nil, err
	}
	notesTree, err := notesCommit.Tree()
	if err != nil {
		return nil, err
	}
	for h := tip.Hash(); ; {
		c, err := object.GetCommit(st, h)
		if err != nil {
			return nil, fmt.Errorf("no build in the last 50 commits")
		}
		// notes are stored as files named after the commit, possibly split in fanout directories
		if note, err := findNote(notesTree, h); err == nil {
			for _, line := range strings.Split(note, "\n") {
				if host, path, _ := strings.Cut(line, " "); host == cfg.Host {
					return &build{Rev: h.String(), Date: c.Committer.When, Path: path}, nil
				}
			}
			return nil, fmt.Errorf("CI built %s without %s", h.String()[:10], cfg.Host)
		}
		if len(c.ParentHashes) == 0 {
			return nil, fmt.Errorf("no build on %s", cfg.Branch)
		}
		h = c.ParentHashes[0]
	}
}

func findNote(tree *object.Tree, commit plumbing.Hash) (string, error) {
	name := commit.String()
	for _, path := range []string{name, name[:2] + "/" + name[2:], name[:2] + "/" + name[2:4] + "/" + name[4:]} {
		if f, err := tree.File(path); err == nil {
			return f.Contents()
		}
	}
	return "", fmt.Errorf("no note")
}

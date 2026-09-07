package main

import (
	"errors"
	"testing"

	"github.com/metacubex/mihomo/constant"
	"github.com/metacubex/mihomo/tunnel/statistic"
)

type closeTestTracker struct {
	id         string
	closeErr   error
	closeCount int
	onClose    func()
}

func (t *closeTestTracker) ID() string {
	return t.id
}

func (t *closeTestTracker) Close() error {
	t.closeCount++
	if t.onClose != nil {
		t.onClose()
	}
	return t.closeErr
}

func (t *closeTestTracker) Info() *statistic.TrackerInfo {
	return &statistic.TrackerInfo{}
}

func (t *closeTestTracker) Chains() constant.Chain {
	return nil
}

func (t *closeTestTracker) ProviderChains() constant.Chain {
	return nil
}

func (t *closeTestTracker) AppendToChains(constant.ProxyAdapter) {}

func (t *closeTestTracker) RemoteDestination() string {
	return ""
}

func TestCloseTrackedConnectionsContinuesAfterCloseError(t *testing.T) {
	trackers := []*closeTestTracker{
		{id: "first", closeErr: errors.New("close failed")},
		{id: "second"},
		{id: "third"},
	}

	attempted, failed := closeTrackedConnections(func(closeTracker func(statistic.Tracker) bool) {
		for _, tracker := range trackers {
			if !closeTracker(tracker) {
				break
			}
		}
	})

	if attempted != 3 || failed != 1 {
		t.Fatalf("close counts = attempted %d, failed %d", attempted, failed)
	}
	for _, tracker := range trackers {
		if tracker.closeCount != 1 {
			t.Fatalf("tracker %s closed %d times", tracker.id, tracker.closeCount)
		}
	}
}

func TestStopListenerClosesTrackedConnections(t *testing.T) {
	tracker := &closeTestTracker{id: t.Name()}
	tracker.onClose = func() {
		statistic.DefaultManager.Leave(tracker)
	}
	statistic.DefaultManager.Join(tracker)
	t.Cleanup(func() {
		statistic.DefaultManager.Leave(tracker)
	})

	if !handleStopListener() {
		t.Fatal("stop listener failed")
	}
	if tracker.closeCount != 1 {
		t.Fatalf("tracked connection closed %d times", tracker.closeCount)
	}
	if statistic.DefaultManager.Get(tracker.id) != nil {
		t.Fatal("tracked connection remains after listener stop")
	}
}

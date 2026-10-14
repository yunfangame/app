package main

import (
	"context"
	"encoding/json"
	"net"
	"os"
	"strings"
	"sync/atomic"
	"testing"
	"time"

	"github.com/metacubex/mihomo/config"
	C "github.com/metacubex/mihomo/constant"
	D "github.com/metacubex/mihomo/dns"
	"github.com/metacubex/mihomo/tunnel"
	DNS "github.com/miekg/dns"
	"gopkg.in/yaml.v3"
)

func TestGeneratedBypassDomainConfiguration(t *testing.T) {
	path := os.Getenv("FENGWO_BYPASS_FIXTURE")
	if path == "" {
		t.Skip("Requires generated Flutter runtime fixtures")
	}
	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	var fixtures []struct {
		Mode       string `json:"mode"`
		FilterMode string `json:"filter_mode"`
		YAML       string `json:"yaml"`
	}
	if err := json.Unmarshal(data, &fixtures); err != nil {
		t.Fatal(err)
	}
	if len(fixtures) != 6 {
		t.Fatalf("Expected six generated fixtures, got %d", len(fixtures))
	}
	for _, fixture := range fixtures {
		t.Run(fixture.Mode+"-"+fixture.FilterMode, func(t *testing.T) {
			var privateQueries, publicQueries atomic.Uint32
			startDNS := func(address string, counter *atomic.Uint32) string {
				connection, err := net.ListenPacket("udp", "127.0.0.1:0")
				if err != nil {
					t.Fatal(err)
				}
				server := &DNS.Server{PacketConn: connection, Handler: DNS.HandlerFunc(func(writer DNS.ResponseWriter, request *DNS.Msg) {
					counter.Add(1)
					response := new(DNS.Msg)
					response.SetReply(request)
					for _, question := range request.Question {
						if question.Qtype == DNS.TypeA {
							response.Answer = append(response.Answer, &DNS.A{Hdr: DNS.RR_Header{Name: question.Name, Rrtype: DNS.TypeA, Class: DNS.ClassINET, Ttl: 1}, A: net.ParseIP(address)})
						}
					}
					_ = writer.WriteMsg(response)
				})}
				go server.ActivateAndServe()
				t.Cleanup(func() { _ = server.Shutdown() })
				return connection.LocalAddr().String()
			}
			privateServer := startDNS("10.23.0.5", &privateQueries)
			publicServer := startDNS("203.0.113.15", &publicQueries)
			var raw yaml.Node
			if err := yaml.Unmarshal([]byte(fixture.YAML), &raw); err != nil {
				t.Fatal(err)
			}
			lookup := func(node *yaml.Node, name string) *yaml.Node {
				for index := 0; index < len(node.Content); index += 2 {
					if node.Content[index].Value == name {
						return node.Content[index+1]
					}
				}
				t.Fatalf("Missing generated YAML key: %s", name)
				return nil
			}
			setServer := func(node *yaml.Node, server string) {
				node.Kind = yaml.SequenceNode
				node.Tag = "!!seq"
				node.Value = ""
				node.Content = []*yaml.Node{{Kind: yaml.ScalarNode, Tag: "!!str", Value: server}}
			}
			dns := lookup(raw.Content[0], "dns")
			setServer(lookup(dns, "nameserver"), publicServer)
			setServer(lookup(dns, "direct-nameserver"), publicServer)
			policies := lookup(dns, "nameserver-policy")
			for index := 0; index < len(policies.Content); index += 2 {
				name := policies.Content[index].Value
				if strings.HasPrefix(name, "rule-set:fengwo-bypass-domains") {
					setServer(policies.Content[index+1], privateServer+"#DIRECT")
				} else {
					setServer(policies.Content[index+1], publicServer)
				}
			}
			encoded, err := yaml.Marshal(raw.Content[0])
			if err != nil {
				t.Fatal(err)
			}
			parsed, err := config.Parse(encoded)
			if err != nil {
				t.Fatal(err)
			}
			for _, provider := range parsed.RuleProviders {
				if err := provider.Initial(); err != nil {
					t.Fatal(err)
				}
			}
			tunnel.UpdateRules(parsed.Rules, parsed.SubRules, parsed.RuleProviders)
			tunnel.UpdateProxies(parsed.Proxies, parsed.Providers)
			resolvers := D.NewResolver(D.Config{Main: parsed.DNS.NameServer, Policy: parsed.DNS.NameServerPolicy, DirectServer: parsed.DNS.DirectNameServer, DirectFollowPolicy: parsed.DNS.DirectFollowPolicy})
			ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
			defer cancel()
			ip, err := resolvers.Resolver.LookupIPv4(ctx, "oa.corp.example")
			if err != nil {
				t.Fatal(err)
			}
			if fixture.Mode == "rule" {
				if len(ip) != 1 || ip[0].String() != "10.23.0.5" || privateQueries.Load() == 0 || publicQueries.Load() != 0 {
					t.Fatalf("Excluded DNS leaked to public resolver: ip=%v private=%d public=%d", ip, privateQueries.Load(), publicQueries.Load())
				}
				ip, err = resolvers.DirectResolver.LookupIPv4(ctx, "oa.corp.example")
				if err != nil || len(ip) != 1 || ip[0].String() != "10.23.0.5" || publicQueries.Load() != 0 {
					t.Fatalf("Direct re-resolution bypassed intranet policy: ip=%v error=%v public=%d", ip, err, publicQueries.Load())
				}
				if !parsed.DNS.FakeIPSkipper.ShouldSkipped("oa.corp.example") {
					t.Fatal("Excluded domain still receives a fake IP")
				}
				matched, target := parsed.Rules[0].Match(&C.Metadata{Host: "oa.corp.example"}, C.RuleMatchHelper{})
				if !matched || target != "DIRECT" {
					t.Fatalf("Excluded route is not direct: %v %s", matched, target)
				}
			} else if len(ip) != 1 || ip[0].String() != "203.0.113.15" || privateQueries.Load() != 0 {
				t.Fatal("Global mode DNS was changed by intranet exclusions")
			}
			ip, err = resolvers.Resolver.LookupIPv4(ctx, "www.public.test")
			if err != nil || len(ip) != 1 || ip[0].String() != "203.0.113.15" {
				t.Fatalf("Ordinary website DNS changed: ip=%v error=%v", ip, err)
			}
			if parsed.DNS.FakeIPSkipper.ShouldSkipped("www.public.test") {
				t.Fatal("Ordinary website fake-IP behavior changed")
			}
			if fixture.FilterMode == "whitelist" && !parsed.DNS.FakeIPSkipper.ShouldSkipped("outside.whitelist.test") {
				t.Fatal("Original fake-IP whitelist default changed")
			}
		})
	}
}

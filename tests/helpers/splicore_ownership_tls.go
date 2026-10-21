// Isolated audit executable, never a Splicore daemon or migration substitute.
// Only the published rc.3 backend is imported; production validators are untouched.
package main

import (
	"context"
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	"crypto/sha256"
	"crypto/tls"
	"crypto/x509"
	"crypto/x509/pkix"
	"encoding/hex"
	"encoding/json"
	"encoding/pem"
	"fmt"
	"io"
	"math/big"
	"net"
	"os"
	"path/filepath"
	"time"

	"github.com/ike-sh/Splicore/internal/splicore/domain/access"
	cfg "github.com/ike-sh/Splicore/internal/splicore/domain/streamtransport"
	"github.com/ike-sh/Splicore/internal/splicore/tlsconfig"
	"github.com/ike-sh/Splicore/protocol/hysteria2/backend"
)

func must(err error) {
	if err != nil {
		panic(err)
	}
}
func output(v any) { must(json.NewEncoder(os.Stdout).Encode(v)) }
func pair(cert, key string) tls.Certificate {
	p, e := tls.LoadX509KeyPair(cert, key)
	must(e)
	return p
}
func parsed(p tls.Certificate) *x509.Certificate {
	c, e := x509.ParseCertificate(p.Certificate[0])
	must(e)
	return c
}
func errorText(e error) string {
	if e != nil {
		return e.Error()
	}
	return "PASS"
}
func writeCert(dir, name string, c, parent *x509.Certificate, key, signer *ecdsa.PrivateKey) {
	der, e := x509.CreateCertificate(rand.Reader, c, parent, &key.PublicKey, signer)
	must(e)
	must(os.WriteFile(filepath.Join(dir, name+".pem"), pem.EncodeToMemory(&pem.Block{Type: "CERTIFICATE", Bytes: der}), 0644))
	b, e := x509.MarshalECPrivateKey(key)
	must(e)
	must(os.WriteFile(filepath.Join(dir, name+"-key.pem"), pem.EncodeToMemory(&pem.Block{Type: "EC PRIVATE KEY", Bytes: b}), 0600))
}
func mint(dir, cert, key string) {
	old := pair(cert, key)
	root := parsed(old)
	signer := old.PrivateKey.(*ecdsa.PrivateKey)
	makeTemplate := func(n int64) *x509.Certificate {
		return &x509.Certificate{SerialNumber: big.NewInt(n), Subject: pkix.Name{CommonName: "probe.example"}, NotBefore: time.Now().Add(-time.Hour), NotAfter: time.Now().Add(24 * time.Hour), DNSNames: []string{"probe.example", "localhost"}, BasicConstraintsValid: true, KeyUsage: x509.KeyUsageDigitalSignature, ExtKeyUsage: []x509.ExtKeyUsage{x509.ExtKeyUsageServerAuth}}
	}
	san := makeTemplate(100)
	san.IsCA = true
	san.KeyUsage |= x509.KeyUsageCertSign
	writeCert(dir, "san-ca", san, san, signer, signer)
	leafKey, e := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	must(e)
	writeCert(dir, "same-ca-leaf", makeTemplate(101), root, leafKey, signer)
	newKey, e := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	must(e)
	ca := makeTemplate(102)
	ca.IsCA = true
	ca.KeyUsage |= x509.KeyUsageCertSign
	writeCert(dir, "new-ca", ca, ca, newKey, newKey)
	b, e := os.ReadFile(filepath.Join(dir, "new-ca.pem"))
	must(e)
	block, _ := pem.Decode(b)
	newRoot, e := x509.ParseCertificate(block.Bytes)
	must(e)
	writeCert(dir, "new-leaf", makeTemplate(103), newRoot, leafKey, newKey)
	expired := makeTemplate(104)
	expired.NotBefore = time.Now().Add(-48 * time.Hour)
	expired.NotAfter = time.Now().Add(-time.Hour)
	writeCert(dir, "expired", expired, root, leafKey, signer)
	wrong := makeTemplate(105)
	wrong.ExtKeyUsage = []x509.ExtKeyUsage{x509.ExtKeyUsageClientAuth}
	writeCert(dir, "wrong-eku", wrong, root, leafKey, signer)
	wrongKU := makeTemplate(106)
	wrongKU.KeyUsage = x509.KeyUsageKeyEncipherment
	writeCert(dir, "wrong-ku", wrongKU, root, leafKey, signer)
	absentUsage := makeTemplate(107)
	absentUsage.KeyUsage = 0
	absentUsage.ExtKeyUsage = nil
	writeCert(dir, "absent-usage", absentUsage, root, leafKey, signer)
	output(map[string]string{"mint": "PASS; controls only, original files unchanged"})
}
func inspect(cert, key, ca, name string) {
	p := pair(cert, key)
	c := parsed(p)
	roots := x509.NewCertPool()
	b, e := os.ReadFile(ca)
	must(e)
	roots.AppendCertsFromPEM(b)
	_, chain := c.Verify(x509.VerifyOptions{Roots: roots})
	_, named := c.Verify(x509.VerifyOptions{Roots: roots, DNSName: name})
	h := sha256.Sum256(c.Raw)
	exts := []map[string]any{}
	for _, ext := range c.Extensions {
		exts = append(exts, map[string]any{"oid": ext.Id.String(), "critical": ext.Critical})
	}
	output(map[string]any{"subject": c.Subject.String(), "issuer": c.Issuer.String(), "is_ca": c.IsCA, "basic_constraints_valid": c.BasicConstraintsValid, "key_usage": c.KeyUsage, "eku": c.ExtKeyUsage, "dns_san": c.DNSNames, "ip_san": c.IPAddresses, "not_before": c.NotBefore, "not_after": c.NotAfter, "key_type": fmt.Sprintf("%T", c.PublicKey), "signature_algorithm": c.SignatureAlgorithm.String(), "certificate_count": len(p.Certificate), "sha256": hex.EncodeToString(h[:]), "pair_load": "PASS", "verify_chain_no_hostname": errorText(chain), "verify_hostname": errorText(named), "extensions": exts, "self_signature": errorText(c.CheckSignature(c.SignatureAlgorithm, c.RawTBSCertificate, c.Signature)), "validity_seconds": c.NotAfter.Sub(c.NotBefore).Seconds()})
}
func tlsProbe(cert, key, ca, name, pin string) {
	p := pair(cert, key)
	b, e := os.ReadFile(ca)
	must(e)
	roots := x509.NewCertPool()
	roots.AppendCertsFromPEM(b)
	result := map[string]string{}
	for _, mode := range []string{"insecure", "ca_hostname", "fingerprint"} {
		listener, e := tls.Listen("tcp", "127.0.0.1:0", &tls.Config{Certificates: []tls.Certificate{p}, MinVersion: tls.VersionTLS13})
		must(e)
		done := make(chan struct{})
		go func() {
			defer close(done)
			c, e := listener.Accept()
			if e != nil {
				return
			}
			defer c.Close()
			_ = c.SetDeadline(time.Now().Add(3 * time.Second))
			_, _ = io.Copy(c, c)
		}()
		config := &tls.Config{ServerName: name, RootCAs: roots, MinVersion: tls.VersionTLS13}
		if mode != "ca_hostname" {
			config.InsecureSkipVerify = true
		}
		if mode == "fingerprint" {
			config.VerifyConnection = func(s tls.ConnectionState) error {
				h := sha256.Sum256(s.PeerCertificates[0].Raw)
				if hex.EncodeToString(h[:]) != pin {
					return fmt.Errorf("fingerprint mismatch")
				}
				return nil
			}
		}
		c, e := tls.DialWithDialer(&net.Dialer{Timeout: 3 * time.Second}, "tcp", listener.Addr().String(), config)
		if e == nil {
			_ = c.SetDeadline(time.Now().Add(3 * time.Second))
			_, e = c.Write([]byte("audit"))
			if e == nil {
				v := make([]byte, 5)
				_, e = io.ReadFull(c, v)
				if e == nil && string(v) != "audit" {
					e = fmt.Errorf("echo mismatch")
				}
			}
			c.Close()
		}
		listener.Close()
		<-done
		result[mode] = errorText(e)
	}
	output(result)
}
func hy2(cert, key, port string) {
	p := pair(cert, key)
	ctx := context.Background()
	packet, e := net.ListenPacket("udp", "127.0.0.1:"+port)
	must(e)
	s, e := backend.NewServer(ctx, packet, backend.ServerConfig{TLS: &tls.Config{Certificates: []tls.Certificate{p}, MinVersion: tls.VersionTLS13, NextProtos: []string{"h3"}}, Transport: cfg.Hysteria{Version: 2, Obfs: &cfg.HysteriaObfs{Type: "salamander", Password: "synthetic-salamander-secret"}}, Authenticate: func(v string) (string, bool) { return "audit", v == "synthetic-hy2-auth" }, TCP: func(ctx context.Context, _ string, c *backend.Stream, d access.Endpoint) error {
		target, e := (&net.Dialer{}).DialContext(ctx, "tcp", net.JoinHostPort(d.Host, fmt.Sprint(d.Port)))
		if e != nil {
			return e
		}
		defer target.Close()
		if e = c.Reply(true); e != nil {
			return e
		}
		go io.Copy(target, c)
		_, e = io.Copy(c, target)
		return e
	}, UDP: func(ctx context.Context, _ string, p net.PacketConn) error {
		data := make([]byte, 65535)
		for {
			n, a, e := p.ReadFrom(data)
			if e != nil {
				return e
			}
			target, e := (&net.Dialer{}).DialContext(ctx, "udp", a.String())
			if e != nil {
				return e
			}
			_ = target.SetDeadline(time.Now().Add(3 * time.Second))
			_, e = target.Write(data[:n])
			if e == nil {
				n, e = target.Read(data)
				if e == nil {
					_, e = p.WriteTo(data[:n], a)
				}
			}
			target.Close()
			if e != nil {
				return e
			}
		}
	}})
	must(e)
	s.Start()
	fmt.Println("READY")
	select {}
}
func main() {
	a := os.Args
	switch a[1] {
	case "mint":
		mint(a[2], a[3], a[4])
	case "inspect":
		inspect(a[2], a[3], a[4], a[5])
	case "tls":
		tlsProbe(a[2], a[3], a[4], a[5], a[6])
	case "hy2":
		hy2(a[2], a[3], a[4])
	case "snapshot":
		ca, e := os.ReadFile(a[4])
		must(e)
		_, key, e := tlsconfig.Snapshot(tlsconfig.Settings{ServerName: a[5], CertificateFile: a[2], PrivateKeyFile: a[3], CACertificate: string(ca)})
		clear(key)
		output(map[string]string{"result": errorText(e)})
	}
}

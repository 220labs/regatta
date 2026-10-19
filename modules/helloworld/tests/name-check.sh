#!/usr/bin/env bash
# Tests for bin/name-check — one local stub answers as RDAP, GitHub, npm, PyPI, Porkbun (HTTP)
# and whois (TCP); every NAME_CHECK_* override points there, so no real registry is asked.
#   bash modules/helloworld/tests/name-check.sh
set -u
B="$(cd "$(dirname "$0")/../bin" && pwd)"
T=$(mktemp -d)
fails=0
check() { if [ "$1" = "$2" ]; then echo "  ok   $3"; else echo "  FAIL $3: expected [$2] got [$1]"; fails=$((fails+1)); fi; }
has()   { if grep -qF -- "$2" "$1"; then echo "  ok   $3"; else echo "  FAIL $3: missing [$2]"; sed 's/^/         | /' "$1" | head -20; fails=$((fails+1)); fi; }
hasnt() { if grep -qF -- "$2" "$1"; then echo "  FAIL $3: found [$2]"; fails=$((fails+1)); else echo "  ok   $3"; fi; }

# A name starting "taken" is registered everywhere; "broken" makes the HTTP endpoints answer 500
# and whois answer something unreadable; "ghost" is a PyPI project with no releases (404 on
# /pypi/NAME/json, 200 on /simple/NAME/); "mixed" gets a whois record with both a free phrase
# and "Domain Name:"; "flaky" gets an empty whois answer the first time; anything else is free.
cat > "$T/stub.py" <<'EOF'
import http.server, json, socketserver, sys, threading
class H(http.server.BaseHTTPRequestHandler):
    def log_message(self, *a): pass
    def send(self, code, body=b""):
        self.send_response(code); self.send_header("Content-Length", str(len(body))); self.end_headers(); self.wfile.write(body)
    def do_GET(self):
        p = self.path
        if p == "/dns.json":
            base = "http://127.0.0.1:%d/rdap/" % self.server.server_address[1]
            return self.send(200, json.dumps({"services": [[["dev", "com", "xyz", "app"], [base]]]}).encode())
        name = p.rstrip("/").split("/")[-1] if not p.endswith("/json") else p.split("/")[-2]
        if name.startswith("broken"): return self.send(500)
        if name.startswith("ghost"): return self.send(200 if p.startswith("/simple/") else 404, b"{}")
        self.send(200 if name.startswith("taken") else 404, b"{}")
    def do_POST(self):
        self.rfile.read(int(self.headers.get("Content-Length") or 0))  # unread, the close can be a reset
        if self.path != "/api/json/v3/pricing/get": return self.send(404)
        self.send(200, json.dumps({"status": "SUCCESS", "pricing": {
            "dev": {"registration": "8.75", "renewal": "12.87"}, "com": {"registration": "11.08", "renewal": "11.08"},
            "io": {"registration": "28.12", "renewal": "51.80"}, "app": {"registration": "x"}}}).encode())
class W(socketserver.StreamRequestHandler):
    asked = set()
    def handle(self):
        q = self.rfile.readline().decode().strip()
        if "." not in q:
            out = {"io": "refer: whois.nic.io\nwhois:        whois.nic.io\n",
                   "er": "domain:       ER\nwhois:        \n\nstatus:       ACTIVE\n"}.get(q, "% no whois for this TLD\n")
        elif q.startswith("taken"): out = "Domain Name: %s\nRegistrar: X\n" % q
        elif q.startswith("broken"): out = "rate limited, try later\n"
        elif q.startswith("mixed"): out = "Domain Name: %s\nNOTICE: no match for a reseller lookup\n" % q
        elif q.startswith("flaky") and q not in W.asked: W.asked.add(q); out = ""
        else: out = "Domain not found.\n>>> Last update <<<\n"
        self.wfile.write(out.encode())
socketserver.TCPServer.allow_reuse_address = True
h = http.server.ThreadingHTTPServer(("127.0.0.1", 0), H)
w = socketserver.ThreadingTCPServer(("127.0.0.1", 0), W)
threading.Thread(target=w.serve_forever, daemon=True).start()
open(sys.argv[1] + ".tmp", "w").write("%d %d" % (h.server_address[1], w.server_address[1]))
import os; os.rename(sys.argv[1] + ".tmp", sys.argv[1])
h.serve_forever()
EOF
python3 "$T/stub.py" "$T/ports" & STUB=$!
trap 'kill $STUB 2>/dev/null; wait $STUB 2>/dev/null; rm -rf "$T"' EXIT
for i in $(seq 1 25); do [ -s "$T/ports" ] && break; sleep 0.2; done
read -r HP WP < "$T/ports"
U="http://127.0.0.1:$HP"
export NAME_CHECK_RDAP_BOOTSTRAP="$U/dns.json" NAME_CHECK_WHOIS="127.0.0.1:$WP" \
  NAME_CHECK_GITHUB="$U" NAME_CHECK_NPM="$U" NAME_CHECK_PYPI="$U" NAME_CHECK_PORKBUN="$U"
nc() { python3 "$B/name-check" "$@"; }

echo "one table"
nc freebie Takenco --tlds io,.dev,com > "$T/out" 2>&1; check "$?" "0" "exit 0"
has "$T/out" "| name | .io | .dev | .com | GitHub | npm | PyPI |" "header: TLDs then handles"
has "$T/out" "| freebie | free | free | free | free | free | free |" "free over RDAP, whois and 404"
has "$T/out" "| takenco | taken | taken | taken | taken | taken | taken |" "taken everywhere, name lower-cased"
has "$T/out" "| price: first / renewal / 10 y | \$28.12 / \$51.80 / \$494 | \$8.75 / \$12.87 / \$125 | \$11.08 / \$11.08 / \$111 |" "price row: 10 y = first + 9 renewals"
has "$T/out" ".io whois, .dev RDAP, .com RDAP" "says which probe each TLD used"
has "$T/out" "not a registrar quote" "free is not a quote, said so"
hasnt "$T/out" "\`?\`" "no unknowns, no notes"

echo "what it cannot read is ?, with why"
nc brokenco --tlds io,com > "$T/out2" 2>&1
has "$T/out2" "| brokenco | ? | ? | ? | ? | ? |" "every cell unknown, none guessed free"
has "$T/out2" "- brokenco .com: HTTP 500" "RDAP error named"
has "$T/out2" "- brokenco .io: whois whois.nic.io gave no answer this script reads" "unreadable whois named"
has "$T/out2" "- brokenco GitHub: HTTP 500" "handle error named"

echo "TLDs with no probe or no price"
nc freebie --tlds zz,xyz > "$T/out3" 2>&1
has "$T/out3" "- freebie .zz: no RDAP and no whois server for .zz" "no way to ask is ?, not free"
has "$T/out3" "| free | free | free | free |" "xyz over RDAP"
has "$T/out3" "not at Porkbun" "a TLD Porkbun does not sell"

echo "the traps the review found"
nc ghostco flakyco mixedco --tlds io > "$T/out5" 2>&1
has "$T/out5" "| ghostco | free | free | free | taken |" "PyPI: a release-less project is taken (simple API), not free"
has "$T/out5" "| flakyco | free |" "an empty whois answer is asked once more"
has "$T/out5" "| mixedco | ? |" "a record with free and taken phrases is ?, never free"
has "$T/out5" "- mixedco .io: whois whois.nic.io reads both free and taken" "  and says why"
nc freebie --tlds er,app > "$T/out6" 2>&1
has "$T/out6" "- freebie .er: no RDAP and no whois server for .er" "IANA's empty whois: line is no server, not the next line"
has "$T/out6" ".er none, .app RDAP" "  the footer says none"
has "$T/out6" "price unreadable" "a malformed price entry costs its cell, not the table"

echo "bad input"
nc "bad_name" > /dev/null 2>&1; check "$?" "2" "underscore refused"
nc "trail-" --tlds io > /dev/null 2>&1; check "$?" "2" "trailing hyphen refused"
nc ok --tlds "" > /dev/null 2>&1; check "$?" "2" "empty --tlds refused"

echo "no network at all"
NAME_CHECK_RDAP_BOOTSTRAP="http://127.0.0.1:1/x" NAME_CHECK_WHOIS="127.0.0.1:1" NAME_CHECK_GITHUB="http://127.0.0.1:1" \
  NAME_CHECK_NPM="http://127.0.0.1:1" NAME_CHECK_PYPI="http://127.0.0.1:1" NAME_CHECK_PORKBUN="http://127.0.0.1:1" \
  python3 "$B/name-check" freebie --tlds io > "$T/out4" 2>&1; check "$?" "0" "still exits 0"
has "$T/out4" "| freebie | ? | ? | ? | ? |" "all unknown"
has "$T/out4" "- freebie .io: whois.iana.org:" "a dead whois is named as such, not as a missing server"
has "$T/out4" "no price list" "price says it could not be read"

[ "$fails" = 0 ] && echo "all ok" || { echo "$fails FAILED"; exit 1; }

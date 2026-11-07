#!/usr/bin/env bash
# =============================================================================
#  3x-ui Pro Configs  —  https://github.com/pdnczone/3x-ui-pro-configs
#
#  Adds a professional, censorship-resistant set of configs to an EXISTING
#  3x-ui panel: REALITY (Vision / XHTTP / gRPC), TLS (Vision / XHTTP),
#  Cloudflare CDN (XHTTP / WS / HTTPUpgrade + clean IPs), Hysteria2 with
#  Salamander, post-quantum VLESS with Sudoku, Shadowsocks-2022.
#  FinalMask (fragment / salamander / sudoku) where it helps.
#
#  ADD-ONLY: never deletes or edits your existing inbounds, clients or hosts.
#
#  Install:
#    bash <(curl -Ls https://raw.githubusercontent.com/pdnczone/3x-ui-pro-configs/main/install.sh)
#
#  Non-interactive:
#    bash install.sh --yes --domain my.example.com --cdn cdn.example.com \
#                    --configs all --clean 20 --token <API_TOKEN>
#  Options:
#    --domain D      domain pointing straight to this server (Cloudflare: DNS only / grey)
#    --cdn C         domain proxied by Cloudflare (orange) to this server
#    --configs L     comma list or "all":  rv,rx,rg,tv,tx,ws,hu,hy,pq,ss
#    --clean N       how many Cloudflare clean-IP configs to add (0-30, default 20)
#    --email E       name of the new client (default pro-xxxx)
#    --token T       panel API token (Settings > API Tokens)
#    --ports auto|ask   what to do when a port is busy (default: ask, or auto with --yes)
#    --no-bbr --no-test --yes --dry-run
# =============================================================================
set -euo pipefail
[ "$(id -u)" = "0" ] || { echo "Please run as root (sudo -i)."; exit 1; }
for b in python3 curl openssl ss; do command -v "$b" >/dev/null || { echo "Missing: $b  (apt install -y $b)"; exit 1; }; done
REPO_RAW="https://raw.githubusercontent.com/pdnczone/3x-ui-pro-configs/main"
TMPPY=$(mktemp /tmp/xui-pro.XXXXXX.py)
trap 'rm -f "$TMPPY"' EXIT
cat > "$TMPPY" <<'PYEOF'
import argparse, base64, glob, ipaddress, json, os, re, secrets, shutil, socket, string, subprocess, sys, time
import concurrent.futures as cfut

REPO_RAW = os.environ.get("REPO_RAW", "")
p = argparse.ArgumentParser()
for a in ("--domain", "--cdn", "--configs", "--email", "--token", "--clean", "--ports"):
    p.add_argument(a)
for a in ("--no-bbr", "--no-test", "--yes", "--dry-run"):
    p.add_argument(a, action="store_true")
A = p.parse_args()

G, Y, R, C, B, D, N = "\033[32m", "\033[33m", "\033[31m", "\033[36m", "\033[1m", "\033[2m", "\033[0m"
def info(*a): print(G + "[+]" + N, *a, flush=True)
def warn(*a): print(Y + "[!]" + N, *a, flush=True)
def die(*a): print(R + "[x]" + N, *a, flush=True); sys.exit(1)
def head(t): print(f"\n{B}{C}── {t} {'─' * max(2, 60 - len(t))}{N}")
def sh(cmd, t=60):
    try:
        return subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=t).stdout.strip()
    except Exception:
        return ""
try:
    TTY = open("/dev/tty")
except Exception:
    TTY = None
# answers are read from /dev/tty only; child commands must never eat the user's typed input
_null = os.open(os.devnull, os.O_RDONLY)
os.dup2(_null, 0)
INTERACTIVE = not A.yes and TTY is not None
def ask(q, default=""):
    if not INTERACTIVE:
        return default
    print(f"{B}?{N} {q}" + (f" {D}[{default}]{N}" if default != "" else "") + ": ", end="", flush=True)
    return TTY.readline().strip() or default
def yes(q, default=True):
    return ask(q + (" (Y/n)" if default else " (y/N)"), "y" if default else "n").lower().startswith("y")

print(f"""{B}{C}
   ┌──────────────────────────────────────────────┐
   │   3x-ui Pro Configs  ·  add-only installer   │
   └──────────────────────────────────────────────┘{N}""")

# =========================================================================== panel
head("Panel")
env = {}
if os.path.exists("/etc/x-ui/install-result.env"):
    for l in open("/etc/x-ui/install-result.env"):
        if "=" in l:
            k, v = l.strip().split("=", 1); env[k] = v
raw = re.sub(r"\x1b\[[0-9;]*m", "", sh("x-ui settings 2>/dev/null"))
pport = env.get("XUI_PANEL_PORT") or (re.search(r"port:\s*(\d+)", raw) or [None, None])[1]
base = env.get("XUI_WEB_BASE_PATH") or (re.search(r"webBasePath:\s*(\S+)", raw) or [None, ""])[1]
base = "/" + base.strip("/") if base and base.strip("/") else ""
access = env.get("XUI_ACCESS_URL") or (re.search(r"Access URL:\s*(\S+)", raw) or [None, ""])[1]
if not pport:
    die("3x-ui was not found on this server. Install 3x-ui v3.x first.")
if access.startswith(("http://", "https://")):
    scheme = access.split(":", 1)[0]
else:
    scheme = "https" if re.search(r"Panel is secure with SSL", raw) else "http"
phost = re.sub(r"^https?://\[?([^/\]]+?)\]?(:\d+)?/.*$", r"\1", access) if access else "127.0.0.1"
PANEL = f"{scheme}://{phost}:{pport}{base}"
RESOLVE = ["--resolve", f"{phost}:{pport}:127.0.0.1"] if re.search(r"[a-zA-Z]", phost) else []
if not RESOLVE:
    PANEL = f"{scheme}://127.0.0.1:{pport}{base}"
TOKEN = A.token or env.get("XUI_API_TOKEN", "")
COOKIE = "/tmp/.xui-pro.cookie"
TEMP_TOKEN_ID = None

def api(path, body=None, post=False, timeout=40):
    c = ["curl", "-sk", "-m", str(timeout)] + RESOLVE + ["-H", f"Authorization: Bearer {TOKEN}"]
    if body is not None:
        c += ["-H", "Content-Type: application/json", "-X", "POST", "-d", json.dumps(body)]
    elif post:
        c += ["-X", "POST"]
    out = subprocess.run(c + [PANEL + path], capture_output=True, text=True).stdout
    try:
        return json.loads(out)
    except Exception:
        return {"success": False, "msg": out[:200]}

def login_and_mint_token(u, pw, otp=""):
    global TOKEN, TEMP_TOKEN_ID
    bc = ["curl", "-sk", "-m", "20"] + RESOLVE + ["-c", COOKIE, "-b", COOKIE]
    def csrf():
        try:
            return json.loads(subprocess.run(bc + [PANEL + "/csrf-token"], capture_output=True, text=True).stdout).get("obj", "")
        except Exception:
            return ""
    body = {"username": u, "password": pw}
    if otp:
        body["twoFactorCode"] = otp
    out = subprocess.run(bc + ["-H", f"X-CSRF-Token: {csrf()}", "-H", "Content-Type: application/json", "-X", "POST",
                               "-d", json.dumps(body), PANEL + "/login"], capture_output=True, text=True).stdout
    if '"success":true' not in out.replace(" ", ""):
        die("Panel login failed:", out[:150])
    out = subprocess.run(bc + ["-H", f"X-CSRF-Token: {csrf()}", "-H", "Content-Type: application/json", "-X", "POST",
                               "-d", json.dumps({"name": f"pro-configs-{int(time.time())}"}),
                               PANEL + "/panel/api/setting/apiTokens/create"], capture_output=True, text=True).stdout
    try:
        o = json.loads(out)["obj"]; TOKEN, TEMP_TOKEN_ID = o["token"], o["id"]
    except Exception:
        die("Logged in, but could not create an API token:", out[:150])
    try:
        os.remove(COOKIE)
    except Exception:
        pass

if not TOKEN or not api("/panel/api/inbounds/list").get("success"):
    if not INTERACTIVE:
        die("No working API token. Pass --token (panel > Settings > API Tokens).")
    print(f"  {D}Panel found at {PANEL}{N}")
    t = ask("Panel API token (Settings > API Tokens) — or press Enter to log in with username/password")
    if t:
        TOKEN = t
    else:
        login_and_mint_token(ask("  Panel username"), ask("  Panel password"), ask("  2FA code (Enter if none)"))
if not api("/panel/api/inbounds/list").get("success"):
    die("Cannot talk to the panel API at", PANEL)
for need in ("/panel/api/clients/list", "/panel/api/hosts/list"):
    if not api(need).get("success"):
        die("Your 3x-ui is too old (no Clients/Hosts pages). Update 3x-ui to v3.x and run again.")
status = api("/panel/api/server/status").get("obj") or {}
XVER = (status.get("xray") or {}).get("version", "?")
info(f"panel {status.get('panelVersion', '?')} · xray {XVER} · {PANEL}")
if not XVER.startswith("26"):
    warn("Xray-core is not 26.x — FinalMask, Hysteria2 and Sudoku need it (Panel > Xray > update).")
XRAY = (glob.glob("/usr/local/x-ui/bin/xray-linux-*") or [""])[0]
DB = "/etc/x-ui/x-ui.db"
settings = api("/panel/api/setting/all", post=True).get("obj") or {}

# =========================================================================== server facts
pub = status.get("publicIP") if isinstance(status.get("publicIP"), dict) else {}
PUB4 = (pub or {}).get("ipv4") or sh("curl -4 -s -m6 https://api.ipify.org")
PUB6 = ""
for l in sh("ip -6 addr show scope global").splitlines():
    m = re.search(r"inet6 ([0-9a-f:]+)/\d+ .*scope global", l)
    if m and "temporary" not in l and "deprecated" not in l and not m.group(1).startswith(("fd", "fc")):
        PUB6 = m.group(1); break
if PUB6 and not sh("curl -6 -s -m6 https://api64.ipify.org"):
    PUB6 = ""
CF_NETS = [ipaddress.ip_network(n) for n in (
    "173.245.48.0/20 103.21.244.0/22 103.22.200.0/22 103.31.4.0/22 141.101.64.0/18 108.162.192.0/18 190.93.240.0/20 "
    "188.114.96.0/20 197.234.240.0/22 198.41.128.0/17 162.158.0.0/15 104.16.0.0/13 104.24.0.0/14 172.64.0.0/13 "
    "131.0.72.0/22 2400:cb00::/32 2606:4700::/32 2803:f800::/32 2405:b500::/32 2405:8100::/32 2a06:98c0::/29 "
    "2c0f:f248::/32").split()]
def ips_of(d):
    try:
        return sorted({a[4][0] for a in socket.getaddrinfo(d, None)})
    except Exception:
        return []
is_cf = lambda ip: any(ipaddress.ip_address(ip) in n for n in CF_NETS if ipaddress.ip_address(ip).version == n.version)

def find_cert(d):
    cands = [(settings.get("webCertFile"), settings.get("webKeyFile")), (settings.get("subCertFile"), settings.get("subKeyFile")),
             (f"/root/cert/{d}/fullchain.pem", f"/root/cert/{d}/privkey.pem"),
             (f"/root/.acme.sh/{d}_ecc/fullchain.cer", f"/root/.acme.sh/{d}_ecc/{d}.key"),
             (f"/root/.acme.sh/{d}/fullchain.cer", f"/root/.acme.sh/{d}/{d}.key"),
             (f"/etc/letsencrypt/live/{d}/fullchain.pem", f"/etc/letsencrypt/live/{d}/privkey.pem")]
    for c, k in cands:
        if c and k and os.path.exists(c) and os.path.exists(k):
            names = sh(f"openssl x509 -in '{c}' -noout -ext subjectAltName 2>/dev/null")
            if f"DNS:{d}" in names or f"DNS:*.{d.split('.', 1)[-1]}" in names:
                if sh(f"openssl x509 -in '{c}' -noout -checkend 86400 >/dev/null && echo ok") == "ok":
                    return c, k
    return None, None

def issue_cert(d):
    """Let's Encrypt via acme.sh standalone (needs TCP 80 free and the domain pointing here)."""
    if sh("ss -H -tln 'sport = :80'"):
        warn("Port 80 is busy — cannot issue a certificate automatically."); return None, None
    acme = os.path.expanduser("~/.acme.sh/acme.sh")
    if not os.path.exists(acme):
        sh("curl -s https://get.acme.sh | sh -s email=admin@" + d, 180)
    if not os.path.exists(acme):
        warn("acme.sh could not be installed."); return None, None
    sh(f"{acme} --set-default-ca --server letsencrypt", 60)
    out = sh(f"{acme} --issue -d {d} --standalone --httpport 80 --keylength ec-256 --force", 240)
    os.makedirs(f"/root/cert/{d}", exist_ok=True)
    sh(f"{acme} --install-cert -d {d} --ecc --fullchain-file /root/cert/{d}/fullchain.pem "
       f"--key-file /root/cert/{d}/privkey.pem --reloadcmd 'x-ui restart'", 60)
    if os.path.exists(f"/root/cert/{d}/fullchain.pem"):
        info(f"certificate issued for {d}"); return f"/root/cert/{d}/fullchain.pem", f"/root/cert/{d}/privkey.pem"
    warn("certificate issue failed:", out[-200:]); return None, None

# =========================================================================== 1. domain
head("1/4  Your domain (direct, Cloudflare grey cloud)")
print(f"  {D}Used for TLS configs and Hysteria2. Must point straight to this server ({PUB4}).{N}")
guess = A.domain or settings.get("webDomain") or settings.get("subDomain") or (phost if re.search(r"[a-z]", phost) else "")
if not guess:
    for d in glob.glob("/root/cert/*/fullchain.pem"):
        guess = d.split("/")[3]; break
DOMAIN = (A.domain if A.domain is not None else ask("Domain (Enter = none, only REALITY configs)", guess)).strip().lower()
CERT = KEY = None
if DOMAIN:
    ips = ips_of(DOMAIN)
    if not ips:
        warn(f"{DOMAIN} does not resolve. Fix DNS, then run again."); DOMAIN = ""
    elif any(is_cf(i) for i in ips):
        warn(f"{DOMAIN} is behind Cloudflare (orange). It must be DNS-only (grey) for direct configs.")
        warn("Turn the proxy off for it in Cloudflare, or use it as your CDN domain instead.")
        DOMAIN = ""
    else:
        if PUB4 not in ips and (not PUB6 or PUB6 not in ips):
            warn(f"{DOMAIN} points to {', '.join(ips)}, not to this server ({PUB4}).")
        CERT, KEY = find_cert(DOMAIN)
        if CERT:
            info(f"certificate found: {CERT}")
        elif yes(f"No valid certificate for {DOMAIN}. Issue one now with Let's Encrypt?", True):
            CERT, KEY = issue_cert(DOMAIN)
        if not CERT:
            warn("No certificate — TLS, CDN and Hysteria2 configs will be skipped.")
ADDR = DOMAIN or PUB4

# =========================================================================== 2. CDN domain
CDN = ""
if CERT:
    head("2/4  CDN domain (Cloudflare orange cloud)")
    print(f"  {D}A subdomain proxied by Cloudflare to this server, SSL/TLS mode = Full. Enter = skip CDN.{N}")
    CDN = (A.cdn if A.cdn is not None else ask("CDN domain", "")).strip().lower()
    if CDN:
        ips = ips_of(CDN)
        if not ips:
            warn(f"{CDN} does not resolve — CDN skipped."); CDN = ""
        elif not any(is_cf(i) for i in ips):
            warn(f"{CDN} is not proxied by Cloudflare (orange cloud is off) — CDN skipped."); CDN = ""
        else:
            info(f"{CDN} is behind Cloudflare")

# =========================================================================== 3. configs
CATALOG = [
    # key, name, needs, description
    ("rv", "⚡ Reality Vision", None, "fastest + stealthiest, main config"),
    ("rx", "🌀 Reality XHTTP", None, "REALITY over XHTTP, padding"),
    ("rg", "🔷 Reality gRPC", None, "REALITY over gRPC"),
    ("tv", "🔐 TLS Vision", "tls", "real certificate, + Fragment and IPv6 variants"),
    ("tx", "🛰 TLS XHTTP", "tls", "direct + CDN capable"),
    ("ws", "🌐 CDN WS", "cdn", "Cloudflare WebSocket + clean IPs"),
    ("hu", "🔗 CDN HTTPUpgrade", "cdn", "Cloudflare HTTPUpgrade"),
    ("hy", "🚄 Hysteria2", "tls", "UDP/QUIC, Salamander FinalMask (needs UDP open)"),
    ("pq", "🧬 PQ Sudoku", None, "post-quantum VLESS + Sudoku FinalMask (beta, Xray 26 clients)"),
    ("ss", "🛟 Shadowsocks-2022", None, "simple backup"),
]
avail = [c for c in CATALOG if c[2] is None or (c[2] == "tls" and CERT) or (c[2] == "cdn" and CDN)]
head("3/4  Which configs to add")
for n, (k, name, _, desc) in enumerate(avail, 1):
    print(f"  {B}{n:2d}{N}) {name:22s} {D}{desc}{N}")
skipped = [c[1] for c in CATALOG if c not in avail]
if skipped:
    print(f"  {D}not available (no domain/cert/CDN): {', '.join(skipped)}{N}")
if A.configs:
    sel_keys = [c[0] for c in avail] if A.configs.strip() == "all" else [x.strip() for x in A.configs.split(",")]
else:
    ans = ask("Numbers separated by comma, or 'all'", "all")
    if ans.strip().lower() == "all":
        sel_keys = [c[0] for c in avail]
    else:
        idx = {int(x) for x in re.findall(r"\d+", ans)}
        sel_keys = [avail[i - 1][0] for i in sorted(idx) if 1 <= i <= len(avail)]
SEL = [c for c in avail if c[0] in sel_keys]
if not SEL:
    die("Nothing selected.")
CLEAN_N = 0
if "ws" in sel_keys or "hu" in sel_keys or ("tx" in sel_keys and CDN):
    CLEAN_N = int(A.clean) if A.clean is not None else int(re.sub(r"\D", "", ask(
        "How many Cloudflare clean-IP configs to add (0-30)", "20")) or 0)
    CLEAN_N = max(0, min(30, CLEAN_N))

# =========================================================================== ports
inbs = api("/panel/api/inbounds/list").get("obj") or []
owner_tcp, owner_udp = {}, {}
for ib in inbs:
    st = ib.get("streamSettings")
    st = json.loads(st) if isinstance(st, str) and st else (st or {})
    label = f"inbound '{ib.get('remark') or ib['id']}'"
    if ib["protocol"] in ("hysteria", "wireguard", "amneziawg") or st.get("network") in ("kcp", "hysteria"):
        owner_udp[ib["port"]] = label
    else:
        owner_tcp[ib["port"]] = label
        if ib["protocol"] in ("shadowsocks", "mixed", "socks", "dokodemo-door", "tunnel"):
            owner_udp[ib["port"]] = label
for flag, dct in (("t", owner_tcp), ("u", owner_udp)):
    for l in sh(f"ss -H -{flag}lnp").splitlines():
        f = l.split()
        if len(f) < 5:
            continue
        m = re.search(r":(\d+)$", f[3])
        if m and int(m.group(1)) not in dct:
            pm = re.search(r'\(\("([^"]+)"', l)
            dct[int(m.group(1))] = f"process '{pm.group(1) if pm else '?'}'"
for k in ("subPort", "webPort"):
    if settings.get(k):
        owner_tcp.setdefault(int(settings[k]), "3x-ui panel/subscription")
owner_tcp.setdefault(int(pport), "3x-ui panel")

CF_HTTPS = [443, 2053, 2083, 2087, 2096, 8443]
PREF = {"rv": [443, 2443, 3443, 6443, 7443], "rx": [8443, 2443, 3443, 5443, 6443], "rg": [4443, 5443, 7443, 9444],
        "tv": [9443, 9444, 10444, 11444], "tx": [2087, 2053, 2083, 2096, 8443], "ws": [2053, 2083, 2087, 2096, 8443],
        "hu": [2083, 2053, 2087, 2096, 8443], "hy": [443, 8443, 4443, 2053, 10443], "pq": [10443, 11443, 12443, 13443],
        "ss": [8080, 8388, 18080, 28080]}
UDP_ONLY = {"hy"}
BOTH = {"ss"}
CDN_KEYS = {"tx", "ws", "hu"}
MODE = A.ports or ("auto" if not INTERACTIVE else "ask")

def busy(pt, key):
    t = pt in owner_tcp if key not in UDP_ONLY else False
    u = pt in owner_udp if (key in UDP_ONLY or key in BOTH) else False
    return (owner_tcp.get(pt) if t else None) or (owner_udp.get(pt) if u else None)
def claim(pt, key):
    if key not in UDP_ONLY: owner_tcp[pt] = "new config"
    if key in UDP_ONLY or key in BOTH: owner_udp[pt] = "new config"
def free_from(lst, key):
    for pt in lst:
        if not busy(pt, key):
            return pt
    for pt in range(20000, 60000, 7):
        if not busy(pt, key) and not (key in CDN_KEYS):
            return pt
    return None

head("4/4  Ports")
PLAN = {}
ORIGIN_RULES = []
for key, name, _, _ in SEL:
    want = PREF[key][0]
    who = busy(want, key)
    if not who:
        PLAN[key] = {"port": want, "client_port": 0}; claim(want, key)
        print(f"  {name:22s} port {want}{'/udp' if key in UDP_ONLY else ''}")
        continue
    alt = free_from(PREF[key], key)
    cdn_note = key in CDN_KEYS and (alt is None or alt not in CF_HTTPS)
    print(f"  {Y}{name:22s} port {want} is used by {who}{N}")
    if key in CDN_KEYS and alt in CF_HTTPS:
        hint = f"Enter = use {alt} (a Cloudflare port)"
    elif key in CDN_KEYS:
        hint = "all Cloudflare ports (443 2053 2083 2087 2096 8443) are busy: o = Origin-Rule mode, s = skip"
    else:
        hint = f"Enter = use {alt}"
    if MODE == "auto":
        choice = "" if alt and not cdn_note else "s"
    else:
        print(f"    {D}Two inbounds can never share one port. Options:{N}")
        print(f"    {D}  Enter  use the next free port{'' if not cdn_note else ' (not possible here)'}{N}")
        print(f"    {D}  <num>  type your own port{N}")
        if key in CDN_KEYS:
            print(f"    {D}  o      Origin-Rule mode: clients use Cloudflare port 443, Cloudflare forwards to any free port{N}")
        print(f"    {D}  s      skip this config (your existing inbound stays as it is){N}")
        choice = ask(f"    {hint}", "")
    choice = choice.strip().lower()
    if choice == "s" or (choice == "" and (alt is None or cdn_note)):
        print(f"    → skipped"); continue
    if choice == "o" and key in CDN_KEYS:
        pt = free_from(range(30000, 60000, 11), "x")
        PLAN[key] = {"port": pt, "client_port": 443, "origin_rule": True}; claim(pt, key)
        print(f"    → Origin-Rule mode: server port {pt}, clients use 443"); continue
    if choice.isdigit():
        pt = int(choice)
        if busy(pt, key):
            warn(f"    port {pt} is also busy ({busy(pt, key)}) — skipped"); continue
        if key in CDN_KEYS and pt not in CF_HTTPS:
            warn("    Cloudflare only proxies 443 2053 2083 2087 2096 8443 — using Origin-Rule mode for this port")
            PLAN[key] = {"port": pt, "client_port": 443, "origin_rule": True}
        else:
            PLAN[key] = {"port": pt, "client_port": 0}
        claim(pt, key); print(f"    → port {pt}"); continue
    PLAN[key] = {"port": alt, "client_port": 0}; claim(alt, key)
    print(f"    → port {alt}")
if not PLAN:
    die("Nothing left to add.")

# =========================================================================== REALITY targets + clean IPs
def tls13_h2(sni):
    out = sh(f"echo | timeout 6 openssl s_client -connect {sni}:443 -servername {sni} -alpn h2 -tls1_3 2>/dev/null", 10)
    return "TLSv1.3" in out and "ALPN protocol: h2" in out
SNI_POOL = ["dl.google.com", "addons.mozilla.org", "www.samsung.com", "www.nvidia.com", "www.speedtest.net",
            "www.amd.com", "www.asus.com", "www.lovelive-anime.jp"]
if any(k in PLAN for k in ("rv", "rx", "rg")):
    with cfut.ThreadPoolExecutor(8) as ex:
        okmap = dict(zip(SNI_POOL, ex.map(tls13_h2, SNI_POOL)))
    GOOD_SNI = [s for s in SNI_POOL if okmap[s]] or SNI_POOL
else:
    GOOD_SNI = SNI_POOL
sni = lambda i: GOOD_SNI[i % len(GOOD_SNI)]

CLEAN = []
if CLEAN_N and CDN:
    lst = sh(f"curl -fsSL -m10 {REPO_RAW}/clean-ips.txt") if REPO_RAW else ""
    cand = [l.split("#")[0].strip() for l in lst.splitlines() if l.split("#")[0].strip()]
    if not cand:
        cand = __FALLBACK_CLEAN__
    cdn_port = next((PLAN[k]["port"] for k in ("ws", "hu", "tx") if k in PLAN and not PLAN[k].get("origin_rule")), None)
    if not cdn_port and any(PLAN.get(k, {}).get("origin_rule") for k in ("ws", "hu", "tx")):
        cdn_port = 443          # Origin-Rule mode: clients reach Cloudflare on 443
    if cdn_port:
        def via_cf(a):
            ip = a if re.match(r"^[\d.]+$", a) else (next((x for x in ips_of(a) if ":" not in x), "") or "")
            if not ip or not is_cf(ip):
                return None
            r = sh(f"curl -s -o /dev/null -m6 -w '%{{http_code}} %{{time_connect}}' --resolve {CDN}:{cdn_port}:{ip} "
                   f"https://{CDN}:{cdn_port}/", 10)
            code, _, t = r.partition(" ")
            return (a, float(t or 9)) if code and code != "000" else None
        info(f"checking {len(cand)} Cloudflare clean IPs / domains against {CDN} ...")
        with cfut.ThreadPoolExecutor(16) as ex:
            res = [r for r in ex.map(via_cf, cand) if r]
        CLEAN = [a for a, _ in res][:CLEAN_N]
        info(f"{len(CLEAN)} clean addresses ready")

# =========================================================================== summary + confirm
head("Plan")
print(f"  address {ADDR}" + (f" · IPv6 {PUB6}" if PUB6 else "") + (f" · CDN {CDN}" if CDN else ""))
for key, name, _, _ in SEL:
    if key in PLAN:
        pl = PLAN[key]
        print(f"  {G}+{N} {name:22s} port {pl['port']}{'/udp' if key in UDP_ONLY else ''}"
              + (f"  (Origin Rule → clients use 443)" if pl.get("origin_rule") else ""))
if CLEAN:
    print(f"  {G}+{N} {len(CLEAN)} clean-IP CDN configs")
print(f"  {D}existing inbounds kept untouched: {len(inbs)}{N}")
if A.dry_run:
    info("Dry run — nothing changed."); sys.exit(0)
if not yes("Start?", True):
    sys.exit(0)

# =========================================================================== builders
hx = secrets.token_hex
def x25519():
    d = {}
    for l in sh(f"{XRAY} x25519").splitlines():
        k, _, v = l.partition(":"); d[k.strip()] = v.strip()
    return d.get("PrivateKey") or d.get("Private key"), \
        d.get("Password (PublicKey)") or d.get("Password") or d.get("PublicKey") or d.get("Public key")
def vlessenc():
    out = sh(f"{XRAY} vlessenc").splitlines()
    for n, l in enumerate(out):
        if "X25519" in l and n + 2 < len(out):
            return out[n + 1].split('"')[3], out[n + 2].split('"')[3]
    raise RuntimeError("this Xray has no 'vlessenc' (update Xray-core)")
def reality(network, target, extra):
    priv, pub = x25519()
    s = {"network": network, "security": "reality", "externalProxy": [],
         "realitySettings": {"show": False, "xver": 0, "target": f"{target}:443", "serverNames": [target],
                             "privateKey": priv, "minClientVer": "", "maxClientVer": "", "maxTimediff": 0,
                             "shortIds": [hx(4), hx(8)],
                             "settings": {"publicKey": pub, "fingerprint": "chrome", "serverName": "", "spiderX": "/"}}}
    s.update(extra); return s
def tls(alpn):
    return {"serverName": DOMAIN, "minVersion": "1.2", "maxVersion": "1.3", "cipherSuites": "", "rejectUnknownSni": False,
            "disableSystemRoot": False, "enableSessionResumption": False,
            "certificates": [{"certificateFile": CERT, "keyFile": KEY, "oneTimeLoading": False, "usage": "encipherment",
                              "buildChain": False}],
            "alpn": alpn, "settings": {"fingerprint": "chrome", "echConfigList": ""}}
def tls_stream(network, extra, alpn):
    s = {"network": network, "security": "tls", "externalProxy": [], "tlsSettings": tls(alpn)}; s.update(extra); return s
TCP = {"tcpSettings": {"acceptProxyProtocol": False, "header": {"type": "none"}}}
XH = lambda: {"path": "/" + hx(5), "host": "", "mode": "auto", "xPaddingBytes": "100-1000",
              "noSSEHeader": False, "scMaxEachPostBytes": "1000000", "scMaxBufferedPosts": 30}
VL = lambda: {"clients": [], "decryption": "none", "fallbacks": []}
FRAG = json.dumps({"tcp": [{"type": "fragment", "settings": {"packets": "tlshello", "lengths": ["10-30"], "delays": ["5-15"]}}]})
SNIFF = {"enabled": True, "destOverride": ["http", "tls", "quic"], "metadataOnly": False, "routeOnly": True}
PATHS = {}
def ws_stream():
    PATHS["ws"] = "/" + hx(5)
    return tls_stream("ws", {"wsSettings": {"acceptProxyProtocol": False, "path": PATHS["ws"], "host": "", "headers": {},
                                            "heartbeatPeriod": 30}}, ["http/1.1"])
def hu_stream():
    PATHS["hu"] = "/" + hx(5)
    return tls_stream("httpupgrade", {"httpupgradeSettings": {"acceptProxyProtocol": False, "path": PATHS["hu"], "host": "",
                                                              "headers": {}}}, ["http/1.1"])
def tx_stream():
    x = XH(); PATHS["tx"] = x["path"]
    return tls_stream("xhttp", {"xhttpSettings": x}, ["h2", "http/1.1"])
def pq():
    dec, enc = vlessenc()
    return ({"clients": [], "decryption": dec, "encryption": enc},
            {"network": "tcp", "security": "none", "externalProxy": [], **TCP,
             "finalmask": {"tcp": [{"type": "sudoku", "settings": {"password": hx(16), "ascii": "prefer_entropy",
                                                                    "paddingMin": 2, "paddingMax": 7}}]}})
BUILD = {
    "rv": ("vless", lambda: (VL(), reality("tcp", sni(0), TCP))),
    "rx": ("vless", lambda: (VL(), reality("xhttp", sni(1), {"xhttpSettings": XH()}))),
    "rg": ("vless", lambda: (VL(), reality("grpc", sni(2), {"grpcSettings": {"serviceName": hx(4), "authority": "",
                                                                             "multiMode": True}}))),
    "tv": ("vless", lambda: (VL(), tls_stream("tcp", TCP, ["h2", "http/1.1"]))),
    "tx": ("vless", lambda: (VL(), tx_stream())),
    "ws": ("vless", lambda: (VL(), ws_stream())),
    "hu": ("vless", lambda: (VL(), hu_stream())),
    "hy": ("hysteria", lambda: ({"version": 2, "clients": []},
                                {"network": "hysteria", "security": "tls", "externalProxy": [], "tlsSettings": tls(["h3"]),
                                 "hysteriaSettings": {"version": 2, "udpIdleTimeout": 60,
                                                      "masquerade": {"type": "proxy", "url": "https://www.bing.com",
                                                                     "rewriteHost": True}},
                                 "finalmask": {"udp": [{"type": "salamander", "settings": {"password": hx(16)}}],
                                               "quicParams": {"congestion": "bbr"}}})),
    "pq": ("vless", pq),
    "ss": ("shadowsocks", lambda: ({"method": "2022-blake3-aes-256-gcm", "password": base64.b64encode(secrets.token_bytes(32)).decode(),
                                    "network": "tcp,udp", "clients": [], "ivCheck": False},
                                   {"network": "tcp", "security": "none", "externalProxy": [], **TCP})),
}
REMARK = {"rv": "⚡ Reality Vision", "rx": "🌀 Reality XHTTP", "rg": "🔷 Reality gRPC", "tv": "🔐 TLS Vision",
          "tx": "🛰 TLS XHTTP", "ws": "🌐 TLS WS", "hu": "🔗 TLS HTTPUpgrade", "hy": "🚄 Hysteria2 · UDP",
          "pq": "🧬 PQ Sudoku · Beta", "ss": "🛟 Shadowsocks · Backup"}
def cdn_host(name, addr, key):
    cp = PLAN[key].get("client_port", 0)
    return (name, addr, {"sni": CDN, "hostHeader": CDN, "finalMask": FRAG, **({"port": cp} if cp else {})})
def HOSTS(key):
    v6 = lambda n, ex={}: [(f"6️⃣ {n} · IPv6", PUB6, ex)] if PUB6 else []
    if key == "rv": return [("⚡ Reality Vision · Main", ADDR, {})] + v6("Reality Vision")
    if key == "rx": return [("🌀 Reality XHTTP", ADDR, {})] + v6("Reality XHTTP")
    if key == "rg": return [("🔷 Reality gRPC", ADDR, {})]
    if key == "tv": return [("🔐 TLS Vision", ADDR, {"sni": DOMAIN}),
                            ("🧩 TLS Vision · Fragment", ADDR, {"sni": DOMAIN, "finalMask": FRAG})] + v6("TLS Vision", {"sni": DOMAIN})
    if key == "tx":
        h = [] if PLAN["tx"].get("origin_rule") else [("🛰 TLS XHTTP", ADDR, {"sni": DOMAIN, "hostHeader": DOMAIN})]
        return h + ([cdn_host("☁️ CDN XHTTP · Fragment", CDN, "tx")] if CDN else [])
    if key == "ws": return [cdn_host("☁️ CDN WS · Fragment", CDN, "ws")]
    if key == "hu": return [cdn_host("☁️ CDN HTTPUpgrade · Fragment", CDN, "hu")]
    if key == "hy": return [("🚄 Hysteria2 · UDP", ADDR, {"sni": DOMAIN})]
    if key == "pq": return [("🧬 PQ Sudoku · Beta", ADDR, {})]
    if key == "ss": return [("🛟 Shadowsocks · Backup", ADDR, {})]
    return []

# =========================================================================== apply
head("Adding")
bak = f"{DB}.bak-pro-{int(time.time())}"
if os.path.exists(DB):
    shutil.copy(DB, bak); info("database backup:", bak)
emails = {c.get("email") for c in (api("/panel/api/clients/list").get("obj") or [])}
EMAIL = A.email or f"pro-{hx(2)}"
while EMAIL in emails:
    EMAIL = f"{EMAIL}-{hx(1)}"
SUBID = "".join(secrets.choice(string.ascii_lowercase + string.digits) for _ in range(16))
CLIENT = {"email": EMAIL, "subId": SUBID, "flow": "xtls-rprx-vision",
          "password": base64.b64encode(secrets.token_bytes(32)).decode(),   # also a valid SS-2022 key
          "totalGB": 0, "expiryTime": 0, "limitIp": 0, "limitHwid": 0, "enable": True, "tgId": 0, "comment": "3x-ui-pro-configs"}
def restart():
    api("/panel/api/server/restartXrayService", post=True)
def xray_ok(pt, udp):
    for _ in range(10):
        time.sleep(1.5)
        if ((api("/panel/api/server/status").get("obj") or {}).get("xray") or {}).get("state") == "running":
            if "xray" in sh(f"ss -H -{'u' if udp else 't'}lnp 'sport = :{pt}'"):
                return True
    return False

added, made_client = [], False
for key, name, _, _ in SEL:
    if key not in PLAN:
        continue
    pt = PLAN[key]["port"]; proto, build = BUILD[key]
    try:
        st, stream = build()
    except Exception as e:
        warn(f"{name}: {e} — skipped"); continue
    r = api("/panel/api/inbounds/add", {"up": 0, "down": 0, "total": 0, "remark": REMARK[key], "enable": True, "expiryTime": 0,
                                        "listen": "", "port": pt, "protocol": proto, "settings": st,
                                        "streamSettings": stream, "sniffing": SNIFF})
    iid = (r.get("obj") or {}).get("id")
    if not r.get("success") or not iid:
        warn(f"{name}: panel refused ({r.get('msg')}) — skipped"); continue
    if not made_client:
        cr = api("/panel/api/clients/add", {"client": CLIENT, "inboundIds": [iid]})
        made_client = bool(cr.get("success"))
        if not made_client:
            api(f"/panel/api/inbounds/del/{iid}", post=True); die("could not create client:", cr.get("msg"))
    else:
        api(f"/panel/api/clients/{EMAIL}/attach", {"inboundIds": [iid]})
    restart()
    if xray_ok(pt, key in UDP_ONLY):
        added.append((key, iid)); info(f"added {name:22s} port {pt}")
    else:
        warn(f"{name}: Xray on this server rejected it — removed again")
        api(f"/panel/api/clients/{EMAIL}/detach", {"inboundIds": [iid]})
        api(f"/panel/api/inbounds/del/{iid}", post=True); restart(); time.sleep(3)
if not added:
    die("Nothing could be added.")
ADDED = dict(added)

# naming: every link gets its own name through Hosts + remarkTemplate {{HOST}}
settings = api("/panel/api/setting/all", post=True).get("obj") or settings
tmpl = settings.get("remarkTemplate", "")
use_hosts = "{{HOST}}" in tmpl or not inbs
if not use_hosts:
    print()
    warn(f"Link names: the panel setting 'remarkTemplate' is '{tmpl}'.")
    warn("Setting it to {{HOST}} gives every new link its own clear name (IPv6 / Fragment / CDN / clean IP).")
    warn("It only changes how link NAMES are shown; nothing is deleted.")
    use_hosts = yes("Set remarkTemplate to {{HOST}}?", True)
chg = False
if use_hosts and "{{HOST}}" not in tmpl:
    settings["remarkTemplate"] = "{{HOST}}"; chg = True
if not settings.get("subJsonEnable"):
    settings["subJsonEnable"] = True; chg = True
if chg:
    info("panel settings:", api("/panel/api/setting/update", settings).get("msg"))

clean_key = next((k for k in ("ws", "hu", "tx") if k in ADDED and not PLAN[k].get("origin_rule")), None) \
    or next((k for k in ("ws", "hu", "tx") if k in ADDED), None)
n_links = 0
for order, (key, iid) in enumerate(added):
    api(f"/panel/api/inbounds/{iid}/subSortIndex", {"subSortIndex": 100 + order})
    hosts = HOSTS(key)
    if key == clean_key and CLEAN:
        tag = {"ws": "WS", "hu": "HU", "tx": "XHTTP"}[key]
        hosts += [cdn_host(f"🧊 Clean {i:02d} · {a}", a, key) for i, a in enumerate(CLEAN, 1)]
    if not use_hosts:
        hosts = [h for h in hosts if h[1] == CDN or h[1] in CLEAN] if key in ("ws", "hu") else []
    for i, (rem, addr, extra) in enumerate(hosts):
        if not addr:
            continue
        r = api("/panel/api/hosts/add", {"inboundIds": [iid], "remark": rem, "hosts": [addr], "port": 0,
                                         "security": "same", "sortOrder": i, **extra})
        n_links += bool(r.get("success"))
        if not r.get("success"):
            warn(f"host {rem}: {r.get('msg')}")

# firewall + BBR
ufw = sh("ufw status 2>/dev/null | head -1")
if "Status: active" in ufw:
    for key, _ in added:
        pt = PLAN[key]["port"]
        if key not in UDP_ONLY: sh(f"ufw allow {pt}/tcp")
        if key in UDP_ONLY or key in BOTH: sh(f"ufw allow {pt}/udp")
    info("ufw: ports opened")
if not A.no_bbr and "bbr" not in sh("sysctl -n net.ipv4.tcp_congestion_control"):
    if yes("Enable BBR (faster TCP)?", True):
        open("/etc/sysctl.d/99-bbr.conf", "w").write("net.core.default_qdisc=fq\nnet.ipv4.tcp_congestion_control=bbr\n")
        sh("modprobe tcp_bbr; sysctl --system")
        info("BBR:", sh("sysctl -n net.ipv4.tcp_congestion_control"))
info("restarting panel ...")
api("/panel/api/setting/restartPanel", post=True); time.sleep(8); restart(); time.sleep(4)

# subscription
settings = api("/panel/api/setting/all", post=True).get("obj") or settings
sport = settings.get("subPort", 2096)
sscheme = "https" if settings.get("subCertFile") else "http"
shost = settings.get("subDomain") or DOMAIN or PUB4
SUB = f"{sscheme}://{shost}:{sport}{settings.get('subPath', '/sub/')}{SUBID}"
JSUB = f"{sscheme}://{shost}:{sport}{settings.get('subJsonPath', '/json/')}{SUBID}"
sres = ["--resolve", f"{shost}:{sport}:127.0.0.1"] if re.search(r"[a-z]", shost) else []

# =========================================================================== test
passed = total = 0
if not A.no_test and XRAY:
    head("Testing every config (client → this server → internet)")
    try:
        subs = json.loads(subprocess.run(["curl", "-sk", "-m", "20"] + sres + [JSUB if sres else JSUB.replace(shost, "127.0.0.1")],
                                         capture_output=True, text=True).stdout)
        subs = subs if isinstance(subs, list) else [subs]
    except Exception:
        subs = []; warn("could not read the JSON subscription")
    ins, outs, rules, meta = [], [], [], []
    for n, cfg in enumerate(subs):
        o = next((x for x in cfg.get("outbounds", []) if x.get("tag") == "proxy"), None)
        if not o:
            continue
        s = o.get("settings", {})
        via_cdn = (o.get("streamSettings", {}).get("tlsSettings") or {}).get("serverName") == CDN and CDN
        def fix(a):
            if via_cdn: return a                                    # really go through Cloudflare
            return "::1" if PUB6 and a == PUB6 else "127.0.0.1"
        for k in ("vnext", "servers"):
            for srv in s.get(k, []) or []: srv["address"] = fix(srv.get("address"))
        if "address" in s: s["address"] = fix(s["address"])
        o["tag"] = f"p{n}"; outs.append(o)
        ins.append({"tag": f"s{n}", "listen": "127.0.0.1", "port": 23000 + n, "protocol": "socks", "settings": {"udp": True}})
        rules.append({"type": "field", "inboundTag": [f"s{n}"], "outboundTag": f"p{n}"})
        meta.append((cfg.get("remarks", f"#{n}"), 23000 + n))
    if outs:
        json.dump({"log": {"loglevel": "none"}, "inbounds": ins, "outbounds": outs + [{"protocol": "freedom", "tag": "d"}],
                   "routing": {"rules": rules}}, open("/tmp/.xui-pro-e2e.json", "w"))
        pr = subprocess.Popen([XRAY, "run", "-c", "/tmp/.xui-pro-e2e.json"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        time.sleep(3)
        def probe(m):
            name, pt = m
            for _ in range(2):
                if sh(f"curl -s -o /dev/null -m 15 -w '%{{http_code}}' --socks5-hostname 127.0.0.1:{pt} "
                      "https://www.google.com/generate_204", 20) == "204":
                    return name, True
            return name, False
        try:
            with cfut.ThreadPoolExecutor(6) as ex:
                for name, ok in ex.map(probe, meta):
                    total += 1; passed += ok
                    print(f"  {G + 'OK  ' + N if ok else R + 'FAIL' + N} {name}")
        finally:
            pr.terminate()
            try: os.remove("/tmp/.xui-pro-e2e.json")
            except Exception: pass
        info(f"{passed}/{total} configs work")

# =========================================================================== done
head("Done")
print(f"  client       {B}{EMAIL}{N}   ({len(added)} inbounds, {n_links} links — {len(inbs)} existing inbounds untouched)")
print(f"  subscription {B}{SUB}{N}")
print(f"  JSON sub     {B}{JSUB}{N}  {D}(use this one for FinalMask configs){N}")
ports_txt = ", ".join(f"{PLAN[k]['port']}/{'udp' if k in UDP_ONLY else ('tcp+udp' if k in BOTH else 'tcp')}" for k, _ in added)
print(f"\n  Open in your cloud firewall (IPv4 + IPv6): {ports_txt}")
if CDN:
    print(f"  Cloudflare: {CDN} = proxied (orange) · {DOMAIN} = DNS only (grey) · SSL/TLS = Full")
rules_needed = [(k, PLAN[k]["port"]) for k, _ in added if PLAN[k].get("origin_rule")]
if rules_needed:
    print(f"\n  {Y}Cloudflare Origin Rules needed{N} (Rules > Origin Rules > Create):")
    for k, pt in rules_needed:
        print(f"    if Hostname = {CDN} AND URI Path starts with {PATHS.get(k, '/')}  →  Destination port = {pt}")
print(f"\n  backup: {bak}\n")
if TEMP_TOKEN_ID is not None:
    api(f"/panel/api/setting/apiTokens/delete/{TEMP_TOKEN_ID}", post=True)
PYEOF

FALLBACK='time.is creativecommons.org www.digitalocean.com www.canva.com www.npmjs.com www.udemy.com cdnjs.com
172.67.153.64 141.101.120.172 104.19.214.18 104.16.165.243 188.114.98.19 172.66.160.120 190.93.246.88 188.114.99.132
104.17.24.19 104.21.114.162 104.24.68.75 188.114.97.156 162.159.140.108 141.101.121.20 104.21.63.243 188.114.97.251
104.27.49.141 190.93.244.210 104.25.60.147 104.16.77.102 188.114.96.74 104.27.96.96 104.18.29.233 104.19.44.112'
python3 - "$TMPPY" "$FALLBACK" <<'FIX'
import sys
p, fb = sys.argv[1], sys.argv[2]
s = open(p).read().replace("__FALLBACK_CLEAN__", repr([x for x in fb.split() if x]))
open(p, "w").write(s)
FIX
REPO_RAW="$REPO_RAW" python3 -I "$TMPPY" "$@"

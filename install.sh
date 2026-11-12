#!/usr/bin/env bash
# =============================================================================
#  3x-ui Pro Configs + Proxy Scanner  (3x-ui / Marzban)
#  Repo: https://github.com/AyhanMansur/AyhanX-Direct
# =============================================================================
set -euo pipefail
[ "$(id -u)" = "0" ] || { echo "Please run as root (sudo -i)."; exit 1; }

PKG=""; PKG_NAME=""
if   command -v apt-get >/dev/null; then PKG="apt-get install -y"; PKG_NAME="apt"
elif command -v apt     >/dev/null; then PKG="apt install -y";     PKG_NAME="apt"
elif command -v dnf     >/dev/null; then PKG="dnf install -y";     PKG_NAME="dnf"
elif command -v yum     >/dev/null; then PKG="yum install -y";     PKG_NAME="yum"
elif command -v apk     >/dev/null; then PKG="apk add --no-cache"; PKG_NAME="apk"
elif command -v pacman  >/dev/null; then PKG="pacman -S --noconfirm"; PKG_NAME="pacman"
fi
need() {
    local bin="$1" pkg="${2:-$1}"
    if ! command -v "$bin" >/dev/null 2>&1; then
        if [ -n "$PKG" ]; then
            echo "[!] installing $pkg via $PKG_NAME …"
            $PKG "$pkg" >/dev/null 2>&1 || true
        fi
        command -v "$bin" >/dev/null 2>&1 || { echo "[x] missing $bin ($pkg) — install it and retry"; exit 1; }
    fi
}
need python3 python3
need curl    curl
need openssl openssl
need ss      iproute2
if ! command -v pipx >/dev/null 2>&1 && [ -n "$PKG" ]; then
    echo "[!] installing pipx via $PKG_NAME …"
    $PKG pipx >/dev/null 2>&1 || true
fi
if { [ -n "${DISPLAY:-}" ] || [ -n "${WAYLAND_DISPLAY:-}" ]; } \
   && ! command -v xclip >/dev/null 2>&1 \
   && command -v apt-get >/dev/null 2>&1; then
    echo "[!] installing xclip via apt …"
    apt-get install -y xclip >/dev/null 2>&1 || true
fi

REPO_RAW="https://raw.githubusercontent.com/pdnczone/3x-ui-pro-configs/main"
USER_REPO="https://github.com/AyhanMansur/AyhanX-Direct"
TMPPY=$(mktemp /tmp/xui-pro.XXXXXX.py)
trap 'rm -f "$TMPPY"' EXIT
cat > "$TMPPY" <<'PYEOF'
# ═══════════════════════════════════════════════════════════════════════════
#  IMPORTS
# ═══════════════════════════════════════════════════════════════════════════
import argparse, base64, glob, ipaddress, json, os, re, secrets, shutil
import socket, string, subprocess, sys, time, platform, uuid, urllib.parse, random
import concurrent.futures as cfut
from ipaddress import ip_network

G, Y, R, C, B, D, N = ("\033[32m","\033[33m","\033[31m","\033[36m",
                        "\033[1m","\033[2m","\033[0m")
OKGREEN, WARNING, FAIL, ENDC = G, Y, R, N
LITBU, YELLOW, CYAN, PURPLE, BOLD = "\033[94m","\033[93m","\033[96m","\033[95m",B
colors = [OKGREEN, LITBU, CYAN, PURPLE]
RAND_COLOR = random.choice(colors)

def info(*a): print(G + "[+]" + N, *a, flush=True)
def warn(*a): print(Y + "[!]" + N, *a, flush=True)
def die(*a): print(R + "[x]" + N, *a, flush=True); sys.exit(1)
def head(t): print(f"\n{B}{C}── {t} {'─' * max(2, 60 - len(t))}{N}")
def sh(cmd, t=60):
    try:
        return subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=t).stdout.strip()
    except Exception:
        return ""

def clear_screen():
    if not sys.stdout.isatty(): return
    if shutil.which("clear"): subprocess.run(["clear"], check=False)
    else: print("\033[2J\033[H", end="", flush=True)

BANNER = r"""
  ▄▄▄     ▓██   ██▓ ██░ ██  ▄▄▄       ███▄    █ ▒██   ██▒▓█████▄  ██▓ ██▀███  ▓█████  ▄████▄  ▄▄▄█████▓
▒████▄    ▒██  ██▒▓██░ ██▒▒████▄     ██ ▀█   █ ▒▒ █ █ ▒░▒██▀ ██▌▓██▒▓██ ▒ ██▒▓█   ▀ ▒██▀ ▀█  ▓  ██▒ ▓▒
▒██  ▀█▄   ▒██ ██░▒██▀▀██░▒██  ▀█▄  ▓██  ▀█ ██▒░░  █   ░░██   █▌▒██▒▓██ ░▄█ ▒▒███   ▒▓█    ▄ ▒ ▓██░ ▒░
░██▄▄▄▄██  ░ ▐██▓░░▓█ ░██ ░██▄▄▄▄██ ▓██▒  ▐▌██▒ ░ █ █ ▒ ░▓█▄   ▌░██░▒██▀▀█▄  ▒▓█  ▄ ▒▓▓▄ ▄██▒░ ▓██▓ ░ 
 ▓█   ▓██▒ ░ ██▒▓░░▓█▒░██▓ ▓█   ▓██▒▒██░   ▓██░▒██▒ ▒██▒░▒████▓ ░██░░██▓ ▒██▒░▒████▒▒ ▓███▀ ░  ▒██▒ ░ 
 ▒▒   ▓▒█░  ██▒▒▒  ▒ ░░▒░▒ ▒▒   ▓▒█░░ ▒░   ▒ ▒ ▒▒ ░ ░▓ ░ ▒▒▓  ▒ ░▓  ░ ▒▓ ░▒▓░░░ ▒░ ░░ ░▒ ▒  ░  ▒ ░░   
  ▒   ▒▒ ░▓██ ░▒░  ▒ ░▒░ ░  ▒   ▒▒ ░░ ░░   ░ ▒░░░   ░▒ ░ ░ ▒  ▒  ▒ ░  ░▒ ░ ▒░ ░ ░  ░  ░  ▒       ░    
  ░   ▒   ▒ ▒ ░░   ░  ░░ ░  ░   ▒      ░   ░ ░  ░    ░   ░ ░  ░  ▒ ░  ░░   ░    ░   ░          ░      
      ░  ░░ ░      ░  ░  ░      ░  ░         ░  ░    ░     ░     ░     ░        ░  ░░ ░               
          ░ ░                                            ░                          ░
"""
USER_REPO  = "https://github.com/AyhanMansur/AyhanX-Direct"
BRAND      = "🧩👾𝐀𝐲𝐡𝐚𝐧𝐗-𝐃𝐢𝐫𝐞𝐜𝐭-"
PRO_TITLE  = f"{B}{C}3x-ui Pro Configs  ·  add-only installer{N}"
SCAN_TITLE = f"{B}{C}Proxy Scanner  ·  range / domain → link builder{N}"

# ═══════════════════════════════════════════════════════════════════════════
#  CLI
# ═══════════════════════════════════════════════════════════════════════════
REPO_RAW = os.environ.get("REPO_RAW", "")
p = argparse.ArgumentParser()
for a in ("--domain","--cdn","--configs","--email","--token","--api-key","--clean","--ports",
          "--scan-limit","--panel","--panel-url","--panel-user","--panel-pass"):
    p.add_argument(a)
for a in ("--no-bbr","--no-test","--yes","--dry-run","--scan","--install","--no-scan"):
    p.add_argument(a, action="store_true")
A = p.parse_args()

try:    TTY = open("/dev/tty")
except Exception: TTY = None
_null = os.open(os.devnull, os.O_RDONLY)
os.dup2(_null, 0)
INTERACTIVE = not A.yes and TTY is not None
def ask(q, default=""):
    if not INTERACTIVE: return default
    print(f"{B}?{N} {q}" + (f" {D}[{default}]{N}" if default != "" else "") + ": ", end="", flush=True)
    return TTY.readline().strip() or default
def yes(q, default=True):
    return ask(q + (" (Y/n)" if default else " (y/N)"), "y" if default else "n").lower().startswith("y")

# ═══════════════════════════════════════════════════════════════════════════
#  SCANNER + SELF-BOOTSTRAP
# ═══════════════════════════════════════════════════════════════════════════
def _pipx_has(mod):
    try: return subprocess.run(["pipx","runpip",mod,"show",mod],
                                capture_output=True, text=True, timeout=30).returncode == 0
    except Exception: return False
def _pipx_install(mod):
    try: return subprocess.run(["pipx","install",mod],
                                capture_output=True, text=True, timeout=300).returncode == 0
    except Exception: return False
def ensure_requests():
    try:
        import requests  # noqa: F401
        return True
    except ImportError:
        pass
    def try_import_after():
        import importlib
        for q in list(sys.path):
            if os.path.isdir(q): importlib.invalidate_caches()
        try:
            import requests  # noqa: F401
            return True
        except ImportError: return False
    def add_pipx_venv_to_path(mod="requests"):
        home = os.path.expanduser("~")
        cands  = glob.glob(f"{home}/.local/pipx/venvs/{mod}/lib/python*/site-packages")
        cands += glob.glob(f"/root/.local/pipx/venvs/{mod}/lib/python*/site-packages")
        cands += glob.glob(f"/usr/local/pipx/venvs/{mod}/lib/python*/site-packages")
        if not cands and shutil.which("pipx"):
            try:
                out = subprocess.run(["pipx","environment","--value","PIPX_LOCAL_VENVS"],
                                     capture_output=True, text=True, timeout=30).stdout.strip()
                if out: cands = glob.glob(f"{out}/{mod}/lib/python*/site-packages")
            except Exception: pass
        if cands:
            sys.path.insert(0, sorted(cands)[-1]); return True
        return False
    pipx = shutil.which("pipx")
    if pipx:
        if not _pipx_has("requests") and not _pipx_install("requests"): pass
        if add_pipx_venv_to_path("requests") and try_import_after(): return True
    for cmd in (["pip","install","--user","requests"],
                [sys.executable,"-m","pip","install","--user","requests"]):
        try:
            if subprocess.run(cmd, capture_output=True, text=True, timeout=180).returncode == 0:
                for q in glob.glob(os.path.expanduser("~/.local/lib/python*/site-packages")):
                    if q not in sys.path: sys.path.append(q)
                if try_import_after(): return True
        except Exception: pass
    for extra in ([], ["--break-system-packages"]):
        try:
            cmd = [sys.executable,"-m","pip","install"] + extra + ["requests"]
            if subprocess.run(cmd, capture_output=True, text=True, timeout=180).returncode == 0 \
               and try_import_after(): return True
        except Exception: pass
    print(f"{R}  ✘{N} could not auto-install {CY}requests{N} — falling back to curl")
    return False

def scan_host(host):
    param = '-n' if sys.platform.startswith('win') else '-c'
    try: return subprocess.run(['ping',param,'1',host], capture_output=True, text=True, timeout=2).returncode == 0
    except Exception: return False
def scan_network(network_str, limit=None):
    try:
        n = ip_network(network_str, strict=False)
        addrs = list(n.hosts())
        if limit is not None: addrs = addrs[:limit]
        print(f"{random.choice(colors)}🔍 Scanning {'IPv6' if n.version==6 else 'IPv4'} {network_str} ({len(addrs)})...{ENDC}")
        a = []
        for ip in addrs:
            if scan_host(str(ip)): a.append(str(ip)); print(f"{OKGREEN}   ✅ {ip}{ENDC}")
        return a, len(addrs)
    except Exception as e:
        print(f"{FAIL}❌ {network_str}: {e}{ENDC}"); return [], 0
def scan_domains(dl, limit=None):
    if limit is not None: dl = dl[:limit]
    print(f"{random.choice(colors)}🔍 Scanning {len(dl)} domains...{ENDC}")
    a = []
    for d in dl:
        if scan_host(d): a.append(d); print(f"{OKGREEN}   ✅ {d}{ENDC}")
    return a, len(dl)

def check_clean_ip(host, cdn_host, cdn_port, timeout=6, max_ms=1500):
    ip = host
    if not re.match(r"^[\d.]+$", host):
        try:
            for _, _, _, _, sa in socket.getaddrinfo(host, None, socket.AF_INET):
                ip = sa[0]; break
        except Exception: return None
    if not re.match(r"^[\d.]+$", ip): return None
    r = sh(f"curl -s -o /dev/null -m{timeout} -w '%{{http_code}} %{{time_connect}}' "
           f"--resolve {cdn_host}:{cdn_port}:{ip} https://{cdn_host}:{cdn_port}/", timeout + 4)
    code, _, t = r.partition(" ")
    if not code or code == "000": return None
    try: ms = int(float(t or 0) * 1000)
    except Exception: ms = 9999
    if code in ("200","204","301","302","403") and ms <= max_ms:
        return ip, ms
    return None
def write_clean_ips(items, filename="clean-ips.txt"):
    try:
        with open(filename, "w", encoding="utf-8") as f:
            f.write("# Cloudflare clean IPs\n")
            for ip, ms in items: f.write(f"{ip}  # {ms}ms\n")
        print(f"{OKGREEN}✅ wrote {len(items)} clean IPs → {os.path.abspath(filename)}{ENDC}")
    except Exception as e:
        print(f"{WARNING}⚠️ {filename}: {e}{ENDC}")

# ───────── proxy link parse / build ─────────
def parse_proxy_link(link):
    link = link.strip()
    if link.startswith('vless://'): return parse_vless(link)
    if link.startswith('vmess://'): return parse_vmess(link)
    if link.startswith('trojan://'): return parse_trojan(link)
    if link.startswith('ss://'): return parse_shadowsocks(link)
    if link.startswith(('hysteria://','hysteria2://')): return parse_hysteria(link)
    raise ValueError("Unsupported scheme.")
def parse_vless(link):
    rest = link[8:]; ui, rest = rest.split('@',1)
    pr = urllib.parse.urlparse('//'+rest); nl, q, fr = pr.netloc, pr.query, pr.fragment
    h, _, ps = nl.partition(':'); pt = int(ps) if ps.isdigit() else 443
    P = urllib.parse.parse_qs(q, keep_blank_values=True)
    for k,v in P.items(): P[k] = v[-1] if v else ''
    return {'scheme':'vless','userinfo':ui,'host':h,'port':pt,'params':P,'fragment':fr,'raw':None}
def parse_vmess(link):
    b64 = link[8:]; b64 += '=' * (-len(b64) % 4)
    d = json.loads(base64.b64decode(b64).decode('utf-8'))
    h, pt = d.get('add',''), d.get('port',443)
    try: pt = int(pt)
    except: pt = 443
    return {'scheme':'vmess','userinfo':None,'host':h,'port':pt,'params':{},'fragment':'','raw':d}
def parse_trojan(link):
    rest = link[9:]; ui, rest = rest.split('@',1)
    pr = urllib.parse.urlparse('//'+rest); nl, q, fr = pr.netloc, pr.query, pr.fragment
    h, _, ps = nl.partition(':'); pt = int(ps) if ps.isdigit() else 443
    P = urllib.parse.parse_qs(q, keep_blank_values=True)
    for k,v in P.items(): P[k] = v[-1] if v else ''
    return {'scheme':'trojan','userinfo':ui,'host':h,'port':pt,'params':P,'fragment':fr,'raw':None}
def parse_shadowsocks(link):
    rest = link[5:]; fr = ''
    if '#' in rest: rest, fr = rest.split('#',1)
    if '@' in rest:
        ui, hp = rest.split('@',1)
        h, _, ps = hp.rsplit(':',1); pt = int(ps) if ps.isdigit() else 443
    else:
        b64 = rest; b64 += '=' * (-len(b64) % 4)
        ui, hp = base64.b64decode(b64).decode('utf-8').split('@',1)
        h, _, ps = hp.rsplit(':',1); pt = int(ps) if ps.isdigit() else 443
    return {'scheme':'ss','userinfo':ui,'host':h,'port':pt,'params':{},'fragment':fr,'raw':None}
def parse_hysteria(link):
    se = link.find('://') + 3; rest = link[se:]
    pr = urllib.parse.urlparse('//'+rest); nl, q, fr = pr.netloc, pr.query, pr.fragment
    h, _, ps = nl.partition(':'); pt = int(ps) if ps.isdigit() else 443
    P = urllib.parse.parse_qs(q, keep_blank_values=True)
    for k,v in P.items(): P[k] = v[-1] if v else ''
    return {'scheme':'hysteria','userinfo':None,'host':h,'port':pt,'params':P,'fragment':fr,'raw':None}

def _qs(P): return '&'.join(f"{k}={urllib.parse.quote_plus(v)}" for k,v in P.items() if v)
def build_vless(c,h):
    q = _qs(c['params']); u = f"vless://{c['userinfo']}@{h}:{c['port']}"
    if q: u += f"?{q}"
    if c['fragment']: u += f"#{c['fragment']}"
    return u
def build_vmess(c,h):
    d = c['raw'].copy(); d['add'] = h
    return f"vmess://{base64.b64encode(json.dumps(d,separators=(',',':')).encode()).decode()}"
def build_trojan(c,h):
    q = _qs(c['params']); u = f"trojan://{c['userinfo']}@{h}:{c['port']}"
    if q: u += f"?{q}"
    if c['fragment']: u += f"#{c['fragment']}"
    return u
def build_shadowsocks(c,h):
    u = f"ss://{c['userinfo']}@{h}:{c['port']}"
    if c['fragment']: u += f"#{c['fragment']}"
    return u
def build_hysteria(c,h):
    q = _qs(c['params']); u = f"hysteria://{h}:{c['port']}"
    if q: u += f"?{q}"
    if c['fragment']: u += f"#{c['fragment']}"
    return u
def build_proxy_link(c,h):
    s = c['scheme']
    return {'vless':build_vless,'vmess':build_vmess,'trojan':build_trojan,
            'ss':build_shadowsocks,'hysteria':build_hysteria}[s](c,h)

def get_cached_list(url, cache_file):
    use_requests = ensure_requests()
    if os.path.exists(cache_file) and os.path.getsize(cache_file) > 0:
        try:
            content = open(cache_file, 'r', encoding='utf-8').read()
            items = [l.strip() for l in content.splitlines() if l.strip() and not l.startswith('#')]
            if items:
                print(f"{OKGREEN}✅ Loaded {len(items)} items from cache.{ENDC}")
                return items
        except Exception: pass
    print(f"{LITBU}📡 Downloading list...{ENDC}")
    content = ""
    if use_requests:
        import requests
        try:
            r = requests.get(url, timeout=15); r.raise_for_status(); content = r.text
        except Exception as e:
            print(f"{WARNING}⚠️ {e} — trying curl{ENDC}")
    if not content: content = sh(f"curl -fsSL -m 20 {url}")
    if not content: die("download failed")
    open(cache_file, 'w', encoding='utf-8').write(content)
    items = [l.strip() for l in content.splitlines() if l.strip() and not l.startswith('#')]
    if not items: die("no items in downloaded file")
    print(f"{OKGREEN}✅ Cached {len(items)} items.{ENDC}")
    return items

def copy_to_clipboard(text):
    try:
        if platform.system() == "Windows":
            import win32clipboard
            win32clipboard.OpenClipboard(); win32clipboard.EmptyClipboard()
            win32clipboard.SetClipboardText(text); win32clipboard.CloseClipboard()
        elif platform.system() == "Linux":
            subprocess.run(['xclip','-selection','clipboard'], input=text, text=True, check=False)
        elif platform.system() == "Darwin":
            subprocess.run(['pbcopy'], input=text, text=True, check=False)
        print(f"{OKGREEN}✅ Copied to clipboard.{ENDC}")
    except Exception as e:
        print(f"{WARNING}⚠️ Clipboard: {e}{ENDC}")

def run_scanner(default_template=None):
    print(f"{B}{C}{BANNER}{N}")
    print(f"{D}        {SCAN_TITLE}{N}")
    print(f"{D}        {USER_REPO}{N}\n")
    if ask(f"{CYAN}❓ Start scan? [Y/n]{ENDC}", "y").lower() == 'n':
        print(f"{YELLOW}🚫 Cancelled.{ENDC}"); return
    if default_template:
        template = ask(f"{YELLOW}➜ template (Enter = from install){ENDC}", default_template).strip()
    else:
        template = ask(f"{YELLOW}➜ proxy link template (Enter = skip){ENDC}", "").strip()
    pc = None
    if template:
        try: pc = parse_proxy_link(template); print(f"{OKGREEN}✅ {pc['scheme']}{ENDC}")
        except Exception as e: print(f"{WARNING}⚠️ {e}{ENDC}")
    ch = ask(f"{CYAN}❓ 1=IPv4, 2=IPv6, 3=domains{ENDC}", "1").strip()
    while ch not in ('1','2','3'): ch = ask(f"{CYAN}❓ 1=IPv4, 2=IPv6, 3=domains{ENDC}", "1").strip()
    RD = ("https://raw.githubusercontent.com/AyhanMansur/AyhanX-Fredom-Scanner/refs/heads/main/"
          "%F0%9D%94%B8%F0%9D%95%AA%F0%9D%95%99%F0%9D%95%92%F0%9D%95%9F%F0%9D%95%8F-%F0%9D%94%BD"
          "%F0%9D%95%A3%F0%9D%95%96%F0%9D%95%95%F0%9D%95%A0%F0%9D%95%9E-%F0%9D%95%8A%F0%9D%95%94"
          "%F0%9D%95%92%F0%9D%95%9F%F0%9D%95%9F%F0%9D%95%96%F0%9D%95%A3-%F0%9F%A7%91%E2%80%8D"
          "%F0%9F%92%BB%F0%9F%8C%BF")
    if ch == '3':
        url, cache = "https://raw.githubusercontent.com/AyhanMansur/AyhanX-Fredom-Scanner/refs/heads/main/domains.txt", "domains_cache.txt"
    elif ch == '2':
        url, cache = RD+"/IPV6.Range.txt", "ranges_v6_cache.txt"
    else:
        url, cache = RD+"/IPV4.Range.txt", "ranges_v4_cache.txt"
    items = get_cached_list(url, cache)
    li = str(A.scan_limit) if A.scan_limit is not None else ask(f"{CYAN}🔢 Limit (Enter = all){ENDC}", "")
    lim = None
    if li:
        try:
            lim = int(li)
            if lim <= 0: raise ValueError
        except ValueError: lim = None
    print(f"{LITBU}🚀 Scanning...{ENDC}\n")
    all_a, tot = [], 0
    if ch == '3': all_a, tot = scan_domains(items, lim)
    else:
        rem = lim
        for r in items:
            if rem is not None and rem <= 0: break
            a, s = scan_network(r, rem); all_a.extend(a); tot += s
            if rem is not None: rem -= s
    print(f"\n{BOLD}{OKGREEN}📊 Summary:{ENDC}")
    print(f"   scanned {tot}, active {len(all_a)}")
    for it in all_a: print(f"   {OKGREEN}► {it}{ENDC}")
    cdn_host = A.cdn or A.domain or ""
    if all_a and cdn_host:
        print(f"\n{LITBU}🧪 verifying against {cdn_host} …{ENDC}")
        clean = []
        with cfut.ThreadPoolExecutor(16) as ex:
            futs = {ex.submit(check_clean_ip, h, cdn_host, 443): h for h in all_a}
            for fut in cfut.as_completed(futs):
                r = fut.result()
                if r: clean.append(r); print(f"{OKGREEN}   ✔ {r[0]} ({r[1]}ms){ENDC}")
        clean.sort(key=lambda t: t[1])
        if clean: write_clean_ips(clean, "clean-ips.txt")
    gen = []
    if pc and all_a:
        for h in all_a:
            nl = build_proxy_link(pc, h); gen.append(nl); print(f"{OKGREEN}   ➜ {nl}{ENDC}")
    if ask(f"{CYAN}📋 Copy? [y/N]{ENDC}", "n").lower() in ('y','yes'):
        copy_to_clipboard("\n".join(gen) if gen else "\n".join(all_a))

# ═══════════════════════════════════════════════════════════════════════════
#  PANEL ADAPTERS — 3x-ui + Marzban
# ═══════════════════════════════════════════════════════════════════════════
class PanelBase:
    name = "abstract"
    def __init__(self, base, token, resolve):
        self.base = base.rstrip("/"); self.token = token or ""; self.resolve = resolve
    def _http(self, path, body=None, method=None, timeout=20):
        c = ["curl","-sk","-m",str(timeout)] + self.resolve
        if self.token: c += ["-H", f"Authorization: Bearer {self.token}"]
        if body is not None:
            c += ["-H","Content-Type: application/json","-X",(method or "POST"),"-d",json.dumps(body)]
        elif method:
            c += ["-X", method]
        out = subprocess.run(c + [self.base + path], capture_output=True, text=True).stdout
        try: return json.loads(out)
        except Exception: return {"success": False, "raw": out[:300]}
    def probe(self):           raise NotImplementedError
    def list_inbounds(self):   raise NotImplementedError
    def add_inbound(self, remark, port, protocol, settings, stream, sniffing): raise NotImplementedError
    def del_inbound(self, iid): raise NotImplementedError
    def add_client(self, email, subid, password, inbound_ids): raise NotImplementedError
    def attach_client(self, email, inbound_ids): raise NotImplementedError
    def detach_client(self, email, inbound_ids): raise NotImplementedError
    def add_host(self, inbound_id, remark, address, extra, sort_order=0): raise NotImplementedError
    def restart(self):         raise NotImplementedError
    def xray_version(self):    raise NotImplementedError
    def ports_owned(self):     return set(), set()
    def sub_urls(self, subid): return (None, None)
    def db_backup(self):       return None
    def set_remark_template(self, tpl): return True
    def clients_list(self):    return []

class Panel3xui(PanelBase):
    name = "3x-ui"
    def probe(self):
        r = self._http("/panel/api/inbounds/list")
        if r.get("success") is True:
            return True
        blob = json.dumps(r).lower()
        if any(tok in blob for tok in ('"success":false', 'inbound', 'not authenticated',
                                       'unauthorized', 'authorization', 'login')):
            return True
        s = json.dumps(self._http("/panel/api/server/status")).lower()
        return "panelversion" in s or "xray" in s
    def _status(self): return self._http("/panel/api/server/status").get("obj") or {}
    def list_inbounds(self): return self._http("/panel/api/inbounds/list").get("obj") or []
    def add_inbound(self, remark, port, protocol, settings, stream, sniffing):
        r = self._http("/panel/api/inbounds/add",
                       {"up":0,"down":0,"total":0,"remark":remark,"enable":True,"expiryTime":0,
                        "listen":"","port":port,"protocol":protocol,"settings":settings,
                        "streamSettings":stream,"sniffing":sniffing})
        return (r.get("obj") or {}).get("id") if r.get("success") else None
    def del_inbound(self, iid):
        return self._http(f"/panel/api/inbounds/del/{iid}", method="POST").get("success", False)
    def add_client(self, email, subid, password, inbound_ids):
        cl = {"email":email,"subId":subid,"flow":"xtls-rprx-vision","password":password,
              "totalGB":0,"expiryTime":0,"limitIp":0,"limitHwid":0,"enable":True,"tgId":0,
              "comment":"3x-ui-pro-configs"}
        return bool(self._http("/panel/api/clients/add", {"client":cl,"inboundIds":inbound_ids}).get("success"))
    def attach_client(self, email, inbound_ids):
        return self._http(f"/panel/api/clients/{email}/attach", {"inboundIds":inbound_ids}).get("success", False)
    def detach_client(self, email, inbound_ids):
        return self._http(f"/panel/api/clients/{email}/detach", {"inboundIds":inbound_ids}).get("success", False)
    def add_host(self, inbound_id, remark, address, extra, sort_order=0):
        body = {"inboundIds":[inbound_id],"remark":remark,"hosts":[address],"port":0,
                "security":"same","sortOrder":sort_order}
        body.update(extra or {})
        return self._http("/panel/api/hosts/add", body).get("success", False)
    def restart(self): self._http("/panel/api/server/restartXrayService", method="POST")
    def xray_version(self):
        return ((self._status().get("xray") or {}).get("version") or "?")
    def clients_list(self): return self._http("/panel/api/clients/list").get("obj") or []
    def ports_owned(self):
        tcp, udp = set(), set()
        for ib in self.list_inbounds():
            st = ib.get("streamSettings")
            st = json.loads(st) if isinstance(st,str) and st else (st or {})
            if ib.get("protocol") in ("hysteria","wireguard","amneziawg") or st.get("network") in ("kcp","hysteria"):
                udp.add(ib.get("port"))
            else:
                tcp.add(ib.get("port"))
                if ib.get("protocol") in ("shadowsocks","mixed","socks","dokodemo-door","tunnel"):
                    udp.add(ib.get("port"))
        s = self._http("/panel/api/setting/all", method="POST").get("obj") or {}
        for k in ("subPort","webPort"):
            if s.get(k): tcp.add(int(s[k]))
        return tcp, udp
    def sub_urls(self, subid):
        s = self._http("/panel/api/setting/all", method="POST").get("obj") or {}
        sp = s.get("subPort", 2096)
        scheme = "https" if s.get("subCertFile") else "http"
        host = s.get("subDomain") or (sh("curl -4 -s -m6 https://api.ipify.org") or "")
        return (f"{scheme}://{host}:{sp}{s.get('subPath','/sub/')}{subid}",
                f"{scheme}://{host}:{sp}{s.get('subJsonPath','/json/')}{subid}")
    def set_remark_template(self, tpl):
        s = self._http("/panel/api/setting/all", method="POST").get("obj") or {}
        s["remarkTemplate"] = tpl
        if not s.get("subJsonEnable"): s["subJsonEnable"] = True
        return self._http("/panel/api/setting/update", s, method="POST").get("success", False)
    def db_backup(self):
        db = "/etc/x-ui/x-ui.db"
        if os.path.exists(db):
            dst = f"{db}.bak-pro-{int(time.time())}"
            shutil.copy(db, dst); return dst
        return None

class PanelMarzban(PanelBase):
    """Marzban — JWT-based (username/password → token), /api/inbound, /api/user."""
    name = "Marzban"
    def __init__(self, base, token, resolve):
        super().__init__(base, token, resolve)
        self.jwt = None
    def login(self, user, pw):
        r = self._http("/api/admin/token",
                       {"username":user,"password":pw,"grant_type":"password"},
                       method="POST")
        tok = r.get("access_token")
        if tok:
            self.jwt = tok; self.token = tok
            return True
        return False
    def probe(self):
        if self.jwt:
            return True
        # Marzban returns 403 on /api/system without auth
        r = self._http("/api/system", method="GET")
        blob = json.dumps(r).lower()
        if "detail" in blob and ("not authenticated" in blob or "forbidden" in blob or "unauthorized" in blob):
            return True
        if any(k in blob for k in ("version", "xray_version")):
            return True
        # HTML from other apps → reject
        return False
    def _system(self):
        r = self._http("/api/system", method="GET")
        return r if isinstance(r, dict) else {}
    def list_inbounds(self):
        r = self._http("/api/inbounds", method="GET")
        if isinstance(r, list): return r
        if isinstance(r, dict):
            v = r.get("inbounds") or {}
            return list(v.values()) if isinstance(v, dict) else (v or [])
        return []
    def add_inbound(self, remark, port, protocol, settings, stream, sniffing):
        tag = (re.sub(r"[^A-Za-z0-9_-]+", "_", remark) or f"in_{port}")[:32]
        body = {"remark":remark,"port":port,"protocol":protocol,
                "settings":settings,"streamSettings":stream,"sniffing":sniffing,
                "tag":tag}
        r = self._http("/api/inbound", body, method="POST")
        if r.get("success") is False or r.get("detail"):
            return None
        return tag
    def del_inbound(self, iid):
        r = self._http(f"/api/inbound/{iid}", method="DELETE")
        return r.get("success", True) and r.get("detail") is None
    def add_client(self, email, subid, password, inbound_ids):
        # Marzban user creation — attach user to all protocols of the given inbound
        proxies = {"vless": {}, "vmess": {}, "trojan": {}}
        inbounds = {p: list(inbound_ids) for p in proxies}
        body = {"username":email,"proxies":proxies,"inbounds":inbounds,
                "expire":0,"data_limit":0,"status":"active","note":"3x-ui-pro-configs"}
        r = self._http("/api/user", body, method="POST")
        return (r.get("detail") is None and r.get("username") is not None)
    def attach_client(self, email, inbound_ids):
        r = self._http(f"/api/user/{email}", method="GET")
        if not isinstance(r, dict) or "inbounds" not in r: return False
        inb = r["inbounds"]
        for k in list(inb.keys()):
            for iid in inbound_ids:
                if iid not in inb[k]: inb[k].append(iid)
        r2 = self._http(f"/api/user/{email}", {"inbounds":inb}, method="PUT")
        return r2.get("detail") is None
    def detach_client(self, email, inbound_ids):
        # Marzban deletes the user when the inbound is deleted; no-op is fine
        return True
    def add_host(self, inbound_id, remark, address, extra, sort_order=0):
        body = {"remark":remark,"address":address,"port":0}
        body.update(extra or {})
        r = self._http(f"/api/inbound/{inbound_id}/hosts", body, method="POST")
        return r.get("detail") is None
    def restart(self):
        self._http("/api/system/restart", method="POST")
    def xray_version(self):
        return self._system().get("xray_version") or "?"
    def ports_owned(self):
        tcp, udp = set(), set()
        for ib in self.list_inbounds():
            port = ib.get("port")
            proto = (ib.get("protocol") or "").lower()
            if not port: continue
            if proto in ("hysteria","hysteria2","wireguard"): udp.add(int(port))
            else: tcp.add(int(port))
        return tcp, udp
    def sub_urls(self, subid):
        r = self._http(f"/api/user/{subid}", method="GET")
        if isinstance(r, dict) and r.get("subscription_url"):
            return (r["subscription_url"], None)
        # Marzban's subscription uses the *username* as key
        return (None, None)
    def db_backup(self):
        for d in ("/var/lib/marzban","/opt/marzban"):
            if os.path.isdir(d):
                for f in glob.glob(f"{d}/*.db"):
                    dst = f"{f}.bak-pro-{int(time.time())}"
                    try:
                        shutil.copy(f, dst); return dst
                    except Exception: pass
        return None
    def clients_list(self):
        r = self._http("/api/users", method="GET")
        if isinstance(r, dict) and "users" in r: return r["users"]
        return r if isinstance(r, list) else []

def _detect_panel(force):
    """force = '3xui' | 'marzban' | 'auto'"""
    cands = []
    if force == "3xui":   cands = [Panel3xui]
    elif force == "marzban": cands = [PanelMarzban]
    else:                 cands = [Panel3xui, PanelMarzban]

    urls = []
    if A.panel_url:
        urls.append(A.panel_url.rstrip("/"))
    else:
        env = {}
        for p_env in ("/etc/x-ui/install-result.env", "/etc/3x-ui/install-result.env"):
            if os.path.exists(p_env):
                try:
                    for l in open(p_env):
                        if "=" in l:
                            k, v = l.strip().split("=", 1); env[k] = v
                except Exception:
                    pass
                break
        xp = env.get("XUI_PANEL_PORT")
        xb = env.get("XUI_WEB_BASE_PATH") or ""
        if not xp:
            raw = re.sub(r"\x1b\[[0-9;]*m", "", sh("x-ui settings 2>/dev/null"))
            xp = (re.search(r"port:\s*(\d+)", raw) or [None, None])[1]
            xb = (re.search(r"webBasePath:\s*(\S+)", raw) or [None, xb])[1] or xb
        base_path = "/" + xb.strip("/") if xb and xb.strip("/") else ""
        if xp:
            urls.append(f"http://127.0.0.1:{xp}{base_path}")
            if base_path: urls.append(f"http://127.0.0.1:{xp}")
        # Marzban default: 8000 (backend) — but Marzban uses 8000 for API too
        urls.insert(0, "http://127.0.0.1:8000") if force == "marzban" else None
        for pt in (2053, 2083, 2087, 2096, 8000, 8080, 8443, 9000, 3000, 5000, 1800, 1801):
            urls.append(f"http://127.0.0.1:{pt}")

    seen, ordered = set(), []
    for u in urls:
        if u not in seen: seen.add(u); ordered.append(u)

    token = A.token or A.api_key or ""
    for cls in cands:
        for u in ordered:
            try:
                p = cls(u, token, [])
                # Marzban needs creds before probing meaningfully
                if cls is PanelMarzban and not token and A.panel_user and A.panel_pass:
                    p.login(A.panel_user, A.panel_pass)
                if p.probe():
                    return p
            except Exception:
                continue
    return None

# ═══════════════════════════════════════════════════════════════════════════
#  MODE SELECTION + PANEL SUB-MENU
# ═══════════════════════════════════════════════════════════════════════════
# ★ clear screen on start
clear_screen()

print(f"{B}{C}{BANNER}{N}")
print(f"{D}        {PRO_TITLE}  ·  {SCAN_TITLE}{N}")
print(f"{D}        {USER_REPO}{N}\n")

if A.scan:
    run_scanner(); sys.exit(0)

MODE_CHOICE = "install"
if INTERACTIVE and not A.install:
    print(f"{B}What do you want to do?{N}")
    print(f"  {B}1{N}) {G}Install Pro Configs{N}   {D}(3x-ui or Marzban){N}")
    print(f"  {B}2{N}) {C}Run the Proxy Scanner only{N}")
    print(f"  {B}3{N}) {Y}Both{N}")
    mc = ask("Choice", "1").strip().lower()
    MODE_CHOICE = {"2":"scan","3":"both","1":"install"}.get(mc,"install")
if MODE_CHOICE == "scan":
    clear_screen()
    run_scanner(); sys.exit(0)

# ★ 3x-ui / Marzban sub-menu
PANEL_FORCE = (A.panel or "").lower()
if PANEL_FORCE in ("3xui","3x-ui"):   PANEL_FORCE = "3xui"
elif PANEL_FORCE == "marzban":        PANEL_FORCE = "marzban"
elif PANEL_FORCE == "auto":           PANEL_FORCE = ""
else:                                 PANEL_FORCE = ""

if not PANEL_FORCE and INTERACTIVE and not A.install:
    print(f"\n{B}Which panel?{N}")
    print(f"  {B}1{N}) {G}3x-ui{N}     {D}(full catalog: reality / tls / cdn / hysteria2 / pq / ss){N}")
    print(f"  {B}2{N}) {C}Marzban{N}   {D}(no hysteria2, no finalmask; stick to reality + tls + ws){N}")
    print(f"  {B}3{N}) {Y}Auto-detect{N}   {D}(tries 3x-ui first, then Marzban){N}")
    pc_choice = ask("Choice", "1").strip().lower()
    PANEL_FORCE = {"1":"3xui","2":"marzban","3":""}.get(pc_choice, "3xui")
if not PANEL_FORCE:
    PANEL_FORCE = "auto"

# =========================================================================== panel
head("Panel")
PANEL = _detect_panel(PANEL_FORCE if PANEL_FORCE != "auto" else "auto")
if not PANEL:
    die(f"No supported panel found. "
        f"Pass --panel 3xui|marzban --panel-url http://host:port [--token …]")

# Auth flow
if PANEL.name == "3x-ui":
    if not PANEL.token:
        if not INTERACTIVE: die("3x-ui needs --token / --api-key.")
        t = ask("3x-ui API token (Settings > API Tokens)")
        if t: PANEL.token = t
        else: die("no token — aborting")
    if not PANEL._http("/panel/api/inbounds/list").get("success"):
        die("Token rejected by 3x-ui API.")
elif PANEL.name == "Marzban":
    if not getattr(PANEL, "jwt", None):
        if not INTERACTIVE: die("Marzban needs --panel-user / --panel-pass.")
        u = A.panel_user or ask("Marzban username", "admin")
        pw = A.panel_pass or ask("Marzban password")
        if not PANEL.login(u, pw): die("Marzban login failed.")
    if not PANEL.probe():
        die("Marzban login did not produce a valid session.")

XVER = PANEL.xray_version()
info(f"panel {PANEL.name} at {PANEL.base} · xray {XVER}")
if XVER and XVER != "?" and not XVER.startswith("26"):
    warn(f"Xray {XVER} — FinalMask / Sudoku / Salamander need 26.x")
if PANEL.name == "Marzban":
    warn("Marzban: Hysteria2 and FinalMask/Sudoku are not supported by its Xray template.")

XRAY = (glob.glob("/usr/local/x-ui/bin/xray-linux-*") or [""])[0]
inbs = PANEL.list_inbounds()

# =========================================================================== server facts
PUB4 = sh("curl -4 -s -m6 https://api.ipify.org")
PUB6 = ""
for l in sh("ip -6 addr show scope global").splitlines():
    m = re.search(r"inet6 ([0-9a-f:]+)/\d+ .*scope global", l)
    if m and "temporary" not in l and "deprecated" not in l and not m.group(1).startswith(("fd","fc")):
        PUB6 = m.group(1); break
if PUB6 and not sh("curl -6 -s -m6 https://api64.ipify.org"): PUB6 = ""

CF_NETS = [ipaddress.ip_network(n) for n in (
    "173.245.48.0/20 103.21.244.0/22 103.22.200.0/22 103.31.4.0/22 141.101.64.0/18 108.162.192.0/18 190.93.240.0/20 "
    "188.114.96.0/20 197.234.240.0/22 198.41.128.0/17 162.158.0.0/15 104.16.0.0/13 104.24.0.0/14 172.64.0.0/13 "
    "131.0.72.0/22 2400:cb00::/32 2606:4700::/32 2803:f800::/32 2405:b500::/32 2405:8100::/32 2a06:98c0::/29 "
    "2c0f:f248::/32").split()]
def ips_of(d):
    try: return sorted({a[4][0] for a in socket.getaddrinfo(d, None)})
    except Exception: return []
is_cf = lambda ip: any(ipaddress.ip_address(ip) in n for n in CF_NETS if ipaddress.ip_address(ip).version == n.version)

def find_cert(d):
    cands = [(f"/root/cert/{d}/fullchain.pem", f"/root/cert/{d}/privkey.pem"),
             (f"/root/.acme.sh/{d}_ecc/fullchain.cer", f"/root/.acme.sh/{d}_ecc/{d}.key"),
             (f"/root/.acme.sh/{d}/fullchain.cer", f"/root/.acme.sh/{d}/{d}.key"),
             (f"/etc/letsencrypt/live/{d}/fullchain.pem", f"/etc/letsencrypt/live/{d}/privkey.pem")]
    for c, k in cands:
        if os.path.exists(c) and os.path.exists(k):
            names = sh(f"openssl x509 -in '{c}' -noout -ext subjectAltName 2>/dev/null")
            if f"DNS:{d}" in names or f"DNS:*.{d.split('.',1)[-1]}" in names:
                if sh(f"openssl x509 -in '{c}' -noout -checkend 86400 >/dev/null && echo ok") == "ok":
                    return c, k
    return None, None

def issue_cert(d):
    if sh("ss -H -tln 'sport = :80'"):
        warn("Port 80 busy — cannot issue cert."); return None, None
    acme = os.path.expanduser("~/.acme.sh/acme.sh")
    if not os.path.exists(acme): sh("curl -s https://get.acme.sh | sh -s email=admin@" + d, 180)
    if not os.path.exists(acme): warn("acme.sh install failed."); return None, None
    sh(f"{acme} --set-default-ca --server letsencrypt", 60)
    out = sh(f"{acme} --issue -d {d} --standalone --httpport 80 --keylength ec-256 --force", 240)
    os.makedirs(f"/root/cert/{d}", exist_ok=True)
    sh(f"{acme} --install-cert -d {d} --ecc --fullchain-file /root/cert/{d}/fullchain.pem "
       f"--key-file /root/cert/{d}/privkey.pem --reloadcmd 'x-ui restart'", 60)
    if os.path.exists(f"/root/cert/{d}/fullchain.pem"):
        info(f"cert issued for {d}"); return f"/root/cert/{d}/fullchain.pem", f"/root/cert/{d}/privkey.pem"
    warn("cert failed:", out[-200:]); return None, None

# =========================================================================== 1. domain
head("1/4  Your domain (direct, Cloudflare grey cloud)")
print(f"  {D}Used for TLS / Hysteria2. Must point straight to this server ({PUB4}).{N}")
DOMAIN = (A.domain if A.domain is not None else ask("Domain (Enter = none, only REALITY)", "")).strip().lower()
CERT = KEY = None
if DOMAIN:
    ips = ips_of(DOMAIN)
    if not ips: warn(f"{DOMAIN} does not resolve."); DOMAIN = ""
    elif any(is_cf(i) for i in ips):
        warn(f"{DOMAIN} is orange-clouded — must be grey."); DOMAIN = ""
    else:
        if PUB4 not in ips and (not PUB6 or PUB6 not in ips):
            warn(f"{DOMAIN} → {', '.join(ips)}, not to this server ({PUB4}).")
        CERT, KEY = find_cert(DOMAIN)
        if CERT: info(f"cert: {CERT}")
        elif yes(f"No cert for {DOMAIN}. Issue one?", True):
            CERT, KEY = issue_cert(DOMAIN)
        if not CERT: warn("No cert — TLS/CDN/Hysteria2 skipped.")
ADDR = DOMAIN or PUB4

# =========================================================================== 2. CDN
CDN = ""
if CERT:
    head("2/4  CDN domain (Cloudflare orange cloud)")
    CDN = (A.cdn if A.cdn is not None else ask("CDN domain (Enter = skip)", "")).strip().lower()
    if CDN:
        ips = ips_of(CDN)
        if not ips: warn(f"{CDN} does not resolve."); CDN = ""
        elif not any(is_cf(i) for i in ips): warn(f"{CDN} not proxied."); CDN = ""
        else: info(f"{CDN} is behind Cloudflare")

# =========================================================================== 3. configs
CATALOG = [
    ("rv",  f"{BRAND}⚡𝐑𝐞𝐚𝐥𝐢𝐭𝐲-𝐕𝐢𝐬𝐢𝐨𝐧", None, "Reality Vision — main config"),
    ("rx",  f"{BRAND}🌀𝐑𝐞𝐚𝐥𝐢𝐭𝐲-𝐗𝐇𝐓𝐓𝐏", None, "Reality XHTTP"),
    ("rg",  f"{BRAND}🔷𝐑𝐞𝐚𝐥𝐢𝐭𝐲-𝐠𝐑𝐏𝐂", None, "Reality gRPC"),
    ("tv",  f"{BRAND}🔐𝐓𝐋𝐒-𝐕𝐢𝐬𝐢𝐨𝐧", "tls", "TLS Vision + Fragment / IPv6"),
    ("tx",  f"{BRAND}🛰𝐓𝐋𝐒-𝐗𝐇𝐓𝐓𝐏", "tls", "TLS XHTTP direct + CDN"),
    ("ws",  f"{BRAND}🌐𝐂𝐃𝐍-𝐖𝐒", "cdn", "Cloudflare WebSocket + clean IPs"),
    ("hu",  f"{BRAND}🔗𝐂𝐃𝐍-𝐇𝐓𝐓𝐏𝐔𝐩𝐠𝐫𝐚𝐝𝐞", "cdn", "Cloudflare HTTPUpgrade"),
    ("th",  f"{BRAND}🛡️𝐓𝐫𝐨𝐣𝐚𝐧-𝐇𝐔", "tls", "Trojan over HTTPUpgrade (CDN)"),
    ("hy",  f"{BRAND}🚄𝐇𝐲𝐬𝐭𝐞𝐫𝐢𝐚𝟐", "tls", "Hysteria2 + Salamander"),
    ("pq",  f"{BRAND}🧬𝐏𝐐-𝐒𝐮𝐝𝐨𝐤𝐮", None, "PQ Sudoku VLESS (Xray 26)"),
    ("tpq", f"{BRAND}🧬𝐓𝐫𝐨𝐣𝐚𝐧-𝐏𝐐", None, "Trojan + PQ Sudoku (Xray 26)"),
    ("ss",  f"{BRAND}🛟𝐒𝐡𝐚𝐝𝐨𝐰𝐬𝐨𝐜𝐤𝐬-𝟐𝟎𝟐𝟐", None, "Shadowsocks-2022"),
]
avail = [c for c in CATALOG if c[2] is None or (c[2] == "tls" and CERT) or (c[2] == "cdn" and CDN)]

# On Marzban, hide unsupported configs from the menu
if PANEL.name == "Marzban":
    unsupported = {"hy","pq","tpq"}
    avail = [c for c in avail if c[0] not in unsupported]

head("3/4  Which configs to add")
for n, (k, name, _, desc) in enumerate(avail, 1):
    print(f"  {B}{n:2d}{N}) {name:52s} {D}{desc}{N}")
skipped = [c[1] for c in CATALOG if c not in avail]
if skipped: print(f"  {D}not available: {', '.join(skipped)}{N}")
if A.configs:
    sel_keys = [c[0] for c in avail] if A.configs.strip() == "all" else [x.strip() for x in A.configs.split(",")]
else:
    ans = ask("Numbers separated by comma, or 'all'", "all")
    if ans.strip().lower() == "all": sel_keys = [c[0] for c in avail]
    else:
        idx = {int(x) for x in re.findall(r"\d+", ans)}
        sel_keys = [avail[i-1][0] for i in sorted(idx) if 1 <= i <= len(avail)]
SEL = [c for c in avail if c[0] in sel_keys]
if not SEL: die("Nothing selected.")
CLEAN_N = 0
if "ws" in sel_keys or "hu" in sel_keys or "th" in sel_keys or ("tx" in sel_keys and CDN):
    CLEAN_N = int(A.clean) if A.clean is not None else int(re.sub(r"\D","", ask(
        "How many Cloudflare clean-IP configs (0-30)", "20")) or 0)
    CLEAN_N = max(0, min(30, CLEAN_N))

# =========================================================================== ports
owner_tcp_set, owner_udp_set = PANEL.ports_owned()
owner_tcp = {pt: "panel" for pt in owner_tcp_set if pt}
owner_udp = {pt: "panel" for pt in owner_udp_set if pt}
for flag, dct in (("t", owner_tcp), ("u", owner_udp)):
    for l in sh(f"ss -H -{flag}lnp").splitlines():
        f = l.split()
        if len(f) < 5: continue
        m = re.search(r":(\d+)$", f[3])
        if m and int(m.group(1)) not in dct:
            pm = re.search(r'\(\("([^"]+)"', l)
            dct[int(m.group(1))] = pm.group(1) if pm else "?"

CF_HTTPS = [443, 2053, 2083, 2087, 2096, 8443]
PREF = {"rv":[443,2443,3443,6443,7443], "rx":[8443,2443,3443,5443,6443], "rg":[4443,5443,7443,9444],
        "tv":[9443,9444,10444,11444], "tx":[2087,2053,2083,2096,8443], "ws":[2053,2083,2087,2096,8443],
        "hu":[2083,2053,2087,2096,8443], "th":[8443,2096,2087,2083,2053], "hy":[443,8443,4443,2053,10443],
        "pq":[10443,11443,12443,13443], "tpq":[11444,12444,13444,14444], "ss":[8080,8388,18080,28080]}
UDP_ONLY = {"hy"}; BOTH = {"ss"}; CDN_KEYS = {"tx","ws","hu","th"}
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
        if not busy(pt, key): return pt
    for pt in range(20000, 60000, 7):
        if not busy(pt, key) and not (key in CDN_KEYS): return pt
    return None

head("4/4  Ports")
PLAN = {}
for key, name, _, _ in SEL:
    want = PREF[key][0]; who = busy(want, key)
    if not who:
        PLAN[key] = {"port": want, "client_port": 0}; claim(want, key)
        print(f"  {name:52s} port {want}{'/udp' if key in UDP_ONLY else ''}"); continue
    alt = free_from(PREF[key], key)
    cdn_note = key in CDN_KEYS and (alt is None or alt not in CF_HTTPS)
    print(f"  {Y}{name:52s} port {want} used by {who}{N}")
    if key in CDN_KEYS and alt in CF_HTTPS: hint = f"Enter = {alt} (CF port)"
    elif key in CDN_KEYS: hint = "all CF busy: o = Origin-Rule, s = skip"
    else: hint = f"Enter = {alt}"
    if MODE == "auto":
        choice = "" if alt and not cdn_note else "s"
    else:
        print(f"    {D}  Enter = next free, <num> = custom, o = Origin-Rule, s = skip{N}")
        choice = ask(f"    {hint}", "")
    choice = choice.strip().lower()
    if choice == "s" or (choice == "" and (alt is None or cdn_note)):
        print(f"    → skipped"); continue
    if choice == "o" and key in CDN_KEYS:
        pt = free_from(range(30000, 60000, 11), "x")
        PLAN[key] = {"port": pt, "client_port": 443, "origin_rule": True}; claim(pt, key)
        print(f"    → Origin-Rule {pt} → client 443"); continue
    if choice.isdigit():
        pt = int(choice)
        if busy(pt, key): warn(f"    {pt} busy — skipped"); continue
        if key in CDN_KEYS and pt not in CF_HTTPS:
            PLAN[key] = {"port": pt, "client_port": 443, "origin_rule": True}
        else: PLAN[key] = {"port": pt, "client_port": 0}
        claim(pt, key); print(f"    → port {pt}"); continue
    PLAN[key] = {"port": alt, "client_port": 0}; claim(alt, key)
    print(f"    → port {alt}")
if not PLAN: die("Nothing to add.")

# =========================================================================== REALITY SNI + CLEAN
def tls13_h2(sni):
    out = sh(f"echo | timeout 6 openssl s_client -connect {sni}:443 -servername {sni} -alpn h2 -tls1_3 2>/dev/null", 10)
    return "TLSv1.3" in out and "ALPN protocol: h2" in out
SNI_POOL = ["dl.google.com","addons.mozilla.org","www.samsung.com","www.nvidia.com","www.speedtest.net",
            "www.amd.com","www.asus.com","www.lovelive-anime.jp"]
if any(k in PLAN for k in ("rv","rx","rg")):
    with cfut.ThreadPoolExecutor(8) as ex:
        okmap = dict(zip(SNI_POOL, ex.map(tls13_h2, SNI_POOL)))
    GOOD_SNI = [s for s in SNI_POOL if okmap[s]] or SNI_POOL
else: GOOD_SNI = SNI_POOL
sni = lambda i: GOOD_SNI[i % len(GOOD_SNI)]

CLEAN = []
if CLEAN_N and CDN:
    if os.path.exists("clean-ips.txt") and os.path.getsize("clean-ips.txt") > 0:
        lst = open("clean-ips.txt", "r", encoding="utf-8").read()
        info("using local clean-ips.txt")
    else:
        lst = sh(f"curl -fsSL -m10 {REPO_RAW}/clean-ips.txt") if REPO_RAW else ""
    cand = [l.split("#")[0].strip() for l in lst.splitlines() if l.split("#")[0].strip()]
    if not cand: cand = __FALLBACK_CLEAN__
    cdn_port = next((PLAN[k]["port"] for k in ("ws","hu","tx","th") if k in PLAN and not PLAN[k].get("origin_rule")), None)
    if not cdn_port and any(PLAN.get(k, {}).get("origin_rule") for k in ("ws","hu","tx","th")): cdn_port = 443
    if cdn_port:
        def via_cf(a):
            ip = a if re.match(r"^[\d.]+$", a) else (next((x for x in ips_of(a) if ":" not in x), "") or "")
            if not ip or not is_cf(ip): return None
            r = sh(f"curl -s -o /dev/null -m6 -w '%{{http_code}} %{{time_connect}}' --resolve {CDN}:{cdn_port}:{ip} "
                   f"https://{CDN}:{cdn_port}/", 10)
            code, _, t = r.partition(" ")
            return (a, float(t or 9)) if code and code != "000" else None
        info(f"checking {len(cand)} against {CDN} ...")
        with cfut.ThreadPoolExecutor(16) as ex:
            res = [r for r in ex.map(via_cf, cand) if r]
        CLEAN = [a for a, _ in res][:CLEAN_N]
        info(f"{len(CLEAN)} clean ready")

head("Plan")
print(f"  panel {PANEL.name} · addr {ADDR}" + (f" · IPv6 {PUB6}" if PUB6 else "") + (f" · CDN {CDN}" if CDN else ""))
for key, name, _, _ in SEL:
    if key in PLAN:
        pl = PLAN[key]
        print(f"  {G}+{N} {name:52s} port {pl['port']}{'/udp' if key in UDP_ONLY else ''}"
              + (f"  (Origin Rule)" if pl.get("origin_rule") else ""))
if CLEAN: print(f"  {G}+{N} {len(CLEAN)} clean-IP configs")
print(f"  {D}existing inbounds untouched: {len(inbs)}{N}")
if A.dry_run: info("Dry run."); sys.exit(0)
if not yes("Start?", True): sys.exit(0)

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
            return out[n+1].split('"')[3], out[n+2].split('"')[3]
    raise RuntimeError("no vlessenc (Xray 26 needed)")
def reality(network, target, extra):
    priv, pub = x25519()
    s = {"network": network, "security": "reality", "externalProxy": [],
         "realitySettings": {"show": False, "xver": 0, "target": f"{target}:443", "serverNames": [target],
                             "privateKey": priv, "minClientVer": "", "maxClientVer": "", "maxTimediff": 0,
                             "shortIds": [hx(4), hx(8)],
                             "settings": {"publicKey": pub, "fingerprint": "chrome", "serverName": "", "spiderX": "/"}}}
    s.update(extra); return s
def tls(alpn):
    return {"serverName": DOMAIN, "minVersion": "1.2", "maxVersion": "1.3", "cipherSuites": "",
            "rejectUnknownSni": False, "disableSystemRoot": False, "enableSessionResumption": False,
            "certificates": [{"certificateFile": CERT, "keyFile": KEY, "oneTimeLoading": False,
                              "usage": "encipherment", "buildChain": False}],
            "alpn": alpn, "settings": {"fingerprint": "chrome", "echConfigList": ""}}
def tls_stream(network, extra, alpn):
    s = {"network": network, "security": "tls", "externalProxy": [], "tlsSettings": tls(alpn)}; s.update(extra); return s
TCP = {"tcpSettings": {"acceptProxyProtocol": False, "header": {"type": "none"}}}
XH = lambda: {"path": "/" + hx(5), "host": "", "mode": "auto", "xPaddingBytes": "100-1000",
              "noSSEHeader": False, "scMaxEachPostBytes": "1000000", "scMaxBufferedPosts": 30}
VL = lambda: {"clients": [], "decryption": "none", "fallbacks": []}
FRAG = json.dumps({"tcp":[{"type":"fragment","settings":{"packets":"tlshello","lengths":["10-30"],"delays":["5-15"]}}]})
SNIFF = {"enabled": True, "destOverride": ["http","tls","quic"], "metadataOnly": False, "routeOnly": True}
PATHS = {}
def ws_stream():
    PATHS["ws"] = "/" + hx(5)
    return tls_stream("ws", {"wsSettings": {"acceptProxyProtocol": False, "path": PATHS["ws"],
                                            "host": "", "headers": {}, "heartbeatPeriod": 30}}, ["http/1.1"])
def hu_stream():
    PATHS["hu"] = "/" + hx(5)
    return tls_stream("httpupgrade", {"httpupgradeSettings": {"acceptProxyProtocol": False,
                                                              "path": PATHS["hu"], "host": "", "headers": {}}},
                      ["http/1.1"])
def th_stream():
    PATHS["th"] = "/" + hx(5)
    return tls_stream("httpupgrade", {"httpupgradeSettings": {"acceptProxyProtocol": False,
                                                              "path": PATHS["th"], "host": "", "headers": {}}},
                      ["http/1.1"])
def tx_stream():
    x = XH(); PATHS["tx"] = x["path"]
    return tls_stream("xhttp", {"xhttpSettings": x}, ["h2","http/1.1"])
def pq():
    dec, enc = vlessenc()
    return ({"clients": [], "decryption": dec, "encryption": enc},
            {"network":"tcp","security":"none","externalProxy":[], **TCP,
             "finalmask":{"tcp":[{"type":"sudoku","settings":{"password":hx(16),"ascii":"prefer_entropy",
                                                              "paddingMin":2,"paddingMax":7}}]}})
def tpq():
    return ({"clients": []},
            {"network":"tcp","security":"none","externalProxy":[], **TCP,
             "finalmask":{"tcp":[{"type":"sudoku","settings":{"password":hx(16),"ascii":"prefer_entropy",
                                                              "paddingMin":2,"paddingMax":7}}]}})
BUILD = {
    "rv":  ("vless", lambda: (VL(), reality("tcp", sni(0), TCP))),
    "rx":  ("vless", lambda: (VL(), reality("xhttp", sni(1), {"xhttpSettings": XH()}))),
    "rg":  ("vless", lambda: (VL(), reality("grpc", sni(2), {"grpcSettings": {"serviceName": hx(4), "authority": "",
                                                                              "multiMode": True}}))),
    "tv":  ("vless", lambda: (VL(), tls_stream("tcp", TCP, ["h2","http/1.1"]))),
    "tx":  ("vless", lambda: (VL(), tx_stream())),
    "ws":  ("vless", lambda: (VL(), ws_stream())),
    "hu":  ("vless", lambda: (VL(), hu_stream())),
    "th":  ("trojan", lambda: ({"clients": []}, th_stream())),
    "hy":  ("hysteria", lambda: ({"version": 2, "clients": []},
                                 {"network":"hysteria","security":"tls","externalProxy":[],"tlsSettings":tls(["h3"]),
                                  "hysteriaSettings":{"version":2,"udpIdleTimeout":60,
                                                      "masquerade":{"type":"proxy","url":"https://www.bing.com",
                                                                    "rewriteHost":True}},
                                  "finalmask":{"udp":[{"type":"salamander","settings":{"password":hx(16)}}],
                                               "quicParams":{"congestion":"bbr"}}})),
    "pq":  ("vless", pq),
    "tpq": ("trojan", tpq),
    "ss":  ("shadowsocks", lambda: ({"method":"2022-blake3-aes-256-gcm",
                                     "password":base64.b64encode(secrets.token_bytes(32)).decode(),
                                     "network":"tcp,udp","clients":[],"ivCheck":False},
                                    {"network":"tcp","security":"none","externalProxy":[], **TCP})),
}
REMARK = {
    "rv":  f"{BRAND}⚡𝐑𝐞𝐚𝐥𝐢𝐭𝐲-𝐕𝐢𝐬𝐢𝐨𝐧",
    "rx":  f"{BRAND}🌀𝐑𝐞𝐚𝐥𝐢𝐭𝐲-𝐗𝐇𝐓𝐓𝐏",
    "rg":  f"{BRAND}🔷𝐑𝐞𝐚𝐥𝐢𝐭𝐲-𝐠𝐑𝐏𝐂",
    "tv":  f"{BRAND}🔐𝐓𝐋𝐒-𝐕𝐢𝐬𝐢𝐨𝐧",
    "tx":  f"{BRAND}🛰𝐓𝐋𝐒-𝐗𝐇𝐓𝐓𝐏",
    "ws":  f"{BRAND}🌐𝐂𝐃𝐍-𝐖𝐒",
    "hu":  f"{BRAND}🔗𝐂𝐃𝐍-𝐇𝐓𝐓𝐏𝐔𝐩𝐠𝐫𝐚𝐝𝐞",
    "th":  f"{BRAND}🛡️𝐓𝐫𝐨𝐣𝐚𝐧-𝐇𝐔",
    "hy":  f"{BRAND}🚄𝐇𝐲𝐬𝐭𝐞𝐫𝐢𝐚𝟐",
    "pq":  f"{BRAND}🧬𝐏𝐐-𝐒𝐮𝐝𝐨𝐤𝐮",
    "tpq": f"{BRAND}🧬𝐓𝐫𝐨𝐣𝐚𝐧-𝐏𝐐",
    "ss":  f"{BRAND}🛟𝐒𝐡𝐚𝐝𝐨𝐰𝐬𝐨𝐜𝐤𝐬-𝟐𝟎𝟐𝟐",
}
def cdn_host(name, addr, key):
    cp = PLAN[key].get("client_port", 0)
    return (name, addr, {"sni": CDN, "hostHeader": CDN, "finalMask": FRAG, **({"port": cp} if cp else {})})
def HOSTS(key):
    v6 = lambda n, ex={}: [(f"{BRAND}6️⃣{n}-IPv6", PUB6, ex)] if PUB6 else []
    if key == "rv": return [(f"{BRAND}⚡𝐑𝐞𝐚𝐥𝐢𝐭𝐲-𝐕𝐢𝐬𝐢𝐨𝐧", ADDR, {})] + v6("𝐑𝐞𝐚𝐥𝐢𝐭𝐲-𝐕𝐢𝐬𝐢𝐨𝐧")
    if key == "rx": return [(f"{BRAND}🌀𝐑𝐞𝐚𝐥𝐢𝐭𝐲-𝐗𝐇𝐓𝐓𝐏", ADDR, {})] + v6("𝐑𝐞𝐚𝐥𝐢𝐭𝐲-𝐗𝐇𝐓𝐓𝐏")
    if key == "rg": return [(f"{BRAND}🔷𝐑𝐞𝐚𝐥𝐢𝐭𝐲-𝐠𝐑𝐏𝐂", ADDR, {})]
    if key == "tv": return [(f"{BRAND}🔐𝐓𝐋𝐒-𝐕𝐢𝐬𝐢𝐨𝐧", ADDR, {"sni": DOMAIN}),
                            (f"{BRAND}🔐𝐓𝐋𝐒-𝐕𝐢𝐬𝐢𝐨𝐧-𝐅𝐫𝐚𝐠", ADDR, {"sni": DOMAIN, "finalMask": FRAG})] + v6("𝐓𝐋𝐒-𝐕𝐢𝐬𝐢𝐨𝐧", {"sni": DOMAIN})
    if key == "tx":
        h = [] if PLAN["tx"].get("origin_rule") else [(f"{BRAND}🛰𝐓𝐋𝐒-𝐗𝐇𝐓𝐓𝐏", ADDR, {"sni": DOMAIN, "hostHeader": DOMAIN})]
        return h + ([cdn_host(f"{BRAND}🛰𝐂𝐃𝐍-𝐗𝐇𝐓𝐓𝐏-𝐅𝐫𝐚𝐠", CDN, "tx")] if CDN else [])
    if key == "ws": return [cdn_host(f"{BRAND}🌐𝐂𝐃𝐍-𝐖𝐒-𝐅𝐫𝐚𝐠", CDN, "ws")]
    if key == "hu": return [cdn_host(f"{BRAND}🔗𝐂𝐃𝐍-𝐇𝐔-𝐅𝐫𝐚𝐠", CDN, "hu")]
    if key == "th":
        h = [] if PLAN["th"].get("origin_rule") else [(f"{BRAND}🛡️𝐓𝐫𝐨𝐣𝐚𝐧-𝐇𝐔", ADDR, {"sni": DOMAIN, "hostHeader": DOMAIN})]
        return h + ([cdn_host(f"{BRAND}☁️𝐓𝐫𝐨𝐣𝐚𝐧-𝐂𝐃𝐍", CDN, "th")] if CDN else [])
    if key == "hy": return [(f"{BRAND}🚄𝐇𝐲𝐬𝐭𝐞𝐫𝐢𝐚𝟐", ADDR, {"sni": DOMAIN})]
    if key == "pq": return [(f"{BRAND}🧬𝐏𝐐-𝐒𝐮𝐝𝐨𝐤𝐮", ADDR, {})]
    if key == "tpq": return [(f"{BRAND}🧬𝐓𝐫𝐨𝐣𝐚𝐧-𝐏𝐐", ADDR, {})]
    if key == "ss": return [(f"{BRAND}🛟𝐒𝐡𝐚𝐝𝐨𝐰𝐬𝐨𝐜𝐤𝐬-𝟐𝟎𝟐𝟐", ADDR, {})]
    return []

# =========================================================================== apply
head("Adding")
bak = PANEL.db_backup()
if bak: info("database backup:", bak)
try: emails = {c.get("email") for c in (PANEL.clients_list() or [])}
except Exception: emails = set()
EMAIL = A.email or f"pro-{hx(2)}"
while EMAIL in emails: EMAIL = f"{EMAIL}-{hx(1)}"
SUBID = "".join(secrets.choice(string.ascii_lowercase + string.digits) for _ in range(16))
PASSWORD = base64.b64encode(secrets.token_bytes(32)).decode()

def xray_ok(pt, udp):
    for _ in range(10):
        time.sleep(1.5)
        if f":{pt}" in sh(f"ss -H -{'u' if udp else 't'}lnp 'sport = :{pt}'"): return True
    return False

added, made_client = [], False
for key, name, _, _ in SEL:
    if key not in PLAN: continue
    pt = PLAN[key]["port"]; proto, build = BUILD[key]
    try: st, stream = build()
    except Exception as e: warn(f"{name}: {e} — skipped"); continue
    iid = PANEL.add_inbound(REMARK[key], pt, proto, st, stream, SNIFF)
    if not iid:
        warn(f"{name}: panel refused — skipped"); continue
    if not made_client:
        made_client = PANEL.add_client(EMAIL, SUBID, PASSWORD, [iid])
        if not made_client:
            PANEL.del_inbound(iid); die("could not create client")
    else:
        PANEL.attach_client(EMAIL, [iid])
    PANEL.restart()
    if xray_ok(pt, key in UDP_ONLY):
        added.append((key, iid)); info(f"added {name:52s} port {pt}")
    else:
        warn(f"{name}: engine rejected — removed")
        PANEL.detach_client(EMAIL, [iid]); PANEL.del_inbound(iid); PANEL.restart(); time.sleep(3)
if not added: die("Nothing could be added.")
ADDED = dict(added)

# remarkTemplate = 3x-ui only
use_hosts = False
if PANEL.name == "3x-ui":
    s = PANEL._http("/panel/api/setting/all", method="POST").get("obj") or {}
    tmpl = s.get("remarkTemplate", "")
    use_hosts = "{{HOST}}" in tmpl or not inbs
    if not use_hosts:
        warn(f"remarkTemplate = '{tmpl}'")
        use_hosts = yes("Set remarkTemplate to {{HOST}}?", True)
    if use_hosts and "{{HOST}}" not in tmpl:
        PANEL.set_remark_template("{{HOST}}")
else:
    use_hosts = True

clean_key = next((k for k in ("ws","hu","tx","th") if k in ADDED and not PLAN[k].get("origin_rule")), None) \
            or next((k for k in ("ws","hu","tx","th") if k in ADDED), None)
n_links = 0
for order, (key, iid) in enumerate(added):
    hosts = HOSTS(key)
    if key == clean_key and CLEAN:
        hosts += [cdn_host(f"{BRAND}🧊𝐂𝐥𝐞𝐚𝐧-{i:02d}", a, key) for i, a in enumerate(CLEAN, 1)]
    if not use_hosts:
        hosts = [h for h in hosts if h[1] == CDN or h[1] in CLEAN] if key in ("ws","hu","th") else []
    for i, (rem, addr, extra) in enumerate(hosts):
        if not addr: continue
        r = PANEL.add_host(iid, rem, addr, extra, i)
        n_links += bool(r)
        if not r: warn(f"host {rem}: rejected")

ufw = sh("ufw status 2>/dev/null | head -1")
if "Status: active" in ufw:
    for key, _ in added:
        pt = PLAN[key]["port"]
        if key not in UDP_ONLY: sh(f"ufw allow {pt}/tcp")
        if key in UDP_ONLY or key in BOTH: sh(f"ufw allow {pt}/udp")
    info("ufw: ports opened")

if not A.no_bbr and "bbr" not in sh("sysctl -n net.ipv4.tcp_congestion_control"):
    if yes("Enable BBR?", True):
        open("/etc/sysctl.d/99-bbr.conf","w").write(
            "net.core.default_qdisc=fq\nnet.ipv4.tcp_congestion_control=bbr\n")
        sh("modprobe tcp_bbr; sysctl --system")
        info("BBR:", sh("sysctl -n net.ipv4.tcp_congestion_control"))

info("restarting engine ...")
PANEL.restart(); time.sleep(4)

SUB, JSUB = PANEL.sub_urls(EMAIL if PANEL.name == "Marzban" else SUBID)
if not SUB:
    warn("subscription URL unavailable"); SUB = JSUB = "(n/a)"

# =========================================================================== test
passed = total = 0
if not A.no_test and XRAY and PANEL.name == "3x-ui" and JSUB and JSUB != "(n/a)":
    head("E2E test")
    try:
        jhost = urllib.parse.urlparse(JSUB).hostname or "127.0.0.1"
        jport = urllib.parse.urlparse(JSUB).port or 80
        sres = ["--resolve", f"{jhost}:{jport}:127.0.0.1"] if re.search(r"[a-z]", jhost) else []
        subs = json.loads(subprocess.run(["curl","-sk","-m","20"] + sres + [JSUB],
                                         capture_output=True, text=True).stdout)
        subs = subs if isinstance(subs, list) else [subs]
    except Exception: subs = []; warn("couldn't read JSON subscription")
    ins, outs, rules, meta = [], [], [], []
    for n, cfg in enumerate(subs):
        o = next((x for x in cfg.get("outbounds", []) if x.get("tag") == "proxy"), None)
        if not o: continue
        s = o.get("settings", {})
        via_cdn = (o.get("streamSettings", {}).get("tlsSettings") or {}).get("serverName") == CDN and CDN
        def fix(a): return a if via_cdn else ("::1" if PUB6 and a == PUB6 else "127.0.0.1")
        for k in ("vnext","servers"):
            for srv in s.get(k, []) or []: srv["address"] = fix(srv.get("address"))
        if "address" in s: s["address"] = fix(s["address"])
        o["tag"] = f"p{n}"; outs.append(o)
        ins.append({"tag":f"s{n}","listen":"127.0.0.1","port":23000+n,"protocol":"socks","settings":{"udp":True}})
        rules.append({"type":"field","inboundTag":[f"s{n}"],"outboundTag":f"p{n}"})
        meta.append((cfg.get("remarks", f"#{n}"), 23000+n))
    if outs:
        json.dump({"log":{"loglevel":"none"},"inbounds":ins,
                   "outbounds":outs + [{"protocol":"freedom","tag":"d"}],
                   "routing":{"rules":rules}}, open("/tmp/.xui-pro-e2e.json","w"))
        pr = subprocess.Popen([XRAY,"run","-c","/tmp/.xui-pro-e2e.json"],
                              stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
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
                    print(f"  {G+'OK  '+N if ok else R+'FAIL'+N} {name}")
        finally:
            pr.terminate()
            try: os.remove("/tmp/.xui-pro-e2e.json")
            except Exception: pass
        info(f"{passed}/{total} work")
elif not A.no_test:
    head("Bind check")
    okc = 0
    for key, _ in added:
        pt = PLAN[key]["port"]; udp = key in UDP_ONLY
        live = f":{pt}" in sh(f"ss -H -{'u' if udp else 't'}lnp 'sport = :{pt}'")
        print(f"  {G+'OK  '+N if live else R+'FAIL'+N} {REMARK[key]} port {pt}")
        okc += live
    info(f"{okc}/{len(added)} ports listening (e2e internet test skipped on {PANEL.name})")

# =========================================================================== done
head("Done")
print(f"  panel        {PANEL.name}  ({len(added)} inbounds, {n_links} links, {len(inbs)} existing untouched)")
print(f"  client       {B}{EMAIL}{N}")
if SUB and SUB != "(n/a)": print(f"  subscription {B}{SUB}{N}")
if JSUB and JSUB != "(n/a)": print(f"  JSON sub     {B}{JSUB}{N}")
ports_txt = ", ".join(f"{PLAN[k]['port']}/{'udp' if k in UDP_ONLY else ('tcp+udp' if k in BOTH else 'tcp')}" for k, _ in added)
print(f"\n  Open in cloud firewall: {ports_txt}")
if CDN:
    print(f"  Cloudflare: {CDN} = proxied · {DOMAIN} = DNS-only · SSL/TLS = Full")
rules_needed = [(k, PLAN[k]["port"]) for k, _ in added if PLAN[k].get("origin_rule")]
if rules_needed:
    print(f"\n  {Y}Cloudflare Origin Rules needed{N}:")
    for k, pt in rules_needed:
        print(f"    Hostname = {CDN} AND Path starts with {PATHS.get(k,'/')}  →  port {pt}")
if bak: print(f"\n  backup: {bak}")
print(f"  repo:   {USER_REPO}\n")

if not A.no_scan and not A.install and not A.dry_run and MODE_CHOICE != "install":
    if not INTERACTIVE:
        if yes("Also run scanner?", False): run_scanner()
    else:
        print(f"\n{B}{C}── Bonus: Proxy Scanner ──{N}")
        if yes("Run scanner now?", False): run_scanner()
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

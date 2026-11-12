#!/usr/bin/env bash
# =============================================================================
#  3x-ui Pro Configs + Proxy Scanner  —  VLESS / Trojan (3x-ui · Marzban · Pasarguard)
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

REPO_RAW="https://raw.githubusercontent.com/pdnczone/3x-ui-pro-configs/main"
USER_REPO="https://github.com/AyhanMansur/AyhanX-Direct"
TMPPY=$(mktemp /tmp/xui-pro.XXXXXX.py)
trap 'rm -f "$TMPPY"' EXIT
cat > "$TMPPY" <<'PYEOF'
import argparse, base64, glob, ipaddress, json, os, re, secrets, shutil
import socket, string, subprocess, sys, time, platform, urllib.parse, random
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
BRAND      = "🧩👾AyhanX-Direct • "
PRO_TITLE  = f"{B}{C}3x-ui Pro Configs  ·  CDN + PQ + REALITY installer{N}"
SCAN_TITLE = f"{B}{C}Proxy Scanner  ·  range / domain → link builder{N}"

p = argparse.ArgumentParser()
for a in ("--domain","--cdn","--configs","--email","--token","--api-key","--clean","--ports","--scan-limit",
          "--panel","--panel-url","--panel-user","--panel-pass"):
    p.add_argument(a)
for a in ("--no-bbr","--no-test","--yes","--dry-run","--scan","--install","--no-scan",
          "--no-reality-scan","--fresh-reality-scan"):
    p.add_argument(a, action="store_true")
A = p.parse_args()
TOKEN_IN = A.token or A.api_key or ""

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

# ───────── scanner ─────────
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
    print(f"{R}  ✘{N} could not auto-install {CYAN}requests{N} — falling back to curl")
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

def parse_proxy_link(link):
    link = link.strip()
    if link.startswith('vless://'): return parse_vless(link)
    if link.startswith('trojan://'): return parse_trojan(link)
    raise ValueError("Only vless and trojan templates are supported.")
def parse_vless(link):
    rest = link[8:]; ui, rest = rest.split('@',1)
    pr = urllib.parse.urlparse('//'+rest); nl, q, fr = pr.netloc, pr.query, pr.fragment
    h, _, ps = nl.partition(':'); pt = int(ps) if ps.isdigit() else 443
    P = urllib.parse.parse_qs(q, keep_blank_values=True)
    for k,v in P.items(): P[k] = v[-1] if v else ''
    return {'scheme':'vless','userinfo':ui,'host':h,'port':pt,'params':P,'fragment':fr,'raw':None}
def parse_trojan(link):
    rest = link[9:]; ui, rest = rest.split('@',1)
    pr = urllib.parse.urlparse('//'+rest); nl, q, fr = pr.netloc, pr.query, pr.fragment
    h, _, ps = nl.partition(':'); pt = int(ps) if ps.isdigit() else 443
    P = urllib.parse.parse_qs(q, keep_blank_values=True)
    for k,v in P.items(): P[k] = v[-1] if v else ''
    return {'scheme':'trojan','userinfo':ui,'host':h,'port':pt,'params':P,'fragment':fr,'raw':None}

def _qs(P): return '&'.join(f"{k}={urllib.parse.quote_plus(v)}" for k,v in P.items() if v)
def build_vless(c,h):
    q = _qs(c['params']); u = f"vless://{c['userinfo']}@{h}:{c['port']}"
    if q: u += f"?{q}"
    if c['fragment']: u += f"#{c['fragment']}"
    return u
def build_trojan(c,h):
    q = _qs(c['params']); u = f"trojan://{c['userinfo']}@{h}:{c['port']}"
    if q: u += f"?{q}"
    if c['fragment']: u += f"#{c['fragment']}"
    return u
def build_proxy_link(c,h):
    return {'vless':build_vless,'trojan':build_trojan}[c['scheme']](c,h)

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
        template = ask(f"{YELLOW}➜ vless/trojan template (Enter = skip){ENDC}", "").strip()
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
#  PANEL ADAPTERS
# ═══════════════════════════════════════════════════════════════════════════
COMING_SOON = "🔮 coming soon"

class PanelBase:
    name = "abstract"
    def __init__(self, base, token, resolve):
        self.base = base.rstrip("/"); self.token = token or ""; self.resolve = resolve
    def _http(self, path, body=None, method=None, timeout=20, form=None):
        c = ["curl","-sk","-m",str(timeout)] + self.resolve
        if self.token: c += ["-H", f"Authorization: Bearer {self.token}"]
        if form is not None:
            c += ["-X", (method or "POST"), "--data", urllib.parse.urlencode(form)]
        elif body is not None:
            c += ["-H","Content-Type: application/json","-X",(method or "POST"),"-d",json.dumps(body)]
        elif method:
            c += ["-X", method]
        out = subprocess.run(c + [self.base + path], capture_output=True, text=True).stdout
        try: return json.loads(out)
        except Exception: return {"success": False, "raw": out[:300]}
    def _code(self, path, method=None, timeout=4):
        c = ["curl","-sk","-m",str(timeout),"-o","/dev/null","-w","%{http_code}"] + self.resolve
        if self.token: c += ["-H", f"Authorization: Bearer {self.token}"]
        if method: c += ["-X", method]
        try:
            return subprocess.run(c + [self.base + path], capture_output=True,
                                  text=True, timeout=timeout + 5).stdout.strip()
        except Exception:
            return ""
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
    def supports(self, key):   return True

class Panel3xui(PanelBase):
    name = "3x-ui"
    def probe(self):
        r = self._http("/panel/api/inbounds/list")
        if r.get("success") is True: return True
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
    name = "Marzban"
    def __init__(self, base, token, resolve):
        super().__init__(base, token, resolve)
        self.jwt = None
    def login(self, user, pw):
        # OAuth2 password flow: must be form-encoded, not JSON
        r = self._http("/api/admin/token",
                       form={"username":user,"password":pw,"grant_type":"password"})
        tok = r.get("access_token") if isinstance(r, dict) else None
        if tok:
            self.jwt = tok; self.token = tok
            return True
        return False
    def probe(self):
        if self.jwt: return True
        # Pasarguard (a Marzban fork) exposes /api/cores; Marzban does not
        if self._code("/api/cores") in ("200","401","403"):
            return False
        r = self._http("/api/system", method="GET")
        blob = json.dumps(r).lower()
        if "detail" in blob and ("not authenticated" in blob or "forbidden" in blob or "unauthorized" in blob):
            return True
        if any(k in blob for k in ("version", "xray_version")):
            return True
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
    def detach_client(self, email, inbound_ids): return True
    def add_host(self, inbound_id, remark, address, extra, sort_order=0):
        body = {"remark":remark,"address":address,"port":0}
        body.update(extra or {})
        r = self._http(f"/api/inbound/{inbound_id}/hosts", body, method="POST")
        return r.get("detail") is None
    def restart(self): self._http("/api/system/restart", method="POST")
    def xray_version(self): return self._system().get("xray_version") or "?"
    def ports_owned(self):
        tcp, udp = set(), set()
        for ib in self.list_inbounds():
            port = ib.get("port"); proto = (ib.get("protocol") or "").lower()
            if not port: continue
            if proto in ("hysteria","hysteria2","wireguard"): udp.add(int(port))
            else: tcp.add(int(port))
        return tcp, udp
    def sub_urls(self, subid):
        r = self._http(f"/api/user/{subid}", method="GET")
        if isinstance(r, dict) and r.get("subscription_url"):
            return (r["subscription_url"], None)
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
    def supports(self, key):
        # Marzban's Xray template rejects FinalMask / PQ Sudoku
        return key not in {"rvpq","rxpq","rgpq","twsp","twstp","trhv","trxp","trgp"}

class PanelPasarguard(PanelBase):
    """Pasarguard: JWT admin login (no API keys). Inbounds are plain Xray inbounds
    inside the core config (/api/cores). Users get access through groups.
    Hosts reference an inbound_tag."""
    name  = "Pasarguard"
    GROUP = "pro-configs"
    def __init__(self, base, token, resolve):
        super().__init__(base, token, resolve)
        self.jwt = None; self.core_id = None; self.group_id = None; self._sub = None

    # ---- helpers
    @staticmethod
    def _items(r, key):
        if isinstance(r, list): return r
        if isinstance(r, dict) and isinstance(r.get(key), list): return r[key]
        return []
    @staticmethod
    def _ok(r, empty_ok=False):
        if isinstance(r, list): return True
        if not isinstance(r, dict) or "detail" in r: return False
        if r.get("success") is False:
            return bool(empty_ok and r.get("raw", "x") == "")
        return True
    def _system(self):
        r = self._http("/api/system", method="GET")
        return r if isinstance(r, dict) else {}

    # ---- auth / detection
    def login(self, user, pw):
        r = self._http("/api/admin/token",
                       form={"username": user, "password": pw, "grant_type": "password"})
        tok = r.get("access_token") if isinstance(r, dict) else None
        if tok:
            self.jwt = self.token = tok; return True
        return False
    def authed(self): return self._code("/api/admin") == "200"
    def probe(self):
        if self.token: return self.authed()
        return self._code("/api/cores") in ("401", "403")   # only Pasarguard has /api/cores

    # ---- core config (inbounds)
    def _core(self):
        cores = self._items(self._http("/api/cores", method="GET"), "cores")
        if not cores: return None
        c = next((x for x in cores if "xray" in str(x.get("type", "xray")).lower()), cores[0])
        self.core_id = c.get("id")
        full = self._http(f"/api/core/{self.core_id}", method="GET")
        if isinstance(full, dict) and full.get("config"): c = full
        cfg = c.get("config")
        if isinstance(cfg, str):
            try: cfg = json.loads(cfg)
            except Exception: return None
        if not isinstance(cfg, dict): return None
        c["config"] = cfg
        return c
    def _save_core(self, core, cfg):
        body = {"name": core.get("name", "Xray"), "config": cfg,
                "exclude_inbound_tags": core.get("exclude_inbound_tags") or [],
                "fallbacks_inbound_tags": core.get("fallbacks_inbound_tags") or []}
        r = self._http(f"/api/core/{self.core_id}?restart_nodes=true", body,
                       method="PUT", timeout=60)
        if not self._ok(r):
            warn(f"Pasarguard core update rejected: {json.dumps(r)[:240]}")
            return False
        return True
    @staticmethod
    def _native(stream):
        """3x-ui stream JSON -> plain Xray streamSettings (strip panel-only keys)."""
        s = json.loads(json.dumps(stream))
        s.pop("externalProxy", None)
        (s.get("realitySettings") or {}).pop("settings", None)
        t = s.get("tlsSettings")
        if t:
            t.pop("settings", None)
            if not t.get("cipherSuites"): t.pop("cipherSuites", None)
        return s

    def list_inbounds(self):
        c = self._core()
        out = []
        for ib in ((c or {}).get("config") or {}).get("inbounds", []) or []:
            out.append({"tag": ib.get("tag"), "port": ib.get("port"),
                        "protocol": ib.get("protocol"),
                        "streamSettings": ib.get("streamSettings") or {}})
        return out
    def ports_owned(self):
        tcp, udp = set(), set()
        for ib in self.list_inbounds():
            try: port = int(ib["port"])
            except Exception: continue
            net = (ib.get("streamSettings") or {}).get("network")
            if (ib.get("protocol") or "") in ("hysteria","hysteria2","wireguard") or net in ("kcp","hysteria"):
                udp.add(port)
            else: tcp.add(port)
        return tcp, udp
    def add_inbound(self, remark, port, protocol, settings, stream, sniffing):
        core = self._core()
        if not core:
            warn("Pasarguard: could not read the core config"); return None
        cfg = core["config"]; ibs = cfg.setdefault("inbounds", [])
        tag = f"pro-{protocol}-{port}"
        if any(i.get("tag") == tag for i in ibs): tag += "-" + secrets.token_hex(2)
        ibs.append({"tag": tag, "port": port, "protocol": protocol, "settings": settings,
                    "streamSettings": self._native(stream), "sniffing": sniffing})
        if not self._save_core(core, cfg): return None
        if not self._group_tags(add=tag):
            self.del_inbound(tag); return None
        return tag
    def del_inbound(self, tag):
        core = self._core()
        if not core: return False
        cfg = core["config"]
        cfg["inbounds"] = [i for i in cfg.get("inbounds", []) if i.get("tag") != tag]
        ok = self._save_core(core, cfg)
        self._group_tags(remove=tag)
        return ok

    # ---- group / user
    def _group(self, first_tag=None):
        if self.group_id: return self.group_id
        for g in self._items(self._http("/api/groups", method="GET"), "groups"):
            if g.get("name") == self.GROUP:
                self.group_id = g.get("id"); return self.group_id
        if not first_tag:
            return None          # panel refuses groups with zero inbounds
        r = self._http("/api/group", {"name": self.GROUP, "inbound_tags": [first_tag]}, method="POST")
        if self._ok(r) and isinstance(r, dict): self.group_id = r.get("id")
        else: warn(f"Pasarguard group create: {json.dumps(r)[:200]}")
        return self.group_id
    def _group_tags(self, add=None, remove=None):
        gid = self._group(first_tag=add)
        if not gid: return False
        g = self._http(f"/api/group/{gid}", method="GET")
        tags = [t for t in (g.get("inbound_tags") or []) if t != remove] if isinstance(g, dict) else []
        if add and add not in tags: tags.append(add)
        if not tags: return True  # panel needs >=1 inbound; leave the group as it is
        r = self._http(f"/api/group/{gid}", {"name": self.GROUP, "inbound_tags": tags}, method="PUT")
        if not self._ok(r):
            warn(f"Pasarguard group update: {json.dumps(r)[:200]}")
            return False
        return True
    def add_client(self, email, subid, password, inbound_ids):
        gid = self._group()
        if not gid: return False
        body = {"username": email, "status": "active", "group_ids": [gid],
                "note": "3x-ui-pro-configs",
                "proxy_settings": {"trojan": {"password": password},
                                   "vless": {"flow": "xtls-rprx-vision"}}}
        r = self._http("/api/user", body, method="POST")
        if self._ok(r) and isinstance(r, dict) and r.get("username"):
            self._sub = r.get("subscription_url"); return True
        warn(f"Pasarguard user create: {json.dumps(r)[:200]}")
        return False
    def attach_client(self, email, inbound_ids): return True   # access comes from the group
    def detach_client(self, email, inbound_ids): return True
    def clients_list(self):
        return self._items(self._http("/api/users?limit=1000", method="GET"), "users")

    # ---- hosts
    def add_host(self, inbound_id, remark, address, extra, sort_order=0):
        extra = extra or {}
        body = {"remark": remark, "address": [address], "inbound_tag": inbound_id,
                "priority": sort_order + 1, "status": ["active"], "security": "inbound_default"}
        sni = extra.get("sni")
        if sni: body["sni"] = [sni]
        if extra.get("hostHeader"): body["host"] = [extra["hostHeader"]]
        if extra.get("port"): body["port"] = int(extra["port"])
        cdn = globals().get("CDN")
        if sni and cdn and sni == cdn:           # CDN hosts: client speaks TLS to Cloudflare
            body["security"] = "tls"; body["fingerprint"] = "chrome"
        if extra.get("finalMask"):
            try:
                st = json.loads(extra["finalMask"])["tcp"][0]["settings"]
                body["fragment_settings"] = {"xray": {"packets": st.get("packets", "tlshello"),
                                                      "length": st["lengths"][0],
                                                      "interval": st["delays"][0]}}
            except Exception: pass
        r = {}
        for path in ("/api/host", "/api/hosts"):
            r = self._http(path, body, method="POST")
            if self._ok(r): return True
            if not any(k in json.dumps(r).lower() for k in ("not found", "not allowed")): break
        warn(f"Pasarguard host: {json.dumps(r)[:200]}")
        return False

    # ---- misc
    def restart(self):
        # core PUT already restarts; this is best-effort only
        self._http("/api/core/restart", method="POST")
    def xray_version(self):
        v = self._system().get("xray_version")
        if v: return v
        for b in ["/var/lib/pasarguard/xray-core/xray", "/usr/local/bin/xray", "/usr/bin/xray"]:
            if os.access(b, os.X_OK):
                m = re.search(r"Xray (\d+[\d.]*)", sh(f"'{b}' version"))
                if m: return m.group(1)
        return "?"
    def sub_urls(self, subid):                      # subid == username here
        u = self._sub
        if not u:
            r = self._http(f"/api/user/{subid}", method="GET")
            u = r.get("subscription_url") if isinstance(r, dict) else None
        if u and u.startswith("/"): u = self.base + u
        return (u, None)
    def db_backup(self):
        # we mutate the core config, so that is what we back up
        c = self._core()
        if not c: return None
        dst = f"pasarguard-core-{self.core_id}.bak-pro-{int(time.time())}.json"
        try:
            json.dump(c, open(dst, "w"), indent=2); return os.path.abspath(dst)
        except Exception: return None
    def stage_cert(self, domain, cert, key):
        # the panel usually runs in Docker; /var/lib/pasarguard is mounted at the same path
        base = "/var/lib/pasarguard"
        if not os.path.isdir(base): return cert, key
        d = f"{base}/certs/{domain}"; os.makedirs(d, exist_ok=True)
        shutil.copy(cert, f"{d}/fullchain.pem"); shutil.copy(key, f"{d}/privkey.pem")
        os.chmod(f"{d}/privkey.pem", 0o600)
        info(f"cert copied to {d} (re-copy after renewals)")
        return f"{d}/fullchain.pem", f"{d}/privkey.pem"
    def supports(self, key): return True

def _detect_panel(force):
    cands = []
    if force == "3xui":       cands = [Panel3xui]
    elif force == "marzban":  cands = [PanelMarzban]
    elif force == "pasarguard": cands = [PanelPasarguard]
    else:                     cands = [Panel3xui, PanelPasarguard, PanelMarzban]

    candidates = []
    if A.panel_url:
        candidates.append(A.panel_url.rstrip("/"))
    else:
        env = {}
        for p_env in ("/etc/x-ui/install-result.env", "/etc/3x-ui/install-result.env"):
            if os.path.exists(p_env):
                try:
                    for l in open(p_env):
                        if "=" in l:
                            k, v = l.strip().split("=", 1); env[k] = v
                except Exception: pass
                break
        xp = env.get("XUI_PANEL_PORT")
        xb = env.get("XUI_WEB_BASE_PATH") or ""
        if not xp:
            raw = re.sub(r"\x1b\[[0-9;]*m", "", sh("x-ui settings 2>/dev/null"))
            xp = (re.search(r"port:\s*(\d+)", raw) or [None, None])[1]
            xb = (re.search(r"webBasePath:\s*(\S+)", raw) or [None, xb])[1] or xb
        base_path = "/" + xb.strip("/") if xb and xb.strip("/") else ""
        if xp:
            candidates.append(f"http://127.0.0.1:{xp}{base_path}")
            if base_path: candidates.append(f"http://127.0.0.1:{xp}")
        if force in ("marzban","pasarguard"):
            candidates.insert(0, "http://127.0.0.1:8000")
        for pt in (2053, 2083, 2087, 2096, 8000, 8080, 8443, 9000, 3000, 5000, 1800, 1801):
            candidates.append(f"http://127.0.0.1:{pt}")

    # Pasarguard / Marzban: read the panel's own .env for the real port + TLS mode
    if force in ("marzban", "pasarguard", "auto") and not A.panel_url:
        for envf in ("/opt/pasarguard/.env", "/opt/marzban/.env"):
            if os.path.exists(envf):
                try:
                    e = dict(l.strip().split("=", 1) for l in open(envf)
                             if "=" in l and not l.lstrip().startswith("#"))
                    pt  = (e.get("UVICORN_PORT") or "8000").strip("\"' ")
                    sch = "https" if (e.get("UVICORN_SSL_CERTFILE") or "").strip("\"' ") else "http"
                    candidates.insert(0, f"{sch}://127.0.0.1:{pt}")
                except Exception: pass

    seen, ordered = set(), []
    for u in candidates:
        if u not in seen: seen.add(u); ordered.append(u)

    listening = set()
    for l in sh("ss -H -tlnp").splitlines():
        m = re.search(r":(\d+)\s", l) or re.search(r":(\d+)$", l)
        if m:
            try: listening.add(int(m.group(1)))
            except: pass
    if listening:
        info(f"listening TCP ports: {sorted(listening)[:25]}")

    token = A.token or A.api_key or ""
    for cls in cands:
        for u in ordered:
            variants = [u] + ([u.replace("http://", "https://", 1)] if (cls is not Panel3xui and u.startswith("http://")) else [])
            for uu in variants:
                pu = urllib.parse.urlparse(uu)
                if pu.port and pu.hostname in ("127.0.0.1", "localhost") and pu.port not in listening:
                    continue
                try:
                    pn = cls(uu, token, [])
                    if cls in (PanelMarzban, PanelPasarguard) and not token and A.panel_user and A.panel_pass:
                        pn.login(A.panel_user, A.panel_pass)
                    if pn.probe():
                        return pn
                except Exception:
                    continue
    return None

# ═══════════════════════════════════════════════════════════════════════════
#  MODE + PANEL SUB-MENU
# ═══════════════════════════════════════════════════════════════════════════
print(f"{B}{C}{BANNER}{N}")
print(f"{D}        {PRO_TITLE}  ·  {SCAN_TITLE}{N}")
print(f"{D}        {USER_REPO}{N}\n")

if A.scan:
    clear_screen(); run_scanner(); sys.exit(0)

MODE_CHOICE = "install"
if INTERACTIVE and not A.install:
    print(f"{B}What do you want to do?{N}")
    print(f"  {B}1{N}) {G}Install Pro Configs{N}   {D}(3x-ui / Marzban / Pasarguard){N}")
    print(f"  {B}2{N}) {C}Run the Proxy Scanner only{N}")
    print(f"  {B}3{N}) {Y}Both{N}")
    mc = ask("Choice", "1").strip().lower()
    MODE_CHOICE = {"2":"scan","3":"both","1":"install"}.get(mc,"install")
if MODE_CHOICE == "scan":
    clear_screen(); run_scanner(); sys.exit(0)

PANEL_FORCE = (A.panel or "").lower()
if PANEL_FORCE in ("3xui","3x-ui"):   PANEL_FORCE = "3xui"
elif PANEL_FORCE == "marzban":        PANEL_FORCE = "marzban"
elif PANEL_FORCE == "pasarguard":     PANEL_FORCE = "pasarguard"
else:                                 PANEL_FORCE = ""

if not PANEL_FORCE and INTERACTIVE and not A.install:
    print(f"\n{B}Which panel?{N}")
    print(f"  {B}1{N}) {G}3x-ui{N}         {D}(full catalog — PQ / REALITY included){N}")
    print(f"  {B}2{N}) {C}Marzban{N}       {D}(PQ / REALITY marked 'coming soon'){N}")
    print(f"  {B}3{N}) {Y}Pasarguard{N}    {D}(full catalog — admin login, edits the Xray core config){N}")
    print(f"  {B}4{N}) {Y}Auto-detect{N}   {D}(3x-ui → Pasarguard → Marzban){N}")
    pc_choice = ask("Choice", "1").strip().lower()
    PANEL_FORCE = {"1":"3xui","2":"marzban","3":"pasarguard","4":"auto"}.get(pc_choice, "3xui")
if not PANEL_FORCE: PANEL_FORCE = "auto"

# =========================================================================== panel
head("Panel")
PANEL = _detect_panel(PANEL_FORCE)
if not PANEL:
    die("No supported panel found. "
        "Pass --panel 3xui|marzban|pasarguard --panel-url http://host:port [--token …] "
        "[--panel-user … --panel-pass …]")

if PANEL.name == "3x-ui":
    if not PANEL.token:
        if not INTERACTIVE: die("3x-ui needs --token / --api-key.")
        t = ask("3x-ui API token (Settings > API Tokens)")
        if t: PANEL.token = t
        else: die("no token — aborting")
    if not PANEL._http("/panel/api/inbounds/list").get("success"):
        die("Token rejected by 3x-ui API.")
elif PANEL.name == "Marzban":
    if not getattr(PANEL, "jwt", None) and not PANEL.token:
        if not INTERACTIVE and not (A.panel_user and A.panel_pass):
            die("Marzban needs --panel-user / --panel-pass.")
        u = A.panel_user or ask("Marzban username", "admin")
        pw = A.panel_pass or ask("Marzban password")
        if not PANEL.login(u, pw): die("Marzban login failed.")
    if not PANEL.probe():
        die("Marzban login did not produce a valid session.")
elif PANEL.name == "Pasarguard":
    if not PANEL.token:
        if not INTERACTIVE and not (A.panel_user and A.panel_pass):
            die("Pasarguard needs --panel-user / --panel-pass (or --token with an existing JWT).")
        u  = A.panel_user or ask("Pasarguard admin username", "admin")
        pw = A.panel_pass or ask("Pasarguard admin password")
        if not PANEL.login(u, pw): die("Pasarguard login failed.")
    if not PANEL.authed(): die("Pasarguard session not accepted.")

XVER = PANEL.xray_version()
info(f"panel {PANEL.name} at {PANEL.base} · xray {XVER}")
if PANEL.name == "Marzban":
    warn("Marzban: PQ Sudoku and REALITY PQ configs are marked 'coming soon'")
if PANEL.name == "Pasarguard" and XVER != "?" and not XVER.startswith("26"):
    warn(f"Pasarguard Xray {XVER}: PQ / finalmask configs need a recent Xray-core (26+)")

_xray_candidates = (
    glob.glob("/usr/local/x-ui/bin/xray-linux-*")
    + glob.glob("/usr/local/x-ui/bin/xray")
    + glob.glob("/var/lib/pasarguard/xray-core/xray")
    + glob.glob("/usr/local/bin/xray")
    + glob.glob("/usr/bin/xray")
)
XRAY = next((p for p in _xray_candidates if p and os.access(p, os.X_OK)), "")
if not XRAY:
    warn("xray binary not found — REALITY / PQ configs will fail")
else:
    info(f"xray binary: {XRAY}")
    _test = sh(f"'{XRAY}' x25519 2>/dev/null")
    if "PrivateKey" not in _test and "Private key" not in _test:
        warn("xray x25519 returned nothing — REALITY will be skipped")

DB = "/etc/x-ui/x-ui.db"
settings = {} if PANEL.name != "3x-ui" else (PANEL._http("/panel/api/setting/all", method="POST").get("obj") or {})
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
print(f"  {D}Used for TLS/CDN configs. Must point straight to this server ({PUB4}).{N}")
DOMAIN = (A.domain if A.domain is not None else ask("Domain (Enter = none, REALITY + plain only)", "")).strip().lower()
CERT = KEY = None
if DOMAIN:
    ips = ips_of(DOMAIN)
    if not ips: warn(f"{DOMAIN} does not resolve."); DOMAIN = ""
    elif any(is_cf(i) for i in ips):
        warn(f"{DOMAIN} orange-clouded — must be grey."); DOMAIN = ""
    else:
        if PUB4 not in ips and (not PUB6 or PUB6 not in ips):
            warn(f"{DOMAIN} → {', '.join(ips)}, not to this server ({PUB4}).")
        CERT, KEY = find_cert(DOMAIN)
        if CERT: info(f"cert: {CERT}")
        elif yes(f"No cert for {DOMAIN}. Issue one?", True):
            CERT, KEY = issue_cert(DOMAIN)
        if not CERT: warn("No cert — TLS/CDN configs skipped.")
if CERT and PANEL.name == "Pasarguard":
    CERT, KEY = PANEL.stage_cert(DOMAIN, CERT, KEY)
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
    ("tch",   f"{BRAND}👾Trojan • HU • CDN", "cdn", "Trojan + HTTPUpgrade (no TLS), over CDN"),
    ("tcht",  f"{BRAND}👾Trojan • HU • CDN • TLS", "cdn", "Trojan + HTTPUpgrade + TLS, over CDN"),
    ("tws",   f"{BRAND}👾Trojan • WS", "tls", "Trojan + WS"),
    ("twsp",  f"{BRAND}🧬Trojan • WS • PQ", None, "Trojan + WS + PQ Sudoku"),
    ("twst",  f"{BRAND}👾Trojan • WS • TLS", "tls", "Trojan + WS + TLS"),
    ("twstp", f"{BRAND}🧬Trojan • WS • TLS • PQ", "tls", "Trojan + WS + TLS + PQ Sudoku"),
    ("thu",   f"{BRAND}👾Trojan • HU • Plain", None, "Trojan + HTTPUpgrade (plain TCP)"),
    ("trhv",  f"{BRAND}👾Trojan • REALITY • HU", None, "Trojan + REALITY + HTTPUpgrade"),
    ("trxp",  f"{BRAND}👾Trojan • REALITY • XH", None, "Trojan + REALITY + XHTTP"),
    ("trgp",  f"{BRAND}👾Trojan • REALITY • gRPC", None, "Trojan + REALITY + gRPC"),
    ("rvpq",  f"{BRAND}🧬Reality • Vision • PQ", None, "VLESS + REALITY TCP + PQ Sudoku"),
    ("rxpq",  f"{BRAND}🧬Reality • XHTTP • PQ", None, "VLESS + REALITY XHTTP + PQ Sudoku"),
    ("rgpq",  f"{BRAND}🧬Reality • gRPC • PQ", None, "VLESS + REALITY gRPC + PQ Sudoku"),
]
avail = [c for c in CATALOG if c[2] is None or (c[2] == "tls" and CERT) or (c[2] == "cdn" and CDN)]

head("3/4  Which configs to add")
for n, (k, name, _, desc) in enumerate(avail, 1):
    tag = "" if PANEL.supports(k) else f" {Y}{COMING_SOON}{N}"
    print(f"  {B}{n:2d}{N}) {name:52s} {D}{desc}{N}{tag}")
skipped = [c[1] for c in CATALOG if c not in avail]
if skipped: print(f"  {D}not available: {', '.join(skipped)}{N}")
if PANEL.name == "Marzban":
    warn("Marzban: PQ / REALITY configs are 'coming soon' — they will be skipped if selected.")
if not XRAY or not sh(f"'{XRAY}' x25519 2>/dev/null"):
    warn("REALITY configs need working `xray x25519`. Install Xray 26+ via panel → Xray → Update.")

# ─── AUTO-SCAN REALITY CAMOUFLAGE TARGETS ───────────────────────────────
def _tls13_h2_probe(dom):
    if not dom or not re.match(r"^[A-Za-z0-9.\-]+$", dom):
        return None
    t0 = time.time()
    out = sh(f"echo | timeout 4 openssl s_client -connect {dom}:443 -servername {dom} -alpn h2 -tls1_3 2>/dev/null", 6)
    if "TLSv1.3" not in out or "ALPN protocol: h2" not in out:
        return None
    return (dom, int((time.time() - t0) * 1000))

SNI_FALLBACK = [
    "dl.google.com","addons.mozilla.org","www.samsung.com","www.nvidia.com",
    "www.speedtest.net","www.amd.com","www.asus.com","www.lovelive-anime.jp",
    "www.microsoft.com","www.apple.com","www.cloudflare.com","www.icloud.com",
    "www.zoom.us","www.github.com","www.wikipedia.org","www.bing.com",
    "www.python.org","www.ubuntu.com","www.mozilla.org","www.docker.com",
]

def discover_reality_targets(need_n=8):
    cache = "reality-targets.txt"
    if getattr(A, "no_reality_scan", False):
        info("--no-reality-scan set → using built-in fallback pool")
        return list(SNI_FALLBACK)[:need_n]
    if getattr(A, "fresh_reality_scan", False):
        try: os.remove(cache)
        except Exception: pass
    if os.path.exists(cache):
        try:
            age = time.time() - os.path.getmtime(cache)
            if age < 6 * 3600:
                cached = [l.split("#")[0].strip() for l in open(cache, encoding="utf-8")
                          if l.strip() and not l.startswith("#")]
                if len(cached) >= need_n:
                    info(f"using cached reality targets ({len(cached)} from {cache}, age {int(age/60)}m)")
                    return cached[:need_n]
        except Exception: pass
    pool = list(SNI_FALLBACK)
    try:
        RD_LIST = ("https://raw.githubusercontent.com/AyhanMansur/AyhanX-Fredom-Scanner/"
                   "refs/heads/main/domains.txt")
        raw = sh(f"curl -fsSL -m 15 {RD_LIST}")
        if raw:
            extra = [l.strip() for l in raw.splitlines() if l.strip() and not l.startswith("#") and "." in l]
            seen = set(pool)
            for d in extra:
                if d not in seen:
                    pool.append(d); seen.add(d)
                    if len(pool) >= 60: break
            info(f"fetched {len(extra)} extra candidates from upstream")
    except Exception: pass
    info(f"probing {len(pool)} camouflage candidates (TLS 1.3 + ALPN h2) …")
    t0 = time.time()
    results = []
    with cfut.ThreadPoolExecutor(16) as ex:
        for r in ex.map(_tls13_h2_probe, pool):
            if r: results.append(r)
    results.sort(key=lambda t: t[1])
    took = int(time.time() - t0)
    good = [d for d, _ in results]
    if not good:
        warn("no candidate answered TLS 1.3 + ALPN h2 — using built-in fallback")
        good = list(SNI_FALLBACK)
    else:
        info(f"found {len(good)} working camouflage targets in {took}s "
             f"(fastest: {good[0]} @ {results[0][1]}ms)")
    try:
        with open(cache, "w", encoding="utf-8") as f:
            f.write("# REALITY camouflage targets — auto-scanned\n")
            f.write(f"# generated {time.strftime('%Y-%m-%d %H:%M:%S')}\n")
            for d, ms in results[:need_n * 2]:
                f.write(f"{d}  # {ms}ms\n")
    except Exception: pass
    return good[:need_n]

_pre_sel = None
if A.configs:
    _pre_sel = [x.strip() for x in A.configs.split(",")]
_reality_picked = bool(_pre_sel and any(k in _pre_sel for k in ("rvpq","rxpq","rgpq","trhv","trxp","trgp")))

if _reality_picked:
    GOOD_SNI = discover_reality_targets(need_n=8)
else:
    GOOD_SNI = list(SNI_FALLBACK)
sni = lambda i: GOOD_SNI[i % len(GOOD_SNI)]

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

filtered = []
for c in SEL:
    if PANEL.supports(c[0]): filtered.append(c)
    else: warn(f"{c[1]}: {COMING_SOON} on {PANEL.name} — skipped")
SEL = filtered
if not SEL: die(f"All selected configs are {COMING_SOON} on {PANEL.name}. Use 3x-ui or Pasarguard for full support.")

if not _reality_picked and any(k in sel_keys for k in ("rvpq","rxpq","rgpq","trhv","trxp","trgp")):
    GOOD_SNI = discover_reality_targets(need_n=8)
    sni = lambda i: GOOD_SNI[i % len(GOOD_SNI)]
    head(f"REALITY camouflage targets ({len(GOOD_SNI)})")
    for d in GOOD_SNI:
        print(f"  {G}▸{N} {d}")
elif any(k in sel_keys for k in ("rvpq","rxpq","rgpq","trhv","trxp","trgp")):
    print(f"  {D}REALITY camouflage targets (auto-scanned, fastest first): "
          f"{', '.join(GOOD_SNI[:5])}{'…' if len(GOOD_SNI) > 5 else ''}{N}")

CLEAN_N = 0
if any(k in sel_keys for k in ("tch","tcht")):
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
PREF = {
    "tch":   [2083, 2053, 2087, 2096, 8443],
    "tcht":  [2087, 2053, 2083, 2096, 8443],
    "tws":   [8082, 8182, 8282, 8382, 8482],
    "twsp":  [8084, 8184, 8284, 8384, 8484],
    "twst":  [9443, 10443, 11443, 12443, 13443],
    "twstp": [9543, 10543, 11543, 12543, 13543],
    "thu":   [8086, 8186, 8286, 8386, 8486],
    "trhv":  [8446, 8546, 8646, 8746, 8846],
    "trxp":  [8447, 8547, 8647, 8747, 8847],
    "trgp":  [8448, 8548, 8648, 8748, 8848],
    "rvpq":  [443, 2443, 3443, 6443, 7443],
    "rxpq":  [8443, 2443, 3443, 5443, 6443],
    "rgpq":  [4443, 5443, 7443, 9444],
}
UDP_ONLY = set(); BOTH = set(); CDN_KEYS = {"tch", "tcht"}
MODE = A.ports or ("auto" if not INTERACTIVE else "ask")

def busy(pt, key): return owner_tcp.get(pt)
def claim(pt, key): owner_tcp[pt] = "new config"
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
        print(f"  {name:52s} port {want}"); continue
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

CLEAN = []
if CLEAN_N and CDN:
    if os.path.exists("clean-ips.txt") and os.path.getsize("clean-ips.txt") > 0:
        lst = open("clean-ips.txt", "r", encoding="utf-8").read()
        info("using local clean-ips.txt")
    else:
        lst = sh(f"curl -fsSL -m10 {REPO_RAW}/clean-ips.txt") if REPO_RAW else ""
    cand = [l.split("#")[0].strip() for l in lst.splitlines() if l.split("#")[0].strip()]
    if not cand: cand = __FALLBACK_CLEAN__
    cdn_port = next((PLAN[k]["port"] for k in CDN_KEYS
                     if k in PLAN and not PLAN[k].get("origin_rule")), None)
    if not cdn_port and any(PLAN.get(k, {}).get("origin_rule") for k in CDN_KEYS):
        cdn_port = 443
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
print(f"  panel {PANEL.name} · address {ADDR}" + (f" · IPv6 {PUB6}" if PUB6 else "") + (f" · CDN {CDN}" if CDN else ""))
for key, name, _, _ in SEL:
    if key in PLAN:
        pl = PLAN[key]
        print(f"  {G}+{N} {name:52s} port {pl['port']}"
              + (f"  (Origin Rule)" if pl.get("origin_rule") else ""))
if CLEAN: print(f"  {G}+{N} {len(CLEAN)} clean-IP configs")
print(f"  {D}existing inbounds untouched: {len(inbs)}{N}")
if A.dry_run: info("Dry run."); sys.exit(0)
if not yes("Start?", True): sys.exit(0)

# =========================================================================== builders
hx = secrets.token_hex
def x25519():
    if not XRAY: raise RuntimeError("xray binary not found — install/update Xray 26+ first")
    d = {}
    for l in sh(f"'{XRAY}' x25519").splitlines():
        k, _, v = l.partition(":"); d[k.strip()] = v.strip()
    priv = d.get("PrivateKey") or d.get("Private key")
    pub  = d.get("Password (PublicKey)") or d.get("Password") or d.get("PublicKey") or d.get("Public key")
    if not priv or not pub: raise RuntimeError("xray x25519 returned empty — update Xray-core to 26+")
    return priv, pub
def vlessenc():
    if not XRAY: raise RuntimeError("xray binary not found — install/update Xray 26+ first")
    out = sh(f"'{XRAY}' vlessenc").splitlines()
    for n, l in enumerate(out):
        if "X25519" in l and n + 2 < len(out):
            return out[n+1].split('"')[3], out[n+2].split('"')[3]
    raise RuntimeError("this Xray has no 'vlessenc' (update Xray-core to 26)")
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
FRAG = json.dumps({"tcp":[{"type":"fragment","settings":{"packets":"tlshello","lengths":["10-30"],"delays":["5-15"]}}]})
SNIFF = {"enabled": True, "destOverride": ["http","tls","quic"], "metadataOnly": False, "routeOnly": True}
PATHS = {}

def _finalmask_sudoku():
    return {"tcp":[{"type":"sudoku","settings":{"password":hx(16),"ascii":"prefer_entropy",
                                                 "paddingMin":2,"paddingMax":7}}]}
def pq(stream):
    s = dict(stream); s["finalmask"] = _finalmask_sudoku(); return s

def tch_stream():
    PATHS["tch"] = "/" + hx(5)
    return {"network": "httpupgrade", "security": "none", "externalProxy": [],
            "httpupgradeSettings": {"acceptProxyProtocol": False,
                                    "path": PATHS["tch"], "host": "", "headers": {}}}
def tcht_stream():
    PATHS["tcht"] = "/" + hx(5)
    return tls_stream("httpupgrade", {"httpupgradeSettings": {"acceptProxyProtocol": False,
                                                              "path": PATHS["tcht"], "host": "", "headers": {}}},
                      ["http/1.1"])
def tws_stream():
    PATHS["tws"] = "/" + hx(5)
    return {"network": "ws", "security": "none", "externalProxy": [],
            "wsSettings": {"acceptProxyProtocol": False, "path": PATHS["tws"],
                           "host": "", "headers": {}, "heartbeatPeriod": 30}}
def twsp_stream():
    PATHS["twsp"] = "/" + hx(5)
    base = {"network": "ws", "security": "none", "externalProxy": [],
            "wsSettings": {"acceptProxyProtocol": False, "path": PATHS["twsp"],
                           "host": "", "headers": {}, "heartbeatPeriod": 30}}
    return pq(base)
def twst_stream():
    PATHS["twst"] = "/" + hx(5)
    return tls_stream("ws", {"wsSettings": {"acceptProxyProtocol": False, "path": PATHS["twst"],
                                            "host": "", "headers": {}, "heartbeatPeriod": 30}},
                      ["http/1.1"])
def twstp_stream():
    PATHS["twstp"] = "/" + hx(5)
    base = tls_stream("ws", {"wsSettings": {"acceptProxyProtocol": False, "path": PATHS["twstp"],
                                            "host": "", "headers": {}, "heartbeatPeriod": 30}},
                      ["http/1.1"])
    return pq(base)
def thu_stream():
    PATHS["thu"] = "/" + hx(5)
    return {"network": "httpupgrade", "security": "none", "externalProxy": [],
            "httpupgradeSettings": {"acceptProxyProtocol": False,
                                    "path": PATHS["thu"], "host": "", "headers": {}}}

BUILD = {
    "tch":   ("trojan", lambda: ({"clients": []}, tch_stream())),
    "tcht":  ("trojan", lambda: ({"clients": []}, tcht_stream())),
    "tws":   ("trojan", lambda: ({"clients": []}, tws_stream())),
    "twsp":  ("trojan", lambda: ({"clients": []}, twsp_stream())),
    "twst":  ("trojan", lambda: ({"clients": []}, twst_stream())),
    "twstp": ("trojan", lambda: ({"clients": []}, twstp_stream())),
    "thu":   ("trojan", lambda: ({"clients": []}, thu_stream())),
    "trhv":  ("trojan", lambda: ({"clients": []}, reality("httpupgrade", sni(6),
                                                          {"httpupgradeSettings": {"acceptProxyProtocol": False,
                                                                                   "path": "/" + hx(5),
                                                                                   "host": "", "headers": {}}}))),
    "trxp":  ("trojan", lambda: ({"clients": []}, reality("xhttp", sni(7), {"xhttpSettings": XH()}))),
    "trgp":  ("trojan", lambda: ({"clients": []}, reality("grpc", sni(8),
                                                          {"grpcSettings": {"serviceName": hx(4),
                                                                            "authority": "",
                                                                            "multiMode": True}}))),
    "rvpq":  ("vless", lambda: ({"clients": [], "decryption": "none", "fallbacks": []},
                                pq(reality("tcp", sni(3), TCP)))),
    "rxpq":  ("vless", lambda: ({"clients": [], "decryption": "none", "fallbacks": []},
                                pq(reality("xhttp", sni(4), {"xhttpSettings": XH()})))),
    "rgpq":  ("vless", lambda: ({"clients": [], "decryption": "none", "fallbacks": []},
                                pq(reality("grpc", sni(5), {"grpcSettings": {"serviceName": hx(4),
                                                                              "authority": "",
                                                                              "multiMode": True}})))),
}
REMARK = {
    "tch":   f"{BRAND}👾Trojan • HU • CDN",
    "tcht":  f"{BRAND}👾Trojan • HU • CDN • TLS",
    "tws":   f"{BRAND}👾Trojan • WS",
    "twsp":  f"{BRAND}🧬Trojan • WS • PQ",
    "twst":  f"{BRAND}👾Trojan • WS • TLS",
    "twstp": f"{BRAND}🧬Trojan • WS • TLS • PQ",
    "thu":   f"{BRAND}👾Trojan • HU • Plain",
    "trhv":  f"{BRAND}👾Trojan • REALITY • HU",
    "trxp":  f"{BRAND}👾Trojan • REALITY • XH",
    "trgp":  f"{BRAND}👾Trojan • REALITY • gRPC",
    "rvpq":  f"{BRAND}🧬Reality • Vision • PQ",
    "rxpq":  f"{BRAND}🧬Reality • XHTTP • PQ",
    "rgpq":  f"{BRAND}🧬Reality • gRPC • PQ",
}
def cdn_host(name, addr, key):
    cp = PLAN[key].get("client_port", 0)
    return (name, addr, {"sni": CDN, "hostHeader": CDN, "finalMask": FRAG, **({"port": cp} if cp else {})})
def HOSTS(key):
    v6 = lambda n, ex={}: [(f"{BRAND}6️⃣{n} • IPv6", PUB6, ex)] if PUB6 else []
    if key == "tch":
        return [cdn_host(f"{BRAND}☁️CDN • HU", CDN, "tch")]
    if key == "tcht":
        h = [] if PLAN["tcht"].get("origin_rule") else [(f"{BRAND}👾Trojan • HU • TLS", ADDR,
                                                         {"sni": DOMAIN, "hostHeader": DOMAIN})]
        return h + ([cdn_host(f"{BRAND}☁️CDN • HU • TLS", CDN, "tcht")] if CDN else [])
    if key == "tws":   return [(f"{BRAND}👾Trojan • WS", ADDR, {})] + v6("Trojan • WS")
    if key == "twsp":  return [(f"{BRAND}🧬Trojan • WS • PQ", ADDR, {})] + v6("Trojan • WS • PQ")
    if key == "twst":  return [(f"{BRAND}👾Trojan • WS • TLS", ADDR, {"sni": DOMAIN})] + v6("Trojan • WS • TLS", {"sni": DOMAIN})
    if key == "twstp": return [(f"{BRAND}🧬Trojan • WS • TLS • PQ", ADDR, {"sni": DOMAIN})] + v6("Trojan • WS • TLS • PQ", {"sni": DOMAIN})
    if key == "thu":   return [(f"{BRAND}👾Trojan • HU • Plain", ADDR, {})] + v6("Trojan • HU • Plain")
    if key == "trhv":  return [(f"{BRAND}👾Trojan • REALITY • HU", ADDR, {})] + v6("Trojan • REALITY • HU")
    if key == "trxp":  return [(f"{BRAND}👾Trojan • REALITY • XH", ADDR, {})] + v6("Trojan • REALITY • XH")
    if key == "trgp":  return [(f"{BRAND}👾Trojan • REALITY • gRPC", ADDR, {})] + v6("Trojan • REALITY • gRPC")
    if key == "rvpq":  return [(f"{BRAND}🧬Reality • Vision • PQ", ADDR, {})] + v6("Reality • Vision • PQ")
    if key == "rxpq":  return [(f"{BRAND}🧬Reality • XHTTP • PQ", ADDR, {})] + v6("Reality • XHTTP • PQ")
    if key == "rgpq":  return [(f"{BRAND}🧬Reality • gRPC • PQ", ADDR, {})] + v6("Reality • gRPC • PQ")
    return []

# =========================================================================== apply
head("Adding")
bak = PANEL.db_backup()
if bak: info("backup:", bak)
try: emails = {c.get("email") or c.get("username") for c in (PANEL.clients_list() or [])}
except Exception: emails = set()
EMAIL = A.email or f"pro_{hx(2)}"
while EMAIL in emails: EMAIL = f"{EMAIL}_{hx(1)}"
SUBID = "".join(secrets.choice(string.ascii_lowercase + string.digits) for _ in range(16))
PASSWORD = base64.b64encode(secrets.token_bytes(32)).decode()

def xray_ok(pt):
    for _ in range(10):
        time.sleep(1.5)
        if f":{pt}" in sh(f"ss -H -tlnp 'sport = :{pt}'"):
            return True
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
    if xray_ok(pt):
        added.append((key, iid)); info(f"added {name:52s} port {pt}")
    else:
        warn(f"{name}: engine rejected — removed")
        PANEL.detach_client(EMAIL, [iid]); PANEL.del_inbound(iid); PANEL.restart(); time.sleep(3)
if not added: die("Nothing could be added.")
ADDED = dict(added)

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

clean_key = next((k for k in CDN_KEYS if k in ADDED and not PLAN[k].get("origin_rule")), None) \
            or next((k for k in CDN_KEYS if k in ADDED), None)
n_links = 0
for order, (key, iid) in enumerate(added):
    hosts = HOSTS(key)
    if key == clean_key and CLEAN:
        hosts += [cdn_host(f"{BRAND}🧊Clean • {i:02d}", a, key) for i, a in enumerate(CLEAN, 1)]
    if not use_hosts:
        hosts = [h for h in hosts if h[1] == CDN or h[1] in CLEAN] if key in CDN_KEYS else []
    for i, (rem, addr, extra) in enumerate(hosts):
        if not addr: continue
        r = PANEL.add_host(iid, rem, addr, extra, i)
        n_links += bool(r)
        if not r: warn(f"host {rem}: rejected")

ufw = sh("ufw status 2>/dev/null | head -1")
if "Status: active" in ufw:
    for key, _ in added:
        pt = PLAN[key]["port"]; sh(f"ufw allow {pt}/tcp")
    info("ufw: ports opened")

if not A.no_bbr and "bbr" not in sh("sysctl -n net.ipv4.tcp_congestion_control"):
    if yes("Enable BBR?", True):
        open("/etc/sysctl.d/99-bbr.conf","w").write(
            "net.core.default_qdisc=fq\nnet.ipv4.tcp_congestion_control=bbr\n")
        sh("modprobe tcp_bbr; sysctl --system")
        info("BBR:", sh("sysctl -n net.ipv4.tcp_congestion_control"))

info("restarting engine ...")
PANEL.restart(); time.sleep(4)

SUB, JSUB = PANEL.sub_urls(EMAIL if PANEL.name in ("Marzban", "Pasarguard") else SUBID)
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
        pt = PLAN[key]["port"]
        live = f":{pt}" in sh(f"ss -H -tlnp 'sport = :{pt}'")
        print(f"  {G+'OK  '+N if live else R+'FAIL'+N} {REMARK[key]} port {pt}")
        okc += live
    info(f"{okc}/{len(added)} ports listening (e2e skipped on {PANEL.name})")

# =========================================================================== done
head("Done")
print(f"  panel        {PANEL.name}  ({len(added)} inbounds, {n_links} links, {len(inbs)} existing untouched)")
print(f"  client       {B}{EMAIL}{N}")
if SUB and SUB != "(n/a)": print(f"  subscription {B}{SUB}{N}")
if JSUB and JSUB != "(n/a)": print(f"  JSON sub     {B}{JSUB}{N}")
ports_txt = ", ".join(f"{PLAN[k]['port']}/tcp" for k, _ in added)
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

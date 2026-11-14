#!/usr/bin/env python3
"""تشغيل JavaScript داخل WebView التطبيق (نسخة debug) عبر DevTools — لتصوير مقاطع المميزات فقط.
الاستخدام: python3 cdp.py "التعبير"  → يطبع النتيجة JSON"""
import json, subprocess, sys, time, urllib.request
import websocket  # pip install websocket-client

def sock():
    out = subprocess.run(["adb", "shell", "cat /proc/net/unix"], capture_output=True, text=True).stdout
    names = sorted({l.split("@")[-1].strip() for l in out.splitlines() if "webview_devtools_remote" in l})
    return names[-1] if names else None

def target():
    s = sock()
    if not s: return None
    subprocess.run(["adb", "forward", "tcp:9222", "localabstract:" + s], capture_output=True)
    for _ in range(10):
        try:
            pages = json.load(urllib.request.urlopen("http://127.0.0.1:9222/json", timeout=3))
            pages = [p for p in pages if p.get("type") == "page" and p.get("webSocketDebuggerUrl")]
            pages.sort(key=lambda p: ("mushaf" not in p.get("url", ""), ))
            if pages: return pages[0]["webSocketDebuggerUrl"]
        except Exception:
            time.sleep(1)
    return None

def ev(expr):
    u = target()
    if not u: return {"err": "no webview"}
    ws = websocket.create_connection(u, timeout=20, suppress_origin=True)
    ws.send(json.dumps({"id": 1, "method": "Runtime.evaluate",
                        "params": {"expression": expr, "returnByValue": True, "awaitPromise": True}}))
    while True:
        m = json.loads(ws.recv())
        if m.get("id") == 1:
            ws.close()
            r = m.get("result", {}).get("result", {})
            return r.get("value", r.get("description"))

if __name__ == "__main__":
    print(json.dumps(ev(sys.argv[1]), ensure_ascii=False))

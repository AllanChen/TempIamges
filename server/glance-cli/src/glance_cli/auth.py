"""Browser sign-in with a loopback callback and one-use PKCE code."""

import base64
from hashlib import sha256
from http.server import BaseHTTPRequestHandler, HTTPServer
import json
import secrets
from datetime import datetime, timedelta, timezone
from urllib.parse import parse_qs, urlencode, urlparse
from urllib.request import Request, urlopen
import webbrowser

from .api import BASE_URL, USER_AGENT, APIError, request
from .registry import clear_session, read_mock_token, read_session, save_session


def login() -> dict:
    mock_token = read_mock_token()
    if mock_token:
        session = {
            "token": mock_token,
            "email": "mock@glance.local",
            "expiresAt": (datetime.now(timezone.utc) + timedelta(days=30)).isoformat(),
        }
        save_session(session)
        return session
    state = secrets.token_urlsafe(24)
    verifier = secrets.token_urlsafe(48)
    challenge = base64.urlsafe_b64encode(sha256(verifier.encode()).digest()).rstrip(b"=").decode()
    received: dict[str, str] = {}

    class Callback(BaseHTTPRequestHandler):
        def do_GET(self) -> None:
            parsed = urlparse(self.path)
            query = parse_qs(parsed.query)
            valid = (parsed.path == "/callback" and query.get("state", [""])[0] == state)
            if valid:
                received["code"] = query.get("code", [""])[0]
                received["error"] = query.get("error", [""])[0]
            self.send_response(200 if valid else 400)
            self.send_header("Content-Type", "text/plain; charset=utf-8")
            self.end_headers()
            self.wfile.write(("可以返回终端。" if valid else "无效的登录回调。").encode())

        def log_message(self, *_args: object) -> None:
            pass

    server = HTTPServer(("127.0.0.1", 0), Callback)
    server.timeout = 5
    redirect = f"http://127.0.0.1:{server.server_port}/callback"
    url = BASE_URL + "/api/v2/developer/auth/start?" + urlencode({
        "redirect_uri": redirect, "state": state, "code_challenge": challenge})
    print("正在打开浏览器登录。如果没有自动打开，请访问：\n" + url)
    webbrowser.open(url)
    for _ in range(36):
        server.handle_request()
        if "code" in received:
            break
    server.server_close()
    if received.get("error"):
        raise APIError(received["error"])
    if not received.get("code"):
        raise APIError("登录超时，请重试")
    payload = json.dumps({"code": received["code"], "code_verifier": verifier}).encode()
    req = Request(BASE_URL + "/api/v2/developer/auth/exchange", data=payload,
                  headers={"Content-Type": "application/json", "User-Agent": USER_AGENT}, method="POST")
    with urlopen(req, timeout=20) as response:
        envelope = json.load(response)
    if not envelope.get("success"):
        raise APIError(envelope.get("error", {}).get("message", "登录失败"))
    session = envelope["result"]
    save_session(session)
    return session


def logout() -> None:
    if read_session():
        try:
            request("POST", "/api/v2/developer/auth/logout", {})
        finally:
            clear_session()
    else:
        clear_session()

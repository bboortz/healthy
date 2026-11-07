"""Test servers for hc: plain HTTP on :8080, TLS 1.3 on :8443 (cert/key from the cwd)."""
import http.server
import ssl
import threading


class H(http.server.SimpleHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def do_GET(self):
        if self.path == "/teapot":
            self.send_response(418)
            self.end_headers()
        elif self.path == "/redir":
            self.send_response(302)
            self.send_header("Location", "/health")
            self.end_headers()
        elif self.path == "/echo-host":
            b = (self.headers.get("Host") or "").encode()
            self.send_response(200)
            self.send_header("Content-Length", str(len(b)))
            self.end_headers()
            self.wfile.write(b)
        else:
            super().do_GET()


class Server(http.server.ThreadingHTTPServer):
    def handle_error(self, request, client_address):
        pass  # handshake-only checks (tls://) close without sending a request: not an error


def serve(port, use_tls):
    s = Server(
        ("127.0.0.1", port), lambda *a, **k: H(*a, directory="www", **k)
    )
    if use_tls:
        c = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        c.minimum_version = ssl.TLSVersion.TLSv1_3
        c.load_cert_chain("srv.pem", "srv.key")
        s.socket = c.wrap_socket(s.socket, server_side=True)
    s.serve_forever()


threading.Thread(target=serve, args=(8080, False), daemon=True).start()
serve(8443, True)

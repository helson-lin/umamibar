#!/usr/bin/env python3
"""Local fixture service for scripts/visual-check.swift. Never uses real credentials."""
import argparse
import json
from http.server import BaseHTTPRequestHandler, HTTPServer

SITES = [{"id": "1", "name": "Fanbar 软件", "domain": "getfanbar.com"},
         {"id": "2", "name": "framecho", "domain": "getframecho.com"},
         {"id": "3", "name": "个人博客", "domain": "blog.example.com"},
         {"id": "4", "name": "产品文档", "domain": "docs.example.com"}]

class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.headers.get("Authorization") != "Bearer test-key":
            self.send_response(401)
            self.end_headers()
            return
        if self.path.split("?")[0] == "/api/websites":
            value = {"data": SITES, "count": len(SITES)}
        elif self.path.split("?")[0].endswith("/pageviews"):
            value = {"sessions": []}
        elif self.path.split("?")[0].endswith("/active"):
            value = {"visitors": 2}
        elif self.path.split("?")[0].endswith("/stats"):
            value = {"visitors": 3, "pageviews": 5, "visits": 4, "bounces": 1, "totaltime": 60}
        else:
            value = []
        data = json.dumps(value).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)
    def log_message(self, *_):
        pass

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--port", type=int, default=8768)
    HTTPServer(("127.0.0.1", parser.parse_args().port), Handler).serve_forever()

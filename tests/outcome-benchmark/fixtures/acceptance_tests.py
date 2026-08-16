#!/usr/bin/env python3
"""Black-box HTTP acceptance tests for the outcome-benchmark's pinned URL
shortener contract. Stdlib only. Run directly against a server already
listening at BASE_URL: python3 acceptance_tests.py -v
"""

import json
import unittest
import urllib.error
import urllib.request

BASE_URL = "http://localhost:8000"


def _request(method, path, body_bytes=None):
    req = urllib.request.Request(
        BASE_URL + path,
        data=body_bytes,
        headers={"Content-Type": "application/json"} if body_bytes is not None else {},
        method=method,
    )
    try:
        with urllib.request.urlopen(req) as resp:
            return resp.status, resp.read()
    except urllib.error.HTTPError as e:
        code, body = e.code, e.read()
        e.close()
        return code, body


def _post_link(url):
    """POST {"url": url} to BASE_URL/api/links.
    Returns (status_code, parsed_json_body); body is {} if the response
    wasn't valid JSON."""
    status, body = _request("POST", "/api/links", json.dumps({"url": url}).encode("utf-8"))
    return status, _parse_json(body)


def _post_raw(body_bytes):
    """POST raw bytes (not necessarily valid JSON) to BASE_URL/api/links.
    Returns (status_code, parsed_json_body_or_empty)."""
    status, body = _request("POST", "/api/links", body_bytes)
    return status, _parse_json(body)


def _parse_json(body_bytes):
    try:
        return json.loads(body_bytes) if body_bytes else {}
    except json.JSONDecodeError:
        return {}


class _NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *args, **kwargs):
        return None


_NO_REDIRECT_OPENER = urllib.request.build_opener(_NoRedirect)


def _get(path):
    """GET BASE_URL + path, redirects NOT followed.
    Returns (status_code, response_headers)."""
    req = urllib.request.Request(BASE_URL + path, method="GET")
    try:
        with _NO_REDIRECT_OPENER.open(req) as resp:
            return resp.status, dict(resp.headers)
    except urllib.error.HTTPError as e:
        code, headers = e.code, dict(e.headers)
        e.close()
        return code, headers


class AcceptanceTests(unittest.TestCase):
    def test_create_then_redirect(self):
        status, body = _post_link("https://example.com/target-one")
        self.assertEqual(status, 201)
        code = body.get("code")
        self.assertTrue(code, "response body must include a non-empty 'code'")

        redirect_status, headers = _get("/" + code)
        self.assertEqual(redirect_status, 302)
        self.assertEqual(headers.get("Location"), "https://example.com/target-one")

    def test_unknown_code_returns_404(self):
        status, _ = _get("/this-code-was-never-created")
        self.assertEqual(status, 404)

    def test_malformed_create_request(self):
        status, _ = _post_raw(b"not valid json")
        self.assertTrue(400 <= status < 500, "expected 4xx for invalid JSON, got %r" % status)

        status2, _ = _post_raw(json.dumps({}).encode("utf-8"))
        self.assertTrue(400 <= status2 < 500, "expected 4xx for missing url, got %r" % status2)

    def test_duplicate_url_each_code_redirects_correctly(self):
        status_a, body_a = _post_link("https://example.com/duplicate-target")
        status_b, body_b = _post_link("https://example.com/duplicate-target")
        self.assertEqual(status_a, 201)
        self.assertEqual(status_b, 201)

        for body in (body_a, body_b):
            code = body.get("code")
            self.assertTrue(code)
            redirect_status, headers = _get("/" + code)
            self.assertEqual(redirect_status, 302)
            self.assertEqual(headers.get("Location"), "https://example.com/duplicate-target")

    def test_code_collision_safety(self):
        created = {}
        for i in range(25):
            url = "https://example.com/collision-check-%d" % i
            status, body = _post_link(url)
            self.assertEqual(status, 201)
            code = body.get("code")
            self.assertTrue(code)
            if code in created:
                self.assertEqual(
                    created[code], url,
                    "code %r was returned for two different URLs" % code,
                )
            created[code] = url

        for code, url in created.items():
            redirect_status, headers = _get("/" + code)
            self.assertEqual(redirect_status, 302)
            self.assertEqual(headers.get("Location"), url)


if __name__ == "__main__":
    unittest.main()

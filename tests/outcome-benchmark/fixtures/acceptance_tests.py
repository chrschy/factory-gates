#!/usr/bin/env python3
"""Black-box HTTP acceptance tests for the outcome-benchmark's pinned URL shortener contract.

Stdlib only. Run directly against a server already listening at BASE_URL:
python3 acceptance_tests.py -v
"""

import email.message
import json
import unittest
import urllib.error
import urllib.request

BASE_URL = "http://localhost:8000"


def _request(method: str, path: str, body_bytes: bytes | None = None) -> tuple[int, bytes]:
    """Send an HTTP request and return its status code and raw response body."""
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


def _post_link(url: str) -> tuple[int, dict]:
    """POST {"url": url} to BASE_URL/api/links and return (status_code, parsed_json_body)."""
    status, body = _request("POST", "/api/links", json.dumps({"url": url}).encode("utf-8"))
    return status, _parse_json(body)


def _post_raw(body_bytes: bytes) -> tuple[int, dict]:
    """POST raw bytes (not necessarily valid JSON) to BASE_URL/api/links."""
    status, body = _request("POST", "/api/links", body_bytes)
    return status, _parse_json(body)


def _parse_json(body_bytes: bytes) -> dict:
    """Parse response body bytes as JSON, returning {} if empty or not valid JSON."""
    try:
        return json.loads(body_bytes) if body_bytes else {}
    except json.JSONDecodeError:
        return {}


class _NoRedirect(urllib.request.HTTPRedirectHandler):
    """Opener handler that disables following HTTP redirects."""

    def redirect_request(self, *args: object, **kwargs: object) -> None:
        """Suppress redirect following by always returning None."""
        return None


_NO_REDIRECT_OPENER = urllib.request.build_opener(_NoRedirect)


def _get(path: str) -> tuple[int, email.message.Message]:
    """GET BASE_URL + path without following redirects, returning (status_code, headers)."""
    req = urllib.request.Request(BASE_URL + path, method="GET")
    try:
        with _NO_REDIRECT_OPENER.open(req) as resp:
            return resp.status, resp.headers
    except urllib.error.HTTPError as e:
        code, headers = e.code, e.headers
        e.close()
        return code, headers


class AcceptanceTests(unittest.TestCase):
    """Black-box HTTP contract tests for the pinned URL shortener acceptance criteria."""

    def test_create_then_redirect(self) -> None:
        """Verify a created link's code redirects to the original target URL."""
        status, body = _post_link("https://example.com/target-one")
        self.assertEqual(status, 201)
        code = body.get("code")
        self.assertTrue(code, "response body must include a non-empty 'code'")
        assert isinstance(code, str)

        redirect_status, headers = _get("/" + code)
        self.assertEqual(redirect_status, 302)
        self.assertEqual(headers.get("Location"), "https://example.com/target-one")

    def test_unknown_code_returns_404(self) -> None:
        """Verify a GET for a code that was never created returns 404."""
        status, _ = _get("/this-code-was-never-created")
        self.assertEqual(status, 404)

    def test_malformed_create_request(self) -> None:
        """Verify malformed or incomplete create requests are rejected with 4xx."""
        status, _ = _post_raw(b"not valid json")
        self.assertTrue(400 <= status < 500, f"expected 4xx for invalid JSON, got {status!r}")

        status2, _ = _post_raw(json.dumps({}).encode("utf-8"))
        self.assertTrue(400 <= status2 < 500, f"expected 4xx for missing url, got {status2!r}")

    def test_duplicate_url_each_code_redirects_correctly(self) -> None:
        """Verify submitting the same URL twice yields two codes that both redirect correctly."""
        status_a, body_a = _post_link("https://example.com/duplicate-target")
        status_b, body_b = _post_link("https://example.com/duplicate-target")
        self.assertEqual(status_a, 201)
        self.assertEqual(status_b, 201)

        for body in (body_a, body_b):
            code = body.get("code")
            self.assertTrue(code)
            assert isinstance(code, str)
            redirect_status, headers = _get("/" + code)
            self.assertEqual(redirect_status, 302)
            self.assertEqual(headers.get("Location"), "https://example.com/duplicate-target")

    def test_code_collision_safety(self) -> None:
        """Verify many distinct URLs never receive colliding codes and all redirect correctly."""
        created: dict[str, str] = {}
        for i in range(25):
            url = f"https://example.com/collision-check-{i}"
            status, body = _post_link(url)
            self.assertEqual(status, 201)
            code = body.get("code")
            self.assertTrue(code)
            assert isinstance(code, str)
            if code in created:
                self.assertEqual(
                    created[code],
                    url,
                    f"code {code!r} was returned for two different URLs",
                )
            created[code] = url

        for code, url in created.items():
            redirect_status, headers = _get("/" + code)
            self.assertEqual(redirect_status, 302)
            self.assertEqual(headers.get("Location"), url)


if __name__ == "__main__":
    unittest.main()

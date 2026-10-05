package main

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func TestRoutes(t *testing.T) {
	h := newRouter(Config{ServiceName: "demo-app", Version: "test"})
	cases := []struct {
		path string
		code int
		want string
	}{
		{"/api/v1/info", 200, `"test"`},
		{"/api/v1/work?ms=1", 200, `"slept_ms":1`},
		{"/api/v1/work?ms=5000", 400, "ms must be"},
		// Internal endpoints are not served on the public listener.
		{"/metrics", 404, ""},
		{"/healthz", 404, ""},
		{"/nope", 404, ""},
	}
	for _, c := range cases {
		t.Run(c.path, func(t *testing.T) {
			rec := httptest.NewRecorder()
			h.ServeHTTP(rec, httptest.NewRequest(http.MethodGet, c.path, nil))
			if rec.Code != c.code {
				t.Fatalf("code = %d, want %d", rec.Code, c.code)
			}
			if !strings.Contains(rec.Body.String(), c.want) {
				t.Fatalf("body %q missing %q", rec.Body.String(), c.want)
			}
		})
	}
}

func TestAdminRoutes(t *testing.T) {
	newRouter(Config{}) // marks ready
	h := newAdminRouter()
	for path, want := range map[string]string{
		"/healthz": `"ok"`,
		"/readyz":  `"ready"`,
		"/metrics": "go_goroutines",
	} {
		rec := httptest.NewRecorder()
		h.ServeHTTP(rec, httptest.NewRequest(http.MethodGet, path, nil))
		if rec.Code != 200 || !strings.Contains(rec.Body.String(), want) {
			t.Errorf("%s: code %d, body missing %q", path, rec.Code, want)
		}
	}
}

func TestSecurityHeaders(t *testing.T) {
	// Checked on a 404 too: the ingress forwards unknown paths to this listener.
	for _, path := range []string{"/api/v1/info", "/does-not-exist"} {
		rec := httptest.NewRecorder()
		newRouter(Config{}).ServeHTTP(rec, httptest.NewRequest(http.MethodGet, path, nil))
		for _, h := range []string{"X-Content-Type-Options", "X-Frame-Options", "Content-Security-Policy", "Strict-Transport-Security"} {
			if rec.Header().Get(h) == "" {
				t.Errorf("%s: missing header %s", path, h)
			}
		}
	}
}

func TestReadinessDrains(t *testing.T) {
	newRouter(Config{})
	h := newAdminRouter()
	ready.Store(false)
	defer ready.Store(true)
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/readyz", nil))
	if rec.Code != http.StatusServiceUnavailable {
		t.Fatalf("code = %d, want 503", rec.Code)
	}
	var body map[string]string
	_ = json.NewDecoder(rec.Body).Decode(&body)
	if body["status"] != "draining" {
		t.Fatalf("status = %q", body["status"])
	}
}

package main

import (
	"encoding/json"
	"net/http"
	"strconv"
	"sync/atomic"
	"time"

	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/collectors"
	"github.com/prometheus/client_golang/prometheus/promauto"
	"github.com/prometheus/client_golang/prometheus/promhttp"
	"go.opentelemetry.io/contrib/instrumentation/net/http/otelhttp"
	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/attribute"
)

var (
	reg = prometheus.NewRegistry()

	httpRequests = promauto.With(reg).NewCounterVec(prometheus.CounterOpts{
		Name: "demo_http_requests_total",
		Help: "HTTP requests by route and status code.",
	}, []string{"route", "code"})

	httpDuration = promauto.With(reg).NewHistogramVec(prometheus.HistogramOpts{
		Name:    "demo_http_request_duration_seconds",
		Help:    "HTTP request latency by route.",
		Buckets: prometheus.DefBuckets,
	}, []string{"route"})
)

func init() {
	reg.MustRegister(collectors.NewGoCollector(), collectors.NewProcessCollector(collectors.ProcessCollectorOpts{}))
}

// ready flips to false during shutdown so the readiness probe drains traffic first.
var ready atomic.Bool

// newRouter is the public listener: API routes only. Anything else is a 404 that still
// carries the security headers, because the ingress forwards every path here.
func newRouter(cfg Config) http.Handler {
	ready.Store(true)
	mux := http.NewServeMux()
	mux.Handle("GET /api/v1/info", instrument("info", infoHandler(cfg)))
	mux.Handle("GET /api/v1/work", instrument("work", http.HandlerFunc(work)))
	return securityHeaders(otelhttp.NewHandler(mux, "http.server"))
}

// newAdminRouter is the internal listener: probes and metrics. It is never routed by the
// ingress; the Service exposes it on a separate port that NetworkPolicy opens only to
// the monitoring namespace (and kubelet probes reach the pod directly).
func newAdminRouter() http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("GET /healthz", healthz)
	mux.HandleFunc("GET /readyz", readyz)
	mux.Handle("GET /metrics", promhttp.HandlerFor(reg, promhttp.HandlerOpts{}))
	return mux
}

func healthz(w http.ResponseWriter, _ *http.Request) {
	writeJSON(w, http.StatusOK, map[string]string{"status": "ok"})
}

func readyz(w http.ResponseWriter, _ *http.Request) {
	if !ready.Load() {
		writeJSON(w, http.StatusServiceUnavailable, map[string]string{"status": "draining"})
		return
	}
	writeJSON(w, http.StatusOK, map[string]string{"status": "ready"})
}

func infoHandler(cfg Config) http.HandlerFunc {
	return func(w http.ResponseWriter, _ *http.Request) {
		writeJSON(w, http.StatusOK, map[string]string{"service": cfg.ServiceName, "version": cfg.Version})
	}
}

// work simulates a request with a child span so traces show more than one hop.
func work(w http.ResponseWriter, r *http.Request) {
	ms, err := strconv.Atoi(r.URL.Query().Get("ms"))
	if err != nil || ms < 0 {
		ms = 25
	}
	if ms > 2000 {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "ms must be <= 2000"})
		return
	}
	_, span := otel.Tracer("demo-app").Start(r.Context(), "simulated-work")
	span.SetAttributes(attribute.Int("work.ms", ms))
	time.Sleep(time.Duration(ms) * time.Millisecond)
	span.End()
	writeJSON(w, http.StatusOK, map[string]int{"slept_ms": ms})
}

type statusRecorder struct {
	http.ResponseWriter
	code int
}

func (s *statusRecorder) WriteHeader(code int) {
	s.code = code
	s.ResponseWriter.WriteHeader(code)
}

func instrument(route string, next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()
		rec := &statusRecorder{ResponseWriter: w, code: http.StatusOK}
		next.ServeHTTP(rec, r)
		httpRequests.WithLabelValues(route, strconv.Itoa(rec.code)).Inc()
		httpDuration.WithLabelValues(route).Observe(time.Since(start).Seconds())
	})
}

func securityHeaders(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		h := w.Header()
		h.Set("X-Content-Type-Options", "nosniff")
		h.Set("X-Frame-Options", "DENY")
		h.Set("Strict-Transport-Security", "max-age=31536000; includeSubDomains")
		h.Set("Referrer-Policy", "no-referrer")
		h.Set("Content-Security-Policy", "default-src 'none'; frame-ancestors 'none'")
		h.Set("Cache-Control", "no-store")
		h.Set("Cross-Origin-Resource-Policy", "same-origin")
		h.Set("Permissions-Policy", "geolocation=(), camera=(), microphone=()")
		next.ServeHTTP(w, r)
	})
}

func writeJSON(w http.ResponseWriter, code int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(code)
	_ = json.NewEncoder(w).Encode(v)
}

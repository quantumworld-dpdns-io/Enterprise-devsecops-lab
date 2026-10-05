// Command demo-app is a deliberately small HTTP service used to exercise the
// platform: health probes, Prometheus metrics, OpenTelemetry traces and a
// graceful shutdown path that respects Kubernetes termination.
package main

import (
	"context"
	"errors"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"
)

func main() {
	logger := slog.New(slog.NewJSONHandler(os.Stdout, nil))
	slog.SetDefault(logger)

	cfg := loadConfig()
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()

	shutdownTracing, err := setupTracing(ctx, cfg)
	if err != nil {
		logger.Error("tracing setup failed", "err", err)
		os.Exit(1)
	}
	defer func() {
		c, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()
		_ = shutdownTracing(c)
	}()

	srv := &http.Server{
		Addr:              cfg.Addr,
		Handler:           newRouter(cfg),
		ReadHeaderTimeout: 5 * time.Second,
		ReadTimeout:       10 * time.Second,
		WriteTimeout:      10 * time.Second,
		IdleTimeout:       60 * time.Second,
	}

	admin := &http.Server{
		Addr:              cfg.AdminAddr,
		Handler:           newAdminRouter(),
		ReadHeaderTimeout: 5 * time.Second,
		ReadTimeout:       10 * time.Second,
		WriteTimeout:      10 * time.Second,
	}

	for name, s := range map[string]*http.Server{"public": srv, "admin": admin} {
		go func() {
			logger.Info("listening", "listener", name, "addr", s.Addr, "version", cfg.Version)
			if err := s.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
				logger.Error("server failed", "listener", name, "err", err)
				stop()
			}
		}()
	}

	<-ctx.Done()
	// Fail readiness first so the Service stops routing here, then drain.
	ready.Store(false)
	logger.Info("shutting down")
	time.Sleep(cfg.DrainDelay)
	c, cancel := context.WithTimeout(context.Background(), 15*time.Second)
	defer cancel()
	if err := srv.Shutdown(c); err != nil {
		logger.Error("graceful shutdown failed", "err", err)
	}
	_ = admin.Shutdown(c) // admin last, so probes and metrics outlive the public drain
}

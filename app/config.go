package main

import (
	"os"
	"time"
)

// Config is read from the environment so the same image runs in every environment.
type Config struct {
	Addr         string // public listener (API), routed by the ingress
	AdminAddr    string // internal listener (probes, metrics), never routed by the ingress
	Version      string
	ServiceName  string
	OTLPEndpoint string        // empty disables trace export
	DrainDelay   time.Duration // time between failing readiness and closing listeners
}

func loadConfig() Config {
	drain, err := time.ParseDuration(getenv("APP_DRAIN_DELAY", "5s"))
	if err != nil {
		drain = 5 * time.Second
	}
	return Config{
		Addr:         getenv("APP_ADDR", ":8080"),
		AdminAddr:    getenv("APP_ADMIN_ADDR", ":9090"),
		Version:      getenv("APP_VERSION", "dev"),
		ServiceName:  getenv("OTEL_SERVICE_NAME", "demo-app"),
		OTLPEndpoint: os.Getenv("OTEL_EXPORTER_OTLP_ENDPOINT"),
		DrainDelay:   drain,
	}
}

func getenv(key, def string) string {
	if v, ok := os.LookupEnv(key); ok && v != "" {
		return v
	}
	return def
}

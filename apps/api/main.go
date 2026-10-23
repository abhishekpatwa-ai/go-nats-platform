// api: receives orders over HTTP and publishes them to NATS JetStream.
// It does not write to the database itself — the worker does, asynchronously.
package main

import (
	"context"
	"encoding/json"
	"log"
	"net/http"
	"os"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/nats-io/nats.go"
	"github.com/nats-io/nats.go/jetstream"
	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/promauto"
	"github.com/prometheus/client_golang/prometheus/promhttp"
)

type Order struct {
	ID        int64     `json:"id,omitempty"`
	Item      string    `json:"item"`
	Quantity  int       `json:"quantity"`
	CreatedAt time.Time `json:"created_at,omitempty"`
}

var published = promauto.NewCounter(prometheus.CounterOpts{
	Name: "orders_published_total",
	Help: "Orders published to NATS",
})

func main() {
	ctx := context.Background()

	// NATS: keep retrying if NATS isn't up yet, instead of crashing
	nc, err := nats.Connect(env("NATS_URL", nats.DefaultURL),
		nats.RetryOnFailedConnect(true), nats.MaxReconnects(-1))
	if err != nil {
		log.Fatalf("nats: %v", err)
	}
	js, err := jetstream.New(nc)
	if err != nil {
		log.Fatalf("jetstream: %v", err)
	}

	// Stream ORDERS keeps every message on subject orders.* on disk,
	// so nothing is lost if the worker is down.
	retry("create stream", func() error {
		_, err := js.CreateOrUpdateStream(ctx, jetstream.StreamConfig{
			Name:     "ORDERS",
			Subjects: []string{"orders.*"},
			Storage:  jetstream.FileStorage,
		})
		return err
	})

	db, err := pgxpool.New(ctx, os.Getenv("DATABASE_URL")) // password comes from a Kubernetes Secret
	if err != nil {
		log.Fatalf("db: %v", err)
	}
	retry("create table", func() error { return createTable(ctx, db) })

	mux := http.NewServeMux()

	// Liveness: is the process alive? (no dependency checks here)
	mux.HandleFunc("GET /healthz", func(w http.ResponseWriter, _ *http.Request) { w.Write([]byte("ok")) })

	// Readiness: can we serve traffic? (NATS connected and DB reachable)
	mux.HandleFunc("GET /readyz", func(w http.ResponseWriter, r *http.Request) {
		if nc.Status() != nats.CONNECTED || db.Ping(r.Context()) != nil {
			http.Error(w, "not ready", http.StatusServiceUnavailable)
			return
		}
		w.Write([]byte("ready"))
	})

	// Create an order: publish to NATS and return 202 Accepted (processed later by the worker)
	mux.HandleFunc("POST /api/orders", func(w http.ResponseWriter, r *http.Request) {
		var o Order
		if err := json.NewDecoder(r.Body).Decode(&o); err != nil || o.Item == "" || o.Quantity <= 0 {
			http.Error(w, "need item and quantity > 0", http.StatusBadRequest)
			return
		}
		data, _ := json.Marshal(o)
		if _, err := js.Publish(r.Context(), "orders.created", data); err != nil {
			http.Error(w, "could not queue order", http.StatusServiceUnavailable)
			return
		}
		published.Inc()
		w.WriteHeader(http.StatusAccepted)
	})

	// List the latest orders the worker has saved
	mux.HandleFunc("GET /api/orders", func(w http.ResponseWriter, r *http.Request) {
		rows, err := db.Query(r.Context(),
			"SELECT id, item, quantity, created_at FROM orders ORDER BY id DESC LIMIT 20")
		if err != nil {
			http.Error(w, "db error", http.StatusInternalServerError)
			return
		}
		defer rows.Close()
		orders := []Order{}
		for rows.Next() {
			var o Order
			if err := rows.Scan(&o.ID, &o.Item, &o.Quantity, &o.CreatedAt); err == nil {
				orders = append(orders, o)
			}
		}
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(orders)
	})

	mux.Handle("GET /metrics", promhttp.Handler()) // scraped by Prometheus

	log.Println("api listening on :8080")
	log.Fatal(http.ListenAndServe(":8080", mux))
}

func createTable(ctx context.Context, db *pgxpool.Pool) error {
	_, err := db.Exec(ctx, `CREATE TABLE IF NOT EXISTS orders (
		id         BIGSERIAL PRIMARY KEY,
		item       TEXT NOT NULL,
		quantity   INT  NOT NULL,
		created_at TIMESTAMPTZ NOT NULL DEFAULT now())`)
	return err
}

// retry runs fn until it succeeds (dependencies may start after us)
func retry(what string, fn func() error) {
	for {
		err := fn()
		if err == nil {
			return
		}
		log.Printf("%s failed, retrying in 3s: %v", what, err)
		time.Sleep(3 * time.Second)
	}
}

func env(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}

// worker: reads orders from NATS JetStream and saves them in PostgreSQL.
// Messages are acknowledged only after the insert succeeds, so nothing is lost.
package main

import (
	"context"
	"encoding/json"
	"log"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/nats-io/nats.go"
	"github.com/nats-io/nats.go/jetstream"
	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/promauto"
	"github.com/prometheus/client_golang/prometheus/promhttp"
)

type Order struct {
	Item     string `json:"item"`
	Quantity int    `json:"quantity"`
}

var (
	processed = promauto.NewCounter(prometheus.CounterOpts{Name: "orders_processed_total", Help: "Orders saved to the database"})
	failed    = promauto.NewCounter(prometheus.CounterOpts{Name: "orders_failed_total", Help: "Orders that failed and will be redelivered"})
)

func main() {
	ctx := context.Background()

	nc, err := nats.Connect(env("NATS_URL", nats.DefaultURL),
		nats.RetryOnFailedConnect(true), nats.MaxReconnects(-1))
	if err != nil {
		log.Fatalf("nats: %v", err)
	}
	js, err := jetstream.New(nc)
	if err != nil {
		log.Fatalf("jetstream: %v", err)
	}

	db, err := pgxpool.New(ctx, os.Getenv("DATABASE_URL"))
	if err != nil {
		log.Fatalf("db: %v", err)
	}
	retry("create table", func() error {
		_, err := db.Exec(ctx, `CREATE TABLE IF NOT EXISTS orders (
			id         BIGSERIAL PRIMARY KEY,
			item       TEXT NOT NULL,
			quantity   INT  NOT NULL,
			created_at TIMESTAMPTZ NOT NULL DEFAULT now())`)
		return err
	})

	// Durable consumer "worker": NATS remembers what was delivered and acknowledged,
	// so after a restart the worker continues where it stopped.
	var cons jetstream.Consumer
	retry("create consumer", func() error {
		var err error
		cons, err = js.CreateOrUpdateConsumer(ctx, "ORDERS", jetstream.ConsumerConfig{
			Durable:       "worker",
			FilterSubject: "orders.created",
			AckPolicy:     jetstream.AckExplicitPolicy, // we decide when a message is done
			MaxDeliver:    5,                          // give up after 5 attempts
		})
		return err
	})

	cc, err := cons.Consume(func(msg jetstream.Msg) {
		var o Order
		if err := json.Unmarshal(msg.Data(), &o); err != nil {
			log.Printf("bad message, dropping: %v", err)
			msg.Term() // never redeliver a message we can't parse
			return
		}
		_, err := db.Exec(context.Background(),
			"INSERT INTO orders (item, quantity) VALUES ($1, $2)", o.Item, o.Quantity)
		if err != nil {
			log.Printf("insert failed, will retry: %v", err)
			failed.Inc()
			msg.NakWithDelay(5 * time.Second) // redeliver later
			return
		}
		processed.Inc()
		msg.Ack()
	})
	if err != nil {
		log.Fatalf("consume: %v", err)
	}

	// Health + metrics on :8081
	mux := http.NewServeMux()
	mux.HandleFunc("GET /healthz", func(w http.ResponseWriter, _ *http.Request) { w.Write([]byte("ok")) })
	mux.Handle("GET /metrics", promhttp.Handler())
	go func() { log.Fatal(http.ListenAndServe(":8081", mux)) }()
	log.Println("worker consuming orders.created")

	// Graceful shutdown: Kubernetes sends SIGTERM; stop taking messages, finish, then exit
	stop := make(chan os.Signal, 1)
	signal.Notify(stop, syscall.SIGTERM, os.Interrupt)
	<-stop
	log.Println("shutting down")
	cc.Stop()
	nc.Drain()
	db.Close()
}

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

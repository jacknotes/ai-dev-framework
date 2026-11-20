package main

import (
	"log"
	"net/http"
	"os"
	"time"

	"example.com/vue-go/backend/internal/api"
)

func main() {
	mux := api.NewRouter()

	port := os.Getenv("PORT")
	if port == "" {
		port = "8000"
	}
	addr := ":" + port

	srv := &http.Server{
		Addr:         addr,
		Handler:      mux,
		ReadTimeout:  10 * time.Second,
		WriteTimeout: 10 * time.Second,
	}
	log.Printf("server listening on %s", addr)
	log.Fatal(srv.ListenAndServe())
}

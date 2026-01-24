package main

import (
	"fmt"
	"net/http"
	"os"
)

func main() {
	name := os.Getenv("APP_NAME")
	if name == "" {
		name = "unknown-app"
	}

	http.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		fmt.Fprintf(w, "Hola desde %s\n", name)
	})

	http.HandleFunc("/health", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		fmt.Fprintf(w, `{"status":"up","app":"%s"}`, name)
	})

	fmt.Println("Listening on :8080")
	http.ListenAndServe(":8080", nil)
}

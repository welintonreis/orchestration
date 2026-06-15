package main

import (
	"embed"
	"io/fs"
	"log"
	"net/http"

	"github.com/go-chi/chi/v5"
	"github.com/go-chi/chi/v5/middleware"

	"redhusky.com.br/orchestration/internal/auth"
	"redhusky.com.br/orchestration/internal/config"
	"redhusky.com.br/orchestration/internal/handlers"
	"redhusky.com.br/orchestration/internal/store"
)

//go:embed web
var webFS embed.FS

func main() {
	cfg := config.Load()

	db, err := store.Open(cfg.DBPath)
	if err != nil {
		log.Fatalf("open db: %v", err)
	}
	defer db.Close()

	webFiles, err := fs.Sub(webFS, "web")
	if err != nil {
		log.Fatalf("web fs: %v", err)
	}

	h, err := handlers.New(cfg, db, webFiles)
	if err != nil {
		log.Fatalf("handlers: %v", err)
	}

	r := chi.NewRouter()
	r.Use(middleware.Logger)
	r.Use(middleware.Recoverer)

	// Static assets
	r.Handle("/static/*", http.StripPrefix("/static/", http.FileServer(http.FS(webFiles))))

	// First-run setup (no auth required)
	r.Get("/setup", h.SetupPage)
	r.Post("/setup", h.Setup)

	// Auth (no middleware)
	r.Get("/login", h.LoginPage)
	r.Post("/login", h.Login)
	r.Post("/logout", h.Logout)

	// Protected routes
	r.Group(func(r chi.Router) {
		r.Use(auth.Middleware(cfg.JWTSecret))
		r.Use(setupGuard(db))

		r.Get("/", h.Dashboard)
		r.Get("/environments", h.ListEnvironments)
		r.Get("/environments/new", h.NewEnvironment)
		r.Post("/environments", h.CreateEnvironment)
		r.Delete("/environments/{id}", h.DeleteEnvironment)
		// HTMX DELETE fallback via _method
		r.Post("/environments/{id}/delete", h.DeleteEnvironment)
	})

	log.Printf("Redhusk Orchestration → %s", cfg.ListenAddr)
	if err := http.ListenAndServe(cfg.ListenAddr, r); err != nil {
		log.Fatal(err)
	}
}

// setupGuard redirects to /setup if no users exist yet.
func setupGuard(db *store.DB) func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			n, _ := db.UserCount()
			if n == 0 {
				http.Redirect(w, r, "/setup", http.StatusSeeOther)
				return
			}
			next.ServeHTTP(w, r)
		})
	}
}

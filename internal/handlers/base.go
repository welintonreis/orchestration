package handlers

import (
	"html/template"
	"io/fs"
	"net/http"
	"strings"

	"redhusky.com.br/orchestration/internal/auth"
	"redhusky.com.br/orchestration/internal/config"
	"redhusky.com.br/orchestration/internal/store"
)

type Base struct {
	cfg   *config.Config
	db    *store.DB
	webFS fs.FS
}

func New(cfg *config.Config, db *store.DB, webFS fs.FS) (*Base, error) {
	return &Base{cfg: cfg, db: db, webFS: webFS}, nil
}

var funcMap = template.FuncMap{
	"initial": func(s string) string {
		if s == "" {
			return "?"
		}
		return strings.ToUpper(string([]rune(s)[0]))
	},
	"upper": strings.ToUpper,
}

type pageData struct {
	User       *auth.Claims
	ActivePath string
	Data       any
}

func (b *Base) render(w http.ResponseWriter, r *http.Request, page string, data any) {
	// Parse layout + page fresh per request to avoid {{define}} block collisions
	tmpl, err := template.New("").Funcs(funcMap).ParseFS(
		b.webFS,
		"templates/layout.html",
		"templates/"+page,
	)
	if err != nil {
		http.Error(w, "template error: "+err.Error(), http.StatusInternalServerError)
		return
	}
	pd := pageData{
		User:       auth.ClaimsFrom(r),
		ActivePath: r.URL.Path,
		Data:       data,
	}
	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	if err := tmpl.ExecuteTemplate(w, "page", pd); err != nil {
		http.Error(w, "render error: "+err.Error(), http.StatusInternalServerError)
	}
}

// renderStandalone renders pages without the layout (login, setup)
func (b *Base) renderStandalone(w http.ResponseWriter, r *http.Request, page string, data any) {
	tmpl, err := template.New("").Funcs(funcMap).ParseFS(b.webFS, "templates/"+page)
	if err != nil {
		http.Error(w, "template error: "+err.Error(), http.StatusInternalServerError)
		return
	}
	pd := pageData{Data: data}
	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	if err := tmpl.ExecuteTemplate(w, page, pd); err != nil {
		http.Error(w, "render error: "+err.Error(), http.StatusInternalServerError)
	}
}

func (b *Base) redirect(w http.ResponseWriter, r *http.Request, url string) {
	http.Redirect(w, r, url, http.StatusSeeOther)
}

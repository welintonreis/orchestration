package handlers

import (
	"net/http"

	"github.com/go-chi/chi/v5"
)

func (b *Base) ListEnvironments(w http.ResponseWriter, r *http.Request) {
	envs, err := b.db.ListEnvironments()
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	b.render(w, r, "environments/index.html", envs)
}

func (b *Base) NewEnvironment(w http.ResponseWriter, r *http.Request) {
	b.render(w, r, "environments/new.html", nil)
}

func (b *Base) CreateEnvironment(w http.ResponseWriter, r *http.Request) {
	name := r.FormValue("name")
	epType := r.FormValue("endpoint_type")
	endpoint := r.FormValue("endpoint")
	if epType == "" {
		epType = "socket"
	}

	if name == "" || endpoint == "" {
		b.render(w, r, "environments/new.html", map[string]string{"Error": "Nome e endpoint são obrigatórios"})
		return
	}

	_, err := b.db.CreateEnvironment(name, epType, endpoint)
	if err != nil {
		b.render(w, r, "environments/new.html", map[string]string{"Error": err.Error()})
		return
	}
	b.redirect(w, r, "/environments")
}

func (b *Base) DeleteEnvironment(w http.ResponseWriter, r *http.Request) {
	id := chi.URLParam(r, "id")
	b.db.DeleteEnvironment(id)
	b.redirect(w, r, "/environments")
}

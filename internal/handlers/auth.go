package handlers

import (
	"net/http"

	"redhusky.com.br/orchestration/internal/auth"
)

func (b *Base) LoginPage(w http.ResponseWriter, r *http.Request) {
	// First run: no users yet
	if n, _ := b.db.UserCount(); n == 0 {
		b.redirect(w, r, "/setup")
		return
	}
	// Already logged in
	if tok := auth.TokenFromRequest(r); tok != "" {
		if _, err := auth.ParseToken(tok, b.cfg.JWTSecret); err == nil {
			b.redirect(w, r, "/")
			return
		}
	}
	b.renderStandalone(w, r, "login.html", nil)
}

func (b *Base) Login(w http.ResponseWriter, r *http.Request) {
	username := r.FormValue("username")
	password := r.FormValue("password")

	user, err := b.db.FindUserByUsername(username)
	if err != nil || !auth.CheckPassword(user.Password, password) {
		b.renderStandalone(w, r, "login.html", map[string]string{"Error": "Usuário ou senha inválidos"})
		return
	}

	token, err := auth.IssueToken(user.ID, user.Username, user.Role, b.cfg.JWTSecret, b.cfg.JWTExpiryH)
	if err != nil {
		http.Error(w, "Erro interno", http.StatusInternalServerError)
		return
	}

	auth.SetCookie(w, token)
	b.redirect(w, r, "/")
}

func (b *Base) Logout(w http.ResponseWriter, r *http.Request) {
	auth.ClearCookie(w)
	b.redirect(w, r, "/login")
}

func (b *Base) SetupPage(w http.ResponseWriter, r *http.Request) {
	n, _ := b.db.UserCount()
	if n > 0 {
		b.redirect(w, r, "/login")
		return
	}
	b.renderStandalone(w, r, "setup.html", nil)
}

func (b *Base) Setup(w http.ResponseWriter, r *http.Request) {
	n, _ := b.db.UserCount()
	if n > 0 {
		b.redirect(w, r, "/login")
		return
	}

	username := r.FormValue("username")
	password := r.FormValue("password")
	if username == "" || len(password) < 8 {
		b.renderStandalone(w, r, "setup.html", map[string]string{"Error": "Username obrigatório; senha mínimo 8 caracteres"})
		return
	}

	hash, err := auth.HashPassword(password)
	if err != nil {
		http.Error(w, "Erro interno", http.StatusInternalServerError)
		return
	}

	user, err := b.db.CreateUser(username, hash, "admin")
	if err != nil {
		b.renderStandalone(w, r, "setup.html", map[string]string{"Error": "Erro ao criar usuário: " + err.Error()})
		return
	}

	// Also create default local environment
	b.db.CreateEnvironment("local", "socket", "unix:///var/run/docker.sock")

	token, _ := auth.IssueToken(user.ID, user.Username, user.Role, b.cfg.JWTSecret, b.cfg.JWTExpiryH)
	auth.SetCookie(w, token)
	b.redirect(w, r, "/")
}

package store

import (
	"database/sql"
	"errors"
	"time"

	"github.com/google/uuid"
)

type User struct {
	ID        string
	Username  string
	Password  string // bcrypt hash
	Role      string // admin | operator | readonly
	CreatedAt time.Time
	UpdatedAt time.Time
}

var ErrNotFound = errors.New("not found")

func (db *DB) UserCount() (int, error) {
	var n int
	err := db.QueryRow("SELECT COUNT(*) FROM users").Scan(&n)
	return n, err
}

func (db *DB) CreateUser(username, passwordHash, role string) (*User, error) {
	u := &User{
		ID:       uuid.NewString(),
		Username: username,
		Password: passwordHash,
		Role:     role,
	}
	_, err := db.Exec(
		"INSERT INTO users (id, username, password, role) VALUES (?, ?, ?, ?)",
		u.ID, u.Username, u.Password, u.Role,
	)
	return u, err
}

func (db *DB) FindUserByUsername(username string) (*User, error) {
	u := &User{}
	err := db.QueryRow(
		"SELECT id, username, password, role, created_at, updated_at FROM users WHERE username = ?",
		username,
	).Scan(&u.ID, &u.Username, &u.Password, &u.Role, &u.CreatedAt, &u.UpdatedAt)
	if errors.Is(err, sql.ErrNoRows) {
		return nil, ErrNotFound
	}
	return u, err
}

func (db *DB) FindUserByID(id string) (*User, error) {
	u := &User{}
	err := db.QueryRow(
		"SELECT id, username, password, role, created_at, updated_at FROM users WHERE id = ?",
		id,
	).Scan(&u.ID, &u.Username, &u.Password, &u.Role, &u.CreatedAt, &u.UpdatedAt)
	if errors.Is(err, sql.ErrNoRows) {
		return nil, ErrNotFound
	}
	return u, err
}

func (db *DB) ListUsers() ([]*User, error) {
	rows, err := db.Query("SELECT id, username, role, created_at FROM users ORDER BY created_at")
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var users []*User
	for rows.Next() {
		u := &User{}
		if err := rows.Scan(&u.ID, &u.Username, &u.Role, &u.CreatedAt); err != nil {
			return nil, err
		}
		users = append(users, u)
	}
	return users, rows.Err()
}

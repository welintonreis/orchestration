package store

import (
	"database/sql"
	_ "modernc.org/sqlite"
)

type DB struct {
	*sql.DB
}

func Open(path string) (*DB, error) {
	db, err := sql.Open("sqlite", path+"?_journal_mode=WAL&_foreign_keys=on")
	if err != nil {
		return nil, err
	}
	if err := db.Ping(); err != nil {
		return nil, err
	}
	s := &DB{db}
	return s, s.migrate()
}

func (db *DB) migrate() error {
	_, err := db.Exec(`
		CREATE TABLE IF NOT EXISTS users (
			id         TEXT PRIMARY KEY,
			username   TEXT UNIQUE NOT NULL,
			password   TEXT NOT NULL,
			role       TEXT NOT NULL DEFAULT 'readonly',
			created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
			updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
		);

		CREATE TABLE IF NOT EXISTS environments (
			id            TEXT PRIMARY KEY,
			name          TEXT NOT NULL,
			endpoint_type TEXT NOT NULL DEFAULT 'socket',
			endpoint      TEXT NOT NULL DEFAULT 'unix:///var/run/docker.sock',
			tls_ca        TEXT,
			tls_cert      TEXT,
			tls_key       TEXT,
			created_at    DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
			updated_at    DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
		);

		CREATE TABLE IF NOT EXISTS environment_access (
			user_id        TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
			environment_id TEXT NOT NULL REFERENCES environments(id) ON DELETE CASCADE,
			role           TEXT NOT NULL DEFAULT 'readonly',
			PRIMARY KEY (user_id, environment_id)
		);

		CREATE TABLE IF NOT EXISTS audit_logs (
			id             TEXT PRIMARY KEY,
			created_at     DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
			user_id        TEXT,
			username       TEXT,
			environment_id TEXT,
			resource_type  TEXT NOT NULL,
			resource_id    TEXT,
			action         TEXT NOT NULL,
			result         TEXT NOT NULL DEFAULT 'success',
			detail         TEXT
		);
	`)
	return err
}

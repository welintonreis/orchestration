package store

import (
	"database/sql"
	"errors"
	"time"

	"github.com/google/uuid"
)

type Environment struct {
	ID           string
	Name         string
	EndpointType string // socket | tcp | ssh
	Endpoint     string
	TLSCA        string
	TLSCert      string
	TLSKey       string
	CreatedAt    time.Time
	UpdatedAt    time.Time
}

func (db *DB) ListEnvironments() ([]*Environment, error) {
	rows, err := db.Query(
		"SELECT id, name, endpoint_type, endpoint, created_at FROM environments ORDER BY name",
	)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var envs []*Environment
	for rows.Next() {
		e := &Environment{}
		if err := rows.Scan(&e.ID, &e.Name, &e.EndpointType, &e.Endpoint, &e.CreatedAt); err != nil {
			return nil, err
		}
		envs = append(envs, e)
	}
	return envs, rows.Err()
}

func (db *DB) FindEnvironment(id string) (*Environment, error) {
	e := &Environment{}
	var tlsCA, tlsCert, tlsKey sql.NullString
	err := db.QueryRow(
		"SELECT id, name, endpoint_type, endpoint, tls_ca, tls_cert, tls_key, created_at FROM environments WHERE id = ?",
		id,
	).Scan(&e.ID, &e.Name, &e.EndpointType, &e.Endpoint, &tlsCA, &tlsCert, &tlsKey, &e.CreatedAt)
	if errors.Is(err, sql.ErrNoRows) {
		return nil, ErrNotFound
	}
	e.TLSCA = tlsCA.String
	e.TLSCert = tlsCert.String
	e.TLSKey = tlsKey.String
	return e, err
}

func (db *DB) CreateEnvironment(name, endpointType, endpoint string) (*Environment, error) {
	e := &Environment{
		ID:           uuid.NewString(),
		Name:         name,
		EndpointType: endpointType,
		Endpoint:     endpoint,
	}
	_, err := db.Exec(
		"INSERT INTO environments (id, name, endpoint_type, endpoint) VALUES (?, ?, ?, ?)",
		e.ID, e.Name, e.EndpointType, e.Endpoint,
	)
	return e, err
}

func (db *DB) DeleteEnvironment(id string) error {
	_, err := db.Exec("DELETE FROM environments WHERE id = ?", id)
	return err
}

package handlers

import (
	"context"
	"net/http"
	"time"

	"redhusky.com.br/orchestration/internal/docker"
)

type dashboardData struct {
	Environments  any
	ActiveEnvID   string
	Containers    int
	Running       int
	Images        int
	Volumes       int
	Networks      int
	SwarmEnabled  bool
	Services      int
	Nodes         int
	DockerVersion string
	Error         string
}

func (b *Base) Dashboard(w http.ResponseWriter, r *http.Request) {
	envs, _ := b.db.ListEnvironments()

	activeID := r.URL.Query().Get("env")
	if activeID == "" {
		if c, err := r.Cookie("active_env"); err == nil {
			activeID = c.Value
		}
	}
	if activeID == "" && len(envs) > 0 {
		activeID = envs[0].ID
	}
	if activeID != "" {
		http.SetCookie(w, &http.Cookie{Name: "active_env", Value: activeID, Path: "/", MaxAge: 86400 * 30})
	}

	d := &dashboardData{Environments: envs, ActiveEnvID: activeID}

	if activeID == "" {
		b.render(w, r, "dashboard.html", d)
		return
	}

	env, err := b.db.FindEnvironment(activeID)
	if err != nil {
		d.Error = "Ambiente não encontrado"
		b.render(w, r, "dashboard.html", d)
		return
	}

	cli, err := docker.New(env.Endpoint, env.ID, env.Name)
	if err != nil {
		d.Error = err.Error()
		b.render(w, r, "dashboard.html", d)
		return
	}

	ctx, cancel := context.WithTimeout(r.Context(), 5*time.Second)
	defer cancel()

	info, err := cli.Info(ctx)
	if err != nil {
		d.Error = err.Error()
		b.render(w, r, "dashboard.html", d)
		return
	}

	d.Containers = info.Containers
	d.Running = info.ContainersRunning
	d.Images = info.Images
	d.SwarmEnabled = info.Swarm.LocalNodeState == "active"
	d.Nodes = info.Swarm.Nodes
	d.DockerVersion = info.ServerVersion

	if vols, err := cli.Volumes(ctx); err == nil {
		d.Volumes = len(vols)
	}
	if nets, err := cli.Networks(ctx); err == nil {
		d.Networks = len(nets)
	}
	if d.SwarmEnabled {
		if svcs, err := cli.Services(ctx); err == nil {
			d.Services = len(svcs)
		}
	}

	b.render(w, r, "dashboard.html", d)
}

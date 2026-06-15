package docker

import (
	"context"
	"encoding/json"
	"fmt"
	"net"
	"net/http"
	"strings"
	"time"
)

// Client wraps the Docker REST API over a Unix socket or TCP.
type Client struct {
	http    *http.Client
	baseURL string
	envID   string
	envName string
}

// New creates a Docker client for the given endpoint.
// endpoint: "unix:///var/run/docker.sock" or "tcp://host:2376"
func New(endpoint, envID, envName string) (*Client, error) {
	var transport *http.Transport
	var baseURL string

	switch {
	case strings.HasPrefix(endpoint, "unix://"):
		socketPath := strings.TrimPrefix(endpoint, "unix://")
		transport = &http.Transport{
			DialContext: func(ctx context.Context, _, _ string) (net.Conn, error) {
				return (&net.Dialer{Timeout: 5 * time.Second}).DialContext(ctx, "unix", socketPath)
			},
		}
		baseURL = "http://localhost"

	case strings.HasPrefix(endpoint, "tcp://"):
		host := strings.TrimPrefix(endpoint, "tcp://")
		transport = &http.Transport{}
		baseURL = "http://" + host

	default:
		return nil, fmt.Errorf("unsupported endpoint: %s", endpoint)
	}

	return &Client{
		http:    &http.Client{Transport: transport, Timeout: 30 * time.Second},
		baseURL: baseURL,
		envID:   envID,
		envName: envName,
	}, nil
}

func (c *Client) get(ctx context.Context, path string, out any) error {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, c.baseURL+"/v1.47"+path, nil)
	if err != nil {
		return err
	}
	resp, err := c.http.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode >= 400 {
		var e struct{ Message string }
		json.NewDecoder(resp.Body).Decode(&e)
		return fmt.Errorf("docker API %s: %s", resp.Status, e.Message)
	}
	return json.NewDecoder(resp.Body).Decode(out)
}

func (c *Client) post(ctx context.Context, path string) error {
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, c.baseURL+"/v1.47"+path, nil)
	if err != nil {
		return err
	}
	resp, err := c.http.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode >= 400 {
		var e struct{ Message string }
		json.NewDecoder(resp.Body).Decode(&e)
		return fmt.Errorf("docker API %s: %s", resp.Status, e.Message)
	}
	return nil
}

// --- Info ---

type SystemInfo struct {
	Containers        int
	ContainersRunning int
	ContainersPaused  int
	ContainersStopped int
	Images            int
	ServerVersion     string
	Swarm             struct {
		LocalNodeState string
		NodeID         string
		Managers       int
		Nodes          int
	}
}

func (c *Client) Info(ctx context.Context) (*SystemInfo, error) {
	var info SystemInfo
	return &info, c.get(ctx, "/info", &info)
}

// --- Containers ---

type Container struct {
	ID      string `json:"Id"`
	Names   []string
	Image   string
	Status  string
	State   string
	Created int64
	Ports   []Port
	Labels  map[string]string
}

type Port struct {
	IP          string
	PrivatePort uint16
	PublicPort  uint16
	Type        string
}

func (c *Client) Containers(ctx context.Context, all bool) ([]Container, error) {
	path := "/containers/json"
	if all {
		path += "?all=1"
	}
	var list []Container
	return list, c.get(ctx, path, &list)
}

func (c *Client) ContainerStart(ctx context.Context, id string) error {
	return c.post(ctx, "/containers/"+id+"/start")
}

func (c *Client) ContainerStop(ctx context.Context, id string) error {
	return c.post(ctx, "/containers/"+id+"/stop")
}

func (c *Client) ContainerRestart(ctx context.Context, id string) error {
	return c.post(ctx, "/containers/"+id+"/restart")
}

func (c *Client) ContainerKill(ctx context.Context, id string) error {
	return c.post(ctx, "/containers/"+id+"/kill")
}

func (c *Client) ContainerPause(ctx context.Context, id string) error {
	return c.post(ctx, "/containers/"+id+"/pause")
}

func (c *Client) ContainerUnpause(ctx context.Context, id string) error {
	return c.post(ctx, "/containers/"+id+"/unpause")
}

// --- Volumes ---

type Volume struct {
	Name       string
	Driver     string
	Mountpoint string
	CreatedAt  string
}

type volumeListResponse struct {
	Volumes []Volume
}

func (c *Client) Volumes(ctx context.Context) ([]Volume, error) {
	var resp volumeListResponse
	return resp.Volumes, c.get(ctx, "/volumes", &resp)
}

// --- Networks ---

type Network struct {
	ID     string `json:"Id"`
	Name   string
	Driver string
	Scope  string
}

func (c *Client) Networks(ctx context.Context) ([]Network, error) {
	var list []Network
	return list, c.get(ctx, "/networks", &list)
}

// --- Images ---

type Image struct {
	ID          string `json:"Id"`
	RepoTags    []string
	RepoDigests []string
	Size        int64
	Created     int64
}

func (c *Client) Images(ctx context.Context) ([]Image, error) {
	var list []Image
	return list, c.get(ctx, "/images/json", &list)
}

// --- Swarm Services ---

type Service struct {
	ID   string `json:"ID"`
	Spec struct {
		Name string
		Mode struct {
			Replicated *struct{ Replicas *uint64 }
			Global     *struct{}
		}
		TaskTemplate struct {
			ContainerSpec struct {
				Image string
			}
		}
	}
}

func (c *Client) Services(ctx context.Context) ([]Service, error) {
	var list []Service
	return list, c.get(ctx, "/services", &list)
}

// --- Swarm Nodes ---

type Node struct {
	ID   string `json:"ID"`
	Spec struct {
		Availability string
		Role         string
	}
	Description struct {
		Hostname string
		Engine   struct{ EngineVersion string }
	}
	Status struct {
		State string
		Addr  string
	}
	ManagerStatus *struct {
		Leader bool
		Addr   string
	}
}

func (c *Client) Nodes(ctx context.Context) ([]Node, error) {
	var list []Node
	return list, c.get(ctx, "/nodes", &list)
}

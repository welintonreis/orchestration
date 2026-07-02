FROM golang:1.25-alpine AS build
WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 go build -o /out/redhusk-edge-agent .

FROM alpine:3.20
RUN apk add --no-cache ca-certificates
COPY --from=build /out/redhusk-edge-agent /usr/local/bin/redhusk-edge-agent
ENTRYPOINT ["/usr/local/bin/redhusk-edge-agent"]

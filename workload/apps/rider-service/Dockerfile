# Build stage
FROM golang:1.25-alpine AS builder
WORKDIR /app
COPY go.mod go.sum ./
RUN go mod download
COPY main.go store.go schema.sql ./
RUN CGO_ENABLED=0 GOOS=linux go build -ldflags="-w -s" -o rider-service .

# Production distroless runtime
FROM gcr.io/distroless/static-debian12:nonroot
WORKDIR /
COPY --from=builder /app/rider-service /rider-service
USER nonroot:nonroot
EXPOSE 8081
ENTRYPOINT ["/rider-service"]

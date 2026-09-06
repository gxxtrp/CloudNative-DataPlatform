# Build stage
FROM golang:1.22-alpine AS builder
WORKDIR /app
COPY go.mod ./
COPY main.go ./
RUN CGO_ENABLED=0 GOOS=linux go build -ldflags="-w -s" -o stream-ingestor .

# Production distroless runtime
FROM gcr.io/distroless/static-debian12:nonroot
WORKDIR /
COPY --from=builder /app/stream-ingestor /stream-ingestor
USER nonroot:nonroot
EXPOSE 8082
ENTRYPOINT ["/stream-ingestor"]

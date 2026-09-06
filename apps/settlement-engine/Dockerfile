# Build stage
FROM golang:1.22-alpine AS builder
WORKDIR /app
COPY go.mod ./
COPY main.go ./
RUN CGO_ENABLED=0 GOOS=linux go build -ldflags="-w -s" -o settlement-engine .

# Production distroless runtime
FROM gcr.io/distroless/static-debian12:nonroot
WORKDIR /
COPY --from=builder /app/settlement-engine /settlement-engine
USER nonroot:nonroot
ENTRYPOINT ["/settlement-engine"]

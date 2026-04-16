# ─── Multi-stage build: tiny final image (~10 MB) ───────────────────────────
FROM golang:1.22-alpine AS builder

WORKDIR /app
COPY go.mod ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 GOOS=linux go build -ldflags="-s -w" -o relayer .

# ── runtime stage ───────────────────────────────────────────────────────────
FROM scratch
COPY --from=builder /app/relayer /relayer

EXPOSE 5001

HEALTHCHECK --interval=10s --timeout=3s --retries=3 \
  CMD ["/relayer", "-health"]

ENTRYPOINT ["/relayer"]

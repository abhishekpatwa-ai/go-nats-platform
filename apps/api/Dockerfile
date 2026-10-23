# ---- Stage 1: build (Go toolchain, never shipped) ----
FROM golang:1.23-alpine AS build
WORKDIR /src
COPY go.mod ./
COPY . .
# No Go on my laptop, so go.sum is generated here. In a team repo, commit go.sum
# and run `go mod download` before COPY . . to cache dependencies.
RUN go mod tidy && CGO_ENABLED=0 go build -ldflags="-s -w" -o /out/app .

# ---- Stage 2: run (distroless: no shell, no package manager, ~10 MB) ----
FROM gcr.io/distroless/static-debian12:nonroot
COPY --from=build /out/app /app
USER nonroot:nonroot
EXPOSE 8080
ENTRYPOINT ["/app"]

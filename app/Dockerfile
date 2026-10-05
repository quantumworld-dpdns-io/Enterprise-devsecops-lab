# syntax=docker/dockerfile:1.7
FROM golang:1.26-alpine AS build
WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download
COPY *.go ./
RUN CGO_ENABLED=0 go build -trimpath -ldflags="-s -w" -o /out/demo-app .

# distroless static: no shell, no package manager, runs as UID 65532
FROM gcr.io/distroless/static-debian12:nonroot
COPY --from=build /out/demo-app /demo-app
ARG VERSION=dev
ENV APP_VERSION=${VERSION}
USER 65532:65532
EXPOSE 8080 9090
ENTRYPOINT ["/demo-app"]

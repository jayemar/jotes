# jotes' backend is a custom Go program embedding PocketBase (not the
# stock prebuilt binary) so it can register Go-native hooks for Web Push
# fan-out (see push.go) - JS hooks can't do the RFC8291 encryption that
# requires. PocketBase's default modernc.org/sqlite driver is pure Go, so
# CGO_ENABLED=0 gives a fully static binary and a minimal final image.
FROM golang:1.25-alpine AS build

WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download

COPY main.go push.go ./
COPY migrations ./migrations

RUN CGO_ENABLED=0 go build -o /pb/jotes-backend .

FROM alpine:3.20

RUN apk add --no-cache ca-certificates

COPY --from=build /pb/jotes-backend /usr/local/bin/jotes-backend

WORKDIR /pb

EXPOSE 8090
VOLUME /pb/pb_data

ENTRYPOINT ["jotes-backend", "serve", "--http=0.0.0.0:8090", "--dir=/pb/pb_data"]

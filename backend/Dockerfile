FROM alpine:3.20 AS download

ARG PB_VERSION=0.39.7

RUN apk add --no-cache unzip curl ca-certificates

RUN curl -fsSL -o /tmp/pb.zip \
        "https://github.com/pocketbase/pocketbase/releases/download/v${PB_VERSION}/pocketbase_${PB_VERSION}_linux_amd64.zip" \
    && unzip /tmp/pb.zip -d /pb \
    && rm /tmp/pb.zip

FROM alpine:3.20

RUN apk add --no-cache ca-certificates

COPY --from=download /pb/pocketbase /usr/local/bin/pocketbase

WORKDIR /pb
COPY pb_migrations ./pb_migrations

EXPOSE 8090
VOLUME /pb/pb_data

ENTRYPOINT ["pocketbase", "serve", "--http=0.0.0.0:8090"]

# Build with the full toolchain, ship only the static binary.
FROM swift:6.2-noble AS build
WORKDIR /src
COPY Package.swift Package.resolved ./
RUN swift package resolve
COPY Sources Sources
RUN swift build -c release --static-swift-stdlib --product woot-push

FROM ubuntu:noble
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates && rm -rf /var/lib/apt/lists/*
COPY --from=build /src/.build/release/woot-push /usr/local/bin/woot-push
USER nobody
EXPOSE 8080
CMD ["woot-push"]

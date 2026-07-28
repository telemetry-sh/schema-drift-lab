FROM debian:trixie-slim

ARG DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
    && apt-get install --yes --no-install-recommends ca-certificates swi-prolog-nox \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY src ./src
COPY public ./public

RUN chown -R nobody:nogroup /app

USER nobody:nogroup

ENV HOST=0.0.0.0
ENV PORT=8080
ENV HOME=/tmp

EXPOSE 8080

HEALTHCHECK --interval=5s --timeout=3s --start-period=3s --retries=5 \
  CMD ["swipl", "-q", "-s", "/app/src/server.pl", "-g", "server:main", "-t", "halt", "--", "--port=8080", "--healthcheck"]

ENTRYPOINT ["swipl", "-q", "-s", "/app/src/server.pl", "-g", "server:main", "-t", "halt", "--"]
CMD ["--port=8080"]

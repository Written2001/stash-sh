FROM alpine:latest
RUN apk add --no-cache bash curl jq
COPY --chmod=0755 ./stash.sh /stash.sh
COPY ./LICENCE /LICENCE
ENTRYPOINT ["/stash.sh"]
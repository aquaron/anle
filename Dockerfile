FROM alpine
MAINTAINER Paul Pham <docker@aquaron.com>

COPY data /data-default

RUN apk add --no-cache nginx certbot \
 && ln -s /data-default/bin/runme.sh /usr/bin \
 && ln -s /data-default/bin/bash-prompt /root/.profile

VOLUME /data
ENTRYPOINT [ "runme.sh" ]
CMD [ "daemon" ]

FROM nginx:1.28-alpine
ARG HTML_FILE=index.html
COPY ${HTML_FILE} /usr/share/nginx/html/index.html
RUN printf "ok\n" > /usr/share/nginx/html/healthz
EXPOSE 80
HEALTHCHECK --interval=5s --timeout=2s --retries=3 CMD wget -q -O /dev/null http://127.0.0.1/healthz || exit 1

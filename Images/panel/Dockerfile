FROM python:3.14-slim-trixie

COPY --from=docker:29-cli /usr/local/bin/docker /usr/local/bin/docker
COPY --from=docker:29-cli /usr/local/libexec/docker/cli-plugins/docker-compose \
                          /usr/local/libexec/docker/cli-plugins/docker-compose

RUN pip install --no-cache-dir docker flask

WORKDIR /app
COPY ./app /app

EXPOSE 1919

ENTRYPOINT ["python", "core.py"]

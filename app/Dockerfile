# deliberately-old & EOL base image (Ubuntu 20.04 is EOL since May 2025)
FROM ubuntu:20.04

# no pinned deps, no trusted mirrors, apt sources not pinned to mirrorlists
RUN apt-get update \
 && apt-get install -y python3 python3-pip nginx \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /srv

# BAD: we copy the whole dir (no .dockerignore) -> .env with secrets is baked in
COPY . /srv

RUN pip3 install -r requirements.txt

# runs as root by default (no USER directive)
EXPOSE 8080

CMD ["python3", "app/app.py"]
FROM ruby:3.4.7-slim

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
  && apt-get install -y --no-install-recommends \
    build-essential \
    ca-certificates \
    curl \
    git \
    libffi-dev \
    libyaml-dev \
    nodejs \
    npm \
    openssh-server \
    zlib1g-dev \
  && rm -rf /var/lib/apt/lists/*

RUN npm install -g @openai/codex

RUN useradd -m -s /bin/bash developer

RUN mkdir -p /etc/ssh/sshd_config.d \
  && printf "PasswordAuthentication yes\nPermitRootLogin no\n" > /etc/ssh/sshd_config.d/dev-container.conf

WORKDIR /work

COPY script/dev-container/entrypoint /usr/local/bin/dev-container-entrypoint
RUN chmod +x /usr/local/bin/dev-container-entrypoint \
  && mkdir -p /var/run/sshd

EXPOSE 4000 22

ENTRYPOINT ["/usr/local/bin/dev-container-entrypoint"]

FROM ruby:2.4.5@sha256:dd40c9f70dd028d0df8c7f7fa636daf2fc7ac1f4919562b68c60691b99714e05
MAINTAINER security@coinbase.com

RUN apt-get update && apt-get upgrade -y --no-install-recommends && apt-get install -y --no-install-recommends \
    g++ \
    gcc \
    libc6-dev \
    make \
    pkg-config \
    curl \
    git  \
    python \
    python-pip \
    python-setuptools \
    python-dev \
    libpython-dev \
    libicu-dev \
    cmake \
    pkg-config \
    wget \
  && rm -rf /var/lib/apt/lists/*

# Required so that Brakeman doesn't run into encoding
# issues when it parses non-ASCII characters.
ENV LANG C.UTF-8
ENV LC_ALL C.UTF-8

### JS + NODE
# Using node version 8.12.0 since it's the latest LTS.
ENV NODE_VERSION 8.12.0
ENV NPM_VERSION 6.4.1
ENV YARN_VERSION 1.12.3
ENV NPM_CONFIG_LOGLEVEL info

# Downloaded from https://nodejs.org/en/download/
COPY node_SHASUMS256.txt SHASUMS256.txt

RUN curl -SLO "https://nodejs.org/dist/v$NODE_VERSION/node-v$NODE_VERSION-linux-x64.tar.xz" \
  && grep " node-v$NODE_VERSION-linux-x64.tar.xz\$" SHASUMS256.txt | sha256sum -c -         \
  && tar -xJf "node-v$NODE_VERSION-linux-x64.tar.xz" -C /usr/local --strip-components=1     \
  && rm "node-v$NODE_VERSION-linux-x64.tar.xz" SHASUMS256.txt                               \
  && npm install -g npm@$NPM_VERSION                                                        \
  && npm install -g yarn@$YARN_VERSION

### GO - required for sift
ENV GOLANG_VERSION 1.11.4
ENV GOLANG_DOWNLOAD_URL https://golang.org/dl/go$GOLANG_VERSION.linux-amd64.tar.gz
ENV GOLANG_DOWNLOAD_SHA256 fb26c30e6a04ad937bbc657a1b5bba92f80096af1e8ee6da6430c045a8db3a5b

RUN curl -fsSL "$GOLANG_DOWNLOAD_URL" -o golang.tar.gz \
  && echo "$GOLANG_DOWNLOAD_SHA256  golang.tar.gz" | sha256sum -c - \
  && tar -C /usr/local -xzf golang.tar.gz \
  && rm golang.tar.gz

ENV GOPATH /go
ENV PATH $GOPATH/bin:/usr/local/go/bin:$PATH

RUN mkdir -p "$GOPATH/src" "$GOPATH/bin"

### Salus

# make the folder for the repo (volumed in)
RUN mkdir -p /home/repo
WORKDIR /home

# ruby gems
COPY Gemfile Gemfile.lock /home/
RUN gem update --system
RUN bundle install --deployment --without development:test

# node modules
COPY package.json yarn.lock /home/
RUN yarn

# prime the bundler-audit CVE DB
RUN bundle exec bundle-audit update

# More powerful grep alternative - https://sift-tool.org/
# Used in PatternSearch scanner.
RUN go get github.com/svent/sift

# Install gosec, static code vulnerability checker
RUN go get github.com/securego/gosec/cmd/gosec/...

# Make repo directory to copy go project into when running gosec
RUN mkdir -p $GOPATH/src/repo

# copy salus code
COPY bin /home/bin
COPY lib /home/lib
COPY salus-default.yaml /home/

# run the salus scan when this docker container is run
ENTRYPOINT ["bundle", "exec", "./bin/salus", "scan"]

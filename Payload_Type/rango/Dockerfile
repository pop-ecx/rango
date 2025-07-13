#FROM itsafeaturemythic/mythic_python_go:latest
#RUN pip3 install mythic_container==0.5.25
FROM python:3.11

ARG CA_CERTIFICATE
ARG NPM_REGISTRY
ARG PYPI_INDEX
ARG PYPI_INDEX_URL
ARG DOCKER_REGISTRY_MIRROR
ARG HTTP_PROXY
ARG HTTPS_PROXY

# Install system dependencies, including Zig
RUN apt-get -y update && \
    apt-get -y upgrade && \
    apt-get install --no-install-recommends \
      software-properties-common apt-utils build-essential libssl-dev zlib1g-dev libbz2-dev \
      libffi-dev liblzma-dev libsqlite3-dev tk-dev xz-utils protobuf-compiler \
      wget -y && \
    wget -q https://ziglang.org/download/0.14.0/zig-linux-x86_64-0.14.0.tar.xz && \
    tar -xf zig-linux-x86_64-0.14.0.tar.xz && \
    mv zig-linux-x86_64-0.14.0 /usr/local/zig && \
    ln -s /usr/local/zig/zig /usr/local/bin/zig && \
    rm zig-linux-x86_64-0.14.0.tar.xz && \
    apt-get purge -y && \
    rm -rf /var/lib/apt/lists/* && \
    apt-get clean

COPY requirements.txt /
RUN pip3 install -r /requirements.txt

WORKDIR /Mythic/

CMD ["python3", "main.py"]

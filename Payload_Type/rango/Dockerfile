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
      build-essential libssl-dev zlib1g-dev libbz2-dev \
      libffi-dev liblzma-dev libsqlite3-dev tk-dev xz-utils protobuf-compiler \
      wget git -y && \
    apt-get purge -y && \
    rm -rf /var/lib/apt/lists/* && \
    apt-get clean

RUN wget https://github.com/CX330Blake/ZYRA/releases/download/v0.1.6/zyra-linux-x86_64 -O zyra && \
    chmod +x zyra && \
    mv zyra /usr/local/bin/zyra

RUN wget -q https://ziglang.org/download/0.15.1/zig-x86_64-linux-0.15.1.tar.xz && \
    tar -xf zig-x86_64-linux-0.15.1.tar.xz && \
    mv zig-x86_64-linux-0.15.1 /usr/local/zig-0.15.1 && \
    ln -s /usr/local/zig-0.15.1/zig /usr/local/bin/zig && \
    rm zig-x86_64-linux-0.15.1.tar.xz

COPY requirements.txt /
RUN pip3 install -r /requirements.txt

WORKDIR /Mythic/

CMD ["python3", "main.py"]

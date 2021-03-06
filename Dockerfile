FROM emarsys/kong-dev-docker:1.5.0-centos-2f54f20-cd6c51c

RUN yum update -y && \
    yum install -y \
        cmake \
        gcc-c++ \
        openssl-devel && \
    yum clean all && \
    rm -rf /var/cache/yum

RUN luarocks install date 2.1.2 && \
    luarocks install classic 0.1.0 && \
    luarocks install escher 0.4.0-1 && \
    luarocks install lbase64 20120820-1 && \
    luarocks install lua-easy-crypto 1.0.0 && \
    luarocks install kong-lib-logger --deps-mode=none && \
    luarocks install kong-client 1.3.0

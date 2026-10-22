# The BBC BASIC 68000 demo (README.txt) as a container image:
#	docker run -it --rm bbc68k-demo
# The build context is build/demo/docker, made by tools/mkdemo.py --docker:
# r68k/ (r68k's tracked sources) and demo/ (the demo without the r68k
# binary).  r68k is compiled here, so the image builds natively for each
# platform (docker buildx build --platform linux/amd64,linux/arm64 ...).

FROM docker.io/library/alpine:3.20 AS build
RUN apk add --no-cache g++ make
COPY r68k /src/r68k
RUN cd /src/r68k && make r68k 'CXX=g++ -static' 'CXXFLAGS=-O2 -Iinclude' \
	'CFLAGS=-O2' && strip r68k

FROM docker.io/library/busybox:1.36
COPY demo /demo
COPY --from=build /src/r68k/r68k /demo/r68k
ENTRYPOINT ["/demo/demo.sh"]

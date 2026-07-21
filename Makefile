.PHONY: build smoke definitive shell

build:
	docker build -t latency-ids:1.0.0 .

smoke:
	PROFILE=smoke docker-compose run --rm artifact

definitive:
	PROFILE=definitive docker-compose run --rm artifact

shell:
	docker-compose run --rm --entrypoint /bin/sh artifact

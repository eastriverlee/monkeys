INSTALL_DIRECTORY ?= $(HOME)/.local/bin
SIGNING_IDENTITY ?= $(shell security find-identity -v -p codesigning 2>/dev/null | sed -n 's/.*"\(Developer ID Application: .*\)"/\1/p' | head -1)

build:
	swift build --configuration release

install: build
	mkdir -p $(INSTALL_DIRECTORY)
	install -m 755 .build/release/monkeys $(INSTALL_DIRECTORY)/monkeys
	$(if $(SIGNING_IDENTITY),codesign --force --options runtime --identifier dev.monk3ys.monkeys --sign "$(SIGNING_IDENTITY)" $(INSTALL_DIRECTORY)/monkeys)

check: build
	python3 tools/check-skill.py .build/release/monkeys
	python3 tools/check-examples.py .build/release/monkeys
	python3 tools/check-plugin.py
	python3 tools/check-release-notes.py
	python3 tools/check-update.py .build/release/monkeys
	claude plugin validate .

picture: install
	python3 tools/render-terminal-svg.py terminal.svg

clean:
	swift package clean

deploy:
	cd docs && DEPLOY_TARGET=site bun run build
	cd docs && monkeys run wrangler pages deploy build/client --project-name monkeys --branch main
	cd docs && bun run build
	cd docs && monkeys run wrangler pages deploy build/client --project-name monkeys-docs --branch main

.PHONY: build install check picture clean deploy

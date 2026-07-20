# Spot 개발·배포 명령. `make` 또는 `make help` 로 목록 확인.
# 배포 절차 상세는 docs/RELEASE.md 참조.

VERSION := $(shell cat VERSION)
TAP_DIR ?= $(HOME)/develop/homebrew-tap

.DEFAULT_GOAL := help
.PHONY: help run build install release publish release-ci clean

help: ## 이 도움말 표시
	@grep -E '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) \
		| awk 'BEGIN{FS=":.*?## "}{printf "  \033[36m%-12s\033[0m %s\n", $$1, $$2}'
	@echo ""
	@echo "  현재 VERSION: $(VERSION)"

run: ## 개발 실행 (swift run)
	swift run

build: ## 릴리즈 빌드 → build/Spot.app (로컬 서명)
	./scripts/make-app.sh

install: ## 빌드 후 /Applications 에 설치·실행
	./scripts/install.sh

release: ## 서명·공증 빌드 → dist/Spot-$(VERSION).zip (게시 없음)
	./scripts/release.sh

publish: ## 로컬에서 전체 게시 — release + GitHub 릴리스 + tap cask 갱신
	TAP_DIR=$(TAP_DIR) ./scripts/release.sh --publish

release-ci: ## CI 게시 — 예: make release-ci V=0.1.4 (VERSION 갱신·커밋·태그 push → Actions 자동 릴리스)
	@test -n "$(V)" || { echo "사용법: make release-ci V=0.1.4"; exit 1; }
	@echo "$(V)" > VERSION
	git add VERSION
	git commit -m "chore: $(V)"
	git push origin main
	git tag v$(V)
	git push origin v$(V)
	@echo "→ Actions 진행: gh run watch \$$(gh run list --workflow release.yml -L1 --json databaseId --jq '.[0].databaseId')"

clean: ## 빌드 산출물 삭제 (.build build dist)
	rm -rf .build build dist

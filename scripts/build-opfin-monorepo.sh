#!/usr/bin/env bash
set -Eeuo pipefail

BACKEND_SHA="${BACKEND_SHA:-fda182cc2d3d741c5f9b462e5d80d5caea6e594a}"
FRONTEND_SHA="${FRONTEND_SHA:-1ef9a0e9a4766ba802afc97f9b91f366620d053a}"
MONOREPO_BRANCH="${MONOREPO_BRANCH:-monorepo-candidate}"
OUTPUT_DIR="${1:-${RUNNER_TEMP:-/tmp}/opfin-monorepo}"

rm -rf "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR"
cd "$OUTPUT_DIR"

git init --initial-branch=main
git config user.name "github-actions[bot]"
git config user.email "41898282+github-actions[bot]@users.noreply.github.com"

cat > README.md <<EOF
# OpFin

Canonical monorepo candidate for the complete OpFin platform.

## Imported source

- Backend: \`lynelk/OpFin-BE@${BACKEND_SHA}\`
- Frontend/mobile: \`lynelk/OpFin-FE@${FRONTEND_SHA}\`
- Generated: 2026-09-04

Both source histories are retained as parents in this Git graph. The old repositories remain the historical record until the new \`lynelk/OpFin\` repository is created, validated and cut over.

## Layout

- \`apps/api\`: Laravel API, queue worker and scheduler source.
- \`apps/web\`: Next.js web experience.
- \`apps/client\`: Flutter Android, iOS, Huawei and desktop client.
- \`packages/contracts\`: shared API-contract home.
- \`infrastructure/railway\`: Railway service-boundary documentation.
- \`docs\`: cross-platform architecture and migration evidence.

## Local verification

\`make api-test\`, \`make web-test\`, \`make client-test\` or \`make test\`.

Each application remains independently buildable and deployable. Repository consolidation does not combine runtimes, secrets or failure domains.
EOF

cat > .gitignore <<'EOF'
.DS_Store
.env
.env.*
!.env.example
**/vendor/
**/node_modules/
**/.next/
**/.dart_tool/
**/build/
**/.flutter-plugins
**/.flutter-plugins-dependencies
**/ios/Pods/
**/DerivedData/
coverage/
EOF

cat > .editorconfig <<'EOF'
root = true

[*]
charset = utf-8
end_of_line = lf
insert_final_newline = true
trim_trailing_whitespace = true

[*.{yml,yaml,json,js,mjs,cjs,ts,tsx,dart,php,md}]
indent_style = space
indent_size = 2

[*.php]
indent_size = 4

[Makefile]
indent_style = tab
EOF

git add README.md .gitignore .editorconfig
git commit -m "Initialize canonical OpFin monorepo"

git remote add backend https://github.com/lynelk/OpFin-BE.git
git fetch --no-tags backend "$BACKEND_SHA"
git subtree add --prefix=apps/api "$BACKEND_SHA" -m "Import OpFin backend history at ${BACKEND_SHA}"

git remote add frontend https://github.com/lynelk/OpFin-FE.git
git fetch --no-tags frontend "$FRONTEND_SHA"
git subtree add --prefix=apps/web "$FRONTEND_SHA" -m "Import OpFin frontend and client history at ${FRONTEND_SHA}"

if [[ ! -d apps/web/opfin-frontend ]]; then
  echo "Expected Flutter application at apps/web/opfin-frontend" >&2
  exit 1
fi

git mv apps/web/opfin-frontend apps/client
rm -rf apps/api/.github apps/web/.github

mkdir -p .github/workflows docs/architecture docs/migration infrastructure/railway packages/contracts scripts

cat > AGENTS.md <<'EOF'
# OpFin monorepo engineering rules

## Boundaries

- `apps/api` owns identity, consent, eligibility, financial decisions, obligations, ledger postings, provider finality and reconciliation.
- `apps/web` and `apps/client` consume authenticated API contracts and never connect directly to PostgreSQL.
- CPay remains the only production money-movement adapter unless an explicitly approved architecture change says otherwise.
- A provider acknowledgement is not accounting finality.
- Secrets remain service-scoped and are never exposed to web or client builds.

## Required verification

- API changes: formatting, tests, dependency audit, PostgreSQL/migration evidence where applicable.
- Web changes: dependency audit, typecheck, lint, tests and production build.
- Client changes: Flutter analyze/tests plus Android and iOS release compile gates.
- Shared financial/API changes: run all affected jobs and end-to-end contract tests.

## Product rules

- Keep `Home | Borrow | Save | Grow | More` as the customer mental model.
- Keep peer lending visible in Borrow and Grow while preserving regulated gates.
- Account deletion must remain available in-app and preserve only legally required records.
- Never advertise provider-gated or regulator-gated capability as live.
EOF

cat > .github/CODEOWNERS <<'EOF'
* @lynelk
/apps/api/ @lynelk
/apps/web/ @lynelk
/apps/client/ @lynelk
/packages/contracts/ @lynelk
/infrastructure/ @lynelk
/docs/ @lynelk
/.github/ @lynelk
EOF

cat > .github/dependabot.yml <<'EOF'
version: 2
updates:
  - package-ecosystem: composer
    directory: /apps/api
    schedule:
      interval: weekly
    open-pull-requests-limit: 5
  - package-ecosystem: npm
    directory: /apps/api
    schedule:
      interval: weekly
    open-pull-requests-limit: 5
  - package-ecosystem: npm
    directory: /apps/web
    schedule:
      interval: weekly
    open-pull-requests-limit: 5
  - package-ecosystem: pub
    directory: /apps/client
    schedule:
      interval: weekly
    open-pull-requests-limit: 5
  - package-ecosystem: github-actions
    directory: /
    schedule:
      interval: weekly
    open-pull-requests-limit: 5
EOF

cat > .github/workflows/ci.yml <<'EOF'
name: OpFin Monorepo CI

on:
  pull_request:
  push:
    branches:
      - main
      - monorepo-candidate

permissions:
  contents: read

jobs:
  layout:
    runs-on: ubuntu-latest
    steps:
      - name: Check out repository
        uses: actions/checkout@v7
      - name: Verify monorepo boundaries
        run: sh scripts/verify-layout.sh

  api:
    runs-on: ubuntu-latest
    defaults:
      run:
        working-directory: apps/api
    steps:
      - name: Check out repository
        uses: actions/checkout@v7
        with:
          fetch-depth: 0
      - name: Set up PHP
        uses: shivammathur/setup-php@v2
        with:
          php-version: "8.2"
          extensions: mbstring, pdo_sqlite, sqlite3
          coverage: none
      - name: Prepare CI environment
        run: cp .env.example .env
      - name: Install Composer dependencies
        run: composer install --no-interaction --prefer-dist --no-progress
      - name: Prepare application
        run: php artisan key:generate
      - name: Enforce CPay-only production money movement
        run: sh scripts/enforce-cpay-only.sh
      - name: Run hermetic tests
        run: sh scripts/run-tests.sh
      - name: Check formatting for changed PHP files
        shell: bash
        run: |
          if [[ "${GITHUB_REF_NAME}" == "monorepo-candidate" && "${GITHUB_EVENT_NAME}" == "push" ]]; then
            echo "Initial import was already formatting-gated in the source repository."
            exit 0
          fi
          if [[ -n "${GITHUB_BASE_REF:-}" ]]; then
            git -C "$GITHUB_WORKSPACE" fetch origin "$GITHUB_BASE_REF" --depth=1
            base="origin/$GITHUB_BASE_REF"
          else
            base="HEAD^"
          fi
          mapfile -t files < <(git -C "$GITHUB_WORKSPACE" diff --name-only --diff-filter=ACMR "$base"...HEAD -- apps/api | grep '\.php$' | sed 's#^apps/api/##' || true)
          if [[ "${#files[@]}" -eq 0 ]]; then
            echo "No changed PHP files to format-check."
            exit 0
          fi
          ./vendor/bin/pint --test "${files[@]}"
      - name: Audit Composer dependencies
        run: composer audit

  api-assets:
    runs-on: ubuntu-latest
    defaults:
      run:
        working-directory: apps/api
    steps:
      - name: Check out repository
        uses: actions/checkout@v7
      - name: Set up Node
        uses: actions/setup-node@v7
        with:
          node-version: 22
          cache: npm
          cache-dependency-path: apps/api/package-lock.json
      - name: Install dependencies
        run: npm ci
      - name: Build assets
        run: npm run build

  web:
    runs-on: ubuntu-latest
    defaults:
      run:
        working-directory: apps/web
    steps:
      - name: Check out repository
        uses: actions/checkout@v7
      - name: Set up Node
        uses: actions/setup-node@v7
        with:
          node-version: 22
          cache: npm
          cache-dependency-path: apps/web/package-lock.json
      - name: Install locked dependencies
        run: npm ci --legacy-peer-deps
      - name: Audit dependencies
        run: npm audit --audit-level=high
      - name: Typecheck
        run: npm run typecheck
      - name: Install TypeScript 6 API for ESLint
        run: npm install --no-save --legacy-peer-deps typescript@npm:@typescript/typescript6@6.0.2
      - name: Lint
        run: npm run lint
      - name: Restore locked application dependencies
        run: npm ci --legacy-peer-deps
      - name: Test
        run: npm run test
      - name: Build
        env:
          NEXT_PUBLIC_OPFIN_API_URL: http://localhost:8000/api
          NEXT_PUBLIC_USE_MOCK_API: "false"
          OPFIN_ENABLE_DEMO_SHORTCUTS: "false"
        run: npm run build
      - name: Reject production mock API mode
        env:
          NODE_ENV: production
          NEXT_PUBLIC_USE_MOCK_API: "true"
        run: |
          if node -e "import('./next.config.mjs')"; then
            echo "Expected production mock API guard to fail"
            exit 1
          fi
      - name: Reject production demo shortcuts
        env:
          NODE_ENV: production
          OPFIN_ENABLE_DEMO_SHORTCUTS: "true"
        run: |
          if node -e "import('./next.config.mjs')"; then
            echo "Expected production demo shortcut guard to fail"
            exit 1
          fi

  client-android:
    runs-on: ubuntu-latest
    defaults:
      run:
        working-directory: apps/client
    steps:
      - name: Check out repository
        uses: actions/checkout@v7
      - name: Set up Flutter
        uses: subosito/flutter-action@v2
        with:
          flutter-version: "3.47.1"
          channel: stable
          cache: true
      - name: Install dependencies
        run: flutter pub get
      - name: Analyze
        run: flutter analyze
      - name: Run tests
        run: flutter test
      - name: Build Android release APK
        run: flutter build apk --release --no-pub
      - name: Build Android App Bundle
        run: flutter build appbundle --release --no-pub

  client-ios:
    runs-on: macos-15
    defaults:
      run:
        working-directory: apps/client
    steps:
      - name: Check out repository
        uses: actions/checkout@v7
      - name: Select Xcode 26+
        run: |
          candidate="$(find /Applications -maxdepth 1 -type d -name 'Xcode_26*.app' -print | sort -V | tail -1)"
          if [[ -n "$candidate" ]]; then
            sudo xcode-select -s "$candidate/Contents/Developer"
          fi
          xcodebuild -version
          major="$(xcodebuild -version | awk '/Xcode / {split($2,v,"."); print v[1]}')"
          if [[ -z "$major" || "$major" -lt 26 ]]; then
            echo "App Store uploads require Xcode 26 or later."
            exit 1
          fi
      - name: Set up Flutter
        uses: subosito/flutter-action@v2
        with:
          flutter-version: "3.47.1"
          channel: stable
          cache: true
      - name: Configure CI bundle identifier
        env:
          OPFIN_IOS_BUNDLE_ID: co.opfin.ci
        run: bash tool/prepare_app_store.sh
      - name: Install dependencies
        run: flutter pub get
      - name: Analyze
        run: flutter analyze
      - name: Run tests
        run: flutter test
      - name: Build unsigned iOS release
        run: |
          flutter build ios --release --no-codesign --no-pub \
            --dart-define=OPFIN_API_BASE_URL=https://opfin-api-production.up.railway.app/api \
            --dart-define=OPFIN_APP_STORE_P2P_BORROWING_ENABLED=false
EOF

cat > scripts/verify-layout.sh <<'EOF'
#!/usr/bin/env sh
set -eu
for path in apps/api/composer.json apps/web/package.json apps/client/pubspec.yaml RELEASE_MANIFEST.json; do
  test -f "$path" || { echo "Missing required monorepo path: $path" >&2; exit 1; }
done
for path in apps/api/.github apps/web/.github apps/client/.github; do
  test ! -d "$path" || { echo "Nested GitHub control directory is not allowed: $path" >&2; exit 1; }
done
if grep -RIn --exclude-dir=.git --exclude='*.md' --exclude='*.example' -E '(CPAY_PRIVATE_KEY|DB_PASSWORD|APP_KEY)=' apps packages infrastructure; then
  echo "A secret-like assignment was committed." >&2
  exit 1
fi
echo "OpFin monorepo layout and secret boundary checks passed."
EOF
chmod +x scripts/verify-layout.sh

cat > scripts/test-api.sh <<'EOF'
#!/usr/bin/env sh
set -eu
cd "$(dirname "$0")/../apps/api"
cp -n .env.example .env || true
composer install --no-interaction --prefer-dist
php artisan key:generate
sh scripts/enforce-cpay-only.sh
sh scripts/run-tests.sh
composer audit
EOF

cat > scripts/test-web.sh <<'EOF'
#!/usr/bin/env sh
set -eu
cd "$(dirname "$0")/../apps/web"
npm ci --legacy-peer-deps
npm audit --audit-level=high
npm run typecheck
npm run lint
npm run test
NEXT_PUBLIC_OPFIN_API_URL=http://localhost:8000/api NEXT_PUBLIC_USE_MOCK_API=false OPFIN_ENABLE_DEMO_SHORTCUTS=false npm run build
EOF

cat > scripts/test-client.sh <<'EOF'
#!/usr/bin/env sh
set -eu
cd "$(dirname "$0")/../apps/client"
flutter pub get
flutter analyze
flutter test
EOF
chmod +x scripts/test-api.sh scripts/test-web.sh scripts/test-client.sh

cat > Makefile <<'EOF'
.PHONY: test api-test web-test client-test layout

test: layout api-test web-test client-test

layout:
	sh scripts/verify-layout.sh

api-test:
	sh scripts/test-api.sh

web-test:
	sh scripts/test-web.sh

client-test:
	sh scripts/test-client.sh
EOF

cat > packages/contracts/README.md <<'EOF'
# Shared contracts

This directory is the canonical home for OpenAPI documents, JSON schemas, generated TypeScript clients, generated Dart clients and compatibility tests.

The initial migration deliberately does not invent a replacement API contract. Existing API behaviour remains authoritative until the contract-generation work is completed and validated against both clients.
EOF

cat > infrastructure/railway/README.md <<'EOF'
# Railway service mapping

The monorepo preserves independent services:

| Service | Root directory | Runtime |
| --- | --- | --- |
| opfin-api | `/apps/api` | Laravel HTTP API |
| opfin-worker | `/apps/api` | Queue worker |
| opfin-scheduler | `/apps/api` | Five-minute scheduler/reconciliation |
| opfin-web | `/apps/web` | Next.js |
| PostgreSQL | unchanged | Managed database |

Flutter clients are built through release pipelines and are not Railway runtime services. Secrets remain scoped to the minimum required service.
EOF

cat > docs/architecture/repository-boundaries.md <<'EOF'
# Repository and runtime boundaries

OpFin uses one repository but retains independent build, deployment and security boundaries.

- API changes do not automatically expose server secrets to web or Flutter.
- Web and Flutter do not access the database directly.
- API, worker, scheduler and web remain separate deployments.
- Mobile store build numbers remain independent of backend-only releases.
- Contract changes require coordinated API, web and client validation.
EOF

cat > docs/migration/SOURCE_MAP.md <<EOF
# Monorepo source map

| Source | Imported commit | Destination |
| --- | --- | --- |
| \`lynelk/OpFin-BE\` | \`${BACKEND_SHA}\` | \`apps/api\` |
| \`lynelk/OpFin-FE\` Next.js root | \`${FRONTEND_SHA}\` | \`apps/web\` |
| \`lynelk/OpFin-FE/opfin-frontend\` | \`${FRONTEND_SHA}\` | \`apps/client\` |

The import uses non-squashed Git subtree merges, so both source histories remain reachable in the monorepo graph. Nested source CI configuration was replaced with one root control plane.
EOF

cat > RELEASE_MANIFEST.json <<EOF
{
  "repository": "lynelk/OpFin",
  "status": "monorepo_candidate",
  "generated_at": "2026-09-04",
  "source": {
    "backend": {
      "repository": "lynelk/OpFin-BE",
      "commit": "${BACKEND_SHA}"
    },
    "frontend_mobile": {
      "repository": "lynelk/OpFin-FE",
      "commit": "${FRONTEND_SHA}"
    }
  },
  "paths": {
    "api": "apps/api",
    "web": "apps/web",
    "client": "apps/client"
  },
  "production_cutover": false
}
EOF

if [[ -f apps/web/README.md ]]; then
  sed -i 's#`opfin-frontend/`#`../client/`#g; s#cd opfin-frontend#cd ../client#g' apps/web/README.md
fi
if [[ -f apps/web/AGENTS.md ]]; then
  sed -i 's#cd opfin-frontend#cd ../client#g' apps/web/AGENTS.md
fi

sh scripts/verify-layout.sh

git add -A
git commit -m "Consolidate OpFin API, web and Flutter client into monorepo layout"

git bundle create "${RUNNER_TEMP:-/tmp}/OpFin-monorepo.bundle" --all
tar --exclude=.git -czf "${RUNNER_TEMP:-/tmp}/OpFin-monorepo.tar.gz" .

if [[ -n "${GITHUB_REPOSITORY:-}" && -n "${GITHUB_TOKEN:-}" ]]; then
  git remote add publish "https://x-access-token:${GITHUB_TOKEN}@github.com/${GITHUB_REPOSITORY}.git"
  git push --force publish HEAD:"refs/heads/${MONOREPO_BRANCH}"
fi

printf 'MONOREPO_HEAD=%s\n' "$(git rev-parse HEAD)"
printf 'MONOREPO_BRANCH=%s\n' "$MONOREPO_BRANCH"

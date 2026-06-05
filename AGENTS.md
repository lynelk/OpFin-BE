# OpFin-BE Agent Guide

This document defines rules for AI-assisted development on this Laravel 11 production backend.

## Stack

- **Framework**: Laravel 11, PHP 8.2
- **Auth**: Laravel Sanctum (token-based; tokens created via `User::createToken()`)
- **Database**: SQLite in CI and local dev; MySQL/PostgreSQL in production
- **Testing**: PHPUnit via `php artisan test`; CI also runs `./vendor/bin/pint --test` and `composer audit`

## API Response Envelope

Every JSON response from an API controller must use `App\Support\ApiResponse`:

```php
// Success
return ApiResponse::success('Message.', ['key' => $value]);
return ApiResponse::success('Created.', $model->toArray(), 201);

// Error
return ApiResponse::error('Not found.', 404);
return ApiResponse::error('Validation failed.', 422, $validator->errors()->toArray());
```

- Never return raw `response()->json()` from API controllers.
- All responses carry the envelope: `{ success: bool, message: string, data: any }`.
- Never leak exception messages to clients. Log with `Log::error()` and return a generic message.

## Validation — Form Requests

All input validation must use Form Request classes. Never use inline `Validator::make()`.

- Every Form Request **must** extend `App\Http\Requests\BaseFormRequest`.
- `BaseFormRequest` overrides `failedValidation()` and `failedAuthorization()` to emit `ApiResponse::error()`, ensuring consistent `success: false` in 422/403 responses.
- Authorization logic (role checks) belongs in the `authorize()` method, not in the controller.
- When adding a new endpoint that accepts a request body, create a corresponding Form Request in `app/Http/Requests/`.

## Authentication & Security

- All protected routes must be under the `auth:sanctum` middleware group (see `routes/api.php`).
- Rate limiting is configured in `AppServiceProvider`: `auth` (5/min), `api` (120/min), `webhooks` (120/min). Do not configure rate limiting inline in routes.
- `MOBILE_MONEY_PROVIDER=mock` is not allowed in production — enforced by `ProductionConfiguration::assertSafe()` called in `AppServiceProvider::boot()`.
- `OPFIN_ENABLE_DEMO_ROUTES=true` is not allowed in production — same guard.
- `APP_ENV` defaults to `production` when no `.env` file is present. Always ensure `.env` exists before running `composer install` or any `php artisan` command.

## Roles

User roles are constants on `App\Models\User`:
`ROLE_PLATFORM_ADMIN`, `ROLE_OPERATIONS`, `ROLE_CUSTOMER`, `ROLE_EMPLOYER_ADMIN`, `ROLE_SUPPORT`

Use `$user->hasAnyRole([...])` for role checks. Never compare role strings directly in controller code.

## Financial Data

- All monetary amounts are UGX integer minor units (e.g. `amount_minor: int`).
- UGX has no sub-units — `amount_minor` equals the whole UGX amount. The minor-unit convention exists for API consistency with the frontend.
- Never store amounts as floats. Use integer columns in migrations.

## Testing

- `php artisan test` runs all PHPUnit tests.
- Feature tests live in `tests/Feature/`. Use `RefreshDatabase` and `Sanctum::actingAs($user)` for authenticated tests.
- Every new Form Request must have at least one test asserting that invalid input is rejected with HTTP 422 and `success: false`.
- Tests, pint, and composer audit must all pass before merging.

## CI

The CI workflow (`.github/workflows/backend-ci.yml`) runs in this order:

1. `cp .env.example .env` — **must run before `composer install`** to prevent `APP_ENV=production` defaulting during the `post-autoload-dump` hook
2. `composer install`
3. `php artisan key:generate`
4. `php artisan test`
5. `./vendor/bin/pint --test`
6. `composer audit`

## Environment Variables

All required variables are documented in `.env.example`. Add new variables there when introducing them.

| Variable | Purpose |
|---|---|
| `APP_ENV` | `local` in dev, `production` in prod. Never set to `production` in CI. |
| `MOBILE_MONEY_PROVIDER` | Payment provider (`mock` blocked in production) |
| `OPFIN_ENABLE_DEMO_ROUTES` | Enables demo route group (blocked in production) |
| `SANCTUM_TOKEN_EXPIRY` | Token lifetime in minutes (default: 10080 = 7 days) |
| `CORS_ALLOWED_ORIGINS` | Comma-separated list of allowed CORS origins |

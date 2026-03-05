# OmniAuth MicrosoftIdentity2 Strategy

[![Test](https://github.com/icoretech/omniauth-microsoft-identity2/actions/workflows/test.yml/badge.svg?branch=main)](https://github.com/icoretech/omniauth-microsoft-identity2/actions/workflows/test.yml?query=branch%3Amain)
[![Gem Version](https://img.shields.io/gem/v/omniauth-microsoft-identity2.svg)](https://rubygems.org/gems/omniauth-microsoft-identity2)

`omniauth-microsoft-identity2` provides a Microsoft Identity (Entra ID) OAuth2/OpenID Connect strategy for OmniAuth.

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'omniauth-microsoft-identity2'
```

Then run:

```bash
bundle install
```

## Usage

Configure OmniAuth in your Rack/Rails app:

```ruby
Rails.application.config.middleware.use OmniAuth::Builder do
  provider :microsoft_identity2,
           ENV.fetch('MICROSOFT_CLIENT_ID'),
           ENV.fetch('MICROSOFT_CLIENT_SECRET')
end
```

Compatibility aliases are available if you want stable callback paths:

```ruby
provider :microsoft_identity, ENV.fetch('MICROSOFT_CLIENT_ID'), ENV.fetch('MICROSOFT_CLIENT_SECRET')
provider :windowslive, ENV.fetch('MICROSOFT_CLIENT_ID'), ENV.fetch('MICROSOFT_CLIENT_SECRET')
```

## Provider App Setup

- [Microsoft identity platform OAuth 2.0 authorization code flow](https://learn.microsoft.com/en-us/entra/identity-platform/v2-oauth2-auth-code-flow)
- [OpenID Connect on the Microsoft identity platform](https://learn.microsoft.com/en-us/entra/identity-platform/v2-protocols-oidc)
- Register callback URL (example): `https://your-app.example.com/auth/windowslive/callback`

## Options

Supported options include:
- `tenant` (default: `common`)
- `scope` (default: `openid profile email offline_access User.Read`)
- `prompt`
- `login_hint`
- `domain_hint`
- `response_mode`
- `redirect_uri`
- `nonce`
- `uid_with_tenant` (default: `true`; yields `tid:oid_or_sub` when possible)
- `skip_jwt` (default: `false`; disable id_token decode in `extra.id_info`)

Request query parameters for supported authorize options are passed through in request phase.

## Troubleshooting

- If callback fails with `message=csrf_detected`, the OAuth `state` value could not be validated.
- A common local smoke-test cause is host mismatch between request and callback (for example `127.0.0.1` vs `localhost`), which changes cookie scope and drops the session state cookie.
- Use the exact same host for request and callback URLs, and register that exact callback in Entra.

## Auth Hash

Example payload from `request.env['omniauth.auth']` (realistic shape, anonymized):

```json
{
  "uid": "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee:11111111-2222-3333-4444-555555555555",
  "info": {
    "name": "Sample User",
    "email": "sample@example.test",
    "first_name": "Sample",
    "last_name": "User",
    "nickname": "sample@example.test",
    "image": "https://graph.microsoft.com/v1.0/me/photo/$value"
  },
  "credentials": {
    "token": "eyJ0eXAiOiJKV1QiLCJhbGciOi...",
    "refresh_token": "1.Aa4A...<redacted>",
    "expires_at": 1772697856,
    "expires": true,
    "scope": "email openid profile User.Read"
  },
  "extra": {
    "raw_info": {
      "aud": "client-id",
      "iss": "https://login.microsoftonline.com/aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee/v2.0",
      "iat": 1772692424,
      "nbf": 1772692424,
      "exp": 1772696324,
      "sid": "session-id-value",
      "uti": "token-uti-value",
      "ver": "2.0",
      "idp": "https://sts.windows.net/tenant-id/",
      "tid": "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee",
      "oid": "11111111-2222-3333-4444-555555555555",
      "sub": "subject-value",
      "name": "Sample User",
      "given_name": "Sample",
      "family_name": "User",
      "preferred_username": "sample@example.test",
      "email": "sample@example.test",
      "picture": "https://graph.microsoft.com/v1.0/me/photo/$value"
    },
    "id_token": "eyJhbGciOiJSUzI1NiIsImtpZCI6I...redacted...",
    "id_info": {
      "aud": "client-id",
      "iss": "https://login.microsoftonline.com/aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee/v2.0",
      "iat": 1772692424,
      "nbf": 1772692424,
      "exp": 1772696324,
      "sid": "session-id-value",
      "uti": "token-uti-value",
      "ver": "2.0",
      "idp": "https://sts.windows.net/tenant-id/",
      "tid": "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee",
      "oid": "11111111-2222-3333-4444-555555555555",
      "sub": "subject-value",
      "name": "Sample User",
      "preferred_username": "sample@example.test"
    }
  }
}
```

## Endpoints

This gem uses Microsoft Identity v2 endpoints and Microsoft Graph user info endpoints:
- `https://login.microsoftonline.com/{tenant}/oauth2/v2.0/authorize`
- `https://login.microsoftonline.com/{tenant}/oauth2/v2.0/token`
- `https://graph.microsoft.com/oidc/userinfo`
- fallback: `https://graph.microsoft.com/v1.0/me`

## Development

```bash
bundle install
bundle exec rake
```

Run Rails integration tests with an explicit Rails version:

```bash
RAILS_VERSION='~> 8.1.0' bundle install
RAILS_VERSION='~> 8.1.0' bundle exec rake test_rails_integration
```

## Test Structure

- `test/omniauth_microsoft_identity2_test.rb`: strategy/unit behavior
- `test/rails_integration_test.rb`: full Rack/Rails request+callback flow
- `test/test_helper.rb`: shared test bootstrap

## Compatibility

- Ruby: `>= 3.2` (tested on `3.2`, `3.3`, `3.4`, `4.0`)
- `omniauth-oauth2`: `>= 1.8`, `< 1.9`
- Rails integration lanes: `~> 7.1.0`, `~> 7.2.0`, `~> 8.0.0`, `~> 8.1.0`

## Release

Tag releases as `vX.Y.Z`; GitHub Actions publishes the gem to RubyGems.

## License

MIT

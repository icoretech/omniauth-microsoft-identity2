# frozen_string_literal: true

require_relative 'test_helper'

require 'json'
require 'uri'

class OmniauthMicrosoftIdentity2Test < Minitest::Test
  DEFAULT_SCOPE = 'openid profile email offline_access User.Read'

  def build_strategy
    OmniAuth::Strategies::MicrosoftIdentity2.new(nil, 'client-id', 'client-secret')
  end

  def test_uses_current_microsoft_endpoints
    client_options = build_strategy.options.client_options

    assert_equal 'https://login.microsoftonline.com', client_options.site
    assert_equal 'common/oauth2/v2.0/authorize', client_options.authorize_url
    assert_equal 'common/oauth2/v2.0/token', client_options.token_url
  end

  def test_alias_strategies_keep_compatibility
    legacy = OmniAuth::Strategies::Windowslive.new(nil, 'client-id', 'client-secret')
    compact = OmniAuth::Strategies::MicrosoftIdentity.new(nil, 'client-id', 'client-secret')

    assert_equal 'windowslive', legacy.options.name
    assert_equal 'microsoft_identity', compact.options.name
  end

  def test_client_builds_tenant_specific_urls
    strategy = build_strategy
    strategy.options[:tenant] = 'organizations'
    strategy.options[:base_url] = 'https://login.microsoftonline.com'

    client_options = strategy.client.options

    assert_equal 'https://login.microsoftonline.com/organizations/oauth2/v2.0/authorize', client_options[:authorize_url]
    assert_equal 'https://login.microsoftonline.com/organizations/oauth2/v2.0/token', client_options[:token_url]
  end

  def test_authorize_params_support_request_overrides
    strategy = build_strategy
    request = Rack::Request.new(
      Rack::MockRequest.env_for(
        '/auth/microsoft_identity2?scope=openid,profile,email,User.Read' \
        '&prompt=select_account&login_hint=sample%40example.test' \
        '&domain_hint=organizations&response_mode=query'
      )
    )
    strategy.define_singleton_method(:request) { request }
    strategy.define_singleton_method(:session) { {} }

    params = strategy.authorize_params

    assert_equal 'openid profile email User.Read', params[:scope]
    assert_equal 'select_account', params[:prompt]
    assert_equal 'sample@example.test', params[:login_hint]
    assert_equal 'organizations', params[:domain_hint]
    assert_equal 'query', params[:response_mode]
  end

  def test_uid_info_credentials_and_extra_are_derived_from_raw_info
    strategy = build_strategy
    raw_info = {
      'aud' => 'client-id',
      'iss' => 'https://login.microsoftonline.com/aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee/v2.0',
      'iat' => 1_772_692_424,
      'nbf' => 1_772_692_424,
      'exp' => 1_772_696_324,
      'tid' => 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee',
      'oid' => '11111111-2222-3333-4444-555555555555',
      'sub' => 'subject-value',
      'sid' => 'session-id-value',
      'uti' => 'token-uti-value',
      'ver' => '2.0',
      'idp' => 'https://sts.windows.net/tenant-id/',
      'name' => 'Sample User',
      'given_name' => 'Sample',
      'family_name' => 'User',
      'preferred_username' => 'sample@example.test',
      'email' => 'sample@example.test',
      'picture' => 'https://graph.microsoft.com/v1.0/me/photo/$value'
    }

    token = FakeAccessToken.new(raw_info)
    strategy.define_singleton_method(:access_token) { token }

    assert_equal 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee:11111111-2222-3333-4444-555555555555', strategy.uid
    assert_equal(
      {
        name: 'Sample User',
        email: 'sample@example.test',
        first_name: 'Sample',
        last_name: 'User',
        nickname: 'sample@example.test',
        image: 'https://graph.microsoft.com/v1.0/me/photo/$value'
      },
      strategy.info
    )
    assert_equal(
      {
        'token' => 'access-token',
        'refresh_token' => 'refresh-token',
        'expires_at' => 1_772_691_847,
        'expires' => true,
        'scope' => DEFAULT_SCOPE
      },
      strategy.credentials
    )
    assert_equal raw_info, strategy.extra['raw_info']
    assert_equal token.params['id_token'], strategy.extra['id_token']
    assert_equal raw_info, strategy.extra['id_info']
  end

  def test_uid_can_skip_tenant_prefix
    strategy = build_strategy
    strategy.options[:uid_with_tenant] = false
    strategy.instance_variable_set(
      :@raw_info,
      {
        'tid' => 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee',
        'oid' => '11111111-2222-3333-4444-555555555555'
      }
    )

    assert_equal '11111111-2222-3333-4444-555555555555', strategy.uid
  end

  def test_raw_info_falls_back_to_graph_me_endpoint
    strategy = build_strategy
    token = FallbackAccessToken.new
    strategy.define_singleton_method(:access_token) { token }

    payload = strategy.raw_info

    assert_equal 'Sample User', payload['name']
    assert_equal 'sample@example.test', payload['email']
    assert_equal 'sample@example.test', payload['preferred_username']
    assert_equal %w[https://graph.microsoft.com/oidc/userinfo https://graph.microsoft.com/v1.0/me], token.paths
  end

  def test_callback_url_prefers_configured_value
    strategy = build_strategy
    callback = 'https://example.test/auth/microsoft_identity2/callback'
    strategy.options[:callback_url] = callback

    assert_equal callback, strategy.callback_url
  end

  def test_query_string_is_ignored_during_callback_request
    strategy = build_strategy
    request = Rack::Request.new(Rack::MockRequest.env_for('/auth/microsoft_identity2/callback?code=abc&state=xyz'))
    strategy.define_singleton_method(:request) { request }

    assert_equal '', strategy.query_string
  end

  def test_missing_state_cookie_fails_with_csrf_detected
    app = ->(_env) { [404, { 'Content-Type' => 'text/plain' }, ['not found']] }
    strategy = OmniAuth::Strategies::MicrosoftIdentity2.new(app, 'client-id', 'client-secret')
    env = Rack::MockRequest.env_for('/auth/microsoft_identity2/callback?code=abc&state=xyz')
    env['rack.session'] = {}

    status, headers, = strategy.call(env)

    assert_equal 302, status
    assert_includes headers.fetch('Location'), '/auth/failure'
    assert_includes headers.fetch('Location'), 'message=csrf_detected'
  end

  def test_request_phase_redirects_to_microsoft_with_expected_params
    previous_request_validation_phase = OmniAuth.config.request_validation_phase
    OmniAuth.config.request_validation_phase = nil

    app = ->(_env) { [404, { 'Content-Type' => 'text/plain' }, ['not found']] }
    strategy = OmniAuth::Strategies::MicrosoftIdentity2.new(app, 'client-id', 'client-secret')
    env = Rack::MockRequest.env_for('/auth/microsoft_identity2', method: 'POST')
    env['rack.session'] = {}

    status, headers, = strategy.call(env)

    assert_equal 302, status
    location = URI.parse(headers['Location'])
    params = URI.decode_www_form(location.query).to_h

    assert_equal 'login.microsoftonline.com', location.host
    assert_equal '/common/oauth2/v2.0/authorize', location.path
    assert_equal 'client-id', params.fetch('client_id')
    assert_equal DEFAULT_SCOPE, params.fetch('scope')
  ensure
    OmniAuth.config.request_validation_phase = previous_request_validation_phase
  end

  class FakeAccessToken
    attr_reader :params, :token, :refresh_token, :expires_at

    def initialize(parsed_payload)
      @parsed_payload = parsed_payload
      id_token = JWT.encode(parsed_payload, nil, 'none')
      @params = {
        'scope' => DEFAULT_SCOPE,
        'id_token' => id_token
      }
      @token = 'access-token'
      @refresh_token = 'refresh-token'
      @expires_at = 1_772_691_847
      @id_token = id_token
    end

    def get(_path)
      Struct.new(:parsed).new(@parsed_payload)
    end

    def [](key)
      { 'id_token' => @id_token }[key]
    end

    def expires?
      true
    end
  end

  class FallbackAccessToken
    attr_reader :paths, :params, :token, :refresh_token, :expires_at

    def initialize
      @paths = []
      @params = {
        'scope' => DEFAULT_SCOPE
      }
      @token = 'access-token'
      @refresh_token = nil
      @expires_at = 1_772_691_847
    end

    def get(path)
      @paths << path
      raise StandardError, 'userinfo endpoint unavailable' if path == 'https://graph.microsoft.com/oidc/userinfo'

      Struct.new(:parsed).new(
        {
          'id' => '11111111-2222-3333-4444-555555555555',
          'displayName' => 'Sample User',
          'givenName' => 'Sample',
          'surname' => 'User',
          'mail' => 'sample@example.test',
          'userPrincipalName' => 'sample@example.test'
        }
      )
    end

    def [](key)
      { 'id_token' => nil }[key]
    end

    def expires?
      true
    end
  end
end

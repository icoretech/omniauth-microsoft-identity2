# frozen_string_literal: true

require 'jwt'
require 'omniauth-oauth2'

module OmniAuth
  module Strategies
    # OmniAuth strategy for Microsoft Identity (Entra ID) OAuth2/OpenID Connect.
    class MicrosoftIdentity2 < OmniAuth::Strategies::OAuth2
      BASE_URL = 'https://login.microsoftonline.com'
      DEFAULT_SCOPE = 'openid profile email offline_access User.Read'
      USER_INFO_URL = 'https://graph.microsoft.com/oidc/userinfo'
      GRAPH_ME_URL = 'https://graph.microsoft.com/v1.0/me'

      option :name, 'microsoft_identity2'
      option :authorize_options, %i[scope state prompt login_hint domain_hint response_mode redirect_uri nonce]
      option :tenant, 'common'
      option :base_url, BASE_URL
      option :scope, DEFAULT_SCOPE
      option :skip_jwt, false
      option :uid_with_tenant, true

      option :client_options,
             site: BASE_URL,
             authorize_url: 'common/oauth2/v2.0/authorize',
             token_url: 'common/oauth2/v2.0/token',
             connection_opts: {
               headers: {
                 user_agent: 'icoretech-omniauth-microsoft-identity2 gem',
                 accept: 'application/json',
                 content_type: 'application/x-www-form-urlencoded'
               }
             }

      uid do
        oid_or_sub = raw_info['oid'] || raw_info['sub'] || raw_info['id']
        tid = raw_info['tid']

        if options[:uid_with_tenant] && present?(tid) && present?(oid_or_sub)
          "#{tid}:#{oid_or_sub}"
        else
          oid_or_sub.to_s
        end
      end

      info do
        email = raw_info['email'] || raw_info['preferred_username'] || raw_info['upn'] || raw_info['mail']
        {
          name: raw_info['name'],
          email: email,
          first_name: raw_info['given_name'],
          last_name: raw_info['family_name'],
          nickname: raw_info['preferred_username'] || raw_info['upn'] || email || raw_info['sub'],
          image: raw_info['picture']
        }.compact
      end

      credentials do
        {
          'token' => access_token.token,
          'refresh_token' => access_token.refresh_token,
          'expires_at' => access_token.expires_at,
          'expires' => access_token.expires?,
          'scope' => token_scope
        }.compact
      end

      extra do
        data = { 'raw_info' => raw_info }
        id_token = raw_id_token
        if present?(id_token)
          data['id_token'] = id_token
          decoded = decoded_id_token
          data['id_info'] = decoded if decoded
        end
        data
      end

      def client
        configure_tenant_client_urls
        super
      end

      def authorize_params
        super.tap do |params|
          apply_request_authorize_overrides(params)
          params[:scope] = normalize_scope(params[:scope] || options[:scope])
          persist_authorize_state(params)
        end
      end

      def raw_info
        @raw_info ||= begin
          claims = {}
          decoded = decoded_id_token
          claims.merge!(decoded) if decoded
          claims.merge!(fetch_user_info)
          claims
        end
      end

      def callback_phase
        return fail_state_mismatch if missing_session_state?

        super
      rescue NoMethodError => e
        raise unless oauth_state_nil_compare_error?(e)

        fail_state_mismatch
      end

      # Ensure token exchange uses a stable callback URI that matches provider config.
      def callback_url
        options[:callback_url] || options[:redirect_uri] || super
      end

      # Prevent authorization response params from being appended to redirect_uri.
      def query_string
        return '' if request.params['code']

        super
      end

      private

      def fetch_user_info
        normalize_user_info(access_token.get(USER_INFO_URL).parsed)
      rescue StandardError
        begin
          normalize_user_info(access_token.get(GRAPH_ME_URL).parsed)
        rescue StandardError
          {}
        end
      end

      def normalize_user_info(payload)
        return {} unless payload.is_a?(Hash)

        return payload unless graph_profile_payload?(payload)

        upn = payload['userPrincipalName']
        {
          'sub' => payload['id'],
          'oid' => payload['id'],
          'name' => payload['displayName'],
          'given_name' => payload['givenName'],
          'family_name' => payload['surname'],
          'email' => payload['mail'] || upn,
          'preferred_username' => upn,
          'upn' => upn
        }.merge(payload).compact
      end

      def normalize_scope(raw_scope)
        raw_scope.to_s.split(/[\s,]+/).reject(&:empty?).uniq.join(' ')
      end

      def apply_request_authorize_overrides(params)
        options[:authorize_options].each do |key|
          request_value = request.params[key.to_s]
          params[key] = request_value unless blank?(request_value)
        end
      end

      def graph_profile_payload?(payload)
        payload.key?('displayName') || payload.key?('userPrincipalName')
      end

      def configure_tenant_client_urls
        tenant = options[:tenant].to_s.strip
        tenant = 'common' if tenant.empty?

        base_url = options[:base_url].to_s.strip
        base_url = BASE_URL if base_url.empty?

        options.client_options.authorize_url = "#{base_url}/#{tenant}/oauth2/v2.0/authorize"
        options.client_options.token_url = "#{base_url}/#{tenant}/oauth2/v2.0/token"
      end

      def persist_authorize_state(params)
        session['omniauth.state'] = params[:state] if params[:state]
      end

      def token_scope
        access_token.params['scope'] || access_token['scope']
      end

      def raw_id_token
        params = access_token.respond_to?(:params) ? access_token.params : {}
        params['id_token'] || access_token['id_token']
      end

      def decoded_id_token
        return nil if options[:skip_jwt]

        token = raw_id_token
        return nil unless present?(token)

        payload, = JWT.decode(token, nil, false)
        payload
      rescue JWT::DecodeError
        nil
      end

      def blank?(value)
        value.nil? || (value.respond_to?(:empty?) && value.empty?)
      end

      def present?(value)
        !blank?(value)
      end

      def missing_session_state?
        present?(request.params['state']) && blank?(session['omniauth.state'])
      end

      def oauth_state_nil_compare_error?(error)
        error.message.include?("undefined method 'bytesize' for nil")
      end

      def fail_state_mismatch
        fail!(
          :csrf_detected,
          OmniAuth::Strategies::OAuth2::CallbackError.new(:csrf_detected, 'OAuth state was missing or mismatched')
        )
      end
    end

    # Backward-compatible strategy name for existing callback paths.
    class MicrosoftIdentity < MicrosoftIdentity2
      option :name, 'microsoft_identity'
    end

    # Compatibility alias for legacy windowslive callback paths.
    class Windowslive < MicrosoftIdentity2
      option :name, 'windowslive'
    end
  end
end

OmniAuth.config.add_camelization 'microsoft_identity2', 'MicrosoftIdentity2'
OmniAuth.config.add_camelization 'microsoft_identity', 'MicrosoftIdentity'
OmniAuth.config.add_camelization 'windowslive', 'Windowslive'

require "net/http"

class DemoReset
  # 作り直しが使う Kubernetes の API の 2 つの操作。Pod の ServiceAccount のトークンで呼び、kubectl のイメージを足さない。
  # ServiceAccount の Role は、web と jobs の Deployment の scale と Pod の一覧だけを許す（deploy/daily-reset.yaml）
  class Kubernetes
    SERVICE_ACCOUNT = "/var/run/secrets/kubernetes.io/serviceaccount".freeze

    attr_reader :ca_file

    # kubelet は期限の付いたトークンをファイルごと書き換えるので、トークンは要求のたびに読む
    def self.from_service_account(env = ENV, dir = SERVICE_ACCOUNT)
      new(base_url: "https://#{env.fetch('KUBERNETES_SERVICE_HOST')}:#{env.fetch('KUBERNETES_SERVICE_PORT')}",
        token_path: File.join(dir, "token"), namespace: File.read(File.join(dir, "namespace")).strip, ca_file: File.join(dir, "ca.crt"))
    end

    def initialize(base_url:, token_path:, namespace:, ca_file:)
      @base_url = base_url
      @token_path = token_path
      @namespace = namespace
      @ca_file = ca_file
    end

    def scale(deployment, replicas)
      request(Net::HTTP::Patch, "/apis/apps/v1/namespaces/#{@namespace}/deployments/#{deployment}/scale",
        body: { spec: { replicas: } }, content_type: "application/merge-patch+json")
    end

    def pod_names(selector)
      request(Net::HTTP::Get, "/api/v1/namespaces/#{@namespace}/pods?#{URI.encode_www_form(labelSelector: selector)}")
        .fetch("items").map { _1.dig("metadata", "name") }
    end

    private

    def request(method, path, body: nil, content_type: nil)
      uri = URI("#{@base_url}#{path}")
      request = method.new(uri)
      request["Authorization"] = "Bearer #{File.read(@token_path).strip}"
      request["Accept"] = "application/json"
      if body
        request["Content-Type"] = content_type
        request.body = JSON.generate(body)
      end
      # Net::HTTP の既定の時間切れは 60 秒で、API が答えないときに作り直しの時間の上限まで止まる
      response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", ca_file: @ca_file, open_timeout: 5, read_timeout: 30) do
        _1.request(request)
      end
      raise Failed, "Kubernetes の API が #{response.code} を返した: #{method::METHOD} #{uri.path}" unless response.is_a?(Net::HTTPSuccess)

      JSON.parse(response.body)
    end
  end
end

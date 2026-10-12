Rails.application.routes.draw do
  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  resource :session, only: %i[create destroy]
  post "graphql", to: "graphql#execute"
  # SendGrid のイベント Webhook。セッションを使わず、署名で認証する（docs/adr/007 決定 5 の A-3）
  post "webhooks/sendgrid/events", to: "webhooks/sendgrid_events#create"
end

class ApplicationMailer < ActionMailer::Base
  default from: ENV.fetch("MAILER_FROM", "Allure <from@example.com>")
  layout "mailer"
end

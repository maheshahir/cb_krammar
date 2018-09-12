FactoryBot.define do
  factory :token do
    user_id { FactoryBot.create(:user).id }
  end

  factory :token_password_reset, parent: :token do
    action 'PasswordReset'
  end
end

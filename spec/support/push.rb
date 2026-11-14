# frozen_string_literal: true

# Push notifications (PLAN_PUSH.md): a configured instance, a device key pair,
# and the receiving side of RFC 8291 so a spec can read what the instance
# actually posted to the relay.
module PushHelpers
  RELAY_ORIGIN = "https://push.allure.rocks"
  VAPID = Allure::Push::Config.generate_key_pair.freeze

  Device = Data.define(:key, :p256dh, :auth) do
    def self.generate
      key = OpenSSL::PKey::EC.generate("prime256v1")
      new(key:, p256dh: Allure::Push::Config.encode(key.public_key.to_octet_string(:uncompressed)),
          auth: Allure::Push::Config.encode(SecureRandom.random_bytes(16)))
    end
  end

  def push_env(overrides = {})
    {
      "VAPID_PUBLIC_KEY" => VAPID[:public_key],
      "VAPID_PRIVATE_KEY" => VAPID[:private_key],
      "VAPID_SUBJECT" => "mailto:operator@allure.test",
      "PUSH_RELAY_ORIGINS" => nil
    }.merge(overrides)
  end

  def with_push_env(values = push_env)
    previous = values.to_h { |key, _value| [ key, ENV[key] ] }
    values.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
    yield
  ensure
    previous&.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
  end

  def relay_endpoint(suffix = SecureRandom.alphanumeric(40))
    "#{RELAY_ORIGIN}/v1/push/#{suffix}"
  end

  def create_push_subscription(session:, endpoint: relay_endpoint, device: Device.generate, **attributes)
    PushSubscription.create!(user: session.user, session:, endpoint:, p256dh: device.p256dh, auth: device.auth,
                             **attributes)
  end

  # RFC 8291 §3.4 and RFC 8188, receiver side, in a single record.
  def decrypt_push(body, device)
    body = body.b
    salt = body.byteslice(0, 16)
    key_length = body.getbyte(20)
    sender_public = body.byteslice(21, key_length)
    ciphertext = body.byteslice(21 + key_length..)

    group = OpenSSL::PKey::EC::Group.new("prime256v1")
    shared = device.key.dh_compute_key(OpenSSL::PKey::EC::Point.new(group, OpenSSL::BN.new(sender_public, 2)))
    receiver_public = device.key.public_key.to_octet_string(:uncompressed)
    auth = Allure::Push::Config.decode(device.auth)
    ikm = OpenSSL::KDF.hkdf(shared, salt: auth, info: "WebPush: info\0".b + receiver_public + sender_public,
                                    hash: "SHA256", length: 32)
    key = OpenSSL::KDF.hkdf(ikm, salt:, info: "Content-Encoding: aes128gcm\0".b, hash: "SHA256", length: 16)
    nonce = OpenSSL::KDF.hkdf(ikm, salt:, info: "Content-Encoding: nonce\0".b, hash: "SHA256", length: 12)

    cipher = OpenSSL::Cipher.new("aes-128-gcm").decrypt
    cipher.key = key
    cipher.iv = nonce
    cipher.auth_tag = ciphertext.byteslice(-16, 16)
    padded = cipher.update(ciphertext.byteslice(0, ciphertext.bytesize - 16)) + cipher.final
    delimiter = padded.rindex("\x02".b)
    padded.byteslice(0, delimiter).force_encoding(Encoding::UTF_8)
  end
end

RSpec.configure do |config|
  config.include PushHelpers
  config.before { Notifications::PushDelivery.resolver = ->(_host, _port) { [ "93.184.216.34" ] } }
  config.after { Notifications::PushDelivery.resolver = nil }
end

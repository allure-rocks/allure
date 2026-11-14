# frozen_string_literal: true

require "openssl"

module Allure
  module Leaderboard
    module Alias
      # The index is derived from the account and the segment, so the order is
      # part of every alias already shown: append, never reorder.
      WORDS = [
        { fr: "Grimpeur", en: "Climber", de: "Kletterer", es: "Escalador", nl: "Klimmer" },
        { fr: "Coureur", en: "Runner", de: "Läufer", es: "Corredor", nl: "Loper" },
        { fr: "Randonneur", en: "Hiker", de: "Wanderer", es: "Senderista", nl: "Wandelaar" },
        { fr: "Pisteur", en: "Tracker", de: "Spurensucher", es: "Rastreador", nl: "Spoorzoeker" },
        { fr: "Rouliste", en: "Rider", de: "Fahrer", es: "Rodador", nl: "Rijder" },
        { fr: "Marcheur", en: "Walker", de: "Geher", es: "Caminante", nl: "Stapper" },
        { fr: "Explorateur", en: "Explorer", de: "Entdecker", es: "Explorador", nl: "Ontdekker" },
        { fr: "Vagabond", en: "Wanderer", de: "Streuner", es: "Vagabundo", nl: "Zwerver" },
        { fr: "Sprinteur", en: "Sprinter", de: "Sprinter", es: "Esprínter", nl: "Sprinter" },
        { fr: "Endurant", en: "Endurer", de: "Ausdauernder", es: "Fondista", nl: "Doorzetter" },
        { fr: "Alpiniste", en: "Alpinist", de: "Alpinist", es: "Alpinista", nl: "Alpinist" },
        { fr: "Voyageur", en: "Traveller", de: "Reisender", es: "Viajero", nl: "Reiziger" },
        { fr: "Pionnier", en: "Pioneer", de: "Pionier", es: "Pionero", nl: "Pionier" },
        { fr: "Navigateur", en: "Navigator", de: "Navigator", es: "Navegante", nl: "Navigator" },
        { fr: "Aventurier", en: "Adventurer", de: "Abenteurer", es: "Aventurero", nl: "Avonturier" },
        { fr: "Traceur", en: "Pathfinder", de: "Pfadfinder", es: "Guía", nl: "Padvinder" }
      ].freeze
      KEY_CONTEXT = "allure/leaderboard-alias/v1"

      module_function

      def for(user_id:, segment_id:, locale: :en, secret_key_base: nil)
        word = WORDS.fetch(word_index(user_id, segment_id, secret_key_base))
        number = alias_number(user_id, segment_id, secret_key_base)
        "#{word.fetch(locale.to_sym) { word.fetch(:en) }} #{number}"
      end

      def resolve(user_id:, segment_id:, existing:, locale: :en, secret_key_base: nil)
        base = self.for(user_id:, segment_id:, locale:, secret_key_base:)
        taken = Array(existing)
        return base unless taken.include?(base)

        suffix = 2
        candidate = "#{base} #{suffix}"
        while taken.include?(candidate)
          suffix += 1
          candidate = "#{base} #{suffix}"
        end
        candidate
      end

      def word_index(user_id, segment_id, secret_key_base)
        digest(user_id, segment_id, secret_key_base).byteslice(0, 8).unpack1("Q>") % WORDS.length
      end

      def alias_number(user_id, segment_id, secret_key_base)
        digest(user_id, segment_id, secret_key_base).byteslice(8, 4).unpack1("L>") % 100
      end

      def digest(user_id, segment_id, secret_key_base)
        key = OpenSSL::HMAC.digest("SHA256", secret_key(secret_key_base), KEY_CONTEXT)
        OpenSSL::HMAC.digest("SHA256", key, "#{user_id}\0#{segment_id}")
      end

      def secret_key(secret_key_base)
        return secret_key_base.to_s if secret_key_base

        Rails.application.secret_key_base
      end
    end
  end
end

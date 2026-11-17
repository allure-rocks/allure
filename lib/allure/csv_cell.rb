# frozen_string_literal: true

require "csv"

module Allure
  # CSV cells a spreadsheet opens safely (docs/dev/ACCOUNT.md): a text cell
  # starting with a formula character gets a leading `'`, so Excel or
  # LibreOffice shows it as text instead of evaluating it. Text written to an
  # export can come from another instance (a credit row's title, a remote
  # account address), so every line goes through here. Numbers are never
  # touched, negative ones included.
  module CsvCell
    FORMULA_START = /\A[=+\-@\t\r]/

    module_function

    def safe(value)
      value.is_a?(String) && value.match?(FORMULA_START) ? "'#{value}" : value
    end

    def line(values)
      CSV.generate_line(values.map { safe(it) })
    end
  end
end

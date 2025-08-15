# Money gem configuration
Money.default_currency = "USD"
Money.rounding_mode = BigDecimal::ROUND_HALF_UP

# Configure locale backend for formatting
# :i18n uses Rails I18n for locale-aware formatting
# :currency uses currency-specific formatting rules
Money.locale_backend = :i18n

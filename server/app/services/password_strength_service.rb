class PasswordStrengthService
  MINIMUM_SCORE = 60
  MINIMUM_LENGTH = 12
  MAXIMUM_LENGTH = 128

  # Character set requirements
  UPPERCASE_REGEX = /[A-Z]/
  LOWERCASE_REGEX = /[a-z]/
  DIGIT_REGEX = /[0-9]/
  SPECIAL_CHAR_REGEX = /[!@#$%^&*()_+\-=\[\]{};':"\\|,.<>\/?]/

  # Common weak patterns
  COMMON_PATTERNS = [
    /(.)\1{2,}/, # Repeated characters (aaa, 111, etc.) - 3+ chars
    /123|abc|qwe|asd/i, # Sequential patterns
    /password|admin|user|login/i # Common words (but allow as part of longer phrases)
  ].freeze

  # Most common passwords to reject
  COMMON_PASSWORDS = %w[
    password password123 123456 123456789 qwerty abc123 111111 password1
    admin login user welcome letmein monkey dragon princess sunshine
    iloveyou rockyou 123123 654321 666666 987654321 000000 123321
  ].freeze

  def self.validate_password(password)
    new(password).validate
  end

  def self.score_password(password)
    new(password).score
  end

  def initialize(password)
    @password = password.to_s
  end

  def validate
    errors = []

    # Length requirements
    if @password.length < MINIMUM_LENGTH
      errors << "Password must be at least #{MINIMUM_LENGTH} characters long"
    elsif @password.length > MAXIMUM_LENGTH
      errors << "Password cannot be longer than #{MAXIMUM_LENGTH} characters"
    end

    # Character set requirements
    unless @password.match?(UPPERCASE_REGEX)
      errors << "Password must contain at least one uppercase letter"
    end

    unless @password.match?(LOWERCASE_REGEX)
      errors << "Password must contain at least one lowercase letter"
    end

    unless @password.match?(DIGIT_REGEX)
      errors << "Password must contain at least one number"
    end

    unless @password.match?(SPECIAL_CHAR_REGEX)
      errors << "Password must contain at least one special character"
    end

    # Common password check
    if COMMON_PASSWORDS.include?(@password.downcase)
      errors << "Password is too common and easily guessable"
    end

    # Pattern checks - only for passwords that meet basic requirements
    if @password.length >= MINIMUM_LENGTH &&
       @password.match?(UPPERCASE_REGEX) &&
       @password.match?(LOWERCASE_REGEX) &&
       @password.match?(DIGIT_REGEX) &&
       @password.match?(SPECIAL_CHAR_REGEX)

      # Check for obviously weak patterns (but allow common words in long complex passwords)
      has_weak_patterns = false
      COMMON_PATTERNS.each do |pattern|
        if @password.match?(pattern)
          # Allow "password" in long complex passwords, but reject repeated chars and sequences
          if pattern.source.include?("password|admin|user|login")
            # Only reject if password is short or simple
            if @password.length < 16 || score < 80
              has_weak_patterns = true
              break
            end
          else
            # Always reject repeated chars and sequences
            has_weak_patterns = true
            break
          end
        end
      end

      if has_weak_patterns
        errors << "Password contains common patterns that make it weak"
      end

      # Strength score check
      if score < MINIMUM_SCORE
        errors << "Password is not strong enough (minimum strength score: #{MINIMUM_SCORE})"
      end
    end

    {
      valid: errors.empty?,
      errors: errors,
      score: score,
      strength: strength_level
    }
  end

  def score
    return 0 if @password.empty?

    score = 0

    # Base score from length
    score += [ @password.length * 2, 50 ].min

    # Character set bonuses
    score += 10 if @password.match?(UPPERCASE_REGEX)
    score += 10 if @password.match?(LOWERCASE_REGEX)
    score += 10 if @password.match?(DIGIT_REGEX)
    score += 15 if @password.match?(SPECIAL_CHAR_REGEX)

    # Entropy calculation
    character_space = calculate_character_space
    if character_space > 0
      entropy = @password.length * Math.log2(character_space)
      score += [ entropy.to_i / 2, 30 ].min
    end

    # Penalties for common patterns - reduced penalty for longer passwords
    COMMON_PATTERNS.each do |pattern|
      if @password.match?(pattern)
        penalty = @password.length >= 16 ? 10 : 20  # Smaller penalty for long passwords
        score -= penalty
      end
    end

    # Penalty for common passwords
    score -= 50 if COMMON_PASSWORDS.include?(@password.downcase)

    # Ensure score is between 0 and 100
    [ [ score, 0 ].max, 100 ].min
  end

  def strength_level
    case score
    when 0...30
      "very_weak"
    when 30...50
      "weak"
    when 50...70
      "moderate"
    when 70...85
      "strong"
    else
      "very_strong"
    end
  end

  private

  def calculate_character_space
    space = 0
    space += 26 if @password.match?(LOWERCASE_REGEX) # a-z
    space += 26 if @password.match?(UPPERCASE_REGEX) # A-Z
    space += 10 if @password.match?(DIGIT_REGEX) # 0-9
    space += 32 if @password.match?(SPECIAL_CHAR_REGEX) # Special chars
    space
  end
end

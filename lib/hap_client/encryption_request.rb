module HAP
  module EncryptionRequest
    AAD_LENGTH_BYTES = 2
    AUTHENTICATE_TAG_LENGTH_BYTES = 16

    attr_reader :encryption_count, :decryption_count

    def encryption_ready?()
      return !@controller_to_accessory_key.nil?
    end

    private

    def encrypt(data)
      @encryption_count ||= 0

      data.chars.each_slice(1024).map(&:join).map do |message|
        additional_data = [message.length].pack('v')

        chacha20poly1305ietf = RubyHome::HAP::Crypto::ChaCha20Poly1305.new(@controller_to_accessory_key)
        encrypted_data = chacha20poly1305ietf.encrypt(encryption_nonce, message, additional_data)
        increment_encryption_count!

        [additional_data, encrypted_data].join
      end
    end

    def decrypt(data)
      @decryption_count ||= 0
      decrypted_data = []
      read_pointer = 0

      while read_pointer < data.length
        little_endian_length_of_encrypted_data = data[read_pointer...read_pointer+AAD_LENGTH_BYTES]
        length_of_encrypted_data = little_endian_length_of_encrypted_data.unpack('v').first
        read_pointer += AAD_LENGTH_BYTES

        message = data[read_pointer...read_pointer+length_of_encrypted_data]
        read_pointer += length_of_encrypted_data

        auth_tag = data[read_pointer...read_pointer+AUTHENTICATE_TAG_LENGTH_BYTES]
        read_pointer += AUTHENTICATE_TAG_LENGTH_BYTES

        ciphertext = message + auth_tag
        additional_data = little_endian_length_of_encrypted_data
        chacha20poly1305ietf = RubyHome::HAP::Crypto::ChaCha20Poly1305.new(@accessory_to_controller_key)
        decrypted_data << chacha20poly1305ietf.decrypt(decryption_nonce, ciphertext, additional_data)

        increment_decryption_count!
      end

      decrypted_data.join
    end

    def increment_encryption_count!
      @encryption_count += 1
    end

    def encryption_nonce
      RubyHome::HAP::HexPad.pad([encryption_count].pack('Q<'))
    end

    def increment_decryption_count!
      @decryption_count += 1
    end

    def decryption_nonce
      RubyHome::HAP::HexPad.pad([decryption_count].pack('Q<'))
    end
  end
end

require 'ruby_home/device_id'
require 'ruby_home/hap/tlv'
require 'ruby_home/hap/hex_pad'
require 'ruby_home/hap/crypto/chacha20poly1305'
require 'hkdf'
require 'ruby_home/hap/crypto/hkdf'
require 'ruby_home-srp'
require 'ed25519'
require 'x25519'

class PairingError < StandardError
end

module HAP
  module Pairing
    ERROR_NAMES = {
      1 => 'kTLVError_Unknown',
      2 => 'kTLVError_Authentication',
      3 => 'kTLVError_Backoff',
      4 => 'kTLVError_MaxPeers',
      5 => 'kTLVError_MaxTries',
      6 => 'kTLVError_Unavailable',
      7 => 'kTLVError_Busy',
    }.freeze
    ERROR_TYPES = ERROR_NAMES.invert.freeze

    def pair_setup(password, &block)
      info("Pair Setup Step 1/3")
      @mode = :pair_setup
      @password = password
      srp_start_request()

      if block_given?
        @pair_setup_callback = block
      end
    end

    def pair_verify(&block)
      info("Pair Verify 1/2")
      @mode = :pair_verify
      verify_start_request()

      if block_given?
        @pair_verify_callback = block
      end
    end

    private

    def pair_setup_parse(data)
      begin
        response = check_tlv_response(data)

        case response['kTLVType_State']
        when 2
          info("Pair Setup Step 2/3")
          srp_verify_request(response, @password)
        when 4
          srp_verify(response)

          info("Pair Setup Step 3/3")
          srp_exchange_request()
        when 6
          info("Verifying Server Exchange")
          srp_exchange_verify(response)

          call_pair_setup_callback(true)
        else
          error("Unknown Pair Setup State: #{response['kTLVType_State']}")
        end
      rescue PairingError => e
        error("Pair Setup Error: #{e}")
        call_pair_setup_callback(false, e.to_s)
      end
    end

    def call_pair_setup_callback(status, data=nil)
      if @pair_setup_callback
        t = @pair_setup_callback
        @pair_setup_callback = nil
        t.call(status, data)
      end
    end

    def srp_start_request()
      debug("Pair Setup SRP Start Request")
      data = RubyHome::HAP::TLV.encode({
                                         'kTLVType_State' => 0x01,
                                         'kTLVType_Method' => 0x00
                                       })
      post("/pair-setup", "application/pairing+tlv8", data)
    end

    def srp_verify_request(response, password)
      debug("Pair Setup SRP Verify Request")

      username = 'Pair-Setup'
      debug("Using #{password} to pair with device")

      # convert bin variables to hex strings
      salt = bin_to_hex(response["kTLVType_Salt"])
      serverPublicKey = bin_to_hex(response["kTLVType_PublicKey"])

      debug("Generating Client Public/Private Keys")
      @srp_client = RubyHome::SRP::Client.new(3072)
      clientPublicKey = hex_to_bin(@srp_client.start_authentication())

      debug("Process Challenge from Server")
      client_M = hex_to_bin(@srp_client.process_challenge(username, password, salt, serverPublicKey))

      debug("Send Client Proof to Server")
      data = RubyHome::HAP::TLV.encode({
                                         'kTLVType_Proof' => client_M,
                                         'kTLVType_PublicKey' => clientPublicKey,
                                         'kTLVType_State' => 3,
                                         'kTLVType_Method' => 0
                                       })

      # Save session key
      @srp_session_key = @srp_client.K

      post("/pair-setup", "application/pairing+tlv8", data)
    end

    def srp_verify(response)
      debug("Verifying Server Proof")
      serverProof = bin_to_hex(response['kTLVType_Proof'])

      unless @srp_client.verify(serverProof)
        raise PairingError, "Failed to verify server proof"
      end

      @srp_client = nil
    end

    def srp_exchange_request()
      debug("Pair Setup SRP Exchange Request")

      debug("Generate Longterm key")
      @signature_key = Ed25519::SigningKey.generate.to_bytes.unpack1('H*')
      @signing_key = Ed25519::SigningKey.new([@signature_key].pack('H*'))

      debug("Generating device id")
      @client_id = RubyHome::DeviceID.generate()

      debug("Generating Encryption key")
      hkdf = RubyHome::HAP::Crypto::HKDF.new(info: 'Pair-Setup-Encrypt-Info', salt: 'Pair-Setup-Encrypt-Salt')
      key = hkdf.encrypt(@srp_session_key)
      @chacha20poly1305ietf = RubyHome::HAP::Crypto::ChaCha20Poly1305.new(key)

      debug("Generating ClientX")
      hkdf = RubyHome::HAP::Crypto::HKDF.new(info: 'Pair-Setup-Controller-Sign-Info', salt: 'Pair-Setup-Controller-Sign-Salt')
      clientX = hkdf.encrypt(@srp_session_key)

      debug("Generating ClientInfo")
      clientLTPK = @signing_key.verify_key.to_bytes
      clientInfo = [
        clientX.unpack1('H*'),
        @client_id.unpack1('H*'),
        clientLTPK.unpack1('H*')
      ].join

      debug("Generating Client Signature")
      clientSignature = @signing_key.sign([clientInfo].pack('H*'))

      debug("Generating Encrypted Data")
      subtlv = RubyHome::HAP::TLV.encode({
                                           'kTLVType_Identifier' => @client_id,
                                           'kTLVType_PublicKey' => clientLTPK,
                                           'kTLVType_Signature' => clientSignature
                                         })
      nonce = RubyHome::HAP::HexPad.pad('PS-Msg05')
      encrypted_data = @chacha20poly1305ietf.encrypt(nonce, subtlv)

      debug("Sending Encrypted Request to Server")
      data = RubyHome::HAP::TLV.encode({
                                         'kTLVType_State' => 5,
                                         'kTLVType_EncryptedData' => encrypted_data
                                       })
      post("/pair-setup", "application/pairing+tlv8", data)
    end

    def srp_exchange_verify(response)
      debug("Decrypting Server Response")
      encrypted_data = response['kTLVType_EncryptedData']
      nonce = RubyHome::HAP::HexPad.pad('PS-Msg06')

      decrypted_data = @chacha20poly1305ietf.decrypt(nonce, encrypted_data)
      unpacked_decrypted_data = RubyHome::HAP::TLV.read(decrypted_data)
      @chacha20poly1305ietf = nil

      debug("Verifying Server Signature")
      @serverPairingId = unpacked_decrypted_data['kTLVType_Identifier']
      serverSignature = unpacked_decrypted_data['kTLVType_Signature']
      @accessoryltpk = unpacked_decrypted_data['kTLVType_PublicKey']

      hkdf = RubyHome::HAP::Crypto::HKDF.new(info: 'Pair-Setup-Accessory-Sign-Info', salt: 'Pair-Setup-Accessory-Sign-Salt')
      accessoryx = hkdf.encrypt(@srp_session_key)

      accessoryinfo = [
        accessoryx.unpack1('H*'),
        @serverPairingId.unpack1('H*'),
        @accessoryltpk.unpack1('H*')
      ].join
      verify_key = RbNaCl::Signatures::Ed25519::VerifyKey.new(@accessoryltpk)

      if verify_key.verify(serverSignature, [accessoryinfo].pack('H*'))
        info("Pairing Success! Server Pairing ID: #{@serverPairingId}")
      else
        error("Failed to verify Server Signature")
        raise PairingError, "Failed to verify Server Signature"
      end
    end

    def pair_verify_parse(data)
      begin
        response = check_tlv_response(data)

        case response['kTLVType_State']
        when 2
          info("Pair Verify 2/2")
          verify_finish_request(response)
        when 4
          verify_finish_verify()
          @mode = :paired

          call_pair_verify_callback(true)
        else
          error("Unknown Pair Verify State: #{response['kTLVType_State']}")
        end
      rescue PairingError => e
        error("Pair Verify Error: #{e}")
        call_pair_verify_callback(false, e.to_s)
      end
    end

    def call_pair_verify_callback(status, data=nil)
      if @pair_verify_callback
        t = @pair_verify_callback
        @pair_verify_callback = nil
        t.call(status, data)
      end
    end

    def verify_start_request()
      debug("Generating new Session Public/Private Keys")
      @client_secret_key = X25519::Scalar.generate
      @client_public_key = @client_secret_key.public_key.to_bytes

      debug("Sending verify Request to Server")
      data = RubyHome::HAP::TLV.encode({
                                         'kTLVType_State' => 1,
                                         'kTLVType_PublicKey' => @client_public_key
                                       })
      post("/pair-verify", "application/pairing+tlv8", data)
    end

    def verify_finish_request(response)
      debug("Generating shared secret")
      server_public_key = X25519::MontgomeryU.new(response['kTLVType_PublicKey'])
      @shared_secret = @client_secret_key.multiply(server_public_key).to_bytes

      debug("Generating session key")
      hkdf = RubyHome::HAP::Crypto::HKDF.new(info: 'Pair-Verify-Encrypt-Info', salt: 'Pair-Verify-Encrypt-Salt')
      session_key = hkdf.encrypt(@shared_secret)

      debug("Decrypting data")
      subtlv = response['kTLVType_EncryptedData']
      chacha20poly1305ietf = RubyHome::HAP::Crypto::ChaCha20Poly1305.new(session_key)
      nonce = RubyHome::HAP::HexPad.pad('PV-Msg02')
      decrypted_data = chacha20poly1305ietf.decrypt(nonce, subtlv)
      decrypted_data = RubyHome::HAP::TLV.read(decrypted_data)

      debug("Verifying Server Signature")
      server_device_id = decrypted_data['kTLVType_Identifier']
      serverSignature = decrypted_data['kTLVType_Signature']

      accessoryinfo = [
        server_public_key.to_bytes.unpack1('H*'),
        server_device_id.unpack1('H*'),
        @client_public_key.unpack1('H*')
      ].join
      verify_key = RbNaCl::Signatures::Ed25519::VerifyKey.new(@accessoryltpk)

      if !verify_key.verify(serverSignature, [accessoryinfo].pack('H*'))
        error("Server signature INVALID!")
        raise PairingError, "Server signature INVALID!"
      end

      debug("Generating Client Info")
      clientInfo = [
        @client_public_key.unpack1('H*'),
        @client_id.unpack1('H*'),
        server_public_key.to_bytes.unpack1('H*')
      ].join

      debug("Generating Client Signature")
      clientSignature = @signing_key.sign([clientInfo].pack('H*'))

      debug("Generating Encrypted Data")
      subtlv = RubyHome::HAP::TLV.encode({
                                           'kTLVType_Identifier' => @client_id,
                                           'kTLVType_Signature' => clientSignature
                                         })

      chacha20poly1305ietf = RubyHome::HAP::Crypto::ChaCha20Poly1305.new(session_key)
      nonce = RubyHome::HAP::HexPad.pad('PV-Msg03')
      encrypted_data = chacha20poly1305ietf.encrypt(nonce, subtlv)

      debug("Sending Encrypted Request to Server")
      data = RubyHome::HAP::TLV.encode({
                                         'kTLVType_State' => 3,
                                         'kTLVType_EncryptedData' => encrypted_data
                                       })

      post("/pair-verify", "application/pairing+tlv8", data)
    end

    def verify_finish_verify()
      hkdf = RubyHome::HAP::Crypto::HKDF.new(info: 'Control-Write-Encryption-Key', salt: 'Control-Salt')
      @controller_to_accessory_key = hkdf.encrypt(@shared_secret)

      hkdf = RubyHome::HAP::Crypto::HKDF.new(info: 'Control-Read-Encryption-Key', salt: 'Control-Salt')
      @accessory_to_controller_key = hkdf.encrypt(@shared_secret)

      @shared_secret = nil

      info("Pair Verify Complete")
    end

    def get_pairing_context()
      {
        :client_id => @client_id,
        :signature_key => @signature_key,
        :accessoryltpk => @accessoryltpk.unpack1('H*')
      }.to_json
    end

    def set_pairing_context(context)
      context = JSON.parse(context)
      @client_id = context['client_id']
      @signature_key = context['signature_key']
      @accessoryltpk = hex_to_bin(context['accessoryltpk'])

      @signing_key = Ed25519::SigningKey.new([@signature_key].pack('H*'))
    end

    def check_tlv_response(data)
      data = RubyHome::HAP::TLV.read(data)

      debug("Response: " + data.to_s)

      if data['kTLVType_Error']
        error("Failed to pair: #{data}")
        raise PairingError, ERROR_NAMES[data['kTLVType_Error']]
      end

      return data
    end

    def bin_to_hex(s)
      s.unpack('H*')[0]
    end

    def hex_to_bin(s)
      s.scan(/../).map { |x| x.hex.chr }.join
    end
  end
end

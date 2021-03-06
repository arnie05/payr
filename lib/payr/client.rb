require "openssl"
require "base64"
require "net/https"
require "uri"

module Payr
	class Client
		def get_paybox_params_from params
			raise ArgumentError if params[:command_id].nil? || params[:buyer_email].nil? || params[:total_price].nil?
			raise ArgumentError if params[:callbacks].nil?
			command_timestamp = Time.now.utc.iso8601
			returned_hash = { pbx_site: Payr.site_id, 
												pbx_rang: Payr.rang,
												pbx_identifiant: Payr.paybox_id,
												pbx_total: params[:total_price],
												pbx_devise: convert_currency,
												pbx_cmd: params[:command_id],
												pbx_porteur: params[:buyer_email],
												pbx_retour: build_return_variables(Payr.callback_values),
												pbx_hash: Payr.hash.upcase,
												pbx_time: command_timestamp }



			returned_hash.merge!(pbx_effectue: params[:callbacks][:paid],
												 	 pbx_refuse: 	 params[:callbacks][:refused],
												   pbx_annule: 	 params[:callbacks][:cancelled])			

			returned_hash.merge!(pbx_repondre_a: params[:callbacks][:ipn])

            # optionnal parameters
      returned_hash.merge!(pbx_typepaiement: Payr.typepaiement, 
                           pbx_typepcarte: Payr.typecard) unless Payr.typepaiement.nil? || Payr.typecard.nil?

      returned_hash.merge! params[:options] unless params[:options].blank?
			base_params = self.to_base_params(returned_hash)			

			returned_hash.merge(pbx_hmac: self.generate_hmac(base_params))
		end


		def check_response query
			params = re_build_query query
			signature = get_signature query
			signed? params, signature
		end

		# QQQ Improve to use re_build_ipn_query
		def check_response_ipn params
			signature =  get_signature params
			query_params = re_build_query params
			signed? query_params, signature
		end

		def select_server_url
			[Payr.paybox_url, Payr.paybox_url_back_one, Payr.paybox_url_back_two].each do |url|
				return url if check_server_availability(url)
			end
		end
		
  	protected
  	def check_server_availability server_url
			uri = URI.parse(server_url)
			http = Net::HTTP.new(uri.host, uri.port)
			http.use_ssl = true

			request = Net::HTTP::Get.new(uri.request_uri)
			response = http.request(request)
			response.code == "200"
		end
  	def signed? params, signature
  		public_key = OpenSSL::PKey::RSA.new(File.read(File.expand_path(File.dirname(__FILE__) + '/keys/pubkey.pem')))
			check_response_verify params, Base64.decode64(Rack::Utils.unescape(signature)), public_key
  	end
  	def get_signature params
  		 params[params.index("&signature=")+"&signature=".length..params.length]
  	end
  	def re_build_ipn_query params
  		Payr.callback_values.keys.collect do |key|
        "#{key}=#{params[key]}" unless key == :signature	
      end.compact.join("&")
  	end
  	def re_build_query params
			params[params.index("?")+1..params.index("&signature")-1]
  	end
  	def check_response_verify params, signature, pub_key
  		digest = OpenSSL::Digest::SHA1.new
			pub_key.verify digest, signature, params
		end

  	def generate_hmac base_params
			binary_key = [Payr.secret_key].pack("H*")
			OpenSSL::HMAC.hexdigest(OpenSSL::Digest::Digest.new(Payr.hash.to_s), binary_key, base_params).upcase
		end

  	def to_base_params params={} 
  		params.to_a.collect do |pair|
  		 	"#{pair[0].upcase}=#{pair[1]}"
  		end.join("&")
  	end

	  def build_return_variables variables
  		variables.to_a.collect do |pair|
  			"#{pair[0]}:#{pair[1].capitalize}"
  		end.join(";")
		end
	 	def convert_currency
			case Payr.currency
		 	when :euro
		 		978
		 	when :us_dollars
		 		840
		 	else
		 		978
		 	end 
		end
	end

end
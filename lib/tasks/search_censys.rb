require 'censys'

module Intrigue
class SearchCensysTask < BaseTask

  def metadata
    {
      :name => "search_censys",
      :pretty_name => "Search Censys.io",
      :authors => ["jcran"],
      :description => "This task hits the Censys API and finds matches",
      :references => [],
      :allowed_types => ["DnsRecord", "IpAddress", "String"],
      :example_entities => [{"type" => "String", "attributes" => {"name" => "intrigue.io"}}],
      :allowed_options => [],
      :created_types => ["IpAddress", "SslCertificate"]
    }
  end

  ## Default method, subclasses must override this
  def run
    super

    begin

      # Make sure the key is set
      uid = _get_global_config "censys_uid"
      secret = _get_global_config "censys_secret"
      entity_name = _get_entity_attribute "name"

      unless uid && secret
        _log_error "No credentials?"
        return
      end

      # Attach to the censys service & search
      censys = Censys::Api.new(uid,secret)

      ## Grab IPv4 Results
      ["ipv4"].each do |search_type|
        response = censys.search(entity_name,search_type)
        response["results"].each do |r|
          _log "Got result: #{r}"

          # Go ahead and create the entity
          ip_address = r["ip"]
          _create_entity "IpAddress", "name" => "#{ip_address}", "additional" => r

          # Where we can, let's create additional entities from the scan results
          if r["protocols"]
            r["protocols"].each do |p|

              # Pull out the protocol
              port = p.split("/").first # format is like "80/http"
              protocol = p.split("/").last # format is like "80/http"

              # Always create a network service
              _create_entity "NetSvc", {
                "name" => "#{ip_address}:#{port}/tcp",
                "port" => port,
                "fingerprint" => protocol}

              # Handle specific protocols
              case protocol
              when "https"
                _create_entity "Uri", "name" => "https://#{ip_address}:#{port}"
              when "http"
                _create_entity "Uri", "name" => "http://#{ip_address}:#{port}"
              when "ftp"
                _create_entity "FtpServer", {
                  "name" => "ftp://#{ip_address}:#{port}",
                  "port" => "#{port}"
                }
              end
            end
          end
        end
      end

      # TODO -Should we expect any details when searching type "websites"

      ["certificates"].each do |search_type|
        response = censys.search(entity_name,search_type)
        response["results"].each do |r|
          _log "Got result: #{r}"
          _create_entity "SslCertificate", "name" => r["parsed.subject_dn"], "additional" => r

          # Pull out the CN and create a name
          r["parsed.subject_dn"].each do |x|
            host = x.split("CN=").last.split(",").first
            _create_entity "DnsRecord", "name" => host if host
          end

        end
      end


    rescue RuntimeError => e
      _log_error "Runtime error: #{e}"
    end

  end # end run()

end # end Class
end

module Intrigue
module Scanner
class QuickDnsSubdomainScan < Intrigue::Scanner::Base

  def metadata
    {
      :name => "quick_dns_subdomain",
      :pretty_name => "Quick DNS Subdomain Scan",
      :authors => ["jcran"],
      :description => "Recursively scan for hostnames using an extensive wordlist, alphanumeric generation to 3 characters and permutations",
      :references => [],
      :allowed_types => ["DnsRecord"],
      :example_entities => [
        {"type" => "DnsRecord", "attributes" => {"name" => "intrigue.io"}}
      ],
      :allowed_options => [ ]
    }
  end

    private

    ###
    ### Main "workflow" function
    ###
    def _recurse(entity, depth)

      if depth <= 0      # Check for bottom of recursion
        @scan_result.logger.log "Returning, depth @ #{depth}"
        return
      end

      if entity.type_string == "DnsRecord"
        ### DNS Subdomain Bruteforce
        _start_task_and_recurse "dns_brute_sub",entity,depth,[]
      else
        @scan_result.logger.log "Unhandled entity type: #{entity.type} #{entity.details["name"]}"
        return
      end
    end

end
end
end

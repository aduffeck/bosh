require "bosh/director/models/dns/domain"
require "bosh/director/models/dns/record"

module Bosh::Director::Models
  class LocalDnsRecord  < Sequel::Model(Bosh::Director::Config.db)
    one_to_one :instances
  end
end

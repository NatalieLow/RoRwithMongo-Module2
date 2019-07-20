class Photo
    attr_accessor :id, :location

    def self.mongo_client
        Mongoid::Clients.default
    end

end
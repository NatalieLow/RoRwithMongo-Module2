class Place
    include ActiveModel::Model

    attr_accessor :id, :formatted_address, :location, :address_components

    def initialize(params)
        @address_components = []
        unless params.nil?
            @id = params[:_id].to_s 

            unless (params[:address_components]).nil? 
                (params[:address_components]).each do |ac|
                    @address_components << AddressComponent.new(ac)
                end
            end

            @formatted_address = params[:formatted_address]
            @location = Point.new(params[:geometry][:geolocation])
        end
    end

    def persisted?
        !@id.nil?
    end

    def self.mongo_client
        Mongoid::Clients.default
    end

    def self.collection
        @db = self.mongo_client
        @coll = @db[:places]
    end

    def self.load_all(json_file)
        file = json_file.read
        parsed = file && file.length >= 2 ? JSON.parse(file).to_a : nil
        self.collection.insert_many(parsed)
    end

    def self.find_by_short_name(short_name)
        Place.collection.find('address_components.short_name' => short_name)
    end

    def self.to_places(mongo_places)
        places = []
        mongo_places.each do |mongo_place|
            places << Place.new(mongo_place)
        end
        return places
    end

    def self.find(id)
        place = Place.collection.find(:_id => BSON::ObjectId.from_string(id)).first
        unless place.nil?
            Place.new(place)
        else
            return nil
        end
    end

    def self.all(offset = 0, limit = 0)
        all_places = Place.collection.find().skip(offset).limit(limit)
        places = []
        all_places.each do |place|
            places << Place.new(place)
        end
        return places
    end

    def destroy
        unless (self.id).nil?
            Place.collection.find(:_id => (BSON::ObjectId.from_string(self.id))).delete_one()
        end
    end

    def self.get_address_components(sort = {}, offset = nil, limit = nil)
        core = [{:$project => {:address_components=> 1, :formatted_address => 1, 'geometry.geolocation' => 1}}, {:$unwind => '$address_components'}]
        core.unshift({:$sort => sort}) unless sort.empty?
        core << ({:$skip => offset}) unless offset.nil?
        core << ({:$limit => limit}) unless limit.nil?
        
        Place.collection.find().aggregate(core) 
    end

    def self.get_country_names
        query = Place.collection.find().aggregate([{:$project => {:_id => 0, 'address_components.long_name' => 1, 
            'address_components.types' => 1}}, {:$unwind => '$address_components'}, {:$unwind => '$address_components.types'}, 
            {:$match => {'address_components.types' => 'country'}}, {:$group => {:_id => '$address_components.long_name'}}]).to_a 
        query.map {|h| h[:_id]}
    end

    def self.find_ids_by_country_code(country_code)
        Place.collection.find().aggregate([{:$match => {'address_components.short_name' => country_code}},
             {:$match => {'address_components.types' => 'country'}}, {:$project => {:_id => 1}}]).to_a.map{|doc| doc[:_id].to_s}
    end

    def self.create_indexes
        Place.collection.indexes.create_one({'geometry.geolocation' => "2dsphere"}) 
        # Mongo::Index::GEO2DSPHERE
    end

    def self.remove_indexes
        Place.collection.indexes.drop_one("geometry.geolocation_2dsphere")
    end

    def self.near(point, max_meters = nil)
        if max_meters.nil?
            Place.collection.find("geometry.geolocation" => {:$near => {:$geometry => point.to_hash}})
        else
            Place.collection.find("geometry.geolocation" => {:$near => {:$geometry => point.to_hash, :$maxDistance => max_meters }})
        end 
    end

    def near(max_meters = nil)
        if max_meters.nil?
            coll = Place.collection.find("geometry.geolocation" => {:$near => {:$geometry => self.location.to_hash}})
        else
            coll = Place.collection.find("geometry.geolocation" => {:$near => {:$geometry => self.location.to_hash, 
                :$maxDistance => max_meters }})
        end 

        Place.to_places(coll)
    end

    def photos(offset = 0, limit = 0)
        query = Photo.find_photos_for_place(@id).skip(offset).limit(limit)
        photos = []
        query.each do |result|
            photos << Photo.find(result[:_id])
        end
        return photos
    end
end
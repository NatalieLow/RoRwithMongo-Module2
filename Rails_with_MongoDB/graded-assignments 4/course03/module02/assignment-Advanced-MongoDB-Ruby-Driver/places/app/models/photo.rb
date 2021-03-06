require 'exifr/jpeg'

class Photo

    attr_accessor :id, :location, :place
    attr_writer :contents

    def self.mongo_client
        Mongoid::Clients.default
    end

    def initialize(params = {})
        unless (params[:_id]).nil?
            @id = params[:_id].to_s
        end

        unless (params[:metadata]).nil?
            unless (params[:metadata][:location]).nil?
                @location = Point.new(params[:metadata][:location])
            end
            unless (params[:metadata][:place]).nil?
                @place = params[:metadata][:place]
            end
        end
    end

    def self.id_criteria(id)
        {_id:BSON::ObjectId.from_string(id)}
    end

    def persisted?
        !(@id.nil?)
    end

    def save
        if self.persisted?
            Photo.mongo_client.database.fs.find(self.class.id_criteria(@id)).update_one(:$set =>{'metadata.location' => @location.to_hash, 'metadata.place' => @place})
        else
            gps = EXIFR::JPEG.new(@contents).gps
            @location = Point.new(:lng=>gps.longitude, :lat=>gps.latitude)
            @contents.rewind 
            description = {}
            description[:content_type] = 'image/jpeg'
            description[:metadata] = {:location=>@location.to_hash, :place => @place}
            grid_file = Mongo::Grid::File.new(@contents.read, description)
            @id = Photo.mongo_client.database.fs.insert_one(grid_file).to_s
        end
    end

    def self.all(offset = 0, limit = 0)
        Photo.mongo_client.database.fs.find.skip(offset).limit(limit).map {|doc| Photo.new(doc)}
    end

    def self.find(id)
        query = Photo.mongo_client.database.fs.find(id_criteria(id)).first
        
        unless query.nil?
            Photo.new(query)
        else
            return nil
        end 
    end

    def contents
        unless @id.nil?
            query = self.class.mongo_client.database.fs.find_one(self.class.id_criteria(@id))
            
            if query
                buffer = ""
                query.chunks.reduce([]) do |x, chunk|
                    buffer << chunk.data.data
                end
                return buffer
            end
        end
    end

    def destroy
        self.class.mongo_client.database.fs.find(self.class.id_criteria(@id)).delete_one
    end

    def find_nearest_place_id(max_meters)
        location = self.class.find(@id).location
        query = Place.near(location, max_meters).limit(1).projection(:_id => true).first[:_id]

        query.nil? ? nil : query
    end

    def place #getter
        @place.nil? ? nil : Place.find(@place)
    end

    def place=(place) #setter
        case 
        when place.is_a?(Place)
            @place = BSON::ObjectId.from_string(place.id)
        when place.is_a?(String)
            @place = BSON::ObjectId.from_string(place) 
        when place.is_a?(BSON::ObjectId)
            @place = place
        else
            @place = nil
        end
    end

    def self.find_photos_for_place(place_id)
        case 
        when place_id.is_a?(BSON::ObjectId)
            query = Photo.mongo_client.database.fs.find('metadata.place' => place_id)
        when place_id.is_a?(String)
            query = Photo.mongo_client.database.fs.find('metadata.place' => BSON::ObjectId.from_string(place_id))
        else
            query = nil
        end
        return query
    end

end
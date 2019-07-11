class Point
    attr_accessor :longitude, :latitude

    def initialize(params)
        unless params.nil? 
            @longitude = params[:coordinates].nil? ? params[:lng] : params[:coordinates][0]
            @latitude = params[:coordinates].nil? ? params[:lat] : params[:coordinates][1]
        end 
    end

    def to_hash
        {"type": "Point", "coordinates":[@longitude, @latitude]}
    end

    
end
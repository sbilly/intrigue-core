module Intrigue
module Entity
class Screenshot < Intrigue::Model::Entity

  def metadata
    {
      :description => "TODO"
    }
  end


  def validate
    @name =~ /^.*$/ # XXX - too loose
    #@details[:file] =~ /^.*$/ # XXX - too loose
  end

end
end
end

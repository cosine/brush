spec = Gem::Specification.new do |s|
  s.name = "rubish"
  s.version = "0.0.1"
  s.author = "Michael H Buselli"
  s.email = ["cosine@cosine.org", "michael@buselli.com"]
  #s.files = Dir["bin/*"] + Dir["lib/**/*"]
  s.files = ["bin/rubish", "lib/rubish.rb"]
  s.require_path = "lib"
  s.has_rdoc = true
  s.rubyforge_project = "rubish"
  s.homepage = "http://cosine.org/ruby/rubish/"

  s.summary = "An interactive shell with the power of Ruby"

  s.description = <<-__EOF__
    Rubish is intented to be an interactive shell with the power of Ruby.
    As it is in its infancy, it is very basic and much of the functionality
    is implemented by scaffolding that will later be replaced.  For
    instance, presently commands are passed off to another shell for
    execution, but eventually all globbing, pipe setup, forking, and execing
    will be handled directly by Rubish.
  __EOF__
end

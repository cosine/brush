spec = Gem::Specification.new do |s|
  s.name = "brush"
  s.version = "0.0.2"
  s.author = "Michael H Buselli"
  s.email = ["cosine@cosine.org", "michael@buselli.com"]
  #s.files = ["LICENSE"] + Dir["bin/*"] + Dir["lib/**/*"]
  s.files = ["LICENSE", "bin/brush", "lib/brush.rb", "lib/brush/pipeline.rb"]
  s.require_path = "lib"
  s.has_rdoc = true
  s.rubyforge_project = "brush"
  s.homepage = "http://cosine.org/ruby/brush/"

  s.summary = "Brush — the Bourne RUby SHell"

  s.description = <<-__EOF__
    Brush is intended to be an interactive shell with the power of
    Ruby.  As it is in its infancy, it is very basic and much of the
    functionality is implemented by scaffolding that will later be
    replaced.  For instance, presently commands are passed off to
    another shell for execution, but eventually all globing, pipe
    setup, forking, and execing will be handled directly by Brush.
  __EOF__
end


module SmallCage::Commands
  class Update
    include SmallCage

    def self.execute(opts)
      self.new(opts).execute
    end
    
    def initialize(opts)
      @opts = opts
    end
    
    def execute
      start = Time.now
      target = Pathname.new(@opts[:path])
      unless target.exist?
        raise "target directory or file does not exist.: " + target.to_s
      end
      
      @loader   = Loader.new(target)
      @renderer = Renderer.new(@loader)
      @list     = UpdateList.create(@loader.root, target)
      render_smc_files
      expire_old_files @list.expire
      @list.save

      count = @list.update_count
      elapsed  = Time.now - start
      puts "-- #{count} files.  #{"%.3f" % elapsed} sec." +
        "  #{"%.3f" % (count == 0 ? 0 : elapsed/count)} sec/file." unless @opts[:quiet]
    end

    def expire_old_files(uris)
      root = @loader.root
      uris.each do |uri|
        file = root + uri[1..-1]
        if file.exist?
          puts "D #{uri}" unless @opts[:quiet]
          file.delete
        end
      end
    end
    private :expire_old_files

    def render_smc_files
      @loader.each_smc_obj do |obj|
        render_smc_obj(obj)
      end
    end
    private :render_smc_files

    def render_smc_obj(obj)
      uris = @renderer.render(obj["template"] + ".uri", obj)
      if uris
        render_multi(obj, uris.split(/\r\n|\r|\n/))
      else
        render_single(obj)
      end
    end
    private :render_smc_obj

    def render_single(obj, mtime = nil)
      mark   = obj["path"].exist? ? "U " : "A "
      mtime  ||= obj["path"].smc.stat.mtime.to_i
      result = @renderer.render(obj["template"], obj)
      result = after_rendering_filters(obj, result)
      output_result(obj, result)
      puts mark + obj["uri"] unless @opts[:quiet]

      # create new uri String to remove smc instance-specific method.
      @list.update(obj["uri"].smc, mtime, String.new(obj["uri"]))
    end
    private :render_single

    def render_multi(obj, uris)
      obj['uris'] ||= uris
      uris    = uris.map {|uri| uri.strip }
      smcuri  = obj['uri'].smc
      smcpath = obj['path'].smc
      base    = obj['path'].parent
      mtime   = smcpath.stat.mtime.to_i
      uris.each_with_index do |uri, index|
        next if uri.empty?
        docpath       = DocumentPath.create_with_uri(@loader.root, uri, base)
        next if docpath.path.directory?
        FileUtils.mkpath(docpath.path.parent)
        obj['uri']    = DocumentPath.add_smc_method(docpath.uri, smcuri)
        obj['path']   = DocumentPath.add_smc_method(docpath.path, smcpath)
        obj['cursor'] = index
        render_single(obj, mtime)
      end
    end
    private :render_multi
    
    def after_rendering_filters(obj, result)
      filters = @loader.filters("after_rendering_filters")
      filters.each do |f|
        result = f.after_rendering_filter(obj, result)
      end
      return result
    end
    private :after_rendering_filters

    def output_result(obj, str)
      open(obj["path"], "w") do |io|
        io << str
      end
    end
    private :output_result

  end
end

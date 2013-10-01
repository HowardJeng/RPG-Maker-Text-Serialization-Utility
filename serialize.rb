=begin
Copyright (c) 2013 Howard Jeng

Permission is hereby granted, free of charge, to any person obtaining a copy of this 
software and associated documentation files (the "Software"), to deal in the Software 
without restriction, including without limitation the rights to use, copy, modify, merge, 
publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons
to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or 
substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, 
INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR 
PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE 
FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR 
OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER 
DEALINGS IN THE SOFTWARE.
=end

require_relative './RGSS'
require_relative './psych_mods'

require 'fileutils'
require 'zlib'

module RGSS
  def self.change_extension(file, new_ext)
    return File.basename(file, '.*') + new_ext
  end

  def self.sanitize_filename(filename)
    return filename.gsub(/[^0-9A-Za-z]+/, '_')
  end

  def self.files_with_extension(directory, extension)
    return Dir.entries(directory).select{|file| File.extname(file) == extension}
  end
  
  def self.inflate(str)
    text = Zlib::Inflate.inflate(str)
    return text.force_encoding("UTF-8")
  end

  def self.deflate(str)
    return Zlib::Deflate.deflate(str, Zlib::BEST_COMPRESSION)
  end
  
  
  def self.dump_data_file(file, data, time, options)
    File.open(file, "wb") do |f|
      Marshal.dump(data, f)
    end
    File.utime(time, time, file)
  end

  def self.dump_yaml_file(file, data, time, options)
    File.open(file, "wb") do |f|
      Psych::dump(data, f, options)
    end
    File.utime(time, time, file)
  end
  
  def self.dump_save(file, data, time, options)
    File.open(file, "wb") do |f|
      data.each do |chunk|
        Marshal.dump(chunk, f)
      end
    end
    File.utime(time, time, file)
  end
  
  def self.dump_raw_file(file, data, time, options)
    File.open(file, "wb") do |f|
      f.write(data)
    end
    File.utime(time, time, file)
  end
  
  def self.dump(dumper, file, data, time, options)
    self.method(dumper).call(file, data, time, options)
  rescue
    warn "Exception dumping #{file}"
    raise
  end
  

  def self.load_data_file(file)
    File.open(file, "rb") do |f|
      return Marshal.load(f)
    end
  end

  def self.load_yaml_file(file)
    File.open(file, "rb") do |f|
      return Psych::load(f)
    end
  end
  
  def self.load_raw_file(file)
    File.open(file, "rb") do |f|
      return f.read
    end
  end
  
  def self.load_save(file)
    File.open(file, "rb") do |f|
      data = []
      while not f.eof?
        o = Marshal.load(f)
        data.push(o)
      end
      return data
    end
  end
  
  def self.load(loader, file)
    return self.method(loader).call(file)
  rescue
    warn "Exception loading #{file}"
    raise
  end
  

  def self.scripts_to_text(dirs, src, dest, options)
     src_file = File.join(dirs[:data], src)
    dest_file = File.join(dirs[:yaml], dest)
    raise "Missing #{src}" unless File.exists?(src_file)
    
    script_entries = load(:load_data_file, src_file)
    check_time = !options[:force] && File.exists?(dest_file)
    oldest_time = File.mtime(dest_file) if check_time
    
    file_map, script_index, script_code = Hash.new(-1), [], {}
    script_entries.each do |script|
      magic_number, script_name, code = script[0], script[1], inflate(script[2])
      script_name.force_encoding("UTF-8")
      
      if code.length > 0 
        filename = script_name.empty? ? 'blank' : sanitize_filename(script_name)
        key = filename.upcase
        value = (file_map[key] += 1)
        actual_filename = filename + (value == 0 ? "" : ".#{value}") + RUBY_EXT
        script_index.push([magic_number, script_name, actual_filename])
        full_filename = File.join(dirs[:script], actual_filename)
        script_code[full_filename] = code
        check_time = false unless File.exists?(full_filename)
        oldest_time = [File.mtime(full_filename), oldest_time].min if check_time
      else
        script_index.push([magic_number, script_name, nil])
      end 
    end

    src_time = File.mtime(src_file)
    if check_time && (src_time - 1) < oldest_time
      puts "Skipping scripts to text" if $VERBOSE
    else
      puts "Converting scripts to text" if $VERBOSE
      dump(:dump_yaml_file, dest_file, script_index, src_time, options)
      script_code.each {|file, code| dump(:dump_raw_file, file, code, src_time, options)}
    end
  end

  def self.scripts_to_binary(dirs, src, dest, options)
     src_file = File.join(dirs[:yaml], src)
    dest_file = File.join(dirs[:data], dest)
    raise "Missing #{src}" unless File.exists?(src_file)
    check_time = !options[:force] && File.exists?(dest_file)
    newest_time = File.mtime(src_file) if check_time
    
    index = load(:load_yaml_file, src_file)
    script_entries = []
    index.each do |entry|
      magic_number, script_name, filename = entry
      code = ''
      if filename
        full_filename = File.join(dirs[:script], filename)
        raise "Missing script file #{filename}" unless File.exists?(full_filename)
        newest_time = [File.mtime(full_filename), newest_time].max if check_time
        code = load(:load_raw_file, full_filename)
      end
      script_entries.push([magic_number, script_name, deflate(code)])
    end
    if check_time && (newest_time - 1) < File.mtime(dest_file)
      puts "Skipping scripts to binary" if $VERBOSE
    else 
      puts "Converting scripts to binary" if $VERBOSE
      dump(:dump_data_file, dest_file, script_entries, newest_time, options)
    end
  end
  
  def self.process_file(file, src_file, dest_file, dest_ext, loader, dumper, options)
    src_time = File.mtime(src_file)
    if !options[:force] && File.exists?(dest_file) && (src_time - 1) < File.mtime(dest_file)
      puts "Skipping #{file}" if $VERBOSE
    else
      puts "Converting #{file} to #{dest_ext}" if $VERBOSE
      data = load(loader, src_file)
      dump(dumper, dest_file, data, src_time, options)
    end
  end
  
  def self.convert(src, dest, options)
    files = files_with_extension(src[:directory], src[:ext])
    files -= src[:exclude]

    files.each do |file|
       src_file = File.join(src[:directory], file)
      dest_file = File.join(dest[:directory], change_extension(file, dest[:ext]))
      
      process_file(file, src_file, dest_file, dest[:ext], src[:load_file],
                   dest[:dump_file], options)
    end
  end
  
  def self.convert_saves(base, src, dest, options)
    save_files = files_with_extension(base, src[:ext])
    save_files.each do |file|
       src_file = File.join(base, file)
      dest_file = File.join(base, change_extension(file, dest[:ext]))
      
      process_file(file, src_file, dest_file, dest[:ext], src[:load_save], 
                   dest[:dump_save], options)
    end
  end

  # [version] one of :ace, :vx, :xp
  # [direction] one of :data_bin_to_text, :data_text_to_bin, :save_bin_to_text,
  #             :save_text_to_bin, :scripts_bin_to_text, :scripts_text_to_bin, 
  #             :all_text_to_bin, :all_bin_to_text
  # [directory] directory that project file is in
  # [options] :force - ignores file dates when converting (default false)
  #           :round_trip - create yaml data that matches original marshalled data skips 
  #                         data cleanup operations (default false)
  #           :line_width - line width form YAML files, -1 for no line width limit
  #                         (default 130)
  #           :table_width - maximum number of entries per row for table data, -1 for no
  #                          table row limit (default 20)
  def self.serialize(version, direction, directory, options = {})
    raise "#{directory} not found" unless File.exist?(directory)

    setup_classes(version, options)
    options = options.clone()
    options[:sort] = true if [:vx, :xp].include?(version)
    options[:flow_classes] = FLOW_CLASSES
    options[:line_width] ||= 130
    
    table_width = options[:table_width]
    reset_const(Table, :MAX_ROW_LENGTH, table_width ? table_width : 20)

    base = File.realpath(directory)

    dirs = {
      :base   => base,
      :data   => get_data_directory(base),
      :yaml   => get_yaml_directory(base),
      :script => get_script_directory(base)
    }
    
    dirs.values.each do |d|
      FileUtils.mkdir(d) unless File.exists?(d)
    end
    
    exts = {
      :ace => ACE_DATA_EXT,
      :vx  => VX_DATA_EXT,
      :xp  => XP_DATA_EXT
    }
    
    yaml_scripts = SCRIPTS_BASE + YAML_EXT
    yaml = {
      :directory => dirs[:yaml],
      :exclude   => [yaml_scripts],
      :ext       => YAML_EXT,
      :load_file => :load_yaml_file,
      :dump_file => :dump_yaml_file,
      :load_save => :load_yaml_file,
      :dump_save => :dump_yaml_file
    }
    
    scripts = SCRIPTS_BASE + exts[version]
    data = {
      :directory => dirs[:data],
      :exclude   => [scripts],
      :ext       => exts[version],
      :load_file => :load_data_file,
      :dump_file => :dump_data_file,
      :load_save => :load_save,
      :dump_save => :dump_save
    }

    case direction
    when :data_bin_to_text
      convert(data, yaml, options)
      scripts_to_text(dirs, scripts, yaml_scripts, options)
    when :data_text_to_bin
      convert(yaml, data, options)
      scripts_to_binary(dirs, yaml_scripts, scripts, options)
    when :save_bin_to_text
      convert_saves(base, data, yaml, options)
    when :save_text_to_bin
      convert_saves(base, yaml, data, options)
    when :scripts_bin_to_text
      scripts_to_text(dirs, scripts, yaml_scripts, options)
    when :scripts_text_to_bin
      scripts_to_binary(dirs, yaml_scripts, scripts, options)
    when :all_bin_to_text
      convert(data, yaml, options)
      scripts_to_text(dirs, scripts, yaml_scripts, options)
      convert_saves(base, data, yaml, options)
    when :all_text_to_bin
      convert(yaml, data, options)
      scripts_to_binary(dirs, yaml_scripts, scripts, options)
      convert_saves(base, yaml, data, options)
    else
      raise "Unrecognized direction :#{direction}"
    end
  end
end

if __FILE__ == $0
  require 'optparse'
  options = {}
  ver = :ace
  directions = []
  path = nil
  
  valid_directions = [:data_bin_to_text,
                      :data_text_to_bin,
                      :save_bin_to_text,
                      :save_text_to_bin,
                      :scripts_bin_to_text,
                      :scripts_text_to_bin,
                      :all_bin_to_text,
                      :all_text_to_bin]

  directions_str = valid_directions.collect do |dir|
    dir.to_s
  end.join(', ')

  OptionParser.new do |opts|
    opts.banner = 
<<HERE
Usage: serialize.rb [options] directions* directory
The directions can be one or more of #{directions_str}

Other options are:
HERE
    opts.on('-x', '--xp', "Directory is an RPG Maker XP project") do
      ver = :xp
    end
    
    opts.on('-v', '--vx', "Directory is an RPG Maker VX project") do
      ver = :vx
    end
    
    opts.on('-a', '--ace', "Directory is an RPG Maker VX Ace project") do
      ver = :ace
    end
    
    opts.on('-l', '--line-width WIDTH', "Line width for YAML output") do |width|
      options[:line_width] = width
    end
    
    opts.on('-t', '--table-width WIDTH', "Table width for YAML output") do |width|
      options[:table_width] = width
    end
    
    opts.on('-f', '--[no-]force', "Force conversion and ignore file times") do |f|
      options[:force] = f
    end
    
    opts.on_tail('-h', '--help', "Show this message") do
      puts opts
      exit
    end
  end.parse!  

  ARGV.each do |arg|
    sym = arg.to_sym
    if valid_directions.include?(sym)
      directions.push(sym)
    else
      if (path)
        puts "Error: Multiple directories entered. '#{path}' and '#{arg}'"
        exit
      end
      path = arg
    end
  end
  
  if directions.empty?
    puts "Error: Must enter a valid direction. Possible choices are #{directions_str}"
  else
    directions.each do |dir|
      RGSS.serialize(ver, dir, path, options)
    end
  end
end
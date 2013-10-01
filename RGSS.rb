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

require 'scanf'

class Table
  def initialize(bytes)
    @dim, @x, @y, @z, items, *@data = bytes.unpack('L5 S*')
    raise "Size mismatch loading Table from data" unless items == @data.length
    raise "Size mismatch loading Table from data" unless @x * @y * @z == items
  end
  
  MAX_ROW_LENGTH = 20
  
  def encode_with(coder)
    coder.style = Psych::Nodes::Mapping::BLOCK
    
    coder['dim'] = @dim
    coder['x'] = @x
    coder['y'] = @y
    coder['z'] = @z
    
    if @x * @y * @z > 0
      stride = @x < 2 ? (@y < 2 ? @z : @y) : @x
      rows = @data.each_slice(stride).to_a
      if MAX_ROW_LENGTH != -1 && stride > MAX_ROW_LENGTH
        block_length = (stride + MAX_ROW_LENGTH - 1) / MAX_ROW_LENGTH
        row_length = (stride + block_length - 1) / block_length
        rows = rows.collect{|x| x.each_slice(row_length).to_a}.flatten(1)
      end
      rows = rows.collect{|x| x.collect{|y| "%04x" % y}.join(" ")}
      coder['data'] = rows
    else
      coder['data'] = []
    end
  end
  
  def init_with(coder)
    @dim = coder['dim']
    @x = coder['x']
    @y = coder['y']
    @z = coder['z']
    @data = coder['data'].collect{|x| x.split(" ").collect{|y| y.hex}}.flatten
    items = @x * @y * @z
    raise "Size mismatch loading Table from YAML" unless items == @data.length
  end
  
  def _dump(*ignored)
    return [@dim, @x, @y, @z, @x * @y * @z, *@data].pack('L5 S*')
  end
  
  def self._load(bytes)
    Table.new(bytes)
  end
end

class Color
  def initialize(bytes)
    @r, @g, @b, @a = *bytes.unpack('D4')
  end

  def _dump(*ignored)
    return [@r, @g, @b, @a].pack('D4')
  end
  
  def self._load(bytes)
    Color.new(bytes)
  end
end

class Tone
  def initialize(bytes)
    @r, @g, @b, @a = *bytes.unpack('D4')
  end

  def _dump(*ignored)
    return [@r, @g, @b, @a].pack('D4')
  end
  
  def self._load(bytes)
    Tone.new(bytes)
  end
end

class Rect
  def initialize(bytes) 
    @x, @y, @width, @height = *bytes.unpack('i4')
  end
  
  def _dump(*ignored)
    return [@x, @y, @width, @height].pack('i4')
  end
  
  def self._load(bytes)
    Rect.new(bytes)
  end
end

def remove_defined_method(scope, name)
  scope.send(:remove_method, name) if scope.instance_methods(false).include?(name)
end

def reset_method(scope, name, method)
  remove_defined_method(scope, name)
  scope.send(:define_method, name, method)
end

def reset_const(scope, sym, value)
  scope.send(:remove_const, sym) if scope.const_defined?(sym)
  scope.send(:const_set, sym, value)
end

def array_to_hash(arr, &block)
  h = {}
  arr.each_with_index do |val, index|
    r = block_given? ? block.call(val) : val
    h[index] = r unless r.nil?
  end
  if arr.length > 0
    last = arr.length - 1
    h[last] = nil unless h.has_key?(last)
  end
  return h
end    

def hash_to_array(hash)
  arr = []
  hash.each do |k, v|
    arr[k] = v
  end
  return arr
end

module BasicCoder
  def encode_with(coder)
    ivars.each do |var|
      name = var.to_s.sub(/^@/, '')
      value = instance_variable_get(var)
      coder[name] = encode(name, value)
    end
  end
  
  def encode(name, value)
    return value
  end
    
  def init_with(coder)
    coder.map.each do |key, value|
      sym = "@#{key}".to_sym
      instance_variable_set(sym, decode(key, value))
    end
  end
  
  def decode(name, value)
    return value
  end
  
  def ivars
    return instance_variables
  end
  
  INCLUDED_CLASSES = []
  def self.included(mod)
    INCLUDED_CLASSES.push(mod)
  end
  
  def self.set_ivars_methods(version)
    INCLUDED_CLASSES.each do |c|
      if version == :ace
        reset_method(c, :ivars, ->{
          return instance_variables
        })
      else
        reset_method(c, :ivars, ->{
          return instance_variables.sort
        })
      end
    end
  end
end

class Game_Switches
  include BasicCoder
  
  def encode(name, value)
    return array_to_hash(value)
  end
  
  def decode(name, value)
    return hash_to_array(value)
  end
end

class Game_Variables
  include BasicCoder
  
  def encode(name, value)
    return array_to_hash(value)
  end
  
  def decode(name, value)
    return hash_to_array(value)
  end
end

class Game_SelfSwitches
  include BasicCoder
  
  def encode(name, value)
    return Hash[value.collect {|pair|
      key, value = pair
      next ["%03d %03d %s" % key, value]
    }.sort]
  end
  
  def decode(name, value)
    return Hash[value.collect {|pair|
      key, value = pair
      next [key.scanf("%d %d %s"), value]
    }]
  end
end

class Game_System
  include BasicCoder
  
  def encode(name, value)
    if name == 'version_id'
      return map_version(value)
    else
      return value
    end
  end
end

module RPG
  class System
    include BasicCoder
    HASHED_VARS = ['variables', 'switches']
    
    def encode(name, value)
      if HASHED_VARS.include?(name)
        return array_to_hash(value) {|val| reduce_string(val)}
      elsif name == 'version_id'
        return map_version(value)
      else
        return value
      end
    end
    
    def decode(name, value)
      if HASHED_VARS.include?(name)
        return hash_to_array(value)
      else
        return value
      end
    end
  end
  
  class EventCommand
    def encode_with(coder)
      raise 'Unexpected number of instance variables' if instance_variables.length != 3
      clean
      
      case @code
      when MOVE_LIST_CODE # move list
        coder.style = Psych::Nodes::Mapping::BLOCK
      else
        coder.style = Psych::Nodes::Mapping::FLOW
      end
      coder['i'], coder['c'], coder['p'] = @indent, @code, @parameters
    end
    
    def init_with(coder)
      @indent, @code, @parameters = coder['i'], coder['c'], coder['p']
    end
  end
end

module RGSS
  # creates an empty class in a potentially nested scope
  def self.process(root, name, *args)
    if args.length > 0
      process(root.const_get(name), *args)
    else
      root.const_set(name, Class.new) unless root.const_defined?(name, false)
    end
  end
  
  # other classes that don't need definitions
  [ # RGSS data structures
    [:RPG, :Actor], [:RPG, :Animation], [:RPG, :Animation, :Frame], 
    [:RPG, :Animation, :Timing], [:RPG, :Area], [:RPG, :Armor], [:RPG, :AudioFile], 
    [:RPG, :BaseItem], [:RPG, :BaseItem, :Feature], [:RPG, :BGM], [:RPG, :BGS], 
    [:RPG, :Class], [:RPG, :Class, :Learning], [:RPG, :CommonEvent], [:RPG, :Enemy], 
    [:RPG, :Enemy, :Action], [:RPG, :Enemy, :DropItem], [:RPG, :EquipItem], 
    [:RPG, :Event], [:RPG, :Event, :Page], [:RPG, :Event, :Page, :Condition], 
    [:RPG, :Event, :Page, :Graphic], [:RPG, :Item], [:RPG, :Map], 
    [:RPG, :Map, :Encounter], [:RPG, :MapInfo], [:RPG, :ME], [:RPG, :MoveCommand], 
    [:RPG, :MoveRoute], [:RPG, :SE], [:RPG, :Skill], [:RPG, :State], 
    [:RPG, :System, :Terms], [:RPG, :System, :TestBattler], [:RPG, :System, :Vehicle], 
    [:RPG, :System, :Words], [:RPG, :Tileset], [:RPG, :Troop], [:RPG, :Troop, :Member], 
    [:RPG, :Troop, :Page], [:RPG, :Troop, :Page, :Condition], [:RPG, :UsableItem], 
    [:RPG, :UsableItem, :Damage], [:RPG, :UsableItem, :Effect], [:RPG, :Weapon],
    # Script classes serialized in save game files
    [:Game_ActionResult], [:Game_Actor], [:Game_Actors], [:Game_BaseItem], 
    [:Game_BattleAction], [:Game_CommonEvent], [:Game_Enemy], [:Game_Event], 
    [:Game_Follower], [:Game_Followers], [:Game_Interpreter], [:Game_Map], 
    [:Game_Message], [:Game_Party], [:Game_Picture], [:Game_Pictures], [:Game_Player], 
    [:Game_System], [:Game_Timer], [:Game_Troop], [:Game_Screen], [:Game_Vehicle], 
    [:Interpreter]
  ].each {|x| process(Object, *x)}
    
  def self.setup_system(version, options)
    # convert variable and switch name arrays to a hash when serialized
    # if round_trip isn't set change version_id to fixed number
    if options[:round_trip]
      iso = ->(val) { return val }
      reset_method(RPG::System, :reduce_string, iso)
      reset_method(RPG::System, :map_version, iso)
      reset_method(Game_System, :map_version, iso)
    else
      reset_method(RPG::System, :reduce_string, ->(str) {
        return nil if str.nil?
        stripped = str.strip
        return stripped.empty? ? nil : stripped
      })
      # These magic numbers should be different. If they are the same, the saved version 
      # of the map in save files will be used instead of any updated version of the map
      reset_method(RPG::System, :map_version, ->(ignored) { return 12345678 })
      reset_method(Game_System, :map_version, ->(ignored) { return 87654321 })
    end
  end
  
  def self.setup_interpreter(version)
    # Game_Interpreter is marshalled differently in VX Ace
    if version == :ace
      reset_method(Game_Interpreter, :marshal_dump, ->{
        return @data
      })
      reset_method(Game_Interpreter, :marshal_load, ->(obj) {
        @data = obj
      })
    else
      remove_defined_method(Game_Interpreter, :marshal_dump)
      remove_defined_method(Game_Interpreter, :marshal_load)
    end
  end

  def self.setup_event_command(version, options)
    # format event commands to flow style for the event codes that aren't move commands
    if options[:round_trip]
      reset_method(RPG::EventCommand, :clean, ->{})
    else
      reset_method(RPG::EventCommand, :clean, ->{
        @parameters[0].rstrip! if @code == 401
      })
    end
    reset_const(RPG::EventCommand, :MOVE_LIST_CODE, version == :xp ? 209 : 205)
  end

  def self.setup_classes(version, options)
    setup_system(version, options)
    setup_interpreter(version)
    setup_event_command(version, options)
    BasicCoder.set_ivars_methods(version)
  end
  
  FLOW_CLASSES = [Color, Tone, RPG::BGM, RPG::BGS, RPG::MoveCommand, RPG::SE]
  
  SCRIPTS_BASE = 'Scripts'
  
  ACE_DATA_EXT = '.rvdata2'
  VX_DATA_EXT  = '.rvdata'
  XP_DATA_EXT  = '.rxdata'
  YAML_EXT     = '.yaml'
  RUBY_EXT     = '.rb'
  
  def self.get_data_directory(base)
    return File.join(base, 'Data')
  end
  
  def self.get_yaml_directory(base)
    return File.join(base, 'YAML')
  end
  
  def self.get_script_directory(base)
    return File.join(base, 'Scripts')
  end
end

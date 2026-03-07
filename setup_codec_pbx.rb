require 'xcodeproj'
require 'fileutils'

project_path = '/Users/boradev/Desktop/comet/cometeditor/cometeditor.xcodeproj'
project = Xcodeproj::Project.open(project_path)
target = project.targets.find { |t| t.name == 'cometeditor' }

# 1. Add Bridging Header and source files
main_group = project.main_group.groups.find { |g| g.name == 'cometeditor' } || project.main_group

bridge_file = main_group.files.find { |f| f.path == 'cometeditor-Bridging-Header.h' } || main_group.new_file('cometeditor-Bridging-Header.h')
swift_file = main_group.files.find { |f| f.path == 'CometImageCodec.swift' } || main_group.new_file('CometImageCodec.swift')

unless target.source_build_phase.files_references.include?(swift_file)
  target.source_build_phase.add_file_reference(swift_file)
end

# 2. Configure SWIFT_OBJC_BRIDGING_HEADER
target.build_configurations.each do |config|
  config.build_settings['SWIFT_OBJC_BRIDGING_HEADER'] = 'cometeditor/cometeditor-Bridging-Header.h'
  
  # Search paths for third_party libraries and CometImageCodec C headers
  header_paths = config.build_settings['HEADER_SEARCH_PATHS'] || ['$(inherited)']
  header_paths << '"$(SRCROOT)/CometImageCodec/Core"' unless header_paths.include?('"$(SRCROOT)/CometImageCodec/Core"')
  header_paths << '"$(SRCROOT)/third_party/install/include"' unless header_paths.include?('"$(SRCROOT)/third_party/install/include"')
  config.build_settings['HEADER_SEARCH_PATHS'] = header_paths

  lib_paths = config.build_settings['LIBRARY_SEARCH_PATHS'] || ['$(inherited)']
  lib_paths << '"$(SRCROOT)/third_party/install/lib"' unless lib_paths.include?('"$(SRCROOT)/third_party/install/lib"')
  config.build_settings['LIBRARY_SEARCH_PATHS'] = lib_paths
end

# 3. Add CometImageCodec C Core to compile sources
core_group = project.main_group.groups.find { |g| g.name == 'CometImageCodec' }
unless core_group
  core_group = project.main_group.new_group('CometImageCodec', 'CometImageCodec')
end
inner_core = core_group.groups.find { |g| g.name == 'Core' } || core_group.new_group('Core', 'Core')

Dir.glob('/Users/boradev/Desktop/comet/cometeditor/CometImageCodec/Core/*.{c,h}').each do |file|
  base_name = File.basename(file)
  ref = inner_core.files.find { |f| f.path == base_name }
  unless ref
    ref = inner_core.new_file(base_name)
  end
  # Add to compile phase if it's a .c file and not already there
  if file.end_with?('.c') && !target.source_build_phase.files_references.include?(ref)
    target.source_build_phase.add_file_reference(ref)
  end
end

# 4. Link Static Libraries (libwebp.a, libavif.a)
# We will link standard macOS static libraries if they exist, but for our build script output:
['libavif.a', 'libwebp.a', 'libwebpmux.a', 'libwebpdemux.a', 'libsharpyuv.a'].each do |lib_name|
  # We just add a custom link flag or create a file reference. 
  # A simple way is to add to OTHER_LDFLAGS:
  target.build_configurations.each do |config|
    ldflags = config.build_settings['OTHER_LDFLAGS'] || ['$(inherited)']
    # Add flag if missing. Format is -l<name> without lib and .a
    flag = "-l#{lib_name.sub(/^lib/, '').sub(/\.a$/, '')}"
    ldflags << flag unless ldflags.include?(flag)
    config.build_settings['OTHER_LDFLAGS'] = ldflags
  end
end

project.save
puts "Successfully configured Xcode project for CometImageCodec C integration."

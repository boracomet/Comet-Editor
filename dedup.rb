require 'xcodeproj'

project_path = '/Users/boradev/Desktop/comet/cometeditor/cometeditor.xcodeproj'
project = Xcodeproj::Project.open(project_path)
target = project.targets.first

# Remove duplicates from source phase
sources = target.source_build_phase.files
seen = {}

sources.each do |file|
  path = file.file_ref.path
  if seen[path]
    puts "Removing duplicate: #{path}"
    file.remove_from_project
  else
    seen[path] = true
  end
end

project.save
puts "Deduplication complete."

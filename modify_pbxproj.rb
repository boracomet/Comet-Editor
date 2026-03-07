require 'xcodeproj'

project_path = '/Users/boradev/Desktop/comet/cometeditor/cometeditor.xcodeproj'
project = Xcodeproj::Project.open(project_path)
target = project.targets.first

def find_file_recursive(group, path)
  found = group.files.find { |f| f.path == path || f.name == path }
  return found if found
  
  group.groups.each do |g|
    res = find_file_recursive(g, path)
    return res if res
  end
  nil
end

xcstrings = find_file_recursive(project.main_group, 'Localizable.xcstrings')
group = xcstrings ? xcstrings.parent : (project.main_group.groups.find { |g| g.path == 'cometeditor' || g.name == 'cometeditor' } || project.main_group)

if xcstrings
  target.build_phases.each do |phase|
    if phase.respond_to?(:remove_file_reference)
      phase.remove_file_reference(xcstrings)
    end
  end
  xcstrings.remove_from_project
end

variant_group = group.children.find { |c| c.name == 'Localizable.strings' && c.class == Xcodeproj::Project::Object::PBXVariantGroup }
unless variant_group
  variant_group = group.new_variant_group('Localizable.strings')
end

en_file = variant_group.files.find { |f| f.name == 'en' }
unless en_file
  en_file = variant_group.new_reference('en.lproj/Localizable.strings')
  en_file.name = 'en'
end

tr_file = variant_group.files.find { |f| f.name == 'tr' }
unless tr_file
  tr_file = variant_group.new_reference('tr.lproj/Localizable.strings')
  tr_file.name = 'tr'
end

resources_phase = target.resources_build_phase
unless resources_phase.files_references.include?(variant_group)
  resources_phase.add_file_reference(variant_group, true)
end

project.save
puts "Successfully modified Xcode project."

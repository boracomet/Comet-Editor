require 'xcodeproj'

project_path = '/Users/boradev/Desktop/comet/cometeditor/cometeditor.xcodeproj'
project = Xcodeproj::Project.open(project_path)
target = project.targets.find { |t| t.name == 'cometeditor' }

# Check if SDWebImageWebPCoder already exists
existing_package = project.root_object.package_references.find { |p| p.repositoryURL.include?('SDWebImageWebPCoder') }
unless existing_package
  # Add the package reference
  package_ref = project.new(Xcodeproj::Project::Object::XCRemoteSwiftPackageReference)
  package_ref.repositoryURL = "https://github.com/SDWebImage/SDWebImageWebPCoder.git"
  package_ref.requirement = {
    "kind" => "upToNextMajorVersion",
    "minimumVersion" => "0.14.6"
  }
  project.root_object.package_references << package_ref

  # Add the product dependency
  product_dep = project.new(Xcodeproj::Project::Object::XCSwiftPackageProductDependency)
  product_dep.package = package_ref
  product_dep.product_name = "SDWebImageWebPCoder"

  # Add it to the target's dependencies
  build_dependency = project.new(Xcodeproj::Project::Object::PBXTargetDependency)
  build_dependency.product_ref = product_dep
  target.dependencies << build_dependency

  # Add it to the Frameworks build phase
  frameworks_phase = target.frameworks_build_phase
  build_file = project.new(Xcodeproj::Project::Object::PBXBuildFile)
  build_file.product_ref = product_dep
  frameworks_phase.files << build_file

  project.save
  puts "SDWebImageWebPCoder added successfully to xcodeproj."
else
  puts "SDWebImageWebPCoder package already exists in project."
end

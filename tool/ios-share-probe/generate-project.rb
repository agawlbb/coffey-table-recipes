require 'xcodeproj'
require 'fileutils'

root = File.expand_path('../..', __dir__)
directory = File.join(root, 'build', 'ios-share-probe')
FileUtils.mkdir_p(directory)
project = Xcodeproj::Project.new(File.join(directory, 'ShareProbe.xcodeproj'))
app = project.new_target(:application, 'ShareProbe', :ios, '15.0')
tests = project.new_target(:ui_test_bundle, 'ShareProbeUITests', :ios, '15.0')
tests.add_dependency(app)
[[app, 'ProbeApp.swift'], [tests, 'ShareLaunchTests.swift']].each do |target, source|
  target.source_build_phase.add_file_reference(project.main_group.new_file(File.join(__dir__, source)))
  target.build_configurations.each do |configuration|
    settings = configuration.build_settings
    settings['SWIFT_VERSION'] = '5.0'
    settings['GENERATE_INFOPLIST_FILE'] = 'YES'
    settings['PRODUCT_BUNDLE_IDENTIFIER'] = "com.coffeytable.#{target.name}"
    settings['TARGETED_DEVICE_FAMILY'] = '1,2'
    settings['CODE_SIGNING_ALLOWED'] = 'NO'
    settings['MARKETING_VERSION'] = '1.0'
    settings['CURRENT_PROJECT_VERSION'] = '1'
  end
end
app.build_configurations.each do |configuration|
  configuration.build_settings['INFOPLIST_KEY_CFBundleDisplayName'] = 'Share launch probe'
  # Without a launch screen, UIKit runs the sender in legacy 320x480 compatibility mode.
  configuration.build_settings['INFOPLIST_KEY_UILaunchScreen_Generation'] = 'YES'
  configuration.build_settings['INFOPLIST_KEY_UIApplicationSceneManifest_Generation'] = 'YES'
end
tests.build_configurations.each do |configuration|
  configuration.build_settings['TEST_TARGET_NAME'] = 'ShareProbe'
end
project.save
scheme = Xcodeproj::XCScheme.new
scheme.add_build_target(app)
scheme.add_build_target(tests)
scheme.set_launch_target(app)
scheme.add_test_target(tests)
scheme.save_as(project.path, 'ShareProbe', true)
puts project.path

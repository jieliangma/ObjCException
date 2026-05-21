#!/usr/bin/env ruby
# Adds the ObjCException_Tests XCTest target to the Example project.
# Idempotent: re-running detects the existing target and exits cleanly.

require 'xcodeproj'

PROJECT_PATH = File.expand_path('../ObjCException.xcodeproj', __dir__)
TESTS_DIR    = 'Tests'
TARGET_NAME  = 'ObjCException_Tests'
HOST_TARGET  = 'ObjCException_Example'
DEPLOYMENT   = '13.0'  # XCTest.framework requires iOS 13+; library still ships 12.0.

project = Xcodeproj::Project.open(PROJECT_PATH)

host = project.targets.find { |t| t.name == HOST_TARGET }
abort "Cannot find host target #{HOST_TARGET}" unless host

test_target = project.targets.find { |t| t.name == TARGET_NAME }

if test_target
  puts "Target #{TARGET_NAME} already exists; refreshing build settings."
else
  # Tests group at project root, real on disk under Example/Tests.
  tests_group = project.main_group.find_subpath(TESTS_DIR, true)
  tests_group.set_source_tree('<group>')
  tests_group.set_path(TESTS_DIR)

  test_target = project.new_target(:unit_test_bundle, TARGET_NAME, :ios, DEPLOYMENT)

  # Source files
  source_files = %w[ObjCExceptionTests.mm ObjCExceptionSwiftTests.swift]
  source_files.each do |basename|
    ref = tests_group.new_reference(basename)
    test_target.add_file_references([ref])
  end

  test_target.add_dependency(host)
end

# Build settings — both configs (idempotent merge)
test_target.build_configurations.each do |config|
  config.build_settings.merge!(
    'IPHONEOS_DEPLOYMENT_TARGET'   => DEPLOYMENT,
    'PRODUCT_BUNDLE_IDENTIFIER'    => 'org.cocoapods.tests.ObjCException-Tests',
    'PRODUCT_NAME'                 => '$(TARGET_NAME)',
    'SWIFT_VERSION'                => '5.0',
    'CLANG_CXX_LANGUAGE_STANDARD'  => 'gnu++17',
    'CLANG_CXX_LIBRARY'            => 'libc++',
    'CLANG_ENABLE_MODULES'         => 'YES',
    'CLANG_ENABLE_OBJC_ARC'        => 'YES',
    'GCC_ENABLE_OBJC_EXCEPTIONS'   => 'YES',
    'GENERATE_INFOPLIST_FILE'      => 'YES',
    'TEST_HOST'                    => '$(BUILT_PRODUCTS_DIR)/ObjCException_Example.app/ObjCException_Example',
    'BUNDLE_LOADER'                => '$(TEST_HOST)',
    'LD_RUNPATH_SEARCH_PATHS'      => '$(inherited) @executable_path/Frameworks @loader_path/Frameworks',
    'ALWAYS_EMBED_SWIFT_STANDARD_LIBRARIES' => 'YES',
    'CODE_SIGN_STYLE'              => 'Automatic',
    'CODE_SIGNING_ALLOWED'         => 'NO',
  )
end

project.save

# The pre-existing scheme references blueprint id 6003F5AD195388D20070C39A.
# Patch the scheme to use whatever UUID xcodeproj just minted.
require 'rexml/document'

scheme_path = File.join(PROJECT_PATH, 'xcshareddata/xcschemes/ObjCException-Example.xcscheme')
doc = REXML::Document.new(File.read(scheme_path))
REXML::XPath.each(doc, '//BuildableReference[@BlueprintName="ObjCException_Tests"]') do |ref|
  ref.attributes['BlueprintIdentifier'] = test_target.uuid
end
File.write(scheme_path, doc.to_s)

puts "Added target #{TARGET_NAME} (uuid=#{test_target.uuid})."

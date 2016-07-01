#
# Be sure to run `pod lib lint FacadeSwift.podspec' to ensure this is a
# valid spec before submitting.
#
# Any lines starting with a # are optional, but their use is encouraged
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html
#

Pod::Spec.new do |s|
  s.name             = "FacadeSwift"
  s.version          = "0.0.3"
  s.summary          = "CoreData made sexy with swift"
  s.homepage         = "https://github.com/othierry/facade"
  s.license          = 'MIT'
  s.author           = { "Olivier Thierry" => "olivier.thierry42@gmail.com" }
  s.source           = { :git => "https://github.com/othierry/facade.git", :tag => s.version.to_s }

  s.platform = :ios, '9.0'
  s.requires_arc = true
  s.module_name = 'Facade'
  s.source_files = 'FacadeSwift/Classes/**/*'

  s.frameworks = [
    'CoreData'
  ]
end

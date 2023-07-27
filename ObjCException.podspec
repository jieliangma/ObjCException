Pod::Spec.new do |s|
  s.name             = 'ObjCException'
  s.version          = '0.1.0'
  s.summary          = 'A short description of ObjCException.'
  s.description      = <<-DESC
TODO: Add long description of the pod here.
                       DESC

  s.homepage         = 'https://github.com/jieliangma/ObjCException'
  s.license          = { :type => 'MIT', :file => 'LICENSE' }
  s.author           = { 'JieLiang Ma' => 'majieliang@didiglobal.com' }
  s.source           = { :git => 'https://github.com/JieLiang Ma/ObjCException.git', :tag => s.version.to_s }

  s.ios.deployment_target = '10.0'
  s.source_files = 'ObjCException/Classes/**/*.{h,hpp,m,mm}'
  s.public_header_files = 'ObjCException/Classes/ObjCException.h'
end

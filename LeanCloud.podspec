Pod::Spec.new do |s|
  s.name         = 'LeanCloud'
  s.version      = '17.0.0-beta.3'
  s.license      = { :type => 'Apache License, Version 2.0', :file => 'LICENSE' }
  s.summary      = 'LeanCloud Swift SDK'
  s.homepage     = 'https://leancloud.cn/'
  s.authors      = 'LeanCloud'
  s.source       = { :git => 'https://github.com/leancloud/swift-sdk.git', :tag => s.version }
  s.swift_version = '5.0'

  s.ios.deployment_target     = '10.0'
  s.osx.deployment_target     = '10.12'
  s.tvos.deployment_target    = '10.0'
  s.watchos.deployment_target = '3.0'

  s.subspec 'Foundation' do |ss|
    ss.dependency 'Alamofire', '5.0.0-rc.2'

    ss.source_files = 'Sources/Foundation/**/*.{swift}'
  end

  s.subspec 'RTM' do |ss|
    ss.dependency 'SwiftProtobuf', '~> 1.6.0'
    ss.dependency 'Starscream', '~> 3.1'
    ss.dependency 'GRDB.swift', '~> 4.4'

    ss.dependency 'LeanCloud/Foundation'

    ss.source_files = 'Sources/RTM/**/*.{swift}'
  end
end
